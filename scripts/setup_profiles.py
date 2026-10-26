"""Personal and company identity metadata; credentials remain in provider stores."""
import json
import os
from pathlib import Path
import re
import tempfile
import time
import uuid

from openbenches_compat import config_root

ROOT = config_root()
STORE = ROOT / 'profiles.json'


def text(value, limit=200):
    if not isinstance(value, str) or not value.strip() or len(value) > limit or any(ord(c) < 32 or ord(c) == 127 for c in value):
        raise ValueError('Enter a nonempty value without control characters (maximum %s characters).' % limit)
    return value.strip()


def email(value):
    value = text(value, 254)
    if not re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+', value):
        raise ValueError('Enter a valid email address.')
    return value


def empty():
    return {'version': 2, 'personal': None, 'companies': [], 'githubAccounts': []}


def new_identity(name, address):
    return {'id': 'identity-' + uuid.uuid4().hex, 'name': text(name),
            'email': email(address), 'githubIds': [], 'defaultGithubId': None}


def scopes(data):
    return ([data['personal']] if data.get('personal') else []) + data['companies']


def normalize(data):
    """Migrate metadata in memory; company IDs and session paths never change."""
    if not isinstance(data, dict) or data.get('version') not in (1, 2) or not isinstance(data.get('companies'), list):
        raise ValueError('Unsupported profile storage; existing data was preserved.')
    if data['version'] == 1:
        data['githubAccounts'] = []
        for scope in scopes(data):
            identity = new_identity(scope['name'], scope['email'])
            github = scope.get('github')
            if github:
                entry = next((a for a in data['githubAccounts'] if a['id'] == github['id']), None)
                if entry is None:
                    entry = {**github, 'state': 'Sign-in required', 'authSource': 'native'}
                    data['githubAccounts'].append(entry)
                identity['githubIds'] = [github['id']]
                identity['defaultGithubId'] = github['id']
            scope['identities'] = [identity]
            scope['defaultIdentityId'] = identity['id']
        data['version'] = 2
    validate(data)
    return data


def validate(data):
    if 'personal' not in data or not isinstance(data.get('githubAccounts'), list):
        raise ValueError('Invalid GitHub account list.')
    account_ids = set()
    for account in data.get('githubAccounts', []):
        if (type(account.get('id')) is not int or account['id'] <= 0 or account['id'] in account_ids
                or not re.fullmatch(r'[A-Za-z0-9-]{1,39}', account.get('login', ''))
                or account.get('state') not in ('Connected', 'Sign-in required', 'Check failed')
                or account.get('authSource') not in ('native', 'managed')):
            raise ValueError('Invalid GitHub account metadata.')
        if account['authSource'] == 'managed' and not re.fullmatch(r'github-[a-f0-9]{32}', account.get('authDirectory', '')):
            raise ValueError('Invalid GitHub credential directory.')
        account_ids.add(account['id'])
    ids, identity_ids = set(), set()
    for scope in scopes(data):
        key = scope['id']
        if not re.fullmatch(r'personal|company-[a-f0-9]{32}', key) or key in ids:
            raise ValueError('Invalid or duplicate profile identity.')
        ids.add(key); text(scope['name'])
        identities = scope['identities']
        if not isinstance(identities, list) or not identities:
            raise ValueError('Each profile needs at least one identity.')
        for identity in identities:
            key = identity['id']
            if not re.fullmatch(r'identity-[a-f0-9]{32}', key) or key in identity_ids:
                raise ValueError('Invalid or duplicate email identity.')
            identity_ids.add(key); text(identity['name']); email(identity['email'])
            links = identity['githubIds']
            if (not isinstance(links, list) or any(type(i) is not int for i in links)
                    or len(links) != len(set(links)) or not set(links) <= account_ids
                    or identity['defaultGithubId'] is not None and identity['defaultGithubId'] not in links):
                raise ValueError('Invalid GitHub identity links.')
        if scope['defaultIdentityId'] not in [i['id'] for i in identities]:
            raise ValueError('Invalid default identity.')
        project_default(scope, data)
    if data.get('personal') and data['personal']['id'] != 'personal':
        raise ValueError('Invalid personal profile identity.')
    if any(p['id'] == 'personal' for p in data['companies']):
        raise ValueError('Company identity cannot use personal storage.')


def project_default(scope, data):
    # Compatibility fields for the existing broker/AI setup consumers.
    identity = next(i for i in scope['identities'] if i['id'] == scope['defaultIdentityId'])
    scope['email'] = identity['email']
    scope['github'] = next((a for a in data['githubAccounts'] if a['id'] == identity['defaultGithubId']), None)


def load():
    if STORE.is_symlink() or ROOT.is_symlink():
        raise ValueError('Profile storage must not be a symlink.')
    return normalize(json.loads(STORE.read_text())) if STORE.exists() else empty()


def add_identity(scope, name, address):
    identity = new_identity(name, address)
    if any(i['email'].casefold() == identity['email'].casefold() for i in scope['identities']):
        raise ValueError('This email is already in this profile; edit its identity instead.')
    scope['identities'].append(identity)
    return identity


def link_github(data, identity, account):
    existing = next((a for a in data['githubAccounts'] if a['id'] == account['id']), None)
    if existing:
        existing.update(account)
    else:
        data['githubAccounts'].append(account)
    if account['id'] not in identity['githubIds']:
        identity['githubIds'].append(account['id'])
    if identity['defaultGithubId'] is None:
        identity['defaultGithubId'] = account['id']


def unlink_github(identity, key):
    identity['githubIds'].remove(key)
    if identity['defaultGithubId'] == key:
        identity['defaultGithubId'] = identity['githubIds'][0] if identity['githubIds'] else None


def save(data):
    if STORE.is_symlink() or ROOT.is_symlink():
        raise ValueError('Profile storage must not be a symlink.')
    normalize(data)
    ROOT.mkdir(parents=True, exist_ok=True, mode=0o700)
    if STORE.exists() and json.loads(STORE.read_text()).get('version') == 1:
        backup = ROOT / 'profiles.v1.json'
        try:
            descriptor = os.open(backup, os.O_CREAT | os.O_EXCL | os.O_WRONLY | os.O_NOFOLLOW, 0o600)
        except FileExistsError:
            if backup.is_symlink() or not backup.is_file() or backup.stat().st_mode & 0o077:
                raise ValueError('Existing profile backup must be a private regular file.')
        else:
            with os.fdopen(descriptor, 'w') as stream:
                stream.write(STORE.read_text()); stream.flush(); os.fsync(stream.fileno())
    with tempfile.NamedTemporaryFile(mode='w', dir=ROOT, delete=False) as stream:
        temporary = Path(stream.name)
        try:
            json.dump(data, stream, indent=2)
            stream.write('\n'); stream.flush(); os.fsync(stream.fileno())
            os.replace(temporary, STORE)
        finally:
            temporary.unlink(missing_ok=True)


def add_company(data, name, address):
    name, address = text(name), email(address)
    slug = re.sub(r'[^a-z0-9]+', '-', name.lower()).strip('-')
    if not slug or slug == 'personal':
        raise ValueError('Choose a company name distinct from Personal.')
    if any(re.sub(r'[^a-z0-9]+', '-', p['name'].lower()).strip('-') == slug for p in data['companies']):
        raise ValueError('This company name already exists; edit its profile instead.')
    identity = new_identity('Work', address)
    profile = {'id': 'company-' + uuid.uuid4().hex, 'name': name, 'email': address, 'github': None,
               'identities': [identity], 'defaultIdentityId': identity['id']}
    data['companies'].append(profile)
    return profile


def account_root(profile):
    key = profile['id']
    if not re.fullmatch(r'personal|company-[a-f0-9]{32}', key):
        raise ValueError('Invalid profile identity.')
    return ROOT / 'identities' / key


def connected_email(root=None):
    """Return only a current, provider-bound, verified email suggestion."""
    root = ROOT if root is None else root
    try:
        provider, session = root / 'account-provider.json', root / 'account-session.json'
        if root.is_symlink() or provider.is_symlink() or session.is_symlink():
            return ''
        if session.stat().st_mode & 0o077:
            return ''
        config = json.loads(provider.read_text())
        identity = json.loads(session.read_text())
        if (not identity.get('subject') or identity.get('emailVerified') is not True
                or identity.get('expiresAt', 0) <= time.time()
                or not config.get('issuer') or not config.get('clientId')
                or any(identity.get(key) != config[key] for key in ('issuer', 'clientId'))):
            return ''
        return email(identity.get('email'))
    except (OSError, ValueError, TypeError, AttributeError, KeyError):
        return ''
