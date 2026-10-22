#!/usr/bin/env python3
"""Regression coverage for selected installs, private mapping enrollment and stdin."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import pty
import re
import select
import signal
import shutil
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
                pattern = pending[0][0] if pending else None
                matched = pattern.search(output[last:].decode(errors='replace')) if isinstance(pattern, re.Pattern) else pattern is not None and pattern.encode() in output[last:]
                if matched:
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
            if key.startswith(('WORKBENCHES_', 'CLAUDE_PROFILES_', 'CODEX_', 'CHATGPT_PROFILES_', 'PI_PROFILES_', 'AI_CREDENTIAL_', 'DOCKER_', 'OPENAI_', 'ANTHROPIC_')):
                self.env.pop(key)
        self.env["WORKBENCHES_TEST_NATIVE_TOOLS"] = "1"
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

    def test_compact_vault_choice_is_one_response_and_remembers_service(self):
        route = self.home / 'route'
        route.touch(mode=0o600)
        status, output = terminal_run([sys.executable, str(ROOT / 'scripts/setup-credential-recovery.py'), '--choose-route', str(route)], self.env, [('Authentication route', '2V\n')])
        self.assertEqual(status, 0, output)
        self.assertEqual(route.read_text(), 'vault:vaultwarden')
        self.assertNotIn('Services (numbers', output)

    def test_compact_recovery_infers_key_and_keeps_explicit_destination_confirmation(self):
        mapping = dict(self.mapping, compact=True)
        item = {'id': '00000000-0000-0000-0000-000000000001', 'name': 'Codex test', 'type': 1, 'login': {'password': 'NEVER-PRINT'}}
        answers = []
        def answer(label):
            answers.append(label)
            return 'y'
        def command(argv, env, limit=24576):
            return json.dumps([item]).encode() if argv[1] == 'list' else b'sk-test-invalid-integration-key'
        with patch.object(runtime, 'vault_command', side_effect=command), patch.object(runtime, 'prompt', side_effect=answer):
            picked = runtime.pick_item(mapping, self.entry, {})
        self.assertEqual(picked['credentialFormat'], 'api-key')
        self.assertEqual(answers, ['Confirm [y/N]: '])


    def test_compact_picker_does_not_infer_an_opaque_password_as_an_api_key(self):
        item = {'id': '00000000-0000-0000-0000-000000000001', 'name': 'Codex test', 'type': 1, 'login': {'password': 'NEVER-PRINT'}}
        def command(argv, env, limit=24576):
            return json.dumps([item]).encode() if argv[1] == 'list' else b'an-opaque-login-password'
        with patch.object(runtime, 'vault_command', side_effect=command), patch.object(runtime, 'prompt', side_effect=['y','2']) as prompt:
            runtime.pick_item(dict(self.mapping, compact=True), self.entry, {})
        self.assertEqual(prompt.call_count, 2)
        self.assertIn('Stored value', prompt.call_args.args[0])

    def test_compact_picker_requires_selection_when_items_are_ambiguous_and_cancels(self):
        item = {'id': '00000000-0000-0000-0000-000000000001', 'name': 'Codex test', 'type': 2, 'notes': 'NEVER-PRINT'}
        with patch.object(runtime, 'vault_command', return_value=json.dumps([item, dict(item, id='00000000-0000-0000-0000-000000000002')]).encode()), patch.object(runtime, 'prompt', return_value='s') as prompt:
            self.assertIsNone(runtime.pick_item(dict(self.mapping,compact=True), self.entry, {}))
        self.assertIn('Item number', prompt.call_args.args[0])

    def test_profile_email_default_is_selected_metadata_and_ambiguous_accounts_have_no_default(self):
        self.manifest()
        self.assertEqual(profiles.login_email([self.entry]), 'personal-1@example.com')
        self.manifest(('personal-1','personal-2'))
        other = dict(self.entry,profile='personal-2')
        self.assertEqual(profiles.login_email([self.entry,other]), '')

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
        if argv[1] == 'exec':
            output = Path(argv[argv.index('--output') + 1])
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

    def shell(self, command, input='', **env):
        return subprocess.run(['bash', '-c', f'source "{ROOT}/scripts/interactive-setup.sh"; ' + command],
                              input=input, env=dict(self.env, **env), capture_output=True, text=True, timeout=10)

    def test_installed_items_default_to_no_changes_and_do_not_need_node(self):
        plan = self.home / 'selection.json'
        result = self.shell(f'''init_components
check_component_status() {{ echo installed; }}
refresh_host_tool_inventory() {{ :; }}
refresh_bench_inventory() {{ :; }}
load_requirements() {{ :; }}
load_statuses
component_checked[codex_cli]=true  # A checkbox without an action still means keep.
selection_file="{plan}"
save_selection
ensure_selected_dependencies
''')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(plan.read_text())['components'], [])

    def test_space_updates_and_undoes_and_remove_has_a_separate_undo(self):
        result = self.shell('''init_components
component_status[codex_cli]=installed
CURRENT_SECTION=1; current_selection=2
for step in 1 2 3 4 5 6; do
  handle_input
  printf '%s:%s\\n' "${component_checked[codex_cli]}" "${component_action[codex_cli]}"
done''', input='  DD D')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), ['true:update', 'false:', 'true:uninstall', 'false:', 'true:update', 'true:uninstall'])

    def test_new_item_space_undoes_install_and_remove_is_ignored(self):
        result = self.shell('''init_components
component_status[codex_cli]='not installed'
CURRENT_SECTION=1; current_selection=2
for step in 1 2 3; do
  handle_input
  printf '%s:%s\\n' "${component_checked[codex_cli]}" "${component_action[codex_cli]}"
done''', input='  D')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), ['true:install', 'false:', 'false:'])

    def test_update_selection_derives_required_providers_and_node(self):
        plan = self.home / 'selection.json'
        plan.write_text(json.dumps({'schemaVersion': 1, 'components': [{'key': 'codex_cli', 'action': 'update'}]}))
        plan.chmod(0o600)
        for command, output in [('providers', 'openai\n'), ('node', '')]:
            result = subprocess.run([sys.executable, str(ROOT / 'scripts/setup_selection.py'), command, str(plan)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, output)

    def fake_npm(self, prefix, failure=0):
        binary = self.home / 'bin'
        binary.mkdir(exist_ok=True)
        npm = binary / 'npm'
        npm.write_text(f'''#!/bin/bash
if [[ "$*" == "config get prefix" ]]; then echo "{prefix}"; exit 0; fi
echo "$*" >> "$HOME/npm-actions"
if [[ "$1" == config ]]; then exit 0; fi
echo 'npm ERR! simulated failure' >&2
exit {failure}
''')
        npm.chmod(0o755)
        return str(binary) + ':' + self.env['PATH']

    def test_npm_readonly_prefix_uses_user_location_and_persists_path_once(self):
        prefix = self.home / 'readonly-prefix'
        prefix.mkdir(mode=0o555)
        path = self.fake_npm(prefix)
        result = self.shell('''ensure_npm_install_location || exit $?
persist_npm_user_path; persist_npm_user_path
printf 'PREFIX:%s\\nPATH:%s\\n' "$npm_config_prefix" "$PATH"''', PATH=path, NPM_CONFIG_PREFIX=str(prefix))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f'PREFIX:{self.home}/.local', result.stdout)
        self.assertIn(f'PATH:{self.home}/.local/bin:', result.stdout)
        self.assertEqual((self.home / 'npm-actions').read_text().strip(), f'config set prefix {self.home}/.local --location=user')
        for name in ('.profile', '.bashrc', '.zshrc'):
            self.assertEqual((self.home / name).read_text().count('# workBenches user npm executables'), 1)
        login = subprocess.run(['bash', '-c', '. "$HOME/.bashrc"; printf "%s" "$PATH"'],
                               env=dict(self.env, PATH=f'/usr/bin:{self.home}/.local/bin'), capture_output=True, text=True)
        self.assertTrue(login.stdout.startswith(f'{self.home}/.local/bin:'), login.stdout)

    def test_writable_node_manager_prefix_is_preserved(self):
        prefix = self.home / 'node-manager'
        prefix.mkdir()
        result = self.shell('ensure_npm_install_location; persist_npm_user_path', PATH=self.fake_npm(prefix))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.home / 'npm-actions').exists())
        self.assertFalse((self.home / '.bashrc').exists())

    def test_each_failed_npm_update_causes_installer_failure(self):
        for item in ('codex_cli', 'copilot_cli', 'openspec'):
            result = self.shell(f'''init_components
component_checked[{item}]=true
component_status[{item}]=installed
component_action[{item}]=update
refresh_component_statuses() {{ :; }}
process_selections''', input='\n', PATH=self.fake_npm(self.home, failure=13), WORKBENCHES_AUTH_ROUTE='later')
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn('update failed (exit 13)', result.stdout)
            self.assertNotIn('updated', result.stdout)
            self.assertNotIn('completed successfully', result.stdout)

    def test_npm_prefix_migration_installs_instead_of_empty_update(self):
        result = self.shell('npm_update_tool @openai/codex Codex', PATH=self.fake_npm(self.home), WORKBENCHES_NPM_PREFIX_CHANGED='1')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.home / 'npm-actions').read_text().strip(), 'install -g @openai/codex')

    def test_update_cancellation_propagates(self):
        for code in (130, 143):
            result = self.shell('npm_update_tool @openai/codex Codex', PATH=self.fake_npm(self.home, failure=code))
            self.assertEqual(result.returncode, code)

    def test_recovered_credentials_skip_auth_route_and_vault_questions(self):
        self.manifest()
        self.target.parent.mkdir(parents=True)
        self.target.write_bytes(self.payload)
        route = self.home / 'route'
        route.touch(mode=0o600)
        env = dict(self.env, WORKBENCHES_SELECTED_PROVIDERS='openai')
        result = subprocess.run([sys.executable, str(ROOT / 'scripts/setup-credential-recovery.py'), '--choose-route', str(route)], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(route.read_text(), 'existing')
        result = subprocess.run([sys.executable, str(ROOT / 'scripts/setup-credential-recovery.py'), '--interactive'], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('Services (numbers', result.stdout)
        self.assertIn('no missing selected credentials', result.stdout)

    def test_standard_credentials_are_reused_without_creating_profiles(self):
        target = self.home / '.codex/auth.json'
        target.parent.mkdir()
        target.write_bytes(self.payload)
        status, output = terminal_run(['bash', str(ROOT / 'scripts/setup-ai-profiles.sh'), '--interactive'],
                                     dict(self.env, WORKBENCHES_SELECTED_PROVIDERS='openai'), [])
        self.assertEqual(status, 0, output)
        self.assertNotIn('Authentication route [1]', output)
        self.assertNotIn('Set up separate AI profiles', output)
        self.assertNotIn('Services (numbers', output)
        self.assertFalse((self.config / 'openai-profiles.json').exists())

    def test_bitwarden_login_password_and_custom_field_picker_display_no_values(self):
        item = {'id': '00000000-0000-0000-0000-000000000001', 'name': 'Codex login', 'type': 1,
                'login': {'password': 'NEVER-DISPLAY-PASSWORD'},
                'fields': [{'name': 'API key', 'type': 1, 'value': 'NEVER-DISPLAY-KEY'}]}
        for choice, expected in [('1', 'password'), ('2', 'custom')]:
            with patch.object(runtime, 'prompt', side_effect=['Codex', '1', choice, 'y', '']), patch.object(runtime, 'vault_command', return_value=json.dumps([item]).encode()), patch('sys.stdout') as output:
                entry = runtime.pick_item(self.mapping, self.entry, {})
            self.assertEqual(entry['itemField'], expected)
            self.assertEqual(entry['credentialFormat'], 'api-key')
            self.assertNotIn('NEVER-DISPLAY', str(output.mock_calls))
            if expected == 'custom':
                self.assertEqual(entry['customField'], 'API key')

    def test_custom_field_lookup_is_exact_and_duplicate_names_are_rejected(self):
        row = dict(self.entry, itemId='00000000-0000-0000-0000-000000000001', itemField='custom', customField='API key')
        item = {'fields': [{'name': 'API key', 'type': 1, 'value': 'fake-key'}, {'name': 'Other key', 'type': 1, 'value': 'wrong-key'}]}
        with patch.object(runtime, 'vault_command', return_value=json.dumps(item).encode()) as command:
            self.assertEqual(runtime.bitwarden_payload(row, {}), b'fake-key')
        self.assertEqual(command.call_args.args[0], ['bw', 'get', 'item', row['itemId']])
        item['fields'].append(item['fields'][0])
        with patch.object(runtime, 'vault_command', return_value=json.dumps(item).encode()), self.assertRaises(runtime.RecoveryError):
            runtime.bitwarden_payload(row, {})
        self.assertNotIn('API key', [field['label'] for field in runtime.bitwarden_fields(item)])

    def test_mapping_field_metadata_is_validated_and_same_item_different_fields_allowed(self):
        base = dict(self.entry, itemId='00000000-0000-0000-0000-000000000001')
        data = dict(self.mapping, entries=[dict(base, itemField='password'), dict(base, profile='personal-2', itemField='custom', customField='API key')])
        self.assertEqual(len(runtime.validate_mapping(data, 'bitwarden')), 2)
        for row in (dict(base, itemField='shell'), dict(base, itemField='custom'), dict(base, itemField='custom', customField='\x1b[31m'), dict(base, customField='unexpected')):
            with self.assertRaises(runtime.RecoveryError):
                runtime.validate_mapping(dict(self.mapping, entries=[row]), 'bitwarden')

    def test_enter_applies_selected_cli_without_host_or_account_setup(self):
        repo = self.home / 'workBenches'
        repo.mkdir()
        for directory in ('scripts', 'config', 'credential-container'):
            shutil.copytree(ROOT / directory, repo / directory, ignore=shutil.ignore_patterns('__pycache__'))
        for name in ('setup.sh', 'bootstrap.sh'):
            shutil.copy(ROOT / name, repo / name)
        binary = self.home / 'bin'
        binary.mkdir()
        docker = binary / 'docker'
        docker.write_text('#!/bin/bash\nif [[ "$1" == info ]]; then echo linux; exit 0; fi\nexit 1\n')
        docker.chmod(0o755)
        shell = repo / 'scripts/setup-shell.sh'
        shell.write_text('#!/bin/bash\necho unexpected > "$HOME/host-changed"\n')
        for name, body in {
            'npm': '#!/bin/bash\nif [[ "$*" == "config get prefix" ]]; then echo "$HOME/.local"; elif [[ "$1" == install || "$1" == update ]]; then touch "$HOME/cli-installed"; fi\n',
            'codex': '#!/bin/bash\necho "codex-cli 1.0.0"\n',
            'node': '#!/bin/bash\necho v24.0.0\n',
        }.items():
            path = binary / name; path.write_text(body); path.chmod(0o755)
        status, output = terminal_run(['bash', str(repo / 'setup.sh')],
            dict(self.env, PATH=str(binary) + ':' + self.env['PATH']),
            [(re.compile(r'REQUIREMENTS · (\d+)/\1 ready'), '\x1b[C\x1b[C\x1b[B\x1b[B \n')])
        self.assertEqual(status, 0, output)
        self.assertTrue((self.home / 'cli-installed').exists())
        self.assertNotIn('Apply these changes?', output)
        self.assertNotIn('Authentication requirements', output)
        self.assertIn('Authentication pending', output)
        self.assertNotIn('Authentication route [1]', output)
        self.assertNotIn('Profile ownership', output)
        self.assertFalse((self.home / 'host-changed').exists())
        self.assertFalse((self.config / 'openai-profiles.json').exists())
        self.assertFalse((self.home / '.chatgpt-profiles').exists())

    def test_fresh_bench_builds_family_before_setup_and_stops_on_family_failure(self):
        for code in (0, 13):
            with self.subTest(family_status=code), tempfile.TemporaryDirectory() as directory:
                home = Path(directory)
                repo = home / 'workBenches'
                repo.mkdir()
                for name in ('scripts', 'config', 'credential-container'):
                    shutil.copytree(ROOT / name, repo / name, ignore=shutil.ignore_patterns('__pycache__'))
                for name in ('setup.sh', 'bootstrap.sh'):
                    shutil.copy(ROOT / name, repo / name)
                binary = home / 'bin'
                binary.mkdir()
                docker = binary / 'docker'
                (repo / 'scripts/shared-images.py').write_text('import sys; sys.exit(0)\n')
                docker.write_text('#!/bin/bash\nif [[ "$1" == info ]]; then echo linux; fi\nexit 0\n')
                docker.chmod(0o755)
                shell = repo / 'scripts/setup-shell.sh'
                shell.write_text('#!/bin/bash\nexit 0\n')
                interactive = repo / 'scripts/interactive-setup.sh'
                interactive.write_text('''#!/bin/bash
case "$1" in
--select-only)
  printf '%s' '{"schemaVersion":1,"components":[{"key":"bench_pyBench","action":"install"}]}' > "$2" ;;
--dependencies-plan) exit 0 ;;
--apply-plan)
  test -f "$HOME/family-built" || exit 23
  touch "$HOME/bench-set-up" ;;
esac
''')
                interactive.chmod(0o755)
                for category in ('devBenches', 'sysBenches', 'bioBenches'):
                    path = repo / category
                    path.mkdir()
                    script = path / 'setup.sh'
                    script.write_text(f'#!/bin/bash\ntouch "$HOME/{category}-called"\n'
                                      + (f'touch "$HOME/family-built"\nexit {code}\n' if category == 'devBenches' else 'exit 24\n'))
                    script.chmod(0o755)
                env = dict(self.env, HOME=str(home), PATH=str(binary) + ':' + self.env['PATH'],
                           WORKBENCHES_TEST_NATIVE_TOOLS='1', WORKBENCHES_SKIP_ESTATE_COMMANDS='1', WORKBENCHES_SKIP_WORKSPACE_REPO='1',
                           WORKBENCHES_SKIP_PROJECT_COMMAND='1')
                result = subprocess.run(['bash', str(repo / 'setup.sh')], env=env,
                                        capture_output=True, text=True, timeout=15)
                self.assertEqual(result.returncode, 0 if code == 0 else 1, result.stdout + result.stderr)
                self.assertEqual((home / 'bench-set-up').exists(), code == 0)
                self.assertTrue((home / 'devBenches-called').exists())
                self.assertFalse((home / 'sysBenches-called').exists())
                self.assertFalse((home / 'bioBenches-called').exists())

    def test_first_bench_setup_failure_is_not_counted_as_success(self):
        repo = self.home / 'workBenches'
        repo.mkdir()
        for name in ('scripts', 'config'):
            shutil.copytree(ROOT / name, repo / name, ignore=shutil.ignore_patterns('__pycache__'))
        shutil.copy(ROOT / 'bootstrap.sh', repo / 'bootstrap.sh')
        command = f'''source "{repo}/scripts/interactive-setup.sh"
init_components
component_checked[bench_pyBench]=true
component_status[bench_pyBench]=not_installed
component_action[bench_pyBench]=install
refresh_component_statuses() {{ :; }}
workbenches_clone() {{ mkdir -p "$2"; printf '#!/bin/bash\\nexit 13\\n' > "$2/setup.sh"; }}
process_selections'''
        result = subprocess.run(['bash', '-c', command], input='\n', env=self.env,
                                capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn('Setup failed', result.stdout)
        self.assertNotIn('completed successfully', result.stdout)

    def test_shell_setup_has_one_owner_for_changing_the_login_shell(self):
        binary = self.home / 'bin'
        binary.mkdir()
        tools = {
            'curl': '''#!/bin/bash
cat <<'INSTALLER'
test "$CHSH" = no && test "$RUNZSH" = no && test "$KEEP_ZSHRC" = yes || exit 41
mkdir -p "$HOME/.oh-my-zsh/custom"
INSTALLER
''',
            'git': '#!/bin/bash\nmkdir -p "${@: -1}"\n',
            'sudo': '#!/bin/bash\necho own-shell-change >> "$HOME/shell-actions"\n',
            'zsh': '#!/bin/bash\necho fixture-zsh\n',
        }
        for name, content in tools.items():
            path = binary / name
            path.write_text(content)
            path.chmod(0o755)
        env = dict(self.env, PATH=str(binary) + ':' + self.env['PATH'])
        for name in ('ZSH', 'ZSH_CUSTOM'):
            env.pop(name, None)
        result = subprocess.run(['bash', str(ROOT / 'scripts/setup-shell.sh')], env=env,
                                capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.home / 'shell-actions').read_text().strip(), 'own-shell-change')

    def prepare_bench_home(self):
        return subprocess.run([sys.executable, str(ROOT / 'scripts/setup-bench-home.py')],
                              env=self.env, capture_output=True, text=True)

    def test_bench_mount_settings_are_created_privately_without_auth_files(self):
        result = self.prepare_bench_home()
        self.assertEqual(result.returncode, 0, result.stderr)
        settings = self.home / '.claude.json'
        self.assertEqual(json.loads(settings.read_text()), {})
        self.assertEqual(settings.stat().st_mode & 0o777, 0o600)
        for name in ('.claude', '.claude-profiles', '.chatgpt-profiles', '.config/gh'):
            self.assertEqual((self.home / name).stat().st_mode & 0o777, 0o700)
        self.assertFalse((self.home / '.claude/.credentials.json').exists())
        self.assertFalse((self.home / '.codex/auth.json').exists())

    def test_bench_preparation_preserves_existing_settings_and_recovered_credentials(self):
        settings = self.home / '.claude.json'
        settings.write_text('{"testSetting": true}')
        self.target.parent.mkdir(parents=True)
        self.target.write_bytes(self.payload)
        before = [(p.read_bytes(), p.stat().st_mtime_ns) for p in (settings, self.target)]
        self.assertEqual(self.prepare_bench_home().returncode, 0)
        self.assertEqual(self.prepare_bench_home().returncode, 0)
        self.assertEqual([(p.read_bytes(), p.stat().st_mtime_ns) for p in (settings, self.target)], before)

    def test_bench_preparation_refuses_wrong_types_before_creating_sources(self):
        (self.home / '.claude.json').mkdir()
        result = self.prepare_bench_home()
        self.assertEqual(result.returncode, 1)
        self.assertIn('Expected a settings file', result.stderr)
        self.assertFalse((self.home / '.ssh').exists())

    def test_bench_preparation_preserves_valid_settings_links_and_refuses_broken_links(self):
        source = self.home / 'settings.json'
        source.write_text('{"testSetting": true}')
        settings = self.home / '.claude.json'
        settings.symlink_to(source)
        self.assertEqual(self.prepare_bench_home().returncode, 0)
        self.assertTrue(settings.is_symlink())
        self.assertEqual(source.read_text(), '{"testSetting": true}')
        settings.unlink()
        source.unlink()
        settings.symlink_to(source)
        self.assertEqual(self.prepare_bench_home().returncode, 1)
        self.assertFalse(source.exists())


if __name__ == '__main__':
    unittest.main()
