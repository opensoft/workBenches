import unittest
from unittest.mock import Mock,patch
import backend

class ImageIdentityTests(unittest.TestCase):
    def test_oci_index_is_resolved_to_verified_runtime_config_identity(self):
        expected=dict(Config={'User':'runner'},RootFS={'Layers':['sha256:layer']},Architecture='amd64',Os='linux')
        original=dict(expected,Config=dict(expected['Config'],OnBuild=None))
        process=Mock();process.wait.return_value=0;process.poll.return_value=0
        import json
        with patch.object(backend.subprocess,'Popen',return_value=process),patch.object(backend,'inspect',return_value=original),patch.object(backend,'inner',side_effect=[Mock(stdout='sha256:config\n'),Mock(stdout=json.dumps([expected]))]):
            self.assertEqual(backend.load('private-engine','sha256:index'),'sha256:config')
    def test_imported_layers_must_equal_pinned_layers(self):
        original=dict(Config={},RootFS={'Layers':['expected']},Architecture='amd64',Os='linux')
        imported=dict(original,RootFS={'Layers':['unexpected']})
        process=Mock();process.wait.return_value=0;process.poll.return_value=0
        import json
        with patch.object(backend.subprocess,'Popen',return_value=process),patch.object(backend,'inspect',return_value=original),patch.object(backend,'inner',side_effect=[Mock(stdout='sha256:config\n'),Mock(stdout=json.dumps([imported]))]):
            with self.assertRaisesRegex(RuntimeError,'differs'): backend.load('private-engine','sha256:index')

if __name__=='__main__': unittest.main()
