#!/usr/bin/env python3
"""Unattended real broker probe; private pre-provisioned sessions, no prompts."""
import argparse
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'scripts'))
from company_sync import Client, SyncError, account_token, digest, read_json, safe_path


def run(config):
    if config.get('qaOnly') is not True or not config['profileId'].startswith('qa:'):
        raise SyncError('nonproduction_profile_required')
    users = config['users']
    if [u['login'] for u in users] != ['Opensoft-Test-User-1', 'Opensoft-Test-User-2']:
        raise SyncError('designated_qa_users_required')
    if safe_path(users[0]['sessionRoot']).resolve() == safe_path(users[1]['sessionRoot']).resolve():
        raise SyncError('distinct_qa_sessions_required')
    for user, allowed in zip(users, [True, False]):
        root = safe_path(user['sessionRoot'])
        client = Client(config['brokerUrl'], lambda: account_token(root))
        rows = [r for r in client.call('profiles')['profiles'] if r['id'] == config['profileId']]
        if bool(rows) != allowed:
            raise SyncError('unexpected_profile_visibility')
        if allowed and (rows[0]['tenant'] != config['tenant'] or 'use' not in rows[0]['permissions']):
            raise SyncError('unexpected_profile_permissions')
        try:
            value = client.call('fetch', {'profileId': config['profileId']})
        except SyncError as error:
            if allowed or error.status != 403:
                raise
        else:
            if not allowed:
                raise SyncError('denied_user_received_credential')
            credential = value['credential']
            if credential.get('accountId') != config['expectedAccountId'] or digest(credential) != config['expectedCredentialDigest']:
                raise SyncError('unexpected_qa_credential')
        print(json.dumps({'login': user['login'], 'allowed': allowed, 'status': 'passed'}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', required=True)
    path = safe_path(parser.parse_args().config)
    if path.stat().st_mode & 0o077:
        raise SyncError('private_qa_config_required')
    run(read_json(path))


if __name__ == '__main__':
    try:
        main()
    except (SyncError, OSError, ValueError, KeyError, TypeError):
        print('Unattended QA failed: check provisioning, permissions and session renewal; no interactive fallback.', file=sys.stderr)
        sys.exit(1)
