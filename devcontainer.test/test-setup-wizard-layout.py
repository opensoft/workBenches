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
BRIDGES = set()


class LayoutTests(unittest.TestCase):
    def shell(self, body, locale='C.UTF-8'):
        result = subprocess.run(['bash', '-c', 'source scripts/interactive-setup.sh\n' + body], cwd=ROOT,
                                env=dict(os.environ, WORKBENCHES_SETUP_LOG_FILE='/dev/null', LC_ALL=locale),
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def frame(self, section, columns=88, rows=40):
        text = self.shell(f'''init_components --loading
setup_os_label='Linux — Omarchy'
CURRENT_SECTION={section}
tput() {{ case $1 in cols) echo {columns};; lines) echo {rows};; esac; }}
render_setup_frame''')
        return ANSI.sub('', text).splitlines()

    def assert_bounds(self, lines, columns, rows=None):
        self.assertTrue(all(len(line) <= columns for line in lines), [(len(line), line) for line in lines if len(line)>columns])
        if rows is not None: self.assertLessEqual(len(lines), rows)

    def test_frame_keeps_legacy_content_while_engine_is_bridged(self):
        lines = self.frame(0)
        self.assertTrue(any('openBenches v1.7' in line for line in lines))
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
            lines = self.frame(3, 88, rows)
            text = '\n'.join(lines)
            self.assertEqual('█▀▀█' in text, full)
            brand_index = next(i for i, line in enumerate(lines) if 'openBenches v1.7' in line)
            self.assertIn('█' if full else 'Opensoft', lines[brand_index])
            nav_index = next(i for i, line in enumerate(lines) if 'Workstation' in line)
            self.assertEqual(lines[nav_index - 1], '')
            self.assertTrue(lines[nav_index + 1].endswith(' Linux — Omarchy ─'))
            self.assertNotIn('workBenches v', text)

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

    def test_agents_and_tools_render_matrix(self):
        for section in (1,2):
            for columns in (36,60,88):
                for rows in (24,40,0):
                    with self.subTest(section=section,columns=columns,rows=rows):
                        lines=self.frame(section,columns,rows)
                        self.assert_bounds(lines,max(columns,36),rows or None)
                        text='\n'.join(lines)
                        self.assertIn('Navigation:',text)
                        self.assertNotIn('AI ASSISTANTS',text)
                        self.assertNotIn('REQUIREMENTS ·',text)

    def test_profiles_render_matrix(self):
        for columns in (36,60,88):
            for rows in (24,40,0):
                lines=self.frame(4,columns,rows)
                self.assert_bounds(lines,max(columns,36),rows or None)
                text='\n'.join(lines)
                self.assertIn('IDENTITIES',text)
                self.assertIn('Personal & companies',text)
                self.assertIn('AI accounts',text)
                self.assertIn('G Back',text)

    def test_footer_contract_at_each_width_and_step(self):
        for section in (0,1,2,3,4,5):
            for width in (36,60,80,87):
                text=self.shell(f'''init_components --loading
CURRENT_SECTION={section}; setup_ui_width={width}
setup_frame_lines=(); setup_frame_footer_prepare; setup_frame_footer
printf '%s\\n' "${{setup_frame_lines[@]}}"
''')
                lines=ANSI.sub('',text).splitlines()
                self.assert_bounds(lines,width)
                self.assertTrue(any('Changes:' in line or 'Changes selected:' in line for line in lines))
                self.assertTrue(any(line.startswith('Navigation:') for line in lines))
                if section==0:
                    self.assertIn('Changes:' if width<60 else 'Changes selected:',lines[0])
                    self.assertTrue(lines[1].startswith('Navigation:'))
                    self.assertNotIn('Loading benches',text)
                if width<60:self.assertLessEqual(len(lines),4)
                if section!=3:self.assertNotIn('V Vault',text)
                if section==4:self.assertTrue(any('G Back' in line and 'Q Quit' in line for line in lines))

    def real_benches_frame(self, columns, rows):
        text=self.shell(f'''init_components; setup_load_bench_metadata_sync
for key in "${{!component_description[@]}}"; do component_status[$key]=installed; done
for key in "${{requirement_items[@]}}"; do component_status[$key]=up; done
status_checks_running=false; setup_refresh_bench_counts
setup_arrive_step 0; setup_bench_zone=bench
setup_focus_bench_name cppBench
tput() {{ case $1 in cols) echo {columns};; lines) echo {rows};; esac; }}
render_setup_frame
printf 'ABOUT-WINDOW=%s\\n' "$setup_about_window"
''')
        return ANSI.sub('',text).splitlines()

    def test_bench_height_budget_gives_benches_priority(self):
        for columns,rows in ((80,24),(37,24),(88,40),(88,0)):
            with self.subTest(columns=columns,rows=rows):
                lines=self.real_benches_frame(columns,rows)
                about=lines.pop()
                self.assert_bounds(lines,max(columns,36),rows or None)
                text='\n'.join(lines)
                self.assertIn('Navigation:',text)
                self.assertIn('›',text)
                self.assertNotIn('cppBench · Ready',text)
                category_index = next(i for i, line in enumerate(lines) if 'CATEGORY' in line)
                self.assertEqual(lines[category_index - 1] == '', rows==0 or rows>=40)
                bench_index = next(i for i, line in enumerate(lines) if line.startswith('╭─ ') and 'ABOUT' not in line)
                about_index = next(i for i, line in enumerate(lines) if line.startswith('╭─ ABOUT'))
                for index in (bench_index, about_index):
                    self.assertEqual(lines[index - 1] == '', rows==0 or rows>=40)
                if columns==80:
                    for name in ('cppBench','dotNetBench','flutterBench','frappeBench','goBench','javaBench','pyBench','rustBench'):
                        self.assertIn(name,text)
                    self.assertEqual(about,'ABOUT-WINDOW=4')
                    self.assertEqual(sum('CATEGORY' in line for line in lines),1)
                if rows==0:self.assertNotIn('more',text)
                if rows==40:
                    for label in ('Software Engineering','Science','System Administration','Electrical Engineering'):
                        self.assertIn(label,text)

    def test_complete_render_matrix_and_no_discovery(self):
        cases=[(c,r) for c in (36,60,87) for r in (24,40,0)]
        cases += [(37,24),(80,24),(88,39),(88,40),(120,40),(30,24)]
        for locale in ('C.UTF-8','C'):
            for columns,rows in cases:
                for section in (3,0,1,2,4,5):
                    with self.subTest(locale=locale,columns=columns,rows=rows,section=section):
                        text=self.shell(f'''init_components; setup_load_bench_metadata_sync
for key in "${{!component_description[@]}}"; do component_status[$key]=installed; done
for key in "${{requirement_items[@]}}"; do component_status[$key]=up; done
status_checks_running=false
for key in bench_cppBench codex_cli vscode; do component_checked[$key]=true; component_action[$key]=update; done
setup_refresh_bench_counts
setup_arrive_step {section}
if [[ "$CURRENT_SECTION" == 0 ]]; then setup_bench_zone=bench; setup_focus_bench_name cppBench; fi
if [[ "$CURRENT_SECTION" == 1 ]]; then current_selection=2; fi
setup_os_label='Linux — Omarchy'
tput() {{ case $1 in cols) echo {columns};; lines) echo {rows};; esac; }}
jq() {{ echo UNEXPECTED_DISCOVERY; return 99; }}
python3() {{ echo UNEXPECTED_DISCOVERY; return 99; }}
docker() {{ echo UNEXPECTED_DISCOVERY; return 99; }}
git() {{ echo UNEXPECTED_DISCOVERY; return 99; }}
render_setup_frame
''',locale)
                        self.assertNotIn('UNEXPECTED_DISCOVERY',text)
                        lines=ANSI.sub('',text).splitlines()
                        self.assert_bounds(lines,max(columns,36),rows or None)
                        if columns>=36:
                            self.assertTrue(any('Navigation:' in line for line in lines),text)
                            self.assertTrue(any('Step ' in line or 'Workstation' in line for line in lines),text)
                            self.assertTrue(any('Changes:' in line or 'Changes selected:' in line for line in lines),text)
                            if section!=5:self.assertIn('›','\n'.join(lines))
                        if columns==80:
                            nav=next(line for line in lines if 'Workstation' in line and 'Benches' in line)
                            for name in ('Benches 1','Harness 1','Tools 1','Profiles','Review'):self.assertIn(name,nav)
                        if columns==120:self.assertTrue(any(len(line)==87 for line in lines))
                        if columns==88:self.assertEqual('█▀▀█' in text,rows==40)

    def test_no_legacy_renderer_remains(self):
        text=(ROOT/'scripts/interactive-setup.sh').read_text()
        for name in ('draw_three_sections','draw_item_compact','setup_frame_legacy_bridge'):
            self.assertNotIn(name,text)

    def test_all_twelve_benches_have_visible_copy_in_their_category(self):
        import json
        catalog=json.loads((ROOT/'config/bench-config.json').read_text())
        for name,entry in catalog['benches'].items():
            text=self.shell(f'''init_components; setup_load_bench_metadata_sync
for key in "${{!component_description[@]}}"; do component_status[$key]=installed; done
setup_refresh_bench_counts
setup_ui_width=87; setup_ui_height=''
setup_bench_zone=bench; setup_bench_category={entry['category']}
setup_focus_bench_name {name}
setup_frame_lines=(); setup_frame_benches
printf '%s\\n' "${{setup_frame_lines[@]}}"
''')
            plain=ANSI.sub('',text)
            self.assertIn(name,plain)
            self.assertIn(entry['tagline'],plain)
            self.assertIn('ABOUT '+name.upper(),plain)
            self.assertIn('Use it for',plain)
            self.assertIn('Contains',plain)


if __name__ == '__main__': unittest.main()
