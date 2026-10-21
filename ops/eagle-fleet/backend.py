"""Disposable rootless Docker execution boundary, managed from Windows."""
import json
import os
import subprocess
import time

FLAGS = getattr(subprocess, 'CREATE_NO_WINDOW', 0)
SOCKET = 'unix:///run/user/1000/docker.sock'
BACKEND = 'docker:28-dind-rootless@sha256:7c3e797187e43738220462658f4586572cbd3bf009f728b21e34d9c5c06ce431'

def call(args, data=None, timeout=300, optional=False):
    result = subprocess.run(args, input=data, text=True, encoding='utf-8', errors='replace',
                            capture_output=True, timeout=timeout, creationflags=FLAGS)
    if result.returncode and not optional:
        raise RuntimeError(f'{args[0]} {args[1]} failed ({result.returncode})')
    return result

def inspect(name, kind=None):
    args = ['docker', kind, 'inspect'] if kind else ['docker', 'inspect']
    result = call(args + [name], optional=True)
    if result.returncode:
        if 'no such' in result.stderr.lower(): return None
        raise RuntimeError('Docker inspect unavailable')
    return json.loads(result.stdout)[0]

def inner(engine, *args, data=None, timeout=300, optional=False):
    return call(['docker', 'exec', '-i', engine, 'docker', '-H', SOCKET, *args],
                data=data, timeout=timeout, optional=optional)

def infrastructure():
    obj = inspect('eagle-fleet-proxy')
    if not obj or not obj['State']['Running'] or obj['Config']['Labels'].get('eagle.fleet') != 'true':
        raise RuntimeError('Fleet gateway needs provisioning')
    return obj['NetworkSettings']['Networks']['eagle-fleet-private']['IPAddress']

def create(guard, engine, address, gateway, memory='8g', lifetime=27000, before_engine=None):
    proxy = f'http://{address}:3128'
    call(['docker','run','-d','--name',guard,'--label','eagle.fleet=true',
          '--network','eagle-fleet-private','--cap-drop','ALL','--cap-add','NET_ADMIN',
          '--security-opt','no-new-privileges','--read-only','--pids-limit','32','--memory','64m',
          '-e',f'PROXY_IP={address}','--entrypoint','/opt/guard.sh',gateway])
    expected = {'-P OUTPUT DROP','-A OUTPUT -o lo -j ACCEPT',
                f'-A OUTPUT -d {address}/32 -p tcp -m tcp --dport 3128 -j ACCEPT'}
    for attempt in range(20):
        rules=call(['docker','exec',guard,'iptables','-S','OUTPUT'],optional=True)
        if rules.returncode == 0 and set(rules.stdout.strip().splitlines()) == expected: break
        time.sleep(1)
    else: raise RuntimeError('Guard not ready')
    if call(['docker','exec',guard,'ip6tables','-S','OUTPUT']).stdout.strip() != '-P OUTPUT DROP':
        raise RuntimeError('IPv6 guard not ready')
    if before_engine: before_engine()
    call(['docker','run','-d','--name',engine,'--label','eagle.fleet=true',
          '--network',f'container:{guard}','--cap-drop','ALL','--cap-add','SETUID','--cap-add','SETGID',
          '--device','/dev/net/tun','--security-opt','seccomp=unconfined','--security-opt','apparmor=unconfined',
          '--security-opt','systempaths=unconfined','--pids-limit','4096','--memory',memory,'--cpus','4',
          '-e','DOCKER_TLS_CERTDIR=','-e','DOCKERD_ROOTLESS_ROOTLESSKIT_NET=slirp4netns',
          '-e',f'HTTP_PROXY={proxy}','-e',f'HTTPS_PROXY={proxy}','-e','NO_PROXY=localhost,127.0.0.1',
          '--entrypoint','timeout',BACKEND,str(lifetime),'dockerd-entrypoint.sh','--log-level=error'])
    obj=inspect(engine)
    host=obj['HostConfig']
    if (obj['Config']['User'] != 'rootless' or host['Privileged'] or host['PortBindings'] or
        any(m['Type'] != 'volume' for m in obj['Mounts'])):
        raise RuntimeError('Unexpected backend host access')
    for attempt in range(40):
        result=inner(engine,'info','--format','{{json .SecurityOptions}}',optional=True)
        if result.returncode == 0 and 'name=rootless' in json.loads(result.stdout): return
        time.sleep(2)
    raise RuntimeError('Rootless engine not ready')

def load(engine,image):
    # Binary stream: no PowerShell pipeline, no host directory, no job credential.
    save=subprocess.Popen(['docker','image','save',image],stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,creationflags=FLAGS)
    receiver=subprocess.Popen(['docker','exec','-i',engine,'docker','-H',SOCKET,'load'],
                              stdin=save.stdout,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,creationflags=FLAGS)
    save.stdout.close()
    try:
        if receiver.wait(timeout=1200) or save.wait(timeout=30): raise RuntimeError('Image transfer failed')
    finally:
        for proc in (receiver,save):
            if proc.poll() is None: proc.kill(); proc.wait()

def prepare(engine,image,address,runner):
    load(engine,image)
    call(['docker','exec','--user','0',engine,'sh','-c',
          'mkdir -p /home/runner/_work /opt/hostedtoolcache; chmod 1777 /home/runner /home/runner/_work /opt/hostedtoolcache; ln -sf /run/user/1000/docker.sock /var/run/docker.sock'])
    inner(engine,'run','--rm','--user','0','-v','/home/runner:/seed','--entrypoint','sh',image,
          '-c','cp -a /home/runner/externals /seed/externals; chmod -R a+rX /seed/externals',timeout=600)
    proxy=f'http://{address}:3128'
    inner(engine,'run','-d','--name',runner,'--network','host','--group-add','2375','--cap-add','SYS_ADMIN',
          '--security-opt','seccomp=unconfined','--security-opt','apparmor=unconfined',
          '-v','/home/runner/_work:/home/runner/_work','-v','/home/runner/externals:/home/runner/externals',
          '-v','/opt/hostedtoolcache:/opt/hostedtoolcache',
          '-v','/run/user/1000/docker.sock:/var/run/docker.sock',
          '-e','DOCKER_HOST=unix:///var/run/docker.sock','-e',f'http_proxy={proxy}',
          '-e',f'https_proxy={proxy}','-e','no_proxy=localhost,127.0.0.1',
          '-e','Papertrail__Host=','-e','Papertrail__Port=0',
          '--entrypoint','sleep',image,'26000')
    proof=inner(engine,'exec',runner,'bash','-lc',
                "test $(id -u) = 1001 && sudo -n true && docker info --format '{{json .SecurityOptions}}'")
    if 'name=rootless' not in json.loads(proof.stdout): raise RuntimeError('Worker rootless proof failed')

def remove(name):
    obj=inspect(name)
    if not obj: return
    if obj['Config']['Labels'].get('eagle.fleet') != 'true': raise RuntimeError('Container ownership collision')
    if any(m['Type'] != 'volume' for m in obj['Mounts']): raise RuntimeError('Unexpected host mount')
    call(['docker','rm','-f','-v',name])
    if inspect(name): raise RuntimeError('Container remains after cleanup')
