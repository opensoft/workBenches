#!/usr/bin/env python3
"""Docker-only setup acceptance, invoked by the declared tools-runtime service."""
import json
import os
from pathlib import Path
import pty
import re
import signal
import select
import shutil
import subprocess
import tempfile
import time
import uuid
from terminal_screen import terminal_screen

ROOT = Path(__file__).resolve().parents[1]


def run(argv, **kwargs):
    result = subprocess.run(argv, capture_output=True, text=True, timeout=240, **kwargs)
    if result.returncode:
        raise AssertionError(f'Command failed: {argv[0]}\n{result.stdout}\n{result.stderr}')
    return result.stdout.strip()


def check_service_buttons(home, env):
    """Real TUI and runtime lifecycle; only the account server is a fixture."""
    repo = home / 'button-fixture'; repo.mkdir()
    for name in ('setup.sh', 'bootstrap.sh'):
        shutil.copy(ROOT / name, repo / name)
    for name in ('scripts', 'config'):
        shutil.copytree(ROOT / name, repo / name, ignore=shutil.ignore_patterns('__pycache__'))
    # Queue a disposable catalog entry, not a production bench whose container
    # may legitimately belong to another checkout on the test workstation.
    catalog = repo / 'config/bench-config.json'
    data = json.loads(catalog.read_text())
    data['benches'] = {'fixtureBench': {'url': 'https://example.invalid/fixtureBench.git',
                                      'path': 'devBenches/fixtureBench',
                                      'description': 'Disposable queue fixture'}}
    catalog.write_text(json.dumps(data))
    helper = repo / 'scripts/setup-workbenches-account.py'
    helper.write_text('''import os, pathlib, sys, time
root = pathlib.Path.home()
session = root / 'fixture-account-session'
counter = root / 'fixture-account-attempts'
if '--status' in sys.argv:
    print('signed in' if session.exists() else 'sign in')
elif '--logout' in sys.argv:
    session.unlink(missing_ok=True)
else:
    attempt = int(counter.read_text()) + 1 if counter.exists() else 1
    counter.write_text(str(attempt))
    if attempt == 1:
        print('Fixture waiting for approval', flush=True)
        try:
            time.sleep(120)
        except KeyboardInterrupt:
            sys.exit(130)
    os.umask(0o077)
    session.write_text('fixture-identity')
''')
    master, slave = pty.openpty()
    process = subprocess.Popen(['/bin/bash', str(repo / 'setup.sh')], cwd=repo, env=env,
                               stdin=slave, stdout=slave, stderr=slave, close_fds=True,
                               start_new_session=True)
    os.close(slave)
    transcript = b''; stage = 0
    deadline = time.monotonic() + 240
    try:
        while process.poll() is None and time.monotonic() < deadline:
            readable, _, _ = select.select([master], [], [], .2)
            if readable:
                try: chunk = os.read(master, 65536)
                except OSError: break
                transcript += chunk
            plain = terminal_screen(transcript)
            ready = False; keys = b''
            if stage == 0 and 'Navigation:' in plain and 'fixtureBench · not installed' in plain and re.search(r'REQUIREMENTS · (\d+)/\1 ready', plain):
                # Queue a bench; use only the Vault button on the main screen.
                ready = True; keys = b' '
            elif stage == 1 and re.search(r'Vault\s+Missing\s+\[V Install\]', plain) and 'Changes selected: 1' in plain:
                ready = True; keys = b'V'
            elif stage == 2 and re.search(r'Vault\s+Up\s+\[V Connect\]', plain) and 'Changes selected: 1' in plain:
                ready = True; keys = b'V'
            elif stage == 3 and 'Fixture waiting for approval' in plain:
                ready = True; keys = b'\x03'
            elif stage == 4 and 'Connection cancelled.' in plain and '[V Connect]' in plain and 'Changes selected: 1' in plain:
                ready = True; keys = b'V'
            elif stage == 5 and re.search(r'Vault\s+Up\s+\[V Sign out\]', plain) and 'Changes selected: 1' in plain:
                ready = True; keys = b'v'
            elif stage == 6 and re.search(r'Vault\s+Up\s+\[V Connect\]', plain) and 'Changes selected: 1' in plain:
                ready = True; keys = b'G'
            elif stage == 7 and 'PERSONAL & COMPANY IDENTITIES' in plain and 'Personal & companies' in plain:
                ready = True; keys = b'\r'
            elif stage == 8 and 'PROFILES · Personal and companies' in plain:
                ready = True; keys = b'q'
            elif stage == 9 and 'Profile action cancelled; saved profiles kept.' in plain:
                ready = True; keys = b'G'
            elif stage == 10 and re.search(r'Vault\s+Up\s+\[V Connect\]', plain) and 'Changes selected: 1' in plain:
                ready = True; keys = b'Q'
            if ready:
                print(f'Button-flow stage {stage} → {stage + 1}', flush=True)
                os.write(master, keys); stage += 1
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            raise AssertionError((stage, transcript.decode(errors='replace')[-6000:])) from None
        assert stage == 11 and process.returncode == 130, (stage, transcript.decode(errors='replace')[-6000:])
        assert not (home / 'fixture-account-session').exists()
        assert (home / 'fixture-account-attempts').read_text() == '2'
    finally:
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
            process.wait(timeout=5)
        os.close(master)
    print('PASS: main-screen Vault V Install → Connect → Ctrl+C → sign in → sign out; Profiles open/cancel/back; queued bench preserved')


def check_cloud_callback(image):
    """Real Docker loopback publication and Tools relay; no provider or tokens."""
    name = 'workbenches-cloud-callback-' + uuid.uuid4().hex[:12]
    script = '''import http.server, socket, threading
from rclone_login import Relay
class Fixture(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_): pass
    def do_GET(self):
        self.send_response(200); self.end_headers(); self.wfile.write(self.path.encode())
local = http.server.ThreadingHTTPServer(('127.0.0.1', 53682), Fixture)
threading.Thread(target=local.serve_forever, daemon=True).start()
http.server.ThreadingHTTPServer((socket.gethostbyname(socket.gethostname()), 53682), Relay).serve_forever()
'''
    try:
        run(['docker', 'run', '-d', '--rm', '--name', name, '--user', f'{os.getuid()}:{os.getgid()}', '--read-only', '--cap-drop', 'ALL',
             '--publish', '127.0.0.1::53682', '--entrypoint', 'python3', image, '-c', script])
        info = json.loads(run(['docker', 'inspect', name]))[0]
        binding = info['NetworkSettings']['Ports']['53682/tcp'][0]
        assert binding['HostIp'] == '127.0.0.1'
        probe = '''import sys, time, urllib.request
url = 'http://127.0.0.1:' + sys.argv[1] + '/auth?state=fixture-state'
for _ in range(30):
    try:
        assert urllib.request.urlopen(url, timeout=2).read() == b'/auth?state=fixture-state'
        break
    except OSError: time.sleep(.1)
else: raise AssertionError('OAuth relay did not become reachable')
'''
        run(['docker', 'run', '--rm', '--network', 'host', '--entrypoint', 'python3', image, '-c', probe, binding['HostPort']])
        print('PASS: cloud OAuth relay reaches container loopback through host-loopback-only publication')
    finally:
        subprocess.run(['docker', 'rm', '-f', name], capture_output=True)


def main():
    assert os.environ.get('WORKBENCHES_RUNTIME_TEST') == '1', 'Use the tools-runtime Compose service'
    suffix = str(os.getpid()) + '-' + uuid.uuid4().hex[:8]
    tools = 'workbenches-runtime-test-tools-' + suffix
    vault = 'workbenches-runtime-test-vault-' + suffix
    network = 'workbenches-runtime-test-' + suffix
    with tempfile.TemporaryDirectory(prefix='workbenches-runtime-test-') as temporary:
        home = Path(temporary)
        binary = home / 'minimal-bin'; binary.mkdir()
        # Simulate a fresh workstation: setup executables are absent.
        for name in ('bash', 'sh', 'docker', 'uname', 'id', 'dirname', 'basename', 'stat',
                     'ps', 'touch', 'cksum', 'readlink', 'mkdir', 'mktemp', 'sleep', 'ln', 'rm', 'mv',
                     'cat', 'chmod', 'date', 'whoami', 'hostname', 'ls', 'tail', 'xargs',
                     'tee', 'tput', 'clear', 'grep', 'tr', 'head', 'find', 'sort', 'sed', 'cut', 'wc'):
            located = shutil.which(name)
            assert located, name
            (binary / name).symlink_to(located)
        # Native probe must distinguish a host tool from the guest's binaries.
        native = binary / 'native-fixture'
        native.write_text('#!/bin/bash\nprintf "host:%s" "$1"\n'); native.chmod(0o755)
        github = binary / 'gh'
        github.write_text('''#!/bin/bash
set -eu
case "$1 $2" in
  'auth status') printf '[{"login":"fixture-user","active":false,"state":"success"}]' ;;
  'auth token') [[ "$5" == --user && "$6" == fixture-user ]]; printf fixture-private-token ;;
  'auth login')
    printf 'First copy your one-time code: ABCD-1234\\n' >&2
    while [[ ! -f "$HOME/github-device-approved" ]]; do sleep .05; done
    printf fixture-private-token > "$GH_CONFIG_DIR/hosts.yml"
    ;;
  'api --hostname') printf '{"id":101,"login":"fixture-user"}' ;;
  *) exit 99 ;;
esac
'''); github.chmod(0o755)
        browser = binary / 'wslview'
        browser.write_text('#!/bin/bash\nprintf "%s" "$1" > "$HOME/github-browser-url"\n'); browser.chmod(0o755)
        clipboard = binary / 'wl-copy'
        clipboard.write_text('#!/bin/bash\ncat > "$HOME/github-device-code"\n'); clipboard.chmod(0o755)
        env = dict(os.environ, HOME=str(home), XDG_CACHE_HOME=str(home / '.cache'),
                   XDG_CONFIG_HOME=str(home / '.config'), XDG_DATA_HOME=str(home / '.local/share'),
                   PATH=str(binary), TERM='xterm', WORKBENCHES_TOOLS_ROOT=str(ROOT),
                   WORKBENCHES_TOOLS_CONTAINER=tools, WORKBENCHES_VAULT_CONTAINER=vault,
                   WORKBENCHES_SERVICES_NETWORK=network)
        env.pop('WORKBENCHES_TEST_NATIVE_TOOLS', None)
        try:
            driver = '''set -e
source "$1/scripts/lib/setup-prerequisites.sh"
for tool in python3 jq git curl rclone; do ! command -v "$tool" || exit 31; done
ensure_workstation_requirements || exit "$?"
python3 -c 'import os, pwd; assert pwd.getpwuid(os.getuid()).pw_name == os.environ["USER"]'
python3 --version
rclone version
python3 -I -c 'import workbenches_host as host; assert host.which("native-fixture")'
python3 "$1/scripts/credential-sync.py" --status
jq -n 'true'
git --version
curl --version
python3 - <<'NATIVE'
import workbenches_host as host
assert host.which('native-fixture')
assert host.which('node') is None
assert host.run(['native-fixture', 'literal $(no-execution); spaces'], capture_output=True, text=True).stdout == 'host:literal $(no-execution); spaces'
try:
    host.resolve('/nonexistent-parent/file')
except OSError:
    pass
else:
    raise AssertionError('Native path probe accepted a missing parent')
print('Native command boundary passed')
long = host.run(['bash', '-c', 'sleep 31; printf long-native-command-completed'],
                capture_output=True, text=True, timeout=60)
assert long.returncode == 0 and long.stdout == 'long-native-command-completed', long
short = host.run(['sleep', '4'], capture_output=True, timeout=1)
assert short.returncode != 0, 'Native command ignored the requested short deadline'
print('Native long/short deadlines passed')
NATIVE
'''
            output = run(['/bin/bash', '-c', driver, 'runtime', str(ROOT)], env=env, cwd=ROOT)
            for expected in ('Python 3.', '"agent"', 'true', 'git version', 'curl ', 'Native command boundary passed', 'Native long/short deadlines passed'):
                assert expected in output, output
            command = '''set -e
source "$1/scripts/lib/setup-prerequisites.sh"
ensure_workstation_requirements
python3 - "$1" <<'GITHUB'
import sys
sys.path.insert(0, sys.argv[1] + '/scripts')
from profile_github import GitHub, DEVICE_URL
import workbenches_host as host
from company_connection import native_action
assert native_action('browser', 'https://identity.example/admin/', host)
assert native_action('copy', 'Public client; device authorization enabled', host)
import pathlib
assert (pathlib.Path.home() / 'github-browser-url').read_text() == 'https://identity.example/admin'
assert (pathlib.Path.home() / 'github-device-code').read_text() == 'Public client; device authorization enabled'
import subprocess
subprocess.run(['/opt/workbenches/rclone-open', 'http://127.0.0.1:53682/auth?state=fixture-state'], cwd=pathlib.Path.home(), check=True)
assert (pathlib.Path.home() / 'github-browser-url').read_text() == 'http://127.0.0.1:53682/auth?state=fixture-state'
(pathlib.Path.home() / 'browser-url').unlink()
client = GitHub(host)
assert client.discover()[0]['login'] == 'fixture-user'
connection = {'id': 101, 'login': 'fixture-user', 'authSource': 'native'}
assert client.verify(connection) and connection['state'] == 'Connected'
assert client.open_browser()
assert client.copy_code('ABCD-1234')
# A long-running approval must not occupy the native RPC dispatcher.
import pathlib, time
config = pathlib.Path.home() / '.config/workbenches/github-auth/fixture'
config.mkdir(parents=True, mode=0o700)
progress = config / 'progress'
progress.touch(mode=0o600)
assert client.command('start-login', config, str(progress)).returncode == 0
for _ in range(100):
    if 'ABCD-1234' in progress.read_text(): break
    time.sleep(.05)
else: raise AssertionError('No native device code')
assert client.open_browser()  # This RPC must return while gh is pending.
assert client.copy_code('ABCD-1234')
(pathlib.Path.home() / 'github-device-approved').touch()
for _ in range(100):
    if pathlib.Path(str(progress) + '.exit').exists(): break
    time.sleep(.05)
else: raise AssertionError('Native login did not finish')
assert pathlib.Path(str(progress) + '.exit').read_text().strip() == '0'
assert client.command('current', config).returncode == 0
print('Native GitHub boundary passed')
import cloud_profiles as cloud
import threading, os
scope = {'id': 'personal', 'name': 'Disposable personal'}
outcomes = []
def connect_fixture():
    try: cloud.connect(scope, 'onedrive', 'Fixture Drive')
    except ValueError: outcomes.append('denied')
    except BaseException: outcomes.append('unexpected')
worker = threading.Thread(target=connect_fixture, daemon=True)
worker.start()
try:
    for _ in range(300):
        url = (pathlib.Path.home() / 'github-browser-url').read_text()
        if url.startswith('http://127.0.0.1:53682/auth?state='): break
        if not worker.is_alive(): raise AssertionError('Cloud browser did not start: ' + str(outcomes))
        time.sleep(.1)
    else: raise AssertionError('Cloud browser did not open')
    image = subprocess.check_output(['docker', 'inspect', os.environ['WORKBENCHES_TOOLS_CONTAINER'], '--format', '{{.Image}}'], text=True).strip()
    probe = """import sys, urllib.request, urllib.error, urllib.parse
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args): return None
url = sys.argv[1]
try: urllib.request.build_opener(NoRedirect).open(url, timeout=5)
except urllib.error.HTTPError as error:
    assert error.code == 307
    target = urllib.parse.urlsplit(error.headers['Location'])
    assert target.hostname == 'login.microsoftonline.com'
    scopes = urllib.parse.parse_qs(target.query)['scope'][0].split()
    assert 'Files.Read' in scopes and not any('Write' in scope for scope in scopes)
else: raise AssertionError('Expected local redirect only')
state = urllib.parse.parse_qs(urllib.parse.urlsplit(url).query)['state'][0]
callback = 'http://127.0.0.1:53682/?' + urllib.parse.urlencode({'state':state, 'error':'access_denied'})
try: urllib.request.urlopen(callback, timeout=5)
except urllib.error.HTTPError as error: assert error.code == 400
"""
    subprocess.run(['docker', 'run', '--rm', '--network', 'host', '--entrypoint', 'python3', image, '-c', probe, url], check=True)
    worker.join(timeout=15)
    assert not worker.is_alive() and outcomes == ['denied'], outcomes
    assert cloud.load(scope) == {'version': 1, 'connections': [], 'sources': []}
    print('Actual Rclone browser RPC, read-only consent redirect, denied callback and cleanup passed')
finally:
    if worker.is_alive():
        for directory in cloud.scope_root(scope).glob('[0-9a-f]' * 32):
            subprocess.run(['docker', 'rm', '-f', 'workbenches-cloud-login-' + directory.name], capture_output=True)
        worker.join(timeout=10)
assert client.open_browser()  # Restore the GitHub fixture's independent postcondition.
GITHUB
[[ "$(cat "$HOME/github-browser-url")" == https://github.com/login/device ]]
[[ "$(cat "$HOME/github-device-code")" == ABCD-1234 ]]
'''
            output = run(['/bin/bash', '-c', command, 'native-github', str(ROOT)], env=env, cwd=ROOT)
            assert 'Native GitHub boundary passed' in output
            assert 'Actual Rclone browser RPC, read-only consent redirect, denied callback and cleanup passed' in output
            assert 'fixture-private-token' not in output
            print('PASS: native GitHub account discovery/verification and browser/clipboard through Tools')
            print('PASS: actual Rclone browser sign-in, read-only consent redirect, denied callback and cleanup')
            prefix = home / '.local'
            package = prefix / 'lib/node_modules/@openai/codex'
            package.mkdir(parents=True)
            (package / 'package.json').write_text('{"name":"@openai/codex"}')
            executable = package / 'cli.js'
            executable.write_text('#!/bin/bash\necho fixture-codex\n'); executable.chmod(0o755)
            (prefix / 'bin').mkdir(parents=True)
            launcher = prefix / 'bin/codex'; launcher.symlink_to(executable)
            (binary / 'codex').symlink_to(launcher)
            npm = binary / 'npm'
            npm.write_text('''#!/bin/bash
if [[ "$1" == prefix ]]; then echo "$HOME/.local"
elif [[ "$1" == uninstall ]]; then rm -f "$HOME/.local/bin/codex"
else exit 99; fi
'''); npm.chmod(0o755)
            command = '''set -e
source "$1/scripts/lib/setup-prerequisites.sh"
ensure_workstation_requirements
[[ "$(python3 "$1/scripts/setup-components.py" tool-status codex_cli)" == installed ]]
python3 "$1/scripts/setup-components.py" uninstall codex_cli
[[ "$(python3 "$1/scripts/setup-components.py" tool-status codex_cli)" == 'not installed' ]]
'''
            run(['/bin/bash', '-c', command, 'native-removal', str(ROOT)], env=env, cwd=ROOT)
            assert not launcher.exists()
            assert executable.exists(), 'The fixture package payload should be preserved by its fake npm command'
            bench_setup = home / 'native-bench.sh'
            bench_setup.write_text('''#!/bin/bash
native-fixture bench > "$HOME/bench-native-result"
python3 -c 'print("container Python available")'
''')
            command = '''source "$1/scripts/lib/setup-prerequisites.sh"
ensure_workstation_requirements || exit "$?"
python3 "$1/scripts/setup-bench-runtime.py" --bench fixture --setup "$2"
[[ "$?" == 1 && "$(cat "$HOME/bench-native-result")" == host:bench ]]
'''
            run(['/bin/bash', '-c', command, 'native-bench', str(ROOT), str(bench_setup)], env=env, cwd=ROOT)
            compose_dir = home / '.devcontainer'; compose_dir.mkdir()
            (compose_dir / 'docker-compose.yml').write_text(
                'services:\n  runtime-fixture:\n    container_name: runtime-fixture\n    image: workbenches/tools:2026.10.15-v1\n')
            bench_setup.write_text('''#!/bin/bash
set -e
native-fixture compose > "$HOME/bench-native-result"
docker-compose -f .devcontainer/docker-compose.yml config --services > "$HOME/bench-compose-result"
''')
            adapter_probe = home / 'adapter-probe.py'
            adapter_probe.write_text('''import importlib.util, pathlib, subprocess, sys
root = pathlib.Path(sys.argv[1])
spec = importlib.util.spec_from_file_location('bench', root / 'scripts/setup-bench-runtime.py')
bench = importlib.util.module_from_spec(spec); spec.loader.exec_module(bench)
original = bench.run
def checked(argv, **kwargs):
    if len(argv) > 1 and argv[1].endswith('wave-container-shell.sh'):
        # No real bench is started; only native script and Docker adapter run.
        if '--prepare-compose' in argv:
            pathlib.Path(argv[argv.index('--prepare-compose') + 1]).write_text('services: {}\\n')
        return subprocess.CompletedProcess(argv, 0 if '--prepare-compose' in argv else 1)
    return original(argv, **kwargs)
bench.run = checked
sys.argv = ['bench', '--bench', 'fixture', '--setup', sys.argv[2]]
assert bench.main() == 1  # No container was launched by the fixture.
''')
            command = '''set -e
source "$1/scripts/lib/setup-prerequisites.sh"
ensure_workstation_requirements
python3 "$2" "$1" "$3"
[[ "$(cat "$HOME/bench-native-result")" == host:compose ]]
[[ "$(cat "$HOME/bench-compose-result")" == runtime-fixture ]]
'''
            run(['/bin/bash', '-c', command, 'compose-adapter', str(ROOT), str(adapter_probe), str(bench_setup)], env=env, cwd=ROOT)
            print('PASS: native bench Docker adapter uses container Python without recursion')
            print('PASS: bench setup uses native host paths and container Python')
            print('PASS: host application discovery and native npm removal through Tools')
            print('PASS: Docker-only bootstrap, five tools, stdin, and literal native-host calls')
            services = ROOT / 'scripts/manage-setup-services.sh'
            state = lambda role: run(['/bin/bash', str(services), 'status', role], env=env)
            assert state('tools') == 'up'
            assert state('vault') == 'missing'
            original = run(['docker', 'inspect', tools, '--format', '{{.Id}}'])
            run(['docker', 'stop', tools]); assert state('tools') == 'down'
            run(['/bin/bash', str(services), 'start', 'tools'], env=env)
            assert original == run(['docker', 'inspect', tools, '--format', '{{.Id}}'])
            assert state('tools') == 'up'
            print('PASS: Tools Up/Down/Missing and restart preserves the container')
            check_cloud_callback(run(['docker', 'inspect', tools, '--format', '{{.Image}}']))
            # Exercise the actual launcher; Q must stop before any installation.
            master, slave = pty.openpty()
            process = subprocess.Popen(['/bin/bash', str(ROOT / 'setup.sh')], cwd=ROOT, env=env,
                                       stdin=slave, stdout=slave, stderr=slave, close_fds=True)
            os.close(slave)
            transcript = b''; sent = False; started = time.monotonic(); deadline = started + 120
            try:
                while process.poll() is None and time.monotonic() < deadline:
                    readable, _, _ = select.select([master], [], [], .2)
                    if readable:
                        try: transcript += os.read(master, 65536)
                        except OSError: break
                    if not sent and b'Navigation:' in transcript:
                        assert time.monotonic() - started < 2, 'TUI was blocked before first paint'
                        os.write(master, b'PQ'); sent = True
                process.wait(timeout=5)
                assert process.returncode == 130, transcript.decode(errors='replace')[-5000:]
                for marker in (b'Docker', b'Tools', b'Vault', b'Loading', b'\x1b[5m', b'REQUIREMENTS'):
                    assert marker in transcript, marker
            finally:
                if process.poll() is None: process.kill(); process.wait()
                os.close(master)
            print('PASS: real setup TUI paints loading states within 2s; P then Q cancels')
            # Optional: public CLI versions and exact isolation of the Vault runtime.
            if os.environ.get('WORKBENCHES_TEST_VAULT') == '1':
                check_service_buttons(home, env)
                run(['/bin/bash', str(services), 'start', 'vault'], env=env)
                assert state('vault') == 'up'
                info = json.loads(run(['docker', 'inspect', vault]))[0]
                mounts = info['Mounts']
                assert len([row for row in mounts if row['Type'] == 'bind']) == 1
                assert mounts[0]['Source'].endswith('/workbenches/vault/jobs')
                assert 'docker.sock' not in json.dumps(mounts)
                assert not any(row['Source'] == str(home) for row in mounts)
                assert info['HostConfig']['ReadonlyRootfs']
                run(['docker', 'stop', vault]); assert state('vault') == 'down'
                run(['/bin/bash', str(services), 'start', 'vault'], env=env)
                assert state('vault') == 'up'
                print('PASS: optional Vault health, restart, and narrow mounts')
        finally:
            for container in (tools, vault):
                subprocess.run(['docker', 'rm', '-f', container], capture_output=True)
            subprocess.run(['docker', 'network', 'rm', network], capture_output=True)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
