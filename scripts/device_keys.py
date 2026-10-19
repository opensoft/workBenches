"""Shared, strict validation of public device metadata; no private keys."""
import base64
import hashlib
import ipaddress
import re
import struct


def text(value, limit=100):
    if not isinstance(value, str) or not value.strip() or len(value) > limit or any(ord(c) < 32 or ord(c) == 127 for c in value):
        raise ValueError('Invalid device text')
    return value.strip()


def public_key(value):
    if not isinstance(value, str) or len(value) > 256:
        raise ValueError('An Ed25519 public key is required')
    parts = value.split()
    if len(parts) < 2 or parts[0] != 'ssh-ed25519':
        raise ValueError('An Ed25519 public key is required')
    raw = base64.b64decode(parts[1], validate=True)
    expected = struct.pack('>I', 11) + b'ssh-ed25519' + struct.pack('>I', 32)
    if len(raw) != 51 or raw[:19] != expected:
        raise ValueError('Invalid Ed25519 public key')
    return 'ssh-ed25519 ' + base64.b64encode(raw).decode()


def fingerprint(value):
    raw = base64.b64decode(public_key(value).split()[1])
    return 'SHA256:' + base64.b64encode(hashlib.sha256(raw).digest()).decode().rstrip('=')


def username(value):
    if not isinstance(value, str) or not re.fullmatch(r'[a-zA-Z_][a-zA-Z0-9_.-]{0,63}', value):
        raise ValueError('Invalid SSH account name')
    if value == 'root':
        raise ValueError('Register an ordinary user account, not root')
    return value


def address(value):
    if value == '': return ''
    value = text(value, 253)
    try: ipaddress.ip_address(value)
    except ValueError:
        if not re.fullmatch(r'[a-zA-Z0-9](?:[a-zA-Z0-9.-]*[a-zA-Z0-9])?', value):
            raise ValueError('Use a hostname or IP address, without a URL or SSH options')
    return value


def metadata(data):
    port = data.get('port', 22)
    if type(port) is not int or not 1 <= port <= 65535: raise ValueError('Invalid SSH port')
    return dict(name=text(data['name']), platform=text(data['platform']), username=username(data['username']),
                publicKey=public_key(data['publicKey']), hostKey=public_key(data['hostKey']) if data.get('hostKey') else '',
                address=address(data.get('address', '')), port=port)
