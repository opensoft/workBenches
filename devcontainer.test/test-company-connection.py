#!/usr/bin/env python3
"""Company onboarding boundaries using disposable files and synthetic IdP data."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import pty
import select
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import company_connection as wizard

spec = importlib.util.spec_from_file_location('company_account', ROOT / 'scripts/setup-workbenches-account.py')
account = importlib.util.module_from_spec(spec); spec.loader.exec_module(account)


class ConnectionTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(); self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.config = {'issuer': 'https://id.example/auth/realms/team', 'clientId': 'registered-application-id'}
        self.metadata = {'issuer': self.config['issuer'], **{
            field: self.config['issuer'] + '/' + field for field in
            ('device_authorization_endpoint', 'token_endpoint', 'userinfo_endpoint')}}
        self.output = io.StringIO()
        capture = contextlib.redirect_stdout(self.output); capture.__enter__(); self.addCleanup(capture.__exit__, None, None, None)

    def source(self, data=None):
        source = self.root / 'enrollment.json'
        source.write_text(json.dumps(self.config if data is None else data))
        return str(source)

    def test_descriptor_preserves_only_defined_non_secret_fields(self):
        data = dict(self.config, organizationId='different-company-id', credentialBrokerUrl='https://broker.example/')
        normalized = wizard.descriptor(data)
        self.assertEqual(normalized['clientId'], 'registered-application-id')
        self.assertEqual(normalized['organizationId'], 'different-company-id')
        self.assertEqual(normalized['credentialBrokerUrl'], 'https://broker.example')

    def test_malformed_or_secret_bearing_descriptors_are_rejected(self):
        cases = [[], {}, dict(self.config, clientSecret='fixture-secret-canary'),
                 dict(self.config, accessToken='fixture-secret-canary'), dict(self.config, clientId=''),
                 dict(self.config, clientId='bad\x1b[2J'), dict(self.config, issuer='http://id.example'),
                 dict(self.config, issuer='https://u:p@id.example'), dict(self.config, issuer='https://id.example/?x=y'),
                 dict(self.config, issuer='https://id.example/#part'), dict(self.config, issuer='https://id.example:bad'),
                 dict(self.config, credentialBrokerUrl='file:///tmp/config')]
        for data in cases:
            with self.subTest(data=data), self.assertRaises(ValueError): wizard.descriptor(data)
        self.assertNotIn('fixture-secret-canary', self.output.getvalue())

    def test_local_and_https_enrollment_import(self):
        self.assertEqual(wizard.read_enrollment(self.source()), self.config)
        response = Mock(); response.read.return_value = json.dumps(self.config).encode()
        response.__enter__ = Mock(return_value=response); response.__exit__ = Mock(return_value=False)
        with patch.object(wizard.urllib.request, 'build_opener') as opener:
            opener.return_value.open.return_value = response
            self.assertEqual(wizard.read_enrollment('https://admin.example/enrollment'), self.config)
            opener.return_value.open.assert_called_once_with('https://admin.example/enrollment', timeout=15)
            response.read.assert_called_once_with(wizard.LIMIT + 1)

    def test_import_bounds_redirects_invalid_json_and_symlinks(self):
        for source in ('http://admin.example/setup', 'https://u:p@admin.example/setup', 'https://admin.example/setup#fragment'):
            with self.subTest(source=source), self.assertRaises(ValueError): wizard.read_enrollment(source)
        with self.assertRaises(ValueError): wizard.NoRedirect().redirect_request(None, None, None, None, None, None)
        source = Path(self.source()); source.write_text('x' * (wizard.LIMIT + 1))
        with self.assertRaises(ValueError): wizard.read_enrollment(str(source))
        source.write_text('{broken')
        with self.assertRaises(ValueError): wizard.read_enrollment(str(source))
        link = self.root / 'linked.json'; link.symlink_to(source)
        with self.assertRaises(ValueError): wizard.read_enrollment(str(link))

    def test_export_round_trip_private_and_no_overwrite(self):
        target = self.root / 'shared.json'
        wizard.export_enrollment(target, self.config)
        self.assertEqual(target.stat().st_mode & 0o777, 0o600)
        self.assertEqual(wizard.read_enrollment(str(target)), self.config)
        before = target.read_bytes()
        with self.assertRaises(ValueError): wizard.export_enrollment(target, dict(self.config, clientId='other'))
        self.assertEqual(target.read_bytes(), before)
        self.assertEqual(set(self.root.iterdir()), {target})

    def test_export_refuses_symlink_destination_or_parent_and_never_exports_tokens(self):
        target = self.root / 'real'; target.write_text('preserve')
        link = self.root / 'link'; link.symlink_to(target)
        with self.assertRaises(ValueError): wizard.export_enrollment(link, self.config)
        folder = self.root / 'directory'; folder.symlink_to(self.root, target_is_directory=True)
        with self.assertRaises(ValueError): wizard.export_enrollment(folder / 'new.json', self.config)
        with self.assertRaises(ValueError): wizard.export_enrollment(self.root / 'tokens.json', dict(self.config, refreshToken='fixture-canary'))
        self.assertEqual(target.read_text(), 'preserve')
        self.assertFalse((self.root / 'tokens.json').exists())

    def test_discovery_never_authorizes_or_proves_client_registration(self):
        request = Mock(return_value=self.metadata)
        result = wizard.discovery(self.config, request)
        request.assert_called_once_with(self.config['issuer'] + '/.well-known/openid-configuration')
        self.assertIn('not verified', result)
        self.assertIn('device sign-in', result)

    def test_discovery_rejects_wrong_issuer_cross_origin_or_unsupported_flow(self):
        missing = dict(self.metadata); del missing['device_authorization_endpoint']
        for metadata in ([], missing, dict(self.metadata, issuer='https://wrong.example'),
                         dict(self.metadata, token_endpoint='https://wrong.example/token'),
                         dict(self.metadata, grant_types_supported=['authorization_code'])):
            with self.subTest(metadata=metadata), self.assertRaises(ValueError):
                wizard.discovery(self.config, Mock(return_value=metadata))

    def test_admin_link_and_registration_instructions(self):
        self.assertEqual(wizard.admin_url(self.config['issuer']), 'https://id.example/auth/admin/')
        self.assertIsNone(wizard.admin_url('https://id.example/not-a-keycloak-realm'))
        guide = '\n'.join(wizard.instructions(self.config['issuer']))
        for phrase in ('once per organization', 'not your user', 'authentication: Off',
                       'Device Authorization Grant: On', 'No client secret', 'openid profile email'):
            self.assertIn(phrase, guide)

    def test_native_browser_and_clipboard_use_host_argument_arrays(self):
        host = Mock(); host.active.return_value = True
        host.which.side_effect = lambda name: name if name in ('xdg-open', 'wl-copy') else None
        host.run.return_value = subprocess.CompletedProcess([], 0)
        self.assertTrue(wizard.native_action('browser', 'https://id.example/admin/', host))
        self.assertEqual(host.run.call_args.args[0], ['xdg-open', 'https://id.example/admin'])
        self.assertTrue(wizard.native_action('copy', 'public registration instructions', host))
        self.assertEqual(host.run.call_args.kwargs['input'], b'public registration instructions')
        self.assertEqual(host.run.call_args.args[0], ['wl-copy'])

    def test_native_unavailable_has_no_shell_or_browser_side_effect(self):
        with patch.object(wizard.shutil, 'which', return_value=None), patch.object(wizard.subprocess, 'run') as run:
            self.assertFalse(wizard.native_action('browser', 'https://id.example/admin/'))
            self.assertFalse(wizard.native_action('copy', 'instructions'))
            run.assert_not_called()

    def test_employee_import_reviews_discovers_and_confirms_before_saving(self):
        source = self.source()
        request = Mock(return_value=self.metadata)
        with patch.object(wizard, 'selected', side_effect=['import', 'save']), \
                patch.object(wizard, 'field', return_value=source), patch.object(wizard, 'prompt', return_value='y'):
            result = wizard.connect(self.root / 'company-one', request, account.write_private, company='One')
        self.assertEqual(result, self.config)
        target = self.root / 'company-one/account-provider.json'
        self.assertEqual(json.loads(target.read_text()), self.config)
        self.assertEqual(target.stat().st_mode & 0o777, 0o600)
        self.assertIn(self.config['issuer'], self.output.getvalue())
        self.assertIn(self.config['clientId'], self.output.getvalue())
        self.assertIn('not verified', self.output.getvalue())
        request.assert_called_once()
        self.assertFalse((target.parent / 'account-session.json').exists())

    def test_admin_guide_browser_copy_export_and_existing_registration(self):
        target = self.root / 'admin-enrollment.json'
        request = Mock(return_value=self.metadata)
        choices = ['admin', 'view', 'browser', 'copy', 'continue', 'export', 'save']
        with patch.object(wizard, 'selected', side_effect=choices) as selected, \
                patch.object(wizard, 'field', side_effect=[self.config['issuer'], self.config['clientId'], str(target)]), \
                patch.object(wizard, 'prompt', side_effect=['', 'yes']), patch.object(wizard, 'native_action', return_value=False):
            result = wizard.connect(self.root / 'company', request, account.write_private)
        self.assertEqual(result, self.config)
        self.assertEqual(wizard.read_enrollment(str(target)), self.config)
        self.assertIn('No client secret', self.output.getvalue())
        self.assertTrue(any('Browser unavailable' in str(call) for call in selected.call_args_list))
        self.assertTrue(any('Clipboard unavailable' in str(call) for call in selected.call_args_list))
        request.assert_called_once()  # no registration/admin API

    def test_decline_back_and_failed_discovery_do_not_change_other_company(self):
        other = self.root / 'other-session.json'; other.write_text('preserve-other-company')
        for approve, fail in (('n', False), ('y', True)):
            with self.subTest(approve=approve, fail=fail), \
                    patch.object(wizard, 'selected', side_effect=['existing', 'save', 'back', 'back']), \
                    patch.object(wizard, 'field', side_effect=[self.config['issuer'], self.config['clientId']]), \
                    patch.object(wizard, 'prompt', return_value=approve):
                request = Mock(side_effect=ValueError('unavailable')) if fail else Mock(return_value=self.metadata)
                self.assertIsNone(wizard.connect(self.root / 'new-company', request, account.write_private))
            self.assertFalse((self.root / 'new-company').exists())
            self.assertEqual(other.read_text(), 'preserve-other-company')

    def test_back_from_field_and_cancel_preserve_unsaved_configuration(self):
        with patch.object(wizard, 'selected', side_effect=['existing', 'back']), patch.object(wizard, 'field', side_effect=wizard.Back):
            self.assertIsNone(wizard.connect(self.root, Mock(), Mock()))
        with patch.object(wizard, 'selected', return_value='import'), patch.object(wizard, 'field', side_effect=SystemExit(130)):
            with self.assertRaises(SystemExit) as raised: wizard.connect(self.root, Mock(), Mock())
            self.assertEqual(raised.exception.code, 130)
        self.assertFalse((self.root / 'account-provider.json').exists())

    def test_account_helper_configured_login_bypasses_wizard(self):
        account.write_private(self.root / 'account-provider.json', self.config)
        with patch.object(account, 'CONFIG', self.root / 'account-provider.json'), \
                patch.dict(os.environ, {}, clear=True), patch.object(sys, 'argv', ['account']), \
                patch.object(wizard, 'connect') as connect, patch.object(account, 'login', return_value=0) as login:
            self.assertEqual(account.main(), 0)
        connect.assert_not_called(); login.assert_called_once_with(self.config)

    def test_account_helper_new_company_uses_selected_root_and_then_existing_login(self):
        with patch.object(account, 'CONFIG', self.root / 'company/account-provider.json'), \
                patch.dict(os.environ, {'WORKBENCHES_ACCOUNT_COMPANY':'Selected Company'}, clear=True), \
                patch.object(sys, 'argv', ['account']), patch.object(wizard, 'connect', return_value=self.config) as connect, \
                patch.object(account, 'login', return_value=0) as login:
            self.assertEqual(account.main(), 0)
        self.assertEqual(connect.call_args.args[0], self.root / 'company')
        self.assertEqual(connect.call_args.kwargs['company'], 'Selected Company')
        login.assert_called_once_with(self.config)

    def test_real_terminal_back_and_cancel_never_start_provider_login(self):
        for key, expected in ((b'b', 0), (b'q', 130)):
            with self.subTest(key=key):
                master, slave = pty.openpty()
                env = dict(os.environ, WORKBENCHES_ACCOUNT_ROOT=str(self.root / 'fresh-company'))
                env.pop('WORKBENCHES_ACCOUNT_ISSUER', None); env.pop('WORKBENCHES_ACCOUNT_CLIENT_ID', None)
                proc = subprocess.Popen([sys.executable, str(ROOT/'scripts/setup-workbenches-account.py')],
                                        stdin=slave, stdout=slave, stderr=slave, env=env)
                os.close(slave)
                try:
                    output = b''; deadline = time.monotonic() + 5
                    while b'COMPANY CONNECTION' not in output and time.monotonic() < deadline:
                        if select.select([master], [], [], .1)[0]: output += os.read(master, 65536)
                    self.assertIn(b'COMPANY CONNECTION', output)
                    os.write(master, key); proc.wait(timeout=5)
                    self.assertEqual(proc.returncode, expected)
                    self.assertFalse((self.root/'fresh-company/account-provider.json').exists())
                finally:
                    if proc.poll() is None: proc.kill(); proc.wait()
                    os.close(master)


if __name__ == '__main__':
    unittest.main()
