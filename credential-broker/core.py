"""Company credential broker. SQLite stores versions/operations, never credential bodies."""
import contextlib
import hashlib
import json
import math
import os
from pathlib import Path
import re
import sqlite3
import subprocess
import time
import uuid

MAX_BYTES = 65536


class BrokerError(Exception):
    def __init__(self, status, code):
        self.status, self.code = status, code
        super().__init__(code)


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), allow_nan=False)


def https(value):
    from urllib.parse import urlsplit
    p = urlsplit(value)
    if p.scheme != 'https' or not p.hostname or p.username or p.password or p.fragment:
        raise ValueError('HTTPS endpoint required')
    return value


def has_refresh(value):
    if isinstance(value, dict):
        return any('refreshtoken' in re.sub('[^a-z]', '', k.lower()) or has_refresh(v) for k, v in value.items())
    return isinstance(value, list) and any(has_refresh(v) for v in value)


class AzureVault:
    """Managed identity only: never fall back to a user's Azure CLI credentials."""
    def __init__(self, client_id=None, identity_mode='managed'):
        from azure.identity import ManagedIdentityCredential, WorkloadIdentityCredential
        if identity_mode == 'managed':
            self.credential = ManagedIdentityCredential(client_id=client_id) if client_id else ManagedIdentityCredential()
        elif identity_mode == 'workload':
            # AKS projected service-account federation is explicit. Never use
            # DefaultAzureCredential or fall back to a workstation Azure cache.
            self.credential = WorkloadIdentityCredential(client_id=client_id)
        else:
            raise ValueError('Unsupported broker identity mode')
        self.clients = {}

    def client(self, profile):
        from azure.keyvault.secrets import SecretClient
        url = https(profile['vaultUrl'])
        if url not in self.clients:
            self.clients[url] = SecretClient(url, self.credential, retry_total=0, connection_timeout=5, read_timeout=15)
        return self.clients[url]

    def find(self, profile, operation):
        from azure.core.exceptions import ResourceNotFoundError
        try:
            for version in self.client(profile).list_properties_of_secret_versions(profile['secretName']):
                if (version.tags or {}).get('workbenches-operation') == operation:
                    return version.version
        except ResourceNotFoundError:
            pass
        return None

    def put(self, profile, credential, operation):
        # Recover an earlier write whose response/metadata commit was interrupted.
        version = self.find(profile, operation)
        if version:
            return version
        secret = self.client(profile).set_secret(profile['secretName'], canonical(credential),
            tags={'workbenches-operation': operation}, content_type='application/json')
        return secret.properties.version

    def get(self, profile, version):
        return json.loads(self.client(profile).get_secret(profile['secretName'], version).value)


class Broker:
    def __init__(self, config, vault):
        self.config, self.vault = config, vault
        self.path = Path(config['database'])
        self.path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        locations = set()
        for profile_id, profile in config['profiles'].items():
            if 'enabled' in profile and type(profile['enabled']) is not bool:
                raise ValueError('Profile enabled must be a JSON boolean')
            if not re.fullmatch(r'[a-zA-Z0-9_.:-]{1,180}', profile_id):
                raise ValueError('Invalid profile ID')
            if profile.get('enabled') is True:
                if profile.get('sharingApproved') is not True or profile.get('mode') not in ('portable', 'broker-refresh'):
                    raise ValueError('Sharing must be explicitly approved for an eligible mode')
                if not profile.get('validator') or not profile.get('accountId') or not profile.get('tenant'):
                    raise ValueError('Enabled profiles require a validator, expected account and tenant')
                if not isinstance(profile['accountId'], str) or not isinstance(profile['tenant'], str):
                    raise ValueError('Expected account and tenant must be immutable string IDs')
                if not isinstance(profile['validator'], list) or not Path(profile['validator'][0]).is_absolute():
                    raise ValueError('Validator must be an absolute administrator-managed command')
                if profile.get('refresher') and (not isinstance(profile['refresher'], list) or not Path(profile['refresher'][0]).is_absolute()):
                    raise ValueError('Refresher must be an absolute administrator-managed command')
                https(profile['vaultUrl'])
                if not re.fullmatch(r'[a-zA-Z0-9-]{1,127}', profile['secretName']):
                    raise ValueError('Invalid server-side secret name')
                location = (profile['vaultUrl'], profile['secretName'])
                if location in locations:
                    raise ValueError('Enabled profiles must not alias the same vault secret')
                locations.add(location)
        with self.db() as db:
            db.executescript('''
                CREATE TABLE IF NOT EXISTS profiles(
                    id TEXT PRIMARY KEY, version TEXT, state TEXT NOT NULL DEFAULT 'empty',
                    operation TEXT, expires REAL, checked REAL, reason TEXT);
                CREATE TABLE IF NOT EXISTS operations(
                    id TEXT PRIMARY KEY, profile TEXT NOT NULL, actor TEXT NOT NULL,
                    request_key TEXT NOT NULL, digest TEXT NOT NULL, expected TEXT,
                    version TEXT, kind TEXT NOT NULL, done INTEGER NOT NULL DEFAULT 0,
                    UNIQUE(actor,request_key));
                CREATE TABLE IF NOT EXISTS audit(
                    at REAL NOT NULL, actor TEXT NOT NULL, profile TEXT NOT NULL,
                    action TEXT NOT NULL, outcome TEXT NOT NULL, version TEXT);
            ''')
            for name in config['profiles']:
                db.execute('INSERT OR IGNORE INTO profiles(id) VALUES(?)', (name,))
        os.chmod(self.path, 0o600)

    @contextlib.contextmanager
    def db(self):
        db = sqlite3.connect(self.path, timeout=30)
        db.row_factory = sqlite3.Row
        try:
            db.execute('BEGIN IMMEDIATE')
            yield db
            db.commit()
        except BaseException:
            db.rollback()
            raise
        finally:
            db.close()

    def grants(self, identity, name):
        profile = self.config['profiles'].get(name, {})
        if profile.get('enabled') is not True:
            return set()
        rights = set()
        for grant in self.config.get('grants', []):
            # Both values come from a verified token, never an entered email.
            if grant['issuer'] == identity['iss'] and grant['subject'] == identity['sub']:
                rights.update(grant.get('profiles', {}).get(name, []))
        # Optional profile-level restriction applies even when multiple direct
        # grants exist. Never trust a GitHub name supplied by a client or token
        # claim: the administrator binds immutable OIDC subjects to GitHub IDs.
        if 'githubTeam' in profile and rights & {'use', 'publish'}:
            from github_team import permitted
            if not permitted(self.config, identity, profile['githubTeam']):
                rights -= {'use', 'publish'}
        return rights

    def authorize(self, identity, name, right):
        if right not in self.grants(identity, name):
            with self.db() as db:
                self.audit(db, identity, name if name in self.config['profiles'] else '<unknown-profile>', right, 'denied')
            raise BrokerError(403, 'profile_access_denied')
        return self.config['profiles'][name]

    @staticmethod
    def actor(identity):
        return canonical([identity['iss'], identity['sub']])

    def audit(self, db, identity, name, action, outcome, version=None):
        db.execute('INSERT INTO audit VALUES(?,?,?,?,?,?)',
                   (time.time(), self.actor(identity), name, action, outcome, version))

    def metadata(self, identity):
        result = []
        with self.db() as db:
            for name, profile in self.config['profiles'].items():
                rights = self.grants(identity, name)
                if not rights:
                    continue
                row = dict(db.execute('SELECT * FROM profiles WHERE id=?', (name,)).fetchone())
                result.append({'id': name, 'tenant': profile['tenant'], 'provider': profile['provider'],
                    'profile': profile['profile'], 'mode': profile['mode'], 'permissions': sorted(rights),
                    'version': row['version'], 'state': row['state'], 'expiresAt': row['expires'],
                    'lastCheckedAt': row['checked'], 'reason': row['reason']})
        return {'profiles': result}

    def adapter(self, profile, action, credential):
        command = profile.get('validator') if action == 'validate' else profile.get('refresher')
        if not command:
            raise BrokerError(422, 'provider_adapter_required')
        request = {'action': action, 'credential': credential, 'accountId': profile['accountId'],
                   'provider': profile['provider'], 'profile': profile['profile']}
        # No shell, no secrets in arguments/env or error output. Adapter is trusted code.
        try:
            done = subprocess.run(command, input=canonical(request).encode(), stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=30)
            raw = done.stdout
            if done.returncode or len(raw) > MAX_BYTES:
                raise ValueError()
            value = json.loads(raw)
            if not isinstance(value, dict):
                raise ValueError()
            canonical(value)
            return value
        except (OSError, ValueError, subprocess.TimeoutExpired):
            raise BrokerError(422, 'provider_validation_or_refresh_failed') from None

    def validate(self, profile, credential):
        if not isinstance(credential, dict) or len(canonical(credential).encode()) > MAX_BYTES:
            raise BrokerError(422, 'invalid_credential')
        value = self.adapter(profile, 'validate', credential)
        if value.get('accountId') != profile['accountId'] or value.get('valid') is not True:
            raise BrokerError(422, 'provider_account_mismatch')
        expiry = value.get('expiresAt')
        if expiry is not None and (type(expiry) not in (float, int) or not math.isfinite(expiry) or expiry <= time.time()):
            raise BrokerError(422, 'credential_expired')
        public = value.get('publicCredential', credential)
        if not isinstance(public, dict) or has_refresh(public):
            raise BrokerError(422, 'shared_refresh_token_forbidden')
        if profile['mode'] == 'portable' and has_refresh(credential):
            raise BrokerError(422, 'rotating_session_not_portable')
        if profile['mode'] == 'broker-refresh' and (not profile.get('refresher') or expiry is None):
            raise BrokerError(422, 'refresh_adapter_and_expiry_required')
        return value, public

    def fetch(self, identity, name):
        profile = self.authorize(identity, name, 'use')
        with self.db() as db:
            row = db.execute('SELECT * FROM profiles WHERE id=?', (name,)).fetchone()
            if row['state'] != 'ready' or not row['version']:
                raise BrokerError(409, 'credential_not_ready')
            version = row['version']
        credential = self.vault.get(profile, version)
        _, public = self.validate(profile, credential)
        with self.db() as db:
            current = db.execute('SELECT * FROM profiles WHERE id=?', (name,)).fetchone()
            if current['version'] != version or current['state'] != 'ready':
                raise BrokerError(409, 'version_changed')
            self.audit(db, identity, name, 'fetch', 'allowed', version)
        return {'version': version, 'credential': public}

    def publish(self, identity, name, credential, expected, request_key, kind='publish', reserved=None):
        profile = self.authorize(identity, name, 'maintain' if kind == 'refresh' else 'publish')
        if not isinstance(request_key, str) or not re.fullmatch('[a-zA-Z0-9-]{8,100}', request_key):
            raise BrokerError(400, 'invalid_idempotency_key')
        request_key = hashlib.sha256(request_key.encode()).hexdigest()
        digest = hashlib.sha256(canonical([name, expected, credential]).encode()).hexdigest()
        actor = self.actor(identity)
        with self.db() as db:
            old = db.execute('SELECT * FROM operations WHERE actor=? AND request_key=?', (actor, request_key)).fetchone()
            if old and (old['digest'] != digest or old['profile'] != name):
                raise BrokerError(409, 'idempotency_conflict')
            if old and old['done']:
                return {'version': old['version']}
        try:
            validation, _ = self.validate(profile, credential)
        except BrokerError:
            with self.db() as db:
                self.audit(db, identity, name, kind, 'validation_rejected')
            raise
        with self.db() as db:
            row = db.execute('SELECT * FROM profiles WHERE id=?', (name,)).fetchone()
            # Recheck after validation and serialize reservations across processes.
            old = db.execute('SELECT * FROM operations WHERE actor=? AND request_key=?', (actor, request_key)).fetchone()
            if old:
                if old['digest'] != digest or old['profile'] != name:
                    raise BrokerError(409, 'idempotency_conflict')
                if old['done']:
                    return {'version': old['version']}
                operation = old['id']
                if row['operation'] != operation:
                    raise BrokerError(409, 'publication_needs_reconciliation')
            else:
                if row['version'] != expected or (row['state'] in ('publishing', 'refreshing') and row['operation'] != reserved):
                    raise BrokerError(409, 'version_conflict')
                operation = reserved or uuid.uuid4().hex
                db.execute('INSERT INTO operations(id,profile,actor,request_key,digest,expected,kind) VALUES(?,?,?,?,?,?,?)',
                           (operation, name, actor, request_key, digest, expected, kind))
                db.execute("UPDATE profiles SET state='publishing',operation=?,checked=?,reason=NULL WHERE id=?", (operation, time.time(), name))
        # Pending operation is durable BEFORE a vault call. Failure leaves a retryable
        # reservation. KV versions are recovered by operation tag, not latest-version.
        import fcntl
        # All replicas MUST share the same local durable volume/host. One broker
        # deployment only; SQLite/flock is not a distributed multi-host database.
        lock = self.path.parent / ('publication-' + hashlib.sha256(name.encode()).hexdigest() + '.lock')
        with open(lock, 'a') as stream:
            fcntl.flock(stream, fcntl.LOCK_EX)
            with self.db() as db:
                op = db.execute('SELECT * FROM operations WHERE id=?', (operation,)).fetchone()
                if op['done']:
                    return {'version': op['version']}
                row = db.execute('SELECT operation FROM profiles WHERE id=?', (name,)).fetchone()
                if row['operation'] != operation:
                    raise BrokerError(409, 'publication_needs_reconciliation')
            try:
                version = self.vault.put(profile, credential, operation)
            except Exception:
                with self.db() as db:
                    self.audit(db, identity, name, kind, 'vault_pending')
                raise BrokerError(503, 'vault_publication_pending') from None
            return self.finish(identity, name, operation, version, validation.get('expiresAt'))

    def finish(self, identity, name, operation, version, expiry):
        with self.db() as db:
            row = db.execute('SELECT * FROM profiles WHERE id=?', (name,)).fetchone()
            if row['operation'] != operation:
                op = db.execute('SELECT * FROM operations WHERE id=?', (operation,)).fetchone()
                if op and op['done'] and op['version'] == version:
                    return {'version': version}
                raise BrokerError(409, 'publication_needs_reconciliation')
            db.execute("UPDATE profiles SET version=?,state='ready',operation=NULL,expires=?,checked=?,reason=NULL WHERE id=?",
                       (version, expiry, time.time(), name))
            db.execute('UPDATE operations SET done=1,version=? WHERE id=?', (version, operation))
            self.audit(db, identity, name, 'publish', 'committed', version)
        return {'version': version}

    def maintain(self, identity, name):
        profile = self.authorize(identity, name, 'maintain')
        now = time.time()
        with self.db() as db:
            row = dict(db.execute('SELECT * FROM profiles WHERE id=?', (name,)).fetchone())
            if row['state'] in ('publishing', 'refreshing', 'login_required', 'refresh_uncertain'):
                return {'state': row['state'], 'reason': row['reason']}
            if not row['version']:
                return {'state': 'empty'}
            due = row['expires'] is not None and row['expires'] < now + profile.get('refreshMarginSeconds', 900)
            if not due and row['checked'] and row['checked'] > now - 604800:
                return {'state': 'ready', 'checked': False}
            operation = uuid.uuid4().hex
            db.execute("UPDATE profiles SET state='refreshing',operation=?,checked=? WHERE id=?", (operation, now, name))
        try:
            credential = self.vault.get(profile, row['version'])
            if due and profile['mode'] == 'broker-refresh':
                # Never automatically repeat a consumed/ambiguous provider refresh.
                credential = self.adapter(profile, 'refresh', credential)['credential']
                return self.publish(identity, name, credential, row['version'], operation, 'refresh', operation)
            self.validate(profile, credential)
            with self.db() as db:
                db.execute("UPDATE profiles SET state='ready',operation=NULL,checked=? WHERE id=? AND operation=?",
                           (now, name, operation))
                self.audit(db, identity, name, 'health', 'valid', row['version'])
            return {'state': 'ready', 'checked': True}
        except Exception:
            with self.db() as db:
                # Preserve any pending vault publication for explicit recovery.
                current = db.execute('SELECT state FROM profiles WHERE id=?', (name,)).fetchone()
                state = 'refresh_uncertain' if current['state'] == 'publishing' else 'login_required'
                db.execute('UPDATE profiles SET state=?,reason=? WHERE id=? AND operation=?',
                           (state, 'maintainer_login_or_reconciliation_required', name, operation))
                self.audit(db, identity, name, 'maintenance', state)
            return {'state': state, 'reason': 'maintainer_login_or_reconciliation_required'}

    def reconcile(self, identity, name):
        profile = self.authorize(identity, name, 'maintain')
        with self.db() as db:
            row = dict(db.execute('SELECT * FROM profiles WHERE id=?', (name,)).fetchone())
        if not row['operation']:
            return {'state': row['state']}
        version = self.vault.find(profile, row['operation'])
        if not version:
            raise BrokerError(409, 'no_committed_vault_write_login_required')
        value, _ = self.validate(profile, self.vault.get(profile, version))
        return self.finish(identity, name, row['operation'], version, value.get('expiresAt'))

    def require_login(self, identity, name, expected):
        """Explicit maintainer recovery of a stalled refresh; never replay its token."""
        self.authorize(identity, name, 'maintain')
        with self.db() as db:
            row = db.execute('SELECT * FROM profiles WHERE id=?', (name,)).fetchone()
            if row['version'] != expected or row['state'] not in ('publishing', 'refreshing', 'refresh_uncertain') or (row['checked'] or 0) > time.time() - 120:
                raise BrokerError(409, 'reconciliation_or_wait_required')
            db.execute("UPDATE profiles SET state='login_required',operation=NULL,reason='maintainer_requested_new_login' WHERE id=?", (name,))
            self.audit(db, identity, name, 'require_login', 'allowed', expected)
        return {'state': 'login_required'}
