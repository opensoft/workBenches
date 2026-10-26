#!/usr/bin/env python3
"""Optional organization login, private session storage, no real accounts."""
import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
spec = importlib.util.spec_from_file_location('account', ROOT / 'scripts/setup-workbenches-account.py')
account = importlib.util.module_from_spec(spec)
spec.loader.exec_module(account)


class AccountTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(); self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        for name, value in (('CONFIG', self.root / 'account-provider.json'), ('SESSION', self.root / 'account-session.json')):
            p = patch.object(account, name, value); p.start(); self.addCleanup(p.stop)
        p = patch.dict(os.environ, {}, clear=True); p.start(); self.addCleanup(p.stop)
        browser = patch.object(account.webbrowser, 'open', return_value=False)
        self.browser = browser.start(); self.addCleanup(browser.stop)
        self.config = {'issuer': 'https://identity.example/realms/workbenches', 'clientId': 'openworkbenches-cli'}
        self.metadata = {'issuer': self.config['issuer'], **{key: self.config['issuer'] + '/' + key for key in ('device_authorization_endpoint', 'token_endpoint', 'userinfo_endpoint')}}
        self.device = {'verification_uri': 'https://identity.example/device', 'user_code': 'TEST-CODE', 'device_code': 'invalid-fixture-device', 'expires_in': 60, 'interval': 1}
        self.tokens = {'access_token': 'invalid-fixture-token', 'expires_in': 30}

    def test_unconfigured_account_is_optional_and_contacts_no_server(self):
        with patch.object(account, 'request', side_effect=AssertionError('unexpected network')):
            self.assertEqual(account.status(), 'not configured')
            with patch('builtins.input', return_value=''):
                self.assertEqual(account.main(), 0)
        self.assertFalse(account.SESSION.exists())

    def test_login_polls_pending_and_slow_down_and_checks_identity(self):
        with patch.object(account, 'request', side_effect=[self.metadata, self.device, {'error': 'authorization_pending'}, {'error': 'slow_down'}, self.tokens, {'sub': 'fixture-user'}]) as request, patch.object(account.time, 'sleep') as sleep:
            self.assertEqual(account.login(self.config), 0)
        self.assertEqual([call.args[0] for call in sleep.call_args_list], [1, 1, 6])
        self.assertEqual(request.call_args.kwargs, {'bearer': 'invalid-fixture-token'})
        session = json.loads(account.SESSION.read_text())
        self.assertEqual(session['subject'], 'fixture-user')
        self.assertEqual(account.SESSION.stat().st_mode & 0o777, 0o600)
        account.write_private(account.CONFIG, self.config)
        self.assertEqual(account.status(), 'signed in')

    def test_only_verified_valid_email_is_retained(self):
        for claims, expected in (
            ({'email': 'work@example.org', 'email_verified': True}, 'work@example.org'),
            ({'email': 'work@example.org', 'email_verified': False}, None),
            ({'email': 'work@example.org', 'email_verified': 'true'}, None),
            ({'email': 'bad\n@example.org', 'email_verified': True}, None),
            ({}, None),
        ):
            with self.subTest(claims=claims), patch.object(account, 'request', side_effect=[
                    self.metadata, self.device, self.tokens, dict(sub='fixture-user', **claims)
            ]) as request, patch.object(account.time, 'sleep'):
                account.login(self.config)
                self.assertIn('email', request.call_args_list[1].args[1]['scope'].split())
                session = json.loads(account.SESSION.read_text())
                self.assertEqual(session.get('email'), expected)
                self.assertEqual(session.get('emailVerified', False), expected is not None)

    def test_issuer_mismatch_or_cross_origin_endpoints_never_get_tokens(self):
        for metadata in (dict(self.metadata, issuer='https://wrong.example'), dict(self.metadata, token_endpoint='https://wrong.example/token')):
            with self.subTest(metadata=metadata), patch.object(account, 'request', return_value=metadata) as request:
                with self.assertRaises(ValueError): account.login(self.config)
                self.assertEqual(request.call_count, 1)
                self.assertFalse(account.SESSION.exists())

    def test_declined_or_expired_approval_never_writes_session(self):
        for error in ('access_denied', 'expired_token'):
            with self.subTest(error=error), patch.object(account, 'request', side_effect=[self.metadata, self.device, {'error': error}]), patch.object(account.time, 'sleep'):
                with self.assertRaises(ValueError): account.login(self.config)
                self.assertFalse(account.SESSION.exists())

    def test_missing_identity_never_reports_signed_in(self):
        with patch.object(account, 'request', side_effect=[self.metadata, self.device, self.tokens, {}]), patch.object(account.time, 'sleep'):
            with self.assertRaises(ValueError): account.login(self.config)
        self.assertFalse(account.SESSION.exists())

    def test_expired_other_client_and_public_sessions_are_not_signed_in(self):
        account.write_private(account.CONFIG, self.config)
        for changes in ({'expiresAt': time.time() - 1}, {'clientId': 'other-client'}, {'issuer': 'https://other.example'}):
            account.write_private(account.SESSION, dict(self.config, subject='fixture-user', expiresAt=time.time() + 60) | changes)
            self.assertEqual(account.status(), 'sign in')
        account.SESSION.chmod(0o644)
        self.assertNotEqual(account.status(), 'signed in')

    def test_browser_opens_complete_verification_url_and_headless_fallback_still_signs_in(self):
        device = dict(self.device, verification_uri_complete='https://identity.example/device?user_code=TEST-CODE')
        with patch.object(account, 'request', side_effect=[self.metadata, device, self.tokens, {'sub': 'fixture-user'}]), patch.object(account.time, 'sleep'):
            self.assertEqual(account.login(self.config), 0)
        self.browser.assert_called_once_with(device['verification_uri_complete'], new=2)
        self.assertEqual(account.SESSION.stat().st_mode & 0o777, 0o600)

    def test_browser_verification_url_cannot_leave_the_configured_origin(self):
        device = dict(self.device, verification_uri_complete='https://other.example/device?user_code=TEST-CODE')
        with patch.object(account, 'request', side_effect=[self.metadata, device]), self.assertRaises(ValueError):
            account.login(self.config)
        self.browser.assert_not_called()
        self.assertFalse(account.SESSION.exists())

    def test_local_logout_removes_only_session_and_is_idempotent(self):
        account.write_private(account.CONFIG, self.config)
        account.write_private(account.SESSION, dict(self.config, subject='fixture-user', expiresAt=time.time() + 60))
        with patch.object(account, 'request', side_effect=AssertionError('unexpected network')):
            self.assertEqual(account.logout(), 0)
            self.assertEqual(account.logout(), 0)
        self.assertFalse(account.SESSION.exists())
        self.assertTrue(account.CONFIG.exists())
        self.assertEqual(account.status(), 'sign in')

    def test_logout_preserves_symlink_and_its_target(self):
        target = self.root / 'important'; target.write_text('preserve')
        account.SESSION.symlink_to(target)
        with self.assertRaises(ValueError): account.logout()
        self.assertTrue(account.SESSION.is_symlink())
        self.assertEqual(target.read_text(), 'preserve')

    def test_https_is_required_and_url_credentials_are_rejected(self):
        for value in ('http://identity.example', 'https://user:password@identity.example', 'https://identity.example/#fragment'):
            with self.subTest(value=value), self.assertRaises(ValueError): account.url(value)

    def test_private_write_preserves_symlink_target(self):
        target = self.root / 'important'; target.write_text('preserve')
        account.SESSION.symlink_to(target)
        with self.assertRaises(ValueError): account.write_private(account.SESSION, {})
        self.assertEqual(target.read_text(), 'preserve')

    def test_background_refresh_token_requires_explicit_offline_consent(self):
        for offline in (False, True):
            tokens = dict(self.tokens, refresh_token='fixture-offline-token')
            env = {'WORKBENCHES_ACCOUNT_OFFLINE': '1'} if offline else {}
            with patch.dict(os.environ, env, clear=True), patch.object(account, 'request', side_effect=[self.metadata, self.device, tokens, {'sub': 'fixture-user'}]) as request, patch.object(account.time, 'sleep'):
                account.login(self.config)
            self.assertEqual('refreshToken' in json.loads(account.SESSION.read_text()), offline)
            self.assertEqual('offline_access' in request.call_args_list[1].args[1]['scope'], offline)

    def test_conflicting_sensitive_aliases_refuse_without_leaking_values(self):
        env = dict(os.environ, OPENBENCHES_ACCOUNT_ISSUER='https://new.example/realm',
                   WORKBENCHES_ACCOUNT_ISSUER='https://old.example/realm')
        result = subprocess.run([sys.executable, str(ROOT / 'scripts/setup-workbenches-account.py'), '--status'],
                                env=env, text=True, capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 2)
        self.assertIn('OPENBENCHES_ACCOUNT_ISSUER and WORKBENCHES_ACCOUNT_ISSUER differ', result.stderr)
        self.assertNotIn('new.example', result.stderr)
        self.assertNotIn('old.example', result.stderr)
        self.assertNotIn('Traceback', result.stderr)

    def test_quit_does_not_write_provider_settings(self):
        with patch('builtins.input', return_value='Q'), self.assertRaises(SystemExit) as error:
            account.main()
        self.assertEqual(error.exception.code, 130)
        self.assertFalse(account.CONFIG.exists())


if __name__ == '__main__':
    unittest.main()
