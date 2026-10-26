#!/usr/bin/env python3
"""Interactive Profiles page actions. No passwords or GitHub tokens are stored here."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import urllib.request
import urllib.parse

import setup_profiles as profiles
from setup_prompts import prompt, cancellation_signals, propagate_cancel

try:
    import workbenches_host as host
except ImportError:
    if os.environ.get('WORKBENCHES_HOST_RPC') or os.environ.get('OPENBENCHES_HOST_RPC'):
        raise
    host = None

HERE = Path(__file__).resolve().parent


def scrubbed_environment(*suffixes):
    env = dict(os.environ)
    for prefix in ('OPENBENCHES_', 'WORKBENCHES_', 'WB_'):
        for suffix in suffixes:
            env.pop(prefix + suffix, None)
    return env


def ai_environment(email, name, scope):
    env = scrubbed_environment('IDENTITY_EMAIL', 'IDENTITY_NAME', 'IDENTITY_SCOPE',
                               'SELECTED_PROVIDERS', 'AUTH_ROUTE', 'AUTH_ROUTE_FILE')
    env.update(OPENBENCHES_IDENTITY_EMAIL=email, OPENBENCHES_IDENTITY_NAME=name,
               OPENBENCHES_IDENTITY_SCOPE=scope,
               WORKBENCHES_IDENTITY_EMAIL=email, WORKBENCHES_IDENTITY_NAME=name,
               WORKBENCHES_IDENTITY_SCOPE=scope)
    return env


def ask(label, default=''):
    return prompt(label + (f' [{default}]' if default else '') + ': ') or default


def confirm(label):
    return ask(label + ' [y/N]').lower() in ('y', 'yes')


def connect_github(profile, data, identity=None):
    from profile_github import GitHub, select_account
    identity = identity or next(i for i in profile['identities'] if i['id'] == profile['defaultIdentityId'])
    selected = select_account(GitHub(host), data)
    if selected and confirm(f'Link verified GitHub account @{selected["login"]} to {identity["name"]}?'):
        profiles.link_github(data, identity, selected)
        profiles.save(data)


def account(profile, action):
    env = scrubbed_environment('ACCOUNT_ROOT', 'ACCOUNT_ISSUER', 'ACCOUNT_CLIENT_ID', 'ACCOUNT_OFFLINE')
    env['WORKBENCHES_ACCOUNT_ROOT'] = str(profiles.account_root(profile))
    if (profiles.account_root(profile) / 'credential-sync.json').exists():
        env['WORKBENCHES_ACCOUNT_OFFLINE'] = '1'
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
    broker = data.get('credentialBrokerUrl')
    organization_id = profiles.text(data['organizationId']) if data.get('organizationId') else None
    if broker:
        from company_sync import endpoint
        broker = endpoint(broker)
        print('Credential broker: ' + broker)
    if organization_id:
        print('Company tenant ID: ' + organization_id)
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
        config = {'issuer': issuer, 'clientId': client}
        if broker:
            config['credentialBrokerUrl'] = broker
        if organization_id:
            config['organizationId'] = organization_id
        module.write_private(root / 'account-provider.json', config)


def edit(profile, data):
    profiles.normalize(data)
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
            print('Y Company credential synchronization')
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
            profile['name'] = name
            identity = default_identity(profile)
            identity['email'] = address
            profiles.save(data)
        elif choice == 'g':
            connect_github(profile, data)
        elif choice == 'u' and confirm('Remove this GitHub link? GitHub CLI credentials will be kept'):
            identity = default_identity(profile)
            for key in list(identity['githubIds']): profiles.unlink_github(identity, key)
            profiles.save(data)
        elif choice == 'c' and company:
            print('Use this company’s administrator-provided HTTPS realm and public client ID.')
            print('Your email domain does not grant company membership. Browser approval verifies access.')
            if account(profile, []) == 0:
                address = profiles.connected_email(profiles.account_root(profile))
                if address:
                    print('Company account email: ' + address + ' (verified by sign-in server)')
                    if address != profile['email'] and confirm('Use this signed-in email for this company profile?'):
                        default_identity(profile)['email'] = address
                        profiles.save(data)
        elif choice == 'i' and company:
            enrollment(profile)
        elif choice == 'y' and company:
            result = subprocess.run([sys.executable, str(HERE / 'setup-company-sync.py'), profile['id']])
            propagate_cancel(result.returncode)
        elif choice == 's' and company:
            account(profile, ['--logout'])
        elif choice == 'a':
            print('AI provider sign-in and vault grants are separate from company/GitHub sign-in.')
            env = ai_environment(profile['email'], profile['name'],
                                 'personal' if profile['id'] == 'personal' else 'organization')
            result = subprocess.run(['bash', str(HERE / 'setup-ai-profiles.sh'), '--interactive'], env=env)
            propagate_cancel(result.returncode)


def wizard(data):
    print('Personal identity first, then any number of companies. Q cancels; saved profiles are kept.')
    if not data['personal']:
        address = profiles.email(ask('Personal email'))
        add_personal(data, 'Main', address)
        profiles.save(data)
    if not data['personal'].get('github') and confirm('Connect your personal GitHub account now?'):
        connect_github(data['personal'], data)
    while confirm('Add a company or organization?'):
        name = profiles.text(ask('Company name'))
        address = profiles.email(ask('Company email', profiles.connected_email()))
        company = profiles.add_company(data, name, address)
        profiles.save(data)
        edit(company, data)


def manage_legacy(data):
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
            address = profiles.email(ask('Company email', profiles.connected_email()))
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


def default_identity(scope):
    return next(i for i in scope['identities'] if i['id'] == scope['defaultIdentityId'])


def add_personal(data, name, address):
    if data['personal'] is None:
        identity = profiles.new_identity(name, address)
        data['personal'] = {'id': 'personal', 'name': 'Personal', 'identities': [identity],
                            'defaultIdentityId': identity['id']}
    else:
        identity = profiles.add_identity(data['personal'], name, address)
    return identity


def identity_form(scope, data):
    print('\033[H\033[2JADD ' + ('PERSONAL' if scope is None or scope['id'] == 'personal' else scope['name'].upper()) + ' IDENTITY')
    print('Name this identity, then enter its email. Q cancels; existing entries stay saved.')
    name = profiles.text(ask('Identity name (for example Main or Consulting)'))
    address = profiles.email(ask('Email', profiles.connected_email() if scope and scope['id'] != 'personal' else ''))
    identity = add_personal(data, name, address) if scope is None or scope['id'] == 'personal' else profiles.add_identity(scope, name, address)
    profiles.save(data)
    return identity


def ai_accounts(scope, identity):
    print('AI provider sign-in and vault grants are separate from identity sign-in.')
    env = ai_environment(identity['email'],
                         scope['name'] if scope['id'] != 'personal' else identity['name'],
                         'personal' if scope['id'] == 'personal' else 'organization')
    result = subprocess.run(['bash', str(HERE / 'setup-ai-profiles.sh'), '--interactive'], env=env)
    propagate_cancel(result.returncode)


def github_details(connection, data):
    from profile_tui import choose
    from profile_github import GitHub, LoginCancelled
    client = GitHub(host)
    while True:
        links = [scope['name'] + ' / ' + identity['name'] for scope in profiles.scopes(data)
                 for identity in scope['identities'] if connection['id'] in identity['githubIds']]
        action, _ = choose('@' + connection['login'], [('Check connection', 'check'), ('Sign in again', 'login')],
            lambda item: [connection['state'], 'Last checked: ' + connection.get('checkedAt', 'Not checked'),
                          'Linked to:', *links, 'Unlink from an identity to preserve other links.'])
        if action == 'b': return
        if action != 'enter': continue
        if _ == 'check':
            client.verify(connection); profiles.save(data)
        else:
            try: replacement = client.login()
            except LoginCancelled: continue
            if replacement['id'] != connection['id']:
                # A different browser account is retained as its own connection.
                existing = next((a for a in data['githubAccounts'] if a['id'] == replacement['id']), None)
                if existing: existing.update(replacement)
                else: data['githubAccounts'].append(replacement)
                profiles.save(data)
                raise ValueError('A different GitHub account was connected. Existing identity links were preserved.')
            connection.update(replacement); profiles.save(data)


def identity_menu(scope, identity, data):
    from profile_tui import choose
    while True:
        accounts = [a for a in data['githubAccounts'] if a['id'] in identity['githubIds']]
        rows = [('@' + a['login'] + (' · Default' if a['id'] == identity['defaultGithubId'] else ''), a) for a in accounts]
        action, selected = choose(scope['name'] + ' / ' + identity['name'], rows,
            lambda item: [identity['email'], 'Default identity' if scope['defaultIdentityId'] == identity['id'] else 'Additional identity',
                          '', ('@' + item['login'] + ' · ' + item['state']) if item else 'No GitHub accounts linked.',
                          'G connects or links an existing account.', 'Defaults apply inside openBenches only.'],
            'G Link GitHub  E Edit  D Default GitHub  U Unlink  A AI')
        if action == 'b': return
        if action == 'g': connect_github(scope, data, identity)
        elif action == 'enter' and selected: github_details(selected, data)
        elif action == 'd' and selected:
            identity['defaultGithubId'] = selected['id']; profiles.save(data)
        elif action == 'u' and selected and confirm('Unlink @' + selected['login'] + ' from this identity? Other links and gh credentials stay saved'):
            profiles.unlink_github(identity, selected['id']); profiles.save(data)
        elif action == 'e':
            name = profiles.text(ask('Identity name', identity['name']))
            address = profiles.email(ask('Email', identity['email']))
            if any(i['id'] != identity['id'] and i['email'].casefold() == address.casefold() for i in scope['identities']):
                raise ValueError('That email already belongs to an identity in this profile.')
            identity.update(name=name, email=address); profiles.save(data)
        elif action == 'a': ai_accounts(scope, identity)


def scope_menu(scope, data):
    from profile_tui import choose
    while True:
        rows = [(i['name'] + (' · Default' if i['id'] == scope['defaultIdentityId'] else ''), i) for i in scope['identities']]
        company = scope['id'] != 'personal'
        action, identity = choose(scope['name'], rows,
            lambda item: [item['email'], f'{len(item["githubIds"])} linked GitHub accounts',
                          'Enter to edit identity and GitHub links.',
                          'Company sign-in is separate from GitHub.' if company else 'Your personal identities stay separate from companies.'],
            'A Add identity  D Default' + ('  C Sign in  I Enrollment  Y Sync  S Sign out  E Rename' if company else ''))
        if action == 'b': return
        if action == 'enter': identity_menu(scope, identity, data)
        elif action == 'a': identity_menu(scope, identity_form(scope, data), data)
        elif action == 'd': scope['defaultIdentityId'] = identity['id']; profiles.save(data)
        elif company and action == 'e':
            name = profiles.text(ask('Company name', scope['name']))
            profiles.add_company({'companies': [s for s in data['companies'] if s['id'] != scope['id']]}, name, scope['email'])
            scope['name'] = name; profiles.save(data)
        elif company and action == 'i': enrollment(scope)
        elif company and action == 's': account(scope, ['--logout'])
        elif company and action == 'y':
            result = subprocess.run([sys.executable, str(HERE / 'setup-company-sync.py'), scope['id']])
            propagate_cancel(result.returncode)
        elif company and action == 'c' and account(scope, []) == 0:
            address = profiles.connected_email(profiles.account_root(scope))
            if address and not any(i['email'].casefold() == address.casefold() for i in scope['identities']):
                if confirm('Add verified signed-in email ' + address + ' to ' + scope['name'] + '?'):
                    profiles.add_identity(scope, 'Signed-in account', address); profiles.save(data)


def manage(data):
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        return manage_legacy(data)
    from profile_tui import choose, clean
    notice = ''
    # Atomic v1->v2 migration on first interactive open; save keeps a private v1 backup.
    profiles.save(data)
    while True:
        rows = []
        for scope in profiles.scopes(data):
            rows.append((scope['name'], ('scope', scope, None)))
            for identity in scope['identities']:
                rows.append(('  ' + identity['name'] + (' · Default' if identity['id'] == scope['defaultIdentityId'] else ''), ('identity', scope, identity)))
                for connection in data['githubAccounts']:
                    if connection['id'] in identity['githubIds']:
                        rows.append(('    @' + connection['login'], ('github', scope, connection)))
        rows += [('+ Add personal identity', ('personal', None, None)),
                 ('+ Add company', ('company', None, None)), ('GitHub account library', ('library', None, None))]
        def detail(row):
            kind, scope, value = row
            if kind == 'identity': return [scope['name'] + ' / ' + value['name'], value['email'], f'{len(value["githubIds"])} GitHub accounts', notice]
            if kind == 'scope': return [scope['name'], f'{len(scope["identities"])} email identities', 'Default: ' + default_identity(scope)['email'], notice]
            if kind == 'github': return ['@' + value['login'], value['state'], 'Connected once; reusable across profiles.', notice]
            return ['A Add personal identity', 'C Add company', 'G Connect/link GitHub']
        action, row = choose('PROFILES · Personal and companies', rows, lambda row: ([notice] if notice else []) + detail(row), 'A Add personal  C Add company  G GitHub accounts  L Workstation account')
        if action == 'b': return
        try:
            kind, scope, value = row
            if action == 'a' or action == 'enter' and kind == 'personal':
                identity = identity_form(data['personal'], data); identity_menu(data['personal'], identity, data)
            elif action == 'c' or action == 'enter' and kind == 'company':
                name = profiles.text(ask('Company name'))
                address = profiles.email(ask('Company email', profiles.connected_email()))
                scope = profiles.add_company(data, name, address); profiles.save(data); scope_menu(scope, data)
            elif action == 'g' or action == 'enter' and kind == 'library':
                from profile_github import GitHub, select_account
                connection = select_account(GitHub(host), data)
                if connection:
                    targets = [(s['name'] + ' / ' + i['name'], (s, i)) for s in profiles.scopes(data) for i in s['identities']]
                    choice, target = choose('LINK @' + connection['login'], targets, lambda item: ['Choose the identity that uses this account.', 'B keeps it in the library without a link.'])
                    if choice == 'enter' and target:
                        profiles.link_github(data, target[1], connection); profiles.save(data)
            elif action == 'l':
                result = subprocess.run([sys.executable, str(HERE / 'setup-workbenches-account.py')])
                propagate_cancel(result.returncode)
            elif action == 'enter':
                if kind == 'scope': scope_menu(scope, data)
                elif kind == 'identity': identity_menu(scope, value, data)
                elif kind == 'github': github_details(value, data)
            notice = ''
        except ValueError as error:
            notice = clean(str(error))[:200]
        except (OSError, KeyError, TypeError, subprocess.TimeoutExpired):
            notice = 'Action needs attention. Check setup and retry; existing connections are kept.'


def main():
    cancellation_signals()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--summary', action='store_true')
    args = parser.parse_args()
    try:
        data = profiles.load()
        if args.summary:
            print('Personal identities: ' + str(len(data['personal']['identities']) if data['personal'] else 0))
            if data['personal']: print('Default: ' + default_identity(data['personal'])['email'])
            print('GitHub accounts: ' + str(len(data['githubAccounts'])))
            print('Company profiles: ' + str(len(data['companies'])))
            for company in data['companies'][:5]:
                print(company['name'] + ': ' + str(len(company['identities'])) + ' identities')
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
