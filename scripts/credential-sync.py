#!/usr/bin/env python3
"""Company credential synchronization CLI; prints metadata only."""
import argparse
import json
import os
import signal
import sys
import time

from company_sync import SyncError, atomic, lock, read_json, safe_path
from credential_sync_client import ROOT, lease_path, run_all


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group()
    action.add_argument('--watch', action='store_true')
    action.add_argument('--status', action='store_true')
    action.add_argument('--stop', action='store_true')
    action.add_argument('--lease-path')
    action.add_argument('--is-managed')
    action.add_argument('--before-launch')
    action.add_argument('--before-login')
    action.add_argument('--after-login')
    action.add_argument('--auth-failed')
    action.add_argument('--publish-local', help='Explicitly adopt a local credential for a configured shared profile')
    action.add_argument('--accept-remote', help='Explicitly replace the selected local credential with the current broker version')
    args = parser.parse_args()
    os.umask(0o077)
    if args.is_managed:
        from credential_sync_client import roots
        for root in roots():
            config = read_json(root / 'credential-sync.json')
            if config.get('enabled') and any(safe_path(e['credentialPath']) == safe_path(args.is_managed) for e in config['entries']):
                return 0
        return 1
    if args.lease_path:
        path = safe_path(lease_path(args.lease_path)); path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        print(path); return 0
    if args.stop:
        atomic(ROOT / 'credential-sync-control.json', {'stop': True}); return 0
    if args.status:
        from credential_sync_client import roots
        print(json.dumps({'agent': read_json(ROOT / 'credential-sync-agent.json', {'running': False})}))
        for root in roots():
            state = read_json(root / 'credential-sync-state.json', {})
            print(json.dumps({'company': root.name, 'lastCheck': state.get('lastCheck'), 'error': state.get('error'),
                'profiles': {key: value.get('state', 'not_checked') for key, value in state.get('entries', {}).items()}}))
        return 0
    only = args.before_launch or args.before_login or args.after_login or args.auth_failed or args.publish_local or args.accept_remote
    options = dict(after_login=bool(args.after_login), before_login=bool(args.before_login), adopt=bool(args.publish_local), accept_remote=bool(args.accept_remote))
    def tick():
        result = run_all(force=not args.watch, only=only, **options)
        bad = False
        for company, state in result.items():
            rows = {key: val.get('state') for key, val in state.get('entries', {}).items()}
            print(json.dumps({'company': company, 'profiles': rows, 'error': state.get('error')}), flush=True)
            bad |= bool(state.get('error')) or any(value not in ('up_to_date', 'published', 'login_started') for value in rows.values())
        return 1 if bad else 0
    if not args.watch:
        return tick()
    running = True
    def stop(*_):
        nonlocal running
        running = False
    signal.signal(signal.SIGTERM, stop); signal.signal(signal.SIGINT, stop)
    with lock(ROOT / 'credential-sync-agent.lock', nonblocking=True):
        atomic(ROOT / 'credential-sync-control.json', {'stop': False})
        try:
            while running:
                if read_json(ROOT / 'credential-sync-control.json', {}).get('stop'):
                    break
                atomic(ROOT / 'credential-sync-agent.json', {'running': True, 'heartbeat': time.time()})
                tick()
                for _ in range(30):
                    if not running or read_json(ROOT / 'credential-sync-control.json', {}).get('stop'):
                        break
                    time.sleep(1)
        finally:
            atomic(ROOT / 'credential-sync-agent.json', {'running': False, 'heartbeat': time.time()})
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (SyncError, OSError, ValueError, KeyError):
        print('Company synchronization needs attention; credentials were preserved.', file=sys.stderr)
        sys.exit(3)
