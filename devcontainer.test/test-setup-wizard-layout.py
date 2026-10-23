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

    def frame(self, section, columns=88, rows=40, wsl=False):
        text = self.shell(f'''is_wsl_windows() {{ return {0 if wsl else 1}; }}
init_components --loading
initialize_loading_statuses
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
        for columns in (36,60,61,88):
            for rows in (24,40,0):
                for wsl in (False,True):
                    with self.subTest(columns=columns, rows=rows, wsl=wsl):
                        lines=self.frame(3,columns,rows,wsl)
                        self.assert_bounds(lines,max(columns,36),rows or None)
                        text='\n'.join(lines)
                        self.assertIn('Workstation',text)
                        self.assertEqual(sum('╭─ Containers' in line for line in lines),1)
                        self.assertNotIn('REQUIRED SOFTWARE',text)
                        self.assertNotIn('OPTIONAL VAULT',text)
                        self.assertIn('ABOUT WSL 2' if wsl else 'ABOUT DOCKER',text)
                        self.assertIn('Vault',text)
                        if wsl:self.assertIn('WSL 2',text)
                        self.assertIn('Navigation:',text)
                        nav_index=next(i for i,line in enumerate(lines) if 'Workstation' in line)
                        self.assertEqual(lines[nav_index+2],'')
                        self.assertIn('REQUIREMENTS ·',lines[nav_index+3])
                        self.assertEqual(lines[nav_index+4], '')
                        self.assertIn('[ ]', text)
                        self.assertNotIn('[Check]', text)
                        if columns-1>=60:self.assertIn('G Profiles',text)

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
                        self.assertIn('ABOUT',text)
                        self.assertIn('Harnesses' if section==1 else 'CATEGORY',text)

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
if [[ "$CURRENT_SECTION" == 1 ]]; then setup_harness_zone=harness; current_selection=2; fi
if [[ "$CURRENT_SECTION" == 2 ]]; then setup_tool_zone=tool; fi
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

    def test_every_catalog_item_has_about_and_categories_are_isolated(self):
        output=self.shell(r'''
init_components --loading
setup_ui_width=87; setup_ui_height=''
for key in "${ai_items[@]}" "${tool_items[@]}"; do
    [[ "$key" != separator* ]] || continue
    [[ -n "${component_about[$key]}" ]] || exit 30
    component_status[$key]=installed
done
for CURRENT_SECTION in 1 2; do
    family=tool; [[ "$CURRENT_SECTION" != 1 ]] || family=harness
    declare -n categories="setup_${family}_categories" members_map="setup_${family}_members" category="setup_${family}_category" zone="setup_${family}_zone"
    zone=$family
    for catalog_test_category in "${categories[@]}"; do
        category=$catalog_test_category
        IFS=' ' read -r -a members <<< "${members_map[$category]}"
        for key in "${members[@]}"; do
            setup_focus_catalog_key "$family" "$key"
            setup_frame_lines=(); setup_frame_components
            printf 'ITEM:%s:%s\n' "$key" "$setup_about_anchor"
            printf '%s\n' "${setup_frame_lines[@]}"
        done
    done
    unset -n categories members_map category zone
done
''')
        harness_groups=[{'claude_cli','copilot_cli','codex_cli','antigravity_cli','opencode_cli','pi_cli'},
                        {'opencode_desktop','qwen_desktop','kimi_desktop','zcode_desktop'},
                        {'copilot_vscode','cline_vscode','continue_vscode'},
                        {'spec_kit','openspec','omnigent','agenttower'}]
        tool_groups=[{'vscode','cursor_ide','kiro_ide','antigravity_ide','comate_ide'},
                     {'warp','wave'},{'amnezia_vpn','0dcloud_vpn'},{'host_shell','workspace_repo'}]
        labels={'claude_cli':'Claude Code CLI','copilot_cli':'GitHub Copilot CLI','codex_cli':'Codex CLI',
                'antigravity_cli':'Antigravity CLI','opencode_cli':'OpenCode CLI','pi_cli':'Pi Coding Agent',
                'opencode_desktop':'OpenCode Desktop','qwen_desktop':'Qwen Code Desktop','kimi_desktop':'Kimi Code Desktop',
                'zcode_desktop':'ZCode','copilot_vscode':'GitHub Copilot — VS Code','cline_vscode':'Cline — VS Code',
                'continue_vscode':'Continue — VS Code','spec_kit':'spec-kit','openspec':'OpenSpec','omnigent':'Omnigent','agenttower':'AgentTower',
                'vscode':'VS Code','cursor_ide':'Cursor','kiro_ide':'Kiro IDE','antigravity_ide':'Antigravity IDE','comate_ide':'Comate IDE',
                'warp':'Warp Terminal','wave':'Wave Terminal','amnezia_vpn':'AmneziaVPN','0dcloud_vpn':'0dcloud VPN',
                'host_shell':'Shell setup','workspace_repo':'Org workspace'}
        managed={'claude_cli','copilot_cli','codex_cli','antigravity_cli','opencode_cli','pi_cli',
                 'spec_kit','openspec','vscode','warp','wave','amnezia_vpn','0dcloud_vpn','host_shell','workspace_repo'}
        chunks=output.split('ITEM:')[1:]
        self.assertEqual(len(chunks),28)
        self.assertEqual({chunk.split(':',1)[0] for chunk in chunks},set(labels))
        for chunk in chunks:
            key,anchor=chunk.splitlines()[0].split(':',1)
            plain=ANSI.sub('',chunk)
            groups=harness_groups if any(key in group for group in harness_groups) else tool_groups
            family='harness' if groups is harness_groups else 'tool'
            self.assertEqual(anchor,family+':'+key)
            self.assertIn('ABOUT',plain)
            self.assertNotIn('Select an item to see its details.',plain)
            if family=='harness':self.assertIn('Harnesses',plain)
            group=next(group for group in groups if key in group)
            body=plain.split('ABOUT',1)[0]
            for member in group:
                self.assertIn(labels[member],body)
            for other in set(labels)-group:
                # Match whole row labels: VS Code alone is a suffix of extension names.
                self.assertNotRegex(body,r'(?:\[ \]|·)\s+[✓○…]\s+'+re.escape(labels[other])+r'\s{2,}')
            self.assertEqual(body.count('[ ]'),len(group & managed))
            if key not in managed:
                self.assertIn('Manual setup:',plain)
                self.assertIn('Setup:',plain)
                self.assertIn('https://',plain)
                self.assertIn('Presence does not establish login',plain)

    def test_long_setup_link_survives_wrap_and_paging_markers(self):
        output=self.shell(r'''
setup_ui_width=36; setup_ui_height=24
url='https://docs.example.test/a-very-long-installation-path/with-no-spaces/extension'
setup_frame_about link ABOUT "$url" 2
printf 'WRAPPED:%s\n' "${setup_about_lines[@]}"
total=${#setup_about_lines[@]}
for ((i=0;i<total-1;i++)); do
    setup_about_offset=$i; setup_frame_lines=()
    setup_frame_about link ABOUT "$url" 2
    printf 'PAGE:%s\n' "$i"
    printf '%s\n' "${setup_frame_lines[@]}"
done
''')
        wrapped=[line.removeprefix('WRAPPED:') for line in output.splitlines() if line.startswith('WRAPPED:')]
        self.assertEqual(''.join(wrapped),'https://docs.example.test/a-very-long-installation-path/with-no-spaces/extension')
        for page in output.split('PAGE:')[1:]:
            index=int(page.splitlines()[0])
            lines=ANSI.sub('',page).splitlines()[2:4]
            content=[line[2:-2].strip().removeprefix('▲ more ').removeprefix('▼ more ') for line in lines]
            self.assertEqual(content,wrapped[index:index+2])

    def test_all_harness_categories_keep_focus_and_about_in_size_locale_matrix(self):
        for locale in ('C.UTF-8','C'):
            output=self.shell(r'''
init_components --loading
for key in "${!component_description[@]}"; do component_status[$key]=installed; done
for key in "${requirement_items[@]}"; do component_status[$key]=up; done
setup_ui_painted=true; setup_ui_size_stale=false
for setup_ui_width in 36 60 87; do
    for setup_ui_height in 24 40 ''; do
        for setup_harness_category in "${setup_harness_categories[@]}"; do
            IFS=' ' read -r -a members <<< "${setup_harness_members[$setup_harness_category]}"
            for setup_harness_zone in category harness; do
                CURRENT_SECTION=1
                setup_focus_harness_key "${members[${#members[@]}-1]}"
                setup_frame_build
                printf 'CASE:%s:%s:%s:%s\n' "$setup_ui_width" "$setup_ui_height" "$setup_harness_category" "$setup_harness_zone"
                printf '%s\n' "${setup_frame_lines[@]}"
            done
        done
    done
done
''',locale)
            cases=output.split('CASE:')[1:]
            self.assertEqual(len(cases),72)
            for case in cases:
                marker,*lines=ANSI.sub('',case).splitlines()
                width,height,category,zone=marker.split(':')
                self.assert_bounds(lines,int(width),int(height) if height else None)
                text='\n'.join(lines)
                self.assertIn('CATEGORY',text)
                self.assertIn('Harnesses',text)
                self.assertIn('ABOUT',text)
                self.assertIn('Navigation:',text)
                if zone=='harness':self.assertIn('›',text)
                self.assertNotIn('separator',text)

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
