"""Guided non-secret company enrollment; never registers clients or handles tokens."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import urllib.parse
import urllib.request

from profile_tui import choose
from setup_prompts import prompt

FIELDS = {'issuer', 'clientId', 'organizationId', 'credentialBrokerUrl'}
LIMIT = 65536
DEVICE_GRANT = 'urn:ietf:params:oauth:grant-type:device_code'


class Back(Exception):
    pass


def text(value):
    if not isinstance(value, str) or not value.strip() or len(value) > 2048 or any(not c.isprintable() for c in value):
        raise ValueError('Use a nonempty setting without control characters.')
    return value.strip()


def https(value):
    value = text(value)
    parsed = urllib.parse.urlsplit(value)
    if parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password or parsed.query or parsed.fragment:
        raise ValueError('Use a complete HTTPS issuer or broker URL without credentials, query or fragment.')
    try:
        parsed.port
    except ValueError:
        raise ValueError('Invalid HTTPS port.') from None
    return value.rstrip('/')


def descriptor(data):
    if not isinstance(data, dict) or set(data) - FIELDS or not {'issuer', 'clientId'} <= set(data):
        raise ValueError('Enrollment must contain only issuer, clientId and optional organizationId/credentialBrokerUrl; no secrets.')
    result = {'issuer': https(data['issuer']), 'clientId': text(data['clientId'])}
    if 'organizationId' in data:
        result['organizationId'] = text(data['organizationId'])
    if 'credentialBrokerUrl' in data:
        result['credentialBrokerUrl'] = https(data['credentialBrokerUrl'])
    return result


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args):
        raise ValueError('Enrollment redirects are refused; use the final administrator-provided URL.')


def read_enrollment(source):
    source = text(source)
    if source.startswith('https://'):
        parsed = urllib.parse.urlsplit(source)
        if not parsed.hostname or parsed.username or parsed.password or parsed.fragment:
            raise ValueError('Use an administrator HTTPS enrollment URL without embedded credentials or a fragment.')
        with urllib.request.build_opener(NoRedirect).open(source, timeout=15) as stream:
            raw = stream.read(LIMIT + 1)
    else:
        if '://' in source:
            raise ValueError('Enrollment URLs require HTTPS.')
        path = Path(source).expanduser()
        if path.is_symlink():
            raise ValueError('Enrollment source must not be a symlink.')
        with path.open('rb') as stream:
            raw = stream.read(LIMIT + 1)
    if len(raw) > LIMIT:
        raise ValueError('Enrollment descriptor is too large.')
    try:
        return descriptor(json.loads(raw))
    except (UnicodeError, json.JSONDecodeError):
        raise ValueError('Enrollment must be a valid non-secret JSON object.') from None


def discovery(config, request):
    config = descriptor(config)
    issuer = config['issuer']
    metadata = request(issuer + '/.well-known/openid-configuration')
    if not isinstance(metadata, dict) or metadata.get('issuer') != issuer:
        raise ValueError('Discovery issuer does not match the company issuer.')
    origin = urllib.parse.urlsplit(issuer)
    for field in ('device_authorization_endpoint', 'token_endpoint', 'userinfo_endpoint'):
        if field not in metadata:
            raise ValueError('This provider does not advertise the required device/token/userinfo endpoints. Ask your administrator for supported Keycloak-compatible setup.')
        endpoint = urllib.parse.urlsplit(https(metadata[field]))
        if (endpoint.scheme, endpoint.netloc) != (origin.scheme, origin.netloc):
            raise ValueError('Company endpoints must use the configured HTTPS server origin.')
    grants = metadata.get('grant_types_supported')
    if grants is not None and (not isinstance(grants, list) or DEVICE_GRANT not in grants):
        raise ValueError('The provider does not advertise device authorization. Ask its administrator to enable a supported public client.')
    return 'Discovery checked. Client registration is not verified until device sign-in succeeds.'


def admin_url(issuer):
    parsed = urllib.parse.urlsplit(https(issuer))
    prefix, separator, realm = parsed.path.rpartition('/realms/')
    if not separator or not realm or '/' in realm:
        return None
    return urllib.parse.urlunsplit((parsed.scheme, parsed.netloc, prefix + '/admin/', '', ''))


def instructions(issuer):
    return [
        'Register openBenches once per organization; employees reuse its enrollment.',
        'Client ID identifies the registered application, not your user, email or company ID.',
        'Keycloak lets an administrator choose the ID; other providers may generate one.',
        'Example only: openworkbenches-cli. Enter the actual registered Client ID.',
        'In the intended Keycloak realm, create an OpenID Connect public client.',
        'Client authentication: Off. OAuth 2.0 Device Authorization Grant: On.',
        'Do not enable password/direct grants or implicit flow for this CLI.',
        'No client secret belongs in the CLI or company enrollment file.',
        'Scopes: openid profile email; offline_access only for opted-in company sync.',
        'Device flow does not use a website callback redirect URI.',
        'Issuer is the HTTPS realm URL, not an admin page or browser login URL.',
        'Current support: Keycloak-compatible same-origin HTTPS device flow.',
        'Other providers require compatible endpoints; arbitrary OIDC support is not implied.',
        'Company login does not grant broker/vault access or AI-provider credentials.',
        'Issuer: ' + https(issuer),
    ]


def export_enrollment(path, config):
    data = descriptor(config)
    destination = Path(path).expanduser()
    # Resolve no symlink component; never overwrite an occupied destination.
    for part in (destination, *destination.parents):
        if part.is_symlink():
            raise ValueError('Enrollment export must not traverse symlinks.')
    if not destination.parent.is_dir():
        raise ValueError('Choose an existing directory for the enrollment export.')
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', dir=destination.parent, delete=False) as stream:
            temporary = Path(stream.name)
            json.dump(data, stream, indent=2)
            stream.write('\n'); stream.flush(); os.fsync(stream.fileno())
        # Atomic no-replace publication, unlike os.replace().
        os.link(temporary, destination)
    except FileExistsError:
        raise ValueError('Export destination already exists; choose another file.') from None
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
    return destination


def native_action(kind, value, host=None):
    active = host is not None and host.active()
    which = host.which if active else shutil.which
    run = host.run if active else subprocess.run
    if kind == 'browser':
        value = https(value)
        choices = [('wslview', [value]), ('xdg-open', [value]), ('open', [value]), ('explorer.exe', [value])]
    elif kind == 'copy':
        choices = [('wl-copy', []), ('pbcopy', []), ('xclip', ['-selection', 'clipboard']), ('clip.exe', [])]
    else:
        raise ValueError('Unknown company setup action.')
    for executable, args in choices:
        try:
            if not which(executable):
                continue
            kwargs = {'capture_output': True, 'timeout': 10}
            if kind == 'copy':
                kwargs['input'] = value.encode()
            if run([executable, *args], **kwargs).returncode == 0:
                return True
        except (OSError, subprocess.SubprocessError):
            continue
    return False


def field(label):
    value = prompt(label + ' (B Back, Q Cancel): ')
    if not value or value.lower() == 'b':
        raise Back()
    return value


def selected(title, rows, details):
    while True:
        action, value = choose(title, rows, lambda _: [line for line in details if line])
        if action in ('', 'b'):
            raise Back()
        if action in ('q', 'escape'):
            raise SystemExit(130)
        if action == 'enter':
            return value


def register_guide(issuer, host=None):
    lines = instructions(issuer)
    url = admin_url(issuer)
    if url:
        lines += ['Administration console: ' + url]
    notice = ''
    while True:
        rows = [('View full registration checklist', 'view'),
                ('I registered the application — continue', 'continue')]
        if url:
            rows.append(('Open provider administration console', 'browser'))
        rows += [('Copy registration instructions', 'copy'), ('Back', 'back')]
        value = selected('COMPANY CONNECTION · Registration guide', rows, [notice, *lines])
        if value == 'continue':
            return
        if value == 'back':
            raise Back()
        if value == 'view':
            print('\n' + '\n'.join(lines), flush=True)
            prompt('Press Enter to return to registration actions (Q cancels): ')
            continue
        if value == 'browser':
            notice = 'Administration console opened.' if native_action('browser', url, host) else 'Browser unavailable. Open the administration URL shown above.'
        elif value == 'copy':
            notice = 'Instructions copied.' if native_action('copy', '\n'.join(lines), host) else 'Clipboard unavailable. Use the instructions shown above.'


def review(config, company, root, request, write, host=None):
    config = descriptor(config)
    notice = 'Settings are not saved. Company login and credential grants are separate.'
    while True:
        details = [notice, 'Company: ' + company, 'Issuer: ' + config['issuer'],
                   'Application Client ID: ' + config['clientId'],
                   'Client ID is not your user or company ID.']
        if config.get('organizationId'):
            details.append('Organization ID: ' + config['organizationId'])
        if config.get('credentialBrokerUrl'):
            details.append('Credential broker: ' + config['credentialBrokerUrl'])
        value = selected('COMPANY CONNECTION · Review', [
            ('Check discovery and save settings', 'save'),
            ('Export non-secret company enrollment file', 'export'), ('Back', 'back')], details)
        if value == 'back':
            raise Back()
        try:
            if value == 'export':
                destination = field('New enrollment JSON file path')
                export_enrollment(destination, config)
                notice = 'Non-secret enrollment exported. Export does not verify registration or sign in.'
                continue
            notice = discovery(config, request)
            # The compact chooser can truncate details; confirmation must show
            # every allowlisted value in full before the user trusts it.
            print('\nCompany: ' + company)
            for key, setting in config.items():
                print(key + ': ' + setting)
            print(notice, flush=True)
            if prompt('Verify these settings came from your administrator. Save for this company? [y/N]: ').lower() not in ('y', 'yes'):
                continue
            write(Path(root) / 'account-provider.json', config)
            return config
        except (ValueError, OSError, KeyError, TypeError):
            notice = 'Setup could not complete. Check the enrollment, HTTPS issuer/device-flow support or export destination. Existing settings are preserved.'


def connect(root, request, write, company='Company', host=None):
    """Return confirmed config or None. Caller alone starts the existing login."""
    notice = ''
    while True:
        try:
            route = selected('COMPANY CONNECTION · ' + company, [
                ('Use company setup link or file (recommended)', 'import'),
                ('Administrator — register openBenches with my provider', 'admin'),
                ('I already have a registered application', 'existing'), ('Back without connecting', 'back')],
                [notice, 'Company registration is normally done once by an administrator.',
                 'Client ID identifies openBenches at your provider, not your user ID.',
                 'Current sign-in requires Keycloak-compatible HTTPS device flow.'])
            if route == 'back':
                return None
            try:
                if route == 'import':
                    config = read_enrollment(field('Administrator enrollment HTTPS URL or JSON file'))
                else:
                    issuer = https(field('Company HTTPS realm issuer URL'))
                    if route == 'admin':
                        register_guide(issuer, host)
                    config = descriptor({'issuer': issuer, 'clientId': field('Registered application Client ID (not your user ID)')})
                return review(config, company, root, request, write, host)
            except Back:
                continue
        except Back:
            return None
        except (OSError, ValueError, KeyError, TypeError):
            notice = 'Invalid company setup. Use administrator-provided non-secret enrollment or supported HTTPS realm/application settings; existing settings are preserved.'
