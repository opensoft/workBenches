#!/usr/bin/env python3
"""Exercise real temporary Docker containers against the declared offline vault."""
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('guided_tests', ROOT / 'devcontainer.test/test-setup-guided-flow.py')
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


class ContainerTests(unittest.TestCase):
    def test_guided_recovery_for_both_vaults_and_cancel_cleanup(self):
        cases = [('bitwarden', False, 'Codex'), ('bitwarden', False, 'password'),
                 ('bitwarden', False, 'custom'), ('bitwarden', True, 'custom'),
                 ('1password', False, 'Codex'), ('1password', True, 'Codex')]
        for service, cancel, search in cases:
            with self.subTest(service=service, cancel=cancel, search=search), tempfile.TemporaryDirectory() as directory:
                home = Path(directory)
                target = home / '.chatgpt-profiles/profiles/personal/personal-1/auth.json'
                manifest = home / 'mapping.json'
                script = home / 'restore.py'
                mapping = {'schemaVersion': 1, 'service': service, 'guided': True, 'authMode': 'signin',
                           'entries': [{'enabled': True, 'provider': 'codex', 'profile': 'personal-1', 'credentialPath': str(target)}]}
                if service == 'bitwarden':
                    mapping['server'] = 'https://vault.bitwarden.com'
                script.write_text(f'''import importlib.util, subprocess, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location('recovery', {str(ROOT / 'credential-container/credential_recovery.py')!r})
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)
r.IMAGES[{service!r}] = 'workbenches-credential-recovery:test-fixture-v3'
run = r.checked_run
def checked(argv, **kwargs):
    if argv[1] == 'build':
        return subprocess.CompletedProcess(argv, 0)
    return run(argv, **kwargs)
r.checked_run = checked
r.recover({service!r}, Path({str(manifest)!r}), guided_mapping={mapping!r})
''')
                replies = [('Bitwarden login email', 'fixture@example.com\n'), ('Two-step method', '\n'), ('Vault master password', 'fake-master\n')] if service == 'bitwarden' else [
                    ('1Password sign-in address', 'my.1password.com\n'), ('1Password login email', 'fixture@example.com\n'),
                    ('1Password Secret Key', 'Q\n' if cancel else 'fake-secret-key\n')]
                if not cancel or service == 'bitwarden':
                    if service == '1password':
                        replies.append(('Vault account password', 'fake-master\n'))
                    replies.extend([('Search ' + service, search + '\n'), ('Item number', '1\n')])
                    if search == 'custom':
                        replies.append(('Field containing', 'Q\n' if cancel else '2\n'))
                    if service == '1password':
                        replies.append(('Field containing', '1\n'))
                    if not cancel:
                        replies.extend([('Confirm', 'y\n'), ('Stored value', '\n' if search in ('password', 'custom') else '1\n')])
                status, output = helper.terminal_run([sys.executable, str(script)], dict(os.environ, HOME=str(home)), replies)
                self.assertEqual(status, 130 if cancel else 0, output)
                for secret in ('fake-master', 'fake-secret-key', 'FAKE_SESSION_TOKEN', 'fake-only-integration-key', 'NEVER-PRINT'):
                    self.assertNotIn(secret, output)
                if cancel:
                    self.assertFalse(target.exists())
                    self.assertFalse(manifest.exists())
                else:
                    self.assertEqual(json.loads(target.read_text())['OPENAI_API_KEY'], 'fake-only-integration-key')
                    self.assertEqual(target.stat().st_mode & 0o777, 0o600)
                    self.assertEqual(manifest.stat().st_mode & 0o777, 0o600)
                    if search in ('password', 'custom'):
                        row = json.loads(manifest.read_text())['entries'][0]
                        self.assertEqual(row['itemField'], search)
                        self.assertEqual(row['credentialFormat'], 'api-key')
                        if search == 'custom':
                            self.assertEqual(row['customField'], 'API key')


if __name__ == '__main__':
    unittest.main()
