#!/usr/bin/env python3
"""Interactive Profiles page actions. No passwords or GitHub tokens are stored here."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import re
import urllib.request
import urllib.parse
from datetime import datetime, timezone

import setup_profiles as profiles
from setup_prompts import prompt, cancellation_signals, propagate_cancel

try:
    import workbenches_host as host
except ImportError:
    if os.environ.get('WORKBENCHES_HOST_RPC'):
        raise
    host = None

HERE = Path(__file__).resolve().parent


def ask(label, default=''):
    return prompt(label + (f' [{default}]' if default else '') + ': ') or default


def confirm(label):
    return ask(label + ' [y/N]').lower() in ('y', 'yes')


def native(argv, capture=True):
    run = host.run if host else subprocess.run
    result = run(argv, capture_output=capture, text=True, timeout=600 if not capture else 30)
    propagate_cancel(result.returncode)
    if result.returncode:
        raise ValueError('GitHub connection needs attention. Existing credentials were preserved; retry or skip.')
    return result


def connect_github(profile, data):
    which = host.which if host else shutil.which
    if not which('gh'):
        print('Install GitHub CLI (gh) on the workstation, then retry Connect GitHub. You can continue without it.')
        return
    print('GitHub credentials stay in GitHub CLI storage. Connecting may change its active GitHub account.')
    if confirm('Authorize a GitHub account in your browser? Choose No to reuse the active gh account'):
        native(['gh', 'auth', 'login', '--hostname', 'github.com', '--git-protocol', 'https', '--web'], capture=False)
    identity = json.loads(native(['gh', 'api', '--hostname', 'github.com', 'user']).stdout)
    login = profiles.text(identity['login'], 39)
    if not isinstance(identity['id'], int) or not re.fullmatch(r'[A-Za-z0-9-]{1,39}', login):
        raise ValueError('GitHub did not confirm an account identity.')
    if confirm(f'Link verified GitHub account @{login} to {profile["name"]}?'):
        profile['github'] = {'id': identity['id'], 'login': login,
                             'verifiedAt': datetime.now(timezone.utc).isoformat()}
        profiles.save(data)


def account(profile, action):
    env = dict(os.environ, WORKBENCHES_ACCOUNT_ROOT=str(profiles.account_root(profile)))
    # Global legacy deployment overrides must not redirect a different company.
    env.pop('WORKBENCHES_ACCOUNT_ISSUER', None)
    env.pop('WORKBENCHES_ACCOUNT_CLIENT_ID', None)
    result = subprocess.run([sys.executable, str(HERE / 'setup-workbenches-account.py'), *action], env=env)
    propagate_cancel(result.returncode)
    return result.returncode


def enrollment(profile):
    """Explicit administrator descriptor; never infer trust from an email domain."""
    source = ask('Administrator enrollment HTTPS URL or local JSON file')
    if not source:
        return
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *args):
            raise ValueError('Enrollment redirects are refused; use the final administrator-provided URL.')
    if source.startswith('https://'):
        parsed = urllib.parse.urlsplit(source)
        if not parsed.hostname or parsed.username or parsed.password or parsed.fragment:
            raise ValueError('Use an HTTPS enrollment URL without embedded credentials or a fragment.')
        with urllib.request.build_opener(NoRedirect).open(source, timeout=15) as response:
            raw = response.read(65537)
    else:
        with Path(source).expanduser().open('rb') as stream:
            raw = stream.read(65537)
    if len(raw) > 65536:
        raise ValueError('Enrollment descriptor is too large.')
    data = json.loads(raw)
    issuer = profiles.text(data['issuer']).rstrip('/')
    parsed = urllib.parse.urlsplit(issuer)
    if parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password or parsed.query or parsed.fragment:
        raise ValueError('Enrollment issuer must be an HTTPS realm URL.')
    client = profiles.text(data['clientId'])
    print(f'Company: {profile["name"]}\nSign-in server: {issuer}\nPublic client: {client}')
    print('Verify these settings came from your company administrator before continuing.')
    if confirm('Save these sign-in settings?'):
        root = profiles.account_root(profile)
        if root.is_symlink():
            raise ValueError('Account storage must not be a symlink.')
        root.mkdir(parents=True, exist_ok=True, mode=0o700)
        # Use the account helper’s private atomic writer without importing token data.
        import importlib.util
        spec = importlib.util.spec_from_file_location('profile_account', HERE / 'setup-workbenches-account.py')
        module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
        module.write_private(root / 'account-provider.json', {'issuer': issuer, 'clientId': client})


def edit(profile, data):
    while True:
        print(f'\n{profile["name"]} — {profile["email"]}')
        github = profile.get('github')
        print('GitHub: ' + ('@' + github['login'] + ' (verified when linked)' if github else 'Not connected'))
        company = profile['id'] != 'personal'
        if company:
            print('Company sign-in: ', end='', flush=True)
            account(profile, ['--status'])
        print('E Email/name   G Connect GitHub   U Unlink GitHub')
        if company:
            print('C Company sign-in   S Local sign-out   I Import enrollment')
        print('A AI accounts   B Back   Q Cancel')
        choice = ask('Action', 'b').lower()
        if choice == 'b':
            return
        if choice == 'e':
            name = profiles.text(ask('Display name', profile['name'])) if company else 'Personal'
            if company:
                probe = {'companies': [p for p in data['companies'] if p['id'] != profile['id']]}
                profiles.add_company(probe, name, profile['email'])
            address = profiles.email(ask('Email', profile['email']))
            profile.update(name=name, email=address); profiles.save(data)
        elif choice == 'g':
            connect_github(profile, data)
        elif choice == 'u' and confirm('Remove this GitHub link? GitHub CLI credentials will be kept'):
            profile['github'] = None; profiles.save(data)
        elif choice == 'c' and company:
            print('Use this company’s administrator-provided HTTPS realm and public client ID.')
            print('Your email domain does not grant company membership. Browser approval verifies access.')
            account(profile, [])
        elif choice == 'i' and company:
            enrollment(profile)
        elif choice == 's' and company:
            account(profile, ['--logout'])
        elif choice == 'a':
            print('AI provider sign-in and vault grants are separate from company/GitHub sign-in.')
            env = dict(os.environ, WORKBENCHES_IDENTITY_EMAIL=profile['email'],
                       WORKBENCHES_IDENTITY_NAME=profile['name'],
                       WORKBENCHES_IDENTITY_SCOPE='personal' if profile['id'] == 'personal' else 'organization')
            # Do not inherit the provider/route chosen for a different identity.
            for key in ('WORKBENCHES_SELECTED_PROVIDERS', 'WORKBENCHES_AUTH_ROUTE', 'WORKBENCHES_AUTH_ROUTE_FILE'):
                env.pop(key, None)
            result = subprocess.run(['bash', str(HERE / 'setup-ai-profiles.sh'), '--interactive'], env=env)
            propagate_cancel(result.returncode)


def wizard(data):
    print('Personal identity first, then any number of companies. Q cancels; saved profiles are kept.')
    if not data['personal']:
        address = profiles.email(ask('Personal email'))
        data['personal'] = {'id': 'personal', 'name': 'Personal', 'email': address, 'github': None}
        profiles.save(data)
    if not data['personal'].get('github') and confirm('Connect your personal GitHub account now?'):
        connect_github(data['personal'], data)
    while confirm('Add a company or organization?'):
        name = profiles.text(ask('Company name'))
        address = profiles.email(ask('Company email'))
        company = profiles.add_company(data, name, address)
        profiles.save(data)
        edit(company, data)


def manage(data):
    if not data['personal']:
        wizard(data)
    while True:
        print('\nPROFILES — Personal and company identities')
        entries = ([data['personal']] if data['personal'] else []) + data['companies']
        for index, profile in enumerate(entries, 1):
            github = profile.get('github')
            print(f'{index}. {profile["name"]} — {profile["email"]} — GitHub: ' + ('@' + github['login'] if github else 'Not linked'))
        print('A Add company   L Existing workstation account   B Back to setup   Q Cancel')
        choice = ask('Profile or action', 'b').lower()
        if choice == 'b':
            return
        if choice == 'a':
            name = profiles.text(ask('Company name'))
            address = profiles.email(ask('Company email'))
            company = profiles.add_company(data, name, address); profiles.save(data); edit(company, data)
        elif choice == 'l':
            print('Existing workstation account (not assigned to a company profile):')
            result = subprocess.run([sys.executable, str(HERE / 'setup-workbenches-account.py'), '--status'])
            propagate_cancel(result.returncode)
            if confirm('Connect the existing workstation account?'):
                result = subprocess.run([sys.executable, str(HERE / 'setup-workbenches-account.py')])
                propagate_cancel(result.returncode)
        elif choice.isdigit() and 1 <= int(choice) <= len(entries):
            edit(entries[int(choice) - 1], data)


def main():
    cancellation_signals()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--summary', action='store_true')
    args = parser.parse_args()
    try:
        data = profiles.load()
        if args.summary:
            if not data['personal']:
                print('Personal identity not configured; add it in Profiles.')
            else:
                personal = data['personal']; github = personal.get('github')
                print('Personal: ' + personal['email'])
                print('GitHub: ' + ('@' + github['login'] + ' (verified when linked)' if github else 'Not connected'))
                print(f'Company profiles: {len(data["companies"])}')
                for company in data['companies'][:5]:
                    print(company['name'] + ': ' + company['email'])
                if len(data['companies']) > 5:
                    print('Open Personal & companies to see all companies.')
            return
        # Serialize interactive changes across setup sessions. Readers use atomic snapshots.
        profiles.ROOT.mkdir(parents=True, exist_ok=True, mode=0o700)
        lock_path = profiles.ROOT / 'profiles.lock'
        descriptor = os.open(lock_path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        with os.fdopen(descriptor, 'w') as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise ValueError('Another Profiles action is running. Close it before trying again.') from None
            manage(profiles.load())
    except (OSError, ValueError, KeyError, TypeError, subprocess.TimeoutExpired) as error:
        print('Profile setup needs attention: ' + str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
