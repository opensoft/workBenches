#!/usr/bin/env python3
"""Resolve trusted release sources and emit workflow outputs without shell interpolation."""
import argparse
import json
import os
import re
from pathlib import Path
from release_validation import ValidationError, atomic, git, plan


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--automation', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    event = os.environ.get('EVENT')
    mode = 'ci'
    if event == 'workflow_dispatch': mode = os.environ['INPUT_MODE']
    elif event == 'schedule': mode = 'release' if os.environ.get('QA_NIGHTLY') == 'true' else 'fixtures'
    workflow_ref = os.environ.get('WORKFLOW_REF', '')
    if event == 'push':
        if workflow_ref != 'refs/heads/main':
            mode = 'fixtures'
        else:
            product = (args.root / 'VERSION').read_text().strip()
            if re.fullmatch(r'\d+\.\d+\.\d+', product):
                try: git(args.root, 'rev-parse', '--verify', 'refs/tags/v' + product)
                except ValidationError: mode = 'release'
    if mode == 'release' and workflow_ref != 'refs/heads/main':
        raise ValidationError('privileged_release_workflow_must_run_from_main')
    identity = git(args.root, 'rev-parse', 'HEAD')
    ref = os.environ.get('INPUT_REF') or (workflow_ref.removeprefix('refs/heads/') if event == 'push' else 'main' if event == 'schedule' else identity)
    automation = git(args.automation, 'rev-parse', 'HEAD')
    value = plan(args.root, args.automation / 'config/release-tests.json', mode, identity, ref)
    if mode == 'release':
        core = value['source']['version'].split('-', 1)[0]
        reachable = False
        for branch in ('origin/main', 'origin/release/' + core):
            try:
                git(args.root, 'merge-base', '--is-ancestor', identity, branch); reachable = True
            except ValidationError: pass
        if not reachable: raise ValidationError('source_not_on_main_or_release_branch')
    atomic(args.output, value)
    outputs = dict(hosted=json.dumps(value['hosted']), sha=identity, ref=ref, automation=automation, mode=mode)
    if any('\n' in v or '\r' in v for v in outputs.values()): raise ValidationError('invalid_output')
    with open(os.environ['GITHUB_OUTPUT'], 'a') as stream:
        for key, val in outputs.items(): stream.write(key + '=' + val + '\n')


if __name__ == '__main__': main()
