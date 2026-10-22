import unittest
from audit_routes import audit


class AuditTests(unittest.TestCase):
    def test_windows_arm_and_xcode_are_native_requirements(self):
        record=audit([dict(repository='example/consumer',path='workflow.yml',source='jobs:\n  a:\n    runs-on: windows-11-arm\n')])[0]
        self.assertIn('native-platform',record['flags']);self.assertIn('arm-platform',record['flags'])
        record=audit([dict(repository='example/consumer',path='workflow.yml',source='jobs:\n  a:\n    runs-on: xcode-27\n')])[0]
        self.assertIn('native-platform',record['flags'])

    def test_quoted_pins_and_versioned_windows_are_reported(self):
        reference='example/project/.github/workflows/build.yml@'+'a'*40
        for quote in ['', "'", '"']:
            for platform in ['windows-latest','windows-2019','windows-2022','windows-2025']:
                with self.subTest(quote=quote,platform=platform):
                    source='jobs:\n  call:\n    uses: '+quote+reference+quote+' # pinned\n  native:\n    runs-on: '+platform+'\n'
                    record=audit([dict(repository='example/consumer',path='workflow.yml',source=source)])[0]
                    self.assertIn('native-platform',record['flags'])
                    self.assertEqual(record['pinned_reusable_workflows'],[dict(workflow=reference.split('@')[0],commit='a'*40)])


if __name__=='__main__': unittest.main()
