"""Reviewed, scope-bound AI metadata sources. Provider credentials stay separate."""
import base64
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import time
from urllib.parse import quote, urlsplit
import urllib.error
import urllib.request

import cloud_profiles as cloud
import setup_profiles as identities
from setup_prompts import prompt, propagate_cancel
from profile_tui import choose, clean
from profile_github import GitHub, select_account

HERE = Path(__file__).resolve().parent
try:
    import workbenches_host as host
except ImportError:
    sys.path.insert(0, str(HERE.parent / 'tools-container'))
    import workbenches_host as host

PROVIDERS = cloud.PROVIDERS
LIMIT = cloud.LIMIT


def json_bytes(raw):
    if len(raw) > LIMIT:
        raise ValueError('Profile manifest exceeds the 1 MiB limit.')
    try:
        def unique(pairs):
            result = {}
            for key, value in pairs:
                if key in result: raise ValueError('Manifest contains duplicate JSON fields.')
                result[key] = value
            return result
        value = json.loads(raw, object_pairs_hook=unique)
    except (UnicodeError, json.JSONDecodeError, RecursionError):
        raise ValueError('Choose a valid UTF-8 JSON profile manifest.') from None
    if not isinstance(value, dict): raise ValueError('Profile manifest must be a JSON object.')
    return value


def local_path(value):
    value = identities.text(value, 4096)
    if re.match(r'^[A-Za-z]:[\\/]', value):
        args = ['@profile-file', 'path', value] if host.active() else ['bash', str(HERE / 'native-profile-file.sh'), 'path', value]
        result = host.run(args, capture_output=True, text=True, timeout=30)
        if result.returncode: raise ValueError('Use a Linux/WSL local path, or choose the native file dialog.')
        value = identities.text(result.stdout.rstrip('\r\n'), 4096)
    path = Path(value).expanduser().absolute()
    return str(path)


def native_file():
    args = ['@profile-file', 'pick'] if host.active() else ['bash', str(HERE / 'native-profile-file.sh'), 'pick']
    result = host.run(args, capture_output=True, text=True, timeout=300)
    if result.returncode == 1 or result.returncode == 0 and not result.stdout.strip(): return None
    if result.returncode == 3: raise ValueError('Picker unavailable; use Enter local path.')
    if result.returncode: raise ValueError('Picker failed; use Enter local path.')
    return local_path(result.stdout.rstrip('\r\n'))


def read_local(value):
    path = local_path(value)
    if host.active():
        result = host.run(['@profile-file', 'read', path], capture_output=True, timeout=30)
        if result.returncode: raise ValueError('Cannot read this host file. Choose a regular readable JSON file.')
        raw = result.stdout
    else:
        file = cloud.safe_path(path)
        if not file.is_file(): raise ValueError('Choose a regular readable JSON file.')
        with file.open('rb') as stream: raw = stream.read(LIMIT + 1)
    if len(raw) > LIMIT: raise ValueError('Profile manifest exceeds the 1 MiB limit.')
    return raw


def https_url(value):
    value = identities.text(value, 4096)
    try:
        parsed = urlsplit(value)
        port = parsed.port
    except ValueError:
        raise ValueError('Use a valid HTTPS file URL.') from None
    if (parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password
            or parsed.fragment or parsed.query or port not in (None, 443)):
        raise ValueError('Use a stable HTTPS file URL without credentials, query tokens or fragments.')
    if parsed.hostname.lower() in ('drive.google.com', 'docs.google.com', '1drv.ms', 'onedrive.live.com') or parsed.hostname.lower().endswith('.sharepoint.com'):
        raise ValueError('For this private sharing link, connect Google Drive/OneDrive and browse to the manifest instead.')
    return value


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs): return None


def read_https(value):
    url = https_url(value)
    try:
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
        with opener.open(urllib.request.Request(url, headers={'Accept': 'application/json'}), timeout=30) as response:
            if response.status != 200: raise ValueError('File server did not return a usable manifest.')
            raw = response.read(LIMIT + 1)
    except (urllib.error.URLError, OSError):
        raise ValueError('Cannot read this HTTPS file. Use its final public JSON URL, GitHub connection, or connected drive.') from None
    if len(raw) > LIMIT: raise ValueError('Profile manifest exceeds the 1 MiB limit.')
    return raw


def repository(value):
    value = identities.text(value, 300)
    if value.startswith('https://github.com/'): value = value[len('https://github.com/'):]
    if value.endswith('.git'): value = value[:-4]
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9_.-]{1,100}', value):
        raise ValueError('Enter a GitHub repository as owner/repository.')
    return value


def repository_path(value):
    value = identities.text(value, 1024)
    if value.startswith('/') or '\\' in value or any(p in ('', '.', '..') for p in value.split('/')):
        raise ValueError('Enter the manifest path within the repository, such as ai/source.json.')
    return value


def read_github(source, data, client=None):
    client = client or GitHub(host)
    account = next((a for a in data['githubAccounts'] if a['id'] == source.get('githubId')), None)
    if not account or not client.verify(account):
        raise ValueError('This source needs its saved GitHub account. Connect/check that account, then retry.')
    repo = repository(source['repository']); path = repository_path(source['path'])
    ref = identities.text(source.get('ref', 'HEAD'), 200)
    config = client.configuration(account)
    revision = client.command('profile-revision', config, account['login'], 'repos/' + repo + '/commits/' + quote(ref, safe=''))
    if revision.returncode or not re.fullmatch(r'[a-f0-9]{40}', revision.stdout.strip()):
        raise ValueError('The selected GitHub account cannot read this repository/ref. Check access and organization approval.')
    commit = revision.stdout.strip()
    def fetch(relative):
        endpoint = 'repos/' + repo + '/contents/' + quote(repository_path(relative), safe='/') + '?ref=' + commit
        result = client.command('profile-file', config, account['login'], endpoint)
        if result.returncode: raise ValueError('Cannot read the manifest or user grant with the selected GitHub account.')
        if len(result.stdout) > 2 * LIMIT: raise ValueError('GitHub manifest response is too large.')
        try:
            file = json.loads(result.stdout)
            if file['encoding'] != 'base64' or type(file['size']) is not int or not 0 <= file['size'] <= LIMIT:
                raise ValueError('Unsupported GitHub file.')
            raw = base64.b64decode(''.join(file['content'].split()), validate=True)
            if len(raw) != file['size'] or len(raw) > LIMIT: raise ValueError('Invalid GitHub file size.')
            return raw
        except (KeyError, TypeError, json.JSONDecodeError):
            raise ValueError('GitHub did not return a supported JSON file.') from None
    raw = fetch(path); value = json_bytes(raw)
    if value.get('kind') == cloud.composer.SOURCE_KIND:
        owner = value.get('owner', {})
        if not isinstance(owner, dict) or not isinstance(value.get('profiles'), dict):
            raise ValueError('Invalid registry ownership or provider list.')
        if any(not isinstance(rows, list) or any(not isinstance(row, dict) for row in rows) for rows in value['profiles'].values()):
            raise ValueError('Invalid registry profile list.')
        cloud.composer.validate_credential_contract(value, Path('source.json'))
        cloud.composer.validate_provider_parity(value, Path('source.json'))
        if owner.get('type') == 'tenant':
            grant = json_bytes(fetch(str(PurePosixPath(path).parent / 'grants' / 'users' / (account['login'] + '.json'))))
            if grant.get('version') != 1 or grant.get('user') != account['login'] or not isinstance(grant.get('profiles'), dict):
                raise ValueError('Invalid grant for the selected GitHub account.')
            authorized = {}
            for provider, rows in value.get('profiles', {}).items():
                patterns = grant['profiles'].get(provider, [])
                if not isinstance(patterns, list) or any(not isinstance(p, str) for p in patterns): raise ValueError('Invalid profile grant.')
                authorized[provider] = [row for row in rows if cloud.composer.is_allowed(row.get('name', ''), patterns)]
            value = dict(value, profiles=authorized)
        elif owner.get('type') != 'user' or owner.get('id', '').casefold() != account['login'].casefold():
            raise ValueError('This registry does not belong to the selected account or an authorized tenant.')
    return raw, value, commit


def read_source(scope, source, data):
    kind = source['kind']
    if kind == 'github': return read_github(source, data)
    if kind == 'local': raw = read_local(source['path'])
    elif kind == 'https': raw = read_https(source['path'])
    elif kind == 'cloud':
        connection = next((c for c in cloud.load(scope)['connections'] if c['id'] == source.get('connectionId')), None)
        if not connection: raise ValueError('The saved drive connection is unavailable. Connect it again.')
        raw = cloud.rclone(scope, connection, 'read', source['path'])
    else: raise ValueError('Unsupported manifest source.')
    return raw, json_bytes(raw), None


def provider_documents(value, source):
    if type(value.get('version')) is not int or value['version'] != 1: raise ValueError('Use a version 1 profile manifest.')
    rows = value.get('profiles')
    if isinstance(rows, list):
        provider = source.get('provider')
        if provider not in PROVIDERS: raise ValueError('Choose the provider for this manifest.')
        return {provider: value}
    if not isinstance(rows, dict) or set(rows) - set(PROVIDERS) - ({'omniroute'} if value.get('kind') == cloud.composer.SOURCE_KIND else set()):
        raise ValueError('Use a provider manifest or a supported multi-provider profile bundle.')
    kind = value.get('kind')
    if kind not in ('workbenches-ai-profile-bundle', cloud.composer.SOURCE_KIND):
        raise ValueError('Multi-provider files need kind workbenches-ai-profile-bundle.')
    if kind == cloud.composer.SOURCE_KIND and source['kind'] != 'github':
        raise ValueError('Import tenant registries through GitHub to check grants, or use an approved provider manifest/bundle.')
    allowed = {'version', 'kind', 'profiles'} if kind == 'workbenches-ai-profile-bundle' else {'version', 'kind', 'owner', 'credentialContractVersion', 'profiles', 'providerParity'}
    if set(value) - allowed: raise ValueError('Profile source contains unsupported metadata; credentials must remain separate.')
    if any(not isinstance(entries, list) for entries in rows.values()): raise ValueError('Provider profiles must be arrays.')
    result = {provider: {'version': 1, 'profiles': entries} for provider, entries in rows.items() if entries and provider in PROVIDERS}
    if not result: raise ValueError('No profiles are available to this account in this source.')
    return result



def metadata_row(row):
    allowed = {'name', 'email', 'family', 'aliases', 'profilePath', 'workspace', 'authentication',
               'accountId', 'credentialId', 'sourceMode', 'owner', 'plan', 'status'}
    if not isinstance(row, dict) or set(row) - allowed:
        raise ValueError('Manifest contains unsupported fields; credentials must stay separate.')
    if row.get('status', 'active') not in ('active', 'planned', 'disabled', 'retired'):
        raise ValueError('Unsupported account status.')
    if 'plan' in row: identities.text(row['plan'], 200)
    if 'owner' in row:
        owner = row['owner']
        if not isinstance(owner, dict) or set(owner) != {'id', 'type'} or owner['type'] not in ('tenant', 'user'):
            raise ValueError('Invalid account owner metadata.')
        identities.text(owner['id'], 200)
    result = {key: value for key, value in row.items() if key not in ('owner', 'plan', 'status')}
    if isinstance(result.get('authentication'), dict) and 'accountId' in result['authentication']:
        auth = dict(result['authentication'])
        account = auth.pop('accountId')
        if account != row.get('accountId'): raise ValueError('Credential reference belongs to a different account.')
        result['authentication'] = auth
    return result

def digest_file(path):
    if not path.exists(): return None
    return hashlib.sha256(path.read_bytes()).hexdigest()


def plans_for(documents, scope, selected):
    plans = {}
    for provider, document in documents.items():
        rows = [metadata_row(row) for index, row in enumerate(document['profiles']) if (provider, index) in selected]
        if not rows: continue
        payload = dict(document, profiles=rows)
        destination, merged, actual = cloud.prepare(json.dumps(payload).encode(), provider, scope)
        plans[provider] = (destination, merged, actual, digest_file(destination))
    return plans


def review(scope, source, documents):
    selected = {(p, i) for p, doc in documents.items() for i, row in enumerate(doc['profiles']) if row.get('status', 'active') == 'active'}
    notice = ''
    while True:
        plans = plans_for(documents, scope, selected)
        count = len(selected)
        rows = [('Import selected profiles (' + str(count) + ')', ('apply', None))]
        for provider, doc in documents.items():
            rows.append(('[All] ' + PROVIDERS[provider], ('provider', provider)))
            for index, profile in enumerate(doc['profiles']):
                item = (provider, index)
                rows.append((('[x] ' if item in selected else '[ ] ') + profile['name'] + (' · Planned' if profile.get('status') == 'planned' else ''), ('profile', item)))
        actual_by_key = {(p, i): row for p, plan in plans.items() for i, row in zip([j for j in range(len(documents[p]['profiles'])) if (p, j) in selected], plan[2])}
        def detail(item):
            kind, key = item
            lines = [scope['name'] + ' · Review import', source.get('repository', source['path']),
                     ', '.join(PROVIDERS[p] + ': ' + str(len(plan[2])) for p, plan in plans.items()), notice]
            if kind == 'profile':
                row = documents[key[0]]['profiles'][key[1]]
                lines = [row['email'], 'Local name: ' + actual_by_key.get(key, row)['name']] + lines
            renamed = sum(actual_by_key[key]['name'] != documents[key[0]]['profiles'][key[1]]['name'] for key in actual_by_key)
            if renamed: lines += [str(renamed) + ' local names changed to preserve existing profiles.']
            if source.get('excludedProviders'): lines += ['Not imported: ' + ', '.join(source['excludedProviders'])]
            return lines + ['Enter toggles a profile or provider.', 'Existing credentials are preserved.', 'I imports metadata; B returns without changes.']
        action, item = choose('REVIEW AI PROFILES · ' + scope['name'], rows, detail, 'I Import selected  Enter Select  B Back')
        if action == 'b': return None
        kind, key = item
        if action == 'i' or action == 'enter' and kind == 'apply':
            if plans: return plans
            notice = 'Select at least one profile.'
        elif action == 'enter' and kind == 'profile':
            selected.symmetric_difference_update({key})
        elif action == 'enter' and kind == 'provider':
            keys = {(key, i) for i in range(len(documents[key]['profiles']))}
            selected = selected - keys if keys <= selected else selected | keys


def configure(provider, destination):
    script = 'setup-claude-profiles.sh' if provider == 'claude' else 'setup-codex-profiles.sh' if provider == 'openai' else 'setup-provider-profiles.sh'
    args = ['bash', str(HERE / script), '--manifest', str(destination)]
    if provider not in ('claude', 'openai'): args += ['--provider', provider]
    result = subprocess.run(args)
    propagate_cancel(result.returncode)
    if result.returncode: raise ValueError('Launcher configuration failed. Previous manifests are restored; retry after checking setup.')


def apply(scope, source, raw, revision, plans):
    root = cloud.scope_root(scope)
    with cloud.locked(identities.ROOT / 'manifest-import'):
        backups = {}
        for destination, payload, actual, baseline in plans.values():
            cloud.safe_path(destination)
            if digest_file(destination) != baseline: raise ValueError('Profiles changed during review. Reopen the source and review again.')
            backups[destination] = destination.read_bytes() if destination.exists() else None
        state = cloud.load(scope)
        saved = dict(source, sha256=hashlib.sha256(raw).hexdigest(), importedAt=time.strftime('%Y-%m-%d %H:%M:%S UTC', time.gmtime()),
                     counts={p: len(plan[2]) for p, plan in plans.items()}, status='launchers configured')
        if revision: saved['revision'] = revision
        # Verify persistence bounds before changing any manifest.
        state['sources'] = [s for s in state['sources'] if not all(s.get(k) == saved.get(k) for k in ('kind', 'provider', 'connectionId', 'githubId', 'repository', 'path', 'ref'))]
        if source['kind'] != 'manual': state['sources'].append(saved)
        if len(json.dumps(state).encode()) > cloud.AGGREGATE_LIMIT: raise ValueError('Too many saved sources; configuration was preserved.')
        cloud.safe_path(root / 'sources.json')
        try:
            for provider, (destination, payload, actual, _) in plans.items():
                cloud.private_json(destination, payload)
                configure(provider, destination)
            if source['kind'] != 'manual': cloud.save(scope, state)
        except BaseException:
            for path, previous in backups.items():
                if previous is None: path.unlink(missing_ok=True)
                else: cloud.private_bytes(path, previous)
            raise


def import_source(scope, source, data):
    print('Reading profile metadata…', flush=True)
    raw, value, revision = read_source(scope, source, data)
    if isinstance(value.get('profiles'), list) and source.get('provider') not in PROVIDERS:
        action, provider = choose('PROVIDER IN THIS FILE', [(label, key) for key, label in PROVIDERS.items()], lambda _: ['Choose the AI provider described by this manifest.', 'Credentials will be recovered separately.'])
        if action != 'enter': return False
        source = dict(source, provider=provider)
    documents = provider_documents(value, source)
    if isinstance(value.get('profiles'), dict):
        excluded = sorted(set(value['profiles']) - set(PROVIDERS))
        if excluded: source = dict(source, excludedProviders=excluded)
    for provider, document in list(documents.items()):
        for row in document['profiles']: metadata_row(row)
        documents[provider] = dict(document, profiles=[row for row in document['profiles'] if row.get('status') not in ('disabled', 'retired')])
    documents = {p: doc for p, doc in documents.items() if doc['profiles']}
    if not documents: raise ValueError('This source has no enabled profiles to import.')
    # Validate every entry, including entries the user might later deselect.
    plans_for(documents, scope, {(p, i) for p, doc in documents.items() for i in range(len(doc['profiles']))})
    plans = review(scope, source, documents)
    if plans is None: return False
    apply(scope, source, raw, revision, plans)
    return True


def recover(scope):
    providers = []; expected = []
    for provider, filename in cloud.composer.PROVIDERS.items():
        file = identities.ROOT / filename
        rows = [row for row in cloud.read_json(file, cloud.AGGREGATE_LIMIT).get('profiles', []) if row.get('family') == scope['id']] if file.exists() else []
        if rows:
            providers.append(provider)
            if provider in ('claude', 'openai'):
                suffix = '.credentials.json' if provider == 'claude' else 'auth.json'
                expected += [{'provider': 'codex' if provider == 'openai' else provider, 'profile': row['name'],
                              'credentialPath': str(cloud.provider_root(provider) / row['profilePath'] / suffix)} for row in rows]
    eligible = [p for p in providers if p in ('claude', 'openai')]
    if not eligible: raise ValueError('Import Claude/Codex profiles first, then recover their credentials.')
    env = dict(os.environ, WORKBENCHES_SELECTED_PROVIDERS=','.join(eligible), WORKBENCHES_CREDENTIAL_SCOPE=scope['id'])
    env.pop('WORKBENCHES_AUTH_ROUTE', None); env.pop('WORKBENCHES_VAULT_SERVICE', None)
    env.pop('WORKBENCHES_SKIP_CREDENTIAL_RECOVERY', None)
    result = subprocess.run([sys.executable, str(HERE / 'setup-credential-recovery.py'), '--interactive'], env=env)
    propagate_cancel(result.returncode)
    if result.returncode: raise ValueError('Credential recovery needs attention. Existing credentials are preserved.')
    import profile_credentials
    return sum(not profile_credentials.present(row) for row in expected)



def field(scope, label, default=''):
    from profile_tui import show, message
    show(message('AI PROFILE SOURCE · ' + scope['name'],
                 [label, 'Profile metadata only; credentials are recovered separately.'], 'B Back  Q Cancel'))
    value = prompt(label + (f' [{default}]' if default else '') + ': ')
    return None if value.lower() == 'b' else value or default


def add_account(scope, identity, provider=None):
    action = 'enter'
    if provider is None: action, provider = choose('ADD AI ACCOUNT · ' + scope['name'], [(label, key) for key, label in PROVIDERS.items()],
                             lambda _: ['Create one isolated profile in ' + scope['name'] + '.', 'Import a profile file instead to add a whole account set.'])
    if action != 'enter': return
    email = field(scope, 'AI account login email', identity['email'])
    if email is None: return
    identities.email(email)
    name = field(scope, 'Profile name', 'personal-1' if scope['id'] == 'personal' else ('personal-' if scope['id'].startswith('personal-') else 'work-') + cloud.onboarding.slugify(scope['name']))
    if name is None: return
    document = {'version': 1, 'profiles': [{'name': name, 'email': email, 'family': scope['id']}]}
    raw = json.dumps(document).encode()
    documents = {provider: document}
    plans_for(documents, scope, {(provider, 0)})
    source = {'kind': 'manual', 'path': name, 'provider': provider}
    plans = review(scope, source, documents)
    if plans: apply(scope, source, raw, None, plans)


def drive_link(scope, value):
    """Offer the supported drive browser; never use a sharing URL as a token."""
    parsed = urlsplit(value)
    domain = (parsed.hostname or '').lower()
    backend = 'drive' if domain in ('drive.google.com', 'docs.google.com') else 'onedrive' if domain in ('1drv.ms', 'onedrive.live.com') or domain.endswith('.sharepoint.com') else None
    if backend is None: return None
    if parsed.scheme != 'https' or parsed.username or parsed.password:
        raise ValueError('Use an HTTPS sharing link without embedded credentials.')
    connections = [c for c in cloud.load(scope)['connections'] if c['backend'] == backend]
    rows = [('Browse ' + c['label'], c) for c in connections] + [('Connect ' + cloud.BACKENDS[backend], None)]
    action, connection = choose('FILE LINK · ' + cloud.BACKENDS[backend], rows,
        lambda _: ['Choose the file in your connected drive.', 'Sharing links are not resolved automatically.', 'The link itself and any query tokens will not be saved.'])
    if action != 'enter': return False
    if connection is None:
        label = field(scope, 'Connection label')
        if label is None: return False
        connection = cloud.connect(scope, backend, label)
    path = cloud.browse(scope, connection)
    return {'kind': 'cloud', 'path': path, 'connectionId': connection['id']} if path else False

def menu(scope, data=None, manual=None):
    data = data or identities.load()
    notice = 'Choose a source for the AI profile list.'
    while True:
        state = cloud.load(scope)
        rows = [('Choose local file…', ('picker', None)), ('Enter local path', ('local', None)),
                ('Enter HTTPS file URL', ('https', None)), ('GitHub repository', ('github', None)),
                ('Google Drive', ('connect', 'drive')), ('OneDrive', ('connect', 'onedrive'))]
        rows += [('Browse ' + c['label'], ('browse', c)) for c in state['connections']]
        rows += [('Refresh · ' + s.get('path', ''), ('refresh', s)) for s in state['sources']]
        rows += [('Recover Claude/Codex credentials', ('recover', None))]
        if manual: rows += [('Add one AI account manually', ('manual', None))]
        def detail(item):
            kind, value = item
            lines = [notice]
            if kind == 'refresh':
                lines += [value.get('repository', value['path']), 'Last import: ' + value.get('importedAt', 'Not recorded'),
                          'Profiles: ' + ', '.join(p + '=' + str(n) for p, n in value.get('counts', {}).items()), value.get('status', '')]
                if value.get('githubId'):
                    account = next((a for a in data['githubAccounts'] if a['id'] == value['githubId']), None)
                    lines += ['GitHub: @' + account['login'] if account else 'GitHub connection needs relinking.']
            elif kind == 'picker': lines += ['Browse this computer for a JSON file.', 'No web login needed.']
            elif kind == 'local': lines += ['Paste a local file path.', 'Works without a graphical desktop.']
            elif kind == 'https': lines += ['Public JSON file URL; reviewed before import.', 'For private files, use GitHub or a connected drive.']
            elif kind == 'github': lines += ['Choose a verified GitHub connection.', 'Company registries use your account grants.']
            elif kind in ('connect', 'browse'): lines += ['Browser sign-in for private drive access.', 'Browse files after connecting. Sharing URLs need this route.']
            elif kind == 'recover': lines += ['Azure device login or another supported vault.', 'Only this scope’s Claude/Codex profiles are selected.']
            return lines + ['Profile metadata and credentials are separate.', 'B returns; Q cancels setup.']
        action, item = choose('AI PROFILES · ' + scope['name'], rows, detail)
        if action == 'b': return
        if action != 'enter': continue
        kind, value = item
        try:
            if kind == 'manual': manual(); notice = 'Account setup returned. Existing profiles were preserved.'; continue
            if kind == 'recover':
                missing = recover(scope)
                notice = (str(missing) + ' profiles still need credentials. Recover or sign in separately.' if missing else 'Credentials are present. Launch a profile to verify provider access.')
                continue
            if kind == 'connect':
                label = field(scope, 'Connection label')
                if label is None: continue
                cloud.connect(scope, value, label); notice = 'Drive connection saved. Choose Browse to select your file.'; continue
            if kind == 'refresh': source = dict(value)
            elif kind == 'browse':
                path = cloud.browse(scope, value)
                if not path: continue
                source = {'kind': 'cloud', 'path': path, 'connectionId': value['id']}
            elif kind == 'github':
                account = select_account(GitHub(host), data)
                if not account: continue
                repo = field(scope, 'GitHub repository (owner/repository)')
                if repo is None: continue
                path = field(scope, 'Manifest path', 'ai/source.json')
                if path is None: continue
                ref = field(scope, 'Branch, tag or commit', 'HEAD')
                if ref is None: continue
                source = {'kind': 'github', 'githubId': account['id'], 'repository': repository(repo),
                          'path': repository_path(path), 'ref': ref}
            elif kind == 'picker':
                path = native_file()
                if path is None: notice = 'File selection cancelled. Nothing changed.'; continue
                source = {'kind': 'local', 'path': path}
            elif kind == 'local':
                path = field(scope, 'Local JSON manifest path')
                if path is None: continue
                source = {'kind': 'local', 'path': local_path(path)}
            elif kind == 'https':
                path = field(scope, 'HTTPS JSON manifest URL')
                if path is None: continue
                linked = drive_link(scope, path)
                if linked is False: continue
                source = linked or {'kind': 'https', 'path': https_url(path)}
            else: continue
            if import_source(scope, source, data): notice = 'Imported. Recover credentials if needed.'
            else: notice = 'Import cancelled. Saved profiles and credentials are unchanged.'
        except (ValueError, OSError, KeyError, TypeError, subprocess.SubprocessError) as error:
            notice = clean(str(error))[:220] if isinstance(error, ValueError) else 'Source needs attention. Check access and format, then retry; saved profiles are kept.'
