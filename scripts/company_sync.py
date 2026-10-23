"""TLS-only broker transport and private local state shared by client/CPC commands."""
import contextlib
import fcntl
import hashlib
import json
import os
from pathlib import Path
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

MAX_BYTES = 131072


class SyncError(Exception):
    def __init__(self, code, status=0):
        self.code, self.status = code, status
        super().__init__(code)


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args):
        raise SyncError('redirect_refused')


def endpoint(url):
    p = urllib.parse.urlsplit(url)
    if p.scheme != 'https' or not p.hostname or p.username or p.password or p.fragment or p.query:
        raise SyncError('https_endpoint_required')
    return url.rstrip('/')


def request(url, data=None, token=None, form=False, json_response=True):
    endpoint(url)
    headers = {'Accept': 'application/json'}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    if data is None:
        body = None
    elif form:
        body = urllib.parse.urlencode(data).encode(); headers['Content-Type'] = 'application/x-www-form-urlencoded'
    else:
        body = json.dumps(data, allow_nan=False).encode(); headers['Content-Type'] = 'application/json'
    try:
        with urllib.request.build_opener(NoRedirect).open(urllib.request.Request(url, data=body, headers=headers), timeout=15) as response:
            raw = response.read(MAX_BYTES + 1)
    except urllib.error.HTTPError as error:
        # Do not reflect remote error bodies (could contain credentials).
        raise SyncError('authorization_required' if error.code in (401, 403) else
                        'version_conflict' if error.code == 409 else 'remote_request_failed', error.code) from None
    except (OSError, urllib.error.URLError):
        raise SyncError('service_unavailable') from None
    if len(raw) > MAX_BYTES:
        raise SyncError('response_too_large')
    if not json_response:
        return {}
    try:
        result = json.loads(raw)
        if not isinstance(result, dict):
            raise ValueError()
        return result
    except ValueError:
        raise SyncError('invalid_response') from None


def safe_path(path):
    path = Path(path).expanduser().absolute()
    if any(p.is_symlink() for p in [path, *path.parents]):
        raise SyncError('symlink_storage_refused')
    return path


def read_json(path, default=None):
    path = safe_path(path)
    if not path.exists() and default is not None:
        return default
    if path.stat().st_size > MAX_BYTES:
        raise SyncError('local_file_too_large')
    try:
        result = json.loads(path.read_bytes())
        if not isinstance(result, dict):
            raise ValueError()
        return result
    except ValueError:
        raise SyncError('invalid_local_json') from None


def atomic(path, data):
    path = safe_path(path)
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    with tempfile.NamedTemporaryFile(mode='w', dir=path.parent, delete=False) as out:
        temporary = Path(out.name)
        try:
            json.dump(data, out, sort_keys=True, allow_nan=False); out.flush(); os.fsync(out.fileno())
            os.replace(temporary, path)
        finally:
            temporary.unlink(missing_ok=True)


@contextlib.contextmanager
def lock(path, nonblocking=False):
    path = safe_path(path)
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    descriptor = os.open(path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    with os.fdopen(descriptor, 'w') as out:
        try:
            fcntl.flock(out, fcntl.LOCK_EX | (fcntl.LOCK_NB if nonblocking else 0))
        except BlockingIOError:
            raise SyncError('another_sync_is_running') from None
        yield


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()).hexdigest()


def account_token(root):
    """Renew only an explicitly enabled company offline session, serialized locally."""
    root = safe_path(root)
    with lock(root / 'account-sync.lock'):
        config = read_json(root / 'account-provider.json')
        if (root / 'account-session.json').stat().st_mode & 0o077:
            raise SyncError('company_session_must_be_private')
        session = read_json(root / 'account-session.json')
        if session.get('issuer') != config['issuer'] or session.get('clientId') != config['clientId']:
            raise SyncError('company_login_required')
        if session.get('expiresAt', 0) > time.time() + 60:
            return session['accessToken']
        if not session.get('refreshToken'):
            raise SyncError('company_login_required')
        issuer = endpoint(config['issuer'])
        metadata = request(issuer + '/.well-known/openid-configuration')
        target = metadata['token_endpoint']
        if metadata.get('issuer') != issuer or urllib.parse.urlsplit(target).netloc != urllib.parse.urlsplit(issuer).netloc:
            raise SyncError('identity_endpoint_mismatch')
        # Persist consumption intent before rotating. An ambiguous response must
        # not cause another process to replay an old company refresh token.
        refresh = session.pop('refreshToken'); atomic(root / 'account-session.json', session)
        tokens = request(target, {'grant_type': 'refresh_token', 'client_id': config['clientId'], 'refresh_token': refresh}, form=True)
        if int(tokens.get('expires_in', 0)) <= 0 or not isinstance(tokens.get('access_token'), str):
            raise SyncError('company_login_required')
        session.update(accessToken=tokens['access_token'], expiresAt=time.time() + int(tokens['expires_in']))
        session['refreshToken'] = tokens.get('refresh_token', refresh)
        atomic(root / 'account-session.json', session)
        return session['accessToken']


class Client:
    def __init__(self, url, token):
        self.url, self.token = endpoint(url), token

    def call(self, route, data=None):
        return request(self.url + '/v1/' + route, data, self.token())
