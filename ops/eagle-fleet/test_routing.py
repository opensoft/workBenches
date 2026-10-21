import unittest
from routing import route

class RoutingTests(unittest.TestCase):
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
        self.assertEqual(route(source),(source,0))
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

if __name__=='__main__': unittest.main()
