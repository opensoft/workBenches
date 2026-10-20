#!/usr/bin/env python3
"""Native acceptance must act on the real fresh-assembly TUI status."""
import importlib.util
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('native', ROOT / 'devcontainer.test/test-wsl-workstation-acceptance.py')
native = importlib.util.module_from_spec(spec); spec.loader.exec_module(native)


class NativePromptTests(unittest.TestCase):
    def test_real_fresh_bench_status_is_selectable(self):
        with tempfile.TemporaryDirectory() as temporary:
            # The cloned frozen assembly has no populated submodule or image.
            # Exercise the product's actual status-to-label path, not a fixture
            # string that assumes "needs setup" is its fresh-install label.
            directory = Path(temporary); (directory / 'scripts').mkdir()
            command = '''source "$1/scripts/interactive-setup.sh"
SCRIPT_DIR="$2/scripts"
bench_installation_status() { printf 'needs setup\\n'; }
state="$(check_component_status bench_pyBench)"
printf 'pyBench · %s\\n' "$(setup_status_label "$state")"
'''
            result = subprocess.run(['bash', '-c', command, 'test', str(ROOT), temporary],
                                    capture_output=True, text=True, timeout=10, check=True)
        self.assertEqual(result.stdout.strip(), 'pyBench · not installed')
        self.assertIsNotNone(re.search(native.BENCH_SELECTABLE, result.stdout))

    def test_incomplete_or_untrusted_inventory_is_not_selected(self):
        for state in ('Loading…', 'needs check', 'needs docker', 'unknown'):
            self.assertIsNone(re.search(native.BENCH_SELECTABLE, 'pyBench · ' + state))


if __name__ == '__main__': unittest.main()
