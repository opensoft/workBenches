#!/usr/bin/env python3
"""Authorize an exact protected source before publishing public QA images."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import urllib.error
import urllib.request
from release_validation import SHA, ValidationError, read, source, version

SPEC = importlib.util.spec_from_file_location('image_preflight', Path(__file__).with_name('release-qa-preflight.py'))
preflight = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(preflight)


def authorize(identity, fetch):
    return preflight.trusted_source({'source': identity}, fetch)


def planned_identity(path, expected):
    identity = read(path)['source']
    if not isinstance(expected, str) or not SHA.fullmatch(expected) or identity.get('commit') != expected:
        raise ValidationError('wrong_image_source_commit')
    version(identity['version'])
    return identity


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    selection = parser.add_mutually_exclusive_group(required=True)
    selection.add_argument('--root', type=Path)
    selection.add_argument('--plan', type=Path)
    parser.add_argument('--commit', required=True)
    parser.add_argument('--require-trusted', action='store_true')
    args = parser.parse_args()
    identity = (planned_identity(args.plan, args.commit) if args.plan else
                source(args.root, Path(__file__).resolve().parents[1] / 'config/release-tests.json', args.commit))
    if os.environ.get('GITHUB_REPOSITORY') != 'opensoft/workBenches':
        raise ValidationError('unexpected_image_repository')
    token = os.environ['WB_SOURCE_READ_TOKEN']

    def fetch(path):
        request = urllib.request.Request('https://api.github.com/repos/opensoft/workBenches/' + path,
            headers={'Authorization': 'Bearer ' + token, 'Accept': 'application/vnd.github+json'})
        try:
            with urllib.request.urlopen(request, timeout=15) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            if error.code == 404: return {}
            raise

    trusted = authorize(identity, fetch)
    if args.require_trusted and not trusted:
        raise ValidationError('untrusted_image_source')
    # Emit constants for the authorization decision. API response objects and
    # request headers must never flow into logs or workflow output files.
    decision = 'true' if trusted else 'false'
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a') as stream:
            stream.write('trusted=' + decision + '\n')
    print('Image source authorized.' if trusted else 'Image source is not authorized for publication.')


if __name__ == '__main__':
    main()
