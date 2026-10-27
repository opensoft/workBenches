#!/usr/bin/env python3
"""Disposable scoped cloud imports, private OAuth setup and cancellation."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import cloud_profiles as cloud

spec = importlib.util.spec_from_file_location('login_helper', ROOT / 'tools-container/rclone_login.py')
login = importlib.util.module_from_spec(spec); spec.loader.exec_module(login)
spec = importlib.util.spec_from_file_location('profile_manager', ROOT / 'scripts/setup-profiles.py')
manager = importlib.util.module_from_spec(spec); spec.loader.exec_module(manager)


class CloudTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(); self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        context = patch.object(cloud.identities, 'ROOT', self.root / 'config')
        context.start(); self.addCleanup(context.stop)
        context = patch.dict(os.environ, {key: str(self.root / key) for key in
                             ('CLAUDE_PROFILES_HOME', 'CODEX_PROFILES_HOME', 'GEMINI_PROFILES_HOME', 'GROK_PROFILES_HOME', 'GLM_PROFILES_HOME')})
        context.start(); self.addCleanup(context.stop)
        self.scope = {'id': 'personal', 'name': 'Personal'}
        self.company = {'id': 'company-' + 'a' * 32, 'name': 'Company'}
        self.connection = {'id': 'b' * 32, 'backend': 'drive', 'label': 'Personal Drive'}
        self.row = {'name': 'account', 'email': 'user@example.com', 'family': 'untrusted', 'aliases': []}
        self.raw = json.dumps({'version': 1, 'profiles': [self.row]}).encode()
        self.output = io.StringIO()
        context = contextlib.redirect_stdout(self.output); context.__enter__()
        self.addCleanup(context.__exit__, None, None, None)

    def test_scope_binding_replaces_remote_ownership_and_host_paths(self):
        raw = json.dumps({'version': 1, 'profiles': [dict(self.row, profilePath='../../foreign', workspace='other')]}).encode()
        _, result, _ = cloud.prepare(raw, 'claude', self.company)
        row = result['profiles'][0]
        self.assertEqual(row['family'], self.company['id'])
        self.assertEqual(row['profilePath'], self.company['id'] + '/account')
        self.assertEqual(row['workspace'], 'Company')

    def test_secrets_unknown_fields_unsafe_names_and_aliases_rejected(self):
        for change in ({'token': 'private-canary'}, {'name': '../escape'}, {'aliases': ['../escape']},
                       {'authentication': {'type': 'oauth', 'access_token': 'private-canary'}},
                       {'accountId': {'token': 'private-canary'}}, {'email': 'not-an-email'}):
            with self.subTest(change=change), self.assertRaises((ValueError, TypeError)):
                cloud.prepare(json.dumps({'version': 1, 'profiles': [dict(self.row, **change)]}).encode(), 'claude', self.scope)
        self.assertNotIn('private-canary', self.output.getvalue())

    def test_empty_wrong_version_oversize_and_duplicate_manifest_refused(self):
        for data in ({'version': 2, 'profiles': [self.row]}, {'version': 1, 'profiles': []},
                     {'version': 1, 'profiles': [self.row, self.row]}, {'version': 1, 'profiles': [self.row], 'token': 'x'}):
            with self.subTest(data=data), self.assertRaises(ValueError):
                cloud.prepare(json.dumps(data).encode(), 'claude', self.scope)
        with self.assertRaises(ValueError): cloud.prepare(b'x' * (cloud.LIMIT + 1), 'claude', self.scope)

    def test_other_scope_collision_renames_new_profile_without_overwriting(self):
        existing = dict(self.row, family=self.company['id'], profilePath=self.company['id'] + '/account')
        cloud.private_json(cloud.identities.ROOT / 'claude-profiles.json', {'version': 1, 'profiles': [existing]})
        _, result, _ = cloud.prepare(self.raw, 'claude', self.scope)
        self.assertEqual(result['profiles'][0], existing)
        self.assertEqual(result['profiles'][1]['name'], 'account-2')
        self.assertEqual(result['profiles'][1]['profilePath'], 'personal/account-2')

    def test_rerun_keeps_existing_profile_and_private_paths(self):
        path, first, _ = cloud.prepare(self.raw, 'claude', self.scope)
        cloud.private_json(path, first)
        _, second, _ = cloud.prepare(self.raw, 'claude', self.scope)
        self.assertEqual(first, second)
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def test_cross_profile_alias_collision_refused(self):
        one = dict(self.row, aliases=['shared'])
        two = dict(self.row, name='other', aliases=['shared'])
        with self.assertRaises(ValueError):
            cloud.prepare(json.dumps({'version': 1, 'profiles': [one, two]}).encode(), 'claude', self.scope)

    def test_local_import_decline_has_no_writes_or_launcher_side_effect(self):
        file = self.root / 'manifest.json'; file.write_bytes(self.raw)
        with patch.object(cloud, 'prompt', return_value='n'), patch.object(cloud.subprocess, 'run') as run:
            self.assertFalse(cloud.import_source(self.scope, {'kind': 'local', 'provider': 'claude', 'path': str(file)}))
        run.assert_not_called(); self.assertFalse(cloud.identities.ROOT.exists())

    def test_local_import_remembers_source_and_applies_only_selected_provider(self):
        file = self.root / 'manifest.json'; file.write_bytes(self.raw)
        with patch.object(cloud, 'prompt', return_value='yes'), patch.object(cloud.subprocess, 'run', return_value=Mock(returncode=0)) as run:
            self.assertTrue(cloud.import_source(self.company, {'kind': 'local', 'provider': 'claude', 'path': str(file)}))
        self.assertTrue(run.call_args.args[0][1].endswith('setup-claude-profiles.sh'))
        source = cloud.load(self.company)['sources'][0]
        self.assertEqual(source['status'], 'launchers configured')
        self.assertNotIn('sources', cloud.load(self.scope)['sources'])
        self.assertEqual(cloud.load(self.scope)['sources'], [])

    def test_failed_launcher_retains_import_with_truthful_retry_state(self):
        file = self.root / 'manifest.json'; file.write_bytes(self.raw)
        with patch.object(cloud, 'prompt', return_value='yes'), patch.object(cloud.subprocess, 'run', return_value=Mock(returncode=1)):
            with self.assertRaisesRegex(ValueError, 'Metadata imported'):
                cloud.import_source(self.scope, {'kind': 'local', 'provider': 'claude', 'path': str(file)})
        self.assertEqual(cloud.load(self.scope)['sources'][0]['status'], 'metadata imported')

    def test_symlink_targets_and_invalid_scope_cannot_escape_store(self):
        self.root.joinpath('config').symlink_to(self.root, target_is_directory=True)
        with self.assertRaises(ValueError): cloud.private_json(cloud.identities.ROOT / 'claude-profiles.json', {})
        with self.assertRaises(ValueError): cloud.scope_root({'id': '../../elsewhere'})

    def test_remote_path_never_accepts_url_backend_override_or_traversal(self):
        for path in ('../file', '/file', 'a//b', 'a/./b', 'remote:file', ':local:', 'https://drive.google.com/x', 'a\\b', 'x\x1b'):
            with self.subTest(path=path), self.assertRaises(ValueError): cloud.remote_path(path)
        self.assertEqual(cloud.remote_path('profiles/my file.json'), 'profiles/my file.json')

    def test_scoped_rclone_only_reads_and_bounds_payload(self):
        directory = cloud.connection_dir(self.scope, self.connection); directory.mkdir(parents=True)
        (directory / 'rclone.conf').write_text('[cloud]\ntype=drive\n'); (directory / 'rclone.conf').chmod(0o600)
        with patch.object(cloud, 'bounded', return_value=self.raw) as run:
            self.assertEqual(cloud.rclone(self.scope, self.connection, 'read', 'profiles/file.json'), self.raw)
        args = run.call_args.args[0]
        self.assertEqual(args[-4:], ['cat', 'cloud:profiles/file.json', '--head', str(cloud.LIMIT + 1)])
        self.assertIn(str(directory / 'rclone.conf'), args)
        with self.assertRaises(ValueError): cloud.rclone(self.scope, self.connection, 'sync', 'file')

    def test_inherited_rclone_tokens_endpoints_and_config_do_not_override(self):
        with patch.dict(os.environ, {'RCLONE_CONFIG': '/foreign', 'RCLONE_DRIVE_TOKEN': 'private-canary', 'RCLONE_DRIVE_AUTH_URL': 'https://bad.example'}):
            self.assertFalse(any(k.startswith('RCLONE_') for k in cloud.clean_environment()))

    def test_command_errors_and_oversize_output_never_leak_payload(self):
        with self.assertRaises(ValueError):
            cloud.bounded([sys.executable, '-c', 'import sys; print("private-canary", file=sys.stderr); sys.exit(1)'])
        with self.assertRaises(ValueError):
            cloud.bounded([sys.executable, '-c', 'print("x"*10000)'], limit=100)
        self.assertNotIn('private-canary', self.output.getvalue())

    def test_browser_question_protocol_refuses_password_token_and_shared_app(self):
        for name in ('config_token', 'client_secret', 'config_shared_client_id', 'arbitrary'):
            with self.subTest(name=name), self.assertRaises(ValueError): login.reply({'Name': name})
        self.assertEqual(login.reply({'Name': 'config_is_local'}), 'true')
        with patch('builtins.input', return_value='1'):
            self.assertEqual(login.reply({'Name': 'config_driveid', 'Examples': [{'Value': 'drive-1', 'Help': 'My drive'}]}), 'drive-1')

    def test_missing_google_app_is_actionable_without_starting_browser(self):
        with patch.object(cloud.subprocess, 'run') as run:
            with self.assertRaisesRegex(ValueError, 'OAuth app'): cloud.connect(self.scope, 'drive', 'My Drive')
        run.assert_not_called()

    def test_cancelled_docker_login_keeps_prior_connections_and_removes_pending_store(self):
        cloud.save(self.scope, {'version': 1, 'connections': [self.connection], 'sources': []})
        with patch.dict(os.environ, {'WORKBENCHES_HOST_RPC': str(self.root)}), \
                patch.object(cloud, 'bounded', return_value=('sha256:' + 'a'*64).encode()), \
                patch.object(cloud.subprocess, 'run', return_value=Mock(returncode=130)) as run:
            with self.assertRaises(SystemExit) as raised: cloud.connect(self.scope, 'onedrive', 'Company Drive')
        self.assertEqual(raised.exception.code, 130)
        args = run.call_args_list[0].args[0]
        self.assertIn('127.0.0.1:53682:53682', args)
        self.assertNotIn('--network=host', args)
        self.assertEqual(cloud.load(self.scope)['connections'], [self.connection])
        self.assertEqual([p.name for p in cloud.scope_root(self.scope).iterdir()], ['sources.json'])

    def test_successful_browser_connection_is_private_and_reusable(self):
        def docker(args, **_):
            if args[1] == 'run':
                directory = Path(args[-2])
                config = directory / 'rclone.conf'; config.write_text('[cloud]\ntype=onedrive\ntoken=private-canary\n'); config.chmod(0o600)
            return Mock(returncode=0)
        with patch.dict(os.environ, {'WORKBENCHES_HOST_RPC': str(self.root)}), \
                patch.object(cloud, 'bounded', return_value=('sha256:' + 'a'*64).encode()), \
                patch.object(cloud.subprocess, 'run', side_effect=docker):
            connection = cloud.connect(self.company, 'onedrive', 'Work Drive')
        self.assertEqual(cloud.load(self.company)['connections'], [connection])
        self.assertNotIn('private-canary', (cloud.scope_root(self.company) / 'sources.json').read_text())
        self.assertEqual(cloud.connection_dir(self.company, connection).stat().st_mode & 0o777, 0o700)

    def test_profiles_identity_action_uses_selected_scope(self):
        identity = {'id': 'main', 'name': 'Main', 'email': 'user@example.com', 'githubIds': [], 'defaultGithubId': None}
        scope = dict(self.scope, identities=[identity], defaultIdentityId='main')
        with patch('profile_tui.choose', side_effect=[('f', None), ('b', None)]), patch.object(manager, 'ai_accounts') as menu:
            manager.identity_menu(scope, identity, {'githubAccounts': []})
        menu.assert_called_once_with(scope, identity, {'githubAccounts': []})

    def test_login_helper_uses_private_config_not_secret_argv_and_finishes_protocol(self):
        root = self.root / 'login'; root.mkdir()
        (root / 'app.json').write_text(json.dumps({'client_id': 'registered-app', 'client_secret': 'private-canary'}))
        calls = []
        def command(argv, env, directory):
            calls.append(argv)
            self.assertNotIn('private-canary', str(argv))
            self.assertEqual(argv[:4], ['rclone', 'config', 'update', 'cloud'])
            with (directory / 'rclone.conf').open('a') as stream: stream.write('token = fixture-authorized-token\n')
            return {'State': '', 'Error': ''}
        with patch.object(login, 'private_command', side_effect=command), \
                patch.object(login.subprocess, 'run', return_value=Mock(returncode=0, stdout='obscured-app-secret\n')) as obscure:
            login.configure(root, 'drive')
        self.assertEqual(obscure.call_args.kwargs['input'], 'private-canary\n')
        self.assertNotIn('private-canary', (root / 'rclone.conf').read_text())
        self.assertIn('scope = drive.readonly', (root / 'rclone.conf').read_text())
        self.assertEqual((root / 'rclone.conf').stat().st_mode & 0o777, 0o600)
        self.assertEqual(len(calls), 1)

    def test_alias_matching_existing_identity_does_not_loop_or_duplicate(self):
        existing = dict(self.row, name='canonical', family='personal', aliases=['account'], profilePath='personal/canonical')
        cloud.private_json(cloud.identities.ROOT / 'claude-profiles.json', {'version': 1, 'profiles': [existing]})
        _, result, preview = cloud.prepare(self.raw, 'claude', self.scope)
        self.assertEqual(result['profiles'], [existing])
        self.assertEqual(preview[0]['name'], 'canonical')

    def test_onedrive_configuration_keeps_explicit_read_only_scopes(self):
        root = self.root / 'login'; root.mkdir()
        def finish(argv, env, directory):
            config = directory / 'rclone.conf'
            data = config.read_text()
            self.assertIn('access_scopes = Files.Read offline_access', data)
            self.assertNotIn('disable_site_permission = true', data)
            self.assertNotIn('Files.ReadWrite', data)
            with config.open('a') as stream: stream.write('token = fixture-authorized-token\n')
            return {'State': '', 'Error': ''}
        with patch.object(login, 'private_command', side_effect=finish): login.configure(root, 'onedrive')
        self.assertEqual(login.reply({'Name': 'config_type'}), 'onedrive')
        with patch('builtins.input', return_value=''):
            self.assertEqual(login.reply({'Name': 'config_change_team_drive', 'DefaultStr': 'false'}), 'false')

    def test_explicit_path_skips_folder_listing_and_retains_selected_connection(self):
        state = {'version': 1, 'connections': [self.connection], 'sources': []}
        with patch.object(cloud, 'load', return_value=state), \
                patch.object(cloud, 'selected', side_effect=[('p', ('browse', self.connection)), ('enter', 'claude'), None]), \
                patch.object(cloud, 'prompt', return_value='profiles/manifest.json'), \
                patch.object(cloud, 'browse') as browse, patch.object(cloud, 'import_source') as imported:
            cloud.menu(self.scope)
        browse.assert_not_called()
        self.assertEqual(imported.call_args.args[2], self.connection)
        self.assertEqual(imported.call_args.args[1]['path'], 'profiles/manifest.json')

    def test_real_launcher_materialization_preserves_default_credentials(self):
        home = self.root / 'home'; home.mkdir()
        (home / '.claude').mkdir(); (home / '.codex').mkdir()
        (home / '.claude/.credentials.json').write_text('private-default-canary')
        (home / '.codex/auth.json').write_text('private-default-canary')
        file = self.root / 'manifest.json'; file.write_bytes(self.raw)
        env = {'HOME': str(home), 'XDG_CONFIG_HOME': str(home / '.config'),
               'CLAUDE_PROFILES_HOME': str(home / '.claude-profiles'),
               'CODEX_PROFILES_HOME': str(home / '.chatgpt-profiles')}
        for provider, base, auth in (('claude', '.claude-profiles', '.credentials.json'), ('openai', '.chatgpt-profiles', 'auth.json')):
            with self.subTest(provider=provider), patch.dict(os.environ, env), patch.object(cloud, 'prompt', return_value='y'):
                self.assertTrue(cloud.import_source(self.scope, {'kind': 'local', 'provider': provider, 'path': str(file)}))
                profile = home / base / 'profiles/personal/account'
                self.assertTrue((profile / '.profile.json').is_file())
                self.assertFalse((profile / auth).exists())
        self.assertEqual((home / '.claude/.credentials.json').read_text(), 'private-default-canary')
        self.assertEqual((home / '.codex/auth.json').read_text(), 'private-default-canary')
        self.assertNotIn('private-default-canary', self.output.getvalue())

    def test_existing_renamed_profile_home_is_reserved_for_both_providers(self):
        for provider in ('claude', 'openai'):
            for path in ('personal/account', 'account'):
                with self.subTest(provider=provider, path=path):
                    existing = dict(self.row, name='renamed-account', email='old@example.com', family='personal', profilePath=path)
                    cloud.private_json(cloud.identities.ROOT / cloud.composer.PROVIDERS[provider], {'version': 1, 'profiles': [existing]})
                    _, result, preview = cloud.prepare(self.raw, provider, self.scope)
                    self.assertEqual(result['profiles'][0], existing)
                    self.assertEqual(preview[0]['name'], 'account-2')
                    self.assertEqual(preview[0]['profilePath'], 'personal/account-2')
                    self.assertEqual(len({row['profilePath'] for row in result['profiles']}), 2)

    def test_unlisted_existing_credential_home_is_not_adopted(self):
        for path in ('personal/account', 'account'):
            with self.subTest(path=path):
                profile = cloud.provider_root('claude') / path
                profile.mkdir(parents=True); (profile / '.credentials.json').write_text('private-old-account')
                _, result, preview = cloud.prepare(self.raw, 'claude', self.scope)
                self.assertEqual(preview[0]['profilePath'], 'personal/account-2')
                self.assertEqual((profile / '.credentials.json').read_text(), 'private-old-account')

    def test_profile_family_symlink_cannot_redirect_launcher_writes(self):
        root = cloud.provider_root('claude'); root.mkdir(parents=True)
        foreign = self.root / 'foreign'; foreign.mkdir()
        (root / 'personal').symlink_to(foreign, target_is_directory=True)
        with self.assertRaises(ValueError): cloud.prepare(self.raw, 'claude', self.scope)
        self.assertEqual(list(foreign.iterdir()), [])

    def test_new_name_cannot_be_its_future_family_directory(self):
        raw = json.dumps({'version': 1, 'profiles': [dict(self.row, name='personal')]}).encode()
        _, _, preview = cloud.prepare(raw, 'claude', self.scope)
        self.assertEqual(preview[0]['name'], 'personal-2')
        self.assertEqual(preview[0]['profilePath'], 'personal/personal-2')

    def test_dynamic_command_arguments_remain_literal_without_a_shell(self):
        marker = self.root / 'must-not-exist'
        value = '$(touch ' + str(marker) + '); echo private-canary'
        result = cloud.bounded([sys.executable, '-c', 'import sys; print(sys.argv[1])', value])
        self.assertEqual(result.decode().strip(), value)
        self.assertFalse(marker.exists())

    def test_case_insensitive_launcher_alias_cannot_shadow_a_new_account(self):
        existing = dict(self.row, name='old', aliases=['Account'], email='old@example.com', family='personal', profilePath='personal/old')
        cloud.private_json(cloud.identities.ROOT / 'claude-profiles.json', {'version': 1, 'profiles': [existing]})
        _, result, preview = cloud.prepare(self.raw, 'claude', self.scope)
        self.assertEqual(preview[0]['name'], 'account-2')
        self.assertEqual(result['profiles'][0], existing)
        changed = json.dumps({'version': 1, 'profiles': [dict(self.row, name='different', aliases=['account'])]}).encode()
        _, result, preview = cloud.prepare(changed, 'claude', self.scope)
        self.assertEqual(preview[0]['aliases'], [])
        keys = [v.casefold() for row in result['profiles'] for v in (row['name'], *row.get('aliases', []))]
        self.assertEqual(len(keys), len(set(keys)))

    def test_compact_source_can_be_reimported_after_large_pretty_aggregate_write(self):
        rows = [dict(self.row, name=f'account-{i}', accountId='a' * 350) for i in range(2000)]
        raw = json.dumps({'version': 1, 'profiles': rows}, separators=(',', ':')).encode()
        self.assertLess(len(raw), cloud.LIMIT)
        path, first, _ = cloud.prepare(raw, 'claude', self.scope)
        cloud.private_json(path, first)
        self.assertGreater(path.stat().st_size, cloud.LIMIT)
        _, second, _ = cloud.prepare(raw, 'claude', self.scope)
        self.assertEqual(second, first)

    def test_oversized_aggregate_rejected_before_replacing_saved_manifest(self):
        path = cloud.identities.ROOT / 'claude-profiles.json'
        cloud.private_json(path, {'version': 1, 'profiles': []})
        before = path.read_bytes()
        raw = json.dumps({'version': 1, 'profiles': [dict(self.row, accountId='a' * 512)]}).encode()
        with patch.object(cloud, 'AGGREGATE_LIMIT', 400), self.assertRaisesRegex(ValueError, 'too large'):
            cloud.prepare(raw, 'claude', self.scope)
        self.assertEqual(path.read_bytes(), before)
        with patch.object(cloud, 'AGGREGATE_LIMIT', 10), self.assertRaises(ValueError):
            cloud.private_json(path, {'would': 'overwrite'})
        self.assertEqual(path.read_bytes(), before)

    def test_existing_duplicate_or_escaping_homes_fail_without_writes(self):
        for homes in (('personal/account', 'personal/account'), ('../escape', 'other')):
            with self.subTest(homes=homes):
                rows = [dict(self.row, name=name, profilePath=home, family='personal') for name, home in zip(('one', 'two'), homes)]
                cloud.private_json(cloud.identities.ROOT / 'claude-profiles.json', {'version': 1, 'profiles': rows})
                before = (cloud.identities.ROOT / 'claude-profiles.json').read_bytes()
                with self.assertRaises(ValueError): cloud.prepare(self.raw, 'claude', self.scope)
                self.assertEqual((cloud.identities.ROOT / 'claude-profiles.json').read_bytes(), before)


if __name__ == '__main__': unittest.main()
