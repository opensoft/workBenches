"""User-scoped device enrollment and expiring SSH authorization reconciliation."""
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import subprocess
import time
import uuid
from datetime import datetime, timezone

from company_sync import Client, SyncError, account_token, atomic, endpoint, lock, read_json, safe_path
from device_keys import metadata, public_key
import setup_profiles

try:
    import workbenches_host as host
except ImportError:
    if os.environ.get('WORKBENCHES_HOST_RPC'): raise
    host = None

HERE = Path(__file__).resolve().parent


def native(argv, **kwargs):
    result = (host.run if host else subprocess.run)(argv, text=True, capture_output=True, timeout=30, **kwargs)
    if result.returncode: raise ValueError('Native SSH helper failed; check OpenSSH and file permissions.')
    return result.stdout.strip()


def which(name):
    return host.which(name) if host else shutil.which(name)


def secure_file(path):
    path = safe_path(path)
    if path.exists():
        status = path.stat()
        if status.st_uid != os.getuid() or status.st_nlink != 1 or not path.is_file() or status.st_mode & 0o022:
            raise ValueError('SSH files must belong to this user and must not be writable by other users.')
    return path


def private_json(path, default=None):
    path = secure_file(path)
    if path.exists() and path.stat().st_mode & 0o077:
        raise ValueError('Device/session capability files must be private (mode 600).')
    return read_json(path, default)


def write_bytes(path, value):
    import tempfile
    path = secure_file(path)
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    secure_directory(path.parent)
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as out:
        tmp = Path(out.name)
        try:
            out.write(value); out.flush(); os.fsync(out.fileno())
            os.replace(tmp, path)
        finally: tmp.unlink(missing_ok=True)


def secure_directory(path):
    path = safe_path(path)
    status = path.stat()
    if status.st_uid != os.getuid() or not path.is_dir() or status.st_mode & 0o022:
        raise ValueError('SSH directories must belong to this user and not be writable by other users.')


def reconcile(namespace, authorized, expires_at, home=None):
    """Replace only this context's managed keys. Existing user grants stay intact."""
    if not re.fullmatch(r'[a-f0-9]{32}', namespace): raise ValueError('Invalid local SSH namespace')
    now = time.time()
    if authorized and (type(expires_at) not in (int, float) or not now < expires_at <= now + 610):
        raise ValueError('Invalid SSH authorization lease')
    ssh = safe_path((home or Path.home()) / '.ssh')
    ssh.mkdir(mode=0o700, parents=True, exist_ok=True); secure_directory(ssh)
    path = secure_file(ssh / 'authorized_keys')
    marker = b' # workbenches-device:' + namespace.encode() + b':'
    with lock(ssh / 'workbenches-keys.lock'):
        old = path.read_bytes() if path.exists() else b''
        if len(old) > 1024 * 1024: raise ValueError('authorized_keys is too large to safely reconcile')
        kept = b''.join(line for line in old.splitlines(keepends=True) if marker not in line)
        lines = []
        stamp = datetime.fromtimestamp(expires_at, timezone.utc).strftime('%Y%m%d%H%M%SZ') if authorized else ''
        for item in authorized:
            key = public_key(item['publicKey'])
            if not re.fullmatch(r'device-[a-f0-9]{32}', item['id']): raise ValueError('Invalid approved device')
            lines.append(f'expiry-time="{stamp}",restrict,pty {key} # workbenches-device:{namespace}:{item["id"]}\n'.encode())
        if lines and kept and not kept.endswith(b'\n'): kept += b'\n'
        value = kept + b''.join(lines)
        if value != old: write_bytes(path, value)


def state_root(root, session, settings):
    owner = json.dumps([str(root), session['issuer'], session['subject'], settings['url'], settings['context']], separators=(',', ':'))
    return safe_path(Path(root) / 'devices' / hashlib.sha256(owner.encode()).hexdigest()[:32])


class Devices:
    def __init__(self, root, client=None):
        self.root = safe_path(root)
        self.config = read_json(self.root / 'account-provider.json')
        self.settings = read_json(self.root / 'device-registry.json')
        if self.settings.get('enabled') is not True: raise ValueError('Device registration is not configured.')
        session = private_json(self.root / 'account-session.json')
        if session.get('issuer') != self.config['issuer'] or session.get('clientId') != self.config['clientId'] or not session.get('subject'):
            raise ValueError('Sign into the configured account before using Devices.')
        self.storage = state_root(root, session, self.settings)
        self.storage.mkdir(mode=0o700, parents=True, exist_ok=True)
        self.namespace = self.storage.name
        self.path = self.storage / 'registration.json'
        self.client = client or Client(endpoint(self.settings['url']), lambda: account_token(self.root))
        self.context = self.settings['context']
        if not re.fullmatch(r'personal|company:[a-zA-Z0-9_.-]{1,100}', self.context): raise ValueError('Invalid registry context')
        self.state = private_json(self.path, {})

    def call(self, operation, **data):
        payload = dict(context=self.context, deviceId=self.state.get('id'), deviceToken=self.state.get('token'))
        payload.update(data)
        return self.client.call('devices/' + operation, payload)

    def register(self):
        with lock(self.storage / 'registration.lock'):
            self.state = private_json(self.path, {})
            if self.state.get('retired'): raise ValueError('This registration was forgotten. Configure Devices again to enroll a new device.')
            if not self.state:
                self.state = dict(id='device-' + uuid.uuid4().hex, token=secrets.token_hex(32))
                atomic(self.path, self.state)  # Persist intent before network; retries reuse the same capability.
            if not re.fullmatch(r'device-[a-f0-9]{32}', self.state.get('id', '')) or not re.fullmatch(r'[a-f0-9]{64}', self.state.get('token', '')):
                raise ValueError('Invalid local device registration')
            ssh = safe_path(Path.home() / '.ssh')
            ssh.mkdir(mode=0o700, exist_ok=True); secure_directory(ssh)
            directory = ssh / 'workbenches'
            directory.mkdir(mode=0o700, exist_ok=True); secure_directory(directory)
            key = secure_file(directory / self.state['id'])
            pub = secure_file(Path(str(key) + '.pub'))
            if not key.exists():
                if self.state.get('registeredAt'): raise ValueError('The registered login key is missing. Replace the local registration in Devices.')
                if pub.exists(): raise ValueError('Existing public key has no private key; register a new device.')
                native(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-C', 'workbenches-device', '-f', str(key)])
            if key.stat().st_mode & 0o077: raise ValueError('Device private key must be private (mode 600).')
            # Derive public data natively; never read or upload the private key bytes.
            key_data = native(['ssh-keygen', '-y', '-P', '', '-f', str(key)])
            host_key = ''
            try:
                host_key = public_key(host.read_text('/etc/ssh/ssh_host_ed25519_key.pub') if host else
                                      Path('/etc/ssh/ssh_host_ed25519_key.pub').read_text())
            except (OSError, ValueError): pass
            system = native(['uname', '-s'])
            if system not in ('Linux', 'Darwin'): raise ValueError('Devices currently supports Linux, WSL, and macOS.')
            label = self.settings.get('name') or native(['hostname'])
            info = metadata(dict(name=label, platform=system, username=native(['id', '-un']), publicKey=key_data,
                                 hostKey=host_key, address=self.settings.get('address', ''), port=self.settings.get('port', 22)))
            self.call('register', metadata=info)
            self.state.update(keyPath=str(key), username=info['username'], registeredAt=time.time())
            atomic(self.path, self.state)
        return self

    def inventory(self):
        return self.call('list')

    def sync(self):
        with lock(self.root / 'device-operation.lock'):
            current = read_json(self.root / 'device-registry.json')
            if current.get('enabled') is not True or any(current.get(k) != self.settings.get(k) for k in ('url', 'context')):
                raise ValueError('Registry settings changed; reopen Devices.')
            if read_json(self.root / 'device-session-control.json', {}).get('signedOut'):
                raise ValueError('Sign into this account to renew device access.')
            try:
                response = self.call('sync')
                reconcile(self.namespace, response['authorized'], response['expiresAt'])
                atomic(self.storage / 'status.json', {'checkedAt': time.time(), 'incoming': len(response['authorized']), 'error': None})
            except (SyncError, ValueError, OSError, KeyError):
                # Offline leases are never extended; expiry-time bounds old access.
                atomic(self.storage / 'status.json', {'checkedAt': time.time(), 'error': 'Sign-in, registry or SSH permissions need attention.'})
                raise

    def replace_registration(self):
        with lock(self.storage / 'registration.lock'):
            with lock(self.root / 'device-operation.lock'):
                self.state = private_json(self.path, {})
                if self.state.get('id'):
                    self.call('forget')
                reconcile(self.namespace, [], 0)
                self.state = {}
                atomic(self.path, self.state)

    def forget(self, peer):
        if peer['id'] == self.state['id']:
            with lock(self.root / 'device-operation.lock'):
                self.call('forget', deviceId=peer['id'])
                reconcile(self.namespace, [], 0)
                self.state['retired'] = True; atomic(self.path, self.state)
        else:
            self.call('forget', deviceId=peer['id'])
            self.sync()

    def connect_command(self, peer, inventory):
        if not any(g['source'] == self.state['id'] and g['destination'] == peer['id'] and g['state'] == 'approved'
                   for g in inventory['connections']): raise ValueError('Ask the destination account to approve this device first.')
        peer = dict(metadata(peer), id=peer['id'])
        if not peer['address'] or not peer['hostKey']: raise ValueError('The destination needs an SSH address and registered server key.')
        key = secure_file(self.state['keyPath'])
        if key != Path.home() / '.ssh/workbenches' / self.state['id'] or not key.is_file() or key.stat().st_mode & 0o077:
            raise ValueError('Device login key is missing or has moved.')
        known = secure_file(self.storage / ('known-' + peer['id']))
        write_bytes(known, ('wb-' + peer['id'] + ' ' + peer['hostKey'] + '\n').encode())
        return ['ssh', '-F', '/dev/null', '-o', 'IdentitiesOnly=yes', '-o', 'IdentityAgent=none',
                '-o', 'ForwardAgent=no', '-o', 'StrictHostKeyChecking=yes', '-o', 'GlobalKnownHostsFile=/dev/null',
                '-o', 'UserKnownHostsFile=' + str(known), '-o', 'HostKeyAlias=wb-' + peer['id'],
                '-o', 'BatchMode=yes', '-i', str(key), '-p', str(peer['port']), '--', peer['username'] + '@' + peer['address']]


def start_agent():
    native(['bash', str(HERE / 'device-trust.sh'), '--start'])


def configured_roots():
    root = setup_profiles.ROOT
    return [r for r in [root, *(root / 'identities').glob('*')] if (r / 'device-registry.json').is_file()]


def signout(root):
    root = safe_path(root)
    if not (root / 'devices').exists() and not (root / 'device-registry.json').exists(): return
    safe_path(root / 'devices')
    with lock(root / 'device-operation.lock'):
        atomic(root / 'device-session-control.json', {'signedOut': True})
        for path in (root / 'devices').glob('*/registration.json'):
            reconcile(path.parent.name, [], 0)


def check_all():
    for root in configured_roots():
        try:
            settings = read_json(root / 'device-registry.json')
            if settings.get('enabled') is not True:
                signout(root); continue
            session_path = root / 'account-session.json'
            if not session_path.exists(): signout(root); continue
            Devices(root).register().sync()
        except (SyncError, OSError, ValueError, KeyError, subprocess.TimeoutExpired) as error:
            if isinstance(error, SyncError) and error.status in (401, 403, 404, 409):
                try: signout(root)
                except (OSError, ValueError, SyncError): pass
            # Each context is independent. Never log session/capability/error bodies.
            continue


def after_login(root):
    settings_path = Path(root) / 'device-registry.json'
    try:
        if not settings_path.exists():
            enrollment = read_json(Path(root) / 'account-provider.json').get('deviceRegistry')
            if not enrollment: return
            endpoint(enrollment['url'])
            if not re.fullmatch(r'personal|company:[a-zA-Z0-9_.-]{1,100}', enrollment['context']):
                raise ValueError('Invalid administrator device context')
            atomic(settings_path, dict(enabled=True, url=enrollment['url'], context=enrollment['context'], address='', port=22))
        if read_json(settings_path).get('enabled') is not True: return
        atomic(Path(root) / 'device-session-control.json', {'signedOut': False})
        Devices(root).register().sync()
        start_agent()
        print('This user/device is registered. Incoming SSH still requires explicit approval in Devices.')
    except (SyncError, OSError, ValueError, KeyError, TypeError, AttributeError, subprocess.TimeoutExpired):
        print('Account signed in; device registration needs attention in Profiles → Devices.')
