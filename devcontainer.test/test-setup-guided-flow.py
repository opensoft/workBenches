#!/usr/bin/env python3
"""Regression coverage for selected installs, private mapping enrollment and stdin."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import pty
import select
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import profile_credentials as profiles
import setup_selection as selection
runtime = profiles.RUNTIME
selector_spec = importlib.util.spec_from_file_location('selector', ROOT / 'scripts/setup-credential-recovery.py')
selector = importlib.util.module_from_spec(selector_spec)
selector_spec.loader.exec_module(selector)


def terminal_run(argv, env, replies):
    master, slave = pty.openpty()
    process = subprocess.Popen(argv, stdin=slave, stdout=slave, stderr=slave, env=env, start_new_session=True)
    os.close(slave)
    output = b''
    pending = list(replies)
    last = 0
    deadline = time.monotonic() + 15
    try:
        while time.monotonic() < deadline:
            if select.select([master], [], [], .1)[0]:
                try:
                    chunk = os.read(master, 65536)
                except OSError:
                    break
                if not chunk:
                    break
                output += chunk
                if pending and pending[0][0].encode() in output[last:]:
                    _, reply = pending.pop(0)
                    os.write(master, reply.encode())
                    last = len(output)
            if process.poll() is not None:
                break
        process.wait(timeout=2)
        return process.returncode, output.decode(errors='replace')
    finally:
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGKILL)
        process.wait()
        os.close(master)


class GuidedFlowTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.config = self.home / '.config/workbenches'
        self.config.mkdir(parents=True)
        self.env = dict(os.environ, HOME=str(self.home), XDG_CONFIG_HOME=str(self.home / '.config'))
        for key in list(self.env):
            if key.startswith(('WORKBENCHES_', 'CLAUDE_PROFILES_', 'CODEX_', 'CHATGPT_PROFILES_', 'PI_PROFILES_', 'AI_CREDENTIAL_', 'DOCKER_')):
                self.env.pop(key)
        self.addCleanup(patch.stopall)
        patch.dict(os.environ, self.env, clear=True).start()
        self.target = self.home / '.chatgpt-profiles/profiles/personal/personal-1/auth.json'
        self.entry = {'enabled': True, 'provider': 'codex', 'profile': 'personal-1', 'credentialPath': str(self.target)}
        self.mapping = {'schemaVersion': 1, 'service': 'bitwarden', 'server': 'https://vault.bitwarden.com',
                        'guided': True, 'authMode': 'signin', 'entries': [self.entry]}
        self.payload = b'{"OPENAI_API_KEY":"fake-only-key"}'

    def manifest(self, names=('personal-1',)):
        data = {'version': 1, 'families': ['personal'], 'profiles': [
            {'name': name, 'email': name + '@example.com', 'family': 'personal', 'profilePath': 'personal/' + name, 'aliases': []}
            for name in names]}
        (self.config / 'openai-profiles.json').write_text(json.dumps(data))
        return data

    def test_onboarding_q_and_eof_cancel_without_traceback_or_manifests(self):
        for reply in ('Q\n', '\x04'):
            status, output = terminal_run([sys.executable, str(ROOT / 'scripts/onboard-ai-profiles.py')], self.env,
                                         [('Set up separate AI profiles', reply)])
            self.assertEqual(status, 130, output)
            self.assertNotIn('Traceback', output)
            self.assertFalse((self.config / 'openai-profiles.json').exists())

    def test_personal_selected_codex_needs_no_github_and_creates_no_other_manifest(self):
        env = dict(self.env, WORKBENCHES_SELECTED_PROVIDERS='openai', WORKBENCHES_PROFILE_PROVIDERS='openai', WORKBENCHES_REQUIRE_PROFILE='1')
        status, output = terminal_run([sys.executable, str(ROOT / 'scripts/onboard-ai-profiles.py')], env,
            [('Profile ownership', '\n'), ('AI account login email', 'person@example.com\n'), ('Use a GitHub credential registry', '\n')])
        self.assertEqual(status, 0, output)
        self.assertNotIn('Personal GitHub username', output)
        self.assertFalse((self.config / 'claude-profiles.json').exists())
        self.assertEqual(json.loads((self.config / 'openai-profiles.json').read_text())['profiles'][0]['email'], 'person@example.com')

    def test_recovered_profile_readiness_requires_valid_credentials_for_each_profile(self):
        self.manifest(('personal-1', 'personal-2'))
        self.target.parent.mkdir(parents=True)
        self.target.write_bytes(self.payload)
        self.assertTrue(profiles.present(self.entry))
        with patch.object(sys, 'argv', ['status', 'ready', 'codex']):
            self.assertEqual(profiles.main(), 1)
        other = self.target.parent.parent / 'personal-2/auth.json'
        other.parent.mkdir()
        other.write_bytes(self.payload)
        with patch.object(sys, 'argv', ['status', 'ready', 'codex']):
            self.assertEqual(profiles.main(), 0)
        other.write_text('{"unexpected":true}')
        self.assertFalse(profiles.present(dict(self.entry, profile='personal-2', credentialPath=str(other))))

    def test_native_login_reads_user_answers_not_profile_rows_and_skips_ready_profile(self):
        self.manifest(('personal-1', 'personal-2', 'personal-3'))
        self.target.parent.mkdir(parents=True)
        self.target.write_bytes(self.payload)
        binaries = self.home / 'bin'
        binaries.mkdir()
        launcher = binaries / 'pcodex'
        launcher.write_text('#!/bin/bash\nprintf "%s\\n" "$2" >> "$HOME/logins"\n')
        launcher.chmod(0o755)
        env = dict(self.env, PATH=str(binaries) + ':' + os.environ['PATH'])
        command = f'source "{ROOT}/scripts/interactive-setup.sh"; guide_isolated_profile_logins Codex "$XDG_CONFIG_HOME/workbenches/openai-profiles.json" pcodex; read -r remainder || :; printf \'REMAINDER:%s\' \"$remainder\"'
        result = subprocess.run(['bash', '-c', command], input='y\ny\nn\n', env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.home / 'logins').read_text(), 'personal-2\n')
        self.assertNotIn('Login personal-1', result.stdout)
        self.assertTrue(result.stdout.endswith('REMAINDER:'))

    def test_native_login_q_at_profile_prompt_cancels(self):
        self.manifest()
        launcher = self.home / 'pcodex'
        launcher.write_text('#!/bin/bash\nexit 0\n')
        launcher.chmod(0o755)
        command = f'source "{ROOT}/scripts/interactive-setup.sh"; guide_isolated_profile_logins Codex "$XDG_CONFIG_HOME/workbenches/openai-profiles.json" "{launcher}"'
        result = subprocess.run(['bash', '-c', command], input=b'y\nQ\n', env=self.env, capture_output=True)
        self.assertEqual(result.returncode, 130)

    def test_selection_uses_only_selected_benches_and_rejects_unrecognized_actions(self):
        plan = self.home / 'selection.json'
        plan.write_text(json.dumps({'schemaVersion': 1, 'components': [{'key': 'codex_cli', 'action': 'install'}]}))
        plan.chmod(0o600)
        for command, expected in [('benches', ''), ('providers', 'openai\n')]:
            result = subprocess.run([sys.executable, str(ROOT / 'scripts/setup_selection.py'), command, str(plan)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, expected)
        data = json.loads(plan.read_text())
        data['components'][0]['action'] = 'execute'
        plan.write_text(json.dumps(data))
        with self.assertRaises(ValueError):
            selection.load(plan)

    def test_selected_codex_does_not_create_pi_or_other_profile_homes(self):
        self.manifest()
        result = subprocess.run(['bash', str(ROOT / 'scripts/setup-ai-profiles.sh'), '--apply-existing'],
            env=dict(self.env, WORKBENCHES_SELECTED_PROVIDERS='openai', WORKBENCHES_AUTH_ROUTE='later'), capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.target.parent.is_dir())
        for folder in ('.claude-profiles', '.pi-profiles', '.gemini-profiles', '.grok-profiles', '.glm-profiles'):
            self.assertFalse((self.home / folder).exists(), folder)
        self.assertFalse((self.config / 'pi-profiles.json').exists())

    def test_auth_route_available_without_separate_profiles(self):
        route = self.home / 'route'
        route.touch(mode=0o600)
        status, output = terminal_run([sys.executable, str(ROOT / 'scripts/setup-credential-recovery.py'), '--choose-route', str(route)], self.env,
                                     [('Authentication route', '2\n')])
        self.assertEqual(status, 0, output)
        self.assertEqual(route.read_text(), 'vault')

    def test_direct_or_later_auth_does_not_require_profiles_or_prompt_for_vault(self):
        for answer in ('1', '3'):
            replies = [('Authentication route', answer + '\n')]
            if answer == '1':
                replies.append(('Set up separate AI profiles', 'n\n'))
            status, output = terminal_run(['bash', str(ROOT / 'scripts/setup-ai-profiles.sh'), '--interactive'],
                                         dict(self.env, WORKBENCHES_SELECTED_PROVIDERS='openai'), replies)
            self.assertEqual(status, 0, output)
            self.assertNotIn('Services (numbers', output)
            self.assertFalse((self.config / 'openai-profiles.json').exists())

    def test_non_npm_selection_does_not_check_or_offer_node(self):
        binary = self.home / 'bin'
        binary.mkdir()
        (binary / 'node').write_text('#!/bin/bash\necho unexpected > "$HOME/node-invoked"\nexit 1\n')
        (binary / 'node').chmod(0o755)
        command = f'source "{ROOT}/scripts/interactive-setup.sh"; component_checked[claude_cli]=true; ensure_selected_dependencies'
        result = subprocess.run(['bash', '-c', command], env=dict(self.env, PATH=str(binary) + ':' + self.env['PATH']), capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.home / 'node-invoked').exists())

    def test_imported_mapping_is_filtered_to_selected_profiles_and_preserved(self):
        self.manifest()
        mapping = copy.deepcopy(self.mapping)
        mapping.pop('guided')
        mapping['entries'][0]['itemId'] = '00000000-0000-0000-0000-000000000001'
        mapping['entries'].append(dict(self.entry, provider='claude', profile='unselected', credentialPath=str(self.home / '.claude-profiles/profiles/unselected/.credentials.json'), itemId='00000000-0000-0000-0000-000000000002'))
        manifest = self.config / 'ai-credential-bitwarden.json'
        manifest.write_text(json.dumps(mapping))
        manifest.chmod(0o600)
        original = manifest.read_bytes()
        captured = []
        def restore(argv, **kwargs):
            path = Path(argv[argv.index('--manifest') + 1])
            captured.append(json.loads(path.read_text()))
            return subprocess.CompletedProcess(argv, 0)
        with patch.dict(os.environ, WORKBENCHES_SELECTED_PROVIDERS='openai'), patch.object(runtime, 'docker_ready'), patch.object(selector.subprocess, 'run', side_effect=restore):
            self.assertEqual(selector.run_recovery('bitwarden', manifest), 0)
        self.assertEqual([row['provider'] for row in captured[0]['entries']], ['codex'])
        self.assertEqual(manifest.read_bytes(), original)

    def test_raw_api_key_conversion_produces_codex_auth_json(self):
        mapping = {'schemaVersion': 1, 'service': '1password', 'entries': [dict(self.entry, secretReference='op://vault/item/field', credentialFormat='api-key')]}
        output = self.home / 'output'
        output.mkdir()
        with patch.object(runtime, 'secret_input', return_value='fake-service-token'), patch.object(runtime, 'vault_command', return_value=b'fake-only-key'), patch.object(runtime.Path, 'mkdir'):
            runtime.container_restore(mapping, output)
        self.assertEqual(json.loads((output / '0.json').read_text()), {'OPENAI_API_KEY': 'fake-only-key'})

    def fake_docker(self, argv, **kwargs):
        if argv[1] == 'run':
            output = Path(next(arg.split('src=', 1)[1].split(',', 1)[0] for arg in argv if 'dst=/recovery/output' in arg))
            self.output = output
            returned = dict(self.mapping, entries=[dict(self.entry, itemId='00000000-0000-0000-0000-000000000001')])
            returned.pop('guided')
            if getattr(self, 'hostile', False):
                returned['entries'][0]['credentialPath'] = str(self.home / '.bashrc')
            (output / 'mapping.json').write_text(json.dumps(returned))
            (output / 'mapping.json').chmod(0o600)
            (output / '0.json').write_bytes(self.payload)
            (output / '0.json').chmod(0o600)
        return subprocess.CompletedProcess(argv, 0, stdout='unix:///var/run/docker.sock')

    def guided_restore(self):
        mapping_path = self.config / 'ai-credential-bitwarden.json'
        with patch.object(runtime, 'checked_run', side_effect=self.fake_docker), patch('sys.stdin.isatty', return_value=True), patch('sys.stdout.isatty', return_value=True):
            runtime.recover('bitwarden', mapping_path, guided_mapping=self.mapping)
        return mapping_path

    def test_guided_recovery_creates_private_mapping_and_approved_credential(self):
        mapping = self.guided_restore()
        self.assertEqual(mapping.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.target.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.target.read_bytes(), self.payload)
        self.assertNotIn('fake-only-key', mapping.read_text())
        self.assertFalse(self.output.exists())

    def test_hostile_container_mapping_and_invalid_payload_install_nothing(self):
        for hostile, payload in ((True, self.payload), (False, b'{"unexpected":"fake-secret"}')):
            self.hostile, self.payload = hostile, payload
            with self.assertRaises(runtime.RecoveryError):
                self.guided_restore()
            self.assertFalse(self.target.exists())
            self.assertFalse((self.config / 'ai-credential-bitwarden.json').exists())
            self.assertFalse(self.output.exists())

    def test_guided_picker_displays_metadata_only_and_saves_exact_source(self):
        note = {'id': '00000000-0000-0000-0000-000000000001', 'name': 'Codex profile', 'type': 2, 'notes': 'NEVER-DISPLAY-SECRET'}
        with patch.object(runtime, 'prompt', side_effect=['Codex', '1', 'y', '1']), patch.object(runtime, 'vault_command', return_value=json.dumps([note]).encode()), patch('sys.stdout') as output:
            entry = runtime.pick_item(self.mapping, self.entry, {})
        self.assertEqual(entry['itemId'], note['id'])
        self.assertNotIn('NEVER-DISPLAY-SECRET', str(output.mock_calls))

    def test_native_signin_captures_token_and_q_cancels(self):
        cli = self.home / 'fake-op'
        cli.write_text('''#!/usr/bin/env python3
import getpass
getpass.getpass('Enter your secret key: ')
getpass.getpass('Enter the password for user@example.com: ')
print('FAKE_SESSION_TOKEN_01234567890123456789')
''')
        cli.chmod(0o755)
        with patch.object(runtime, 'secret_input', side_effect=['fake-key', 'fake-password']):
            token = runtime.native_signin([str(cli)], self.env)
        self.assertEqual(token, 'FAKE_SESSION_TOKEN_01234567890123456789')
        with patch.object(runtime, 'secret_input', side_effect=SystemExit(130)):
            with self.assertRaises(SystemExit) as error:
                runtime.native_signin([str(cli)], self.env)
        self.assertEqual(error.exception.code, 130)


if __name__ == '__main__':
    unittest.main()
