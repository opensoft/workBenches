#!/usr/bin/env python3
"""Publish only a stable, current-main release with verified full-run evidence."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

from release_validation import DEFAULT_MANIFEST, ValidationError, atomic, gate, git, read, source


def gh(*args, payload=None, absent=False):
    result = subprocess.run(['gh', *args], input=json.dumps(payload) if payload is not None else None,
                            text=True, capture_output=True, timeout=120)
    if result.returncode:
        if absent and 'HTTP 404' in result.stderr: return None
        raise ValidationError('github_operation_failed')
    return result.stdout


def run_identity(value, repository, commit):
    if value.get('path') != '.github/workflows/release-validation.yml' or value.get('head_branch') != 'main':
        raise ValidationError('untrusted_validation_workflow')
    if value.get('event') not in ('workflow_dispatch', 'schedule', 'push') or value.get('conclusion') != 'success' or value.get('status') != 'completed':
        raise ValidationError('validation_run_not_successful')
    if value.get('head_sha') != commit or value.get('head_repository', {}).get('full_name') != repository:
        raise ValidationError('validation_not_current_main')
    return dict(runId=str(value['id']), attempt=str(value['run_attempt']), repository=repository, automationCommit=commit)


def existing_tag(repository, tag, commit, run_id):
    raw = gh('api', f'repos/{repository}/git/ref/tags/{tag}', absent=True)
    if raw is None: return False
    ref = json.loads(raw)
    if ref.get('object', {}).get('type') != 'tag': raise ValidationError('annotated_tag_required')
    object_id = ref['object']['sha']
    value = json.loads(gh('api', f'repos/{repository}/git/tags/{object_id}'))
    required = [f'Validated source {commit}', f'Evidence https://github.com/{repository}/actions/runs/{run_id}']
    if value.get('tag') != tag or (value.get('object', {}).get('type') != 'commit' or value.get('object', {}).get('sha') != commit) or any(line not in value.get('message', '').splitlines() for line in required):
        raise ValidationError('existing_tag_does_not_match_validated_source')
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--run-id', required=True)
    parser.add_argument('--version', required=True)
    parser.add_argument('--publish', action='store_true', help='Default validates only; does not write tags/releases')
    args = parser.parse_args()
    if not re.fullmatch(r'\d+', args.run_id) or not re.fullmatch(r'(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)', args.version):
        raise ValidationError('stable_version_and_validation_run_required')
    repository = os.environ.get('GITHUB_REPOSITORY', '')
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repository): raise ValidationError('repository_required')
    identity = source(args.root, DEFAULT_MANIFEST)
    commit = identity['commit']
    remote = json.loads(gh('api', f'repos/{repository}/git/ref/heads/main'))
    if remote['object']['sha'] != commit or identity['version'] != args.version: raise ValidationError('checkout_not_final_main_version')
    metadata = json.loads(gh('api', f'repos/{repository}/actions/runs/{args.run_id}'))
    expected_run = run_identity(metadata, repository, commit)
    notes = args.root / 'docs' / ('release-' + args.version + '.md')
    if not notes.is_file(): raise ValidationError('release_notes_required')
    with tempfile.TemporaryDirectory(prefix='validated-release-') as temp:
        directory = Path(temp)
        gh('run', 'download', args.run_id, '--repo', repository, '--pattern', 'release-summary', '--dir', str(directory / 'summary'))
        summary = read(directory / 'summary/summary.report')
        if summary.get('publishable') is not True or summary.get('mode') != 'release' or summary.get('run') != expected_run:
            raise ValidationError('full_release_evidence_required')
        gh('run', 'download', args.run_id, '--repo', repository, '--pattern', 'release-evidence-*', '--dir', str(directory / 'evidence'))
        flattened = directory / 'reports'; flattened.mkdir()
        for path in (directory / 'evidence').glob('*/*.json'):
            target = flattened / path.name
            if target.exists(): raise ValidationError('duplicate_evidence_artifact')
            target.write_bytes(path.read_bytes())
        value = gate(args.root, DEFAULT_MANIFEST, flattened, 'release', commit, summary['source']['ref'], expected_run)
        if not value['publishable'] or summary['source'] != value['source']: raise ValidationError('invalid_release_evidence')
        tag = 'v' + args.version
        already_tagged = existing_tag(repository, tag, commit, args.run_id)
        print('Verified full release evidence for ' + tag + ' at ' + commit)
        if not args.publish:
            print('Validation only; no tag or release written.'); return
        remote = json.loads(gh('api', f'repos/{repository}/git/ref/heads/main'))
        if remote['object']['sha'] != commit: raise ValidationError('main_changed_before_publication')
        message = f'workBenches {args.version}\nValidated source {commit}\nEvidence https://github.com/{repository}/actions/runs/{args.run_id}'
        if not already_tagged:
            annotation = json.loads(gh('api', '--method', 'POST', f'repos/{repository}/git/tags', '--input', '-',
                payload={'tag': tag, 'message': message, 'object': commit, 'type': 'commit'}))
            gh('api', '--method', 'POST', f'repos/{repository}/git/refs', '--input', '-',
                payload={'ref': 'refs/tags/' + tag, 'sha': annotation['sha']})
        # A failure never deletes/moves a tag. An administrator inspects and
        # resumes publication of that validated source instead of retagging.
        content = notes.read_text() + '\n\n' + message + '\n'
        note_file = directory / 'release-notes.md'; note_file.write_text(content)
        evidence = directory / 'validation-report.json'; atomic(evidence, value)
        previous = gh('api', f'repos/{repository}/releases/tags/{tag}', absent=True)
        if previous is not None:
            if json.loads(previous).get('draft'): raise ValidationError('existing_draft_requires_review')
            print('The validated release is already published; nothing changed.'); return
        gh('release', 'create', tag, str(evidence), '--repo', repository, '--verify-tag', '--latest',
            '--title', 'workBenches ' + args.version, '--notes-file', str(note_file))
        print('Published ' + tag)


if __name__ == '__main__':
    try: main()
    except (ValueError, OSError, KeyError, TypeError):
        raise SystemExit('Publication blocked: invalid, incomplete, stale, or untrusted release evidence/configuration.')
