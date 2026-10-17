#!/usr/bin/env python3
"""Fictional test provider only; must never be used for real credentials."""
import json
import sys
import time

job = json.load(sys.stdin)
credential = job['credential']
if job['action'] == 'refresh':
    if credential.get('refresh_token') == 'fixture-denied':
        sys.exit(1)
    credential.update(access_token='fixture-renewed', refresh_token='fixture-rotated', expiresAt=time.time() + 7200)
    print(json.dumps({'credential': credential}))
else:
    public = {k: v for k, v in credential.items() if k != 'refresh_token'}
    print(json.dumps({'valid': credential.get('access_token', '').startswith('fixture-'),
                     'accountId': credential.get('accountId'), 'expiresAt': credential.get('expiresAt'),
                     'publicCredential': public}))
