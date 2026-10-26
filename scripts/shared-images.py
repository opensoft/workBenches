#!/usr/bin/env python3
"""Resolve compatible public shared images; local source changes build locally."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
import importlib.util

ROOT = Path(__file__).resolve().parents[1]
COMPAT_SPEC = importlib.util.spec_from_file_location(
    'openbenches_compat', ROOT / 'scripts/openbenches_compat.py')
compat = importlib.util.module_from_spec(COMPAT_SPEC)
COMPAT_SPEC.loader.exec_module(compat)
resolve_env = compat.resolve_env
CONTEXTS = {'base': 'base-image', 'dev': 'devBenches/base-image'}
TAGS = {'base': 'workbench-base:latest', 'dev': 'dev-bench-base:latest'}
REGISTRIES = {'base': 'ghcr.io/opensoft/workbenches-base', 'dev': 'ghcr.io/opensoft/workbenches-dev-base'}
LABEL = 'io.workbenches.source'
RELEASE_REPOSITORIES = ('opensoft/openBenches', 'opensoft/workBenches')

def tracked_context_paths(root):
    """Use Git's file-mode contract for tracked recipes, independent of umask."""
    try:
        result = subprocess.run(
            ['git', '-c', f'safe.directory={root}', '-c', 'core.fsmonitor=false',
             '-C', str(root), 'ls-files', '-z', '--', *CONTEXTS.values()],
            capture_output=True, check=True, timeout=10)
        return {os.fsdecode(name) for name in result.stdout.split(b'\0') if name}
    except (OSError, subprocess.SubprocessError):
        # Exported source trees have no index. Keep their real permissions in
        # the cache key rather than treating arbitrary local files as tracked.
        return set()

def fingerprint(layer, root=ROOT):
    digest = hashlib.sha256()
    context = root / CONTEXTS[layer]
    tracked = tracked_context_paths(root)
    for path in sorted(context.rglob('*')):
        relative = path.relative_to(context)
        if '.git' in relative.parts or '__pycache__' in relative.parts or path.suffix == '.pyc':
            continue
        if path.is_symlink():
            payload = b'link:' + os.readlink(path).encode()
        elif path.is_file():
            payload = path.read_bytes()
        else:
            continue
        mode = path.lstat().st_mode & 0o777
        if not path.is_symlink() and path.relative_to(root).as_posix() in tracked:
            mode = 0o755 if mode & 0o100 else 0o644
        digest.update(str(relative).encode() + b'\0' + str(mode).encode() + b'\0')
        digest.update(hashlib.sha256(payload).digest())
    if layer == 'dev':
        digest.update(fingerprint('base', root).encode())
        digest.update((root / 'scripts/lib/image-names.sh').read_bytes())
    return digest.hexdigest()

def release_tag(root=ROOT):
    return 'shared-images-' + fingerprint('base', root)[:16] + '-' + fingerprint('dev', root)[:16]

def inspect(image):
    result = subprocess.run(['docker', 'image', 'inspect', image], capture_output=True, text=True)
    if result.returncode:
        return None
    try:
        row = json.loads(result.stdout)[0]
        return row if isinstance(row, dict) else None
    except (ValueError, IndexError, KeyError, TypeError):
        return None

def compatible(row, layer, source, platform, parent=None):
    if not row:
        return False
    labels = row.get('Config', {}).get('Labels') or {}
    return (labels.get(LABEL) == source and row.get('Os', '') + '/' + row.get('Architecture', '') == platform
            and (layer != 'dev' or labels.get('io.workbenches.parent') == parent))

def manifest_image(payload, layer, platform, source, parent=None):
    if len(payload) > 65536:
        raise ValueError('manifest too large')
    manifest = json.loads(payload)
    if manifest.get('schemaVersion') != 1:
        raise ValueError('unsupported manifest')
    entry = manifest['images'][layer][platform]
    if entry['sourceHash'] != source or (layer == 'dev' and entry['parentImageId'] != parent):
        raise ValueError('source or parent mismatch')
    image = entry['image']
    if not re.fullmatch(re.escape(REGISTRIES[layer]) + r'@sha256:[0-9a-f]{64}', image):
        raise ValueError('unapproved registry or digest')
    return image

def ensure(layer):
    if resolve_env('BUILD_LOCAL') == '1':
        print('Local build requested.')
        return 1
    info = subprocess.run(['docker', 'info', '--format', '{{.OSType}}/{{.Architecture}}'],
                          capture_output=True, text=True, check=True).stdout.strip()
    platform = info.replace('x86_64', 'amd64').replace('aarch64', 'arm64')
    source = fingerprint(layer)
    parent_row = inspect(TAGS['base']) if layer == 'dev' else None
    parent = parent_row['Id'] if parent_row else None
    if layer == 'dev' and not parent:
        print('Developer image needs the system base first.', file=sys.stderr)
        return 1
    if compatible(inspect(TAGS[layer]), layer, source, platform, parent):
        print(f'{TAGS[layer]} matches this source and platform; reusing it.')
        return 0
    try:
        explicit = resolve_env('IMAGE_MANIFEST', sensitive=True)
        if explicit:
            image = manifest_image(Path(explicit).read_bytes(), layer, platform, source, parent)
        else:
            tag = release_tag()
            for repository in RELEASE_REPOSITORIES:
                try:
                    url = f'https://github.com/{repository}/releases/download/{tag}/shared-images.json'
                    with urllib.request.urlopen(url, timeout=8) as response:
                        payload = response.read(65537)
                    image = manifest_image(payload, layer, platform, source, parent)
                except (OSError, ValueError, KeyError, TypeError):
                    if repository == RELEASE_REPOSITORIES[-1]:
                        raise
                else:
                    break
        print(f'Pulling verified {layer} image for {platform}...', flush=True)
        # Never use the workstation's registry logins for this public pull.
        with tempfile.TemporaryDirectory(prefix='workbenches-public-pull-') as directory:
            endpoint = os.environ.get('DOCKER_HOST') if not os.environ.get('DOCKER_CONTEXT') else None
            if not endpoint:
                endpoint = subprocess.run(['docker', 'context', 'inspect', '--format', '{{.Endpoints.docker.Host}}'], capture_output=True, text=True, check=True).stdout.strip()
            if not endpoint.startswith('unix://'):
                raise ValueError('public pulls require a local Docker endpoint')
            env = dict(os.environ, DOCKER_CONFIG=directory, DOCKER_HOST=endpoint)
            env.pop('DOCKER_CONTEXT', None)
            result = subprocess.run(['docker', 'pull', '--platform', platform, image], env=env)
        if result.returncode in (130, 143, -2, -15):
            raise SystemExit(130)
        if result.returncode or not compatible(inspect(image), layer, source, platform, parent):
            raise ValueError('pull failed or image metadata did not match')
        subprocess.run(['docker', 'tag', image, TAGS[layer]], check=True)
        return 0
    except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError):
        print(f'Compatible public {layer} image unavailable; building locally.', flush=True)
        return 1

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('fingerprint', 'ensure', 'release-tag'))
    parser.add_argument('layer', nargs='?', choices=CONTEXTS)
    args = parser.parse_args()
    if args.command == 'release-tag':
        print(release_tag())
        return 0
    if not args.layer:
        parser.error('layer is required')
    if args.command == 'fingerprint':
        print(fingerprint(args.layer))
        return 0
    return ensure(args.layer)

if __name__ == '__main__':
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
