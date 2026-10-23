#!/usr/bin/env python3
"""Reject wrong/private-cache identities before any QA credential upload."""
import base64
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('bootstrap', ROOT / 'qa/release/provision-provider-qa.py')
bootstrap = importlib.util.module_from_spec(spec); spec.loader.exec_module(bootstrap)


def token(email=bootstrap.EMAIL, expiry=None):
    value = {'email': email, 'exp': expiry if expiry is not None else time.time() + 3600, 'sub': 'qa-subject'}
    return 'fixture.' + base64.urlsafe_b64encode(json.dumps(value).encode()).decode().rstrip('=') + '.fixture'


class BootstrapTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.directory = Path(self.temp.name)
        self.addCleanup(self.temp.cleanup)
        self.root = patch.object(bootstrap, 'root', return_value=self.directory)
        self.root.start(); self.addCleanup(self.root.stop)

    def credential(self, provider, email=bootstrap.EMAIL, expiry=None):
        path = self.directory / ('auth.json' if provider == 'codex' else 'claude/.credentials.json')
        path.parent.mkdir(exist_ok=True)
        value = ({'auth_mode': 'chatgpt', 'tokens': {'id_token': token(email, expiry),
                   'account_id': 'fixture-workspace', 'refresh_token': 'fixture-private-refresh'}}
                 if provider == 'codex' else {'claudeAiOauth': {
                   'expiresAt': (expiry if expiry is not None else time.time() + 3600) * 1000,
                   'refreshToken': 'fixture-private-refresh'}})
        path.write_text(json.dumps(value)); path.chmod(0o600)
        return path

    def test_wrong_identity_and_expired_cache_never_upload(self):
        for email, expiry in [('other@example.invalid', None), (bootstrap.EMAIL, 1)]:
            self.credential('codex', email, expiry)
            with patch.object(bootstrap.subprocess, 'run') as run:
                with self.assertRaises(ValueError): bootstrap.collect('codex')
                run.assert_not_called()

    def test_public_file_and_symlink_never_upload(self):
        path = self.credential('codex'); path.chmod(0o644)
        with patch.object(bootstrap.subprocess, 'run') as run:
            with self.assertRaises(ValueError): bootstrap.collect('codex')
            path.chmod(0o600); target = path.with_name('private.json'); path.rename(target); path.symlink_to(target)
            with self.assertRaises(ValueError): bootstrap.collect('codex')
            run.assert_not_called()

    def test_access_only_sessions_cannot_be_marked_refresh_ready(self):
        for provider, section, name in [('codex', 'tokens', 'refresh_token'), ('claude', 'claudeAiOauth', 'refreshToken')]:
            for refresh in (None, '', '   ', 123):
                path = self.credential(provider); value = json.loads(path.read_text())
                value[section][name] = refresh; path.write_text(json.dumps(value))
                with patch.object(bootstrap.subprocess, 'run') as run:
                    with self.assertRaises(ValueError): bootstrap.collect(provider)
                    run.assert_not_called()

    def test_codex_api_key_cannot_satisfy_native_account_slot(self):
        path = self.credential('codex'); value = json.loads(path.read_text())
        value['OPENAI_API_KEY'] = 'fixture-api-key'; path.write_text(json.dumps(value))
        with patch.object(bootstrap.subprocess, 'run') as run:
            with self.assertRaises(ValueError): bootstrap.collect('codex')
            run.assert_not_called()

    def test_malformed_cache_cannot_be_marked_ready(self):
        for provider in ('codex', 'claude'):
            section = 'tokens' if provider == 'codex' else 'claudeAiOauth'
            for value in (None, [], {section: None}, {section: []}):
                path = self.credential(provider); path.write_text(json.dumps(value))
                with patch.object(bootstrap.subprocess, 'run') as run:
                    with self.assertRaises(ValueError): bootstrap.collect(provider)
                    run.assert_not_called()

    def test_codex_upload_private_file_and_metadata_only_output(self):
        self.credential('codex')
        uploaded = []
        def run(argv, **kwargs):
            self.assertEqual(argv[:4], ['az', 'keyvault', 'secret', 'set'])
            self.assertNotIn('fixture-private-refresh', ' '.join(argv))
            path = Path(argv[argv.index('--file') + 1])
            self.assertEqual(path.stat().st_mode & 0o077, 0)
            uploaded.append((path, json.loads(path.read_text())))
            return subprocess.CompletedProcess(argv, 0, b'private-vault-result', b'')
        output = io.StringIO()
        with patch.object(bootstrap.subprocess, 'run', side_effect=run), contextlib.redirect_stdout(output):
            bootstrap.collect('codex')
        path, value = uploaded[0]
        self.assertFalse(path.exists())
        self.assertEqual(value['providerSubject'], 'qa-subject')
        self.assertEqual(value['profile'], 'Team001')
        self.assertNotIn('fixture-private-refresh', output.getvalue())
        self.assertNotIn('private-vault-result', output.getvalue())

    def test_claude_organization_is_not_user_account(self):
        self.credential('claude'); captured = []
        def run(argv, **kwargs):
            if argv[0] == 'fixture-claude':
                return subprocess.CompletedProcess(argv, 0, json.dumps({
                    'loggedIn': True, 'email': bootstrap.EMAIL, 'orgId': 'fixture-tenant'}).encode(), b'')
            captured.append(json.loads(Path(argv[argv.index('--file') + 1]).read_text()))
            return subprocess.CompletedProcess(argv, 0, b'', b'')
        with patch.object(bootstrap, 'binary', return_value='fixture-claude'), \
                patch.object(bootstrap.subprocess, 'run', side_effect=run), contextlib.redirect_stdout(io.StringIO()):
            bootstrap.collect('claude')
        self.assertIsNone(captured[0]['providerAccountId'])
        self.assertEqual(captured[0]['providerTenantId'], 'fixture-tenant')

    def test_isolated_environment_excludes_inherited_credentials(self):
        with patch.dict(os.environ, {'OPENAI_API_KEY': 'fixture-secret', 'ANTHROPIC_API_KEY': 'fixture-secret',
                                     'SSH_AUTH_SOCK': '/fixture/agent', 'GH_TOKEN': 'fixture-secret'}):
            env = bootstrap.environment('codex')
        for name in ('OPENAI_API_KEY', 'ANTHROPIC_API_KEY', 'SSH_AUTH_SOCK', 'GH_TOKEN'):
            self.assertNotIn(name, env)
        self.assertEqual(env['CODEX_HOME'], str(self.directory))
        self.assertNotEqual(env['HOME'], str(Path.home()))

    def test_reserved_api_slots_are_pending_and_have_no_model(self):
        slots = json.loads((ROOT / 'config/qa-provider-slots.json').read_text())
        self.assertEqual(set(slots['providers']), {'claude', 'codex', 'deepseek', 'glm'})
        for name in ('deepseek', 'glm'):
            self.assertEqual(slots['providers'][name]['setup'], 'awaiting-user')
            self.assertIsNone(slots['providers'][name]['model'])


if __name__ == '__main__': unittest.main()
