#!/usr/bin/env python3
"""Attended live authorization probe. Not a complete github-live release adapter.

Run only in a disposable QA account. Each login has an isolated gh credential
store, deleted on exit. No daily gh identity is switched; no credential is printed.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from github_profile_authorization import authorize, AuthorizationUnavailable


def main():
    policy = json.loads((ROOT / 'qa/release/github-profile-policy.json').read_text())
    for login, expected in [('Opensoft-Test-User-1', True), ('Opensoft-Test-User-2', False)]:
        print('Sign in as ' + login + ' in the browser. Cancel if a different account is selected.', flush=True)
        with tempfile.TemporaryDirectory(prefix='wb-github-qa-') as temporary:
            env = dict(os.environ, GH_CONFIG_DIR=temporary, GH_HOST='github.com')
            for key in ('GH_TOKEN', 'GITHUB_TOKEN', 'GH_ENTERPRISE_TOKEN', 'GITHUB_ENTERPRISE_TOKEN'):
                env.pop(key, None)
            # Device code stays on the attended terminal, never in a report.
            subprocess.run(['gh', 'auth', 'login', '--hostname', 'github.com', '--git-protocol', 'https',
                            '--web', '--scopes', 'read:org', '--insecure-storage'], env=env, check=True)
            result = subprocess.run(['gh', 'auth', 'token', '--hostname', 'github.com'], env=env,
                                    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=True)
            token = result.stdout.decode().strip()
            decision = authorize(token, 'qa/github-team-check', policy)
            del token, result
            if decision.get('login', '').casefold() != login.casefold():
                raise AuthorizationUnavailable('wrong_test_account')
            if decision['allowed'] is not expected:
                raise AuthorizationUnavailable('unexpected_authorization_decision')
            print(json.dumps({'login': login, 'allowed': decision['allowed'], 'status': 'passed'}), flush=True)
    print('Live team authorization passed; broader browser/TUI release cases remain required.')


if __name__ == '__main__':
    try:
        main()
    except (AuthorizationUnavailable, subprocess.CalledProcessError, OSError, ValueError):
        print('QA authorization probe failed; no release attestation emitted.', file=sys.stderr)
        sys.exit(1)
