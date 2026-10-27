"""Reviewed, metadata-only profile import/export over bound source connections."""
import base64
import copy
import hashlib
import json
import os
from pathlib import Path
import re
import tempfile
from urllib.parse import quote

import cloud_profiles as cloud
import profile_sources as sources
import setup_profiles as profiles
from profile_github import GitHub, select_account
from profile_tui import choose

KIND = 'openbenches-profile'
PROFILE_FIELDS = {'type', 'name', 'email', 'description', 'profileUrl'}


def digest(raw): return hashlib.sha256(raw).hexdigest()


def safe_account(value, provider, family):
    sources.metadata_row(value)
    authentication = value.get('authentication')
    if authentication is not None and (not isinstance(authentication, dict) or set(authentication) - {'type', 'credentialRef', 'escrowStatus'}):
        raise ValueError('Portable files may contain credential references only, never secrets.')
    return cloud.composer.validate_profile(dict(value, family=family), provider, Path('profile.json'))


def label(source):
    if source['kind'] == 'github': return 'https://github.com/' + source['repository'] + '/blob/' + source['ref'] + '/' + source['path']
    if source['kind'] == 'cloud': return 'drive://' + source['connectionId'] + '/' + source['path']
    return source['path']


def location_menu(scope, record, data, ui):
    rows = [('Local file path', 'local'), ('Public HTTPS file URL', 'https'),
            ('GitHub repository', 'github'), ('Google Drive', 'drive'), ('OneDrive', 'onedrive')]
    action, kind = choose('Profile URL / Location', rows, lambda value: [
        'Save a stable location for ' + record['name'] + '.',
        'Private sources use the selected browser connection.',
        'Export to HTTPS creates a local file; no generic web upload.'])
    if action != 'enter': return
    def ask(name, default=''):
        result = ui['ask'](name + ' (B Back)', default)
        return None if result.lower() == 'b' else result
    if kind in ('local', 'https'):
        value = ask('Profile file path' if kind == 'local' else 'HTTPS profile URL', record.get('profileUrl', ''))
        if value is None: return
        if kind == 'https':
            linked = sources.drive_link(scope, value)
            if linked is False: return
            source = linked or {'kind': kind, 'path': sources.https_url(value)}
        else: source = {'kind': kind, 'path': sources.local_path(value)}
    elif kind == 'github':
        account = select_account(GitHub(sources.host), data)
        if not account: return
        repo = ask('Repository (owner/repository)')
        if repo is None: return
        path = ask('Profile JSON path', 'profiles/profile.json')
        if path is None: return
        ref = ask('Branch', 'main')
        if ref is None: return
        source = {'kind': 'github', 'githubId': account['id'], 'repository': sources.repository(repo),
                  'path': sources.repository_path(path), 'ref': branch(ref)}
    else:
        state = cloud.load(scope)
        options = [(c['label'], c) for c in state['connections'] if c['backend'] == kind]
        options += [('+ Connect ' + cloud.BACKENDS[kind], None)]
        selected, connection = choose(cloud.BACKENDS[kind] + ' Connection', options,
            lambda c: ['Use this saved browser connection.' if c else 'Connect in your browser; no pasted tokens.'])
        if selected != 'enter': return
        if connection is None:
            name = ask('Connection label')
            if name is None: return
            connection = cloud.connect(scope, kind, name)
        path = cloud.browse(scope, connection, create=True)
        if not path: return
        source = {'kind': 'cloud', 'connectionId': connection['id'], 'path': path}
    # A changed source has no stale reviewed remote baseline.
    record.update(location=source, profileUrl=label(source))
    record.pop('sourceDigest', None)
    profiles.save(data)


def branch(value):
    value = profiles.text(value, 200)
    if (re.fullmatch(r'[a-f0-9]{40}', value) or value in ('HEAD', '@') or value.startswith(('-', '/', '.'))
            or value.endswith(('/', '.', '.lock')) or any(x in value for x in ('..', '@{', '//'))
            or re.search(r'[\s~^:?*\[\\]', value)):
        raise ValueError('Export needs a branch name, not HEAD, a tag or commit.')
    return value


def document(scope, record, kind):
    from profile_navigation import MAKERS, account_rows
    info = {'type': kind, 'name': record['name'], 'description': record.get('description', '')}
    if kind != 'workstation': info['email'] = record.get('email', scope['email'])
    if record.get('location', {}).get('kind') == 'https': info['profileUrl'] = record['profileUrl']
    accounts = {}
    if kind != 'workstation':
        for provider in MAKERS:
            rows = []
            for row in account_rows(scope, provider):
                # Never export machine paths, sessions or arbitrary extension fields.
                value = {k: row[k] for k in ('name', 'email', 'aliases', 'plan', 'status', 'owner', 'accountId', 'credentialId', 'sourceMode', 'authentication') if k in row}
                safe_account(value, provider, scope['id'])
                rows.append(value)
            if rows: accounts[provider] = rows
    value = {'version': 1, 'kind': KIND, 'profile': info, 'aiProfiles': accounts}
    validate(value, kind)
    raw = (json.dumps(value, indent=2) + '\n').encode()
    if len(raw) > cloud.LIMIT: raise ValueError('Export exceeds the profile file size limit.')
    return raw


def validate(value, kind):
    if (not isinstance(value, dict) or set(value) != {'version', 'kind', 'profile', 'aiProfiles'}
            or type(value['version']) is not int or value['version'] != 1 or value['kind'] != KIND):
        raise ValueError('Use an openBenches portable profile file. Import provider manifests from AI profiles.')
    info = value['profile']
    if not isinstance(info, dict) or set(info) - PROFILE_FIELDS or info.get('type') != kind:
        raise ValueError('This file belongs to a different profile type or contains unsupported fields.')
    profiles.text(info.get('name'))
    if info.get('description'): profiles.text(info['description'], 2000)
    if info.get('profileUrl'): sources.https_url(info['profileUrl'])
    if kind != 'workstation': profiles.email(info.get('email'))
    accounts = value['aiProfiles']
    if not isinstance(accounts, dict) or set(accounts) - set(cloud.PROVIDERS) or kind == 'workstation' and accounts:
        raise ValueError('Unsupported AI model maker or workstation AI metadata.')
    for provider, rows in accounts.items():
        if not isinstance(rows, list): raise ValueError('AI profiles must be account lists.')
        for row in rows:
            if not isinstance(row, dict) or 'profilePath' in row or 'family' in row:
                raise ValueError('Portable accounts cannot redirect credential paths or ownership.')
            safe_account(row, provider, 'personal')
    return info


def github_base(source, data, client):
    account = next((a for a in data['githubAccounts'] if a['id'] == source['githubId']), None)
    if not account or not client.verify(account): raise ValueError('Reconnect the saved GitHub account before exporting.')
    repository = sources.repository(source['repository']); path = sources.repository_path(source['path'])
    ref = branch(source['ref']); endpoint = 'repos/' + repository + '/contents/' + quote(path, safe='/')
    result = client.command('profile-export-base', client.configuration(account), account['login'], endpoint + '?ref=' + quote(ref, safe=''))
    if result.returncode == 44: return account, endpoint, None, None
    if result.returncode: raise ValueError('Cannot inspect the export destination with this GitHub account.')
    try:
        file = json.loads(result.stdout)
        if file['encoding'] != 'base64' or not re.fullmatch(r'[a-f0-9]{40,64}', file['sha']): raise ValueError()
        raw = base64.b64decode(''.join(file['content'].split()), validate=True)
        if len(raw) > cloud.LIMIT or file['size'] != len(raw): raise ValueError()
        return account, endpoint, file['sha'], raw
    except (ValueError, KeyError, TypeError): raise ValueError('Invalid GitHub destination metadata.') from None


def local_export(path, raw, baseline):
    path = cloud.safe_path(sources.local_path(path))
    if path.exists():
        if baseline is None or digest(sources.read_local(str(path))) != baseline:
            raise ValueError('The local file changed during review; review it again.')
        # Replacement is explicit; symlinks and special files are refused above.
        cloud.private_json(path, json.loads(raw))
    else:
        if baseline is not None: raise ValueError('The export destination changed during review.')
        fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, 'wb') as stream: stream.write(raw); stream.flush(); os.fsync(stream.fileno())


def export(scope, record, kind, data, ui):
    raw = document(scope, record, kind)
    source = dict(record['location'])
    if source['kind'] == 'https':
        path = ui['ask']('Local export file (B Back)', str(Path.home() / ('openbenches-' + kind + '-profile.json')))
        if path.lower() == 'b': return 'Export cancelled.'
        source = {'kind': 'local', 'path': sources.local_path(path)}
    client = GitHub(sources.host); connection = None; sha = None
    if source['kind'] == 'github':
        account, endpoint, sha, previous = github_base(source, data, client)
    elif source['kind'] == 'local':
        path = cloud.safe_path(source['path'])
        previous = sources.read_local(str(path)) if path.exists() else None
    else:
        connection = next((c for c in cloud.load(scope)['connections'] if c['id'] == source['connectionId']), None)
        if not connection: raise ValueError('The saved cloud connection needs relinking.')
        if connection.get('access') != 'write':
            if not ui['confirm']('Reconnect in your browser with file-write permission for explicit exports?'):
                return 'Export cancelled; read-only connection retained.'
            connection = cloud.connect(scope, connection['backend'], connection['label'] + ' · Export', write=True)
            path = cloud.browse(scope, connection, create=True)
            if not path: return 'Export cancelled; original profile location retained.'
            source['connectionId'] = connection['id']
            source['path'] = path
        previous = cloud.file_contents(scope, connection, source['path'])
    baseline = digest(previous) if previous is not None else None
    existing_info = None
    if previous is not None:
        try:
            existing = json.loads(previous)
            if existing != {}: existing_info = validate(existing, kind)
        except (ValueError, TypeError, KeyError):
            raise ValueError('Choose an empty JSON file or a matching portable profile. Export cannot replace a provider manifest, tenant registry or unrelated document.') from None
    old_digest = record.get('sourceDigest') if source == record.get('location') else None
    if old_digest and old_digest != baseline:
        raise ValueError('The saved source changed since import/export. Import or choose the location again before overwriting.')
    lines = [record['name'], label(source), 'Update existing file' if previous is not None else 'Create new file',
             str(len(raw)) + ' bytes of profile/AI-account metadata. No tokens or sessions.']
    if existing_info: lines += ['Existing profile: ' + existing_info['name'] + ' · ' + existing_info.get('email', '')]
    if source['kind'] == 'cloud': lines += ['Drive checks content before upload; concurrent external writes can still race.']
    action, _ = choose('Review Profile Export', [('Export to this destination', True), ('Cancel', False)], lambda _: lines)
    if action != 'enter' or _ is not True: return 'Export cancelled.'
    if source['kind'] == 'github':
        current = github_base(source, data, client)
        if current[2] != sha: raise ValueError('Remote profile changed during review. Review it again.')
        body = {'message': 'Update openBenches profile metadata', 'branch': branch(source['ref']),
                'content': base64.b64encode(raw).decode()}
        if sha: body['sha'] = sha
        with tempfile.NamedTemporaryFile(mode='w', dir=cloud.scope_root(scope)) as stream:
            json.dump(body, stream); stream.flush()
            result = client.command('profile-put', client.configuration(account), account['login'], endpoint, stream.name)
        if result.returncode: raise ValueError('GitHub refused the update. Check write access, branch rules and remote changes.')
    elif source['kind'] == 'cloud': cloud.publish(scope, connection, source['path'], raw, baseline)
    else: local_export(source['path'], raw, baseline)
    if source['kind'] == 'cloud': record.update(location=source, profileUrl=label(source))
    if source == record.get('location'): record['sourceDigest'] = digest(raw); profiles.save(data)
    return 'Profile exported to ' + label(source)


def import_profile(scope, record, kind, data, ui):
    source = record['location']
    raw, value, revision = sources.read_source(scope, source, data)
    info = validate(value, kind)
    documents = {p: {'version': 1, 'profiles': [r for r in rows if r.get('status') not in ('disabled', 'retired')]}
                 for p, rows in value['aiProfiles'].items()}
    documents = {p: d for p, d in documents.items() if d['profiles']}
    plans = None
    if documents:
        sources.plans_for(documents, scope, {(p, i) for p, doc in documents.items() for i in range(len(doc['profiles']))})
        plans = sources.review(scope, source, documents)
        if plans is None: return 'Import cancelled.'
    action, confirm = choose('Review Profile Import', [('Import selected profile', True), ('Cancel', False)],
        lambda _: [info['name'], info.get('email', ''), info.get('description', ''),
                   'AI model makers: ' + (', '.join(documents) or 'None'),
                   'Disabled/retired AI accounts are not imported.',
                   'Keep this profile’s local identity, sign-in connections and file location.'])
    if action != 'enter' or not confirm: return 'Import cancelled.'
    current = sources.read_source(scope, source, data)
    if digest(current[0]) != digest(raw): raise ValueError('Remote profile changed during review. Import it again.')
    before = copy.deepcopy(record)
    target = record if kind == 'personal' else next((i for i in scope.get('identities', []) if i['id'] == scope['defaultIdentityId']), None)
    identity_before = copy.deepcopy(target)
    try:
        if kind != 'personal':
            entries = data['companies'] if kind == 'company' else data.get('workstations', [])
            if any(p['id'] != record['id'] and p['name'].casefold() == info['name'].casefold() for p in entries):
                raise ValueError('The imported profile name already exists.')
        record.update(name=info['name'], description=info.get('description', ''))
        if kind != 'workstation':
            if any(i['id'] != target['id'] and i['email'].casefold() == info['email'].casefold() for i in scope['identities']):
                raise ValueError('That email already belongs to another identity.')
            target['email'] = info['email']
        record['sourceDigest'] = digest(raw)
        profiles.save(data)
        if plans: sources.apply(scope, dict(kind='manual', path='portable-profile'), raw, revision, plans)
    except BaseException:
        record.clear(); record.update(before)
        if target is not None and target is not record:
            # Reacquire company identity after restoring its containing record.
            target = next(i for i in record['identities'] if i['id'] == identity_before['id'])
            target.clear(); target.update(identity_before)
        profiles.save(data)
        raise
    return 'Profile imported. Credentials and existing sign-in connections were kept.'


def transfer(scope, record, kind, data, ui, action):
    if not record.get('location'):
        location_menu(scope, record, data, ui)
        if not record.get('location'): return 'No profile location selected.'
    cloud.scope_root(scope).mkdir(parents=True, exist_ok=True, mode=0o700)
    return export(scope, record, kind, data, ui) if action == 'export' else import_profile(scope, record, kind, data, ui)
