#!/usr/bin/env python3
"""Freeze assembly source revisions and prepare selected benches without drift."""
import argparse
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
LOCK = 'config/release-lock.json'


def git(root, *arguments):
    result = subprocess.run(['git', '-C', str(root), *arguments], capture_output=True,
                            text=True, timeout=60, env=dict(os.environ, GIT_TERMINAL_PROMPT='0'))
    if result.returncode:
        raise ValueError(f'Git operation failed in {root}: {arguments[0]}')
    return result.stdout.strip()


def version(root):
    value = (root / 'VERSION').read_text().strip()
    if not re.fullmatch(r'(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-[0-9A-Za-z.-]+)?', value):
        raise ValueError('VERSION must contain a release version such as 1.5.0')
    return value


def sources(root):
    catalog = json.loads((root / 'config/bench-config.json').read_text())['benches']
    result = {item['path']: {'url': item['url']} for item in catalog.values()}
    for line in git(root, 'ls-tree', '-r', 'HEAD').splitlines():
        metadata, path = line.split('\t', 1)
        mode, _, commit = metadata.split()
        if mode != '160000':
            continue
        url = git(root, 'config', '-f', '.gitmodules', f'submodule.{path}.url')
        result.setdefault(path, {'url': url})['gitlink'] = commit
    for path, item in result.items():
        parts = PurePosixPath(path).parts
        if not parts or parts[0] not in ('devBenches', 'sysBenches', 'bioBenches') or '..' in parts:
            raise ValueError(f'Invalid bench path: {path}')
        if not item['url'] or item['url'].startswith('-'):
            raise ValueError(f'Invalid source URL for {path}')
    return result


def checkout_identity(path):
    # git -C on an empty submodule directory otherwise finds the parent repo.
    if Path(git(path, 'rev-parse', '--show-toplevel')).resolve() != path.resolve():
        raise ValueError(f'{path} is not its own Git checkout')
    if git(path, 'status', '--porcelain', '--untracked-files=normal'):
        raise ValueError(f'{path} has local changes; save them before using a frozen release')
    return git(path, 'rev-parse', 'HEAD')


def freeze(root):
    entries = []
    for path, source in sorted(sources(root).items()):
        checkout = root / path
        if (checkout / '.git').exists():
            commit = checkout_identity(checkout)
        elif source.get('gitlink'):
            commit = source['gitlink']
        else:
            # Capture an absent public bench without cloning or installing it.
            remote = git(root, 'ls-remote', source['url'], 'HEAD').split()
            if not remote:
                raise ValueError(f'Cannot resolve the source revision for {path}')
            commit = remote[0]
        if source.get('gitlink', commit) != commit:
            raise ValueError(f'{path} differs from the assembly gitlink; commit its pin first')
        if not re.fullmatch(r'[0-9a-f]{40}', commit):
            raise ValueError(f'Invalid source revision for {path}')
        entries.append({'path': path, 'url': source['url'], 'commit': commit})
    manifest = {'schemaVersion': 1, 'version': version(root), 'repositories': entries}
    (root / LOCK).write_text(json.dumps(manifest, indent=2) + '\n')
    return manifest


def validate(root, tag=None, check_worktrees=True):
    manifest = json.loads((root / LOCK).read_text())
    if manifest.get('schemaVersion') != 1 or manifest.get('version') != version(root):
        raise ValueError('Release lock does not match VERSION; freeze the candidate again')
    declared = sources(root)
    entries = manifest['repositories']
    if not isinstance(entries, list) or len(entries) != len(declared):
        raise ValueError('Release lock must cover every bench and submodule')
    seen = set()
    for entry in entries:
        path = entry['path']; expected = declared.get(path)
        if path in seen or expected is None or entry['url'] != expected['url']:
            raise ValueError(f'Stale or duplicate release source: {path}')
        seen.add(path)
        if not re.fullmatch(r'[0-9a-f]{40}', entry['commit']):
            raise ValueError(f'Invalid revision: {path}')
        if expected.get('gitlink', entry['commit']) != entry['commit']:
            raise ValueError(f'Frozen revision differs from assembly gitlink: {path}')
        checkout = root / path
        if check_worktrees and (checkout / '.git').exists() and checkout_identity(checkout) != entry['commit']:
            raise ValueError(f'{path} is not at its frozen commit {entry["commit"]}; use a fresh release checkout')
    status_arguments = ['status', '--porcelain', '--untracked-files=normal']
    if not check_worktrees:
        # Installing a selected bench checks its worktree below. Removal and
        # unrelated tools must preserve, and remain usable alongside, local work.
        status_arguments.append('--ignore-submodules=all')
    if git(root, *status_arguments):
        raise ValueError('Release checkout has local changes; commit the freeze before tagging or installing')
    if tag:
        if tag != 'v' + manifest['version']:
            raise ValueError('Release tag must match VERSION')
        if git(root, 'rev-parse', f'refs/tags/{tag}^{{commit}}') != git(root, 'rev-parse', 'HEAD'):
            raise ValueError('Release tag does not identify this checkout')
        if git(root, 'cat-file', '-t', f'refs/tags/{tag}') != 'tag':
            raise ValueError('Use an annotated release tag')
    return manifest


def prepare(root, selection):
    manifest = validate(root, check_worktrees=False)
    locked = {entry['path']: entry for entry in manifest['repositories']}
    catalog = json.loads((root / 'config/bench-config.json').read_text())['benches']
    entries = json.loads(selection.read_text())['components']
    wanted = {catalog[entry['key'][6:]]['path'] for entry in entries
              if entry['key'].startswith('bench_') and entry['action'] in ('install', 'update')}
    # Refuse every existing mismatch before creating any missing checkout.
    for path in sorted(wanted):
        checkout = root / path
        if (checkout / '.git').exists():
            if checkout_identity(checkout) != locked[path]['commit']:
                raise ValueError(f'{path} is not at its frozen commit {locked[path]["commit"]}; use a fresh release checkout')
        elif checkout.exists() and any(checkout.iterdir()):
            raise ValueError(f'{path} contains files; use a fresh release checkout')
    for path in sorted(wanted):
        checkout = root / path; entry = locked[path]
        if not (checkout / '.git').exists():
            checkout.parent.mkdir(parents=True, exist_ok=True)
            # Share SSH preference/HTTPS fallback, then detach at the frozen SHA.
            subprocess.run(['bash', str(root / 'bootstrap.sh'), '--clone', entry['url'],
                            str(checkout), '--no-checkout'], check=True)
            git(checkout, 'checkout', '--detach', entry['commit'])
            subprocess.run(['bash', str(root / 'bootstrap.sh'), '--submodules', str(checkout)], check=True)
        if checkout_identity(checkout) != entry['commit']:
            raise ValueError(f'Frozen source verification failed: {path}')
        print(f'Frozen source: {path} @ {entry["commit"][:12]}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('freeze', 'check', 'prepare'))
    parser.add_argument('--tag')
    parser.add_argument('--selection', type=Path)
    args = parser.parse_args()
    if args.command == 'freeze':
        manifest = freeze(ROOT)
        print(f'Freeze candidate v{manifest["version"]}: {len(manifest["repositories"])} repository pins written to {LOCK}')
    elif args.command == 'check':
        manifest = validate(ROOT, args.tag)
        print(f'Release v{manifest["version"]} source lock verified')
    elif args.selection:
        prepare(ROOT, args.selection)
    else:
        parser.error('prepare requires --selection')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        print(f'Release stopped: {error}', file=sys.stderr)
        sys.exit(1)
