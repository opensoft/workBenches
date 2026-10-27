#!/usr/bin/env python3
"""Multiple identities, migration, native gh account isolation, and terminal UI."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import pty
import re
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
import setup_profiles as profiles
import profile_github as github
import profile_tui as tui
spec = importlib.util.spec_from_file_location('multi_ui', ROOT / 'scripts/setup-profiles.py')
ui = importlib.util.module_from_spec(spec); spec.loader.exec_module(ui)


class MultipleProfilesTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(); self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.root = self.directory / 'workbenches'
        self.patcher = patch.multiple(profiles, ROOT=self.root, STORE=self.root / 'profiles.json')
        self.patcher.start(); self.addCleanup(self.patcher.stop)

    def connection(self, key=101, login='example'):
        return {'id': key, 'login': login, 'state': 'Connected', 'authSource': 'native'}

    def test_multiple_personal_and_company_identities_defaults_and_shared_links(self):
        data = profiles.empty()
        first = ui.add_personal(data, 'Main', 'me@example.org')
        other = ui.add_personal(data, 'Consulting', 'consult@example.org')
        company = profiles.add_company(data, 'Example Company', 'work@company.org')
        work2 = profiles.add_identity(company, 'Other work', 'other@company.org')
        for identity in (first, other, work2): profiles.link_github(data, identity, self.connection())
        profiles.link_github(data, first, self.connection(102, 'example-work'))
        first['defaultGithubId'] = 102
        company['defaultIdentityId'] = work2['id']
        profiles.save(data)
        saved = profiles.load()
        self.assertEqual(len(saved['personal']['identities']), 2)
        self.assertEqual(saved['companies'][0]['email'], 'other@company.org')
        self.assertEqual(len(saved['githubAccounts']), 2)
        self.assertEqual(saved['personal']['github']['id'], 102)
        profiles.unlink_github(first, 101); profiles.save(data)
        self.assertEqual(work2['githubIds'], [101])
        self.assertEqual(other['githubIds'], [101])
        self.assertEqual(len(profiles.load()['githubAccounts']), 2)
        self.assertEqual(profiles.STORE.stat().st_mode & 0o777, 0o600)

    def test_v1_migration_keeps_company_root_and_backups_and_deduplicates_github(self):
        self.root.mkdir()
        company_id = 'company-' + '1' * 32
        identity = {'id': 101, 'login': 'example', 'verifiedAt': 'previous-check'}
        old = {'version': 1, 'personal': {'id': 'personal', 'name': 'Personal', 'email': 'me@example.org', 'github': identity},
               'companies': [{'id': company_id, 'name': 'Example', 'email': 'work@example.org', 'github': identity}]}
        original = json.dumps(old); profiles.STORE.write_text(original); profiles.STORE.chmod(0o600)
        session = self.root / 'identities' / company_id / 'account-session.json'
        session.parent.mkdir(parents=True); session.write_text('untouched-session-fixture')
        data = profiles.load()
        self.assertEqual(profiles.STORE.read_text(), original)  # summaries are read-only
        self.assertEqual(len(data['githubAccounts']), 1)
        self.assertEqual(data['githubAccounts'][0]['state'], 'Sign-in required')
        self.assertEqual(profiles.account_root(data['companies'][0]), session.parent)
        profiles.save(data)
        self.assertEqual((self.root / 'profiles.v1.json').read_text(), original)
        self.assertEqual((self.root / 'profiles.v1.json').stat().st_mode & 0o777, 0o600)
        self.assertEqual(session.read_text(), 'untouched-session-fixture')
        self.assertEqual(profiles.load(), data)

    def test_invalid_default_reference_duplicate_email_and_symlink_are_refused(self):
        data = profiles.empty(); identity = ui.add_personal(data, 'Main', 'me@example.org')
        with self.assertRaises(ValueError): profiles.add_identity(data['personal'], 'Duplicate', 'ME@example.org')
        identity['githubIds'] = [999]
        with self.assertRaises(ValueError): profiles.save(data)
        identity['githubIds'] = []; identity['defaultGithubId'] = 999
        with self.assertRaises(ValueError): profiles.save(data)
        connection = {'authSource': 'managed', 'authDirectory': '../../elsewhere'}
        with self.assertRaises(ValueError): github.GitHub().configuration(connection)

    def test_verify_checks_immutable_id_and_records_reauth_vs_network_states(self):
        client = github.GitHub(); account = self.connection()
        for response, expected in ((subprocess.CompletedProcess([], 4, '', ''), 'Sign-in required'),
                (subprocess.CompletedProcess([], 1, '', 'private failure'), 'Check failed'),
                (subprocess.CompletedProcess([], 0, '{"id":202,"login":"different"}', ''), 'Check failed'),
                (subprocess.CompletedProcess([], 0, '{"id":101,"login":"renamed"}', ''), 'Connected')):
            with patch.object(client, 'command', return_value=response):
                self.assertEqual(client.verify(account), expected == 'Connected')
            self.assertEqual(account['state'], expected)
            self.assertEqual(account['id'], 101)
        with patch.object(client, 'command', side_effect=subprocess.TimeoutExpired('gh', 30)):
            self.assertFalse(client.verify(account)); self.assertEqual(account['state'], 'Check failed')

    def test_native_verification_never_switches_accounts_or_returns_tokens(self):
        fake = self.directory / 'bin'; fake.mkdir()
        log = self.directory / 'gh.log'
        executable = fake / 'gh'
        executable.write_text('''#!/usr/bin/env bash
set -eu
printf '%s\\n' "$*" >> "$FAKE_GH_LOG"
case "$1 $2" in
  'auth token') [[ -z "${GH_TOKEN:-}" && -z "${GITHUB_TOKEN:-}" ]]; printf fixture-private-token ;;
  'api --hostname') [[ "$GH_TOKEN" == fixture-private-token ]]; printf '{"id":101,"login":"example"}' ;;
  *) exit 99 ;;
esac
'''); executable.chmod(0o755)
        with patch.dict(os.environ, PATH=str(fake) + ':/usr/bin:/bin', FAKE_GH_LOG=str(log), GH_TOKEN='ambient-wrong-account', GITHUB_TOKEN='ambient-other'):
            client = github.GitHub(); account = self.connection()
            self.assertTrue(client.verify(account))
        self.assertNotIn('switch', log.read_text())
        self.assertNotIn('fixture-private-token', log.read_text())
        self.assertNotIn('token', json.dumps(account))
        self.assertIn('--user example', log.read_text())

    def test_native_expired_token_reports_signin_without_printing_error_or_token(self):
        fake = self.directory / 'bin'; fake.mkdir()
        executable = fake / 'gh'
        executable.write_text('''#!/usr/bin/env bash
case "$1 $2" in
  'auth token') printf fixture-private-token ;;
  'api --hostname') printf 'gh: Bad credentials (HTTP 401)' >&2; exit 1 ;;
  *) exit 99 ;;
esac
'''); executable.chmod(0o755)
        with patch.dict(os.environ, PATH=str(fake) + ':/usr/bin:/bin'):
            account = self.connection()
            self.assertFalse(github.GitHub().verify(account))
        self.assertEqual(account['state'], 'Sign-in required')
        self.assertNotIn('fixture-private-token', json.dumps(account))

    def test_account_picker_reuses_connection_without_duplicate_or_other_links(self):
        data = profiles.empty(); identity = ui.add_personal(data, 'Main', 'me@example.org')
        connection = self.connection(); profiles.link_github(data, identity, connection)
        client = github.GitHub()
        with patch.object(github, 'choose', return_value=('enter', ('known', connection))), patch.object(client, 'verify', return_value=True):
            self.assertIs(github.select_account(client, data), connection)
        self.assertEqual(len(data['githubAccounts']), 1)
        self.assertEqual(identity['githubIds'], [101])

    def test_reauth_as_different_browser_account_preserves_existing_links(self):
        data = profiles.empty(); identity = ui.add_personal(data, 'Main', 'me@example.org')
        original = self.connection(); profiles.link_github(data, identity, original)
        replacement = self.connection(202, 'different')
        with patch.object(tui, 'choose', return_value=('enter', 'login')), \
                patch.object(github.GitHub, 'login', return_value=replacement):
            with self.assertRaises(ValueError): ui.github_details(original, data)
        self.assertEqual(original['id'], 101)
        self.assertEqual(identity['githubIds'], [101])
        self.assertEqual([a['id'] for a in profiles.load()['githubAccounts']], [101, 202])

    def test_clipboard_uses_stdin_and_browser_uses_fixed_device_url(self):
        client = github.GitHub()
        with patch.object(client, 'which', side_effect=lambda name: '/bin/' + name if name in ('wl-copy', 'xdg-open') else None), \
                patch.object(client, 'run', return_value=subprocess.CompletedProcess([], 0)) as run:
            self.assertTrue(client.copy_code('ABCD-1234'))
            self.assertEqual(run.call_args.kwargs['input'], 'ABCD-1234')
            self.assertTrue(client.open_browser())
            self.assertEqual(run.call_args.args[0], ['xdg-open', github.DEVICE_URL])

    def test_automatic_handoff_copies_before_browser_and_keeps_fallback_available(self):
        client = github.GitHub(); calls = []
        with patch.object(client, 'copy_code', side_effect=lambda code: calls.append(('copy', code)) or True), \
                patch.object(client, 'open_browser', side_effect=lambda: calls.append(('open',)) or True):
            self.assertIn('paste the code', client.handoff('ABCD-1234'))
        self.assertEqual(calls, [('copy', 'ABCD-1234'), ('open',)])
        with patch.object(client, 'copy_code', side_effect=OSError('no clipboard')), \
                patch.object(client, 'open_browser', side_effect=subprocess.TimeoutExpired('browser', 30)):
            notice = client.handoff('ABCD-1234')
        self.assertIn('Clipboard unavailable', notice)
        self.assertIn('Open the displayed URL', notice)

    def test_frames_fit_small_and_wide_terminals_and_keep_selection_visible(self):
        rows = [('Identity ' + str(i), i) for i in range(30)]
        for width, height in ((36, 16), (60, 20), (80, 24), (100, 30)):
            output = tui.frame('PROFILES', rows, 29, ['Details', 'me@example.org'],
                               'A Add personal  C Add company  G GitHub accounts', (width, height))
            self.assertTrue(all(len(line) <= width for line in output.splitlines()), output)
            self.assertLessEqual(len(output.splitlines()), height)
            self.assertIn('› Identity 29', output)

    def test_pty_dashboard_can_add_two_personal_and_company_identities_and_defaults(self):
        env = dict(os.environ, HOME=str(self.directory), XDG_CONFIG_HOME=str(self.directory), WORKBENCHES_HOST_RPC='')
        steps = [('PROFILES · Personal and companies', b'a'),
                 ('Identity name (for example Main or Consulting):', b'Main\n'), ('Email:', b'me@example.org\n'),
                 ('Personal / Main', b'b'), ('PROFILES · Personal and companies', b'a'),
                 ('Identity name (for example Main or Consulting):', b'Consulting\n'), ('Email:', b'consult@example.org\n'),
                 ('Personal / Consulting', b'b'), ('PROFILES · Personal and companies', b'c'),
                 ('Company name:', b'Example Company\n'), ('Company email:', b'work@example.org\n'),
                 ('C Sign in', b'a'), ('Identity name (for example Main or Consulting):', b'Other work\n'),
                 ('Email:', b'other@example.org\n'), ('Example Company / Other work', b'b'),
                 ('C Sign in', b'\x1b[B\x1b[Bd'), ('Other work · Default', b'b'),
                 ('PROFILES · Personal and companies', b'b')]
        transcript = self.drive_pty(env, steps)
        saved = profiles.load()
        self.assertEqual(len(saved['personal']['identities']), 2)
        self.assertEqual(len(saved['companies'][0]['identities']), 2)
        self.assertEqual(saved['companies'][0]['email'], 'other@example.org')
        self.assertNotIn('Traceback', transcript)

    def fake_device_flow(self):
        fake = self.directory / 'bin'; fake.mkdir()
        marker = self.directory / 'approval'
        browser_log = self.directory / 'browser.log'
        clipboard = self.directory / 'clipboard'
        gh = fake / 'gh'
        gh.write_text('''#!/usr/bin/env bash
set -eu
case "$1 $2" in
  'auth login')
    printf 'First copy your one-time code: ABCD-1234\\n' >&2
    while [[ "${FAKE_AUTO_APPROVE:-0}" != 1 || ! -f "$FAKE_BROWSER_LOG" || ! -f "$FAKE_CLIPBOARD" ]]; do sleep .05; done
    printf fixture-private-token > "$GH_CONFIG_DIR/hosts.yml"
    ;;
  'auth token') cat "$GH_CONFIG_DIR/hosts.yml" ;;
  'api --hostname') printf '{"id":101,"login":"example"}' ;;
  'auth status') printf '[]' ;;
  *) exit 99 ;;
esac
'''); gh.chmod(0o755)
        browser = fake / 'wslview'
        browser.write_text('#!/usr/bin/env bash\nprintf "%s" "$1" > "$FAKE_BROWSER_LOG"\n'); browser.chmod(0o755)
        copy = fake / 'wl-copy'
        copy.write_text('#!/usr/bin/env bash\ncat > "$FAKE_CLIPBOARD"\n'); copy.chmod(0o755)
        native = self.directory / 'native-gh'; native.mkdir()
        original = native / 'hosts.yml'; original.write_text('original-active-account')
        env = dict(os.environ, HOME=str(self.directory), XDG_CONFIG_HOME=str(self.directory), WORKBENCHES_HOST_RPC='',
            PATH=str(fake) + ':/usr/bin:/bin', FAKE_APPROVAL=str(marker),
            FAKE_BROWSER_LOG=str(browser_log), FAKE_CLIPBOARD=str(clipboard),
            GH_CONFIG_DIR=str(native), GH_TOKEN='ambient-token-must-not-be-used')
        data = profiles.empty(); ui.add_personal(data, 'Main', 'me@example.org'); profiles.save(data)
        return env, original, browser_log, clipboard

    def test_pty_device_code_automatically_opens_copies_and_preserves_native_account(self):
        env, original, browser_log, clipboard = self.fake_device_flow()
        env['FAKE_AUTO_APPROVE'] = '1'
        steps = [('PROFILES · Personal and companies', b'g'), ('GITHUB ACCOUNTS', b'n'),
            ('LINK @example', b'\r'), ('PROFILES · Personal and companies', b'b')]
        transcript = self.drive_pty(env, steps)
        saved = profiles.load()
        self.assertEqual(saved['personal']['identities'][0]['githubIds'], [101])
        self.assertEqual(saved['githubAccounts'][0]['state'], 'Connected')
        self.assertEqual(saved['githubAccounts'][0]['authSource'], 'managed')
        self.assertEqual(browser_log.read_text(), github.DEVICE_URL)
        self.assertEqual(clipboard.read_text(), 'ABCD-1234')
        self.assertEqual(original.read_text(), 'original-active-account')
        self.assertNotIn('fixture-private-token', transcript + profiles.STORE.read_text())
        self.assertFalse(list(self.root.rglob('device-progress*')))

    def test_pty_cancel_device_login_preserves_native_account_and_restores_menu(self):
        env, original, _, _ = self.fake_device_flow()
        steps = [('PROFILES · Personal and companies', b'g'), ('GITHUB ACCOUNTS', b'n'),
            ('Device code: ABCD-1234', b'b'), ('GITHUB ACCOUNTS', b'b'),
            ('PROFILES · Personal and companies', b'b')]
        self.drive_pty(env, steps)
        self.assertEqual(profiles.load()['githubAccounts'], [])
        self.assertEqual(original.read_text(), 'original-active-account')
        self.assertFalse(list(self.root.rglob('device-progress*')))

    def drive_pty(self, env, steps):
        master, slave = pty.openpty()
        process = subprocess.Popen([sys.executable, str(ROOT / 'scripts/setup-profiles.py')],
            stdin=slave, stdout=slave, stderr=slave, env=env, start_new_session=True)
        os.close(slave); transcript = ''; cursor = 0; stage = 0
        try:
            deadline = time.monotonic() + 15
            while process.poll() is None and time.monotonic() < deadline:
                ready, _, _ = select.select([master], [], [], .05)
                if ready:
                    try: transcript += os.read(master, 65536).decode(errors='replace')
                    except OSError: break
                if stage < len(steps) and steps[stage][0] in transcript[cursor:]:
                    cursor = len(transcript); os.write(master, steps[stage][1]); stage += 1
            if process.poll() is None and stage == len(steps):
                process.wait(timeout=2)
            if process.poll() is None:
                self.fail(f'PTY stalled at {stage}: {transcript[-5000:]}')
            self.assertEqual(process.returncode, 0, transcript)
            self.assertEqual(stage, len(steps), transcript)
            return transcript
        finally:
            if process.poll() is None: os.killpg(process.pid, signal.SIGTERM); process.wait(timeout=3)
            os.close(master)


if __name__ == '__main__': unittest.main()
