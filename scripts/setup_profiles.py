"""Personal and company identity metadata; credentials remain in provider stores."""
import json
import os
from pathlib import Path
import re
import tempfile
import time
import uuid

ROOT = Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home() / '.config'))) / 'workbenches'
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


def load():
    if STORE.is_symlink() or ROOT.is_symlink():
        raise ValueError('Profile storage must not be a symlink.')
    if not STORE.exists():
        return {'version': 1, 'personal': None, 'companies': []}
    data = json.loads(STORE.read_text())
    if not isinstance(data, dict) or data.get('version') != 1 or not isinstance(data.get('companies'), list):
        raise ValueError('Unsupported profile storage; existing data was preserved.')
    ids = set()
    for profile in ([data['personal']] if data.get('personal') else []) + data['companies']:
        if not isinstance(profile, dict):
            raise ValueError('Invalid profile record.')
        key = profile['id']
        if not re.fullmatch(r'personal|company-[a-f0-9]{32}', key) or key in ids:
            raise ValueError('Invalid or duplicate profile identity.')
        ids.add(key)
        text(profile['name']); email(profile['email'])
        github = profile.get('github')
        if github and (not isinstance(github, dict) or not isinstance(github.get('id'), int) or not re.fullmatch(r'[A-Za-z0-9-]{1,39}', github.get('login', ''))):
            raise ValueError('Invalid GitHub identity metadata.')
    if data.get('personal') and data['personal']['id'] != 'personal':
        raise ValueError('Invalid personal profile identity.')
    if any(p['id'] == 'personal' for p in data['companies']):
        raise ValueError('Company identity cannot use personal storage.')
    return data


def save(data):
    if STORE.is_symlink() or ROOT.is_symlink():
        raise ValueError('Profile storage must not be a symlink.')
    ROOT.mkdir(parents=True, exist_ok=True, mode=0o700)
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
    profile = {'id': 'company-' + uuid.uuid4().hex, 'name': name, 'email': address, 'github': None}
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
