#!/usr/bin/env python3
"""Broker/client/CPC isolation and failure tests; fictional provider and vault only."""
import copy
import importlib.util
import io
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT / 'scripts'), str(ROOT / 'credential-broker')]
from core import Broker, BrokerError
from app import Application, OIDC
from company_sync import SyncError, atomic, read_json
from credential_sync_client import Sync
from cpc import tick, notify


class Vault:
    def __init__(self):
        self.values = {}; self.operations = {}; self.fail_after = False; self.counter = 0

    def find(self, profile, operation):
        return self.operations.get(operation)

    def put(self, profile, credential, operation):
        if operation not in self.operations:
            self.counter += 1; version = str(self.counter)
            self.operations[operation] = version; self.values[version] = copy.deepcopy(credential)
        if self.fail_after:
            self.fail_after = False
            raise OSError('fixture disconnected after write')
        return self.operations[operation]

    def get(self, profile, version):
        return copy.deepcopy(self.values[version])


class Transport:
    def __init__(self, broker, identity):
        self.broker, self.identity = broker, identity

    def call(self, route, data=None):
        try:
            if route == 'profiles': return self.broker.metadata(self.identity)
            name = data['profileId']
            if route == 'fetch': return self.broker.fetch(self.identity, name)
            if route == 'publish': return self.broker.publish(self.identity, name, data['credential'], data['expectedVersion'], data['idempotencyKey'])
            if route == 'maintain': return self.broker.maintain(self.identity, name)
        except BrokerError as error:
            raise SyncError(error.code, error.status) from None


class CompanySyncTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.root_patch = patch('credential_sync_client.ROOT', self.root / 'local-config')
        self.root_patch.start(); self.addCleanup(self.root_patch.stop)
        self.user = {'iss': 'https://identity.example/realm', 'sub': 'user-immutable'}
        self.reader = dict(self.user, sub='reader-immutable')
        self.other = dict(self.user, sub='other-company-user')
        self.cpc = dict(self.user, sub='cpc-service')
        command = [sys.executable, str(ROOT / 'devcontainer.test/fixtures/company-credential-adapter.py')]
        self.name = 'company:codex:team'
        self.config = {'database': str(self.root / 'server/state.sqlite3'),
            'issuer': self.user['iss'], 'audience': 'broker', 'jwksUrl': self.user['iss'] + '/certs',
            'profiles': {self.name: {'enabled': True, 'sharingApproved': True, 'tenant': 'company',
                'provider': 'codex', 'profile': 'team', 'mode': 'portable', 'accountId': 'expected-account',
                'vaultUrl': 'https://fixture.vault.azure.net', 'secretName': 'fixture',
                'validator': command, 'refresher': command}},
            'grants': [dict(self.user, issuer=self.user['iss'], subject=self.user['sub'], profiles={self.name: ['use', 'publish']}),
                {'issuer': self.reader['iss'], 'subject': self.reader['sub'], 'profiles': {self.name: ['use']}},
                {'issuer': self.cpc['iss'], 'subject': self.cpc['sub'], 'profiles': {self.name: ['maintain']}}]}
        self.vault = Vault(); self.broker = Broker(self.config, self.vault)
        self.value = {'accountId': 'expected-account', 'access_token': 'fixture-first'}

    def publish(self, value=None, expected=None, key='fixture-publish-0001'):
        return self.broker.publish(self.user, self.name, value or self.value, expected, key)['version']

    def client(self, label='client', publisher=True):
        root = self.root / label; path = root / 'native-auth.json'
        atomic(root / 'credential-sync.json', {'enabled': True, 'tenant': 'company', 'brokerUrl': 'https://broker.example',
            'entries': [{'profileId': self.name, 'credentialPath': str(path), 'publishChanges': publisher}]})
        return Sync(root, Transport(self.broker, self.user if publisher else self.reader)), path

    def test_publish_fetch_grants_and_tenant_isolation(self):
        version = self.publish()
        self.assertEqual(self.broker.fetch(self.reader, self.name)['credential'], self.value)
        self.assertEqual(self.broker.metadata(self.other), {'profiles': []})
        for identity, action in [(self.reader, 'publish'), (self.other, 'use')]:
            with self.assertRaises(BrokerError) as error: self.broker.authorize(identity, self.name, action)
            self.assertEqual(error.exception.status, 403)
        self.assertEqual(version, '1')

    def test_github_team_gate_reaches_metadata_fetch_publish_and_revocation(self):
        self.publish()
        self.config['profiles'][self.name]['githubTeam'] = {
            'organization': 'Opensoft-Testing', 'team': 'workbenches-qa-allowed'}
        self.config['githubIdentities'] = [
            {'issuer': self.user['iss'], 'subject': self.user['sub'], 'login': 'Opensoft-Test-User-1', 'githubId': 345520656},
            {'issuer': self.reader['iss'], 'subject': self.reader['sub'], 'login': 'Opensoft-Test-User-2', 'githubId': 345521882}]
        active = True
        def api(path, token):
            if path.startswith('/users/'):
                return {'id': 345520656 if path.endswith('User-1') else 345521882}
            return {'state': 'active'} if active and path.endswith('User-1') else {}
        with patch('github_team.token_file', return_value='fixture-read-only'), patch('github_team.get', side_effect=api):
            self.assertEqual(len(self.broker.metadata(self.user)['profiles']), 1)
            self.assertEqual(self.broker.metadata(self.reader), {'profiles': []})
            self.assertEqual(self.broker.fetch(self.user, self.name)['credential'], self.value)
            app = Application(self.broker, lambda _: self.reader)
            for route in ('fetch', 'publish'):
                data = {'profileId': self.name, 'credential': self.value, 'expectedVersion': '1', 'idempotencyKey': 'denied-at-http'}
                body = json.dumps(data).encode(); status = []
                raw = b''.join(app({'REQUEST_METHOD': 'POST', 'PATH_INFO': '/v1/' + route,
                    'CONTENT_LENGTH': str(len(body)), 'wsgi.input': io.BytesIO(body)}, lambda value, _: status.append(value)))
                self.assertTrue(status[0].startswith('403'))
                self.assertNotIn(b'fixture-first', raw)
            active = False
            self.assertEqual(self.broker.metadata(self.user), {'profiles': []})
            with self.assertRaises(BrokerError) as error: self.broker.fetch(self.user, self.name)
            self.assertEqual(error.exception.status, 403)
            # Maintenance remains governed by its separate service OIDC grant.
            self.broker.authorize(self.cpc, self.name, 'maintain')

    def test_github_binding_and_api_failures_never_release_credentials(self):
        self.publish()
        self.config['profiles'][self.name]['githubTeam'] = {'organization': 'qa', 'team': 'allowed'}
        self.assertEqual(self.broker.metadata(self.user), {'profiles': []})
        self.config['githubIdentities'] = [{'issuer': self.user['iss'], 'subject': self.user['sub'],
                                         'login': 'test-user', 'githubId': 123}]
        with patch('github_team.token_file', return_value='fixture'), patch('github_team.get', return_value={'id': 456}):
            with self.assertRaises(BrokerError) as error: self.broker.fetch(self.user, self.name)
            self.assertEqual(error.exception.status, 403)
        with patch('github_team.token_file', side_effect=BrokerError(503, 'github_membership_unavailable')):
            with self.assertRaises(BrokerError) as error: self.broker.fetch(self.user, self.name)
            self.assertEqual(error.exception.status, 503)
        self.config['githubIdentities'].append(dict(self.config['githubIdentities'][0]))
        self.assertEqual(self.broker.metadata(self.user), {'profiles': []})

    def test_unattended_live_probe_rejects_wrong_status_or_credential(self):
        spec = importlib.util.spec_from_file_location('live_team_probe', ROOT / 'qa/release/test-broker-team-live.py')
        probe = importlib.util.module_from_spec(spec); spec.loader.exec_module(probe)
        from company_sync import digest
        config = {'qaOnly': True, 'brokerUrl': 'https://qa.example', 'profileId': 'qa:test', 'tenant': 'qa',
                  'expectedAccountId': 'fixture', 'expectedCredentialDigest': digest({'accountId': 'fixture'}),
                  'users': [{'login': 'Opensoft-Test-User-1', 'sessionRoot': str(self.root / 'a')},
                            {'login': 'Opensoft-Test-User-2', 'sessionRoot': str(self.root / 'b')}]}
        def client(denial):
            class Client:
                def __init__(self, url, token): self.allowed = token() == 'a'
                def call(self, route, data=None):
                    if route == 'profiles': return {'profiles': [{'id': 'qa:test', 'tenant': 'qa', 'permissions': ['use']}] if self.allowed else []}
                    if not self.allowed: raise SyncError('denied', denial)
                    return {'credential': {'accountId': 'fixture'}}
            return Client
        with patch.object(probe, 'account_token', side_effect=lambda root: root.name):
            with patch.object(probe, 'Client', client(403)):
                probe.run(config)
                bad = dict(config, expectedCredentialDigest='wrong')
                with self.assertRaises(SyncError): probe.run(bad)
            with patch.object(probe, 'Client', client(401)):
                with self.assertRaises(SyncError): probe.run(config)

    def test_github_membership_token_file_is_private_and_not_symlinked(self):
        from github_team import token_file
        path = self.root / 'membership-token'; path.write_text('fixture-token'); path.chmod(0o600)
        self.assertEqual(token_file(str(path)), 'fixture-token')
        path.chmod(0o644)
        with self.assertRaises(BrokerError): token_file(str(path))
        path.chmod(0o600)
        link = self.root / 'token-link'; link.symlink_to(path)
        with self.assertRaises(BrokerError): token_file(str(link))

    def qa_provisioner(self):
        spec = importlib.util.spec_from_file_location('qa_provisioner', ROOT / 'qa/release/provision-github-qa-sessions.py')
        value = importlib.util.module_from_spec(spec); spec.loader.exec_module(value)
        return value

    def test_qa_oauth_verifies_identity_and_scope_before_storing(self):
        provision = self.qa_provisioner()
        device = {'expires_in': 900, 'interval': 5, 'device_code': 'fixture-device-code'}
        token = {'access_token': 'fixture-oauth-secret', 'scope': 'read:org', 'expires_in': 100,
                 'refresh_token': 'fixture-refresh-secret'}
        user = {'login': 'Opensoft-Test-User-1', 'id': 345520656}
        with patch.object(provision.time, 'sleep'), patch.object(provision, 'request', side_effect=[token, user]), \
             patch.object(provision, 'store', return_value='qa-secret') as store, patch('builtins.print') as output:
            provision.finish(user['login'], user['id'], device)
            self.assertEqual(store.call_args.args[1]['githubId'], user['id'])
            text = str(output.call_args_list)
            for secret in ('fixture-oauth-secret', 'fixture-refresh-secret', 'fixture-device-code'):
                self.assertNotIn(secret, text)
        for identity, scopes in [(dict(user, id=123), 'read:org'), (user, 'read:org,repo')]:
            with patch.object(provision.time, 'sleep'), patch.object(provision, 'request', side_effect=[dict(token, scope=scopes), identity]), \
                 patch.object(provision, 'store') as store:
                with self.assertRaises(provision.ProvisionError): provision.finish(user['login'], user['id'], device)
                store.assert_not_called()

    def test_qa_oauth_upload_never_puts_token_in_command_or_leaves_local_file(self):
        provision = self.qa_provisioner(); paths = []
        def upload(argv, **kwargs):
            path = Path(argv[argv.index('--file') + 1]); paths.append(path)
            self.assertEqual(path.stat().st_mode & 0o077, 0)
            self.assertIn('fixture-oauth-secret', path.read_text())
            self.assertNotIn('fixture-oauth-secret', str(argv))
            self.assertNotIn('env', kwargs)
            return subprocess.CompletedProcess(argv, 0, b'https://qa/secret/version', b'')
        with patch.object(provision.subprocess, 'run', side_effect=upload):
            provision.store('Opensoft-Test-User-1', {'oauth': {'access_token': 'fixture-oauth-secret'}})
        self.assertTrue(paths)
        self.assertTrue(all(not path.exists() for path in paths))

    def qa_vault_sessions(self):
        spec = importlib.util.spec_from_file_location('qa_vault_sessions', ROOT / 'qa/release/github-vault-sessions.py')
        value = importlib.util.module_from_spec(spec); spec.loader.exec_module(value)
        return value

    def test_qa_renewal_persists_intent_and_verified_rotated_session(self):
        sessions = self.qa_vault_sessions(); login, user_id = sessions.PROVISION.USERS[0]
        bundle = {'provider': 'github', 'clientId': sessions.PROVISION.CLIENT_ID, 'login': login,
                  'githubId': user_id, 'oauth': {'scope': 'read:org', 'refresh_token': 'fixture-old'}}
        tokens = {'scope': 'read:org', 'access_token': 'fixture-new', 'refresh_token': 'fixture-rotated',
                  'expires_in': 28800, 'refresh_token_expires_in': 100000}
        with patch.object(sessions.PROVISION, 'store') as store, patch.object(sessions.PROVISION, 'request',
                side_effect=[tokens, {'id': user_id, 'login': login}]):
            result, rotated = sessions.renew(bundle, login, user_id, force=True)
        self.assertTrue(rotated)
        self.assertEqual(store.call_count, 2)
        intent = store.call_args_list[0].args[1]
        self.assertEqual(intent['state'], 'renewal-in-progress')
        self.assertNotIn('refresh_token', intent['oauth'])
        self.assertEqual(result['oauth']['refresh_token'], 'fixture-rotated')
        self.assertEqual(bundle['oauth']['refresh_token'], 'fixture-old')
        with self.assertRaises(sessions.SessionError): sessions.validate(intent, login, user_id)

    def test_qa_renewal_failure_leaves_no_replayable_latest_refresh_token(self):
        sessions = self.qa_vault_sessions(); login, user_id = sessions.PROVISION.USERS[0]
        bundle = {'provider': 'github', 'clientId': sessions.PROVISION.CLIENT_ID, 'login': login,
                  'githubId': user_id, 'oauth': {'scope': 'read:org', 'refresh_token': 'fixture-old'}}
        with patch.object(sessions.PROVISION, 'store') as store, patch.object(sessions.PROVISION, 'request', return_value={'error': 'bad_refresh_token'}):
            with self.assertRaises(sessions.SessionError): sessions.renew(bundle, login, user_id, True)
        self.assertEqual(store.call_count, 1)
        self.assertNotIn('refresh_token', store.call_args.args[1]['oauth'])

    def test_broker_workload_identity_is_explicit_and_never_falls_back(self):
        from core import AzureVault
        with patch('azure.identity.ManagedIdentityCredential') as managed, patch('azure.identity.WorkloadIdentityCredential') as workload:
            AzureVault('fixture-client', 'workload')
            workload.assert_called_once_with(client_id='fixture-client')
            managed.assert_not_called()
        with patch('azure.identity.ManagedIdentityCredential') as managed, patch('azure.identity.WorkloadIdentityCredential', side_effect=RuntimeError('fixture identity unavailable')):
            with self.assertRaises(RuntimeError): AzureVault('fixture-client', 'workload')
            managed.assert_not_called()
        with self.assertRaises(ValueError): AzureVault(identity_mode='azure-cli')

    def test_changing_vault_identity_requires_broker_restart(self):
        config_path = self.root / 'server-identity.json'
        changed = dict(self.config, identityMode='workload'); atomic(config_path, changed)
        app = Application(self.broker, lambda _: self.user, config_path)
        status = []
        raw = b''.join(app({'REQUEST_METHOD': 'GET', 'PATH_INFO': '/v1/profiles'}, lambda value, _: status.append(value)))
        self.assertTrue(status[0].startswith('503'))
        self.assertEqual(json.loads(raw)['error'], 'deployment_configuration_changed')

    def test_host_and_image_hook_sources_match(self):
        self.assertEqual((ROOT / 'scripts/lib/company-profile-sync.sh').read_bytes(), (ROOT / 'base-image/files/company-profile-sync.sh').read_bytes())
        self.assertEqual((ROOT / 'scripts/opencode-profile').read_bytes(), (ROOT / 'base-image/files/opencode-profile').read_bytes())

    def test_wrong_account_refresh_tokens_and_disabled_profiles_fail_closed(self):
        for value in [dict(self.value, accountId='wrong'), dict(self.value, refresh_token='fixture-refresh')]:
            with self.assertRaises(BrokerError): self.publish(value)
        self.config['profiles'][self.name]['enabled'] = False
        self.assertEqual(self.broker.metadata(self.user)['profiles'], [])
        self.assertEqual(self.vault.counter, 0)
        invalid = copy.deepcopy(self.config)
        invalid['profiles'][self.name]['enabled'] = 'false'
        with self.assertRaises(ValueError): Broker(invalid, self.vault)
        invalid['profiles'][self.name].update(enabled=True, sharingApproved='false')
        with self.assertRaises(ValueError): Broker(invalid, self.vault)
        client, _ = self.client()
        bad_client = copy.deepcopy(client.config)
        bad_client['entries'][0]['publishChanges'] = 'false'
        atomic(client.root / 'credential-sync.json', bad_client)
        with self.assertRaises(SyncError): Sync(client.root, client.client)

    def test_compare_and_set_and_idempotent_retry(self):
        version = self.publish()
        self.assertEqual(self.publish(), version)
        with self.assertRaises(BrokerError): self.publish(dict(self.value, access_token='fixture-different'))
        with self.assertRaises(BrokerError): self.publish(expected=None, key='fixture-other-0001')
        self.assertEqual(self.vault.counter, 1)

    def test_ambiguous_vault_write_is_recovered_without_another_version(self):
        self.vault.fail_after = True
        with self.assertRaises(BrokerError): self.publish()
        self.assertEqual(self.broker.metadata(self.user)['profiles'][0]['state'], 'publishing')
        self.assertEqual(self.publish(), '1')
        self.assertEqual(self.vault.counter, 1)

    def test_concurrent_publishers_one_wins(self):
        outcomes = []; barrier = threading.Barrier(2)
        def publish(key):
            barrier.wait()
            try: outcomes.append(self.publish(key=key))
            except BrokerError as error: outcomes.append(error.status)
        threads = [threading.Thread(target=publish, args=(f'fixture-thread-{i}',)) for i in range(2)]
        for thread in threads: thread.start()
        for thread in threads: thread.join()
        self.assertCountEqual(outcomes, ['1', 409])
        self.assertEqual(self.vault.counter, 1)

    def test_same_operation_concurrently_creates_only_one_vault_version(self):
        outcomes = []
        def publish(): outcomes.append(self.publish())
        threads = [threading.Thread(target=publish) for _ in range(2)]
        for thread in threads: thread.start()
        for thread in threads: thread.join()
        self.assertEqual(outcomes, ['1', '1']); self.assertEqual(self.vault.counter, 1)

    def test_two_clients_download_local_login_upload_and_refresh(self):
        self.publish()
        first, path1 = self.client('first'); second, path2 = self.client('second', publisher=False)
        first.run(True); second.run(True)
        updated = dict(self.value, access_token='fixture-new-login')
        atomic(path1, updated)
        first.run(True, only=path1, before_login=True)
        first.run(True, only=path1, after_login=True)
        second.run(True)
        self.assertEqual(read_json(path2), updated)
        self.assertEqual(path2.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.vault.counter, 2)

    def test_dirty_local_conflicts_are_preserved(self):
        version = self.publish(); client, path = self.client(); client.run(True)
        local = dict(self.value, access_token='fixture-local'); atomic(path, local)
        self.publish(dict(self.value, access_token='fixture-remote'), version, 'fixture-other-version')
        state = client.run(True, adopt=True)
        self.assertEqual(state['entries'][self.name]['state'], 'version_conflict')
        self.assertEqual(read_json(path), local)

    def test_logout_partial_writes_and_unknown_existing_file_not_uploaded(self):
        self.publish(); client, path = self.client()
        atomic(path, self.value)
        state = client.run(True)
        self.assertEqual(state['entries'][self.name]['state'], 'existing_local_credential_needs_approval')
        path.unlink(); client.run(True); path.unlink()
        self.assertEqual(client.run(True)['entries'][self.name]['state'], 'local_credential_removed')
        path.write_text('{'); path.chmod(0o600)
        self.assertEqual(client.run(True)['entries'][self.name]['state'], 'invalid_local_json')
        self.assertEqual(self.vault.counter, 1)

    def test_download_does_not_echo_upload_and_active_writer_is_not_replaced(self):
        from company_sync import lock
        from credential_sync_client import lease_path
        self.publish(); client, path = self.client(); client.run(True); client.run(True)
        self.assertEqual(self.vault.counter, 1)
        with lock(lease_path(path)):
            result = client.run(True)
        self.assertEqual(result['entries'][self.name]['state'], 'another_sync_is_running')

    def refresh_login(self):
        self.config['profiles'][self.name]['mode'] = 'broker-refresh'
        self.publish(dict(self.value, refresh_token='fixture-old-refresh', expiresAt=time.time() + 6000))
        client, path = self.client()
        client.run(True)
        baseline = read_json(client.state_path)['entries'][self.name].copy()
        client.run(True, before_login=True)
        logged_in = dict(self.value, access_token='fixture-new-login', refresh_token='fixture-new-refresh', expiresAt=time.time() + 6000)
        atomic(path, logged_in)
        return client, path, logged_in, baseline

    def test_broker_refresh_retries_cleanup_after_fetch_failure_and_restart(self):
        client, path, logged_in, baseline = self.refresh_login()
        original = client.client.call
        def offline_fetch(route, data=None):
            if route == 'fetch': raise SyncError('service_unavailable')
            return original(route, data)
        client.client.call = offline_fetch
        failed = client.run(True, after_login=True)['entries'][self.name]
        self.assertEqual(failed['state'], 'service_unavailable')
        self.assertEqual(failed['hash'], baseline['hash'])
        self.assertIn('pending', failed)
        self.assertEqual(read_json(path), logged_in)
        self.assertEqual(self.vault.counter, 2)
        self.assertNotIn('fixture-new-refresh', client.state_path.read_text())
        restarted = Sync(client.root, Transport(self.broker, self.user))
        recovered = restarted.run()['entries'][self.name]
        self.assertEqual(recovered['state'], 'published')
        self.assertNotIn('pending', recovered)
        self.assertNotIn('refresh_token', read_json(path))
        self.assertEqual(read_json(path)['access_token'], 'fixture-new-login')
        self.assertEqual(self.vault.counter, 2)

    def test_broker_refresh_recovers_after_projection_write_before_baseline_save(self):
        client, path, logged_in, baseline = self.refresh_login()
        def interrupted_write(destination, value):
            atomic(destination, value)
            if destination == path: raise OSError('fixture interrupted after public projection install')
        with patch('credential_sync_client.atomic', side_effect=interrupted_write):
            client.run(True, after_login=True)
        self.assertNotIn('refresh_token', read_json(path))
        self.assertIn('pending', read_json(client.state_path)['entries'][self.name])
        restarted = Sync(client.root, Transport(self.broker, self.user))
        with patch.object(restarted.client, 'call', wraps=restarted.client.call) as calls:
            recovered = restarted.run()['entries'][self.name]
        self.assertNotIn('pending', recovered)
        self.assertEqual(recovered['state'], 'published')
        self.assertFalse(any(call.args[0] == 'publish' for call in calls.call_args_list))
        self.assertEqual(self.vault.counter, 2)
        # A later explicitly approved login must not inherit a stale operation.
        restarted.run(True, before_login=True)
        atomic(path, dict(logged_in, access_token='fixture-next-approved-login'))
        self.assertEqual(restarted.run(True, after_login=True)['entries'][self.name]['state'], 'published')
        self.assertEqual(self.vault.counter, 3)
        self.assertNotIn('refresh_token', read_json(path))

    def test_broker_refresh_cleanup_preserves_a_concurrent_local_login(self):
        client, path, logged_in, baseline = self.refresh_login()
        original = client.client.call
        changed = dict(logged_in, access_token='fixture-concurrent-login')
        def changed_during_fetch(route, data=None):
            result = original(route, data)
            if route == 'fetch': atomic(path, changed)
            return result
        client.client.call = changed_during_fetch
        failed = client.run(True, after_login=True)['entries'][self.name]
        self.assertEqual(failed['state'], 'local_writer_conflict')
        self.assertEqual(failed['hash'], baseline['hash'])
        self.assertIn('pending', failed)
        self.assertEqual(read_json(path), changed)
        restarted = Sync(client.root, Transport(self.broker, self.user))
        failed = restarted.run()['entries'][self.name]
        self.assertEqual(failed['state'], 'unresolved_publication_local_changed')
        self.assertEqual(read_json(path), changed)
        self.assertEqual(self.vault.counter, 2)

    def test_cpc_expiry_driven_refresh_never_releases_refresh_token(self):
        self.config['profiles'][self.name]['mode'] = 'broker-refresh'
        initial = dict(self.value, refresh_token='fixture-old', expiresAt=time.time() + 60)
        self.publish(initial)
        fetched = self.broker.fetch(self.reader, self.name)['credential']
        self.assertNotIn('refresh_token', fetched)
        result = tick(Transport(self.broker, self.cpc))
        self.assertEqual(result[0]['state'], 'ready')
        row = self.broker.metadata(self.cpc)['profiles'][0]
        self.assertGreater(row['expiresAt'], time.time() + 3600)
        self.assertEqual(self.vault.values[row['version']]['refresh_token'], 'fixture-rotated')
        tick(Transport(self.broker, self.cpc)); self.assertEqual(self.vault.counter, 2)

    def test_cpc_failure_requires_login_and_does_not_repeat_refresh(self):
        self.config['profiles'][self.name]['mode'] = 'broker-refresh'
        self.publish(dict(self.value, refresh_token='fixture-denied', expiresAt=time.time() + 60))
        result = tick(Transport(self.broker, self.cpc)); self.assertEqual(result[0]['state'], 'login_required')
        tick(Transport(self.broker, self.cpc)); self.assertEqual(self.vault.counter, 1)

    def test_crash_during_refresh_stays_blocked_until_reconciliation(self):
        self.publish()
        with self.broker.db() as db:
            db.execute("UPDATE profiles SET state='refreshing',operation='fixture-crash' WHERE id=?", (self.name,))
        self.assertEqual(self.broker.maintain(self.cpc, self.name)['state'], 'refreshing')
        with self.assertRaises(BrokerError): self.broker.fetch(self.reader, self.name)

    def test_http_errors_never_echo_secret_values_and_revocation_reloads(self):
        config_path = self.root / 'server.json'; atomic(config_path, self.config)
        app = Application(self.broker, lambda token: self.user, config_path)
        def call(path, data):
            body = json.dumps(data).encode(); status = []
            output = b''.join(app({'REQUEST_METHOD': 'POST', 'PATH_INFO': path,
                'CONTENT_LENGTH': str(len(body)), 'wsgi.input': io.BytesIO(body)}, lambda s, h: status.append(s)))
            return status[0], output
        status, raw = call('/v1/publish', {'profileId': self.name, 'credential': dict(self.value, accountId='wrong'),
            'expectedVersion': None, 'idempotencyKey': 'fixture-http-0001'})
        self.assertTrue(status.startswith('422')); self.assertNotIn(b'fixture-first', raw)
        self.publish(); self.config['grants'] = []; atomic(config_path, self.config)
        self.assertTrue(call('/v1/fetch', {'profileId': self.name})[0].startswith('403'))

    def test_no_credential_bodies_in_sqlite_or_audit(self):
        self.publish(); self.broker.fetch(self.reader, self.name)
        self.assertNotIn(b'fixture-first', self.broker.path.read_bytes())
        with self.broker.db() as db:
            self.assertEqual(db.execute('SELECT COUNT(*) FROM audit').fetchone()[0], 2)

    def test_oidc_rejects_wrong_audience_issuer_expiry_and_unsigned_tokens(self):
        try:
            import jwt
            from cryptography.hazmat.primitives.asymmetric import rsa
        except ImportError:
            self.skipTest('Run the declared credential-sync service for PyJWT/crypto checks')
        private = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        auth = OIDC(self.config)
        key = type('Key', (), {'key': private.public_key()})()
        claims = dict(self.user, aud='broker', iat=int(time.time()), exp=int(time.time()) + 60)
        with patch.object(auth.jwks, 'get_signing_key_from_jwt', return_value=key):
            good = jwt.encode(claims, private, algorithm='RS256')
            self.assertEqual(auth('Bearer ' + good)['sub'], self.user['sub'])
            for changes in [{'aud': 'other'}, {'iss': 'https://evil.example'}, {'exp': 1}]:
                bad = jwt.encode(claims | changes, private, algorithm='RS256')
                with self.assertRaises(BrokerError): auth('Bearer ' + bad)
            unsigned = jwt.encode(claims, key='', algorithm='none')
            with self.assertRaises(BrokerError): auth('Bearer ' + unsigned)

    def test_client_recovers_lost_publication_response_with_same_key(self):
        self.publish(); client, path = self.client(); client.run(True)
        atomic(path, dict(self.value, access_token='fixture-login'))
        client.run(True, before_login=True)
        original = client.client.call; lost = [False]
        def call(route, data=None):
            value = original(route, data)
            if route == 'publish' and not lost[0]:
                lost[0] = True
                raise SyncError('service_unavailable')
            return value
        client.client.call = call
        first = client.run(True, after_login=True)
        self.assertIn('pending', first['entries'][self.name])
        second = client.run(True, after_login=True)
        self.assertEqual(second['entries'][self.name]['state'], 'published')
        self.assertEqual(self.vault.counter, 2)

    def test_cpc_weekly_health_sweep_and_redacted_deduplicated_alerts(self):
        self.publish()
        with self.broker.db() as db:
            db.execute('UPDATE profiles SET checked=? WHERE id=?', (time.time() - 604801, self.name))
        self.assertTrue(self.broker.maintain(self.cpc, self.name)['checked'])
        self.assertFalse(self.broker.maintain(self.cpc, self.name)['checked'])
        seen = {}; rows = [{'profileId': self.name, 'state': 'login_required'}]
        with patch('cpc.request', return_value={}) as send:
            notify({'alertsWebhookUrl': 'https://alerts.example/credential-health'}, rows, seen)
            notify({'alertsWebhookUrl': 'https://alerts.example/credential-health'}, rows, seen)
        self.assertEqual(send.call_count, 1)
        self.assertNotIn('fixture-first', json.dumps(send.call_args.args))

    def test_company_background_session_rotation_and_ambiguous_failure(self):
        from company_sync import account_token
        root = self.root / 'company-session'
        config = {'issuer': 'https://identity.example/realm', 'clientId': 'workbenches'}
        atomic(root / 'account-provider.json', config)
        original = config | {'accessToken': 'fixture-expired', 'refreshToken': 'fixture-company-refresh', 'expiresAt': 1}
        atomic(root / 'account-session.json', original)
        metadata = {'issuer': config['issuer'], 'token_endpoint': config['issuer'] + '/token'}
        with patch('company_sync.request', side_effect=[metadata, {'access_token': 'fixture-company-new', 'refresh_token': 'fixture-company-rotated', 'expires_in': 300}]):
            self.assertEqual(account_token(root), 'fixture-company-new')
        self.assertEqual(read_json(root / 'account-session.json')['refreshToken'], 'fixture-company-rotated')
        atomic(root / 'account-session.json', original)
        with patch('company_sync.request', side_effect=[metadata, SyncError('service_unavailable')]):
            with self.assertRaises(SyncError): account_token(root)
        self.assertNotIn('refreshToken', read_json(root / 'account-session.json'))

    def test_real_https_transport_and_signed_identity_end_to_end(self):
        try:
            import jwt
            from cryptography import x509
            from cryptography.hazmat.primitives import hashes, serialization
            from cryptography.hazmat.primitives.asymmetric import rsa
            from cryptography.x509.oid import NameOID
        except ImportError:
            self.skipTest('Run the declared credential-sync service for TLS/crypto checks')
        from datetime import datetime, timedelta, timezone
        import ssl
        from wsgiref.simple_server import make_server, WSGIRequestHandler
        from company_sync import Client
        private = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'localhost')])
        certificate = (x509.CertificateBuilder().subject_name(subject).issuer_name(subject).public_key(private.public_key())
            .serial_number(x509.random_serial_number()).not_valid_before(datetime.now(timezone.utc) - timedelta(minutes=1))
            .not_valid_after(datetime.now(timezone.utc) + timedelta(hours=1))
            .add_extension(x509.SubjectAlternativeName([x509.DNSName('localhost')]), critical=False).sign(private, hashes.SHA256()))
        cert, key = self.root / 'cert.pem', self.root / 'key.pem'
        cert.write_bytes(certificate.public_bytes(serialization.Encoding.PEM))
        key.write_bytes(private.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
        auth = OIDC(self.config)
        claims = dict(self.user, aud='broker', iat=int(time.time()), exp=int(time.time()) + 60)
        token = jwt.encode(claims, private, algorithm='RS256')
        class Quiet(WSGIRequestHandler):
            def log_message(self, *args): pass
        server = make_server('127.0.0.1', 0, Application(self.broker, auth), handler_class=Quiet)
        tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        tls.minimum_version = ssl.TLSVersion.TLSv1_2
        tls.load_cert_chain(cert, key)
        server.socket = tls.wrap_socket(server.socket, server_side=True)
        thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
        public = type('Key', (), {'key': private.public_key()})()
        trusted = ssl.create_default_context(cafile=str(cert))
        try:
            with patch.object(auth.jwks, 'get_signing_key_from_jwt', return_value=public), patch('ssl._create_default_https_context', return_value=trusted):
                client = Client(f'https://localhost:{server.server_port}', lambda: token)
                self.assertEqual(client.call('profiles')['profiles'][0]['id'], self.name)
                client.call('publish', {'profileId': self.name, 'credential': self.value, 'expectedVersion': None, 'idempotencyKey': 'fixture-tls-publish'})
                self.assertEqual(client.call('fetch', {'profileId': self.name})['credential'], self.value)
                client.token = lambda: jwt.encode(claims | {'aud': 'wrong'}, private, algorithm='RS256')
                with self.assertRaises(SyncError) as error: client.call('profiles')
                self.assertEqual(error.exception.status, 401)
        finally:
            server.shutdown(); thread.join(); server.server_close()

    def test_explicit_remote_acceptance_restores_logout_without_silent_sign_in(self):
        self.publish(); client, path = self.client(); client.run(True); path.unlink()
        self.assertEqual(client.run(True)['entries'][self.name]['state'], 'local_credential_removed')
        self.assertFalse(path.exists())
        client.run(True, only=path, accept_remote=True)
        self.assertEqual(read_json(path), self.value)

    def test_cross_company_mapping_and_personal_stores_are_refused(self):
        from credential_sync_client import managed_path
        self.publish(); client, path = self.client(); client.config['tenant'] = 'other-company'
        self.assertEqual(client.run(True)['entries'][self.name]['state'], 'profile_belongs_to_another_company')
        self.assertFalse(path.exists())
        for name in ['.codex/auth.json', '.claude/.credentials.json', '.chatgpt-profiles/profiles/personal/account/auth.json']:
            with self.assertRaises(SyncError): managed_path(Path.home() / name)

    def test_readable_credential_and_symlink_storage_are_refused(self):
        self.publish(); client, path = self.client(); atomic(path, self.value); path.chmod(0o644)
        self.assertEqual(client.run(True)['entries'][self.name]['state'], 'credential_file_must_be_private')
        path.unlink(); target = client.root / 'target.json'; atomic(target, self.value); path.symlink_to(target)
        with self.assertRaises(SyncError): Sync(client.root, Transport(self.broker, self.user))
        self.assertEqual(read_json(target), self.value)

    def test_stalled_refresh_requires_explicit_maintainer_recovery(self):
        version = self.publish()
        with self.broker.db() as db:
            db.execute("UPDATE profiles SET state='refreshing',operation='fixture-stalled',checked=? WHERE id=?", (time.time(), self.name))
        with self.assertRaises(BrokerError): self.broker.require_login(self.cpc, self.name, version)
        with self.broker.db() as db:
            db.execute('UPDATE profiles SET checked=? WHERE id=?', (time.time() - 121, self.name))
        self.assertEqual(self.broker.require_login(self.cpc, self.name, version)['state'], 'login_required')
        self.publish(dict(self.value, access_token='fixture-new-login'), version, 'fixture-new-login-recovery')
        self.assertEqual(self.broker.fetch(self.reader, self.name)['credential']['access_token'], 'fixture-new-login')

    def test_generic_oauth_adapter_validates_audience_and_never_returns_refresh_secret(self):
        spec = importlib.util.spec_from_file_location('test_oauth_adapter', ROOT / 'credential-broker/oauth_adapter.py')
        adapter = importlib.util.module_from_spec(spec); spec.loader.exec_module(adapter)
        secret = self.root / 'client-secret'; secret.write_text('fixture-server-secret')
        config = {'clientId': 'fixture', 'clientSecretFile': str(secret), 'introspectionEndpoint': 'https://provider.example/introspect',
            'tokenEndpoint': 'https://provider.example/token', 'expectedAudience': 'provider-api', 'requiredScopes': ['use'],
            'accessTokenPath': ['tokens', 'access_token'], 'refreshTokenPath': ['tokens', 'rt']}
        credential = {'tokens': {'access_token': 'fixture-access', 'rt': 'fixture-private-refresh'}}
        with patch.object(adapter, 'request', return_value={'active': True, 'sub': 'provider-account', 'aud': 'provider-api', 'scope': 'use', 'exp': time.time() + 300}):
            result = adapter.execute(config, {'action': 'validate', 'credential': credential})
        self.assertTrue(result['valid']); self.assertNotIn('rt', result['publicCredential']['tokens'])
        with patch.object(adapter, 'request', return_value={'active': True, 'aud': 'wrong', 'scope': 'use'}):
            self.assertFalse(adapter.execute(config, {'action': 'validate', 'credential': credential})['valid'])
        with patch.object(adapter, 'request', return_value={'access_token': 'fixture-new-access', 'expires_in': 300}) as refresh:
            with self.assertRaises(ValueError): adapter.execute(config, {'action': 'refresh', 'credential': credential})
            self.assertEqual(refresh.call_count, 1)

    def test_azure_adapter_uses_managed_identity_and_operation_tags(self):
        try:
            from azure.core.exceptions import ResourceNotFoundError
            from core import AzureVault
        except ImportError:
            self.skipTest('Run the declared credential-sync service for Azure SDK checks')
        from unittest.mock import MagicMock
        sdk = MagicMock(); sdk.list_properties_of_secret_versions.side_effect = ResourceNotFoundError('fixture missing')
        sdk.set_secret.return_value.properties.version = 'fixture-kv-version'
        with patch('azure.identity.ManagedIdentityCredential') as identity, patch('azure.keyvault.secrets.SecretClient', return_value=sdk):
            vault = AzureVault('fixture-managed-identity')
            identity.assert_called_once_with(client_id='fixture-managed-identity')
            profile = self.config['profiles'][self.name]
            self.assertEqual(vault.put(profile, self.value, 'fixture-op'), 'fixture-kv-version')
            self.assertEqual(sdk.set_secret.call_args.kwargs['tags'], {'workbenches-operation': 'fixture-op'})
            sdk.get_secret.return_value.value = json.dumps(self.value)
            self.assertEqual(vault.get(profile, 'fixture-kv-version'), self.value)
            sdk.get_secret.assert_called_with('fixture', 'fixture-kv-version')

    def test_launcher_hook_holds_lease_and_releases_before_publishing_login(self):
        from company_sync import lock
        binary = self.root / 'bin'; binary.mkdir()
        config = self.root / '.config/workbenches'; config.mkdir(parents=True)
        (config / 'company-sync-enabled').touch()
        helper = binary / 'workbenches-credential-sync'
        helper.write_text('''#!/bin/bash
printf '%s\n' "$1" >> "$FIXTURE_ACTION_LOG"
case "$1" in
--is-managed) exit 0 ;;
--lease-path) echo "$FIXTURE_LEASE" ;;
--after-login) flock -n "$FIXTURE_LEASE" true ;;
esac
'''); helper.chmod(0o755)
        lease = self.root / 'native.lock'; actions = self.root / 'actions'
        env = dict(os.environ, HOME=str(self.root), XDG_CONFIG_HOME=str(self.root / '.config'),
            PATH=str(binary) + ':' + os.environ['PATH'], FIXTURE_ACTION_LOG=str(actions), FIXTURE_LEASE=str(lease))
        ready = self.root / 'ready'
        script = 'source "$1"; wb_sync_before "$2" run || exit; touch "$3"; sleep 1'
        process = subprocess.Popen(['bash', '-c', script, 'fixture', str(ROOT / 'scripts/lib/company-profile-sync.sh'), str(self.root / 'native.json'), str(ready)], env=env)
        try:
            deadline = time.monotonic() + 5
            while not ready.exists() and process.poll() is None and time.monotonic() < deadline: time.sleep(.01)
            self.assertTrue(ready.exists())
            with self.assertRaises(SyncError):
                with lock(lease, nonblocking=True): pass
            self.assertEqual(process.wait(timeout=5), 0)
        finally:
            if process.poll() is None: process.kill(); process.wait()
        script = 'source "$1"; wb_sync_before "$2" login && wb_sync_after_login "$2"'
        result = subprocess.run(['bash', '-c', script, 'fixture', str(ROOT / 'scripts/lib/company-profile-sync.sh'), str(self.root / 'native.json')], env=env, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertLess(actions.read_text().index('--before-login'), actions.read_text().index('--after-login'))

    def test_background_agent_stops_cleanly_and_records_missing_login(self):
        config_root = self.root / 'workbenches'
        company_id = 'company-' + 'a' * 32
        atomic(config_root / 'profiles.json', {'version': 1, 'personal': {'id': 'personal', 'name': 'Personal', 'email': 'me@example.org'},
            'companies': [{'id': company_id, 'name': 'Company', 'email': 'me@company.org'}]})
        company = config_root / 'identities' / company_id
        atomic(company / 'credential-sync.json', {'enabled': True, 'tenant': 'company', 'brokerUrl': 'https://broker.example', 'entries': []})
        env = dict(os.environ, XDG_CONFIG_HOME=str(self.root))
        command = [sys.executable, str(ROOT / 'scripts/credential-sync.py')]
        process = subprocess.Popen(command + ['--watch'], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            deadline = time.monotonic() + 5
            while not (company / 'credential-sync-state.json').exists() and process.poll() is None and time.monotonic() < deadline: time.sleep(.02)
            self.assertEqual(read_json(company / 'credential-sync-state.json')['error'], 'company_login_or_configuration_required')
            subprocess.run(command + ['--stop'], env=env, check=True, capture_output=True, timeout=5)
            output, errors = process.communicate(timeout=5)
            self.assertEqual(process.returncode, 0, errors)
            self.assertFalse(read_json(config_root / 'credential-sync-agent.json')['running'])
            self.assertNotIn('fixture-first', output)
        finally:
            if process.poll() is None: process.kill(); process.communicate()

    def test_baked_production_factory_starts_without_user_azure_credentials(self):
        if not Path('/app/app.py').exists():
            self.skipTest('Run the declared credential-sync service for the production image smoke test')
        config = copy.deepcopy(self.config)
        config['profiles'][self.name]['enabled'] = False
        path = self.root / 'production-factory.json'; atomic(path, config)
        code = '''import app, io
application = app.create_app()
status = []
body = b''.join(application({'REQUEST_METHOD': 'GET', 'PATH_INFO': '/v1/profiles', 'wsgi.input': io.BytesIO()}, lambda value, headers: status.append(value)))
assert status[0].startswith('401'), status
assert b'authentication_required' in body
assert type(application.broker.vault).__name__ == 'AzureVault'
'''
        env = dict(os.environ, WORKBENCHES_BROKER_CONFIG=str(path))
        result = subprocess.run([sys.executable, '-c', code], cwd='/app', env=env, capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == '__main__':
    unittest.main()
