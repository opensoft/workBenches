#!/usr/bin/env python3
"""Deterministic frame checks; timing runs separately on the developer host."""
import os
from pathlib import Path
import re
import subprocess
import signal
import time
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

    def test_size_cache_and_height_repaint(self):
        output = self.shell(r'''
setup_frame_build() { setup_frame_lines=(hello); }
tput() { printf '%s\n' "$1" >> "$TMP_SIZE_CALLS"; case $1 in cols) echo 88;; lines) echo "$height";; esac; }
TMP_SIZE_CALLS=$(mktemp); height=40
draw_ui > /dev/null
draw_ui > /dev/null
[[ $(wc -l < "$TMP_SIZE_CALLS") == 2 ]] || exit 91
height=24; setup_ui_size_stale=true
draw_ui
rm "$TMP_SIZE_CALLS"
''')
        self.assertIn('\x1b[2J', output)

    def test_resize_interrupt_returns_redraw_not_quit(self):
        for running in ('true', 'false'):
            command = ('source scripts/interactive-setup.sh\nstatus_checks_running=' + running +
                       '\necho READY\nhandle_input; result=$?; echo result=$result stale=$setup_ui_size_stale')
            proc = subprocess.Popen(['bash', '-c', command], cwd=ROOT, stdin=subprocess.PIPE,
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                                    env=dict(os.environ, WORKBENCHES_SETUP_LOG_FILE='/dev/null'))
            try:
                self.assertEqual(proc.stdout.readline().strip(), 'READY')
                time.sleep(0.03)
                os.kill(proc.pid, signal.SIGWINCH)
                proc.wait(timeout=3)
                output = proc.stdout.read()
                self.assertEqual(proc.returncode, 0, proc.stderr.read())
                self.assertIn('result=3 stale=true', output)
            finally:
                if proc.poll() is None: proc.kill(); proc.wait()
                proc.stdin.close(); proc.stdout.close(); proc.stderr.close()

    def test_invalid_size_defaults_and_locale_is_utf8(self):
        output = self.shell(r'''
tput() { case $1 in cols) echo invalid;; lines) echo 0;; esac; }
setup_ui_read_size
printf '%s:%s:%s\n' "$setup_ui_width" "$setup_ui_height" "${#SILVER}"
''')
        self.assertTrue(output.startswith('87::'))

    def test_list_window_is_edge_triggered(self):
        output = self.shell(r'''
offset=0
setup_ui_list_window 12 0 5 offset
printf '%s:%s\n' "$offset" "$setup_window_count"
setup_ui_list_window 12 1 5 offset
printf '%s\n' "$offset"
setup_ui_list_window 12 7 5 offset
printf '%s:%s:%s\n' "$offset" "$setup_window_above" "$setup_window_below"
setup_ui_height=''; setup_ui_list_window 12 7 0 offset
printf '%s:%s:%s\n' "$setup_window_start" "$setup_window_count" "$setup_window_below"
''')
        self.assertEqual(output.splitlines()[:2], ['0:4', '0'])
        start, above, below = map(int, output.splitlines()[2].split(':'))
        self.assertGreater(start, 0); self.assertGreater(above, 0); self.assertGreater(below, 0)
        self.assertEqual(output.splitlines()[3], '0:12:0')

    def test_about_wrap_scroll_reset_and_top_clipping(self):
        output = self.shell(r'''
setup_ui_width=36; setup_ui_height=24; setup_frame_lines=()
setup_frame_about bench:one ABOUT 'one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty' 2
printf 'lines=%s offset=%s\n' "${#setup_about_lines[@]}" "$setup_about_offset"
setup_about_scroll 1
setup_frame_lines=(); setup_frame_about bench:one ABOUT 'one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty' 2
printf 'scrolled=%s\n' "$setup_about_offset"
printf '%s\n' "${setup_frame_lines[@]}"
setup_frame_about bench:two ABOUT 'short text' 2
printf 'reset=%s\n' "$setup_about_offset"
setup_frame_lines=(one two three four five); setup_ui_height=3; setup_frame_fit
printf 'fit=%s\n' "${setup_frame_lines[*]}"
''')
        self.assertIn('scrolled=1', output)
        self.assertIn('▲ more', output)
        self.assertIn('PgUp/PgDn scroll', output)
        self.assertIn('reset=0', output)
        self.assertIn('fit=three four five', output)

    def test_banner_collapses_below_forty_rows(self):
        for rows, full in ((24, False), (39, False), (40, True)):
            text = '\n'.join(self.frame(3, 88, rows))
            self.assertEqual('█▀▀█' in text, full)

    def test_main_loop_uses_variable_signature(self):
        text = (ROOT / 'scripts/interactive-setup.sh').read_text()
        main = text.split('main() {', 1)[1]
        self.assertNotIn('$(get_checked_state)', main)
        output = self.shell(r'''
init_components --loading
setup_update_ui_signature; before=$setup_ui_signature
setup_about_offset=2; setup_update_ui_signature
[[ "$before" != "$setup_ui_signature" ]] || exit 91
''')
        self.assertEqual(output, '')

    def test_workstation_render_matrix(self):
        for columns in (36,60,88):
            for rows in (24,40,0):
                with self.subTest(columns=columns, rows=rows):
                    lines=self.frame(3,columns,rows)
                    self.assert_bounds(lines,max(columns,36),rows or None)
                    text='\n'.join(lines)
                    self.assertIn('Workstation',text)
                    self.assertIn('REQUIRED SOFTWARE',text)
                    self.assertIn('OPTIONAL VAULT',text)
                    self.assertIn('Navigation:',text)


if __name__ == '__main__': unittest.main()
