#!/usr/bin/env python3
"""Per-user device enrollment, directional trust, revocation and SSH preservation."""
import base64
import copy
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT / 'scripts'), str(ROOT / 'credential-broker')]
from core import Broker, BrokerError
from devices import DeviceRegistry
from app import Application
from company_sync import SyncError, atomic, read_json
from device_keys import public_key, fingerprint, metadata
from device_trust import Devices, reconcile, signout, state_root


def key(byte=1):
    return 'ssh-ed25519 ' + base64.b64encode(struct.pack('>I', 11) + b'ssh-ed25519' + struct.pack('>I', 32) + bytes([byte]) * 32).decode()


class DeviceTrustTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.directory = Path(self.tmp.name)
        self.identity = {'iss': 'https://identity.example/realm', 'sub': 'immutable-brett'}
        self.config = dict(database=str(self.directory / 'broker.sqlite3'), issuer=self.identity['iss'], profiles={},
            deviceRegistry={'enabled': True, 'contexts': {'personal': {'enabled': True},
                'company:opensoft': {'enabled': True, 'members': [{'issuer': self.identity['iss'], 'subject': self.identity['sub']}]}}})
        self.registry = DeviceRegistry(Broker(self.config, None))
        self.context = 'personal'
        self.a, self.b = 'device-' + 'a' * 32, 'device-' + 'b' * 32
        self.tokens = {self.a: '1' * 64, self.b: '2' * 64}
        self.register(self.a, 1); self.register(self.b, 2)

    def call(self, operation, device=None, identity=None, context=None, **extra):
        data = dict(context=context or self.context, deviceId=device, deviceToken=self.tokens.get(device))
        data.update(extra)
        return self.registry.call(identity or self.identity, operation, data)

    def info(self, number):
        return dict(name='Raven' if number == 1 else 'Eagle', platform='Linux', username='brett',
                    publicKey=key(number), hostKey=key(number + 10), address='raven' if number == 1 else 'eagle', port=22)

    def register(self, device, number, **kwargs):
        return self.call('register', device, metadata=self.info(number), **kwargs)

    def denied(self, code, function):
        with self.assertRaises(BrokerError) as caught: function()
        self.assertEqual(caught.exception.code, code)

    def test_registration_is_not_approval_and_inventory_has_no_capabilities(self):
        listing = self.call('list')
        self.assertEqual(len(listing['devices']), 2)
        self.assertEqual(listing['connections'], [])
        self.assertNotIn('deviceToken', json.dumps(listing)); self.assertNotIn('capability', json.dumps(listing))
        self.assertEqual(self.call('sync', self.a)['authorized'], [])
        with self.registry.broker.db() as db:
            self.assertNotEqual(db.execute('SELECT capability FROM devices WHERE id=?', (self.a,)).fetchone()[0], self.tokens[self.a])

    def test_directional_approval_requires_destination_capability(self):
        self.call('request', self.b, peerId=self.a)
        self.denied('destination_device_required', lambda: self.call('approve', self.a, peerId=self.b, deviceToken=self.tokens[self.b]))
        self.call('approve', self.a, peerId=self.b)
        self.assertEqual([d['id'] for d in self.call('sync', self.a)['authorized']], [self.b])
        self.assertEqual(self.call('sync', self.b)['authorized'], [])
        self.call('request', self.b, peerId=self.a)
        self.assertEqual(self.call('list')['connections'][0]['state'], 'approved')

    def test_revoke_removes_only_one_direction(self):
        self.call('approve', self.a, peerId=self.b); self.call('approve', self.b, peerId=self.a)
        self.call('revoke', self.a, peerId=self.b)
        self.assertEqual(self.call('sync', self.a)['authorized'], [])
        self.assertEqual(len(self.call('sync', self.b)['authorized']), 1)

    def test_other_user_and_other_issuer_cannot_list_or_approve_owner_devices(self):
        other = dict(self.identity, sub='someone-else')
        self.assertEqual(self.call('list', identity=other)['devices'], [])
        self.denied('device_not_found', lambda: self.call('approve', self.a, identity=other, peerId=self.b))
        self.denied('device_identity_required', lambda: self.call('list', identity=dict(self.identity, iss='https://evil.example')))

    def test_company_membership_is_explicit_and_does_not_expose_personal_devices(self):
        self.assertEqual(self.call('list', context='company:opensoft')['devices'], [])
        self.denied('device_context_denied', lambda: self.call('list', context='company:opensoft', identity=dict(self.identity, sub='outsider')))
        self.denied('device_registry_disabled', lambda: self.call('list', context='company:unknown'))
        self.denied('device_not_found', lambda: self.call('sync', self.a, context='company:opensoft'))

    def test_disabled_feature_has_no_registry_access(self):
        self.config['deviceRegistry']['enabled'] = False
        self.denied('device_registry_disabled', lambda: self.call('list'))

    def test_retirement_revokes_and_cannot_be_resurrected(self):
        self.call('approve', self.a, peerId=self.b)
        self.call('forget', self.b, deviceToken=None)  # Owner can retire a lost device.
        self.assertEqual(self.call('sync', self.a)['authorized'], [])
        self.denied('device_registration_conflict', lambda: self.register(self.b, 2))
        self.assertEqual([d['id'] for d in self.call('list')['devices']], [self.a])

    def test_reregister_requires_capability_and_preserves_login_identity(self):
        self.denied('destination_device_required', lambda: self.register(self.a, 1, deviceToken='3' * 64))
        self.denied('register_new_device_for_new_login_key', lambda: self.register(self.a, 2))
        info = self.info(1); info['username'] = 'other'
        self.denied('register_new_device_for_new_login_key', lambda: self.call('register', self.a, metadata=info))

    def test_host_key_or_endpoint_change_invalidates_both_directions(self):
        for field, value in [('hostKey', key(50)), ('address', 'new-address'), ('port', 2222)]:
            self.call('approve', self.a, peerId=self.b); self.call('approve', self.b, peerId=self.a)
            info = self.info(1); info[field] = value
            self.call('register', self.a, metadata=info)
            self.assertEqual(self.call('list')['connections'], [])
            self.register(self.a, 1)

    def test_missing_server_configuration_cannot_be_approved(self):
        info = self.info(1); info['hostKey'] = ''
        self.call('register', self.a, metadata=info)
        self.denied('destination_ssh_not_configured', lambda: self.call('approve', self.a, peerId=self.b))

    def test_validation_rejects_private_keys_options_controls_and_root(self):
        for bad in ['-----BEGIN OPENSSH PRIVATE KEY-----', 'command="evil" ' + key(), 'ssh-ed25519 AAAA']:
            with self.assertRaises(ValueError): public_key(bad)
        for field, value in [('username', 'root'), ('username', 'brett\nroot'), ('address', '-oProxyCommand=evil'),
                             ('name', '\033[2J'), ('port', True), ('port', 65536)]:
            info = self.info(1); info[field] = value
            with self.assertRaises(ValueError): metadata(info)

    def test_sync_lease_is_bounded_and_not_secret_bearing(self):
        self.call('approve', self.a, peerId=self.b)
        result = self.call('sync', self.a)
        self.assertTrue(time.time() + 590 < result['expiresAt'] < time.time() + 601)
        self.assertEqual(result['authorized'][0]['fingerprint'], fingerprint(key(2)))

    def test_http_routes_authenticate_and_do_not_reflect_device_tokens(self):
        app = Application(self.registry.broker, lambda header: self.identity)
        data = json.dumps(dict(context='personal')).encode(); statuses = []
        body = b''.join(app({'REQUEST_METHOD': 'POST', 'PATH_INFO': '/v1/devices/list', 'CONTENT_LENGTH': str(len(data)),
                            'wsgi.input': io.BytesIO(data)}, lambda status, headers: statuses.append(status)))
        self.assertEqual(statuses, ['200 OK']); self.assertEqual(len(json.loads(body)['devices']), 2)
        self.assertNotIn(self.tokens[self.a].encode(), body)

    def test_private_file_reconciliation_preserves_foreign_keys_and_contexts(self):
        home = self.directory / 'home'; ssh = home / '.ssh'; ssh.mkdir(parents=True, mode=0o700)
        foreign = b'# manual configuration\n' + key(9).encode() + b' manual\n'
        path = ssh / 'authorized_keys'; path.write_bytes(foreign); path.chmod(0o600)
        item = dict(id=self.a, publicKey=key())
        reconcile('1' * 32, [item], time.time() + 600, home)
        reconcile('2' * 32, [dict(item, id=self.b)], time.time() + 600, home)
        self.assertTrue(path.read_bytes().startswith(foreign)); self.assertIn(b'restrict,pty', path.read_bytes())
        self.assertIn(b'expiry-time=', path.read_bytes()); self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        reconcile('1' * 32, [], 0, home)
        self.assertNotIn(b'workbenches-device:' + b'1' * 32, path.read_bytes())
        self.assertIn(b'workbenches-device:' + b'2' * 32, path.read_bytes())
        reconcile('2' * 32, [], 0, home); self.assertEqual(path.read_bytes(), foreign)

    def test_symlink_hardlink_and_unsafe_permission_refusal(self):
        home = self.directory / 'home'; ssh = home / '.ssh'; ssh.mkdir(parents=True, mode=0o700)
        victim = self.directory / 'victim'; victim.write_text('untouched')
        auth = ssh / 'authorized_keys'; auth.symlink_to(victim)
        with self.assertRaises(SyncError): reconcile('1' * 32, [], 0, home)
        auth.unlink(); os.link(victim, auth)
        with self.assertRaises(ValueError): reconcile('1' * 32, [], 0, home)
        auth.unlink(); auth.write_text('manual'); auth.chmod(0o666)
        with self.assertRaises(ValueError): reconcile('1' * 32, [], 0, home)
        self.assertEqual(victim.read_text(), 'untouched')

    def test_invalid_or_expired_lease_never_modifies_authorization(self):
        for expiry in [time.time() - 1, time.time() + 99999, float('inf'), float('nan')]:
            with self.assertRaises(ValueError): reconcile('1' * 32, [dict(id=self.a, publicKey=key())], expiry, self.directory / 'home')

    def local_client(self):
        root = self.directory / 'account'; root.mkdir(exist_ok=True)
        atomic(root / 'account-provider.json', {'issuer': self.identity['iss'], 'clientId': 'workbenches'})
        atomic(root / 'account-session.json', dict(issuer=self.identity['iss'], subject=self.identity['sub'], clientId='workbenches'))
        atomic(root / 'device-registry.json', dict(enabled=True, url='https://broker.example', context='personal'))
        registry, identity = self.registry, self.identity
        class Transport:
            def call(self, route, data): return registry.call(identity, route.removeprefix('devices/'), data)
        return Devices(root, Transport())

    def test_local_namespace_separates_accounts_contexts_and_registry_origins(self):
        session = dict(issuer=self.identity['iss'], subject=self.identity['sub'])
        values = {str(state_root(self.directory / root, dict(session, subject=sub), dict(url=url, context=context)))
            for root, sub, url, context in [('p', 'a', 'https://a', 'personal'), ('p', 'a', 'https://a', 'company:opensoft'),
                ('c', 'a', 'https://a', 'personal'), ('p', 'b', 'https://a', 'personal'), ('p', 'a', 'https://b', 'personal')]}
        self.assertEqual(len(values), 5)

    def test_signout_blocks_agent_renewal_and_removes_only_managed_lines(self):
        client = self.local_client(); client.state = {'id': self.a, 'token': self.tokens[self.a]}; atomic(client.path, client.state)
        home = self.directory / 'home'; home.mkdir()
        self.call('approve', self.a, peerId=self.b)
        with patch('device_trust.Path.home', return_value=home):
            client.sync(); self.assertIn(b'workbenches-device:', (home / '.ssh/authorized_keys').read_bytes())
            signout(client.root)
            self.assertEqual((home / '.ssh/authorized_keys').read_bytes(), b'')
            with self.assertRaises(ValueError): client.sync()

    def test_exposed_local_capability_and_session_files_are_refused(self):
        client = self.local_client(); atomic(client.path, {'id': self.a, 'token': self.tokens[self.a]})
        client.storage.chmod(0o777)
        with self.assertRaises(ValueError): Devices(client.root, client.client)
        client.storage.chmod(0o700)
        client.path.chmod(0o644)
        with self.assertRaises(ValueError): Devices(client.root, client.client)
        client.path.chmod(0o600); (client.root / 'account-session.json').chmod(0o644)
        with self.assertRaises(ValueError): Devices(client.root, client.client)

    def test_old_registry_client_cannot_renew_after_context_change(self):
        client = self.local_client(); client.state = {'id': self.a, 'token': self.tokens[self.a]}
        settings = read_json(client.root / 'device-registry.json'); settings['context'] = 'company:opensoft'
        atomic(client.root / 'device-registry.json', settings)
        with self.assertRaises(ValueError): client.sync()

    def test_connect_requires_approved_direction_and_pins_server_key(self):
        client = self.local_client(); client.state = {'id': self.a, 'token': self.tokens[self.a], 'keyPath': str(self.directory / '.ssh/workbenches' / self.a)}
        private = Path(client.state['keyPath']); private.parent.mkdir(parents=True); private.write_text('fake-never-uploaded'); private.chmod(0o600)
        peer = next(d for d in client.inventory()['devices'] if d['id'] == self.b)
        with patch('device_trust.Path.home', return_value=self.directory):
            with self.assertRaises(ValueError): client.connect_command(peer, client.inventory())
            self.call('approve', self.b, peerId=self.a)
            command = client.connect_command(peer, client.inventory())
        self.assertIn('StrictHostKeyChecking=yes', command); self.assertIn('IdentityAgent=none', command)
        self.assertIn('brett@eagle', command); self.assertIn(str(private), command)
        self.assertEqual((client.storage / ('known-' + self.b)).read_text(), 'wb-' + self.b + ' ' + key(12) + '\n')

    def test_registration_uses_native_host_for_keys_and_uploads_only_public_data(self):
        import device_trust as device
        client = self.local_client()
        home = self.directory / 'native-home'; home.mkdir()
        calls = []
        class Host:
            def read_text(self, path):
                self_path = '/etc/ssh/ssh_host_ed25519_key.pub'
                assert path == self_path
                return key(42)
            def run(self, argv, **kwargs):
                calls.append(argv)
                if argv[:2] == ['ssh-keygen', '-q']:
                    dest = Path(argv[argv.index('-f') + 1])
                    dest.write_text('PRIVATE-FIXTURE-NEVER-UPLOAD'); dest.chmod(0o600)
                    Path(str(dest) + '.pub').write_text(key(22))
                    output = ''
                elif argv[:2] == ['ssh-keygen', '-y']: output = key(22)
                else: output = {('uname', '-s'): 'Linux', ('id', '-un'): 'brett', ('hostname',): 'Native Raven'}[tuple(argv)]
                return subprocess.CompletedProcess(argv, 0, output, '')
        with patch.object(device, 'host', Host()), patch.object(device.Path, 'home', return_value=home):
            client.register()
            identifier = client.state['id']; token = client.state['token']
            client.register()
        self.assertEqual(client.state['id'], identifier); self.assertEqual(client.state['token'], token)
        self.assertEqual(sum(c[:2] == ['ssh-keygen', '-q'] for c in calls), 1)
        listing = self.call('list'); serialized = json.dumps(listing)
        self.assertNotIn('PRIVATE-FIXTURE', serialized); self.assertNotIn(token, serialized)
        registered = next(d for d in listing['devices'] if d['id'] == identifier)
        self.assertEqual(registered['publicKey'], key(22)); self.assertEqual(registered['hostKey'], key(42))
        self.assertEqual(client.path.stat().st_mode & 0o777, 0o600)

    def test_after_login_provisions_only_explicit_administrator_registry(self):
        import device_trust as device
        client = self.local_client(); (client.root / 'device-registry.json').unlink()
        config = read_json(client.root / 'account-provider.json')
        with patch.object(device, 'Devices') as factory, patch.object(device, 'start_agent'):
            device.after_login(client.root); factory.assert_not_called()
            config['deviceRegistry'] = {'url': 'https://broker.example', 'context': 'personal'}
            atomic(client.root / 'account-provider.json', config)
            factory.return_value.register.return_value = factory.return_value
            device.after_login(client.root)
            factory.assert_called_once_with(client.root)
            factory.return_value.sync.assert_called_once()
        self.assertTrue(read_json(client.root / 'device-registry.json')['enabled'])

    def test_forgotten_device_can_be_explicitly_replaced_but_not_auto_reregistered(self):
        client = self.local_client(); client.state = {'id': self.a, 'token': self.tokens[self.a]}
        atomic(client.path, client.state)
        self.call('forget', self.a)
        self.denied('device_registration_conflict', lambda: self.register(self.a, 1))
        home = self.directory / 'home'; home.mkdir()
        with patch('device_trust.Path.home', return_value=home): client.replace_registration()
        self.assertEqual(client.state, {}); self.assertEqual(read_json(client.path), {})

    def test_native_terminal_launch_detaches_without_shell_interpolation(self):
        import profile_devices as ui
        command = ['ssh', '-i', '/home/some user/key', '--', 'brett@eagle']
        with patch.object(ui, 'which', side_effect=lambda name: name == 'kitty'), patch.object(ui, 'native') as native:
            self.assertTrue(ui.launch(command))
        args = native.call_args.args[0]
        self.assertEqual(args[2], 'nohup "$@" </dev/null >/dev/null 2>&1 &')
        self.assertEqual(args[-len(command):], command)

    def test_tui_approval_requires_confirmation_and_uses_incoming_direction(self):
        import profile_devices as ui
        client = self.local_client(); client.state = dict(id=self.a, token=self.tokens[self.a], username='brett')
        peer = next(d for d in client.inventory()['devices'] if d['id'] == self.b)
        with patch.object(ui.setup_profiles, 'ROOT', client.root), patch.object(ui, 'Devices', return_value=client), \
             patch.object(client, 'register', return_value=client), patch.object(client, 'sync'), patch.object(ui, 'start_agent'), \
             patch.object(ui, 'choose', side_effect=[('enter', peer), ('enter', 'approve'), ('b', None)]), patch.object(ui, 'confirm', return_value=True) as confirm:
            ui.manage()
        self.assertIn('→ brett here', confirm.call_args.args[0])
        self.assertEqual(self.call('list')['connections'][0]['destination'], self.a)


@unittest.skipUnless(os.environ.get('WORKBENCHES_DEVICE_SSH_TEST') == '1', 'Use declared device-trust service for real sshd')
class RealSSHTests(unittest.TestCase):
    def test_real_login_direction_other_user_host_pin_and_revocation(self):
        with tempfile.TemporaryDirectory(prefix='wb-device-ssh-', dir=Path.home()) as temporary:
            directory = Path(temporary)
            source = directory / 'source'; other = directory / 'other-key'; host = directory / 'host'
            for path in (source, other, host):
                subprocess.run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-f', str(path)], check=True)
            home = directory / 'server/brett'; home.mkdir(parents=True)
            authorized = dict(id='device-' + 'a' * 32, publicKey=source.with_suffix('.pub').read_text())
            with socket.socket() as sock:
                sock.bind(('127.0.0.1', 0)); port = sock.getsockname()[1]
            config = directory / 'sshd_config'
            config.write_text(f'''Port {port}
ListenAddress 127.0.0.1
HostKey {host}
PidFile {directory}/sshd.pid
AuthorizedKeysFile {directory}/server/%u/.ssh/authorized_keys
PasswordAuthentication no
KbdInteractiveAuthentication no
UsePAM no
PermitRootLogin no
StrictModes yes
PerSourcePenalties no
LogLevel ERROR
''')
            server = subprocess.Popen(['sudo', '-n', '/usr/sbin/sshd', '-D', '-E', str(directory / 'sshd.log'), '-f', str(config)], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
            try:
                for _ in range(100):
                    if server.poll() is not None: self.fail(server.stderr.read().decode())
                    try:
                        with socket.create_connection(('127.0.0.1', port), timeout=.1): break
                    except OSError: time.sleep(.05)
                known = directory / 'known'; known.write_text('server ' + host.with_suffix('.pub').read_text())
                base = ['ssh', '-F', '/dev/null', '-o', 'BatchMode=yes', '-o', 'IdentitiesOnly=yes', '-o', 'IdentityAgent=none',
                    '-o', 'StrictHostKeyChecking=yes', '-o', 'GlobalKnownHostsFile=/dev/null', '-o', 'HostKeyAlias=server',
                    '-o', 'UserKnownHostsFile=' + str(known), '-o', 'ConnectTimeout=3', '-p', str(port)]
                def connect(identity=source, user='brett'):
                    return subprocess.run([*base, '-i', str(identity), user + '@127.0.0.1', 'printf trusted'], capture_output=True, timeout=8)
                self.assertNotEqual(connect().returncode, 0)  # Registration alone grants nothing.
                reconcile('a' * 32, [authorized], time.time() + 600, home)
                result = connect(); self.assertEqual(result.returncode, 0, result.stderr.decode() + subprocess.check_output(['sudo', '-n', 'cat', str(directory / 'sshd.log')], text=True)[-8000:]); self.assertEqual(result.stdout, b'trusted')
                self.assertNotEqual(connect(other).returncode, 0)
                self.assertNotEqual(connect(user='other').returncode, 0)
                known.write_text('server ' + other.with_suffix('.pub').read_text())
                self.assertNotEqual(connect().returncode, 0)
                known.write_text('server ' + host.with_suffix('.pub').read_text())
                reconcile('a' * 32, [], 0, home)
                self.assertNotEqual(connect().returncode, 0)
                expired = time.strftime('%Y%m%d%H%M%SZ', time.gmtime(time.time() - 60))
                (home / '.ssh/authorized_keys').write_text(f'expiry-time="{expired}",restrict,pty {public_key(authorized["publicKey"])}\n')
                self.assertNotEqual(connect().returncode, 0)
            finally:
                subprocess.run(['sudo', '-n', 'kill', str(server.pid)], check=False, capture_output=True)
                server.wait(timeout=10); server.stderr.close()


if __name__ == '__main__': unittest.main()
