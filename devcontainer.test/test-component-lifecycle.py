#!/usr/bin/env python3
"""Install/uninstall/reinstall evidence through an isolated declared Docker bench."""
import json
import os
from pathlib import Path
import pty
import re
import select
import shutil
import subprocess
import tempfile
import time
from terminal_screen import terminal_screen

SOURCE = Path('/source')


def run(argv, **kwargs):
    return subprocess.run(argv, check=True, capture_output=True, text=True, timeout=60, **kwargs).stdout.strip()


def setup_tui(repo, keys, env, expected_status=0):
    master, slave = pty.openpty()
    process = subprocess.Popen(['bash', str(repo / 'setup.sh')], cwd=repo, env=env,
                               stdin=slave, stdout=slave, stderr=slave, start_new_session=True)
    os.close(slave)
    output = b''; submitted = False; terminal_closed = False
    deadline = time.monotonic() + 90
    try:
        while time.monotonic() < deadline:
            ready, _, _ = select.select([master], [], [], 0.2)
            if ready:
                try: chunk = os.read(master, 65536)
                except OSError:
                    terminal_closed = True
                    break
                if not chunk:
                    terminal_closed = True
                    break
                output += chunk
                text = terminal_screen(output)
                if 'Navigation:' in text and re.search(r'REQUIREMENTS · (\d+)/\1 ready', text) and not submitted:
                    os.write(master, keys); submitted = True
            if process.poll() is not None and not ready: break
        # PTY EOF can arrive before the kernel reports the child exit. Reap it
        # before deciding that setup hung; keep the bounded wait for real hangs.
        if terminal_closed and process.poll() is None:
            try: process.wait(timeout=5)
            except subprocess.TimeoutExpired: pass
        if process.poll() is None:
            process.kill()
            raise AssertionError('Setup did not finish: ' + output.decode(errors='replace')[-2500:])
        assert process.wait() == expected_status, output.decode(errors='replace')[-3500:]
        assert submitted
        return output.decode(errors='replace')
    finally:
        if process.poll() is None: process.kill(); process.wait()
        os.close(master)


def main():
    assert os.environ.get('WORKBENCHES_LIFECYCLE_TEST') == '1', 'Run through the declared component-lifecycle service'
    assert not run(['docker', 'ps', '-aq']), 'This test requires an empty isolated Docker engine'
    with tempfile.TemporaryDirectory(prefix='component-lifecycle-') as temporary:
        directory = Path(temporary); home = directory / 'home'; home.mkdir()
        repo = directory / 'workBenches'; repo.mkdir()
        shutil.copytree(SOURCE / 'scripts', repo / 'scripts', ignore=shutil.ignore_patterns('__pycache__'))
        shutil.copytree(SOURCE / 'config', repo / 'config')
        shutil.copytree(SOURCE / 'credential-container', repo / 'credential-container', ignore=shutil.ignore_patterns('__pycache__'))
        for name in ('setup.sh', 'bootstrap.sh'): shutil.copy(SOURCE / name, repo / name)
        (repo / 'config/bench-config.json').write_text(json.dumps({'benches': {'pyBench': {'path': 'devBenches/pyBench', 'url': 'https://github.com/opensoft/pyBench.git'}}}))
        checkout = repo / 'devBenches/pyBench'; checkout.mkdir(parents=True)
        run(['git', 'init', '-q', str(checkout)])
        run(['git', '-C', str(checkout), 'remote', 'add', 'origin', 'https://github.com/opensoft/pyBench.git'])
        (checkout / '.devcontainer').mkdir()
        note = checkout / 'local-work.txt'; note.write_text('preserve local work')
        projects = home / 'projects'; projects.mkdir()
        project = projects / 'project.txt'; project.write_text('preserve project')
        credential = home / '.codex/auth.json'; credential.parent.mkdir()
        credential.write_text('{"OPENAI_API_KEY":"sk-test-invalid-lifecycle-fixture"}')
        credential.chmod(0o600)
        env = dict(os.environ, HOME=str(home), USER='node', XDG_CONFIG_HOME=str(home / '.config'),
                   XDG_DATA_HOME=str(home / '.local/share'), AGENT_PROTOCOL_ROOT=str(home / '.agents'),
                   PATH=str(home / '.local/bin') + ':' + os.environ['PATH'], TERM='xterm', WORKBENCHES_TEST_NATIVE_TOOLS='1',
                   npm_config_prefix=str(home / '.local'))
        package = directory / 'codex-fixture'; package.mkdir()
        (package / 'package.json').write_text(json.dumps({'name': '@openai/codex', 'version': '0.0.0', 'bin': {'codex': 'cli.js'}}))
        (package / 'cli.js').write_text('#!/usr/bin/env node\nconsole.log("fixture Codex CLI");\n')
        run(['npm', 'install', '--global', '--ignore-scripts', str(package)], env=env)
        run(['docker', 'pull', 'busybox:1.37.0'])
        run(['docker', 'tag', 'busybox:1.37.0', 'workbench-base:latest'])
        run(['docker', 'tag', 'busybox:1.37.0', 'dev-bench-base:latest'])
        volume = 'component-lifecycle-data'
        run(['docker', 'volume', 'create', volume])
        run(['docker', 'run', '--rm', '--mount', f'type=volume,src={volume},dst=/data', 'busybox:1.37.0', 'sh', '-c', 'echo preserve-volume > /data/marker'])

        def install_runtime():
            for tag in ('latest', 'node'):
                run(['docker', 'tag', 'busybox:1.37.0', 'py-bench:' + tag])
            run(['docker', 'run', '-d', '--name', 'py-bench', '--label',
                 'com.docker.compose.project.working_dir=' + str(checkout),
                 '--mount', f'type=bind,src={projects},dst=/workspace/projects',
                 '--mount', f'type=volume,src={volume},dst=/data',
                 'py-bench:node', 'sleep', '3600'])

        def statuses():
            command = 'source scripts/interactive-setup.sh; init_components; load_statuses; printf "%s:%s\\n" "${component_status[bench_pyBench]}" "${component_status[codex_cli]}"'
            return run(['bash', '-c', command], cwd=repo, env=env).splitlines()[-1]

        install_runtime()
        initial = statuses()
        assert initial == 'installed:installed', initial
        requirements_output = setup_tui(repo, b'\x1b[CPQ', env, expected_status=130)
        for text in ('workBenches v', 'Linux', 'REQUIREMENTS', 'Docker', 'REQUIRED SOFTWARE',
                     'OPTIONAL VAULT', 'Vault', 'G Profiles', 'Setup cancelled'):
            assert text in requirements_output, requirements_output[-3500:]
        profiles_output = setup_tui(repo, b'GQ', env, expected_status=130)
        for text in ('IDENTITIES', 'Personal & companies',
                     'Workstation account', 'AI accounts', 'Setup cancelled'):
            assert text in profiles_output, profiles_output[-3500:]
        assert statuses() == initial, 'Browsing Requirements/Profiles must not change installed components'
        # Remove a running bench and the npm CLI in one real setup.sh TUI plan.
        output = setup_tui(repo, b'\x1b[C\tD\x1b[C\x1b[B\x1b[BD\n\n', env)
        assert 'pyBench uninstalled' in output, output[-2500:]
        assert 'All selected changes completed successfully' in output
        assert statuses() == 'needs setup:not installed'
        assert not run(['docker', 'ps', '-aq'])
        for tag in ('latest', 'node'):
            assert subprocess.run(['docker', 'image', 'inspect', 'py-bench:' + tag], capture_output=True).returncode != 0
        assert credential.read_text() == '{"OPENAI_API_KEY":"sk-test-invalid-lifecycle-fixture"}'
        assert note.read_text() == 'preserve local work' and project.read_text() == 'preserve project'
        run(['docker', 'image', 'inspect', 'workbench-base:latest', 'dev-bench-base:latest'])
        assert run(['docker', 'run', '--rm', '--mount', f'type=volume,src={volume},dst=/data', 'busybox:1.37.0', 'cat', '/data/marker']) == 'preserve-volume'
        setup_tui(repo, b'\x1b[C\n\n', env)  # No selection remains a no-op.
        install_runtime()
        run(['npm', 'install', '--global', '--ignore-scripts', str(package)], env=env)
        assert statuses() == 'installed:installed'
        assert note.is_file() and project.is_file() and credential.is_file()
        print('PASS live setup.sh uninstall/reinstall detection: running bench + npm CLI; source, projects, credentials, shared bases and volume preserved', flush=True)


if __name__ == '__main__':
    main()
