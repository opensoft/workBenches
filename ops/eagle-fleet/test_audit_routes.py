import unittest
from audit_routes import audit


class AuditTests(unittest.TestCase):
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
