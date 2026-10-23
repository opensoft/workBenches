#!/usr/bin/env python3
"""Single-writer QA OAuth renewal and live GitHub identity/team verification.

Run by the QA coordinator. Azure CLI is an explicit provisioning transport here,
never a credential-broker fallback. No credential values are printed or exported.
"""
import argparse
import copy
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import time

SPEC = importlib.util.spec_from_file_location('provision', Path(__file__).with_name('provision-github-qa-sessions.py'))
PROVISION = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PROVISION)

# The workflow runs every four hours. A ten-minute expiry threshold can skip a
# session which expires before the next run, leaving unattended QA with a dead
# token between scheduled checks. Include the interval and scheduling margin.
REFRESH_AHEAD_SECONDS = 4 * 60 * 60 + 15 * 60


class SessionError(Exception):
    pass


def load(login):
    result = subprocess.run(['az', 'keyvault', 'secret', 'show', '--subscription', PROVISION.SUBSCRIPTION,
        '--vault-name', PROVISION.VAULT, '--name', 'github-' + login.lower() + '-oauth',
        '--query', 'value', '-o', 'tsv', '--only-show-errors'],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60)
    if result.returncode:
        raise SessionError('qa_vault_read_failed')
    try:
        return json.loads(result.stdout)
    except ValueError:
        raise SessionError('invalid_qa_session') from None


def validate(bundle, login, user_id):
    if (bundle.get('provider') != 'github' or bundle.get('clientId') != PROVISION.CLIENT_ID
            or bundle.get('login') != login or bundle.get('githubId') != user_id
            or bundle.get('state', 'ready') != 'ready'):
        raise SessionError('session_identity_or_state_invalid')
    tokens = bundle.get('oauth', {})
    scopes = set(tokens.get('scope', '').replace(',', ' ').split())
    if 'read:org' not in scopes or not scopes <= {'read:org', 'offline_access'}:
        raise SessionError('unexpected_qa_scope')
    return tokens


def renew(bundle, login, user_id, force=False):
    tokens = validate(bundle, login, user_id)
    if not force and bundle.get('expiresAt', 0) > time.time() + REFRESH_AHEAD_SECONDS:
        return bundle, False
    if not tokens.get('refresh_token'):
        raise SessionError('reauthorization_required')
    # Persist consumption intent before rotating a one-use refresh token. A
    # crash/ambiguous response must not cause automatic replay of the old token.
    intent = copy.deepcopy(bundle)
    intent['state'] = 'renewal-in-progress'
    intent['oauth'].pop('refresh_token', None)
    PROVISION.store(login, intent)
    response = PROVISION.request('https://github.com/login/oauth/access_token', {
        'client_id': PROVISION.CLIENT_ID, 'grant_type': 'refresh_token',
        'refresh_token': tokens['refresh_token']})
    if response.get('error') or not response.get('access_token') or not response.get('refresh_token'):
        raise SessionError('reauthorization_required_after_failed_renewal')
    candidate = dict(bundle, state='ready', oauth=response, renewedAt=time.time(),
                     expiresAt=time.time() + int(response['expires_in']),
                     refreshExpiresAt=time.time() + int(response['refresh_token_expires_in']))
    validate(candidate, login, user_id)
    user = PROVISION.request('https://api.github.com/user', token=response['access_token'])
    if user.get('id') != user_id or user.get('login', '').casefold() != login.casefold():
        raise SessionError('renewed_identity_mismatch')
    PROVISION.store(login, candidate)
    return candidate, True


def team_member(bundle):
    token = bundle['oauth']['access_token']
    user = PROVISION.request('https://api.github.com/user', token=token)
    if user.get('id') != bundle['githubId'] or user.get('login', '').casefold() != bundle['login'].casefold():
        raise SessionError('live_identity_mismatch')
    found = False
    for page in range(1, 101):
        teams = PROVISION.request('https://api.github.com/user/teams?per_page=100&page=' + str(page), token=token)
        if not isinstance(teams, list):
            raise SessionError('invalid_team_response')
        for team in teams:
            found |= (team['organization']['login'].casefold() == 'opensoft-testing'
                      and team['slug'] == 'workbenches-qa-allowed')
        if len(teams) < 100:
            return found
    raise SessionError('incomplete_membership_pagination')


def run(force=False):
    results = []
    for login, user_id in PROVISION.USERS:
        bundle, rotated = renew(load(login), login, user_id, force)
        allowed = team_member(bundle)
        if allowed != (user_id == PROVISION.USERS[0][1]):
            raise SessionError('unexpected_live_team_authorization')
        result = {'login': login, 'githubId': user_id, 'allowed': allowed,
                  'renewed': rotated, 'status': 'passed', 'vault': PROVISION.VAULT}
        results.append(result)
        print(json.dumps(result), flush=True)
    return results


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--refresh', action='store_true', help='Prove real token rotation even before expiry')
    args = parser.parse_args()
    directory = Path.home() / '.cache/openbenches-qa'
    if directory.is_symlink():
        raise SessionError('private_coordinator_storage_required')
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    directory.chmod(0o700)
    fd = os.open(directory / 'github-session.lock', os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        run(args.refresh)


if __name__ == '__main__':
    try:
        main()
    except (SessionError, PROVISION.ProvisionError, OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired) as error:
        code = str(error) if isinstance(error, (SessionError, PROVISION.ProvisionError)) else 'qa_session_check_failed'
        print(json.dumps({'status': 'failed', 'reason': code}), flush=True)
        raise SystemExit(1)
