#!/usr/bin/env python3
"""Native WSL acceptance. See workstation/README.md before running.

The PTY and native callbacks run on the real WSL host. Benches use the declared
disposable engine so fixed bench names cannot replace an existing installation.
No generated credential is sent to an AI service.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import pwd
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
spec = importlib.util.spec_from_file_location('workstation_acceptance', Path(__file__).with_name('test-workstation-acceptance.py'))
tui = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tui)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--sha', required=True)
    parser.add_argument('--engine', required=True, help='Disposable engine Unix socket, mounted at the same path inside it')
    parser.add_argument('--phase', choices=('all', 'desktop', 'bench'), default='all')
    args = parser.parse_args()
    home, repo, report = Path.home().resolve(), args.repo.resolve(), args.report.resolve()
    assert os.environ.get('WORKBENCHES_WSL_ACCEPTANCE') == '1', 'Explicit native acceptance opt-in required'
    assert 'microsoft-standard' in os.uname().release.lower() and not Path('/.dockerenv').exists(), 'Requires a real WSL 2 host'
    assert home != Path(pwd.getpwuid(os.getuid()).pw_dir).resolve(), 'Requires an isolated HOME'
    assert repo.is_relative_to(home) and not report.is_relative_to(repo), 'Use a private checkout and external report directory'
    assert args.engine.startswith('unix:///') and args.engine != 'unix:///var/run/docker.sock'
    assert os.environ.get('WORKBENCHES_FROZEN') == '1'
    assert not os.environ.get('WORKBENCHES_TEST_NATIVE_TOOLS'), 'Production Tools transport is required'
    for variable in ('WORKBENCHES_TOOLS_CONTAINER', 'WORKBENCHES_VAULT_CONTAINER', 'WORKBENCHES_SERVICES_NETWORK'):
        assert 'qa' in os.environ.get(variable, '') or 'eagle150' in os.environ.get(variable, ''), 'Use unique QA resource names: ' + variable
    report.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, TERM='xterm-256color')
    env.pop('DOCKER_CONTEXT', None)
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
    if args.phase in ('all', 'desktop'):
        assert not run(['bash', '-c', 'command -v codex || true']), 'Fresh CLI phase requires no existing Codex on PATH'
    desktop_id = run(['docker', 'info', '--format', '{{.ID}}'], environment=desktop)
    originals = set(run(['docker', 'ps', '-aq', '--no-trunc'], environment=desktop).splitlines())
    images = set(run(['docker', 'image', 'ls', '--no-trunc', '--format', '{{.Repository}}:{{.Tag}} {{.ID}}'], environment=desktop).splitlines())
    volumes = set(run(['docker', 'volume', 'ls', '-q'], environment=desktop).splitlines())
    lock = (repo / 'config/release-lock.json').read_bytes()
    tui.REPO, tui.REPORT, tui.ENV = repo, report, env
    results = []
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
        started = time.monotonic()
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
    codex = [(tui.TUI, '\x1b[C\x1b[B\x1b[B'), (r'Codex CLI · (?:not installed|needs creds|installed)', ' \n')]
    remove_codex = [(tui.TUI, '\x1b[C\x1b[B\x1b[B'), (r'Codex CLI · (?:needs creds|installed)', 'D\n')]
    project = home / 'projects/wsl-acceptance-project.txt'
    credential = home / '.codex/auth.json'
    baseline = None

    def snapshot():
        return [(path.read_bytes(), path.stat().st_mode & 0o777, path.stat().st_mtime_ns)
                for path in (project, credential, home / '.p10k.zsh')]

    def preserved():
        assert snapshot() == baseline, 'Project, credential, or prompt changed'

    save()
    try:
        if args.phase in ('all', 'desktop'):
            check('tools', lambda: run(['bash', 'scripts/manage-setup-services.sh', 'start', 'tools'], timeout=600, log='tools-start.log'))
            check('loading-cancellation', lambda: terminal('loading-cancellation', [(r'workBenches v1\.5\.0', 'Q')], 130))
            check('empty', lambda: terminal('empty', [(tui.TUI, '\n')]))
            (home / '.zshrc').write_text('# WSL acceptance custom settings\n')
            (home / '.p10k.zsh').write_text('# WSL acceptance custom prompt\n')
            def install_codex():
                output = terminal('codex-install', codex)
                assert (home / '.local/bin/codex').is_file(), 'CLI selection did not install Codex'
                assert 'OpenAI Codex CLI installed' in output
                assert '# WSL acceptance custom settings' in (home / '.zshrc').read_text()
                run([str(home / '.local/bin/codex'), '--version'], log='codex-version.log')
            check('codex-install', install_codex)
            project.write_text('preserve WSL acceptance project\n')
            credential.parent.mkdir(exist_ok=True)
            value = 'sk-test-invalid-wsl-acceptance'
            tui.MARKERS.append(value)
            credential.write_text(json.dumps({'OPENAI_API_KEY': value}) + '\n')
            credential.chmod(0o600)
            baseline = snapshot()
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
            fault = dict(env, NPM_CONFIG_REGISTRY='http://127.0.0.1:9', NPM_CONFIG_FETCH_RETRIES='0')
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
            assert run(['docker', 'info', '--format', '{{.ID}}']) != desktop_id, 'Bench engine must be isolated'
            assert not run(['docker', 'ps', '-aq']), 'Bench phase requires an empty engine'
            benches = sorted(json.loads((repo / 'config/bench-config.json').read_text())['benches'])
            navigation = '\x1b[B' * benches.index('pyBench')
            bench = [(tui.TUI, navigation), (r'pyBench · (?:needs setup|installed|image only)', ' \n')]
            check('bench-install', lambda: terminal('bench-install', bench, timeout=3600))
            def bench_shells():
                run(['bash', 'scripts/wave-container-shell.sh', '--workbenches-root', str(repo), '--shell', 'bash', '--check', 'pyBench'], timeout=300, log='wave-shell-check.log')
                for shell in ('bash', 'zsh'):
                    run(['docker', 'exec', '--user', env['USER'], 'py-bench', shell, '-ic', 'python3 --version && codex --version'], log='bench-' + shell + '.log')
            check('bench-shells', bench_shells)
            check('bench-update', lambda: terminal('bench-update', bench, timeout=3600))
            checkout = repo / 'devBenches/pyBench'
            note = checkout / 'wsl-acceptance-local-work.txt'
            note.write_text('preserve local source work\n')
            def remove_bench():
                terminal('bench-remove', [(tui.TUI, navigation), (r'pyBench · installed', 'D\n')])
                assert subprocess.run(['docker', 'inspect', 'py-bench'], env=env, capture_output=True).returncode != 0
                assert note.read_text() == 'preserve local source work\n'
                run(['docker', 'image', 'inspect', 'workbench-base:latest', 'dev-bench-base:latest'])
                if baseline:
                    preserved()
            check('bench-remove', remove_bench)
            def frozen_guard():
                terminal('frozen-local-work-guard', bench, 1)
                assert note.read_text() == 'preserve local source work\n'
                pinned = next(row['commit'] for row in json.loads(lock)['repositories'] if row['path'] == 'devBenches/pyBench')
                assert run(['git', '-C', str(checkout), 'rev-parse', 'HEAD']) == pinned
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
