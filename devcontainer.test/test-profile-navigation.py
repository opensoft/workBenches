#!/usr/bin/env python3
"""Owner isolation, portable-file boundaries, navigation and conditional exports."""
import base64
import copy
import importlib.util
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
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import setup_profiles as profiles
import profile_navigation as nav
import profile_portability as portable
import profile_sources as sources
import cloud_profiles as cloud
import profile_tui as tui
spec = importlib.util.spec_from_file_location('navigation_entry', ROOT / 'scripts/setup-profiles.py')
entry = importlib.util.module_from_spec(spec); spec.loader.exec_module(entry)


class NavigationTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(); self.addCleanup(temp.cleanup)
        self.home = Path(temp.name); self.config = self.home / 'workbenches'
        changes = patch.dict(os.environ, HOME=str(self.home), XDG_CONFIG_HOME=str(self.home), WORKBENCHES_HOST_RPC='')
        changes.start(); self.addCleanup(changes.stop)
        model = patch.multiple(profiles, ROOT=self.config, STORE=self.config / 'profiles.json')
        model.start(); self.addCleanup(model.stop)
        self.data = profiles.empty()
        self.first = entry.add_personal(self.data, 'Main', 'main@example.org')
        self.second = entry.add_personal(self.data, 'Consulting', 'consult@example.org')
        self.company = profiles.add_company(self.data, 'Example', 'work@example.org')
        profiles.save(self.data)
        self.scope = profiles.ai_scope(self.data['personal'], self.first)
        self.ui = dict(vars(entry))

    def accounts(self, provider='openai'):
        path = self.config / cloud.composer.PROVIDERS[provider]
        rows = [{'name': 'main', 'email': 'main@example.org', 'family': 'personal'},
                {'name': 'consulting', 'email': 'consult@example.org', 'family': profiles.ai_scope(self.data['personal'], self.second)['id']},
                {'name': 'work', 'email': 'work@example.org', 'family': self.company['id']}]
        path.write_text(json.dumps({'version': 1, 'profiles': rows})); path.chmod(0o600)
        return path

    def test_personal_scopes_stay_stable_when_default_changes(self):
        original = profiles.ai_scope(self.data['personal'], self.first)['id']
        other = profiles.ai_scope(self.data['personal'], self.second)['id']
        self.data['personal']['defaultIdentityId'] = self.second['id']; profiles.save(self.data)
        loaded = profiles.load()['personal']
        self.assertEqual(profiles.ai_scope(loaded, loaded['identities'][0])['id'], original)
        self.assertEqual(profiles.ai_scope(loaded, loaded['identities'][1])['id'], other)
        self.assertEqual(original, 'personal'); self.assertNotEqual(original, other)

    def test_kind_list_is_exact_and_about_only_describes_selected_kind(self):
        seen = []
        def pick(title, rows, detail, **kwargs):
            seen.append((title, rows, detail('personal')))
            return 'b', None
        with patch.object(nav, 'choose', side_effect=pick): nav.manage(self.data, self.ui)
        self.assertEqual([r[0] for r in seen[0][1]], ['Personal', 'Company', 'Workstation'])
        self.assertNotIn('AI accounts', str(seen[0][1]))
        self.assertNotIn('work@example.org', ' '.join(seen[0][2]))

    def test_personal_profiles_have_add_last_and_select_opens_editor(self):
        seen = []
        def pick(title, rows, detail, **kwargs):
            seen.append((title, rows, detail(self.second['id'])))
            return ('enter', self.second['id']) if len(seen) == 1 else ('b', None)
        with patch.object(nav, 'choose', side_effect=pick), patch.object(nav, 'editor') as editor:
            nav.profile_list('personal', self.data, self.ui)
        self.assertEqual(seen[0][0], 'Personal Profiles')
        self.assertEqual(seen[0][1][-1][0], '+ Add personal profile')
        self.assertIn('consult@example.org', seen[0][2]); self.assertNotIn('main@example.org', seen[0][2])
        self.assertIs(editor.call_args.args[1], self.second)

    def test_workstation_is_local_and_preserves_legacy_signin(self):
        with patch.object(nav, 'choose', return_value=('b', None)):
            nav.profile_list('workstation', self.data, self.ui)
        row = profiles.load()['workstations'][0]
        self.assertTrue(row['legacyAccount']); self.assertTrue(row['hostname'])
        self.assertNotIn(row, profiles.scopes(self.data))
        self.assertEqual(profiles.account_root(row).parent.name, 'identities')

    def test_account_inventory_filters_both_owner_and_maker(self):
        self.accounts()
        self.assertEqual([r['name'] for r in nav.account_rows(self.scope, 'openai')], ['main'])
        self.assertEqual([r['name'] for r in nav.account_rows(profiles.ai_scope(self.data['personal'], self.second), 'openai')], ['consulting'])
        self.assertEqual(nav.account_rows(self.scope, 'claude'), [])

    def test_model_maker_choice_opens_that_makers_accounts(self):
        with patch.object(nav, 'choose', side_effect=[('enter', 'openai'), ('b', None)]), patch.object(nav, 'maker_accounts') as accounts:
            nav.ai_menu(self.data['personal'], self.second, self.data, self.ui)
        self.assertEqual(accounts.call_args.args[0]['id'], self.second['aiScopeId'])
        self.assertEqual(accounts.call_args.args[-1], 'openai')

    def test_portable_export_excludes_other_owners_ids_paths_and_secrets(self):
        path = self.accounts(); original = path.read_bytes()
        value = json.loads(portable.document(self.scope, self.first, 'personal'))
        self.assertEqual([r['name'] for r in value['aiProfiles']['openai']], ['main'])
        self.assertNotIn('id', value['profile']); self.assertNotIn('family', value['aiProfiles']['openai'][0])
        self.assertNotIn('profilePath', str(value)); self.assertEqual(path.read_bytes(), original)
        value['aiProfiles']['openai'][0]['authentication'] = {'token': 'do-not-export'}
        with self.assertRaises(ValueError): portable.validate(value, 'personal')

    def test_wrong_type_and_unknown_portable_fields_are_refused(self):
        value = json.loads(portable.document(self.scope, self.first, 'personal'))
        with self.assertRaises(ValueError): portable.validate(value, 'company')
        value['profile']['clientSecret'] = 'private'
        with self.assertRaises(ValueError): portable.validate(value, 'personal')

    def test_import_cancel_leaves_metadata_and_manifests_unchanged(self):
        raw = portable.document(self.scope, self.first, 'personal')
        source = self.home / 'profile.json'; source.write_bytes(raw)
        self.first['location'] = {'kind': 'local', 'path': str(source)}; profiles.save(self.data)
        original = profiles.STORE.read_bytes()
        with patch.object(portable, 'choose', return_value=('b', None)):
            self.assertIn('cancelled', portable.import_profile(self.scope, self.first, 'personal', self.data, self.ui))
        self.assertEqual(profiles.STORE.read_bytes(), original)

    def test_import_changes_information_but_keeps_local_identity_and_connections(self):
        value = json.loads(portable.document(self.scope, self.first, 'personal'))
        value['profile'].update(name='Renamed', email='new@example.org', description='My information')
        source = self.home / 'profile.json'; source.write_text(json.dumps(value))
        self.first['location'] = {'kind': 'local', 'path': str(source)}; profiles.save(self.data)
        key = self.first['id']; second = copy.deepcopy(self.second)
        with patch.object(portable, 'choose', return_value=('enter', True)):
            portable.import_profile(self.scope, self.first, 'personal', self.data, self.ui)
        self.assertEqual(self.first['name'], 'Renamed'); self.assertEqual(self.first['id'], key)
        self.assertEqual(self.first['email'], 'new@example.org'); self.assertEqual(self.second, second)

    def test_failed_import_restores_live_record_references_and_manifest(self):
        path = self.accounts(); previous = path.read_bytes()
        value = json.loads(portable.document(self.scope, self.first, 'personal'))
        value['profile']['name'] = 'Should roll back'
        source = self.home / 'profile.json'; source.write_text(json.dumps(value))
        self.first['location'] = {'kind': 'local', 'path': str(source)}; profiles.save(self.data)
        before = copy.deepcopy(self.first)
        plans = sources.plans_for({'openai': {'version': 1, 'profiles': value['aiProfiles']['openai']}}, self.scope, {('openai', 0)})
        with patch.object(sources, 'review', return_value=plans), patch.object(portable, 'choose', return_value=('enter', True)), patch.object(sources, 'configure', side_effect=ValueError('failed launcher')):
            with self.assertRaises(ValueError): portable.import_profile(self.scope, self.first, 'personal', self.data, self.ui)
        self.assertIs(self.data['personal']['identities'][0], self.first)
        self.assertEqual(self.first, before); self.assertEqual(path.read_bytes(), previous)

    def test_local_export_is_private_and_refuses_symlinks_and_changed_files(self):
        path = self.home / 'export.json'; raw = portable.document(self.scope, self.first, 'personal')
        portable.local_export(str(path), raw, None)
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        path.write_text('{}')
        with self.assertRaises(ValueError): portable.local_export(str(path), raw, portable.digest(raw))
        link = self.home / 'link.json'; link.symlink_to(path)
        with self.assertRaises(ValueError): portable.local_export(str(link), raw, portable.digest(b'{}'))

    def github(self, responses):
        account = {'id': 101, 'login': 'example', 'state': 'Connected', 'authSource': 'native'}
        self.data['githubAccounts'] = [account]
        self.first['location'] = {'kind': 'github', 'githubId': 101, 'repository': 'example/profiles', 'path': 'profiles/main.json', 'ref': 'main'}
        self.first['profileUrl'] = portable.label(self.first['location'])
        cloud.scope_root(self.scope).mkdir(parents=True, exist_ok=True)
        return patch.object(portable, 'GitHub'), account

    def test_github_export_uses_bound_account_reviewed_sha_and_private_payload(self):
        p, account = self.github(None)
        raw = b'{}'; file = dict(encoding='base64', content=base64.b64encode(raw).decode(), sha='a'*40, size=len(raw))
        bodies = []
        def command(operation, config, login, endpoint, *args):
            self.assertEqual(login, 'example'); self.assertEqual(config, 'isolated-account')
            if operation == 'profile-export-base': return subprocess.CompletedProcess([], 0, json.dumps(file))
            self.assertEqual(operation, 'profile-put'); self.assertNotIn('?', endpoint)
            bodies.append(json.loads(Path(args[0]).read_text()))
            return subprocess.CompletedProcess([], 0, 'b'*40)
        with p as factory, patch.object(portable, 'choose', return_value=('enter', True)):
            client = factory.return_value; client.verify.return_value = True; client.configuration.return_value = 'isolated-account'; client.command.side_effect = command
            portable.export(self.scope, self.first, 'personal', self.data, self.ui)
        self.assertEqual(bodies[0]['sha'], 'a'*40); self.assertEqual(bodies[0]['branch'], 'main')
        self.assertNotIn('token', base64.b64decode(bodies[0]['content']).decode())

    def test_github_remote_conflict_prevents_put_and_cancel_prevents_write(self):
        for cancel in [False, True]:
            with self.subTest(cancel=cancel):
                p, account = self.github(None)
                def command(operation, *args):
                    self.assertEqual(operation, 'profile-export-base')
                    content = b'{}'
                    return subprocess.CompletedProcess([], 0, json.dumps(dict(encoding='base64', content=base64.b64encode(content).decode(), sha=('a' if not getattr(command, 'called', False) else 'b')*40, size=2)))
                with p as factory, patch.object(portable, 'choose', side_effect=lambda *a: (setattr(command, 'called', True) or ('b', None)) if cancel else (setattr(command, 'called', True) or ('enter', True))):
                    client = factory.return_value; client.verify.return_value = True; client.configuration.return_value = 'isolated'; client.command.side_effect = command
                    if cancel: self.assertIn('cancelled', portable.export(self.scope, self.first, 'personal', self.data, self.ui))
                    else:
                        with self.assertRaisesRegex(ValueError, 'changed'): portable.export(self.scope, self.first, 'personal', self.data, self.ui)

    def test_cloud_write_requires_permission_and_checks_current_content(self):
        connection = {'id': '1'*32, 'backend': 'drive', 'label': 'Fixture'}
        directory = cloud.connection_dir(self.scope, connection); directory.mkdir(parents=True)
        config = directory / 'rclone.conf'; config.write_text('[cloud]\n'); config.chmod(0o600)
        with self.assertRaisesRegex(ValueError, 'read-only'): cloud.publish(self.scope, connection, 'profile.json', b'{}', portable.digest(b'{}'))
        connection['access'] = 'write'
        listing = b'[{"Path":"profile.json","IsDir":false}]'
        with patch.object(cloud, 'bounded', side_effect=[listing, b'changed']) as run:
            with self.assertRaisesRegex(ValueError, 'changed'): cloud.publish(self.scope, connection, 'profile.json', b'{}', portable.digest(b'{}'))
        self.assertEqual(run.call_count, 2)
        with patch.object(cloud, 'bounded', side_effect=[listing, b'old', b'', b'new']) as run:
            cloud.publish(self.scope, connection, 'profile.json', b'new', portable.digest(b'old'))
        self.assertIn('copyto', run.call_args_list[2].args[0])

    def test_new_cloud_file_is_created_without_replacing_existing_content(self):
        connection = {'id': '3'*32, 'backend': 'onedrive', 'label': 'Exports', 'access': 'write'}
        directory = cloud.connection_dir(self.scope, connection); directory.mkdir(parents=True)
        config = directory/'rclone.conf'; config.write_text('[cloud]\n'); config.chmod(0o600)
        with patch.object(cloud, 'bounded', side_effect=[b'[]', b'', b'new']) as run:
            cloud.publish(self.scope, connection, 'profile.json', b'new', None)
        self.assertIn('--immutable', run.call_args_list[1].args[0])
        with patch.object(cloud, 'rclone', return_value=b'[]'):
            self.assertIsNone(cloud.file_contents(self.scope, connection, 'profile.json'))

    def test_cloud_browser_can_choose_a_new_json_file_in_current_folder(self):
        with patch.object(cloud, 'rclone', return_value=b'[]'), patch.object(cloud, 'selected', return_value=('enter', '@new')), patch.object(cloud, 'prompt', return_value='my-profile.json'):
            self.assertEqual(cloud.browse(self.scope, {'backend': 'drive'}, create=True), 'my-profile.json')

    def test_declined_cloud_write_upgrade_keeps_connection_and_profile(self):
        connection = {'id': '2'*32, 'backend': 'onedrive', 'label': 'Read only'}
        cloud.save(self.scope, {'version': 1, 'connections': [connection], 'sources': []})
        self.first['location'] = {'kind': 'cloud', 'connectionId': connection['id'], 'path': 'profile.json'}
        before = copy.deepcopy(self.first)
        with patch.object(cloud, 'connect') as connect:
            result = portable.export(self.scope, self.first, 'personal', self.data, dict(self.ui, confirm=lambda _: False))
        self.assertIn('cancelled', result); connect.assert_not_called(); self.assertEqual(self.first, before)

    def test_https_export_is_local_without_changing_source_or_publishing(self):
        url = 'https://example.org/profile.json'
        self.first.update(location={'kind': 'https', 'path': url}, profileUrl=url)
        path = self.home / 'local-export.json'
        with patch.object(portable, 'choose', return_value=('enter', True)), patch.object(sources, 'read_https') as remote:
            portable.export(self.scope, self.first, 'personal', self.data, dict(self.ui, ask=lambda *a: str(path)))
        remote.assert_not_called(); self.assertTrue(path.is_file())
        self.assertEqual(self.first['location']['path'], url)

    def test_export_refuses_to_replace_an_existing_provider_registry(self):
        path = self.home / 'registry.json'
        original = b'{"version":1,"kind":"tenant-registry","profiles":{}}'
        path.write_bytes(original)
        self.first.update(location={'kind': 'local', 'path': str(path)}, profileUrl=str(path))
        with patch.object(portable, 'choose') as review:
            with self.assertRaisesRegex(ValueError, 'cannot replace'):
                portable.export(self.scope, self.first, 'personal', self.data, self.ui)
        review.assert_not_called(); self.assertEqual(path.read_bytes(), original)

    def test_disabled_accounts_in_portable_files_are_not_materialized(self):
        value = json.loads(portable.document(self.scope, self.first, 'personal'))
        value['aiProfiles'] = {'openai': [{'name': 'disabled-account', 'email': 'main@example.org', 'status': 'disabled'}]}
        path = self.home / 'profile.json'; path.write_text(json.dumps(value))
        self.first.update(location={'kind': 'local', 'path': str(path)})
        with patch.object(portable, 'choose', return_value=('enter', True)), patch.object(sources, 'configure') as configure:
            portable.import_profile(self.scope, self.first, 'personal', self.data, self.ui)
        configure.assert_not_called(); self.assertFalse((self.config/'openai-profiles.json').exists())

    def test_native_github_write_is_bound_to_account_and_passes_json_file(self):
        fake = self.home / 'bin'; fake.mkdir()
        output = self.home / 'captured-body'
        calls = self.home / 'gh-calls'
        executable = fake / 'gh'
        executable.write_text('''#!/usr/bin/env bash
set -eu
printf '%s ambient=%s\n' "$*" "${GH_TOKEN:+set}" >> "$CAPTURE_CALLS"
case "$1 $2" in
 'auth token') [[ -z "${GH_TOKEN:-}" && "$*" == *'--user example'* ]]; printf fixture-private-token ;;
 'api --hostname') [[ "$GH_TOKEN" == fixture-private-token && "$*" == *'--method PUT'* ]]; while [[ "$1" != --input ]]; do shift; done; cat "$2" > "$CAPTURE_BODY"; printf '%040d' 1 ;;
 *) exit 99 ;;
esac
'''); executable.chmod(0o755)
        payload = self.home / 'payload.json'; payload.write_text('{"content":"e30=","branch":"main"}')
        env = dict(os.environ, PATH=str(fake)+os.pathsep+os.defpath, CAPTURE_BODY=str(output), CAPTURE_CALLS=str(calls), GH_TOKEN='wrong-ambient-account', GITHUB_TOKEN='wrong-ambient-account')
        result = subprocess.run(['bash', str(ROOT/'scripts/github-account.sh'), 'profile-put', 'native', 'example', 'repos/example/profiles/contents/profile.json', str(payload)], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr + (calls.read_text() if calls.exists() else 'No helper invocation')); self.assertEqual(output.read_text(), payload.read_text())
        self.assertNotIn('fixture-private-token', result.stdout+result.stderr)

    def test_browser_login_requests_write_scopes_only_when_explicit(self):
        spec = importlib.util.spec_from_file_location('navigation_login', ROOT/'tools-container/rclone_login.py')
        login = importlib.util.module_from_spec(spec); spec.loader.exec_module(login)
        for write in (False, True):
            root = self.home / ('write' if write else 'read'); root.mkdir()
            scopes = []
            def command(argv, env, directory):
                parser = login.configparser.ConfigParser(interpolation=None); parser.read(directory/'rclone.conf')
                scopes.append(parser['cloud']['access_scopes']); parser['cloud']['token'] = 'private-fixture'
                with (directory/'rclone.conf').open('w') as stream: parser.write(stream)
                return {}
            with patch.object(login, 'private_command', side_effect=command): login.configure(root, 'onedrive', write=write)
            self.assertEqual(scopes, ['Files.ReadWrite offline_access' if write else 'Files.Read offline_access'])

    def test_stacked_panels_keep_selection_about_and_navigation_visible(self):
        for width, height in [(36, 16), (60, 20), (80, 24), (100, 40)]:
            text = tui.frame('Personal Profiles', [('Profile '+str(i), i) for i in range(30)], 29, ['Selected profile only', 'selected@example.org'], 'A Add profile', (width, height))
            self.assertIn('› Profile 29', text); self.assertIn('About', text); self.assertIn('Q Cancel', text)
            self.assertLessEqual(len(text.splitlines()), height)
            self.assertTrue(all(len(line) <= width for line in text.splitlines()))

    def test_pty_personal_profile_name_edit_and_back_navigation(self):
        env = dict(os.environ, HOME=str(self.home), XDG_CONFIG_HOME=str(self.home), WORKBENCHES_HOST_RPC='')
        master, slave = pty.openpty()
        process = subprocess.Popen([sys.executable, str(ROOT/'scripts/setup-profiles.py')], stdin=slave, stdout=slave, stderr=slave, env=env)
        os.close(slave)
        steps = [('╭─ Profile', b'\r'), ('Personal Profiles', b'\r'), ('Personal Profile · Main', b'\r'),
                 ('Profile name [Main]:', b'My personal\n'), ('Personal Profile · My personal', b'b'),
                 ('Personal Profiles', b'b'), ('╭─ Profile', b'b')]
        output = ''; cursor = 0; stage = 0
        try:
            deadline = time.monotonic() + 15
            while process.poll() is None and time.monotonic() < deadline:
                if select.select([master], [], [], .1)[0]:
                    try: output += os.read(master, 65536).decode(errors='replace')
                    except OSError: break
                if stage < len(steps) and steps[stage][0] in output[cursor:]:
                    cursor = len(output); os.write(master, steps[stage][1]); stage += 1
            if process.poll() is None: process.terminate()
            code = process.wait(timeout=2)
            self.assertEqual(stage, len(steps), output[-4000:]); self.assertEqual(code, 0, output[-4000:])
            self.assertEqual(profiles.load()['personal']['identities'][0]['name'], 'My personal')
        finally:
            if process.poll() is None: process.kill(); process.wait()
            os.close(master)


if __name__ == '__main__': unittest.main()
