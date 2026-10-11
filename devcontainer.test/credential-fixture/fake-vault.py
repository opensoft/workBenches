#!/usr/bin/env python3
"""Offline fake vault. No authentication, network or real secrets."""
import getpass
import json
import sys

args = sys.argv[1:]
command = sys.argv[0].rsplit('/', 1)[-1]
item_id = '00000000-0000-0000-0000-000000000001'
if command == 'bw':
    if args[0] in ('login', 'unlock'):
        print('FAKE_SESSION_TOKEN_01234567890123456789')
    elif args[:2] == ['list', 'items']:
        print(json.dumps([{'id': item_id, 'name': 'Codex fixture', 'type': 2, 'notes': 'NEVER-PRINT-THIS-NOTE'}]))
    elif args[:2] == ['get', 'notes']:
        print(json.dumps({'OPENAI_API_KEY': 'fake-only-integration-key'}))
    elif args[0] not in ('config', 'sync', 'logout'):
        sys.exit(1)
elif command == 'op':
    if args[:2] == ['account', 'add']:
        getpass.getpass('Enter your secret key: ')
        getpass.getpass('Enter the password for fixture@example.com: ')
        print('FAKE_SESSION_TOKEN_01234567890123456789')
    elif args[:2] == ['item', 'list']:
        print(json.dumps([{'id': 'fixtureitem', 'title': 'Codex fixture', 'vault': {'id': 'fixturevault'}}]))
    elif args[:2] == ['item', 'get']:
        print(json.dumps({'fields': [{'id': 'credential-json', 'label': 'credential JSON', 'value': 'NEVER-PRINT-THIS-FIELD'}]}))
    elif args[0] == 'read':
        print(json.dumps({'OPENAI_API_KEY': 'fake-only-integration-key'}))
    else:
        sys.exit(1)
else:
    sys.exit(1)
