#!/usr/bin/env python3
"""Explicit company sync configuration/actions from the Profiles page."""
import argparse
import os
from pathlib import Path
import subprocess
import sys

from company_sync import Client, SyncError, account_token, atomic, endpoint, read_json
from credential_sync_client import ROOT, Sync, managed_path, roots
from setup_prompts import prompt, propagate_cancel, cancellation_signals
import setup_profiles


def ask(text, default=''):
    return prompt(text + (f' [{default}]' if default else '') + ': ') or default


def yes(text):
    return ask(text + ' [y/N]').lower() in ('yes', 'y')


def native_helper(action):
    command = ['bash', str(Path(__file__).with_name('credential-sync.sh')), action]
    try:
        import workbenches_host as host
    except ImportError:
        if os.environ.get('WORKBENCHES_HOST_RPC'):
            raise
        host = None
    result = host.run(command, timeout=30) if host else subprocess.run(command)
    propagate_cancel(result.returncode)
    if result.returncode:
        raise SyncError('workstation_helper_needs_attention')


def manage(profile):
    root = setup_profiles.account_root(profile)
    config_path = root / 'credential-sync.json'
    while True:
        config = read_json(config_path, {})
        print('\nCompany credential sync — ' + profile['name'])
        print('Broker: ' + config.get('brokerUrl', 'Not configured'))
        print('Synchronization: ' + ('Enabled' if config.get('enabled') else 'Disabled'))
        agent = read_json(ROOT / 'credential-sync-agent.json', {})
        import time
        active = agent.get('running') and agent.get('heartbeat', 0) > time.time() - 120
        print('Workstation background agent: ' + ('Running' if active else 'Stopped or needs attention'))
        state = read_json(root / 'credential-sync-state.json', {})
        print('Last check: ' + str(state.get('lastCheck', 'Not checked')))
        for key, value in state.get('entries', {}).items():
            print(key + ': ' + value.get('state', 'Not checked'))
        print('C Configure broker   A Add approved profile   R Check now')
        print('S Start background sync   T Stop background sync   D Disable this company')
        print('P Publish an existing local credential   F Fetch remote and replace local')
        print('B Back   Q Cancel')
        choice = ask('Action', 'b').lower()
        if choice == 'b':
            return
        try:
            if choice == 'c':
                organization = read_json(root / 'account-provider.json', {})
                url = endpoint(ask('Administrator-provided broker HTTPS URL', config.get('brokerUrl', organization.get('credentialBrokerUrl', ''))))
                tenant = setup_profiles.text(ask('Administrator-provided company tenant ID', config.get('tenant', organization.get('organizationId', ''))))
                if config.get('brokerUrl') and (url != config['brokerUrl'] or tenant != config.get('tenant')):
                    print('Changing brokers requires a separate company identity to prevent credential publication to the wrong service.')
                    continue
                if yes('Enable sync for this company? Only explicitly added profile paths will be read'):
                    native_helper('--install')
                    config.update(enabled=True, brokerUrl=url, tenant=tenant, entries=config.get('entries', []))
                    atomic(config_path, config)
                    print('Use company sign-in again to approve a background/offline session if needed. Your administrator must configure the broker audience.')
            elif choice == 'a':
                client = Client(config['brokerUrl'], lambda: account_token(root))
                rows = [r for r in client.call('profiles')['profiles'] if 'use' in r['permissions'] and r['tenant'] == config['tenant']]
                for index, row in enumerate(rows, 1):
                    print(f'{index}. {row["provider"]}/{row["profile"]} — {row["state"]} — {", ".join(row["permissions"])}')
                if not rows:
                    print('No approved profiles are available for this company identity. Ask your administrator to check profile grants and required GitHub team membership.')
                    continue
                selection = ask('Profile number (Enter skips)')
                if not selection:
                    continue
                if not selection.isdigit() or not 1 <= int(selection) <= len(rows):
                    raise SyncError('select_a_listed_profile')
                row = rows[int(selection) - 1]
                path = ask('Exact native profile credential JSON path (existing files must be private)')
                path = str(managed_path(path)) if path else ''
                if not path:
                    continue
                if any(e['profileId'] == row['id'] or e['credentialPath'] == path for e in config['entries']):
                    raise SyncError('profile_or_path_already_configured')
                for other_root in roots():
                    if other_root != root and any(e['credentialPath'] == path for e in read_json(other_root / 'credential-sync.json')['entries']):
                        raise SyncError('path_belongs_to_another_company')
                publish = 'publish' in row['permissions'] and yes('Publish approved local login changes for this shared company profile?')
                if yes(f'Allow workBenches to manage only this path: {path}?'):
                    config['entries'].append({'profileId': row['id'], 'credentialPath': path, 'publishChanges': publish})
                    atomic(config_path, config)
            elif choice == 'r':
                result = Sync(root).run(force=True)
                print('Check: ' + result.get('error', 'completed; see profile states above'))
            elif choice == 's':
                if not config.get('enabled'):
                    raise SyncError('configure_this_company_first')
                native_helper('--start')
            elif choice == 't':
                atomic(ROOT / 'credential-sync-control.json', {'stop': True})
                print('Background sync stop requested for this workstation.')
            elif choice == 'd' and config and yes('Disable company sync and its launch checks? Local credentials will be kept'):
                config['enabled'] = False; atomic(config_path, config)
            elif choice in ('p', 'f'):
                for index, entry in enumerate(config.get('entries', []), 1):
                    print(f'{index}. {entry["profileId"]} — {entry["credentialPath"]}')
                selected = ask('Profile number (Enter skips)')
                if selected.isdigit() and 1 <= int(selected) <= len(config.get('entries', [])):
                    entry = config['entries'][int(selected) - 1]
                    message = 'Publish this existing credential as a new shared version?' if choice == 'p' else 'Replace this local credential with the current broker version? Unpublished local changes will be discarded'
                    if yes(message):
                        Sync(root).run(force=True, only=entry['credentialPath'], adopt=choice == 'p', accept_remote=choice == 'f')
        except (SyncError, OSError, ValueError, KeyError):
            print('Company sync needs attention. Check sign-in, grants, broker configuration, and profile status. Credentials were preserved.')


def main():
    cancellation_signals()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('company')
    args = parser.parse_args()
    profiles = setup_profiles.load()['companies']
    selected = next((p for p in profiles if p['id'] == args.company), None)
    if not selected:
        raise SystemExit('Select a company from Profiles.')
    manage(selected)


if __name__ == '__main__':
    try:
        main()
    except (SyncError, OSError, ValueError, KeyError):
        print('Company synchronization needs attention; existing credentials were preserved.', file=sys.stderr)
        sys.exit(1)
