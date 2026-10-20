#!/usr/bin/env python3
"""Secret-free tests of QA renewal fail-closed and privacy contracts."""
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('sessions', ROOT / 'qa/release/github-vault-sessions.py')
sessions = importlib.util.module_from_spec(spec); spec.loader.exec_module(sessions)


class SessionTests(unittest.TestCase):
    def setUp(self):
        self.login, self.user_id = sessions.PROVISION.USERS[0]
        self.bundle = {'provider': 'github', 'clientId': sessions.PROVISION.CLIENT_ID, 'login': self.login,
                       'githubId': self.user_id, 'oauth': {'scope': 'read:org', 'refresh_token': 'fixture-old'}}

    def test_rotation_persists_intent_before_consumption(self):
        tokens = {'scope': 'read:org', 'access_token': 'fixture-new', 'refresh_token': 'fixture-rotated',
                  'expires_in': 28800, 'refresh_token_expires_in': 100000}
        with patch.object(sessions.PROVISION, 'store') as store, patch.object(sessions.PROVISION, 'request',
                side_effect=[tokens, {'id': self.user_id, 'login': self.login}]):
            result, rotated = sessions.renew(self.bundle, self.login, self.user_id, True)
        self.assertTrue(rotated); self.assertEqual(store.call_count, 2)
        intent = store.call_args_list[0].args[1]
        self.assertEqual(intent['state'], 'renewal-in-progress')
        self.assertNotIn('refresh_token', intent['oauth'])
        self.assertEqual(result['oauth']['refresh_token'], 'fixture-rotated')
        with self.assertRaises(sessions.SessionError): sessions.validate(intent, self.login, self.user_id)

    def test_invalid_refresh_never_replays(self):
        with patch.object(sessions.PROVISION, 'store') as store, patch.object(sessions.PROVISION, 'request', return_value={'error': 'bad_refresh_token'}):
            with self.assertRaises(sessions.SessionError): sessions.renew(self.bundle, self.login, self.user_id, True)
        self.assertEqual(store.call_count, 1)
        self.assertNotIn('refresh_token', store.call_args.args[1]['oauth'])

    def test_default_rotation_covers_the_next_four_hour_schedule(self):
        # This token is valid now but will be dead when the next job runs.
        # The old ten-minute window skipped it and left an availability gap.
        self.bundle['expiresAt'] = 1000 + 3 * 3600
        tokens = {'scope': 'read:org', 'access_token': 'fixture-new', 'refresh_token': 'fixture-rotated',
                  'expires_in': 28800, 'refresh_token_expires_in': 100000}
        with patch.object(sessions.time, 'time', return_value=1000), \
                patch.object(sessions.PROVISION, 'store') as store, \
                patch.object(sessions.PROVISION, 'request', side_effect=[tokens, {'id': self.user_id, 'login': self.login}]):
            result, rotated = sessions.renew(self.bundle, self.login, self.user_id)
        self.assertTrue(rotated)
        self.assertEqual(result['expiresAt'], 1000 + 28800)
        self.assertEqual(store.call_count, 2)

    def test_healthy_session_outside_the_next_run_window_is_not_rotated(self):
        self.bundle['expiresAt'] = 1000 + 8 * 3600
        with patch.object(sessions.time, 'time', return_value=1000), \
                patch.object(sessions.PROVISION, 'store') as store, patch.object(sessions.PROVISION, 'request') as request:
            result, rotated = sessions.renew(self.bundle, self.login, self.user_id)
        self.assertFalse(rotated)
        self.assertIs(result, self.bundle)
        store.assert_not_called(); request.assert_not_called()

    def test_wrong_identity_or_broad_scope_rejected(self):
        for value in [dict(self.bundle, githubId=1), dict(self.bundle, oauth={'scope': 'read:org,repo'})]:
            with self.assertRaises(sessions.SessionError): sessions.validate(value, self.login, self.user_id)

    def test_live_pagination_checks_exact_organization(self):
        self.bundle['oauth']['access_token'] = 'fixture-token'
        unrelated = {'organization': {'login': 'other-company'}, 'slug': 'workbenches-qa-allowed'}
        team = {'organization': {'login': 'Opensoft-Testing'}, 'slug': 'workbenches-qa-allowed'}
        with patch.object(sessions.PROVISION, 'request', side_effect=[{'id': self.user_id, 'login': self.login}, [unrelated]*100, [team]]):
            self.assertTrue(sessions.team_member(self.bundle))
        with patch.object(sessions.PROVISION, 'request', side_effect=[{'id': self.user_id, 'login': self.login}, [unrelated]]):
            self.assertFalse(sessions.team_member(self.bundle))


if __name__ == '__main__': unittest.main()
