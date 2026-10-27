#!/usr/bin/env python3
"""Disposable metadata, account-bound transport, native adapter and PTY regressions."""
import base64
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import pty
import re
import select
import shutil
import struct
import subprocess
import sys
import tempfile
import termios
import time
import unittest
from unittest.mock import patch
import fcntl

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import profile_sources as sources
import profile_credentials
import setup_profiles as identities
spec = importlib.util.spec_from_file_location('profiles_entry', ROOT / 'scripts/setup-profiles.py')
entry = importlib.util.module_from_spec(spec); spec.loader.exec_module(entry)


class ProfileSourcesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.config = self.directory / '.config/workbenches'
        self.config.mkdir(parents=True)
        self.addCleanup(patch.stopall)
        patch.dict(os.environ, {'HOME': str(self.directory), 'XDG_CONFIG_HOME': str(self.directory / '.config')}).start()
        for name in ('CLAUDE_PROFILES_HOME', 'CODEX_PROFILES_HOME', 'CHATGPT_PROFILES_HOME', 'WORKBENCHES_CREDENTIAL_SCOPE', 'WORKBENCHES_HOST_RPC'):
            patch.dict(os.environ).start(); os.environ.pop(name, None)
        patch.object(identities, 'ROOT', self.config).start()
        patch.object(identities, 'STORE', self.config / 'profiles.json').start()
        self.scope = {'id': 'company-' + 'a' * 32, 'name': 'Example Company'}
        self.other = {'id': 'company-' + 'b' * 32, 'name': 'Other Company'}
        self.personal = {'id': 'personal', 'name': 'Personal'}
        self.row = {'name': 'team-001', 'email': 'team-001@example.org', 'family': 'company', 'aliases': ['team001']}
        self.bundle = {'version': 1, 'kind': 'workbenches-ai-profile-bundle', 'profiles': {'claude': [self.row], 'openai': [self.row]}}
        self.file = self.directory / 'manifest with spaces.json'; self.file.write_text(json.dumps(self.bundle))
        self.source = {'kind': 'local', 'path': str(self.file)}
        self.data = identities.empty()

    def documents(self): return sources.provider_documents(self.bundle, self.source)

    def plans(self, scope=None):
        return sources.plans_for(self.documents(), scope or self.scope, {('claude', 0), ('openai', 0)})

    def test_reviewed_bundle_configures_scoped_manifests_and_preserves_credentials(self):
        secret = self.directory / '.claude-profiles/profiles/personal/local/.credentials.json'
        secret.parent.mkdir(parents=True); secret.write_text('private sentinel')
        with patch.object(sources, 'review', side_effect=lambda scope, source, docs: self.plans()), patch.object(sources, 'configure') as configure:
            self.assertTrue(sources.import_source(self.scope, self.source, self.data))
        self.assertEqual(configure.call_count, 2)
        for name in ('claude-profiles.json', 'openai-profiles.json'):
            p = self.config / name; row = json.loads(p.read_text())['profiles'][0]
            self.assertEqual(row['family'], self.scope['id']); self.assertTrue(row['profilePath'].startswith(self.scope['id'] + '/'))
            self.assertEqual(p.stat().st_mode & 0o777, 0o600)
        saved = sources.cloud.load(self.scope)['sources'][0]
        self.assertEqual(saved['counts'], {'claude': 1, 'openai': 1}); self.assertIn('importedAt', saved)
        self.assertEqual(secret.read_text(), 'private sentinel')
        self.assertNotIn('private sentinel', json.dumps(saved))

    def test_cancel_does_not_persist_source_or_manifests(self):
        with patch.object(sources, 'review', return_value=None), patch.object(sources, 'configure') as configure:
            self.assertFalse(sources.import_source(self.scope, self.source, self.data))
        self.assertFalse((self.config / 'claude-profiles.json').exists()); configure.assert_not_called()
        self.assertEqual(sources.cloud.load(self.scope)['sources'], [])

    def test_multi_provider_failure_rolls_back_and_keeps_previous_source(self):
        for p, plan in self.plans(self.personal).items(): sources.cloud.private_json(plan[0], plan[1])
        before = {p: p.read_bytes() for p in self.config.glob('*-profiles.json')}
        plans = self.plans()
        with patch.object(sources, 'configure', side_effect=[None, ValueError('fixture failure')]), self.assertRaises(ValueError):
            sources.apply(self.scope, self.source, self.file.read_bytes(), None, plans)
        self.assertEqual(before, {p: p.read_bytes() for p in before})
        self.assertEqual(sources.cloud.load(self.scope)['sources'], [])

    def test_manifest_race_requires_new_review(self):
        plans = self.plans()
        sources.cloud.private_json(plans['claude'][0], {'version': 1, 'profiles': []})
        with patch.object(sources, 'configure') as configure, self.assertRaisesRegex(ValueError, 'during review'):
            sources.apply(self.scope, self.source, self.file.read_bytes(), None, plans)
        configure.assert_not_called()

    def test_refresh_is_idempotent_and_other_company_homes_are_reserved(self):
        for scope in (self.other, self.scope, self.scope):
            with patch.object(sources, 'configure'):
                sources.apply(scope, self.source, self.file.read_bytes(), None, self.plans(scope))
        rows = json.loads((self.config / 'claude-profiles.json').read_text())['profiles']
        self.assertEqual(len(rows), 2); self.assertEqual(len({r['profilePath'] for r in rows}), 2)
        self.assertEqual(len(sources.cloud.load(self.scope)['sources']), 1)
        self.assertEqual(rows[0]['email'], rows[1]['email'])

    def test_secrets_bad_json_and_unbounded_sources_are_rejected(self):
        for value in (dict(self.bundle, token='secret'), {'version': 1, 'profiles': [{'name': 'x', 'email': 'x@example.org', 'token': 'secret'}]}):
            raw = json.dumps(value).encode(); source = dict(self.source, provider='claude')
            with self.subTest(value=value), self.assertRaises(ValueError):
                docs = sources.provider_documents(value, source)
                sources.plans_for(docs, self.scope, {('claude', 0)})
        for raw in (b'{"version":1,"version":2}', b'\xff', b'x' * (sources.LIMIT + 1)):
            with self.subTest(raw=raw[:30]), self.assertRaises(ValueError): sources.json_bytes(raw)
        self.file.unlink(); self.file.mkdir()
        with self.assertRaises(ValueError): sources.read_local(str(self.file))

    def test_catalog_metadata_status_and_owner_are_not_confused_with_credentials(self):
        row = dict(self.row, owner={'type': 'tenant', 'id': 'example'}, plan='Team', status='active', accountId='account-1',
                   authentication={'type': 'oauth', 'accountId': 'account-1', 'credentialRef': 'ai/secrets/claude/team-001.json', 'escrowStatus': 'not-escrowed'})
        normalized = sources.metadata_row(row)
        self.assertNotIn('owner', normalized); self.assertNotIn('accountId', normalized['authentication'])
        with self.assertRaises(ValueError): sources.metadata_row(dict(row, token='must-never-import'))
        with self.assertRaises(ValueError): sources.metadata_row(dict(row, authentication=dict(row['authentication'], accountId='other')))
        planned = dict(self.row, status='planned')
        docs = {'claude': {'version': 1, 'profiles': [planned]}}
        calls = []
        def choose(title, rows, detail, footer):
            calls.append(rows[0][0])
            if len(calls) == 1: return 'enter', ('profile', ('claude', 0))
            return 'i', ('apply', None)
        with patch.object(sources, 'choose', side_effect=choose):
            sources.review(self.scope, self.source, docs)
        self.assertIn('(0)', calls[0]); self.assertIn('(1)', calls[1])

    def test_disabled_accounts_are_excluded_before_review(self):
        value = dict(self.bundle, profiles={'claude': [self.row, dict(self.row, name='disabled', status='disabled')]})
        self.file.write_text(json.dumps(value))
        with patch.object(sources, 'review', return_value=None) as review:
            sources.import_source(self.scope, self.source, self.data)
        self.assertEqual([row['name'] for row in review.call_args.args[2]['claude']['profiles']], ['team-001'])

    def test_https_rejects_token_urls_and_private_share_links_without_fetching(self):
        for url in ('http://example.org/x', 'https://u:p@example.org/x', 'https://example.org/x?token=secret',
                    'https://example.org/x#secret', 'https://drive.google.com/file/d/id/view', 'https://company.sharepoint.com/x'):
            with self.subTest(url=url), self.assertRaises(ValueError): sources.https_url(url)
        self.assertEqual(sources.https_url('https://example.org/profiles.json'), 'https://example.org/profiles.json')
        with patch.object(sources.urllib.request, 'build_opener') as opener:
            response = opener.return_value.open.return_value.__enter__.return_value
            response.status = 200; response.read.return_value = self.file.read_bytes()
            self.assertEqual(sources.read_https('https://example.org/profiles.json'), self.file.read_bytes())
            response.read.assert_called_with(sources.LIMIT + 1)

    def github_client(self, grant=True):
        row = dict(self.row, authentication={'type': 'oauth', 'credentialRef': 'azure-key-vault://example-vault/ai-credential-claude-team-001', 'escrowStatus': 'external-vault'})
        catalog = {'version': 1, 'kind': sources.cloud.composer.SOURCE_KIND, 'owner': {'type': 'tenant', 'id': 'example'},
                   'profiles': {'claude': [row, dict(row, name='hidden', email='hidden@example.org', authentication={'type': 'oauth', 'credentialRef': 'ai/secrets/claude/hidden.json', 'escrowStatus': 'not-escrowed'})]}}
        calls = []
        class Client:
            def verify(self, account): calls.append(('verify', account['id'])); return account['id'] == 101
            def configuration(self, account): return '/private/selected-config'
            def command(self, operation, config, login, endpoint):
                calls.append((operation, config, login, endpoint))
                if operation == 'profile-revision': return subprocess.CompletedProcess([], 0, 'c' * 40 + '\n')
                value = catalog if '/contents/ai/source.json?' in endpoint else {'version': 1, 'user': 'engineer', 'profiles': {'claude': ['team-*']}}
                if not grant and '/grants/' in endpoint: return subprocess.CompletedProcess([], 1, '')
                raw = json.dumps(value).encode()
                return subprocess.CompletedProcess([], 0, json.dumps({'size': len(raw), 'encoding': 'base64', 'sha': 'd' * 40, 'content': base64.b64encode(raw).decode()}))
        data = {'githubAccounts': [{'id': 101, 'login': 'engineer'}, {'id': 202, 'login': 'other'}]}
        source = {'kind': 'github', 'repository': 'Example/Profiles', 'path': 'ai/source.json', 'ref': 'feature/profiles', 'githubId': 101}
        return Client(), calls, data, source

    def test_github_uses_selected_account_immutable_revision_and_grants(self):
        client, calls, data, source = self.github_client()
        _, value, revision = sources.read_github(source, data, client)
        self.assertEqual([r['name'] for r in value['profiles']['claude']], ['team-001'])
        self.assertEqual(revision, 'c' * 40)
        self.assertIn('feature%2Fprofiles', calls[1][-1])
        for call in calls[2:]:
            self.assertEqual(call[1:3], ('/private/selected-config', 'engineer'))
            self.assertTrue(call[-1].endswith('?ref=' + 'c' * 40))
        self.assertIn('grants/users/engineer.json', calls[-1][-1])

    def test_denied_github_never_substitutes_another_account(self):
        client, calls, data, source = self.github_client()
        source['githubId'] = 202
        with self.assertRaisesRegex(ValueError, 'saved GitHub account'): sources.read_github(source, data, client)
        self.assertEqual(calls, [('verify', 202)])
        client, calls, data, source = self.github_client(grant=False)
        with self.assertRaisesRegex(ValueError, 'user grant'): sources.read_github(source, data, client)

    def test_native_helper_uses_explicit_account_and_strips_ambient_tokens(self):
        binpath = self.directory / 'bin'; binpath.mkdir(); gh = binpath / 'gh'
        gh.write_text('''#!/bin/bash
case "$1 $2" in
 'auth token') [[ "$*" == *"--user engineer"* ]] || exit 2; printf fixture-credential ;;
 'api --hostname') [[ "$GH_TOKEN" == fixture-credential && "$GH_CONFIG_DIR" == /selected ]] || exit 2; printf '{"size":0}' ;;
 *) exit 2 ;;
esac
'''); gh.chmod(0o755)
        env = dict(os.environ, PATH=str(binpath) + ':' + os.environ['PATH'], GH_TOKEN='ambient', GITHUB_TOKEN='wrong')
        result = subprocess.run(['bash', str(ROOT / 'scripts/github-account.sh'), 'profile-file', '/selected', 'engineer', 'repos/example/profiles/contents/manifest.json?ref=' + 'c' * 40], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr); self.assertEqual(result.stdout, '{"size":0}')
        self.assertNotIn('credential', result.stdout + result.stderr)

    def test_recovery_env_and_entries_are_limited_to_selected_scope(self):
        for scope in (self.personal, self.scope):
            with patch.object(sources, 'configure'): sources.apply(scope, self.source, self.file.read_bytes(), None, self.plans(scope))
        with patch.object(sources.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0)) as run:
            sources.recover(self.scope)
        self.assertEqual(run.call_args.kwargs['env']['WORKBENCHES_CREDENTIAL_SCOPE'], self.scope['id'])
        with patch.dict(os.environ, {'WORKBENCHES_CREDENTIAL_SCOPE': self.scope['id']}):
            rows = profile_credentials.entries({'claude', 'codex'})
        self.assertEqual(len(rows), 2)
        self.assertTrue(all(self.scope['id'] in r['credentialPath'] for r in rows))

    def native(self, system, command=None, display=True, extra=None):
        directory = self.directory / ('native-' + str(time.time_ns())); directory.mkdir()
        def executable(name, body):
            p = directory / name; p.write_text('#!/bin/bash\n' + body + '\n'); p.chmod(0o755)
        executable('uname', 'printf %s ' + system)
        if command: executable(*command)
        env = dict(os.environ, PATH=str(directory) + ':/usr/bin:/bin')
        for key in ('WSL_DISTRO_NAME', 'SSH_CONNECTION', 'SSH_TTY', 'DISPLAY', 'WAYLAND_DISPLAY'): env.pop(key, None)
        if display: env['DISPLAY'] = ':fixture'
        if extra: env.update(extra)
        return directory, env, executable

    def test_native_linux_success_and_cancel_without_gui(self):
        _, env, _ = self.native('Linux', ('zenity', "printf '/tmp/manifest with spaces.json\\n'"))
        result = subprocess.run(['bash', str(ROOT / 'scripts/native-profile-file.sh'), 'pick'], env=env, capture_output=True, text=True)
        self.assertEqual(result.stdout.strip(), '/tmp/manifest with spaces.json'); self.assertEqual(result.returncode, 0)
        _, env, _ = self.native('Linux', ('zenity', 'exit 1'))
        result = subprocess.run(['bash', str(ROOT / 'scripts/native-profile-file.sh'), 'pick'], env=env, capture_output=True)
        self.assertEqual(result.returncode, 1)

    def test_native_mac_and_windows_wsl_route_to_host_picker(self):
        _, env, _ = self.native('Darwin', ('osascript', "printf '/Users/engineer/profiles.json\\n'"))
        result = subprocess.run(['bash', str(ROOT / 'scripts/native-profile-file.sh'), 'pick'], env=env, capture_output=True, text=True)
        self.assertEqual(result.stdout.strip(), '/Users/engineer/profiles.json')
        _, env, executable = self.native('Linux', ('powershell.exe', 'printf "C:\\\\Profiles\\\\profiles.json"'), extra={'WSL_DISTRO_NAME': 'Ubuntu'})
        executable('wslpath', '[[ "$1" == -u ]] || exit 2; printf /mnt/c/Profiles/profiles.json')
        result = subprocess.run(['bash', str(ROOT / 'scripts/native-profile-file.sh'), 'pick'], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr); self.assertTrue(result.stdout.startswith('C:'))
        _, env, executable = self.native('MINGW64_NT', ('powershell.exe', 'printf "C:\\\\Profiles\\\\profiles.json"'))
        executable('cygpath', 'printf /c/Profiles/profiles.json')
        result = subprocess.run(['bash', str(ROOT / 'scripts/native-profile-file.sh'), 'pick'], env=env, capture_output=True, text=True)
        self.assertTrue(result.stdout.startswith('C:'))

    def test_headless_ssh_and_host_rpc_do_not_use_container_picker(self):
        for extra in ({}, {'SSH_CONNECTION': 'fixture'}):
            _, env, _ = self.native('Linux', display=False, extra=extra)
            result = subprocess.run(['bash', str(ROOT / 'scripts/native-profile-file.sh'), 'pick'], env=env, capture_output=True)
            self.assertEqual(result.returncode, 3)
        with patch.object(sources.host, 'active', return_value=True), patch.object(sources.host, 'run', return_value=subprocess.CompletedProcess([], 0, str(self.file) + '\n')) as run:
            self.assertEqual(sources.native_file(), str(self.file)); self.assertEqual(run.call_args.args[0], ['@profile-file', 'pick'])
        with patch.object(sources.host, 'active', return_value=True), patch.object(sources.host, 'run', return_value=subprocess.CompletedProcess([], 0, self.file.read_bytes())) as run:
            self.assertEqual(sources.read_local(str(self.file)), self.file.read_bytes()); self.assertEqual(run.call_args.args[0][:2], ['@profile-file', 'read'])

    def test_sharing_link_uses_scoped_drive_browser_without_saving_the_url(self):
        connection = {'id': 'a' * 32, 'backend': 'drive', 'label': 'Company Drive'}
        with patch.object(sources.cloud, 'load', return_value={'connections': [connection], 'sources': []}), \
                patch.object(sources, 'choose', return_value=('enter', connection)), \
                patch.object(sources.cloud, 'browse', return_value='profiles/claude.json'):
            source = sources.drive_link(self.scope, 'https://drive.google.com/file/d/shared/view?usp=sharing')
        self.assertEqual(source, {'kind': 'cloud', 'path': 'profiles/claude.json', 'connectionId': connection['id']})
        self.assertNotIn('sharing', json.dumps(source))

    def test_windows_manual_and_picker_paths_translate_through_native_host(self):
        path = 'C:\\Profiles\\profiles.json'
        with patch.object(sources.host, 'active', return_value=True), patch.object(sources.host, 'run', return_value=subprocess.CompletedProcess([], 0, '/mnt/c/Profiles/profiles.json')) as run:
            self.assertEqual(sources.local_path(path), '/mnt/c/Profiles/profiles.json')
            self.assertEqual(run.call_args.args[0], ['@profile-file', 'path', path])

    def test_native_read_rejects_symlink_and_directory_and_bounds_bytes(self):
        helper = ROOT / 'scripts/native-profile-file.sh'
        link = self.directory / 'link.json'; link.symlink_to(self.file)
        for target in (link, self.directory):
            result = subprocess.run(['bash', str(helper), 'read', str(target)], capture_output=True)
            self.assertNotEqual(result.returncode, 0)
        self.file.write_bytes(b'x' * (sources.LIMIT + 10))
        result = subprocess.run(['bash', str(helper), 'read', str(self.file)], capture_output=True)
        self.assertEqual(len(result.stdout), sources.LIMIT + 1)

    def test_recovery_reference_defaults_come_from_selected_metadata_only(self):
        row = dict(self.row, authentication={'type': 'oauth', 'credentialRef': 'azure-key-vault://example-vault/ai-credential-claude-team-001', 'escrowStatus': 'external-vault'})
        source = dict(self.source, provider='claude')
        doc = {'claude': {'version': 1, 'profiles': [row]}}
        plans = sources.plans_for(doc, self.scope, {('claude', 0)})
        with patch.object(sources, 'configure'): sources.apply(self.scope, source, b'{}', None, plans)
        with patch.dict(os.environ, {'WORKBENCHES_CREDENTIAL_SCOPE': self.scope['id']}):
            rows = profile_credentials.entries({'claude'})
        self.assertEqual(profile_credentials.references(rows), {('claude', 'team-001'): ('example-vault', 'ai-credential-claude-team-001')})

    def test_scoped_recovery_saves_mapping_beside_the_company_source(self):
        spec = importlib.util.spec_from_file_location('source_recovery', ROOT / 'scripts/setup-credential-recovery.py')
        recovery = importlib.util.module_from_spec(spec); spec.loader.exec_module(recovery)
        spec_data = []
        def guided(service, manifest, advanced): spec_data.append((service, manifest)); return 0
        with patch.dict(os.environ, {'WORKBENCHES_CREDENTIAL_SCOPE': self.scope['id'], 'WORKBENCHES_AUTH_ROUTE': 'vault', 'WORKBENCHES_VAULT_SERVICE': 'azure'}), \
                patch.object(recovery.profile_credentials, 'selected_ready', return_value=False), \
                patch.object(sys.stdin, 'isatty', return_value=True), patch.object(sys.stdout, 'isatty', return_value=True), \
                patch.object(sys, 'argv', ['recovery', '--interactive']), patch.object(recovery, 'guided_recovery', side_effect=guided):
            self.assertEqual(recovery.main(), 0)
        self.assertEqual(spec_data[0][1], self.config / 'manifest-sources' / self.scope['id'] / 'ai-credential-keyvault.json')

    def test_scope_pane_exposes_source_entry_and_no_identity_needed_for_files(self):
        data = identities.empty(); scope = identities.add_company(data, 'Example', 'me@example.org')
        seen = []
        def choose(title, rows, detail, actions):
            seen.append((title, rows, detail(rows[0][1])))
            return ('enter', None) if len(seen) == 1 else ('b', None)
        with patch('profile_tui.choose', side_effect=choose), patch.object(entry, 'ai_accounts') as ai:
            entry.scope_menu(scope, data)
        ai.assert_called_once(); self.assertIn('AI profiles', seen[0][1][0][0])
        self.assertIn('Local file', ' '.join(seen[0][2]))

    def test_review_can_deselect_provider_and_preserves_narrow_navigation(self):
        choices = [('enter', ('provider', 'openai')), ('i', ('apply', None))]
        with patch.object(sources, 'choose', side_effect=choices):
            plans = sources.review(self.scope, self.source, self.documents())
        self.assertEqual(set(plans), {'claude'})
        import profile_tui
        for width, height in [(42, 16), (100, 24)]:
            view = profile_tui.frame('AI PROFILES · Example', [('Choose local file…', None), ('Enter HTTPS file URL', None)], 0, ['File or repository', 'Credentials separate'], 'Enter Open  B Back  Q Cancel', (width, height))
            self.assertTrue(all(len(line) <= width for line in view.splitlines())); self.assertIn('Q Cancel', view)

    def test_manual_account_uses_same_review_without_github_or_a_remote_source(self):
        identity = {'email': 'me@example.org'}
        with patch.object(sources, 'choose', return_value=('enter', 'claude')), \
                patch.object(sources, 'field', side_effect=['me@example.org', 'my-work']), \
                patch.object(sources, 'review', side_effect=lambda scope, source, docs: sources.plans_for(docs, scope, {('claude', 0)})), \
                patch.object(sources, 'configure'):
            sources.add_account(self.scope, identity)
        row = json.loads((self.config / 'claude-profiles.json').read_text())['profiles'][0]
        self.assertEqual(row['name'], 'my-work'); self.assertEqual(row['family'], self.scope['id'])
        self.assertEqual(sources.cloud.load(self.scope)['sources'], [])

    def test_default_login_does_not_skip_interactive_ownership_pane(self):
        auth = self.directory / '.codex/auth.json'; auth.parent.mkdir(); auth.write_text('{"OPENAI_API_KEY":"fixture-key"}')
        env = dict(os.environ, WORKBENCHES_SELECTED_PROVIDERS='openai', PATH='/usr/bin:/bin')
        for key in ('WORKBENCHES_AUTH_ROUTE', 'WORKBENCHES_PROFILE_SOURCE_FLOW'): env.pop(key, None)
        master, slave = pty.openpty()
        process = subprocess.Popen(['bash', str(ROOT / 'scripts/setup-ai-profiles.sh'), '--interactive'],
                                   stdin=slave, stdout=slave, stderr=slave, env=env)
        os.close(slave); output = ''; sent = False
        try:
            deadline = time.monotonic() + 8
            while process.poll() is None and time.monotonic() < deadline:
                if select.select([master], [], [], .1)[0]:
                    try: output += os.read(master, 65536).decode(errors='replace')
                    except OSError: break
                if not sent and 'AI PROFILES · Choose ownership' in output:
                    os.write(master, b'jj\r'); sent = True
            process.wait(timeout=2)
            self.assertTrue(sent, output); self.assertEqual(process.returncode, 0, output)
            self.assertIn('Reusing existing credentials', output)
            self.assertEqual(json.loads(auth.read_text()), {'OPENAI_API_KEY': 'fixture-key'})
        finally:
            if process.poll() is None: process.kill(); process.wait()
            os.close(master)

    def test_pty_local_import_in_company_pane_and_cursor_restoration(self):
        data = identities.empty(); scope = identities.add_company(data, 'Example Company', 'me@example.org'); identities.save(data)
        env = dict(os.environ, PYTHONPATH=str(ROOT / 'scripts'))
        harness = f'''import importlib.util,profile_sources as s
s.configure=lambda provider,path:None
spec=importlib.util.spec_from_file_location('entry',{str(ROOT / 'scripts/setup-profiles.py')!r})
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
m.main()
'''
        output = self.directory / 'route'; output.touch(mode=0o600)
        master, slave = pty.openpty(); fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 110, 0, 0))
        process = subprocess.Popen([sys.executable, '-c', harness, '--ai-onboarding', str(output)], stdin=slave, stdout=slave, stderr=slave, env=env)
        os.close(slave); transcript = ''; stage = 0
        steps = [('AI PROFILES · Choose ownership', b'j\r'), ('AI PROFILES · Example Company', b'j\r'),
                 ('Local JSON manifest path:', (str(self.file) + '\n').encode()), ('REVIEW AI PROFILES', b'i'),
                 ('Imported. Recover', b'b'), ('AI PROFILES · Choose ownership', b'jjj\r')]
        try:
            deadline = time.monotonic() + 12
            while process.poll() is None and time.monotonic() < deadline:
                if select.select([master], [], [], .1)[0]:
                    try: transcript += os.read(master, 65536).decode(errors='replace')
                    except OSError: break
                plain = re.sub(r'\x1b(?:\[[0-?]*[ -/]*[@-~]|[78])', '', transcript)
                if stage < len(steps) and steps[stage][0] in plain:
                    os.write(master, steps[stage][1]); transcript = ''; stage += 1
            self.assertEqual(stage, len(steps), transcript)
            process.wait(timeout=2); self.assertEqual(process.returncode, 0, transcript)
            file = self.config / 'claude-profiles.json'
            self.assertEqual(json.loads(file.read_text())['profiles'][0]['family'], scope['id'])
        finally:
            if process.poll() is None: process.kill(); process.wait()
            os.close(master)


if __name__ == '__main__': unittest.main()
