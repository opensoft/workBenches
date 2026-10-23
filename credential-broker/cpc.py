"""Scheduled CPC: weekly health sweeps, expiry-driven refresh on each scheduler tick."""
import argparse
import json
import os
from pathlib import Path
import random
import signal
import time

from company_sync import Client, SyncError, endpoint, read_json, request


class ServiceToken:
    def __init__(self, config):
        self.config, self.token, self.expiry = config, None, 0

    def __call__(self):
        if self.token and self.expiry > time.time() + 60:
            return self.token
        config = self.config
        secret = Path(config['clientSecretFile']).read_text().strip()
        value = request(endpoint(config['tokenEndpoint']), {'grant_type': 'client_credentials',
            'client_id': config['clientId'], 'client_secret': secret}, form=True)
        self.token, self.expiry = value['access_token'], time.time() + int(value['expires_in'])
        return self.token


def tick(client):
    results = []
    for profile in client.call('profiles')['profiles']:
        if 'maintain' not in profile['permissions']:
            continue
        try:
            value = client.call('maintain', {'profileId': profile['id']})
            results.append({'profileId': profile['id'], 'state': value.get('state', 'ready')})
        except SyncError as error:
            results.append({'profileId': profile['id'], 'state': error.code})
    # Credential bodies never enter reports/stdout. Container log collection can
    # route login_required/refresh_uncertain records to the organization's alerts.
    return results


def notify(config, results, seen):
    for row in results:
        name, state = row['profileId'], row['state']
        if state in ('login_required', 'refresh_uncertain', 'refreshing') and seen.get(name) != state:
            event = {'event': 'company_profile_needs_attention', 'profileId': name, 'state': state}
            print(json.dumps(event), flush=True)
            if config.get('alertsWebhookUrl'):
                token = Path(config['alertsBearerTokenFile']).read_text().strip() if config.get('alertsBearerTokenFile') else None
                request(endpoint(config['alertsWebhookUrl']), event, token, json_response=False)
            seen[name] = state
        elif state == 'ready':
            seen.pop(name, None)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--watch', action='store_true')
    args = parser.parse_args()
    config = read_json(os.environ['WORKBENCHES_CPC_CONFIG'])
    client = Client(config['brokerUrl'], ServiceToken(config))
    seen = {}
    running = True
    def stop(*_):
        nonlocal running
        running = False
    signal.signal(signal.SIGTERM, stop); signal.signal(signal.SIGINT, stop)
    while running:
        try:
            results = tick(client)
            print(json.dumps({'maintenance': results}), flush=True)
            notify(config, results, seen)
        except (SyncError, OSError, KeyError, ValueError):
            print(json.dumps({'state': 'maintenance_unavailable'}), flush=True)
        if not args.watch:
            break
        deadline = time.monotonic() + random.uniform(0.9, 1.1) * max(30, min(900, config.get('intervalSeconds', 300)))
        while running and time.monotonic() < deadline:
            time.sleep(min(1, max(0, deadline - time.monotonic())))


if __name__ == '__main__':
    main()
