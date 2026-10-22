import unittest
from routing import route

class RoutingTests(unittest.TestCase):
    def test_input_expression_and_array_are_routed(self):
        for selector in ['${{ inputs.runner }}','${{ vars.CI_RUNNER }}','${{ needs.build.outputs.runner }}']:
            with self.subTest(selector=selector):
                result,count=route('jobs:\n  a:\n    runs-on: '+selector+'\n')
                self.assertEqual(count,1)
                self.assertIn(selector[3:-2].strip(),result)
                self.assertEqual(route(result),(result,0))
        source='jobs:\n  a:\n    runs-on: [ubuntu-latest]\n  b:\n    runs-on: [self-hosted, gpu]\n'
        self.assertEqual(route(source),(source.replace('[ubuntu-latest]','[eagle-linux-ubuntu24]'),1))

    def test_direct_preserves_comments_and_steps(self):
        source='jobs:\n  test:\n    runs-on: ubuntu-latest # platform\n    steps:\n      - run: echo ubuntu-latest\n'
        result,count=route(source)
        self.assertEqual(count,1)
        self.assertEqual(result,source.replace('runs-on: ubuntu-latest','runs-on: eagle-linux-ubuntu24'))
    def test_matrix_values_and_conditions_stay_original(self):
        source="jobs:\n  test:\n    runs-on: ${{ matrix.os }}\n    strategy:\n      matrix:\n        os: [ubuntu-latest, windows-latest, macos-15]\n    steps:\n      - if: matrix.os == 'ubuntu-latest'\n        run: true\n"
        result,count=route(source)
        self.assertEqual(count,1)
        self.assertIn('os: [ubuntu-latest, windows-latest, macos-15]',result)
        self.assertIn("if: matrix.os == 'ubuntu-latest'",result)
        self.assertIn('"ubuntu-22.04":"eagle-linux-ubuntu22"',result)
    def test_specialized_runner_and_native_platform_preserved(self):
        source='jobs:\n  a:\n    runs-on: [self-hosted, cuttlefish]\n  b:\n    runs-on: windows-latest\n  c:\n    runs-on:\n      group: existing-workers\n'
        self.assertEqual(route(source),(source.replace('runs-on: windows-latest','runs-on: eagle-windows-2025'),1))
    def test_conditional_platform_keeps_windows(self):
        source="jobs:\n  a:\n    runs-on: ${{ matrix.platform == 'windows-x64' && 'windows-latest' || 'ubuntu-latest' }}\n"
        result,count=route(source)
        self.assertEqual(count,1)
        self.assertIn("matrix.platform == 'windows-x64' && 'windows-latest' || 'ubuntu-latest'",result)
    def test_predicates_are_preserved_in_expression(self):
        expression="matrix.os == 'ubuntu-latest' && 'ubuntu-latest' || 'windows-latest'"
        result,count=route('jobs:\n  a:\n    runs-on: ${{ '+expression+' }}\n')
        self.assertEqual(count,1)
        self.assertEqual(result.count(expression),2)
    def test_action_inputs_are_not_runner_selectors(self):
        source='jobs:\n  a:\n    runs-on: ubuntu-latest\n    steps:\n      - uses: example/action@v1\n        with:\n          runs-on: ubuntu-latest\n'
        result,count=route(source)
        self.assertEqual(count,1)
        self.assertIn('          runs-on: ubuntu-latest',result)

    def test_anchored_selector_is_rewritten_once(self):
        source='jobs:\n  a:\n    runs-on: &linux ubuntu-latest\n  b:\n    runs-on: *linux\n'
        result,count=route(source)
        self.assertEqual(count,1)
        import yaml
        self.assertEqual([job['runs-on'] for job in yaml.safe_load(result)['jobs'].values()],
                         ['eagle-linux-ubuntu24','eagle-linux-ubuntu24'])

    def test_aliased_job_is_rewritten_once(self):
        source='jobs:\n  a: &job\n    runs-on: ubuntu-latest\n    steps: [{run: echo original}]\n  b: *job\n'
        result,count=route(source)
        self.assertEqual(count,1)
        import yaml
        jobs=yaml.safe_load(result)['jobs']
        self.assertEqual(jobs['a']['runs-on'],'eagle-linux-ubuntu24')
        self.assertEqual(jobs['a'],jobs['b'])
        self.assertEqual(jobs['a']['steps'],[{'run':'echo original'}])

    def test_native_platforms_get_distinct_unavailable_labels(self):
        source='jobs:\n  win:\n    runs-on: windows-2022\n  mac:\n    runs-on: macos-latest\n'
        result,count=route(source)
        self.assertEqual(count,2)
        self.assertIn('runs-on: eagle-windows-2022',result)
        self.assertIn('runs-on: eagle-macos-latest',result)
        self.assertNotIn('eagle-linux',result)

    def test_generated_matrix_routing_is_idempotent(self):
        source='jobs:\n  a:\n    runs-on: ${{ matrix.os }}\n'
        routed,_=route(source)
        self.assertEqual(route(routed),(routed,0))

    def test_generated_linux_mapping_can_add_native_routing_without_nesting(self):
        old="jobs:\n  a:\n    runs-on: ${{ fromJSON('{\"ubuntu-latest\":\"eagle-linux-ubuntu24\"}')[(matrix.os)] || (matrix.os) }}\n"
        result,count=route(old)
        self.assertEqual(count,1)
        self.assertEqual(result.count('fromJSON'),1)
        self.assertIn('"windows-latest":"eagle-windows-2025"',result)

if __name__=='__main__': unittest.main()
