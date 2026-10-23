#!/usr/bin/env python3
"""Optional Keycloak account sign-in through a public-client device flow."""
import argparse
import contextlib
import fcntl
import json
import os
from pathlib import Path
import signal
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import webbrowser

ROOT = Path(os.environ.get('WORKBENCHES_ACCOUNT_ROOT', str(
    Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home() / '.config'))) / 'workbenches')))
CONFIG = ROOT / 'account-provider.json'
SESSION = ROOT / 'account-session.json'


def url(value):
    parsed = urllib.parse.urlsplit(value)
    if parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password or parsed.fragment:
        raise ValueError('Use an HTTPS Keycloak realm URL without credentials or a fragment.')
    return value


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args):
        raise ValueError('Account endpoints must not redirect; check your Keycloak server configuration.')


def request(endpoint, fields=None, bearer=None):
    headers = {'Accept': 'application/json'}
    if bearer:
        headers['Authorization'] = 'Bearer ' + bearer
    data = urllib.parse.urlencode(fields).encode() if fields is not None else None
    req = urllib.request.Request(url(endpoint), data=data, headers=headers)
    try:
        with urllib.request.build_opener(NoRedirect).open(req, timeout=10) as response:
            payload = response.read(65537)
    except urllib.error.HTTPError as error:
        payload = error.read(65537)
        try:
            code = json.loads(payload).get('error')
        except (ValueError, AttributeError):
            code = None
        if code in ('authorization_pending', 'slow_down', 'access_denied', 'expired_token'):
            return {'error': code}
        raise ValueError('Account server rejected the request. Check the realm and public-client device-flow settings.') from None
    if len(payload) > 65536:
        raise ValueError('Invalid account server response.')
    result = json.loads(payload)
    if not isinstance(result, dict):
        raise ValueError('Invalid account server response.')
    return result


def write_private(path, data):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    # Refuse symlink destinations; replace files atomically with private mode.
    if path.is_symlink() or path.parent.is_symlink():
        raise ValueError('Account storage must not be a symlink.')
    with tempfile.NamedTemporaryFile(mode='w', dir=path.parent, delete=False) as stream:
        temporary = Path(stream.name)
        try:
            json.dump(data, stream)
            stream.flush()
            os.fsync(stream.fileno())
            os.replace(temporary, path)
        finally:
            temporary.unlink(missing_ok=True)


@contextlib.contextmanager
def session_lock():
    root = SESSION.parent
    if root.is_symlink():
        raise ValueError('Account storage must not be a symlink.')
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    descriptor = os.open(root / 'account-sync.lock', os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    with os.fdopen(descriptor, 'w') as stream:
        fcntl.flock(stream, fcntl.LOCK_EX)
        yield


def configuration():
    data = json.loads(CONFIG.read_text()) if CONFIG.exists() else {}
    issuer = os.environ.get('WORKBENCHES_ACCOUNT_ISSUER', data.get('issuer', '')).rstrip('/')
    client = os.environ.get('WORKBENCHES_ACCOUNT_CLIENT_ID', data.get('clientId', ''))
    if not issuer or not client:
        return None
    url(issuer)
    if urllib.parse.urlsplit(issuer).query or not isinstance(client, str) or not client.strip():
        raise ValueError('Invalid Keycloak account configuration.')
    return {'issuer': issuer, 'clientId': client}


def status():
    try:
        config = configuration()
        if config is None:
            return 'not configured'
        if not SESSION.is_symlink() and SESSION.stat().st_mode & 0o077 == 0:
            session = json.loads(SESSION.read_text())
            if session.get('issuer') == config['issuer'] and session.get('clientId') == config['clientId'] and session.get('expiresAt', 0) > time.time() and session.get('subject'):
                return 'signed in'
    except FileNotFoundError:
        pass
    except (OSError, ValueError, TypeError, AttributeError):
        return 'needs configuration'
    return 'sign in'


def prompt(message):
    answer = input(message).strip()
    if answer.lower() == 'q':
        raise SystemExit(130)
    return answer


def login(config):
    issuer = config['issuer']
    metadata = request(issuer + '/.well-known/openid-configuration')
    if metadata.get('issuer') != issuer:
        raise ValueError('The account server issuer does not match your organization configuration.')
    endpoints = {}
    origin = urllib.parse.urlsplit(issuer)
    for name in ('device_authorization_endpoint', 'token_endpoint', 'userinfo_endpoint'):
        endpoint = url(metadata[name])
        parsed = urllib.parse.urlsplit(endpoint)
        if (parsed.scheme, parsed.netloc) != (origin.scheme, origin.netloc):
            raise ValueError('Account endpoints must use the configured server origin.')
        endpoints[name] = endpoint
    offline = os.environ.get('WORKBENCHES_ACCOUNT_OFFLINE') == '1'
    scope = 'openid profile email offline_access' if offline else 'openid profile email'
    device = request(endpoints['device_authorization_endpoint'], {'client_id': config['clientId'], 'scope': scope})
    verification = url(device['verification_uri'])
    if urllib.parse.urlsplit(verification).netloc != origin.netloc:
        raise ValueError('Invalid account verification URL.')
    browser_url = url(device.get('verification_uri_complete', verification))
    parsed_browser = urllib.parse.urlsplit(browser_url)
    if (parsed_browser.scheme, parsed_browser.netloc) != (origin.scheme, origin.netloc):
        raise ValueError('Invalid account verification URL.')
    print('Open this page in your browser: ' + verification, flush=True)
    print('Enter code: ' + device['user_code'], flush=True)
    print('Continue with your organization account in the browser.', flush=True)
    print('Passwords and MFA stay in your browser. Ctrl+C cancels.', flush=True)
    try:
        webbrowser.open(browser_url, new=2)
    except (OSError, webbrowser.Error):
        pass  # URL and device code above support headless workstations.
    interval = max(1, min(30, int(device.get('interval', 5))))
    deadline = time.monotonic() + min(600, max(1, int(device['expires_in'])))
    while time.monotonic() < deadline:
        time.sleep(interval)
        if time.monotonic() >= deadline:
            break
        tokens = request(endpoints['token_endpoint'], {'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
                         'client_id': config['clientId'], 'device_code': device['device_code']})
        error = tokens.get('error')
        if error == 'authorization_pending':
            continue
        if error == 'slow_down':
            interval += 5
            continue
        if error:
            raise ValueError('Account approval was declined or expired; sign-in remains optional.')
        token = tokens['access_token']
        user = request(endpoints['userinfo_endpoint'], bearer=token)
        if not isinstance(user.get('sub'), str) or not user['sub']:
            raise ValueError('The account server did not confirm a user identity.')
        lifetime = int(tokens['expires_in'])
        if lifetime <= 0:
            raise ValueError('Account session has expired; sign in again.')
        session = {**config, 'subject': user['sub'], 'accessToken': token, 'expiresAt': time.time() + lifetime}
        # Keep verified identity metadata from the authenticated userinfo call.
        # Email is a profile suggestion, never an authorization grant.
        if user.get('email_verified') is True:
            from setup_profiles import email
            try:
                session['email'] = email(user.get('email'))
                session['emailVerified'] = True
            except ValueError:
                pass
        if offline and isinstance(tokens.get('refresh_token'), str):
            session['refreshToken'] = tokens['refresh_token']
        with session_lock():
            write_private(SESSION, session)
        print('workBenches account signed in. AI tokens and vault permissions are configured separately.')
        return 0
    raise ValueError('Account approval timed out; rerun optional account setup to try again.')


def logout():
    if SESSION.is_symlink():
        raise ValueError('Account storage must not be a symlink.')
    with session_lock():
        SESSION.unlink(missing_ok=True)
    print('Signed out of workBenches on this workstation.')
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument('--status', action='store_true')
    modes.add_argument('--logout', action='store_true')
    args = parser.parse_args()
    if args.logout:
        return logout()
    if args.status:
        print(status())
        return 0
    config = configuration()
    if config is None:
        print('Optional workBenches account: your organization must provide its Keycloak realm URL and public client ID.')
        issuer = prompt('Realm HTTPS URL (Enter skips, Q cancels): ')
        if not issuer:
            print('Account setup skipped. Bench installation does not require an account.')
            return 0
        client = prompt('Public client ID (Enter skips, Q cancels): ')
        if not client:
            print('Account setup skipped.')
            return 0
        config = {'issuer': url(issuer.rstrip('/')), 'clientId': client}
        if urllib.parse.urlsplit(config['issuer']).query:
            raise ValueError('Realm URL must not contain a query.')
        write_private(CONFIG, config)
    return login(config)


def terminate(*_):
    raise SystemExit(143)


if __name__ == '__main__':
    signal.signal(signal.SIGTERM, terminate)
    try:
        raise SystemExit(main())
    except (KeyboardInterrupt, EOFError):
        raise SystemExit(130)
    except (OSError, ValueError, KeyError, TypeError, urllib.error.URLError):
        print('Account sign-in needs attention. Check your Keycloak realm, public client, HTTPS access, and device-flow configuration. Installation can continue without an account.')
        raise SystemExit(1)
