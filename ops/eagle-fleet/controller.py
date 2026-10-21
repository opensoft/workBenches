"""One-job fleet controller. Host auth never enters a job container."""
import datetime
import concurrent.futures
import json
import os
from pathlib import Path
import subprocess
import time
import uuid
import backend

ROOT=Path(__file__).resolve().parent
STATE=ROOT/'state.json'
CONFIG=ROOT/'config.json'

def event(name,**fields):
    target=ROOT/'events.jsonl'
    if target.exists() and target.stat().st_size > 2_000_000: target.replace(ROOT/'events.previous.jsonl')
    with target.open('a',encoding='utf-8') as stream:
        stream.write(json.dumps(dict(time=datetime.datetime.now(datetime.timezone.utc).isoformat(),event=name,**fields))+'\n')

def save(state):
    path=STATE.with_suffix('.tmp')
    path.write_text(json.dumps(state,indent=2),encoding='utf-8');path.replace(STATE)

def api(path,method='GET',data=None):
    args=['gh','api','--method',method,path]
    if data is not None: args+=['--input','-']
    result=backend.call(args,data=json.dumps(data) if data is not None else None,timeout=90)
    return json.loads(result.stdout) if result.stdout.strip() else None

def pages(path,key):
    result=[]
    separator='&' if '?' in path else '?'
    page=1
    while True:
        items=api(path+separator+f'per_page=100&page={page}')[key]
        result.extend(items)
        if len(items)<100: return result
        page+=1

def registrations(state):
    return pages(f"orgs/{state['organization']}/actions/runner-groups/{state['group_id']}/runners",'runners')

def retire(state):
    # DELETE is the assignment race barrier: GitHub refuses a busy registration.
    for runner in registrations(state):
        if runner['name'] != state['runner']: continue
        if runner['busy']: return False
        result=backend.call(['gh','api','--method','DELETE',f"orgs/{state['organization']}/actions/runners/{runner['id']}"],optional=True)
        if result.returncode: return False
    return True

def cleanup(state):
    volumes=set(state.get('volumes',[]))
    for name in (state['engine'],state['guard']):
        obj=backend.inspect(name)
        if obj:
            if obj['Config']['Labels'].get('eagle.fleet') != 'true': raise RuntimeError('Foreign container')
            volumes.update(m['Name'] for m in obj['Mounts'] if m['Type']=='volume')
    state.update(phase='cleaning',volumes=sorted(volumes));save(state)
    for name in (state['engine'],state['guard']): backend.remove(name)
    for name in volumes:
        if backend.inspect(name,'volume'): backend.call(['docker','volume','rm',name])
        if backend.inspect(name,'volume'): raise RuntimeError('Private volume remains')
    if any(r['name']==state['runner'] for r in registrations(state)): raise RuntimeError('Registration remains')
    event('cleanup-verified',runner=state['runner']);save(dict(phase='ready'))

def available(config):
    # Linux /proc includes cache; MemAvailable is the reclaimable capacity measure.
    result=backend.call(['docker','exec','eagle-fleet-proxy','cat','/proc/meminfo'])
    values={line.split(':')[0]:int(line.split()[1])*1024 for line in result.stdout.splitlines() if ':' in line}
    return values['MemAvailable'] >= config['minimum_available_bytes']

def queued(config):
    def scan(item):
        pool,repo=item
        result=[]
        for status in ('queued','in_progress'):
            runs=api(f'repos/{repo}/actions/runs?status={status}&per_page=20')['workflow_runs']
            for run in runs:
                # Do not occupy capacity for a pending environment approval.
                jobs=pages(f"repos/{repo}/actions/runs/{run['id']}/jobs",'jobs')
                for job in jobs:
                    if job['status'] != 'queued': continue
                    for profile in config['profiles']:
                        requested={label.lower() for label in job['labels']}
                        offered={label.lower() for label in profile['labels']}
                        if requested and requested <= offered and any(label.startswith('eagle-') for label in requested):
                            result.append((job.get('created_at') or run['created_at'],pool,profile,repo,run['id'],job['id']))
        return result
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
        results=list(executor.map(scan,[(pool,repo) for pool in config['pools'] for repo in pool.get('scan_repositories',pool['repositories'])]))
    candidates=[candidate for result in results for candidate in result]
    return min(candidates,key=lambda c:c[0]) if candidates else None

def validate_pool(pool):
    path=f"orgs/{pool['organization']}/actions/runner-groups/{pool['group_id']}"
    group=api(path)
    repos=pages(path+'/repositories','repositories')
    if (group['name'] != pool['group'] or group['visibility'] != 'selected' or
        group['restricted_to_workflows'] or group['allows_public_repositories'] != pool['allows_public_repositories'] or
        {r['full_name'].lower() for r in repos} != {r.lower() for r in pool['repositories']}):
        raise RuntimeError('Runner group scope drift')

def execute(candidate,config):
    _,pool,profile,repo,run,job=candidate
    validate_pool(pool)
    suffix=uuid.uuid4().hex[:12]
    state=dict(phase='creating-guard',runner='eagle-fleet-'+suffix,engine='eagle-fleet-engine-'+suffix,
               guard='eagle-fleet-guard-'+suffix,organization=pool['organization'],group_id=pool['group_id'],
               created=time.time(),deadline=time.time()+config['maximum_lifetime_seconds'],
               repository=repo,run_id=run,job_id=job)
    save(state);event('creating',runner=state['runner'],repository=repo,job=job)
    address=backend.infrastructure()
    def before_engine():
        state['phase']='creating-engine';save(state)
    backend.create(state['guard'],state['engine'],address,config['gateway_image'],
                   config['memory_limit'],config['maximum_lifetime_seconds'],before_engine)
    state['phase']='preparing';save(state)
    backend.prepare(state['engine'],profile['image'],address,state['runner'])
    state['phase']='configuring';save(state)
    registration=api(f"orgs/{pool['organization']}/actions/runners/registration-token",'POST')
    configure="""import os,sys,subprocess
os.environ['ACTIONS_RUNNER_INPUT_TOKEN']=sys.stdin.read().strip()
args=['./config.sh','--unattended','--url',sys.argv[1],'--name',sys.argv[2],'--runnergroup',sys.argv[3],'--labels',sys.argv[4],'--no-default-labels','--ephemeral','--work','_work']
sys.exit(subprocess.run(args,capture_output=True).returncode)
"""
    backend.inner(state['engine'],'exec','-i',state['runner'],'python3','-c',configure,
                  'https://github.com/'+pool['organization'],state['runner'],pool['group'],','.join(profile['labels']),
                  data=registration['token']+'\n',timeout=180)
    registration=None
    logs=ROOT/'logs';logs.mkdir(exist_ok=True)
    with (logs/(state['runner']+'.log')).open('w',encoding='utf-8') as stream:
        listener=subprocess.Popen(['docker','exec',state['engine'],'docker','-H',backend.SOCKET,
                                   'exec',state['runner'],'./run.sh','--once'],stdout=stream,stderr=subprocess.STDOUT,creationflags=backend.FLAGS)
        state['phase']='listening';save(state);event('listening',runner=state['runner'])
        idle=time.time()+900
        while listener.poll() is None:
            if time.time() >= state['deadline']:
                event('hard-deadline',runner=state['runner'])
                # External lifetime enforcement cannot be disabled by private Docker API.
                backend.remove(state['engine']);listener.wait(timeout=60)
                break
            if ((ROOT/'STOP').exists() or time.time() >= idle) and retire(state):
                backend.remove(state['engine']);listener.wait(timeout=60);break
            time.sleep(15)
    state['phase']='retiring';save(state)
    if not retire(state): raise RuntimeError('Waiting for GitHub registration to settle')
    cleanup(state)

def recover():
    if not STATE.exists(): return
    state=json.loads(STATE.read_text())
    if state.get('phase')=='ready': return
    pending={'creating-guard':state['guard'],'creating-engine':state['engine']}.get(state['phase'])
    if pending and not backend.inspect(pending):
        raise RuntimeError('Uncertain create; reconcile exact container before retry')
    if time.time() >= state['deadline']:
        backend.remove(state['engine'])
    if not retire(state): raise RuntimeError('Existing assigned job is preserved')
    cleanup(state)

def main():
    import msvcrt
    lock=(ROOT/'controller.lock').open('a+b')
    if lock.tell()==0: lock.write(b'0');lock.flush()
    lock.seek(0)
    try: msvcrt.locking(lock.fileno(),msvcrt.LK_NBLCK,1)
    except OSError: return
    event('controller-started',pid=os.getpid())
    while True:
        try:
            recover()
            if (ROOT/'STOP').exists(): return
            config=json.loads(CONFIG.read_text())
            if not available(config):
                event('capacity-wait');time.sleep(60);continue
            candidate=queued(config)
            if candidate: execute(candidate,config)
            else: time.sleep(config['poll_seconds'])
        except Exception as error:
            event('retry',reason=type(error).__name__+': '+str(error)[:160]);time.sleep(60)

if __name__=='__main__': main()
