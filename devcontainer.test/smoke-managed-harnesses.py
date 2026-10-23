#!/usr/bin/env python3
"""Opt-in public distribution checks; run only in a disposable test container."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from setup_harnesses import Installer, Runner
import setup_harness_targets as targets


def command(argv, **kwargs):
    return subprocess.run(argv, check=True, text=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--key', action='append', default=[])
    parser.add_argument('--docker-recreation', action='store_true')
    args = parser.parse_args()
    if not Path('/.dockerenv').exists() or os.getuid() == 0:
        parser.error('use the declared disposable workstation test container as its non-root user')
    if not args.key and not args.docker_recreation:
        parser.error('choose --key or --docker-recreation explicitly')
    with tempfile.TemporaryDirectory(prefix='workbenches-harness-smoke-') as temporary:
        home = Path(temporary) / 'home'; home.mkdir()
        for key in args.key:
            installer = Installer(home=home, runner=Runner(local=True))
            installer.install(key)
            if installer.status(key) != 'installed': raise RuntimeError('install status failed')
            receipt = json.loads((installer.base / key / 'current/receipt.json').read_text())
            installer.uninstall(key)
            print('PUBLIC SMOKE PASS', key, receipt['version'], flush=True)
        if args.docker_recreation:
            docker_smoke(Path(temporary))


def docker_smoke(root):
    """Use private fixture names/catalog; never bind to a real bench name."""
    suffix = uuid.uuid4().hex[:12]
    image = 'workbenches-harness-smoke-' + suffix + ':fixture'
    name = 'harness' + suffix + 'Bench'
    repo = 'harness' + suffix + '-bench'
    context = root / 'context'; context.mkdir()
    shutil.copytree(ROOT / 'user-layer/harness-runtime', context / 'runtime')
    (context / 'runtime/selection.list').write_text('dsh_cli\n')
    (context / 'Dockerfile').write_text('''FROM workbenches-test:workstation
USER node
COPY --chown=node:node runtime/ /opt/harness-smoke/
RUN chmod 600 /opt/harness-smoke/selection.list && export HOME="$(getent passwd "$(id -u)" | cut -d: -f6)" && python3 /opt/harness-smoke/scripts/setup-harnesses.py install --local --selection /opt/harness-smoke/selection.list
''')
    cid = None
    try:
        command(['docker', 'build', '-t', image, str(context)], stdout=subprocess.DEVNULL)
        for _ in range(2):
            command(['docker', 'run', '--rm', '--entrypoint', 'sh', image, '-c',
                     'exec "$(getent passwd "$(id -u)" | cut -d: -f6)/.local/bin/dsh" --version'])
        # The live target starts without dsh. Reuse the ordinary bench resource
        # validator with a private catalog rooted in this disposable fixture.
        checkout = root / 'checkout'; (checkout / 'config').mkdir(parents=True)
        directory = checkout / 'devBenches' / name; directory.mkdir(parents=True)
        (checkout / 'config/bench-config.json').write_text(json.dumps({'benches': {name: {'path': 'devBenches/' + name}}}))
        command(['docker', 'tag', 'workbenches-test:workstation', repo + ':latest'])
        cid = subprocess.check_output(['docker', 'run', '-d', '--name', repo, '--user', 'node',
                                       '--label', 'com.docker.compose.project.working_dir=' + str(directory),
                                       repo + ':latest', 'sleep', 'infinity'], text=True).strip()
        spec = importlib.util.spec_from_file_location('smoke_components', ROOT / 'scripts/setup-components.py')
        api = importlib.util.module_from_spec(spec); spec.loader.exec_module(api); api.ROOT = checkout
        old_home = os.environ.get('HOME'); os.environ['HOME'] = str(root / 'desired-home'); Path.home().mkdir()
        try:
            prepared = targets.prepare([name], api)
            if targets.apply('install', 'dsh_cli', prepared): raise RuntimeError('live target pending')
            command(['docker', 'exec', '--user', 'node', cid, 'sh', '-c',
                     'exec "$(getent passwd "$(id -u)" | cut -d: -f6)/.local/bin/dsh" --version'])
            if targets.apply('uninstall', 'dsh_cli', prepared): raise RuntimeError('live removal pending')
            if targets.read_selection(targets.selection_path(repo)): raise RuntimeError('desired removal failed')
        finally:
            if old_home is None: os.environ.pop('HOME', None)
            else: os.environ['HOME'] = old_home
        print('DOCKER SMOKE PASS: live non-root install/remove and two fresh containers from selected-tool image', flush=True)
    finally:
        if cid: subprocess.run(['docker', 'rm', '-f', cid], stdout=subprocess.DEVNULL, check=False)
        for tag in (image, repo + ':latest'):
            subprocess.run(['docker', 'image', 'rm', tag], stdout=subprocess.DEVNULL, check=False)


if __name__ == '__main__': main()
