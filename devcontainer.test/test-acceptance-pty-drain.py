#!/usr/bin/env python3
"""A child's buffered final diagnostic survives parent exit and is redacted."""
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'devcontainer.test'))
spec = importlib.util.spec_from_file_location('acceptance', ROOT / 'devcontainer.test/test-workstation-acceptance.py')
tui = importlib.util.module_from_spec(spec); spec.loader.exec_module(tui)


class TailTests(unittest.TestCase):
    def test_buffered_tail_after_exit_is_kept_private_and_redacted(self):
        class Child:
            pid = 1
            returncode = 1
            def poll(self): return 1
            def wait(self, **kwargs): return 1
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            with patch.object(tui, 'REPO', root), patch.object(tui, 'REPORT', root), patch.object(tui, 'RESULTS', []), \
                 patch.object(tui, 'MARKERS', ['fixture-private-value']), patch.object(tui.subprocess, 'Popen', return_value=Child()), \
                 patch.object(tui.select, 'select', side_effect=lambda read, *args: (read, [], [])), \
                 patch.object(tui.os, 'read', side_effect=[b'build progress\n', b'fatal tail fixture-private-value\n', OSError()]):
                with self.assertRaisesRegex(AssertionError, 'test value leaked'):
                    tui.terminal('failed-build', [], expected=1)
            text = (root / 'failed-build.txt').read_text()
            self.assertIn('fatal tail', text)
            self.assertIn('[redacted test value]', text)
            self.assertNotIn('fixture-private-value', text)


if __name__ == '__main__': unittest.main()
