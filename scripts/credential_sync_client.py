"""Opt-in company profile sync. Conflicts preserve local credentials for reconciliation."""
import os
from pathlib import Path
import random
import time
import uuid

from company_sync import Client, SyncError, account_token, atomic, digest, lock, read_json, safe_path
from openbenches_compat import config_root


def coordination_root():
    profile_root = config_root()
    legacy = profile_root.parent / 'workbenches'
    return legacy if legacy.exists() or legacy.is_symlink() else profile_root


ROOT = coordination_root()


def managed_path(value):
    path = safe_path(value)
    home = Path.home()
    personal_roots = [home / name / 'profiles/personal' for name in ('.claude-profiles', '.chatgpt-profiles', '.opencode-profiles', '.pi-profiles')]
    bare = [home / '.claude/.credentials.json', home / '.codex/auth.json', home / '.local/share/opencode/auth.json']
    if path in bare or any(path.is_relative_to(root) for root in personal_roots):
        raise SyncError('personal_credential_publication_forbidden')
    return path


def lease_path(path):
    return ROOT / 'sync-leases' / (digest(str(safe_path(path))) + '.lock')


def credential(path):
    path = safe_path(path)
    if not path.exists():
        return None
    if path.stat().st_mode & 0o077:
        raise SyncError('credential_file_must_be_private')
    return read_json(path)


class Sync:
    def __init__(self, root, client=None):
        self.root = safe_path(root)
        self.config = read_json(self.root / 'credential-sync.json')
        if type(self.config.get('enabled')) is not bool:
            raise SyncError('synchronization_consent_must_be_boolean')
        if not isinstance(self.config.get('tenant'), str) or not self.config['tenant']:
            raise SyncError('company_tenant_id_required')
        paths = [managed_path(e['credentialPath']) for e in self.config['entries']]
        if any(type(e.get('publishChanges', False)) is not bool for e in self.config['entries']):
            raise SyncError('publication_consent_must_be_boolean')
        ids = [e['profileId'] for e in self.config['entries']]
        if len(paths) != len(set(paths)) or len(ids) != len(set(ids)):
            raise SyncError('duplicate_profile_mapping')
        self.client = client or Client(self.config['brokerUrl'], lambda: account_token(self.root))
        self.state_path = self.root / 'credential-sync-state.json'

    def run(self, force=False, only=None, after_login=False, before_login=False, adopt=False, accept_remote=False):
        if self.config.get('enabled') is not True:
            return {'state': 'disabled'}
        with lock(self.root / 'credential-sync.lock'):
            state = read_json(self.state_path, {'entries': {}})
            try:
                remote_due = force or time.time() >= state.get('nextRemoteCheck', 0)
                listing = self.client.call('profiles') if remote_due else None
                if listing is not None:
                    state['metadata'] = {r['id']: r for r in listing['profiles']}
                    state['lastCheck'] = time.time()
                    state['nextRemoteCheck'] = time.time() + random.uniform(3240, 3960)
                for entry in self.config['entries']:
                    path = safe_path(entry['credentialPath'])
                    if only is not None and path != safe_path(only):
                        continue
                    local = state['entries'].setdefault(entry['profileId'], {})
                    try:
                        with lock(lease_path(path), nonblocking=True):
                            self.entry(entry, local, state, force, after_login, before_login, adopt, accept_remote)
                    except SyncError as error:
                        local['state'] = error.code
                    atomic(self.state_path, state)
                state.pop('error', None)
            except SyncError as error:
                state['error'] = error.code
                state['nextRemoteCheck'] = time.time() + 60
            except (OSError, ValueError, KeyError):
                state['error'] = 'company_login_or_configuration_required'
                state['nextRemoteCheck'] = time.time() + 60
            atomic(self.state_path, state)
            return state

    def entry(self, entry, local, state, force, after_login, before_login, adopt, accept_remote):
        name, path = entry['profileId'], safe_path(entry['credentialPath'])
        remote = state.get('metadata', {}).get(name)
        if remote is None:
            raise SyncError('profile_not_authorized')
        if remote['tenant'] != self.config['tenant']:
            raise SyncError('profile_belongs_to_another_company')
        if before_login:
            if 'publish' not in remote['permissions'] or not entry.get('publishChanges'):
                raise SyncError('publication_not_enabled')
            local['loginBase'] = remote['version']; local['state'] = 'login_started'
            return
        value = credential(path)
        if accept_remote:
            if 'use' not in remote['permissions']:
                raise SyncError('profile_not_authorized')
            downloaded = self.client.call('fetch', {'profileId': name})
            if credential(path) != value:
                raise SyncError('local_writer_conflict')
            atomic(path, downloaded['credential'])
            local.clear()
            local.update(version=downloaded['version'], hash=digest(downloaded['credential']), state='up_to_date', lastSync=time.time())
            return
        fingerprint = digest(value) if value is not None else None
        pending = local.get('pending')
        if value is not None and pending and pending.get('publicHash') == fingerprint:
            # Cleanup finished before a restart interrupted the baseline save.
            local.update(version=pending['publicVersion'], hash=fingerprint, state='published', lastSync=time.time())
            local.pop('pending', None); local.pop('loginBase', None)
            return
        baseline = local.get('hash')
        dirty = value is not None and fingerprint != baseline
        if dirty:
            # Unknown preexisting credentials are never automatically adopted.
            if baseline is None and not (adopt or after_login or local.get('pending')):
                raise SyncError('existing_local_credential_needs_approval')
            if not entry.get('publishChanges') or 'publish' not in remote['permissions']:
                raise SyncError('local_change_not_published')
            if remote['mode'] == 'broker-refresh' and not after_login and not local.get('pending', {}).get('login'):
                raise SyncError('interactive_login_publication_required')
            if not (after_login or adopt or local.get('pending')):
                if local.get('observedHash') != fingerprint:
                    local.update(observedHash=fingerprint, observedAt=time.time(), state='local_change_detected')
                    return
                if time.time() - local.get('observedAt', 0) < 2:
                    return
            # Fresh grant/version check for EVERY publication, including between polls.
            fresh = {r['id']: r for r in self.client.call('profiles')['profiles']}
            remote = fresh.get(name)
            if remote is None or 'publish' not in remote['permissions']:
                raise SyncError('profile_not_authorized')
            if remote['tenant'] != self.config['tenant']:
                raise SyncError('profile_belongs_to_another_company')
            expected = local.get('loginBase') if after_login and 'loginBase' in local else local.get('version')
            if adopt and 'version' not in local:
                expected = remote['version']
            pending = local.get('pending')
            if pending:
                expected = pending['expectedVersion']
            elif remote['version'] != expected:
                raise SyncError('version_conflict')
            if pending and pending['hash'] != fingerprint:
                raise SyncError('unresolved_publication_local_changed')
            if not pending:
                pending = {'id': uuid.uuid4().hex, 'hash': fingerprint, 'expectedVersion': expected, 'login': after_login}
                local['pending'] = pending
                # Write the idempotency key before network I/O; token remains only in its store.
                atomic(self.state_path, state)
            result = self.client.call('publish', {'profileId': name, 'credential': value,
                'expectedVersion': expected, 'idempotencyKey': pending['id']})
            remote['version'] = result['version']; state.setdefault('metadata', {})[name] = remote
            if remote['mode'] == 'broker-refresh':
                # Remove the newly logged-in refresh token from the local shared
                # profile once the authoritative bundle is safely stored server-side.
                downloaded = self.client.call('fetch', {'profileId': name})
                if credential(path) != value:
                    raise SyncError('local_writer_conflict')
                pending.update(publicHash=digest(downloaded['credential']), publicVersion=downloaded['version'])
                atomic(self.state_path, state)
                atomic(path, downloaded['credential'])
                result = downloaded
                fingerprint = digest(downloaded['credential'])
            # Keep the durable operation and old baseline until cleanup succeeds.
            # A failed fetch can then replay publication idempotently and retry.
            local.update(version=result['version'], hash=fingerprint, state='published', lastSync=time.time())
            local.pop('pending', None); local.pop('loginBase', None)
            return
        if value is None and baseline is not None:
            # Local logout/deletion is intentional; do not silently sign the user back in.
            raise SyncError('local_credential_removed')
        if 'use' not in remote['permissions']:
            raise SyncError('profile_not_authorized')
        if remote['state'] != 'ready':
            raise SyncError(remote['state'])
        if remote['version'] != local.get('version'):
            # Fetch rechecks authorization. Recheck local contents before replacing.
            result = self.client.call('fetch', {'profileId': name})
            if credential(path) != value:
                raise SyncError('local_writer_conflict')
            atomic(path, result['credential'])
            local.update(version=result['version'], hash=digest(result['credential']), lastSync=time.time())
        local['state'] = 'up_to_date'


def roots():
    # Only company IDs explicitly recorded by Profiles are eligible.
    import setup_profiles
    for profile in setup_profiles.load()['companies']:
        root = setup_profiles.account_root(profile)
        if (root / 'credential-sync.json').exists():
            yield root


def run_all(force=False, only=None, **options):
    results = {}
    companies = list(roots())
    mapped = set()
    for root in companies:
        config = read_json(root / 'credential-sync.json')
        if not config.get('enabled'):
            continue
        for entry in config['entries']:
            path = managed_path(entry['credentialPath'])
            if path in mapped:
                raise SyncError('credential_path_assigned_to_multiple_profiles')
            mapped.add(path)
    for root in companies:
        try:
            sync = Sync(root)
            if only is not None and not any(safe_path(e['credentialPath']) == safe_path(only) for e in sync.config['entries']):
                continue
            result = sync.run(force, only, **options)
            if only is not None:
                selected = {e['profileId'] for e in sync.config['entries'] if safe_path(e['credentialPath']) == safe_path(only)}
                result = dict(result, entries={key: val for key, val in result.get('entries', {}).items() if key in selected})
            results[root.name] = result
        except (SyncError, OSError, ValueError, KeyError):
            results[root.name] = {'error': 'company_sync_needs_attention'}
    return results
