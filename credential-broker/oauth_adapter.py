#!/usr/bin/env python3
"""Adapter for explicitly approved RFC 7662 introspection/refresh providers.

Not an adapter for Claude/Codex subscriptions. Configure only a provider that
supports these endpoints and independent broker-side refresh of shared sessions.
"""
import copy
import json
from pathlib import Path
import sys
import time

from company_sync import endpoint, read_json, request


def get_path(value, path):
    for key in path:
        value = value[key]
    return value


def put_path(value, path, item):
    parent = value
    for key in path[:-1]:
        parent = parent[key]
    parent[path[-1]] = item


def strip_refresh(value):
    if isinstance(value, dict):
        return {k: strip_refresh(v) for k, v in value.items() if k.lower().replace('_', '') not in ('refreshtoken', 'idtoken')}
    if isinstance(value, list):
        return [strip_refresh(v) for v in value]
    return value


def execute(config, job):
    credential = copy.deepcopy(job['credential'])
    client = {'client_id': config['clientId'], 'client_secret': Path(config['clientSecretFile']).read_text().strip()}
    if job['action'] == 'refresh':
        # Exactly one refresh attempt. The broker owns the uncertainty state.
        result = request(endpoint(config['tokenEndpoint']), {**client, 'grant_type': 'refresh_token',
            'refresh_token': get_path(credential, config['refreshTokenPath'])}, form=True)
        if config.get('rotatesRefreshToken', True) and not result.get('refresh_token'):
            raise ValueError('Missing rotated refresh token')
        put_path(credential, config['accessTokenPath'], result['access_token'])
        if result.get('refresh_token'):
            put_path(credential, config['refreshTokenPath'], result['refresh_token'])
        if config.get('expiresAtPath'):
            put_path(credential, config['expiresAtPath'], (time.time() + int(result['expires_in'])) * config.get('expiresAtScale', 1))
        return {'credential': credential}
    proof = request(endpoint(config['introspectionEndpoint']), {**client,
        'token': get_path(credential, config['accessTokenPath']), 'token_type_hint': 'access_token'}, form=True)
    audiences = proof.get('aud', [])
    if isinstance(audiences, str):
        audiences = [audiences]
    valid = proof.get('active') is True
    valid &= bool(config.get('expectedAudience')) and config['expectedAudience'] in audiences
    valid &= set(config.get('requiredScopes', [])).issubset(set(proof.get('scope', '').split()))
    public = strip_refresh(credential)
    if config.get('refreshTokenPath'):
        parent = public
        try:
            for key in config['refreshTokenPath'][:-1]: parent = parent[key]
            parent.pop(config['refreshTokenPath'][-1], None)
        except (KeyError, TypeError):
            pass
    return {'valid': valid, 'accountId': proof.get(config.get('accountClaim', 'sub')),
            'expiresAt': proof.get('exp'), 'publicCredential': public}


if __name__ == '__main__':
    try:
        config = read_json(sys.argv[1])
        value = json.loads(sys.stdin.buffer.read(65537))
        print(json.dumps(execute(config, value), allow_nan=False))
    except Exception:
        # Provider responses and exception messages can contain credentials.
        sys.exit(1)
