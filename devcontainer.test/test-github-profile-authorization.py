#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('authorization', Path(__file__).resolve().parents[1] / 'scripts/github_profile_authorization.py')
auth = importlib.util.module_from_spec(spec)
spec.loader.exec_module(auth)
POLICY = {'profiles': {'qa': {'organization': 'Opensoft-Testing', 'team': 'workbenches-qa-allowed'}}}
TEAM = {'organization': {'login': 'Opensoft-Testing'}, 'slug': 'workbenches-qa-allowed'}


class AuthorizationTests(unittest.TestCase):
    def get(self, teams):
        return lambda path, token: {'login': 'verified-user', 'id': 123} if path == '/user' else teams

    def test_allowed_and_denied_members(self):
        self.assertTrue(auth.authorize('token', 'qa', POLICY, self.get([TEAM]))['allowed'])
        self.assertFalse(auth.authorize('token', 'qa', POLICY, self.get([]))['allowed'])

    def test_same_team_in_wrong_org_is_denied(self):
        team = dict(TEAM, organization={'login': 'other-company'})
        self.assertFalse(auth.authorize('token', 'qa', POLICY, self.get([team]))['allowed'])

    def test_unknown_profile_never_queries_github(self):
        self.assertFalse(auth.authorize('token', 'unknown', POLICY, lambda *_: self.fail())['allowed'])

    def test_pagination_and_fresh_revocation(self):
        pages = []
        def get(path, token):
            pages.append(path)
            if path == '/user': return {'login': 'verified-user', 'id': 123}
            return [dict(TEAM, slug='unrelated')] * 100 if path.endswith('page=1') else [TEAM]
        self.assertTrue(auth.authorize('token', 'qa', POLICY, get)['allowed'])
        self.assertEqual(len(pages), 3)
        self.assertFalse(auth.authorize('token', 'qa', POLICY, self.get([]))['allowed'])

    def test_api_errors_and_invalid_membership_fail_closed(self):
        def unavailable(*_): raise auth.AuthorizationUnavailable('unavailable')
        for get in [unavailable, self.get({}), self.get([{}])]:
            with self.assertRaises(auth.AuthorizationUnavailable):
                auth.authorize('token', 'qa', POLICY, get)

    def test_page_limit_fails_closed(self):
        with self.assertRaises(auth.AuthorizationUnavailable):
            auth.authorize('token', 'qa', POLICY, self.get([TEAM] * 100))


if __name__ == '__main__': unittest.main()
