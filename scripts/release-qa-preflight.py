#!/usr/bin/env python3
"""Discover available protected QA workers; emit blocked evidence for missing ones."""
import argparse
import json
import os
from pathlib import Path
import urllib.request
import urllib.parse
from release_validation import atomic, base_report, context, read


def trusted_source(plan, fetch):
    main = fetch('branches/main')
    if main['commit']['sha'] == plan['source']['commit']: return True
    core = plan['source']['version'].split('-', 1)[0]
    candidate = fetch('branches/' + urllib.parse.quote('release/' + core, safe=''))
    return candidate.get('protected') is True


def readiness(plan, runners, configured, blocked_reason=None):
    ready, blocked = [], []
    for suite in plan['external']:
        matching = [r for r in runners if r.get('status') == 'online' and not r.get('busy') and
                    set(suite['labels']) <= {label['name'] for label in r.get('labels', [])}]
        if configured and matching: ready.append(suite)
        else:
            report = base_report(suite['suite'], plan['source'])
            report['reason'] = blocked_reason or ('qa_configuration_missing' if not configured else 'matching_runner_unavailable')
            blocked.append(report)
    return ready, blocked


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--plan', type=Path, required=True)
    parser.add_argument('--reports', type=Path, required=True)
    args = parser.parse_args()
    plan = read(args.plan)
    runners = []
    token = os.environ.get('WB_QA_INVENTORY_TOKEN')
    repository = os.environ.get('GITHUB_REPOSITORY', '')
    configured = os.environ.get('WB_QA_CONFIGURED') == 'true'
    if token and repository:
        try:
            for page in range(1, 11):
                request = urllib.request.Request(f'https://api.github.com/repos/{repository}/actions/runners?per_page=100&page={page}',
                    headers={'Authorization': 'Bearer ' + token, 'Accept': 'application/vnd.github+json'})
                with urllib.request.urlopen(request, timeout=15) as response:
                    rows = json.load(response)['runners']
                runners.extend(rows)
                if len(rows) < 100: break
        except (OSError, ValueError, KeyError):
            configured = False; runners = []
    else: configured = False
    reason = None
    if configured:
        try:
            source_token = os.environ['WB_SOURCE_READ_TOKEN']
            def fetch(path):
                request = urllib.request.Request('https://api.github.com/repos/' + repository + '/' + path,
                    headers={'Authorization':'Bearer ' + source_token, 'Accept':'application/vnd.github+json'})
                with urllib.request.urlopen(request, timeout=15) as response: return json.load(response)
            if not trusted_source(plan, fetch):
                configured = False; reason = 'unprotected_candidate_ref'
        except (OSError, ValueError, KeyError):
            configured = False; reason = 'source_trust_check_unavailable'
    ready, blocked = readiness(plan, runners, configured, reason)
    for report in blocked: atomic(args.reports / (report['suite'] + '.json'), report)
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a') as stream:
            stream.write('matrix=' + json.dumps({'include': ready}, separators=(',', ':')) + '\n')
            stream.write('has_ready=' + str(bool(ready)).lower() + '\n')
            stream.write('has_blocked=' + str(bool(blocked)).lower() + '\n')
    print(json.dumps({'ready': [s['suite'] for s in ready], 'blocked': [r['suite'] for r in blocked]}))


if __name__ == '__main__': main()
