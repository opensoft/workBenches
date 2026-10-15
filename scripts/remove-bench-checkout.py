#!/usr/bin/env python3
"""Remove an explicitly selected, clean checkout after focused confirmation."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys

from setup_prompts import cancellation_signals, prompt

ROOT = Path(__file__).resolve().parents[1]


def git(directory, *args):
    return subprocess.check_output(['git', '-C', str(directory), *args], text=True).strip()


def verify(directory):
    if directory.is_symlink() or directory.resolve() != directory:
        raise ValueError('checkout path contains a symlink')
    if Path(git(directory, 'rev-parse', '--show-toplevel')).resolve() != directory:
        raise ValueError('directory is not its own Git checkout')
    if git(directory, 'status', '--porcelain') or git(directory, 'ls-files', '--others', '--directory'):
        raise ValueError('checkout contains local changes, untracked files, or ignored files')
    if git(directory, 'rev-list', '--all', 'HEAD', '--not', '--remotes'):
        raise ValueError('checkout contains commits absent from its local remote-tracking refs')
    ids = subprocess.check_output(['docker', 'ps', '-q'], text=True).split()
    if ids:
        containers = json.loads(subprocess.check_output(['docker', 'inspect', *ids], text=True))
        for container in containers:
            labels = container.get('Config', {}).get('Labels') or {}
            paths = labels.get('com.docker.compose.project.config_files', '').split(',')
            paths += [labels.get('com.docker.compose.project.working_dir', '')]
            paths += [row.get('Source', '') for row in container.get('Mounts', [])]
            if any(path and Path(path).is_absolute() and Path(path).is_relative_to(directory)
                   for path in paths):
                raise ValueError('a running container uses this checkout; stop it before removal')


def main():
    cancellation_signals()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bench', required=True)
    args = parser.parse_args()
    relative = Path(json.loads((ROOT / 'config/bench-config.json').read_text())['benches'][args.bench]['path'])
    if relative.is_absolute() or '..' in relative.parts or len(relative.parts) != 2 or relative.parts[0] not in ('devBenches', 'sysBenches', 'bioBenches'):
        raise ValueError('invalid bench checkout path')
    directory = ROOT / relative
    if not directory.exists():
        print(f'{args.bench} is already removed.')
        return 0
    verify(directory)
    if not sys.stdin.isatty():
        raise ValueError('checkout deletion requires an interactive confirmation')
    if prompt(f'Delete the clean {args.bench} checkout at {directory}? [y/N]: ').lower() not in ('y', 'yes'):
        print(f'{args.bench} removal declined; checkout preserved.')
        return 1
    # Recheck after the prompt in case local work or a container appeared.
    verify(directory)
    shutil.rmtree(directory)
    print(f'Removed {args.bench} checkout. Docker images, volumes, and credentials were preserved.')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        print(f'Removal blocked; checkout preserved: {error}', file=sys.stderr)
        sys.exit(1)
