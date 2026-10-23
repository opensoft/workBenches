"""Server-only fresh GitHub membership gate, bound to immutable OIDC subjects."""
import json
import os
from pathlib import Path
import re
import stat
import urllib.error
import urllib.request

from core import BrokerError


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args):
        return None


def get(path, token):
    request = urllib.request.Request('https://api.github.com' + path, headers={
        'Authorization': 'Bearer ' + token, 'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28', 'User-Agent': 'workBenches-broker'})
    try:
        with urllib.request.build_opener(NoRedirect()).open(request, timeout=10) as response:
            raw = response.read(131073)
            if len(raw) > 131072:
                raise ValueError()
            value = json.loads(raw)
            if not isinstance(value, dict):
                raise ValueError()
            return value
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return {}
        raise BrokerError(503, 'github_membership_unavailable') from None
    except (OSError, ValueError, urllib.error.URLError):
        raise BrokerError(503, 'github_membership_unavailable') from None


def token_file(path):
    try:
        path = Path(path)
        if not path.is_absolute() or any(p.is_symlink() for p in [path, *path.parents]):
            raise ValueError()
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
        with os.fdopen(fd) as stream:
            info = os.fstat(stream.fileno())
            if not stat.S_ISREG(info.st_mode) or info.st_uid not in (0, os.geteuid()) or info.st_mode & 0o077:
                raise ValueError()
            token = stream.read(16385).strip()
        if not token or len(token) > 16384 or any(c.isspace() for c in token):
            raise ValueError()
        return token
    except (OSError, ValueError, TypeError):
        raise BrokerError(503, 'github_membership_configuration_required') from None


def permitted(config, identity, rule, api=None):
    """No rights are created here: the existing OIDC grant is also required."""
    if not isinstance(rule, dict) or set(rule) != {'organization', 'team'}:
        raise BrokerError(503, 'invalid_github_team_policy')
    if not all(isinstance(v, str) and re.fullmatch(r'[A-Za-z0-9_-]{1,100}', v) for v in rule.values()):
        raise BrokerError(503, 'invalid_github_team_policy')
    api = api or get
    matches = [entry for entry in config.get('githubIdentities', [])
               if entry.get('issuer') == identity['iss'] and entry.get('subject') == identity['sub']]
    if len(matches) != 1:
        return False
    entry = matches[0]
    login, user_id = entry.get('login'), entry.get('githubId')
    if not isinstance(login, str) or not re.fullmatch(r'[A-Za-z0-9-]{1,39}', login) or type(user_id) is not int or user_id <= 0:
        raise BrokerError(503, 'invalid_github_identity_binding')
    token = token_file(config.get('githubMembershipTokenFile'))
    user = api('/users/' + login, token)
    if user.get('id') != user_id:
        return False
    membership = api('/orgs/' + rule['organization'] + '/teams/' + rule['team'] + '/memberships/' + login, token)
    return membership.get('state') == 'active'
