"""Scoped, pull-only local/cloud provider manifest imports through Tools Rclone."""
import contextlib
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path, PurePosixPath
import re
import select
import shutil
import subprocess
import tempfile
import time
import uuid

import setup_profiles as identities
from setup_prompts import prompt, propagate_cancel
from profile_tui import choose

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('cloud_onboarding', HERE / 'onboard-ai-profiles.py')
onboarding = importlib.util.module_from_spec(spec); spec.loader.exec_module(onboarding)
composer = onboarding.COMPOSER
LIMIT = 1024 * 1024
AGGREGATE_LIMIT = 8 * LIMIT
BACKENDS = {'drive': 'Google Drive', 'onedrive': 'OneDrive'}
PROVIDERS = {'claude': 'Claude', 'openai': 'Codex', 'gemini': 'Gemini', 'grok': 'Grok', 'glm': 'GLM'}
NAME = re.compile(r'[a-z0-9][a-z0-9-]{0,79}')


def safe_path(path):
    path = Path(path).expanduser()
    if any(part.is_symlink() for part in (path, *path.parents)):
        raise ValueError('Profile storage must not traverse symlinks.')
    return path


def private_json(path, value):
    if len((json.dumps(value, indent=2) + '\n').encode()) > AGGREGATE_LIMIT:
        raise ValueError('Combined local profile metadata is too large; previous configuration is preserved.')
    path = safe_path(path)
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    composer.atomic_json(path, value)


def read_json(path, limit=LIMIT, private=False):
    path = safe_path(path)
    if private and (not path.is_file() or path.stat().st_mode & 0o077):
        raise ValueError('Connection metadata must be an owner-only file.')
    with path.open('rb') as stream: raw = stream.read(limit + 1)
    if len(raw) > limit: raise ValueError('Manifest or connection data is too large.')
    return json.loads(raw)


def scope_root(scope):
    if not re.fullmatch(r'personal|company-[a-f0-9]{32}', scope['id']):
        raise ValueError('Invalid profile scope.')
    return safe_path(identities.ROOT / 'manifest-sources' / scope['id'])


def load(scope):
    file = scope_root(scope) / 'sources.json'
    data = read_json(file, limit=AGGREGATE_LIMIT, private=True) if file.exists() else {'version': 1, 'connections': [], 'sources': []}
    if not isinstance(data, dict) or data.get('version') != 1:
        raise ValueError('Unsupported source metadata.')
    for key in ('connections', 'sources'):
        if not isinstance(data.get(key), list): raise ValueError('Invalid source metadata.')
    return data


def save(scope, data):
    private_json(scope_root(scope) / 'sources.json', data)


def connection_dir(scope, connection):
    if not re.fullmatch(r'[a-f0-9]{32}', connection['id']) or connection['backend'] not in BACKENDS:
        raise ValueError('Invalid cloud connection.')
    return safe_path(scope_root(scope) / connection['id'])


@contextlib.contextmanager
def locked(directory):
    directory = safe_path(directory)
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    descriptor = os.open(directory / 'connection.lock', os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    with os.fdopen(descriptor, 'w') as stream:
        try: fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError: raise ValueError('This cloud connection is busy; retry after the other operation.') from None
        yield


def clean_environment():
    return {k: v for k, v in os.environ.items() if not k.startswith('RCLONE_')}


def bounded(argv, limit=LIMIT, timeout=90):
    """Never reflect command output/errors; enforce a streaming memory bound."""
    process = subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, env=clean_environment())
    output = bytearray(); deadline = time.monotonic() + timeout
    try:
        while True:
            if time.monotonic() >= deadline: raise ValueError('Cloud operation timed out; saved profiles are preserved.')
            if not select.select([process.stdout], [], [], .1)[0]: continue
            chunk = os.read(process.stdout.fileno(), 65536)
            if not chunk: break
            output.extend(chunk)
            if len(output) > limit: raise ValueError('Cloud file or folder listing is too large.')
        status = process.wait(timeout=5)
        propagate_cancel(status)
        if status: raise ValueError('Cloud access failed. Check the connection or reconnect using browser sign-in.')
        return bytes(output)
    finally:
        if process.poll() is None: process.kill(); process.wait()
        process.stdout.close()


def remote_path(value):
    if (not isinstance(value, str) or not value or len(value) > 2048
            or any(not c.isprintable() for c in value) or ':' in value or '\\' in value
            or value.startswith('/') or any(p in ('', '.', '..') for p in value.split('/'))):
        raise ValueError('Choose a file within the connected drive; sharing URLs are not remote file paths.')
    return value


def provider_root(provider):
    variables = {'claude': ('CLAUDE_PROFILES_HOME', '.claude-profiles'),
                 'openai': ('CODEX_PROFILES_HOME', '.chatgpt-profiles'),
                 'gemini': ('GEMINI_PROFILES_HOME', '.gemini-profiles'),
                 'grok': ('GROK_PROFILES_HOME', '.grok-profiles'),
                 'glm': ('GLM_PROFILES_HOME', '.glm-profiles')}
    variable, default = variables[provider]
    fallback = os.environ.get('CHATGPT_PROFILES_HOME', Path.home() / default) if provider == 'openai' else Path.home() / default
    base = Path(os.environ.get(variable, fallback))
    if provider == 'grok' and not os.environ.get(variable) and base.exists() and not os.access(base, os.W_OK):
        base = Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share')) / 'workbenches/grok-profiles'
    return safe_path(base / 'profiles')


def home_key(value):
    if not isinstance(value, str) or not value or PurePosixPath(value).is_absolute() or '..' in value.split('/'):
        raise ValueError('Existing profile has an unsafe credential home; repair it before import.')
    return str(PurePosixPath(value)).casefold()


def merge_profiles(existing, incoming, provider):
    """Reserve credential directories independently of user-visible profile names."""
    if not isinstance(existing, list) or any(not isinstance(row, dict) or any(not isinstance(row.get(key), str) for key in ('name', 'email', 'family')) for row in existing):
        raise ValueError('Existing profile metadata is invalid; repair it before import.')
    merged = list(existing); actual = []; names = {}; homes = set()
    # Launcher setup creates these family directories before its legacy-home
    # migration loop. A same-named new profile would trigger a recursive copy.
    families = {row['family'].casefold() for row in [*existing, *incoming]}
    for row in existing:
        key = home_key(row.get('profilePath') or row['name'])
        if key in homes: raise ValueError('Existing profiles share a credential home; repair the manifest before import.')
        homes.add(key)
        for name in (row['name'], *row.get('aliases', [])):
            key = name.casefold()
            if key in names and names[key] is not row:
                raise ValueError('Existing profile names or aliases are ambiguous; repair the manifest before import.')
            names[key] = row
    root = provider_root(provider)
    for profile in incoming:
        preferred = profile['name']
        for suffix in range(1, 10001):
            name = preferred if suffix == 1 else f'{preferred}-{suffix}'
            existing_row = names.get(name.casefold())
            if existing_row and (existing_row.get('family'), existing_row.get('email', '').casefold()) == (profile['family'], profile['email'].casefold()):
                actual.append(existing_row); break
            relative = profile['family'] + '/' + name
            target = root / relative
            legacy = root / name
            safe_path(target.parent)
            if (existing_row or name.casefold() in families or home_key(relative) in homes or home_key(name) in homes
                    or target.exists() or target.is_symlink() or legacy.exists() or legacy.is_symlink()): continue
            added = dict(profile, name=name, profilePath=relative,
                         aliases=[a for a in profile.get('aliases', []) if a.casefold() != name.casefold() and a.casefold() not in names])
            merged.append(added); actual.append(added); homes.add(home_key(relative))
            for key in (name, *added['aliases']): names[key.casefold()] = added
            break
        else: raise ValueError('Could not allocate an unused profile home safely.')
    return merged, actual


def rclone(scope, connection, operation, path=''):
    directory = connection_dir(scope, connection)
    config = directory / 'rclone.conf'
    if config.is_symlink() or not config.is_file() or config.stat().st_mode & 0o077:
        raise ValueError('Cloud authorization is missing or not private; reconnect.')
    argv = ['rclone', '--config', str(config), '--log-level', 'ERROR', '--retries', '1', '--low-level-retries', '1']
    if path: remote_path(path)
    if operation == 'list': args = ['lsjson', 'cloud:' + path, '--max-depth', '1']
    elif operation == 'read': args = ['cat', 'cloud:' + remote_path(path), '--head', str(LIMIT + 1)]
    else: raise ValueError('Unsupported cloud operation.')
    with locked(directory): return bounded([*argv, *args])


def connect(scope, backend, label):
    if backend not in BACKENDS: raise ValueError('Unsupported cloud provider.')
    apps_file = identities.ROOT / 'cloud-profile-apps.json'
    apps = read_json(apps_file, private=True) if apps_file.exists() else {}
    if not isinstance(apps, dict) or set(apps) - set(BACKENDS):
        raise ValueError('Invalid administrator cloud app settings.')
    app = apps.get(backend, {})
    if not isinstance(app, dict) or set(app) - {'client_id', 'client_secret'}:
        raise ValueError('Invalid administrator cloud app settings.')
    if backend == 'drive' and not (app.get('client_id') and app.get('client_secret')):
        raise ValueError('Google Drive needs an administrator OAuth app in cloud-profile-apps.json. See docs/cloud-profile-import.md.')
    if any(not isinstance(v, str) or not v or len(v) > 4096 or any(not c.isprintable() for c in v) for v in app.values()):
        raise ValueError('Invalid cloud application settings.')
    rpc = os.environ.get('WORKBENCHES_HOST_RPC')
    if not rpc: raise ValueError('Connect from setup in the updated Tools container so the native browser is available.')
    root = scope_root(scope); root.mkdir(parents=True, exist_ok=True, mode=0o700)
    connection = {'id': uuid.uuid4().hex, 'backend': backend, 'label': identities.text(label)}
    destination = connection_dir(scope, connection)
    destination.mkdir(mode=0o700)
    name = 'workbenches-cloud-login-' + connection['id']
    complete = False
    try:
        if app: private_json(destination / 'app.json', app)
        tools = os.environ.get('WORKBENCHES_TOOLS_CONTAINER', 'workbenches-tools')
        if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]*', tools):
            raise ValueError('Invalid Tools container name.')
        image = bounded(['docker', 'inspect', tools, '--format', '{{.Image}}'], limit=256, timeout=15).decode().strip()
        if not re.fullmatch(r'sha256:[a-f0-9]{64}', image): raise ValueError('Start the updated Tools container first.')
        args = ['docker', 'run', '--rm', '--interactive', '--name', name,
                '--user', f'{os.getuid()}:{os.getgid()}', '--read-only', '--cap-drop', 'ALL',
                '--security-opt', 'no-new-privileges', '--tmpfs', '/tmp:rw,nosuid,nodev,mode=1777,size=32m',
                '--publish', '127.0.0.1:53682:53682', '--workdir', str(destination), '--env', f'HOME={destination}',
                '--mount', f'type=bind,src={destination},dst={destination}',
                '--mount', f'type=bind,src={rpc},dst={rpc}', '--env', f'WORKBENCHES_HOST_RPC={rpc}']
        if os.isatty(0) and os.isatty(1): args += ['--tty']
        args += ['--entrypoint', 'python3', image, '/opt/workbenches/rclone_login.py', str(destination), backend]
        print('Opening a temporary browser login. Return here after approval.', flush=True)
        result = subprocess.run(args, env=clean_environment(), timeout=900)
        propagate_cancel(result.returncode)
        if result.returncode: raise ValueError('Cloud connection was not completed. Previous connections are preserved.')
        config = destination / 'rclone.conf'
        if not config.is_file() or config.is_symlink() or config.stat().st_mode & 0o077:
            raise ValueError('Provider did not save private authorization.')
        state = load(scope); state['connections'].append(connection); save(scope, state)
        complete = True
        return connection
    finally:
        try:
            subprocess.run(['docker', 'rm', '-f', name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15)
        except (OSError, subprocess.SubprocessError):
            pass
        (destination / 'app.json').unlink(missing_ok=True)
        if not complete: shutil.rmtree(destination, ignore_errors=True)


def selected(title, rows, details=(), actions=''):
    action, value = choose(title, rows, lambda _: list(details), actions)
    if action in ('b', ''): return None
    return (action, value)


def browse(scope, connection):
    path = ''
    while True:
        entries = json.loads(rclone(scope, connection, 'list', path))
        if not isinstance(entries, list) or len(entries) > 2000: raise ValueError('Folder listing is too large.')
        rows = [('.. Back', None)]
        for entry in entries:
            value = remote_path(entry['Path'])
            if '/' in value: raise ValueError('Invalid folder entry.')
            rows.append((('[Folder] ' if entry['IsDir'] else '') + value, entry))
        choice = selected(BACKENDS[connection['backend']] + ' · ' + (path or '/'), rows,
                          ['Choose a JSON profile manifest.', 'P enters a path in this drive.'], 'P Enter path')
        if choice is None: return None
        action, item = choice
        if action == 'p': return remote_path(prompt('Manifest path within this drive (Q cancels): '))
        if action != 'enter': continue
        if item is None:
            if not path: return None
            path = str(PurePosixPath(path).parent)
            if path == '.': path = ''
        else:
            full = '/'.join(p for p in (path, item['Path']) if p)
            if item['IsDir']: path = full
            else: return remote_path(full)


def prepare(raw, provider, scope):
    if provider not in PROVIDERS or len(raw) > LIMIT: raise ValueError('Invalid or oversized provider manifest.')
    data = json.loads(raw)
    if not isinstance(data, dict) or set(data) - {'version', 'profiles', 'families'} or data.get('version') != 1:
        raise ValueError('Use a version 1 provider manifest with a profiles array.')
    rows = data.get('profiles')
    if not isinstance(rows, list) or not 1 <= len(rows) <= 2000: raise ValueError('Manifest needs 1–2000 profiles.')
    allowed = {'name', 'email', 'family', 'aliases', 'profilePath', 'workspace', 'authentication', 'accountId', 'credentialId', 'sourceMode'}
    incoming = []; seen = set(); incoming_names = set()
    family = 'personal' if scope['id'] == 'personal' else scope['id']
    for row in rows:
        if not isinstance(row, dict) or set(row) - allowed: raise ValueError('Manifest contains unsupported fields; credentials must stay separate.')
        if not NAME.fullmatch(row.get('name', '')) or row['name'] in seen: raise ValueError('Invalid or duplicate profile name.')
        seen.add(row['name']); identities.email(row.get('email', ''))
        aliases = row.get('aliases', [])
        if not isinstance(aliases, list) or any(not isinstance(a, str) or not NAME.fullmatch(a) for a in aliases):
            raise ValueError('Invalid profile alias.')
        values = [row['name'], *aliases]
        if len(values) != len(set(values)) or incoming_names.intersection(values):
            raise ValueError('Imported names or aliases conflict.')
        incoming_names.update(values)
        authentication = row.get('authentication')
        if authentication is not None and (not isinstance(authentication, dict) or set(authentication) - {'type', 'credentialRef', 'escrowStatus'}):
            raise ValueError('Manifest authentication must contain references only.')
        for key in ('accountId', 'credentialId', 'sourceMode'):
            if key in row and (not isinstance(row[key], str) or len(row[key]) > 512 or any(not c.isprintable() for c in row[key])):
                raise ValueError('Invalid profile metadata.')
        profile = composer.validate_profile(dict(row, family=family), provider, Path('imported-manifest.json'))
        profile.update(family=family, workspace=scope['name'], profilePath=f'{family}/{profile["name"]}')
        incoming.append(profile)
    destination = safe_path(identities.ROOT / composer.PROVIDERS[provider])
    existing = read_json(destination, limit=AGGREGATE_LIMIT) if destination.exists() else {'version': 1, 'profiles': [], 'families': []}
    merged, actual = merge_profiles(existing['profiles'], incoming, provider)
    # Validate global aliases before any launcher script receives the manifest.
    names = set()
    for row in merged:
        values = {value.casefold() for value in (row['name'], *row.get('aliases', []))}
        if names.intersection(values): raise ValueError('Imported profile names or aliases conflict with existing profiles.')
        names.update(values)
    result = dict(existing, version=1, profiles=merged,
                  families=list(dict.fromkeys([*existing.get('families', []), family])))
    if len((json.dumps(result, indent=2) + '\n').encode()) > AGGREGATE_LIMIT:
        raise ValueError('Combined local profile metadata is too large; previous configuration is preserved.')
    return destination, result, actual


def import_source(scope, source, connection=None):
    if source['kind'] == 'local':
        path = safe_path(source['path'])
        with path.open('rb') as stream: raw = stream.read(LIMIT + 1)
    elif source['kind'] == 'cloud' and connection:
        raw = rclone(scope, connection, 'read', source['path'])
    else: raise ValueError('Invalid manifest source.')
    destination, payload, incoming = prepare(raw, source['provider'], scope)
    from profile_tui import clean
    print('Source: ' + clean((connection['label'] + ' / ' if connection else '') + source['path']))
    print(f'Import into {scope["name"]}: {len(incoming)} {PROVIDERS[source["provider"]]} profiles.')
    print('Existing matching profiles are kept; new names may be suffixed to preserve other accounts.')
    for row in incoming: print(f'  {row["name"]} · {row["email"]}')
    print('Profile metadata only. AI sign-in and vault access remain separate.')
    if prompt('Merge and configure local launchers? [y/N]: ').lower() not in ('y', 'yes'): return False
    private_json(destination, payload)
    state = load(scope)
    source = dict(source, sha256=hashlib.sha256(raw).hexdigest(), status='metadata imported')
    state['sources'] = [s for s in state['sources'] if not all(s.get(k) == source.get(k) for k in ('kind', 'provider', 'connectionId', 'path'))]
    state['sources'].append(source); save(scope, state)
    provider = source['provider']
    script = 'setup-claude-profiles.sh' if provider == 'claude' else 'setup-codex-profiles.sh' if provider == 'openai' else 'setup-provider-profiles.sh'
    args = ['bash', str(HERE / script), '--manifest', str(destination)]
    if provider not in ('claude', 'openai'): args += ['--provider', provider]
    result = subprocess.run(args)
    propagate_cancel(result.returncode)
    if result.returncode: raise ValueError('Metadata imported; launcher setup needs retry. Existing credentials are preserved.')
    source['status'] = 'launchers configured'; save(scope, state)
    print('Profiles imported and launchers configured. Credentials were not downloaded.')
    return True


def menu(scope):
    notice = ''
    while True:
        state = load(scope)
        rows = [('Import local JSON file', ('local', None)),
                ('Connect Google Drive', ('connect', 'drive')), ('Connect OneDrive', ('connect', 'onedrive'))]
        rows += [('Browse ' + c['label'], ('browse', c)) for c in state['connections']]
        rows += [('Pull again: ' + s['path'], ('pull', s)) for s in state['sources']]
        choice = selected(scope['name'] + ' · Profile manifest files', rows,
                          [notice, 'Connect in your browser; browse and pull a provider manifest.', 'Q cancels. B returns. No remote writes.'],
                          'P Enter path for selected drive')
        if choice is None: return
        action, (kind, value) = choice
        if action != 'enter' and not (action == 'p' and kind == 'browse'): continue
        try:
            if kind == 'connect':
                connect(scope, value, prompt('Connection label (Q cancels): ')); notice = 'Connection saved for this profile.'; continue
            connection = value if kind == 'browse' else None
            if kind == 'pull':
                source = value
                if source['kind'] == 'cloud':
                    connection = next((c for c in state['connections'] if c['id'] == source['connectionId']), None)
                    if not connection: raise ValueError('Reconnect this source before pulling.')
            else:
                if connection:
                    path = remote_path(prompt('Manifest path within this drive (Q cancels): ')) if action == 'p' else browse(scope, connection)
                else: path = prompt('Local provider manifest JSON path (Q cancels): ')
                if not path: continue
                choice = selected('Provider in this manifest', [(v, k) for k, v in PROVIDERS.items()])
                if choice is None: continue
                if choice[0] != 'enter': continue
                source = {'kind': 'cloud' if connection else 'local', 'provider': choice[1], 'path': path}
                if connection: source['connectionId'] = connection['id']
            import_source(scope, source, connection); notice = 'Import complete. Provider authentication remains separate.'
        except ValueError as error:
            from profile_tui import clean
            notice = clean(str(error))[:240]
            print(notice); prompt('Press Enter to return (Q cancels): ')
        except (OSError, KeyError, TypeError, subprocess.SubprocessError):
            notice = 'Action needs attention. Check app configuration, source format or cloud access; existing credentials are kept.'
            print(notice); prompt('Press Enter to return (Q cancels): ')
