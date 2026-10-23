"""Bind reviewed harness selections to verified local bench resources."""
import base64
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import uuid

from setup_harnesses import HarnessError, ROOT, inspect_directory, registry, safe_directory


def components():
    spec = importlib.util.spec_from_file_location('harness_components', ROOT / 'scripts/setup-components.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def selection_path(repo, home=None):
    import re
    if not re.fullmatch(r'[a-z0-9][a-z0-9-]*', repo):
        raise HarnessError('Invalid bench recipe identity')
    return Path(home or Path.home()) / '.config/workbenches/harnesses/benches' / (repo + '.list')


def read_selection(path):
    if path.is_relative_to(Path.home()):
        inspect_directory(path.parent, Path.home())
    if not path.exists() and not path.is_symlink():
        return set()
    info = path.lstat()
    if path.is_symlink() or not path.is_file() or info.st_uid != os.getuid() or info.st_mode & 0o077 or info.st_size > 16384:
        raise HarnessError('Bench harness selection must be a private regular file')
    body = path.read_bytes()
    keys = body.decode('ascii').splitlines()
    if body != ''.join(key + '\n' for key in keys).encode('ascii'):
        raise HarnessError('Bench harness selections require plain IDs and LF-terminated lines')
    allowed = {key for key, row in registry().items() if row['kind'] != 'unavailable'}
    if len(keys) != len(set(keys)) or not set(keys) <= allowed:
        raise HarnessError('Invalid bench harness selection')
    return set(keys)


def write_selection(path, keys):
    allowed = {key for key, row in registry().items() if row['kind'] != 'unavailable'}
    if not set(keys) <= allowed:
        raise HarnessError('Unknown or unavailable desired harness')
    safe_directory(path.parent, Path.home())
    # Reuse the strict existing-file validation before replacing it.
    read_selection(path)
    import uuid
    temporary = path.with_name('.' + path.name + '-' + uuid.uuid4().hex)
    try:
        fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, 'w') as output:
            output.write(''.join(key + '\n' for key in sorted(keys)))
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def prepare(names, api=None):
    api = api or components()
    if len(names) != len(set(names)):
        raise HarnessError('Duplicate bench target')
    if not names:
        return api, None, []
    env = api.local_docker_environment()
    inventory = api.docker_inventory(env=env)
    targets = []
    for name in names:
        _, repo, _ = api.bench_identity(name)
        _, containers = api.bench_resources(name, inventory)
        if len(containers) > 1:
            raise HarnessError('Ambiguous bench target')
        for row in containers:
            if not row.get('Id', '').isalnum() or len(row['Id']) != 64:
                raise HarnessError('Invalid immutable bench container ID')
            if row.get('Config', {}).get('User', '') in ('', '0', '0:0', 'root', 'root:root'):
                raise HarnessError('Bench harness installation requires its non-root runtime user')
        path = selection_path(repo)
        read_selection(path)
        targets.append((name, path, containers[0] if containers else None))
    return api, env, targets


BOOTSTRAP = '''import base64,json,os,pathlib,pwd,sys,tempfile,signal
if os.getuid()==0: raise SystemExit("Refusing root harness installation")
data=json.load(sys.stdin)
signal.signal(signal.SIGTERM,lambda *_:sys.exit(143))
signal.signal(signal.SIGINT,lambda *_:sys.exit(130))
os.environ["HOME"]=pwd.getpwuid(os.getuid()).pw_dir
os.environ.pop("WORKBENCHES_HOST_RPC",None)
marker=pathlib.Path("/tmp")/("workbenches-harness-"+data["operation"]+".json")
with marker.open("x") as output:
 marker.chmod(0o600)
 json.dump({"pid":os.getpid(),"start":pathlib.Path("/proc/self/stat").read_text().split()[21]},output)
try:
 with tempfile.TemporaryDirectory(prefix="workbenches-harness-") as temporary:
  root=pathlib.Path(temporary)
  for name,body in data["files"].items():
   path=root/name; path.parent.mkdir(parents=True,exist_ok=True); path.write_bytes(base64.b64decode(body))
  sys.path.insert(0,str(root/"scripts"))
  from setup_harnesses import Installer,Runner
  installer=Installer(runner=Runner(local=True))
  if data["action"]=="uninstall": installer.uninstall(data["key"])
  else: installer.install(data["key"])
finally:
 marker.unlink(missing_ok=True)
'''

CANCEL = '''import json,os,pathlib,signal,sys
p=pathlib.Path("/tmp")/("workbenches-harness-"+sys.argv[1]+".json")
if not p.exists():raise SystemExit(0)
if p.is_symlink() or p.stat().st_uid!=os.getuid() or p.stat().st_mode&0o077:raise SystemExit(1)
d=json.loads(p.read_text());pid=int(d["pid"])
stat=pathlib.Path("/proc")/str(pid)/"stat"
if stat.exists() and stat.read_text().split()[21]==d["start"]:os.kill(pid,signal.SIGTERM)
'''


def apply(action, key, prepared, run=subprocess.run):
    if action not in {'install', 'update', 'uninstall'} or key not in registry() or registry()[key]['kind'] == 'unavailable':
        raise HarnessError('Invalid managed harness target operation')
    _, env, targets = prepared
    files = {name: base64.b64encode((ROOT / name).read_bytes()).decode() for name in (
        'scripts/setup_harnesses.py', 'scripts/harness-native-command.sh', 'config/harness-installers.json')}
    pending = []
    for name, path, row in targets:
        import fcntl
        safe_directory(path.parent, Path.home())
        fd = os.open(path.with_suffix('.lock'), os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        try:
            if os.fstat(fd).st_uid != os.getuid():
                raise HarnessError('Foreign bench harness lock')
            fcntl.flock(fd, fcntl.LOCK_EX)
            keys = read_selection(path)
            keys.discard(key) if action == 'uninstall' else keys.add(key)
            write_selection(path, keys)
        finally:
            os.close(fd)
        if row is None or not row.get('State', {}).get('Running'):
            print(name + ': selection saved; pending next personalized image build/start')
            pending.append(name)
            continue
        operation = uuid.uuid4().hex
        try:
            result = run(['docker', 'exec', '-i', '--user', row['Config']['User'], row['Id'],
                          'python3', '-c', BOOTSTRAP], input=json.dumps({'files': files, 'action': action, 'key': key, 'operation': operation}),
                         text=True, capture_output=True, env=env, timeout=2400)
        except BaseException:
            try:
                run(['docker', 'exec', '--user', row['Config']['User'], row['Id'], 'python3', '-c', CANCEL, operation],
                    text=True, capture_output=True, env=env, timeout=10)
            except (OSError, subprocess.TimeoutExpired):
                pass
            raise
        if result.returncode:
            print(name + ': selection saved; live installation failed; retry Apply or rebuild the personalized image')
            pending.append(name)
        else:
            print(name + ': ' + ('managed CLI removed' if action == 'uninstall' else 'managed CLI installed and verified'))
    return pending
