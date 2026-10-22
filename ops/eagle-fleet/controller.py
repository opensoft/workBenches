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

class ApiUnavailable(RuntimeError):
    pass

def api(path,method='GET',data=None):
    args=['gh','api','--method',method,path]
    if data is not None: args+=['--input','-']
    attempts=3 if method=='GET' else 1
    for attempt in range(attempts):
        try:
            result=backend.call(args,data=json.dumps(data) if data is not None else None,
                                timeout=30 if method=='GET' else 90,optional=True)
        except subprocess.TimeoutExpired:
            result=None
        if result is not None and result.returncode==0:
            return json.loads(result.stdout) if result.stdout.strip() else None
        if attempt+1<attempts: time.sleep(attempt+1)
    # Do not expose response bodies or credentials; mutations are never retried.
    raise ApiUnavailable('GitHub API unavailable: '+method+' '+path)

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
    # Forced deletion is permitted only after local listener/worker exit. A busy
    # read is an extra settling check, never an assignment-race barrier.
    if not state.get('listener_stopped'):
        raise RuntimeError('Listener exit must be proven before unregistering')
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
        try:
            pool,repo=item
            result=[]
            for status in ('queued','in_progress'):
                runs=pages(f'repos/{repo}/actions/runs?status={status}','workflow_runs')
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
        except ApiUnavailable:
            event('repository-scan-unavailable',repository=item[1])
            return []
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
               created=time.time(),deadline=None,job_assigned=False,
               maximum_job_seconds=config['maximum_lifetime_seconds'],
               repository=repo,run_id=run,job_id=job)
    save(state);event('creating',runner=state['runner'],repository=repo,job=job)
    address=backend.infrastructure(config['gateway_image'])
    def before_engine():
        state['phase']='creating-engine';save(state)
    backend.create(state['guard'],state['engine'],address,config['gateway_image'],
                   config['backend_image'],config['memory_limit'],before_engine)
    state['phase']='preparing';save(state)
    backend.prepare(state['engine'],profile['image'],address,state['runner'])
    pending=api(f'repos/{repo}/actions/jobs/{job}')
    if (ROOT/'STOP').exists() or pending['status']!='queued':
        state['listener_stopped']=True;save(state)
        if not retire(state): raise RuntimeError('Unexpected assignment before listener start')
        cleanup(state)
        return
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
    state['exec_id']=backend.listener_create(state['engine'],state['runner'])
    state['phase']='starting-listener';save(state)
    backend.listener_start(state['engine'],state['runner'],state['exec_id'])
    state['phase']='listening';save(state);event('listening',runner=state['runner'])
    monitor(state)
    state['phase']='retiring';save(state)
    if not retire(state): raise RuntimeError('Waiting for GitHub registration to settle')
    cleanup(state)

def monitor(state):
    """Wait for the exact once-listener; STOP never cancels its assigned job."""
    while True:
        # Enforce persisted job limits even if the private daemon becomes faulty.
        if state.get('job_assigned') and time.time()>=state['deadline']:
            event('hard-job-deadline',runner=state['runner'])
            backend.remove(state['engine']);state['listener_stopped']=True;save(state);return
        obj=backend.inspect(state['engine'])
        if not obj or not obj['State']['Running']:
            state['listener_stopped']=True;save(state);return
        if not state.get('hook_acknowledged'):
            marker=backend.inner(state['engine'],'exec',state['runner'],'test','-e','/home/runner/.eagle-job-started',optional=True)
            if marker.returncode==0:
                if not state.get('job_assigned'):
                    state.update(job_assigned=True,deadline=time.time()+state['maximum_job_seconds']);save(state)
                backend.inner(state['engine'],'exec',state['runner'],'touch','/home/runner/.eagle-job-start-ack')
                state['hook_acknowledged']=True;save(state)
        registered=registrations(state)
        if any(r['name']==state['runner'] and r['busy'] for r in registered) and not state.get('job_assigned'):
            state.update(job_assigned=True,deadline=time.time()+state['maximum_job_seconds']);save(state)
        worker=backend.inner(state['engine'],'inspect',state['runner'],optional=True)
        if worker.returncode:
            if 'no such' not in worker.stderr.lower(): raise RuntimeError('Worker inspection unavailable')
            backend.remove(state['engine']);state['listener_stopped']=True;save(state);return
        status=backend.listener_status(state['engine'],state['runner'],state['exec_id'])
        if not status['Running']:
            state['listener_stopped']=True;save(state)
            event('listener-exited',runner=state['runner'],returncode=status['ExitCode'])
            logs=ROOT/'logs';logs.mkdir(exist_ok=True)
            result=backend.inner(state['engine'],'exec',state['runner'],'tail','-c','200000','/home/runner/eagle-listener.log',optional=True)
            if not result.returncode: (logs/(state['runner']+'.log')).write_text(result.stdout,encoding='utf-8')
            return
        assigned=any(r['name']==state['runner'] and r['busy'] for r in registered)
        if assigned and not state.get('job_assigned'):
            state.update(job_assigned=True,deadline=time.time()+state['maximum_job_seconds']);save(state)
        if state.get('job_assigned') and time.time()>=state['deadline']:
            event('hard-job-deadline',runner=state['runner'])
            backend.remove(state['engine']);state['listener_stopped']=True;save(state);return
        # An idle registered once-listener remains until it exits naturally. It
        # may claim one final job while draining; no new sandbox is provisioned.
        time.sleep(15)

def recover():
    if not STATE.exists(): return
    state=json.loads(STATE.read_text())
    if state.get('phase')=='ready': return
    pending={'creating-guard':state['guard'],'creating-engine':state['engine']}.get(state['phase'])
    if pending and not backend.inspect(pending):
        raise RuntimeError('Uncertain create; reconcile exact container before retry')
    if state.get('exec_id'):
        if state['phase']=='starting-listener':
            status=backend.listener_status(state['engine'],state['runner'],state['exec_id'])
            if not status['Running'] and status['ExitCode']==0 and any(r['name']==state['runner'] for r in registrations(state)):
                raise RuntimeError('Uncertain listener start; preserve exact exec until reconciled')
        monitor(state)
    elif state['phase']=='listening':
        if any(r['name']==state['runner'] for r in registrations(state)):
            raise RuntimeError('Preserving legacy listener until its ephemeral registration disappears')
    state['listener_stopped']=True;save(state)
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
