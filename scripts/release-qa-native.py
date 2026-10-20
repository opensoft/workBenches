#!/usr/bin/env python3
"""Native Arch/WSL adapter for dedicated disposable QA workers, never a daily home."""
import json
import os
from pathlib import Path
import pwd
import shutil
import signal
import subprocess
import sys
import tempfile

from release_validation import ValidationError, read, failure_location, encrypt_fixture_diagnostics, NATIVE_CASES

HERE = Path(__file__).resolve().parents[1]


def native_diagnostics(repo, report, output, suite, destination, certificate):
    """Keep a safe case identifier and optional ciphertext before HOME cleanup."""
    result = {}
    results_file = report / 'wsl-all-results.json'
    try:
        value = read(results_file)
        failed = [row['case'] for row in value.get('results', [])
                  if row.get('status') == 'failed' and row.get('case') in NATIVE_CASES]
        if failed: result['case'] = failed[-1]
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        pass
    if not certificate or suite not in ('arch-native', 'wsl-native'): return result
    try:
        if (not destination.is_absolute() or any(p.is_symlink() for p in [destination, *destination.parents])
                or destination.resolve().is_relative_to(repo.resolve())):
            return result
        destination.mkdir(parents=True, exist_ok=True, mode=0o700)
        if destination.stat().st_uid != os.getuid() or destination.stat().st_mode & 0o077:
            return result
        driver = report / 'driver-failure.log'
        output.seek(0, 2); output.seek(max(0, output.tell() - 8 * 1024 * 1024))
        driver.write_bytes(output.read()); driver.chmod(0o600)
        files = [('native-driver.log', driver), ('driver-results.json', results_file)]
        logs = [p for p in (repo / 'logs').glob('setup*.log') if p.is_file() and not p.is_symlink()]
        if logs: files.append(('setup.log', max(logs, key=lambda p: p.stat().st_mtime)))
        files.append(('bench-terminal.txt', report / 'wsl-bench-install.txt'))
        path = destination / (suite + '-debug.cms')
        encrypted = encrypt_fixture_diagnostics(files, certificate, path)
        if encrypted:
            result['encryptedDiagnostics'] = dict(encrypted, file=path.name)
    except (OSError, ValueError, subprocess.SubprocessError):
        # Optional diagnosis never replaces the actual acceptance failure.
        pass
    return result


def main():
    def terminate(*_): raise SystemExit(143)
    signal.signal(signal.SIGTERM, terminate)
    request = json.load(sys.stdin)
    kind = {'arch-native': 'arch', 'wsl-native': 'wsl'}.get(request['suite'])
    if not kind: raise ValidationError('unsupported_native_suite')
    settings_path = Path(os.environ.get('WB_NATIVE_QA_SETTINGS', '/etc/workbenches/native-qa.json'))
    if settings_path.is_symlink() or settings_path.stat().st_uid != 0 or settings_path.stat().st_mode & 0o022:
        raise ValidationError('root_owned_native_settings_required')
    settings = read(settings_path)
    marker = Path('/etc/workbenches/disposable-qa-id')
    if not marker.is_file() or marker.stat().st_uid != 0 or marker.stat().st_mode & 0o022:
        raise ValidationError('root_owned_disposable_marker_required')
    if settings.get('kind') != kind or marker.read_text().strip() != request['resetId']:
        raise ValidationError('dedicated_reset_qa_worker_required')
    if os.getuid() == 0 or Path('/.dockerenv').exists(): raise ValidationError('native_normal_user_required')
    if kind == 'wsl' and 'microsoft' not in os.uname().release.lower(): raise ValidationError('real_wsl2_required')
    if kind == 'arch':
        release = dict(line.split('=', 1) for line in Path('/etc/os-release').read_text().splitlines() if '=' in line)
        if release.get('ID', '').strip('"') not in ('arch', 'manjaro', 'endeavouros'): raise ValidationError('real_arch_required')
    original_home = Path(pwd.getpwuid(os.getuid()).pw_dir).resolve()
    base = original_home / '.cache/workbenches-release-qa'
    base.mkdir(parents=True, exist_ok=True, mode=0o700)
    cases = []; cleanup = 'failed'
    with tempfile.TemporaryDirectory(prefix='qa-', dir=base) as temp:
        directory = Path(temp); home = directory / 'home'; home.mkdir()
        repo = home / 'projects/workBenches'; repo.parent.mkdir()
        report = directory / 'private-report'; report.mkdir(mode=0o700)
        project = 'wb-native-qa-' + directory.name[3:]
        env = {k: v for k, v in os.environ.items() if k in
            ('TERM', 'LANG', 'DISPLAY', 'WAYLAND_DISPLAY', 'XDG_RUNTIME_DIR', 'DBUS_SESSION_BUS_ADDRESS', 'SHELL', 'SYSTEMROOT', 'WINDIR')
            or k.startswith(('LC_', 'WSL_'))}
        env.update(HOME=str(home), USER=pwd.getpwuid(os.getuid()).pw_name, XDG_CONFIG_HOME=str(home / '.config'),
            XDG_CACHE_HOME=str(home / '.cache'), XDG_DATA_HOME=str(home / '.local/share'), TMPDIR=str(home / 'tmp'),
            AGENT_PROTOCOL_ROOT=str(home / '.agents'), NPM_CONFIG_USERCONFIG=str(home / '.npmrc'),
            npm_config_prefix=str(home / '.local'), WORKBENCHES_FROZEN='1', WORKBENCHES_WSL_ACCEPTANCE='1',
            WORKBENCHES_SKIP_WAVE_WIDGETS='1', WORKBENCHES_SKIP_ESTATE_COMMANDS='1',
            WORKBENCHES_SKIP_WORKSPACE_REPO='1', WORKBENCHES_SKIP_PROJECT_COMMAND='1',
            GIT_CONFIG_GLOBAL='/dev/null', GIT_CONFIG_NOSYSTEM='1', GIT_TERMINAL_PROMPT='0',
            WORKBENCHES_TOOLS_CONTAINER=project + '-tools', WORKBENCHES_VAULT_CONTAINER=project + '-vault',
            WORKBENCHES_SERVICES_NETWORK=project + '-services', WORKBENCHES_TOOLS_IMAGE='workbenches/tools:' + project,
            WORKBENCHES_VAULT_IMAGE='workbenches/vault:' + project)
        for variable in ('DOCKER_HOST', 'DOCKER_CONTEXT', 'WORKBENCHES_DOCKER_ENDPOINT', 'WORKBENCHES_TEST_NATIVE_TOOLS', 'SSH_AUTH_SOCK'):
            env.pop(variable, None)
        Path(env['TMPDIR']).mkdir()
        env['PATH'] = str(home / '.local/bin') + ':' + settings['cleanPath']
        diagnostic_snapshot = {}
        def run(argv, timeout=600, environment=None, phase="native-command"):
            # Plaintext is deleted with HOME; only operator-encrypted fixtures
            # may survive a failed native run in the separate diagnostics path.
            with tempfile.TemporaryFile() as output:
                try:
                    result = subprocess.run(argv, env=environment or env, stdout=output, stderr=output, timeout=timeout)
                    if not result.returncode: return
                    diagnostic = dict(phase=phase, exitCode=result.returncode)
                except subprocess.TimeoutExpired:
                    diagnostic = dict(phase=phase, exception='TimeoutExpired')
                output.seek(0, 2); size = output.tell(); output.seek(max(0, size - 256 * 1024))
                diagnostic.update(failure_location(output.read()))
                # A subsequent cleanup failure must not overwrite the first
                # failed command's encrypted diagnostic bytes.
                if not diagnostic_snapshot.get('encryptedDiagnostics'):
                    diagnostic_snapshot.update(native_diagnostics(repo, report, output, request['suite'],
                        Path(os.environ.get('WB_QA_DIAGNOSTICS_DIR', str(base / 'diagnostics'))),
                        os.environ.get('OPENBENCHES_QA_FAILURE_CERT_PEM')))
                diagnostic.update(diagnostic_snapshot)
                print('NATIVE_QA_FAILURE ' + json.dumps(diagnostic), file=sys.stderr, flush=True)
                raise ValidationError('native_acceptance_failed')
        run(['git', 'clone', '--no-hardlinks', '--no-checkout', request['root'], str(repo)])
        run(['git', '-C', str(repo), 'checkout', '--detach', request['source']['commit']])
        socket = directory / 'socket'; socket.mkdir()
        override = directory / 'compose.json'
        volumes = [f'{home}:{home}', f'{socket}:/var/run', f'{socket}:{socket}']
        for path in ('/mnt/wslg', '/usr/lib/wsl'):
            if kind == 'wsl' and Path(path).exists(): volumes.append(path + ':' + path + ':ro')
        override.write_text(json.dumps({'services': {'acceptance-engine': {'volumes': volumes}}}))
        compose = ['docker', 'compose', '-p', project, '-f', str(repo / 'devcontainer.test/docker-compose.yml'), '-f', str(override), '--profile', 'workstation-acceptance']
        try:
            if kind == 'arch':
                # This is the disposable account's OS shell, never Brett's home.
                run(['sudo', '-n', 'true'])
                # Shell setup intentionally creates .zshrc/.p10k links. The
                # workstation driver seeds its own custom settings and refuses
                # to overwrite existing links. Exercise both flows with separate
                # private homes, preserving both sets of assertions.
                shell_home = directory / 'shell-home'; shell_home.mkdir()
                shell_env = dict(env, HOME=str(shell_home),
                    XDG_CONFIG_HOME=str(shell_home / '.config'),
                    XDG_CACHE_HOME=str(shell_home / '.cache'),
                    XDG_DATA_HOME=str(shell_home / '.local/share'),
                    AGENT_PROTOCOL_ROOT=str(shell_home / '.agents'),
                    NPM_CONFIG_USERCONFIG=str(shell_home / '.npmrc'),
                    npm_config_prefix=str(shell_home / '.local'))
                run(['bash', str(repo / 'scripts/setup-shell.sh')], 1200, shell_env, 'shell-install')
                cases.append('shell-install')
                run(['bash', str(repo / 'scripts/setup-shell.sh')], 1200, shell_env, 'shell-repeat')
                cases.append('shell-repeat')
            run([*compose, 'up', '-d', 'acceptance-engine'])
            run(['python3', str(HERE / 'devcontainer.test/test-wsl-workstation-acceptance.py'),
                 '--platform', kind, '--repo', str(repo), '--report', str(report), '--sha', request['source']['commit'],
                 '--engine', 'unix://' + str(socket / 'docker.sock'), '--phase', 'all'], 5400, phase='workstation-driver')
            result = read(report / 'wsl-all-results.json')
            if result.get('sha') != request['source']['commit'] or result.get('complete') is not True or result.get('notRun'):
                raise ValidationError('native_driver_incomplete')
            cases += ['fresh-install', 'repeat-install', 'cancel-preserve'] if kind == 'arch' else ['desktop', 'bench', 'services', 'guard', 'preservation']
        finally:
            try:
                run([*compose, 'down', '--volumes', '--remove-orphans'])
                run(['docker', 'rm', '-f', project + '-tools'])
                # Vault is not always created; inspect before removing.
                found = subprocess.run(['docker', 'inspect', project + '-vault'], env=env, capture_output=True).returncode == 0
                if found: run(['docker', 'rm', '-f', project + '-vault'])
                network = subprocess.run(['docker', 'network', 'inspect', project + '-services'], env=env, capture_output=True).returncode == 0
                if network: run(['docker', 'network', 'rm', project + '-services'])
                cleanup = 'passed'; cases.append('cleanup')
            except (OSError, ValueError, subprocess.TimeoutExpired): cleanup = 'failed'
        expected = request['requiredCases']
        if cleanup != 'passed' or set(cases) != set(expected): raise ValidationError('native_cleanup_or_cases_incomplete')
        print(json.dumps(dict(source=request['source'], run=request['run'], suite=request['suite'], resetId=request['resetId'],
            cases=[dict(id=name, status='passed') for name in expected], cleanup='passed', status='passed')))


if __name__ == '__main__':
    try: main()
    except (ValueError, OSError, KeyError, TypeError, subprocess.TimeoutExpired):
        # Do not reflect paths, raw command output, credentials or browser state.
        print('Native QA prerequisites, acceptance or cleanup failed.', file=sys.stderr)
        raise SystemExit(1)
