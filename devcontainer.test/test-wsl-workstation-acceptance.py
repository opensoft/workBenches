#!/usr/bin/env python3
"""Native WSL acceptance. See workstation/README.md before running.

The PTY and native callbacks run on the real WSL host. Benches use the declared
disposable engine so fixed bench names cannot replace an existing installation.
No generated credential is sent to an AI service.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import pwd
import re
import shutil
import socket
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
spec = importlib.util.spec_from_file_location('workstation_acceptance', Path(__file__).with_name('test-workstation-acceptance.py'))
tui = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tui)

# A fresh frozen assembly has no populated bench submodule or runtime yet.
# Its actual TUI state is "not installed", before setup can prepare the source.
BENCH_SELECTABLE = r'pyBench · (?:not installed|needs setup|Ready|image only)'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--sha', required=True)
    parser.add_argument('--engine', required=True, help='Disposable engine Unix socket, mounted at the same path inside it')
    parser.add_argument('--platform', choices=('wsl', 'arch'), default='wsl')
    parser.add_argument('--phase', choices=('all', 'desktop', 'bench', 'services', 'guard'), default='all')
    parser.add_argument('--resume', action='store_true', help='Continue matching evidence after correcting a QA driver or environment issue')
    args = parser.parse_args()
    home, repo, report = Path.home().resolve(), args.repo.resolve(), args.report.resolve()
    assert os.environ.get('WORKBENCHES_WSL_ACCEPTANCE') == '1', 'Explicit native acceptance opt-in required'
    assert not Path('/.dockerenv').exists(), 'Requires a native QA host'
    if args.platform == 'wsl':
        assert 'microsoft-standard' in os.uname().release.lower(), 'Requires a real WSL 2 host'
    else:
        release = Path('/etc/os-release').read_text()
        assert any(line in release.splitlines() for line in ('ID=arch', 'ID=manjaro', 'ID=endeavouros')), 'Requires native Arch-family Linux'
    assert os.getuid() != 0, 'Run as the normal WSL user to exercise mapped-user access'
    assert home != Path(pwd.getpwuid(os.getuid()).pw_dir).resolve(), 'Requires an isolated HOME'
    if args.phase in ('all', 'bench', 'guard'):
        assert not home.is_relative_to(Path('/tmp').resolve()), 'DinD masks /tmp; put the isolated bench home under the user cache'
    assert repo.is_relative_to(home) and not report.is_relative_to(repo), 'Use a private checkout and external report directory'
    assert args.engine.startswith('unix:///') and args.engine != 'unix:///var/run/docker.sock'
    assert os.environ.get('WORKBENCHES_FROZEN') == '1'
    assert not os.environ.get('WORKBENCHES_TEST_NATIVE_TOOLS'), 'Production Tools transport is required'
    for variable in ('WORKBENCHES_TOOLS_CONTAINER', 'WORKBENCHES_VAULT_CONTAINER', 'WORKBENCHES_SERVICES_NETWORK'):
        assert 'qa' in os.environ.get(variable, '') or 'eagle150' in os.environ.get(variable, ''), 'Use unique QA resource names: ' + variable
    for variable in ('WORKBENCHES_TOOLS_IMAGE', 'WORKBENCHES_VAULT_IMAGE'):
        assert 'qa' in os.environ.get(variable, '') or 'eagle150' in os.environ.get(variable, ''), 'Use explicit QA image tags: ' + variable
    report.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, TERM='xterm-256color', BUILDKIT_PROGRESS='plain')
    env.pop('DOCKER_CONTEXT', None)
    env.pop('DOCKER_HOST', None)
    env.pop('WORKBENCHES_DOCKER_ENDPOINT', None)
    desktop = dict(env)
    desktop.pop('DOCKER_HOST', None)

    def run(argv, *, environment=None, timeout=120, log=None):
        result = subprocess.run(argv, cwd=repo, env=environment or env, capture_output=True, text=True, timeout=timeout)
        if log:
            (report / log).write_text(result.stdout + result.stderr)
        assert result.returncode == 0, f'{Path(argv[0]).name} failed ({result.returncode}); see {log or "the private report"}'
        return result.stdout.strip()

    assert run(['git', 'rev-parse', 'HEAD']) == args.sha, 'Unexpected tested commit'
    assert not run(['git', 'status', '--porcelain', '--ignore-submodules=all']), 'Requires a clean assembly checkout'
    assert run(['npm', 'prefix', '--global']) == str(home / '.local'), 'npm must target the private home'
    if args.phase in ('all', 'desktop') and not args.resume:
        assert not run(['bash', '-c', 'command -v codex || true']), 'Fresh CLI phase requires no existing Codex on PATH'
    desktop_id = run(['docker', 'info', '--format', '{{.ID}}'], environment=desktop)
    (report / 'native-environment.json').write_text(json.dumps({
        'sha': args.sha, 'host': os.uname().nodename, 'kernel': os.uname().release,
        'uid': os.getuid(), 'gid': os.getgid(), 'groups': os.getgroups(),
        'node': run(['node', '--version']), 'npm': run(['npm', '--version']),
        'npmExecutable': shutil.which('npm'), 'desktopEngine': desktop_id,
        'docker': run(['docker', 'version', '--format', '{{.Client.Version}}/{{.Server.Version}}'], environment=desktop),
    }, indent=2) + '\n')
    originals = set(run(['docker', 'ps', '-aq', '--no-trunc'], environment=desktop).splitlines())
    # These exact managed QA tags can legitimately change when startup rebuilds
    # its helpers. Every other existing image/tag remains protected.
    helper_images = {env['WORKBENCHES_TOOLS_IMAGE'], env['WORKBENCHES_VAULT_IMAGE']}
    images = {row for row in run(['docker', 'image', 'ls', '--no-trunc', '--format', '{{.Repository}}:{{.Tag}} {{.ID}}'], environment=desktop).splitlines()
              if row.rsplit(' ', 1)[0] not in helper_images}
    volumes = set(run(['docker', 'volume', 'ls', '-q'], environment=desktop).splitlines())
    lock = (repo / 'config/release-lock.json').read_bytes()
    tui.REPO, tui.REPORT, tui.ENV = repo, report, env
    value = 'sk-test-invalid-wsl-acceptance'
    tui.MARKERS.append(value)
    results = []
    if args.resume or args.phase in ('bench', 'services', 'guard'):
        names = (args.phase,) if args.resume else (('bench', 'all', 'desktop') if args.phase in ('services', 'guard') else ('desktop', 'all'))
        previous = next((report / ('wsl-' + name + '-results.json') for name in names
                         if (report / ('wsl-' + name + '-results.json')).is_file()), None)
        if previous:
            evidence = json.loads(previous.read_text())
            assert evidence['sha'] == args.sha and evidence['desktopEngine'] == desktop_id, 'Desktop evidence must match this candidate and engine'
            results = [row for row in evidence['results'] if row['case'] != 'preservation']
        else:
            assert not args.resume, 'No matching report to resume'
    required = ['tools', 'loading-cancellation', 'empty', 'codex-install', 'codex-update', 'queued-cancellation',
                'failed-update', 'codex-remove', 'codex-reinstall', 'host-shells', 'vault', 'bench-install',
                'bench-shells', 'bench-update', 'bench-remove', 'frozen-local-work-guard', 'preservation']

    def save():
        (report / ('wsl-' + args.phase + '-results.json')).write_text(json.dumps({
            'sha': args.sha, 'phase': args.phase, 'host': os.uname().nodename,
            'kernel': os.uname().release, 'desktopEngine': desktop_id,
            'frozenSourceMode': True, 'results': results,
            'complete': all(any(row['case'] == name and row['status'] == 'passed' for row in results) for name in required),
            'notRun': [name for name in required if not any(row['case'] == name for row in results)],
        }, indent=2) + '\n')

    def check(name, action):
        if args.resume and any(row['case'] == name and row['status'] == 'passed' for row in results):
            print('PREVIOUSLY VERIFIED ' + name, flush=True)
            return
        started = time.monotonic()
        results[:] = [row for row in results if row['case'] != name]
        try:
            action()
        except Exception as error:
            # Assertions contain only our diagnostics, never command output or credentials.
            results.append({'case': name, 'status': 'failed', 'errorType': type(error).__name__,
                            'durationSeconds': round(time.monotonic() - started, 2)})
            save()
            raise
        results.append({'case': name, 'status': 'passed', 'durationSeconds': round(time.monotonic() - started, 2)})
        save()
        print('VERIFIED ' + name, flush=True)

    def terminal(name, replies, expected=0, environment=None, timeout=900):
        return tui.terminal('wsl-' + name, replies, expected, env=environment or env, timeout=timeout)

    # Wait for the selected row's inventory as well as required services. A
    # ready Docker/Tools header alone does not mean the CLI/bench row is loaded.
    codex = [(tui.TUI, '\x1b[D\x1b[D\x1b[B\x1b[C\x1b[B\x1b[B'), (r'Codex CLI · (?:not installed|needs creds|Ready)', ' \n')]
    remove_codex = [(tui.TUI, '\x1b[D\x1b[D\x1b[B\x1b[C\x1b[B\x1b[B'), (r'Codex CLI · (?:needs creds|Ready)', 'D\n')]
    project = home / 'projects/wsl-acceptance-project.txt'
    credential = home / '.codex/auth.json'
    baseline = None

    def fixture(path, content):
        if path.exists() or path.is_symlink():
            assert not path.is_symlink() and path.read_text() == content, 'Refusing to replace an existing QA fixture: ' + path.name
        else:
            path.write_text(content)

    def snapshot():
        return [[hashlib.sha256(path.read_bytes()).hexdigest(), path.stat().st_mode & 0o777, path.stat().st_mtime_ns]
                for path in (project, credential, home / '.p10k.zsh')]

    def preserved():
        assert snapshot() == baseline, 'Project, credential, or prompt changed'

    def frozen_guard():
        checkout = repo / 'devBenches/pyBench'
        note = checkout / 'wsl-acceptance-local-work.txt'
        fixture(note, 'preserve local source work\n')
        benches = sorted(json.loads((repo / 'config/bench-config.json').read_text())['benches'])
        replies = [(tui.TUI, '\x1b[B' * benches.index('pyBench')),
                   (r'pyBench · (?:needs setup|Ready|image only)', ' \n')]
        output = terminal('frozen-local-work-guard', replies, 1)
        assert 'has local changes; save them before using a frozen release' in output
        assert note.read_text() == 'preserve local source work\n'
        pinned = next(row['commit'] for row in json.loads(lock)['repositories'] if row['path'] == 'devBenches/pyBench')
        assert run(['git', '-C', str(checkout), 'rev-parse', 'HEAD']) == pinned

    save()
    try:
        if args.phase == 'guard':
            if project.exists() and credential.exists():
                baseline = snapshot()
            env['DOCKER_HOST'] = args.engine
            for variable in ('WORKBENCHES_TOOLS_CONTAINER', 'WORKBENCHES_SERVICES_NETWORK'):
                env[variable] += '-bench'
            assert run(['docker', 'info', '--format', '{{.ID}}']) != desktop_id, 'Guard engine must be isolated'
            check('frozen-local-work-guard', frozen_guard)
        if args.phase == 'services':
            if project.exists() and credential.exists():
                baseline = snapshot()
            check('tools', lambda: run(['bash', 'scripts/manage-setup-services.sh', 'start', 'tools'], timeout=600, log='tools-start.log'))
            check('vault', lambda: run(['bash', 'scripts/manage-setup-services.sh', 'start', 'vault'], timeout=1800, log='vault-start.log'))
        if args.phase in ('all', 'desktop'):
            check('tools', lambda: run(['bash', 'scripts/manage-setup-services.sh', 'start', 'tools'], timeout=600, log='tools-start.log'))
            check('loading-cancellation', lambda: terminal('loading-cancellation', [(r'workBenches v' + re.escape((repo / 'VERSION').read_text().strip()), 'Q')], 130))
            check('empty', lambda: terminal('empty', [(tui.TUI, '\n')]))
            if not args.resume:
                fixture(home / '.zshrc', '# WSL acceptance custom settings\n')
                fixture(home / '.p10k.zsh', '# WSL acceptance custom prompt\n')
            def install_codex():
                output = terminal('codex-install', codex)
                assert (home / '.local/bin/codex').is_file(), 'CLI selection did not install Codex'
                assert 'OpenAI Codex CLI installed' in output
                assert '# WSL acceptance custom settings' in (home / '.zshrc').read_text()
                run([str(home / '.local/bin/codex'), '--version'], log='codex-version.log')
            check('codex-install', install_codex)
            if not args.resume:
                fixture(project, 'preserve WSL acceptance project\n')
                credential.parent.mkdir(exist_ok=True)
                fixture(credential, json.dumps({'OPENAI_API_KEY': value}) + '\n')
                credential.chmod(0o600)
            witness = report / 'preservation-witness.json'
            if args.resume and witness.is_file():
                baseline = json.loads(witness.read_text())
                preserved()
            else:
                assert project.read_text() == 'preserve WSL acceptance project\n'
                assert json.loads(credential.read_text()) == {'OPENAI_API_KEY': value}
                assert (home / '.p10k.zsh').read_text() == '# WSL acceptance custom prompt\n'
                baseline = snapshot()
                witness.write_text(json.dumps(baseline) + '\n')
            def update_codex():
                assert 'Codex CLI updated' in terminal('codex-update', codex)
                preserved()
            check('codex-update', update_codex)
            def cancel_queued():
                binary = (home / '.local/bin/codex').resolve()
                before = (binary.stat().st_mtime_ns, binary.read_bytes())
                terminal('queued-cancellation', [codex[0], (codex[1][0], ' PPQ')], 130)
                assert (binary.stat().st_mtime_ns, binary.read_bytes()) == before
                preserved()
            check('queued-cancellation', cancel_queued)
            # Reserve an unused, non-listening port. Port 9 can silently drop
            # SYNs on WSL instead of returning a prompt connection refusal.
            with socket.socket() as registry:
                registry.bind(('127.0.0.1', 0))
                fault = dict(env, NPM_CONFIG_REGISTRY=f'http://127.0.0.1:{registry.getsockname()[1]}',
                             NPM_CONFIG_FETCH_RETRIES='0', NPM_CONFIG_FETCH_TIMEOUT='5000')
                def failed_update():
                    assert 'update failed' in terminal('failed-update', codex, 1, environment=fault)
                    preserved()
                check('failed-update', failed_update)
            def remove():
                terminal('codex-remove', remove_codex)
                assert not (home / '.local/bin/codex').exists(), 'Codex launcher remains'
                preserved()
            check('codex-remove', remove)
            check('codex-reinstall', lambda: (terminal('codex-reinstall', codex), preserved()))
            check('host-shells', lambda: [run([shell, '-ic', 'codex --version'], log=shell + '-startup.log') for shell in ('bash', 'zsh')])
            check('vault', lambda: run(['bash', 'scripts/manage-setup-services.sh', 'start', 'vault'], timeout=1800, log='vault-start.log'))
        if args.phase in ('all', 'bench'):
            if baseline is None and project.exists() and credential.exists():
                baseline = snapshot()
            env['DOCKER_HOST'] = args.engine
            for variable in ('WORKBENCHES_TOOLS_CONTAINER', 'WORKBENCHES_SERVICES_NETWORK'):
                env[variable] += '-bench'
            benches = sorted(json.loads((repo / 'config/bench-config.json').read_text())['benches'])
            navigation = '\x1b[B' * benches.index('pyBench')
            bench = [(tui.TUI, navigation), (BENCH_SELECTABLE, ' \n')]
            unrelated = None
            def install_bench():
                nonlocal unrelated
                assert run(['docker', 'info', '--format', '{{.ID}}']) != desktop_id, 'Bench engine must be isolated'
                assert not run(['docker', 'ps', '-aq']), 'Bench phase requires an empty engine'
                for image in ('py-bench:latest', 'py-bench:' + env['USER']):
                    assert subprocess.run(['docker', 'image', 'inspect', image], env=env, capture_output=True).returncode != 0, 'Fresh bench phase requires no selected bench image: ' + image
                run(['docker', 'pull', 'busybox:1.37.0'], timeout=300, log='unrelated-image.log')
                run(['docker', 'tag', 'busybox:1.37.0', 'wsl-acceptance-unrelated:fixture'])
                run(['docker', 'volume', 'create', 'wsl-acceptance-unrelated'])
                unrelated = run(['docker', 'run', '-d', '--name', 'wsl-acceptance-unrelated',
                                 '--mount', 'type=volume,src=wsl-acceptance-unrelated,dst=/data',
                                 'wsl-acceptance-unrelated:fixture', 'sh', '-c',
                                 'printf preserve-unrelated-volume > /data/marker; exec sleep 86400'])
                assert 'pyBench is ready (launch verified)' in terminal('bench-install', bench, timeout=3600)
            check('bench-install', install_bench)
            def bench_shells():
                run(['bash', 'scripts/wave-container-shell.sh', '--workbenches-root', str(repo), '--shell', 'bash', '--check', 'pyBench'], timeout=300, log='wave-shell-check.log')
                for shell in ('bash', 'zsh'):
                    run(['docker', 'exec', '--user', env['USER'], 'py-bench', shell, '-ic', 'python3 --version && codex --version'], log='bench-' + shell + '.log')
            check('bench-shells', bench_shells)
            def update_bench():
                # Setup deliberately preserves a running bench. Stop only this
                # test's bench in the already verified disposable engine.
                run(['docker', 'stop', '--time', '10', 'py-bench'])
                assert 'pyBench is ready (launch verified)' in terminal('bench-update', bench, timeout=3600)
                bench_shells()
            check('bench-update', update_bench)
            checkout = repo / 'devBenches/pyBench'
            note = checkout / 'wsl-acceptance-local-work.txt'
            fixture(note, 'preserve local source work\n')
            def remove_bench():
                terminal('bench-remove', [(tui.TUI, navigation), (r'pyBench · Ready', 'D\n')])
                assert subprocess.run(['docker', 'inspect', 'py-bench'], env=env, capture_output=True).returncode != 0
                for image in ('py-bench:latest', 'py-bench:' + env['USER']):
                    assert subprocess.run(['docker', 'image', 'inspect', image], env=env, capture_output=True).returncode != 0, 'Removed bench image remains: ' + image
                assert note.read_text() == 'preserve local source work\n'
                run(['docker', 'image', 'inspect', 'workbench-base:latest', 'dev-bench-base:latest'])
                assert run(['docker', 'inspect', '--format', '{{.Id}}', 'wsl-acceptance-unrelated']) == unrelated
                assert run(['docker', 'exec', 'wsl-acceptance-unrelated', 'cat', '/data/marker']) == 'preserve-unrelated-volume'
                run(['docker', 'image', 'inspect', 'wsl-acceptance-unrelated:fixture'])
                if baseline:
                    preserved()
            check('bench-remove', remove_bench)
            check('frozen-local-work-guard', frozen_guard)
    finally:
        def preservation():
            assert originals <= set(run(['docker', 'ps', '-aq', '--no-trunc'], environment=desktop).splitlines())
            assert images <= set(run(['docker', 'image', 'ls', '--no-trunc', '--format', '{{.Repository}}:{{.Tag}} {{.ID}}'], environment=desktop).splitlines())
            assert volumes <= set(run(['docker', 'volume', 'ls', '-q'], environment=desktop).splitlines())
            assert (repo / 'config/release-lock.json').read_bytes() == lock
            if baseline:
                preserved()
        check('preservation', preservation)


if __name__ == '__main__':
    main()
