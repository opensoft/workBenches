"""GitHub device sign-in and per-account verification through native gh."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import uuid
from datetime import datetime, timezone

import setup_profiles as profiles
from profile_tui import choose, message, keyboard, key, show
from setup_prompts import propagate_cancel

HELPER = Path(__file__).resolve().with_name('github-account.sh')
DEVICE_URL = 'https://github.com/login/device'


class LoginCancelled(Exception):
    pass


class GitHub:
    def __init__(self, host=None):
        self.host = host

    def which(self, name):
        return self.host.which(name) if self.host else shutil.which(name)

    def run(self, arguments, **kwargs):
        return (self.host.run if self.host else subprocess.run)(arguments, text=True,
            capture_output=True, timeout=kwargs.pop('timeout', 30), **kwargs)

    def command(self, operation, config='native', *args, **kwargs):
        result = self.run(['bash', str(HELPER), operation, str(config), *args], **kwargs)
        propagate_cancel(result.returncode)
        return result

    def configuration(self, account):
        if account.get('authSource') != 'managed': return 'native'
        name = account.get('authDirectory', '')
        if not re.fullmatch(r'github-[a-f0-9]{32}', name): raise ValueError('Invalid GitHub connection directory.')
        root = profiles.ROOT / 'github-auth'
        path = root / name
        if profiles.ROOT.is_symlink() or root.is_symlink() or path.is_symlink():
            raise ValueError('GitHub connection storage must not be a symlink.')
        return path

    def discover(self):
        if not self.which('gh'): raise ValueError('Install GitHub CLI (gh) on the workstation, then retry.')
        result = self.command('list')
        if result.returncode: raise ValueError('Could not list native GitHub accounts. Update gh or connect another account.')
        accounts = json.loads(result.stdout)
        if not isinstance(accounts, list): raise ValueError('GitHub CLI returned an invalid account list.')
        return [a for a in accounts if isinstance(a, dict) and re.fullmatch(r'[A-Za-z0-9-]{1,39}', a.get('login', ''))]

    def verify(self, account):
        if not re.fullmatch(r'[A-Za-z0-9-]{1,39}', account.get('login', '')):
            raise ValueError('Invalid GitHub account name.')
        account['checkedAt'] = datetime.now(timezone.utc).isoformat()
        try:
            result = self.command('verify', self.configuration(account), account['login'])
            if result.returncode:
                account['state'] = 'Sign-in required' if result.returncode == 4 else 'Check failed'
                return False
            response = json.loads(result.stdout)
            if (type(response.get('id')) is not int or response['id'] <= 0
                    or not re.fullmatch(r'[A-Za-z0-9-]{1,39}', response.get('login', ''))
                    or account.get('id') is not None and response['id'] != account['id']):
                account['state'] = 'Check failed'
                return False
        except (OSError, subprocess.TimeoutExpired, ValueError, TypeError, AttributeError):
            account['state'] = 'Check failed'
            return False
        account.update(id=response['id'], login=response['login'], state='Connected', verifiedAt=account['checkedAt'])
        return True

    def open_browser(self):
        for name in ('wslview', 'xdg-open', 'open'):
            if self.which(name):
                return self.run([name, DEVICE_URL]).returncode == 0
        if self.which('powershell.exe'):
            return self.run(['powershell.exe', '-NoProfile', '-Command', 'Start-Process', DEVICE_URL]).returncode == 0
        return False

    def copy_code(self, code):
        for name, args in (('wl-copy', []), ('pbcopy', []), ('xclip', ['-selection', 'clipboard']), ('clip.exe', [])):
            if self.which(name): return self.run([name, *args], input=code).returncode == 0
        return False

    def attempt(self, action):
        try:
            return action()
        except (OSError, subprocess.TimeoutExpired):
            return False

    def handoff(self, code):
        # Copy first so the code is ready when the browser takes focus.
        copied = self.attempt(lambda: self.copy_code(code))
        opened = self.attempt(self.open_browser)
        return ('Device code copied. ' if copied else 'Clipboard unavailable; copy the displayed code. ') + (
            'Browser opened; paste the code to continue.' if opened else 'Open the displayed URL in your browser.')

    def login(self):
        if not sys.stdin.isatty() or not sys.stdout.isatty():
            raise ValueError('Use an interactive terminal for GitHub browser sign-in.')
        if not self.which('gh'): raise ValueError('Install GitHub CLI (gh) on the workstation, then retry.')
        account = {'authSource': 'managed', 'authDirectory': 'github-' + uuid.uuid4().hex}
        config = self.configuration(account)
        config.mkdir(parents=True, mode=0o700)
        config.parent.chmod(0o700)
        progress = config / 'device-progress'
        progress.touch(mode=0o600)
        result = self.command('start-login', config, str(progress))
        if result.returncode: raise ValueError('GitHub sign-in could not start.')
        exit_file = Path(str(progress) + '.exit')
        deadline = time.monotonic() + 600
        code, notice = '', 'Waiting for a device code…'
        try:
            with keyboard():
                while not exit_file.exists():
                    if time.monotonic() >= deadline:
                        raise ValueError('GitHub approval timed out. Retry when ready.')
                    transcript = progress.read_text(errors='replace')[-16384:]
                    match = re.search(r'\b[A-Z0-9]{4}-[A-Z0-9]{4}\b', transcript)
                    if match and match.group() != code:
                        code = match.group()
                        notice = self.handoff(code)
                    show(message('CONNECT GITHUB',
                        [DEVICE_URL, 'Device code: ' + (code or 'Waiting…'), '',
                         'O Open browser   C Copy code', notice,
                         'Choose the intended GitHub account in your browser.',
                         'No username, password, or token to type here.'], 'O Open browser  C Copy code  B Cancel  Q Exit Profiles'))
                    pressed = key(.15)
                    if pressed in ('b', 'back'): raise LoginCancelled()
                    if pressed == 'o': notice = 'Browser opened.' if self.attempt(self.open_browser) else 'Open the URL above in your browser.'
                    if pressed == 'c': notice = ('Code copied.' if self.attempt(lambda: self.copy_code(code)) else 'Clipboard unavailable; use the code above.') if code else 'Waiting for a device code…'
            status = int(exit_file.read_text().strip())
            propagate_cancel(status)
            if status: raise ValueError('GitHub sign-in did not complete. Retry when ready.')
            response = self.command('current', config)
            if response.returncode: raise ValueError('GitHub could not confirm the signed-in account.')
            identity = json.loads(response.stdout)
            account.update(login=identity.get('login'), id=identity.get('id'))
            if not isinstance(account['login'], str) or not self.verify(account):
                raise ValueError('GitHub did not confirm the account identity.')
            return account
        finally:
            Path(str(progress) + '.cancel').touch(mode=0o600)
            for _ in range(100):
                if exit_file.exists(): break
                time.sleep(.05)
            if exit_file.exists():
                for suffix in ('', '.cancel', '.launch', '.exit', '.exit.new'):
                    Path(str(progress) + suffix).unlink(missing_ok=True)


def select_account(client, data):
    """Choose a reusable connection or a native gh account; verify before linking."""
    notice = ''
    while True:
        rows = [('@' + a['login'] + ' · ' + a['state'], ('known', a)) for a in data['githubAccounts']]
        rows += [('Use an account already in GitHub CLI', ('native', None)),
                 ('Connect another GitHub account', ('new', None))]
        action, value = choose('GITHUB ACCOUNTS', rows,
            lambda item: [notice, 'Connect once; link to multiple identities.',
                          ('@' + item[1]['login'] + ': ' + item[1]['state']) if item[0] == 'known' else '',
                          'WorkBenches defaults do not switch gh accounts.'],
            'Enter Link  C Check  R Sign in again  N New account')
        if action == 'b': return None
        if action not in ('enter', 'c', 'r', 'n'): continue
        kind, account = value
        if action == 'c':
            if kind == 'known':
                client.verify(account); profiles.save(data)
                notice = '@' + account['login'] + ': ' + account['state']
            continue
        if action in ('r', 'n'): kind = 'new'
        if kind == 'native':
            native_accounts = client.discover()
            action, selected = choose('ACCOUNTS IN GITHUB CLI',
                [('@' + a['login'], a) for a in native_accounts],
                lambda item: ['Credentials stay in GitHub CLI.', 'Your active gh account will not change.'])
            if action != 'enter' or selected is None: continue
            account = {'login': selected['login'], 'authSource': 'native'}
        elif kind == 'new':
            try: account = client.login()
            except LoginCancelled: continue
        if not client.verify(account):
            if kind == 'known': profiles.save(data)
            notice = '@' + account['login'] + ': ' + account['state'] + '. Use Sign in again from its account details.'
            continue
        existing = next((a for a in data['githubAccounts'] if a['id'] == account['id']), None)
        if existing: existing.update(account); account = existing
        else: data['githubAccounts'].append(account)
        profiles.save(data)
        return account
