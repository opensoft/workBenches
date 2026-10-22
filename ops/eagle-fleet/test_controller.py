import unittest
from unittest.mock import patch,Mock
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
        for status,labels in [('waiting',['eagle-linux-ubuntu24']),('queued',['windows-latest']),('queued',['self-hosted','eagle-linux-ubuntu24']),('in_progress',['eagle-linux-ubuntu24'])]:
            def api(path):
                if '/jobs?' in path: return dict(jobs=[dict(id=7,status=status,labels=labels)])
                return dict(workflow_runs=[dict(id=3,created_at='2026-10-21T00:00:00Z')])
            with self.subTest(status=status,labels=labels),patch.object(controller,'api',side_effect=api):
                self.assertIsNone(controller.queued(self.config()))
    def test_busy_registration_is_not_deleted(self):
        state=dict(runner='eagle-fleet-123',organization='example',listener_stopped=True)
        with patch.object(controller,'registrations',return_value=[dict(name=state['runner'],busy=True)]),patch.object(controller.backend,'call') as call:
            self.assertFalse(controller.retire(state));call.assert_not_called()
    def test_idle_api_read_is_not_permission_to_remove_live_listener(self):
        with patch.object(controller,'registrations') as registrations,patch.object(controller.backend,'call') as call:
            with self.assertRaisesRegex(RuntimeError,'Listener exit'): controller.retire(dict(runner='eagle-fleet-123'))
            registrations.assert_not_called();call.assert_not_called()
    def test_repository_pages_are_collected(self):
        with patch.object(controller,'api',side_effect=[dict(repositories=[dict(id=i) for i in range(100)]),dict(repositories=[dict(id=100)])]) as api:
            self.assertEqual(len(controller.pages('example/repositories','repositories')),101)
            self.assertIn('page=2',api.call_args.args[0])
    def test_active_idle_listener_is_preserved_without_forced_deletion(self):
        state=dict(engine='private',runner='eagle-fleet-123',exec_id='exact',job_assigned=False,maximum_job_seconds=27000,hook_acknowledged=True)
        with patch.object(controller.backend,'inspect',return_value={'State':{'Running':True}}),patch.object(controller,'registrations',return_value=[dict(name=state['runner'],busy=False)]),patch.object(controller.backend,'inner',return_value=Mock(returncode=0)),patch.object(controller.backend,'listener_status',return_value={'Running':True}),patch.object(controller.time,'sleep',side_effect=RuntimeError('poll boundary')),patch.object(controller.backend,'remove') as remove,patch.object(controller,'retire') as retire:
            with self.assertRaisesRegex(RuntimeError,'poll boundary'): controller.monitor(state)
            remove.assert_not_called();retire.assert_not_called()
    def test_job_deadline_is_enforced_before_private_daemon_calls(self):
        state=dict(engine='private',runner='eagle-fleet-123',job_assigned=True,deadline=40)
        with patch.object(controller.time,'time',return_value=50),patch.object(controller,'event'),patch.object(controller,'save'),patch.object(controller.backend,'remove') as remove,patch.object(controller.backend,'inspect') as inspect:
            controller.monitor(state)
            remove.assert_called_once_with('private');inspect.assert_not_called()
    def test_job_hook_is_acknowledged_only_after_deadline_is_persisted(self):
        state=dict(engine='private',runner='eagle-fleet-123',exec_id='exact',job_assigned=False,maximum_job_seconds=100)
        order=[]
        def command(*args,**kwargs):
            if 'touch' in args:
                self.assertTrue(state['job_assigned']);self.assertEqual(state['deadline'],150)
                order.append('ack')
            return Mock(returncode=0)
        with patch.object(controller.time,'time',return_value=50),patch.object(controller.backend,'inspect',return_value={'State':{'Running':True}}),patch.object(controller.backend,'inner',side_effect=command),patch.object(controller,'save',side_effect=lambda s:order.append('save')),patch.object(controller,'registrations',side_effect=RuntimeError('after ack')):
            with self.assertRaisesRegex(RuntimeError,'after ack'): controller.monitor(state)
        self.assertEqual(order[:2],['save','ack']);self.assertTrue(state['hook_acknowledged'])

    def test_get_retries_a_transient_cli_failure(self):
        with patch.object(controller.backend,'call',side_effect=[Mock(returncode=1),Mock(returncode=0,stdout='{"ok":true}')]) as call,patch.object(controller.time,'sleep'):
            self.assertEqual(controller.api('example'),{'ok':True})
            self.assertEqual(call.call_count,2)

    def test_mutation_is_never_retried_after_uncertain_response(self):
        with patch.object(controller.backend,'call',return_value=Mock(returncode=1)) as call,patch.object(controller.time,'sleep'):
            with self.assertRaises(controller.ApiUnavailable):controller.api('example','POST',{})
            call.assert_called_once()

    def test_unavailable_repository_does_not_hide_other_queued_jobs(self):
        config=self.config();config['pools'][0]['repositories'].append('example/unavailable')
        def api(path):
            if 'example/unavailable' in path:raise controller.ApiUnavailable('unavailable')
            if '/jobs?' in path:return dict(jobs=[dict(id=7,status='queued',labels=['eagle-linux-ubuntu24'])])
            return dict(workflow_runs=[dict(id=3,created_at='2026-10-21T00:00:00Z')]) if 'status=queued' in path else dict(workflow_runs=[])
        with patch.object(controller,'api',side_effect=api),patch.object(controller,'event') as event:
            self.assertEqual(controller.queued(config)[-1],7)
            event.assert_called_with('repository-scan-unavailable',repository='example/unavailable')

if __name__=='__main__': unittest.main()
