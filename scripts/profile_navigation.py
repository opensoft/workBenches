"""Profile kind → profile editor → model maker → account navigation."""
import json
import platform
import subprocess

import setup_profiles as profiles
from profile_tui import choose, clean

MAKERS = {'claude': 'Anthropic', 'openai': 'OpenAI', 'gemini': 'Google',
          'grok': 'xAI', 'glm': 'Z.ai'}
KINDS = {'personal': 'Personal', 'company': 'Company', 'workstation': 'Workstation'}
ABOUT = {
    'personal': ['Your named personal profiles and email identities.',
                 'Edit profile information, file location, GitHub links and AI profiles.'],
    'company': ['Your company profiles and work identities.',
                'Company sign-in, profile files and AI accounts are managed within each company.'],
    'workstation': ['Named configurations for this local workstation.',
                    'Edit their information, profile file location and workstation sign-in.',
                    'Remote workstation access is planned for v1.8.'],
}


def selected_index(rows, focus):
    return next((i for i, (_, value) in enumerate(rows) if value == focus), 0)


def details(record, kind, notice=''):
    return [record['name'], record.get('email', record.get('hostname', '')),
            record.get('description') or 'No description yet.',
            'Profile URL/location: ' + (record.get('profileUrl') or 'Not set'), notice]


def owner(scope, record, kind):
    return profiles.ai_scope(scope, record) if kind == 'personal' else scope


def account_rows(scope, provider):
    import cloud_profiles as cloud
    path = profiles.ROOT / cloud.composer.PROVIDERS[provider]
    if not path.exists(): return []
    return [r for r in cloud.read_json(path, cloud.AGGREGATE_LIMIT).get('profiles', [])
            if r.get('family') == scope['id']]


def ai_menu(scope, identity, data, ui):
    scope = profiles.ai_scope(scope, identity)
    focus = None
    while True:
        inventories = {p: account_rows(scope, p) for p in MAKERS}
        rows = [(label, provider) for provider, label in MAKERS.items()]
        rows += [('Import / manage AI profile sources', 'sources')]
        def about(value):
            if value == 'sources': return ['Import AI profile sets for ' + scope['name'] + '.',
                'Local file, HTTPS, GitHub, Google Drive or OneDrive.', 'Credential recovery is a separate action.']
            return [MAKERS[value], str(len(inventories[value])) + ' accounts in this profile.',
                    'Enter to list accounts from this model maker.']
        action, focus = choose('AI Profiles · ' + scope['name'], rows, about, selected=selected_index(rows, focus))
        if action == 'b': return
        if action != 'enter': continue
        if focus == 'sources':
            from profile_sources import menu, add_account
            menu(scope, data, manual=lambda: add_account(scope, identity))
        else: maker_accounts(scope, identity, data, focus)


def maker_accounts(scope, identity, data, provider):
    from profile_sources import add_account, menu
    focus = None
    while True:
        accounts = account_rows(scope, provider)
        rows = [(r['name'], r['name']) for r in accounts]
        rows += [('Import / manage sources', '@sources'), ('+ Add ' + MAKERS[provider] + ' account', '@add')]
        by_name = {r['name']: r for r in accounts}
        def about(value):
            if value == '@add': return ['Add one ' + MAKERS[provider] + ' account to ' + scope['name'] + '.']
            if value == '@sources': return ['Import accounts or recover this profile’s credentials.',
                                           'The source review lists every affected model maker.']
            row = by_name[value]
            return [MAKERS[provider] + ' · ' + row['name'], row.get('email', ''),
                    'Plan: ' + row.get('plan', 'Not specified'),
                    'Status: ' + row.get('status', 'Configured'),
                    'Enter to view this account. Credentials remain in their provider store.']
        action, focus = choose(MAKERS[provider] + ' Accounts · ' + scope['name'], rows, about,
                               selected=selected_index(rows, focus))
        if action == 'b': return
        if action != 'enter': continue
        if focus == '@add': add_account(scope, identity, provider=provider)
        elif focus == '@sources': menu(scope, data, manual=lambda: add_account(scope, identity, provider=provider))
        else:
            while True:
                key, _ = choose('AI Account · ' + focus, [('Back to accounts', None)], lambda _: about(focus))
                if key in ('b', 'enter'): break


def github_menu(scope, identity, data, ui):
    while True:
        linked = [a for a in data['githubAccounts'] if a['id'] in identity['githubIds']]
        rows = [('@' + a['login'], a) for a in linked] + [('+ Link GitHub account', None)]
        action, item = choose('GitHub Accounts · ' + identity['name'], rows,
            lambda a: ([a['state'], 'Default' if a['id'] == identity['defaultGithubId'] else 'Additional account'] if a else
                       ['Browser sign-in, or link an existing verified account.']),
            'D Set default  U Unlink')
        if action == 'b': return
        if action == 'enter':
            if item: ui['github_details'](item, data)
            else: ui['connect_github'](scope, data, identity)
        elif action == 'd' and item: identity['defaultGithubId'] = item['id']; profiles.save(data)
        elif action == 'u' and item and ui['confirm']('Unlink @' + item['login'] + '? Existing credentials will be kept'):
            profiles.unlink_github(identity, item['id']); profiles.save(data)


def email_identities(scope, data, ui):
    while True:
        rows = [(i['name'], i) for i in scope['identities']] + [('+ Add email identity', None)]
        action, identity = choose('Email Identities · ' + scope['name'], rows,
            lambda i: [i['email'], 'Default' if i['id'] == scope['defaultIdentityId'] else 'Additional identity'] if i else ['Add another email identity to this company.'],
            'D Set default')
        if action == 'b': return
        if action == 'enter':
            if identity: ui['identity_menu'](scope, identity, data)
            else: ui['identity_form'](scope, data)
        elif action == 'd' and identity: scope['defaultIdentityId'] = identity['id']; profiles.save(data)


def edit_field(record, scope, kind, field, data, ui):
    labels = {'name': 'Profile name', 'email': 'Email', 'description': 'About this profile'}
    value = ui['ask'](labels[field] + (' (- clears)' if field == 'description' else ''), record.get(field, ''))
    if field == 'description' and value == '-': value = ''
    if field == 'email':
        value = profiles.email(value)
        target = record if kind == 'personal' else ui['default_identity'](scope)
        if any(i['id'] != target['id'] and i['email'].casefold() == value.casefold() for i in scope['identities']):
            raise ValueError('That email already belongs to another profile identity.')
        target['email'] = value
    else:
        if value: profiles.text(value, 2000 if field == 'description' else 200)
        if field == 'name' and kind != 'personal':
            existing = data['companies'] if kind == 'company' else data.get('workstations', [])
            if any(p['id'] != record['id'] and p['name'].casefold() == value.casefold() for p in existing):
                raise ValueError('That profile name already exists.')
            if kind == 'company': profiles.add_company({'companies': []}, value, scope['email'])
        record[field] = value
    profiles.save(data)


def editor(scope, record, kind, data, ui):
    from profile_portability import location_menu, transfer
    focus = None; notice = ''
    while True:
        target = owner(scope, record, kind)
        rows = [('Name: ' + record['name'], 'name')]
        if kind != 'workstation': rows += [('Email: ' + (record['email'] if kind == 'personal' else scope['email']), 'email')]
        rows += [('About this profile', 'description'), ('Profile URL / location', 'location'),
                 ('Import profile', 'import'), ('Export profile', 'export')]
        if kind != 'workstation': rows += [('AI profiles', 'ai'), ('GitHub accounts', 'github')]
        if kind == 'personal': rows += [('Default personal profile' if record['id'] == scope['defaultIdentityId'] else 'Make default personal profile', 'default')]
        if kind == 'company':
            rows += [('Email identities', 'identities'), ('Company sign-in', 'login'),
                     ('Company connection setup', 'connection'), ('Import company enrollment', 'enrollment'),
                     ('Company credential synchronization', 'sync'), ('Company sign-out', 'logout')]
        if kind == 'workstation': rows += [('Workstation account', 'workstation-login')]
        descriptions = {
            'name': ['Edit the display name of this profile.'], 'email': ['Edit this profile’s email.'],
            'description': ['Edit the description shown when this profile is highlighted.'],
            'location': ['Choose the file URL/location used to import and export this profile.',
                         'Browser-connected GitHub, Google Drive and OneDrive are supported.'],
            'import': ['Read the saved location, review information and select AI accounts before importing.'],
            'export': ['Export profile and AI-account metadata only.', 'Review the destination before a local write or remote upload.', 'Passwords, tokens and sessions are excluded.'],
            'ai': ['Model maker → accounts belonging to this profile.'],
            'github': ['GitHub connections linked to this profile’s email identity.'],
            'default': ['Choose this personal profile as the default.', 'Existing AI accounts keep their original owner and credential locations.'],
            'identities': ['Manage this company’s email identities.'],
            'login': ['Sign in to this company through its registered identity provider.'],
            'connection': ['Use administrator enrollment or register the application with your provider.'],
            'enrollment': ['Import non-secret company sign-in settings.'],
            'sync': ['Explicit company credential synchronization.'], 'logout': ['Sign out of this company only.'],
            'workstation-login': ['Workstation sign-in is separate from profile files and cloud storage.'],
        }
        action, focus = choose(KINDS[kind] + ' Profile · ' + record['name'], rows,
            lambda value: details(record, kind, notice) + descriptions[value],
            selected=selected_index(rows, focus))
        if action == 'b': return
        if action != 'enter': continue
        try:
            identity = record if kind == 'personal' else ui['default_identity'](scope) if kind == 'company' else None
            if focus in ('name', 'email', 'description'): edit_field(record, scope, kind, focus, data, ui)
            elif focus == 'location': location_menu(target, record, data, ui)
            elif focus in ('import', 'export'): notice = transfer(target, record, kind, data, ui, focus)
            elif focus == 'ai': ai_menu(scope, identity, data, ui)
            elif focus == 'github': github_menu(scope, identity, data, ui)
            elif focus == 'default': scope['defaultIdentityId'] = record['id']; profiles.save(data)
            elif focus == 'identities': email_identities(scope, data, ui)
            elif focus == 'enrollment': ui['enrollment'](scope)
            elif focus in ('login', 'connection', 'logout'):
                result = ui['account'](scope, {'login': [], 'connection': ['--configure'], 'logout': ['--logout']}[focus])
                if focus == 'login' and result == 0:
                    address = profiles.connected_email(profiles.account_root(scope))
                    if address and not any(i['email'].casefold() == address.casefold() for i in scope['identities']):
                        if ui['confirm']('Add verified signed-in email ' + address + ' to ' + scope['name'] + '?'):
                            profiles.add_identity(scope, 'Signed-in account', address); profiles.save(data)
            elif focus == 'sync':
                result = subprocess.run([ui['sys'].executable, str(ui['HERE'] / 'setup-company-sync.py'), scope['id']])
                ui['propagate_cancel'](result.returncode)
            elif focus == 'workstation-login':
                env = dict(ui['os'].environ, WORKBENCHES_ACCOUNT_ROOT=str(profiles.ROOT if record.get('legacyAccount') else profiles.account_root(record)))
                for key in ('WORKBENCHES_ACCOUNT_ISSUER', 'WORKBENCHES_ACCOUNT_CLIENT_ID'): env.pop(key, None)
                result = subprocess.run([ui['sys'].executable, str(ui['HERE'] / 'setup-workbenches-account.py')], env=env)
                ui['propagate_cancel'](result.returncode)
        except (ValueError, OSError, KeyError, TypeError, subprocess.SubprocessError) as error:
            notice = clean(str(error))[:220] if isinstance(error, ValueError) else 'Action needs attention; existing profiles are kept.'


def profile_list(kind, data, ui):
    focus = None; notice = ''
    if kind == 'workstation' and not data.get('workstations'):
        record = profiles.add_workstation(data, platform.node() or 'This workstation', platform.node() or 'localhost')
        record['legacyAccount'] = True
        profiles.save(data)
    while True:
        records = (data['personal']['identities'] if data.get('personal') else []) if kind == 'personal' else data['companies'] if kind == 'company' else data.get('workstations', [])
        rows = [(r['name'], r['id']) for r in records] + [('+ Add ' + KINDS[kind].lower() + ' profile', '@add')]
        lookup = {r['id']: r for r in records}
        action, focus = choose(KINDS[kind] + ' Profiles', rows,
            lambda value: ['Add a new ' + KINDS[kind].lower() + ' profile.', notice] if value == '@add' else details(lookup[value], kind, notice),
            selected=selected_index(rows, focus))
        if action == 'b': return
        if action not in ('enter', 'a'): continue
        try:
            if focus == '@add' or action == 'a':
                if kind == 'personal': record = ui['identity_form'](None, data)
                elif kind == 'company': record = ui['company_form'](data)
                else:
                    name = profiles.text(ui['ask']('Workstation profile name'))
                    record = profiles.add_workstation(data, name, platform.node() or 'localhost'); profiles.save(data)
                focus = record['id']
            else: record = lookup[focus]
            scope = data['personal'] if kind == 'personal' else record
            editor(scope, record, kind, data, ui)
        except ValueError as error: notice = clean(str(error))[:200]


def manage(data, ui, kind=None):
    profiles.save(data)
    if kind: return profile_list(kind, data, ui)
    focus = 'personal'
    while True:
        rows = [(label, value) for value, label in KINDS.items()]
        action, focus = choose('Profiles', rows, lambda value: ABOUT[value], selected=selected_index(rows, focus))
        if action == 'b': return
        if action == 'enter': profile_list(focus, data, ui)
