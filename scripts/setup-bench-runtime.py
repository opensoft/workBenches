#!/usr/bin/env python3
"""Add first-start Wave mounts to native Compose setup, then verify readiness."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]

try:
    import workbenches_host as host
except ImportError:
    host = None
    if os.environ.get('WORKBENCHES_HOST_RPC'):
        raise


def run(argv, **kwargs):
    if argv[0] == 'bash' and host and host.active():
        # Bench scripts inspect native WSL/GPU/desktop paths. Keep those scripts
        # on the workstation, while their four setup commands use the shims.
        env = dict(kwargs.get('env') or os.environ)
        prefix = str(Path(os.environ.get('XDG_CACHE_HOME', str(Path.home() / '.cache'))) / 'workbenches/tools/bin')
        if env.get('WORKBENCHES_REAL_DOCKER'):
            prefix = env['PATH'].split(os.pathsep)[0] + os.pathsep + prefix
        env['WORKBENCHES_COMMAND_PATH'] = prefix
        env['WORKBENCHES_COMMAND_CWD'] = str(kwargs.get('cwd') or Path.cwd())
        return host.run(['bash', '-c',
                         'export PATH="$WORKBENCHES_COMMAND_PATH:$PATH"; cd "$WORKBENCHES_COMMAND_CWD" || exit; exec bash "$@"',
                         'workbenches-native', *argv[1:]], env=env,
                        capture_output=kwargs.get('capture_output', False),
                        text=kwargs.get('text', False), timeout=3600)
    return subprocess.run(argv, **kwargs)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bench', required=True)
    parser.add_argument('--setup', type=Path, required=True)
    args = parser.parse_args()
    setup = args.setup.resolve()
    compose = setup.parent / '.devcontainer/docker-compose.yml'
    docker = shutil.which('docker')
    if not compose.is_file():
        code = run(['bash', str(setup)], cwd=setup.parent).returncode
        if code == 0:
            print('Needs attention: setup completed without a declared Compose runtime; finish the bench Dev Container setup.', file=sys.stderr)
        return code or 1
    config = run([docker, 'compose', '-f', str(compose), 'config', '--format', 'json'],
                 cwd=compose.parent, capture_output=True, text=True)
    if config.returncode:
        print('Needs attention: could not render the declared bench Compose configuration.', file=sys.stderr)
        return 1
    services = json.loads(config.stdout)['services']
    candidates = [name for name, row in services.items() if row.get('container_name') == name]
    if len(candidates) != 1:
        print('Needs attention: cannot identify a unique bench container.', file=sys.stderr)
        return 1
    container = candidates[0]
    inspected = run([docker, 'container', 'inspect', container], capture_output=True, text=True)
    initial = json.loads(inspected.stdout)[0] if inspected.returncode == 0 else None
    if initial and initial['State']['Running']:
        print(f'Needs attention: {container} is already running; preserving it. Stop it before applying setup changes.', file=sys.stderr)
        return 1
    if initial:
        labels = initial.get('Config', {}).get('Labels') or {}
        if labels.get('com.docker.compose.project') != json.loads(config.stdout).get('name') or labels.get('com.docker.compose.service') != container:
            print('Needs attention: existing container belongs to another Compose lifecycle; preserving it.', file=sys.stderr)
            return 1
    wave = ['bash', str(ROOT / 'scripts/wave-container-shell.sh'), '--workbenches-root', str(ROOT), '--shell', 'bash']
    with tempfile.TemporaryDirectory(prefix='workbenches-bench-') as directory:
        work = Path(directory)
        override = Path(os.environ.get('WAVE_WORKBENCHES_COMPOSE_CACHE', str(Path.home() / '.cache/workbenches/wave-compose'))) / (container + '.override.yml')
        override.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        result = run(wave + ['--prepare-compose', str(override), container])
        if result.returncode:
            return result.returncode
        adapter = work / 'docker'
        adapter.write_text('''#!/usr/bin/env python3
import json, os, pathlib, subprocess, sys
real=os.environ['WORKBENCHES_REAL_DOCKER']
args=sys.argv[1:]
if pathlib.Path(sys.argv[0]).name == 'docker-compose': args=['compose']+args
if args and args[0]=='compose':
    index=1; files=[]
    paired=('-f','--file','-p','--project-name','--env-file','--profile','--project-directory')
    while index<len(args):
        word=args[index]
        if word in paired:
            if word in ('-f','--file'): files.append(str(pathlib.Path(args[index+1]).resolve()))
            index+=2
        elif word.startswith('-'): index+=1
        else: break
    if index<len(args) and args[index] in ('up','create') and os.environ['WORKBENCHES_NATIVE_COMPOSE'] in files:
        current=subprocess.run([real,'container','inspect',os.environ['WORKBENCHES_BENCH_CONTAINER']],capture_output=True,text=True)
        if current.returncode==0:
            row=json.loads(current.stdout)[0]
            if row['State']['Running'] or row['Id']!=os.environ['WORKBENCHES_INITIAL_CONTAINER_ID']:
                print('Needs attention: bench appeared or started during setup; preserving it.',file=sys.stderr);sys.exit(1)
        args[index:index]=['-f',os.environ['WORKBENCHES_WAVE_OVERRIDE']]
os.execv(real,[real]+args)
''')
        adapter.chmod(0o700)
        (work / 'docker-compose').symlink_to(adapter)
        env = dict(os.environ, PATH=str(work)+os.pathsep+os.environ['PATH'],
                   WORKBENCHES_REAL_DOCKER=docker, WORKBENCHES_NATIVE_COMPOSE=str(compose),
                   WORKBENCHES_BENCH_CONTAINER=container, WORKBENCHES_WAVE_OVERRIDE=str(override),
                   WORKBENCHES_INITIAL_CONTAINER_ID=initial['Id'] if initial else '')
        # An existing Layer 2 tag can still inherit an obsolete family base.
        # Use the bench's declared builder so Docker evaluates its current FROM
        # image instead of letting an existence-only check reuse stale layers.
        builder = setup.parent / 'scripts/build-layer2.sh'
        if builder.is_file():
            print(f'Refreshing {args.bench} image from its declared sources...', flush=True)
            result = run(['bash', str(builder)], cwd=setup.parent, env=env)
            if result.returncode:
                return result.returncode
        result = run(['bash', str(setup)], cwd=setup.parent, env=env)
        if result.returncode:
            return result.returncode
    # Ordinary verification must pass; no implicit --repair after native startup.
    result = run(wave + ['--check', container])
    if result.returncode:
        print(f'Needs attention: {container} did not pass its launch check; run the displayed recovery command.', file=sys.stderr)
    return result.returncode

if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f'Bench setup needs attention: {error}', file=sys.stderr)
        sys.exit(1)
