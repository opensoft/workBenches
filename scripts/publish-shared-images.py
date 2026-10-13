#!/usr/bin/env python3
"""Build, validate and release anonymous shared-image manifests through CI."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import urllib.error
import urllib.request
import shared_images as shared

ROOT = shared.ROOT

def run(argv, **kwargs):
    return subprocess.run(argv, check=True, **kwargs)

def github(path, payload, content_type='application/json'):
    data = payload if isinstance(payload, bytes) else json.dumps(payload).encode()
    request = urllib.request.Request('https://api.github.com/' + path, data=data,
        headers={'Authorization': 'Bearer ' + os.environ['GH_TOKEN'],
                 'Accept': 'application/vnd.github+json', 'Content-Type': content_type}, method='POST')
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        raise RuntimeError(f'GitHub release operation failed (HTTP {error.code}).') from None

def main():
    # No workstation credentials or user-specific Layer 3 are ever published.
    platform = run(['docker', 'info', '--format', '{{.OSType}}/{{.Architecture}}'],
                   capture_output=True, text=True).stdout.strip().replace('x86_64', 'amd64')
    if platform != 'linux/amd64':
        raise RuntimeError('This initial release supports linux/amd64; other platforms build locally.')
    repository = os.environ['GITHUB_REPOSITORY']
    if repository != 'opensoft/workBenches':
        raise RuntimeError('Publication is restricted to the source repository.')
    release_url = f'https://github.com/{repository}/releases/download/{shared.release_tag()}/shared-images.json'
    try:
        with urllib.request.urlopen(release_url, timeout=15) as response:
            existing = json.loads(response.read(65537))
    except (OSError, ValueError):
        existing = None
    if existing:
        with tempfile.TemporaryDirectory() as directory:
            for layer in ('base', 'dev'):
                entry = existing['images'][layer][platform]
                if entry['sourceHash'] != shared.fingerprint(layer) or not entry['image'].startswith(shared.REGISTRIES[layer]+'@sha256:'):
                    raise RuntimeError('Existing release does not match the source recipe.')
                run(['docker','manifest','inspect',entry['image']],env=dict(os.environ,DOCKER_CONFIG=directory),stdout=subprocess.DEVNULL)
        print('Compatible immutable release already exists; preserving it.')
        return
    run(['docker', 'login', 'ghcr.io', '--username', os.environ['REGISTRY_USER'], '--password-stdin'],
        input=os.environ['GH_TOKEN'], text=True, stdout=subprocess.DEVNULL)
    manifest = {'schemaVersion': 1, 'sourceCommit': os.environ['GITHUB_SHA'], 'images': {}}
    for layer in ('base', 'dev'):
        run(['bash', str(ROOT / shared.CONTEXTS[layer] / 'build.sh')], cwd=ROOT)
        tag = shared.REGISTRIES[layer] + ':source-' + shared.fingerprint(layer)
        run(['docker', 'tag', shared.TAGS[layer], tag])
        # Smoke tests exercise installed binaries without any account login.
        run(['docker', 'run', '--rm', '--entrypoint', 'sh', tag, '-ec',
             'codex --version; claude --version; python3 --version; node --version'])
        run(['docker', 'push', tag])
        row = shared.inspect(tag)
        refs = [ref for ref in row['RepoDigests'] if ref.startswith(shared.REGISTRIES[layer] + '@sha256:')]
        if len(refs) != 1:
            raise RuntimeError('Expected exactly one pushed digest.')
        entry = {'sourceHash': shared.fingerprint(layer), 'image': refs[0]}
        if layer == 'dev':
            entry['parentImageId'] = shared.inspect(shared.TAGS['base'])['Id']
        manifest['images'][layer] = {platform: entry}
    output = Path('/release/shared-images.json')
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(manifest, indent=2) + '\n')
    # GHCR packages start private. Do not release a manifest until every image
    # resolves with an empty credential configuration (even if layers are cached).
    with tempfile.TemporaryDirectory() as directory:
        env = dict(os.environ, DOCKER_CONFIG=directory)
        for layer in ('base', 'dev'):
            image = manifest['images'][layer][platform]['image']
            try:
                run(['docker', 'manifest', 'inspect', image], env=env, stdout=subprocess.DEVNULL)
                run(['docker', 'pull', image], env=env)
            except subprocess.CalledProcessError:
                raise RuntimeError('Anonymous access failed. Make the workbenches-base and workbenches-dev-base GHCR packages public, then rerun this workflow.') from None
    release = github(f'repos/{repository}/releases', {'tag_name': shared.release_tag(),
        'target_commitish': os.environ['GITHUB_SHA'], 'name': shared.release_tag(),
        'body': 'Validated shared images for anonymous workstation installation. Manifest pins source fingerprints, architecture and image digests.'})
    upload = release['upload_url'].split('{', 1)[0].replace('https://uploads.github.com/', '')
    request = urllib.request.Request('https://uploads.github.com/' + upload + '?name=shared-images.json',
        data=output.read_bytes(), headers={'Authorization': 'Bearer ' + os.environ['GH_TOKEN'],
        'Content-Type': 'application/json'}, method='POST')
    with urllib.request.urlopen(request, timeout=60) as response:
        response.read()
    print('Released anonymous shared images: ' + shared.release_tag())

if __name__ == '__main__':
    main()
