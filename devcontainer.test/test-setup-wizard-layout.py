#!/usr/bin/env python3
"""Deterministic frame checks; timing runs separately on the developer host."""
import os
from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
ANSI = re.compile(r'\x1b\[[0-?]*[ -/]*[@-~]')
BRIDGES = {'setup_frame_legacy_bridge'}


class LayoutTests(unittest.TestCase):
    def shell(self, body):
        result = subprocess.run(['bash', '-c', 'source scripts/interactive-setup.sh\n' + body], cwd=ROOT,
                                env=dict(os.environ, WORKBENCHES_SETUP_LOG_FILE='/dev/null', LC_ALL='C.UTF-8'),
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def frame(self, section, columns=88, rows=40):
        text = self.shell(f'''init_components --loading
setup_os_label=Linux
CURRENT_SECTION={section}
tput() {{ case $1 in cols) echo {columns};; lines) echo {rows};; esac; }}
render_setup_frame''')
        return ANSI.sub('', text).splitlines()

    def assert_bounds(self, lines, columns, rows=None):
        self.assertTrue(all(len(line) <= columns for line in lines), [(len(line), line) for line in lines if len(line)>columns])
        if rows is not None: self.assertLessEqual(len(lines), rows)

    def test_frame_keeps_legacy_content_while_engine_is_bridged(self):
        lines = self.frame(0)
        self.assertTrue(any('workBenches v' in line for line in lines))
        self.assertTrue(any('Navigation:' in line for line in lines))
        self.assert_bounds(lines, 88)

    def test_variable_helpers_count_characters(self):
        output = self.shell("setup_ui_pair_v result 'héllo' '✓' 12; printf '%s:%s\\n' \"${#result}\" \"$result\"\nsetup_ui_rule_v result 5; printf '%s\\n' \"$result\"")
        self.assertEqual(output, '12:héllo      ✓\n─────\n')

    def test_render_engine_has_no_forks(self):
        text = (ROOT/'scripts/interactive-setup.sh').read_text()
        functions = re.findall(r'^(\w+)\(\) \{\n(.*?)^\}', text, re.M|re.S)
        checked = []
        for name, body in functions:
            if not (name.startswith(('setup_frame_', 'setup_ui_', 'wizard_render_')) or name=='draw_ui') or name in BRIDGES:
                continue
            checked.append(name)
            body = '\n'.join(line for line in body.splitlines() if not line.lstrip().startswith('#'))
            self.assertNotRegex(body, r'\$\((?!\()|`|[<>]\(', name)
            self.assertNotRegex(body, r'(?<!\|)\|(?!\|)', name)
        self.assertIn('setup_frame_build', checked)
        self.assertIn('draw_ui', checked)


if __name__ == '__main__': unittest.main()
