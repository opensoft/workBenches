#!/usr/bin/env python3
"""Profiles onboarding and isolation checks; no real sign-ins or host changes."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import re
import pty
import select
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import setup_profiles as profiles

spec = importlib.util.spec_from_file_location('profile_setup', ROOT / 'scripts/setup-profiles.py')
ui = importlib.util.module_from_spec(spec); spec.loader.exec_module(ui)


class ProfilesTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.root = self.directory / 'workbenches'
        self.patcher = patch.multiple(profiles, ROOT=self.root, STORE=self.root / 'profiles.json')
        self.patcher.start(); self.addCleanup(self.patcher.stop)

    def test_wizard_personal_then_multiple_companies_and_private_storage(self):
        data = profiles.load()
        with patch.object(ui, 'ask', side_effect=['me@example.org', 'First Company', 'me@first.org', 'Second Company', 'me@second.org']), patch.object(ui, 'confirm', side_effect=[False, True, True, False]), patch.object(ui, 'edit'):
            ui.wizard(data)
        saved = profiles.load()
        self.assertEqual(saved['personal']['email'], 'me@example.org')
        self.assertEqual(len(saved['companies']), 2)
        self.assertNotEqual(*[p['id'] for p in saved['companies']])
        self.assertEqual(profiles.STORE.stat().st_mode & 0o777, 0o600)
        self.assertFalse((self.root / 'account-session.json').exists())

    def test_connected_email_requires_current_bound_verified_private_session(self):
        self.root.mkdir()
        config = {'issuer': 'https://identity.example/realm', 'clientId': 'cli'}
        (self.root / 'account-provider.json').write_text(json.dumps(config))
        session = dict(config, subject='user-id', email='work@example.org', emailVerified=True,
                       expiresAt=time.time() + 60, accessToken='fixture-secret')
        path = self.root / 'account-session.json'
        for changes, expected in (
            ({}, 'work@example.org'), ({'emailVerified': False}, ''),
            ({'emailVerified': 'true'}, ''), ({'expiresAt': 0}, ''),
            ({'issuer': 'https://other.example'}, ''), ({'clientId': 'other'}, ''),
            ({'email': 'invalid'}, ''),
        ):
            with self.subTest(changes=changes):
                path.write_text(json.dumps(session | changes)); path.chmod(0o600)
                self.assertEqual(profiles.connected_email(), expected)
        path.chmod(0o644)
        self.assertEqual(profiles.connected_email(), '')
        path.unlink(); path.symlink_to(self.directory / 'elsewhere')
        self.assertEqual(profiles.connected_email(), '')

    def test_company_login_email_update_requires_confirmation_and_preserves_personal(self):
        for consent in (True, False):
            data = {'version': 1, 'personal': {'id': 'personal', 'name': 'Personal',
                    'email': 'personal@example.org', 'github': None}, 'companies': []}
            company = profiles.add_company(data, 'Company', 'entered@example.org')
            with patch.object(ui, 'ask', side_effect=['c', 'b']), patch.object(ui, 'account', return_value=0), \
                    patch.object(profiles, 'connected_email', return_value='signedin@example.org'), \
                    patch.object(ui, 'confirm', return_value=consent):
                ui.edit(company, data)
            self.assertEqual(company['email'], 'signedin@example.org' if consent else 'entered@example.org')
            self.assertEqual(data['personal']['email'], 'personal@example.org')

    def test_cancel_keeps_saved_personal_and_no_partial_company(self):
        data = profiles.load()
        with patch.object(ui, 'ask', side_effect=['me@example.org', 'Company', SystemExit(130)]), patch.object(ui, 'confirm', side_effect=[False, True]):
            with self.assertRaises(SystemExit): ui.wizard(data)
        self.assertEqual(profiles.load()['personal']['email'], 'me@example.org')
        self.assertEqual(profiles.load()['companies'], [])

    def test_rejects_controls_duplicate_scopes_and_reserved_names(self):
        data = profiles.load()
        profiles.add_company(data, 'First Company', 'me@first.org')
        for name in ('First-Company', 'Personal', 'Bad\x1b[2J', '!!!'):
            with self.assertRaises(ValueError): profiles.add_company(data, name, 'me@example.org')
        with self.assertRaises(ValueError): profiles.email('not an email')

    def test_symlink_and_unknown_version_are_not_overwritten(self):
        self.root.mkdir(); target = self.directory / 'existing'; target.write_text('preserve')
        profiles.STORE.symlink_to(target)
        with self.assertRaises(ValueError): profiles.save(profiles.load())
        self.assertEqual(target.read_text(), 'preserve')
        profiles.STORE.unlink(); profiles.STORE.write_text('{"version":99,"companies":[]}')
        with self.assertRaises(ValueError): profiles.load()

    def test_company_sessions_are_separate_and_ignore_legacy_overrides(self):
        data = profiles.load()
        first = profiles.add_company(data, 'First', 'me@first.org')
        second = profiles.add_company(data, 'Second', 'me@second.org')
        legacy = self.root / 'account-session.json'; self.root.mkdir(); legacy.write_text('preserve')
        with patch.dict(os.environ, WORKBENCHES_ACCOUNT_ISSUER='https://legacy.example/realm', WORKBENCHES_ACCOUNT_CLIENT_ID='legacy'), patch.object(ui.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0)) as run:
            ui.account(first, ['--logout']); ui.account(second, ['--status'])
        roots = [call.kwargs['env']['WORKBENCHES_ACCOUNT_ROOT'] for call in run.call_args_list]
        self.assertNotEqual(*roots)
        self.assertTrue(all('WORKBENCHES_ACCOUNT_ISSUER' not in call.kwargs['env'] for call in run.call_args_list))
        self.assertEqual(legacy.read_text(), 'preserve')

    def test_github_identity_is_verified_and_only_metadata_saved(self):
        data = profiles.load(); profile = profiles.add_company(data, 'First', 'me@first.org')
        response = subprocess.CompletedProcess([], 0, json.dumps({'login': 'example-user', 'id': 123, 'unused': 'not-stored'}))
        import profile_github
        verified = {'login': 'example-user', 'id': 123, 'state': 'Connected', 'authSource': 'native'}
        with patch.object(profile_github, 'select_account', return_value=verified), patch.object(ui, 'confirm', return_value=True):
            ui.connect_github(profile, data)
        saved = profiles.load()
        self.assertEqual(saved['companies'][0]['github']['id'], 123)
        self.assertEqual(len(saved['githubAccounts']), 1)
        self.assertNotIn('unused', profiles.STORE.read_text())

    def test_enrollment_import_is_confirmed_and_scoped(self):
        data = profiles.load(); profile = profiles.add_company(data, 'First', 'me@first.org')
        source = self.directory / 'enrollment.json'
        source.write_text(json.dumps({'issuer': 'https://identity.example/realms/company', 'clientId': 'workbenches'}))
        with patch.object(ui, 'ask', return_value=str(source)), patch.object(ui, 'confirm', return_value=True):
            ui.enrollment(profile)
        config = profiles.account_root(profile) / 'account-provider.json'
        self.assertEqual(json.loads(config.read_text())['clientId'], 'workbenches')
        self.assertEqual(config.stat().st_mode & 0o777, 0o600)
        source.write_text(json.dumps({'issuer': 'http://insecure.example', 'clientId': 'test'}))
        with patch.object(ui, 'ask', return_value=str(source)), self.assertRaises(ValueError): ui.enrollment(profile)

    def test_tui_profile_navigation_preserves_component_selections(self):
        command = f'''source "{ROOT}/scripts/interactive-setup.sh"
init_components
CURRENT_SECTION=1; current_selection=2
component_checked[codex_cli]=true; component_action[codex_cli]=install
handle_input
[[ "$CURRENT_SECTION" == 4 && "$current_selection" == 0 ]] || exit 20
activate_profile() {{ echo OPENED; }}
handle_input
handle_input
[[ "$CURRENT_SECTION" == 1 && "$current_selection" == 2 ]] || exit 21
[[ "${{component_checked[codex_cli]}}" == true && "${{component_action[codex_cli]}}" == install ]] || exit 22
'''
        result = subprocess.run(['bash', '-c', command], input='G G', text=True, capture_output=True,
                                env=dict(os.environ, HOME=str(self.directory), XDG_CONFIG_HOME=str(self.directory)), timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('OPENED', result.stdout)

    def test_cli_onboarding_round_trip_without_credentials(self):
        env = dict(os.environ, HOME=str(self.directory), XDG_CONFIG_HOME=str(self.directory))
        result = subprocess.run([sys.executable, str(ROOT / 'scripts/setup-profiles.py')],
                                input='me@example.org\nn\ny\nExample Company\nme@company.org\nb\nn\nb\n',
                                text=True, capture_output=True, env=env, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        saved = json.loads((self.root / 'profiles.json').read_text())
        self.assertEqual(saved['companies'][0]['name'], 'Example Company')
        self.assertFalse((self.root / 'account-session.json').exists())

    def test_company_sync_menu_is_visible_without_enabling_or_reading_credentials(self):
        env = dict(os.environ, HOME=str(self.directory), XDG_CONFIG_HOME=str(self.directory))
        # Nested interactive helpers share a real terminal, not a prefetched stdin pipe.
        data = profiles.empty()
        ui.add_personal(data, 'Main', 'me@example.org')
        company = profiles.add_company(data, 'Example Company', 'me@company.org')
        profiles.save(data)
        # Dashboard -> company -> existing sync helper -> back to dashboard.
        steps = [('PROFILES · Personal and companies', '\x1b[B\x1b[B\r'),
            ('C Sign in', 'y'), ('Action [b]:', 'b\n'),
            ('C Sign in', 'b'), ('PROFILES · Personal and companies', 'b')]
        master, slave = pty.openpty()
        process = subprocess.Popen([sys.executable, str(ROOT / 'scripts/setup-profiles.py')],
            stdin=slave, stdout=slave, stderr=slave, env=env)
        os.close(slave); transcript = ''; cursor = 0; stage = 0
        try:
            deadline = time.monotonic() + 15
            while process.poll() is None and time.monotonic() < deadline:
                ready, _, _ = select.select([master], [], [], .1)
                if ready:
                    try: transcript += os.read(master, 65536).decode(errors='replace')
                    except OSError: break
                if stage < len(steps) and steps[stage][0] in transcript[cursor:]:
                    cursor = len(transcript); os.write(master, steps[stage][1].encode()); stage += 1
            self.assertEqual(process.wait(timeout=2), 0, transcript)
        finally:
            if process.poll() is None: process.kill(); process.wait()
            os.close(master)
        self.assertEqual(stage, len(steps))
        self.assertIn('Company credential sync — Example Company', transcript)
        self.assertIn('Synchronization: Disabled', transcript)
        self.assertFalse(list(self.root.rglob('credential-sync.json')))
        self.assertFalse((self.root / 'company-sync-enabled').exists())

    def test_adding_company_ai_profiles_preserves_personal_and_other_companies(self):
        self.root.mkdir()
        existing = {'version': 1, 'families': ['personal', 'other'], 'profiles': [
            {'name': 'personal-1', 'email': 'me@example.org', 'family': 'personal', 'profilePath': 'personal/personal-1', 'aliases': []},
            {'name': 'work-other', 'email': 'me@other.org', 'family': 'other', 'profilePath': 'other/xfactor/work-other', 'aliases': []}]}
        destination = self.root / 'openai-profiles.json'; destination.write_text(json.dumps(existing))
        answers = self.directory / 'answers.json'
        answers.write_text(json.dumps({'consent': True, 'githubUser': '', 'companies': [
            {'name': 'New Company', 'email': 'me@new.org', 'providers': ['openai'], 'registry': 'manual'}],
            'personal': {'accounts': [], 'registry': 'manual'}}))
        env = dict(os.environ, HOME=str(self.directory), XDG_CONFIG_HOME=str(self.directory), WORKBENCHES_IDENTITY_SCOPE='organization')
        for key in ('WORKBENCHES_SELECTED_PROVIDERS', 'WORKBENCHES_PROFILE_PROVIDERS'):
            env.pop(key, None)
        command = [sys.executable, str(ROOT / 'scripts/onboard-ai-profiles.py'), '--answers', str(answers), '--output-dir', str(self.root)]
        for _ in range(2):
            result = subprocess.run(command, env=env, capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        saved = json.loads(destination.read_text())
        self.assertEqual(saved['profiles'][:2], existing['profiles'])
        self.assertEqual([p['name'] for p in saved['profiles']], ['personal-1', 'work-other', 'work-new-company'])

    def test_profiles_panel_fits_narrow_and_standard_widths_without_discovery(self):
        for width in (36, 60, 80, 100):
            command = f'''source "{ROOT}/scripts/interactive-setup.sh"
init_components
CURRENT_SECTION=4; setup_ui_width={width}
profiles_summary=$'Personal: me@example.org\\nGitHub: @example-user (verified when linked)\\nCompany profiles: 2\\nCompany A: me@company-a.example.org'
python3() {{ echo UNEXPECTED_DISCOVERY; return 99; }}
draw_profiles; draw_setup_footer
'''
            result = subprocess.run(['bash', '-c', command], capture_output=True, text=True,
                                    env=dict(os.environ, HOME=str(self.directory)), timeout=15)
            self.assertEqual(result.returncode, 0, result.stderr)
            plain = re.sub(r'\x1b\[[0-9;?]*[A-Za-z]', '', result.stdout)
            self.assertNotIn('UNEXPECTED_DISCOVERY', plain)
            self.assertTrue(all(len(line) <= width for line in plain.splitlines()), plain)

    def test_profile_action_uses_required_readiness_not_optional_inventory_completion(self):
        command = f'''source "{ROOT}/scripts/interactive-setup.sh"
init_components
component_status[wsl]=up; component_status[docker]=up; component_status[setup_tools]=up
status_checks_running=true; CURRENT_SECTION=4; current_selection=0
component_checked[codex_cli]=true; component_action[codex_cli]=install
stop_status_loader() {{ status_checks_running=false; }}
refresh_component_statuses() {{ :; }}
python3() {{ if [[ "$2" == --summary ]]; then echo Summary; else echo OPENED; fi; }}
activate_profile
[[ "${{component_checked[codex_cli]}}" == true ]] || exit 23
'''
        result = subprocess.run(['bash', '-c', command], capture_output=True, text=True,
                                env=dict(os.environ, HOME=str(self.directory)), timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('OPENED', result.stdout)


if __name__ == '__main__':
    unittest.main()
