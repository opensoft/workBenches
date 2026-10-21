import unittest
from unittest.mock import patch
import controller

class QueueTests(unittest.TestCase):
    def config(self): return dict(pools=[dict(repositories=['example/project'])],profiles=[dict(labels=['eagle-linux-ubuntu24'],image='immutable')])
    def test_only_matching_queued_jobs_are_selected(self):
        def api(path):
            if '/jobs?' in path: return dict(jobs=[dict(id=7,status='queued',labels=['eagle-linux-ubuntu24'])])
            return dict(workflow_runs=[dict(id=3,created_at='2026-10-21T00:00:00Z')]) if 'status=queued' in path else dict(workflow_runs=[])
        with patch.object(controller,'api',side_effect=api):
            selected=controller.queued(self.config())
            self.assertEqual(selected[3:],('example/project',3,7))
    def test_unrelated_labels_and_waiting_jobs_do_not_take_capacity(self):
        for status,labels in [('waiting',['eagle-linux-ubuntu24']),('queued',['windows-latest']),('in_progress',['eagle-linux-ubuntu24'])]:
            def api(path):
                if '/jobs?' in path: return dict(jobs=[dict(id=7,status=status,labels=labels)])
                return dict(workflow_runs=[dict(id=3,created_at='2026-10-21T00:00:00Z')])
            with self.subTest(status=status,labels=labels),patch.object(controller,'api',side_effect=api):
                self.assertIsNone(controller.queued(self.config()))
    def test_busy_registration_is_not_deleted(self):
        state=dict(runner='eagle-fleet-123',organization='example')
        with patch.object(controller,'registrations',return_value=[dict(name=state['runner'],busy=True)]),patch.object(controller.backend,'call') as call:
            self.assertFalse(controller.retire(state));call.assert_not_called()

if __name__=='__main__': unittest.main()
