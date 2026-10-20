#!/usr/bin/env python3
"""Authorize the two designated GitHub QA users and save OAuth bundles to QA KV.

Only provisioning is attended. Device codes remain in process memory and expire;
only verified OAuth results are uploaded. No daily gh credential store is touched.
"""
import argparse
import concurrent.futures
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

SUBSCRIPTION = '297b2389-33bf-48c8-8deb-0b92838431e4'
VAULT = 'kv-openbenches-qa'
# Public GitHub CLI OAuth application ID, from cli/cli internal/authflow/flow.go.
CLIENT_ID = '178c6fc778ccc68e1d6a'
USERS = [('Opensoft-Test-User-1', 345520656), ('Opensoft-Test-User-2', 345521882)]


class ProvisionError(Exception):
    pass


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args):
        return None


def request(url, fields=None, token=None):
    headers = {'Accept': 'application/json', 'User-Agent': 'openBenches-QA-provisioning'}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    body = None if fields is None else urllib.parse.urlencode(fields).encode()
    try:
        with urllib.request.build_opener(NoRedirect()).open(
                urllib.request.Request(url, data=body, headers=headers), timeout=20) as response:
            raw = response.read(65537)
            if len(raw) > 65536:
                raise ValueError()
            return json.loads(raw)
    except (OSError, ValueError, urllib.error.URLError):
        raise ProvisionError('github_request_failed') from None


def store(login, value):
    name = 'github-' + login.lower() + '-oauth'
    # Never place credential values in argv, environment variables, or tool output.
    with tempfile.TemporaryDirectory(prefix='openbenches-qa-oauth-', dir='/dev/shm') as directory:
        path = Path(directory) / 'bundle.json'
        path.write_text(json.dumps(value))
        path.chmod(0o600)
        for attempt in range(12):
            result = subprocess.run(['az', 'keyvault', 'secret', 'set', '--subscription', SUBSCRIPTION,
                '--vault-name', VAULT, '--name', name, '--file', str(path), '--encoding', 'utf-8',
                '--content-type', 'application/json', '--tags', 'application=openBenches', 'environment=qa',
                'credentialType=github-oauth', '--query', 'id', '-o', 'tsv', '--only-show-errors'],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60)
            if result.returncode == 0:
                return name
            # Azure RBAC assignments can take a short period to propagate.
            if b'Forbidden' not in result.stderr and b'403' not in result.stderr:
                raise ProvisionError('qa_vault_write_failed')
            time.sleep(10)
    raise ProvisionError('qa_vault_authorization_unavailable')


def finish(login, user_id, device):
    deadline = time.monotonic() + device['expires_in']
    interval = max(int(device['interval']), 5)
    while time.monotonic() < deadline:
        time.sleep(interval)
        tokens = request('https://github.com/login/oauth/access_token', {
            'client_id': CLIENT_ID, 'device_code': device['device_code'],
            'grant_type': 'urn:ietf:params:oauth:grant-type:device_code'})
        error = tokens.get('error')
        if error == 'authorization_pending':
            continue
        if error == 'slow_down':
            interval = int(tokens.get('interval', interval + 5))
            continue
        if error or not tokens.get('access_token'):
            raise ProvisionError('device_authorization_failed_or_expired')
        user = request('https://api.github.com/user', token=tokens['access_token'])
        if user.get('id') != user_id or user.get('login', '').casefold() != login.casefold():
            raise ProvisionError('wrong_github_account_no_secret_written')
        scopes = set(tokens.get('scope', '').replace(',', ' ').split())
        if not scopes <= {'read:org', 'offline_access'} or 'read:org' not in scopes:
            raise ProvisionError('unexpected_oauth_scope_no_secret_written')
        now = time.time()
        value = {'schemaVersion': 1, 'provider': 'github', 'clientId': CLIENT_ID,
                 'login': login, 'githubId': user_id, 'createdAt': now, 'oauth': tokens}
        if tokens.get('expires_in'):
            value['expiresAt'] = now + int(tokens['expires_in'])
        if tokens.get('refresh_token_expires_in'):
            value['refreshExpiresAt'] = now + int(tokens['refresh_token_expires_in'])
        store(login, value)
        print(json.dumps({'login': login, 'status': 'stored', 'vault': VAULT,
                          'hasRefreshToken': bool(tokens.get('refresh_token')), 'scopes': sorted(scopes)}), flush=True)
        return login
    raise ProvisionError('device_authorization_expired')


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--user', choices=[login for login, _ in USERS])
    args = parser.parse_args()
    pending = []
    for login, user_id in USERS:
        if args.user and args.user != login:
            continue
        device = request('https://github.com/login/device/code', {
            'client_id': CLIENT_ID, 'scope': 'read:org offline_access'})
        if not all(k in device for k in ('device_code', 'user_code', 'verification_uri', 'expires_in', 'interval')):
            raise ProvisionError('device_authorization_unavailable')
        print(json.dumps({'login': login, 'userCode': device['user_code'],
                          'verificationUrl': device['verification_uri'], 'expiresIn': device['expires_in']}), flush=True)
        pending.append((login, user_id, device))
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
        futures = {executor.submit(finish, *args): args[0] for args in pending}
        failed = False
        for future in concurrent.futures.as_completed(futures):
            try:
                future.result()
            except (ProvisionError, OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired) as error:
                failed = True
                code = str(error) if isinstance(error, ProvisionError) else 'provisioning_failed'
                print(json.dumps({'login': futures[future], 'status': 'failed', 'reason': code}), flush=True)
        return int(failed)


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (ProvisionError, OSError, ValueError, KeyError, TypeError):
        print('QA provisioning failed; no token values emitted.', flush=True)
        raise SystemExit(1)
