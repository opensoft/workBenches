"""Broker-side GitHub team authorization. Never use a caller-supplied login/team.

The broker supplies a protected policy and the caller's delegated GitHub token.
Call authorize before retrieving any credential. API errors fail closed.
"""
import json
import urllib.error
import urllib.request


class AuthorizationUnavailable(Exception):
    """Identity or membership could not be verified; release no credential."""


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # Never forward the delegated Authorization header to another endpoint.
        return None


def github_get(path, token):
    request = urllib.request.Request('https://api.github.com' + path, headers={
        'Authorization': 'Bearer ' + token, 'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28', 'User-Agent': 'workBenches-authorization'})
    try:
        with urllib.request.build_opener(NoRedirect()).open(request, timeout=20) as response:
            return json.load(response)
    except (urllib.error.URLError, ValueError, OSError):
        raise AuthorizationUnavailable('github_verification_unavailable') from None


def authorize(token, profile, policy, get=github_get):
    """Return verified identity + decision; no cached authorization or secrets.

    Policy maps profile IDs to {organization, team}. All teams are fetched fresh;
    pagination is bounded and exceeding the bound fails closed. Unknown profiles
    are denied without an API call. This is not GitHub repository authorization.
    """
    rule = policy.get('profiles', {}).get(profile)
    if not isinstance(rule, dict) or set(rule) != {'organization', 'team'}:
        return {'allowed': False, 'reason': 'profile_not_granted'}
    if not all(isinstance(rule[k], str) and rule[k] for k in rule):
        raise AuthorizationUnavailable('invalid_server_policy')
    if not isinstance(token, str) or not token.strip():
        raise AuthorizationUnavailable('github_login_required')
    user = get('/user', token)
    if not isinstance(user, dict) or not isinstance(user.get('id'), int) or not user.get('login'):
        raise AuthorizationUnavailable('invalid_github_identity')
    expected = (rule['organization'].casefold(), rule['team'].casefold())
    allowed = False
    for page in range(1, 101):
        teams = get('/user/teams?per_page=100&page=' + str(page), token)
        if not isinstance(teams, list):
            raise AuthorizationUnavailable('invalid_github_membership')
        for team in teams:
            if not isinstance(team, dict) or not isinstance(team.get('organization'), dict):
                raise AuthorizationUnavailable('invalid_github_membership')
            org, slug = team['organization'].get('login'), team.get('slug')
            if not isinstance(org, str) or not isinstance(slug, str):
                raise AuthorizationUnavailable('invalid_github_membership')
            allowed |= (org.casefold(), slug.casefold()) == expected
        if len(teams) < 100:
            return {'allowed': allowed, 'reason': 'team_granted' if allowed else 'team_required',
                    'login': user['login'], 'githubId': user['id']}
    raise AuthorizationUnavailable('github_membership_page_limit')
