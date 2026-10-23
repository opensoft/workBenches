#!/usr/bin/env python3
"""Fixture-only regression checks for the guided setup wizard."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class WizardTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        shutil.copytree(ROOT / 'scripts', self.root / 'scripts')
        shutil.copy2(ROOT / 'bootstrap.sh', self.root / 'bootstrap.sh')
        (self.root / 'config').mkdir()
        (self.root / 'status').mkdir()
        self.catalog = {'categories': {
            'science': {'order': 2, 'label': ' Science\x1b[2J ', 'summary': 'Test\u009b hostile\tcopy'},
            'unknown': {}}, 'benches': {'365Bench': {
                'path': 'sysBenches/365Bench', 'category': 'science', 'tagline': '',
                'description': ' Desc\x1b[2J ', 'usedFor': ['one|two', '', 'three\nitems'],
                'contains': ['Tools\u009b here']}}}
        self.write_catalog()

    def write_catalog(self):
        (self.root / 'config/bench-config.json').write_text(json.dumps(self.catalog))

    def shell(self, body, locale='C.UTF-8'):
        result = subprocess.run(['bash', '-c', 'source "$FIXTURE/scripts/interactive-setup.sh"\n' + body],
                                env=dict(os.environ, FIXTURE=str(self.root), WORKBENCHES_SETUP_LOG_FILE='/dev/null',
                                         LC_ALL=locale, TERM='xterm-256color'),
                                capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result.stdout

    def test_metadata_producer_contract_and_atomic_publication(self):
        self.shell(r'''
status_worker_dir="$FIXTURE/status"
init_components() { bench_items=(365Bench); }
python3() { printf 'optional\n'; }
check_component_status() { echo 'not installed'; }
refresh_bench_inventory() { :; }; refresh_host_tool_inventory() { :; }
is_wsl_windows() { return 1; }
mv() { printf '%s\n' "${2##*/}" >> "$FIXTURE/publish-order"; command mv "$@"; }
status_collect_inventory
''')
        status = self.root / 'status'
        self.assertEqual((status / 'catalog').read_text(), '365Bench\tsysBenches/365Bench\n')
        categories = {line.split('\t')[0]: line.split('\t')[1:] for line in (status / 'bench-categories').read_text().splitlines()}
        self.assertEqual(categories['science'], ['2', 'Science [2J', 'Test  hostile copy'])
        self.assertEqual(categories['unknown'], ['999', 'unknown', '-'])
        self.assertEqual((status / 'bench-meta').read_text(),
                         '365Bench\tscience\t-\tDesc [2J\tone/two|three items\tTools  here\n')
        order = (self.root / 'publish-order').read_text().splitlines()
        self.assertEqual(order[:3], ['catalog', 'bench-categories', 'bench-meta'])
        self.assertLess(order.index('bench-meta'), order.index('bench_365Bench.row'))
        self.assertFalse(list(status.glob('*.tmp')))
        for filename in ('catalog', 'bench-categories', 'bench-meta'):
            content = (status / filename).read_text()
            self.assertNotIn('\x1b', content)
            self.assertNotIn('\u009b', content)


    def test_outside_text_sanitized_in_any_locale(self):
        for locale in ('C', 'C.UTF-8'):
            with self.subTest(locale=locale):
                output = self.shell(r'''
input=$'hello\e[2J\302\233tab\tend\036tail'
setup_sanitize_text result "$input"
printf '%s\n' "$result"
''', locale)
                self.assertEqual(output, 'hello [2J tab end tail\n')
                self.assertNotIn('\x1b', output)
                self.assertNotIn('\u009b', output)

    def test_worker_details_and_identities_sanitized(self):
        for locale in ('C', 'C.UTF-8'):
            output = self.shell(r'''
init_components --loading
status_loader_dir="$FIXTURE/status"; status_checks_running=true; status_loader_pid=$$
printf 'up\tbad\033[2J\302\233\ttext\036tail\n' > "$status_loader_dir/docker.row"
printf 'optional\tfirst\033[2J\036second\302\233\n' > "$status_loader_dir/personal_profiles.row"
poll_status_loader
printf '%s\n%s\n' "${requirement_detail[docker]}" "$profiles_summary"
''', locale)
            self.assertEqual(output, 'bad [2J  text tail\nfirst [2J\nsecond \n')

    def test_profile_helper_summary_sanitized(self):
        for locale in ('C', 'C.UTF-8'):
            output = self.shell(r'''
init_components --loading
for key in "${requirement_items[@]}"; do component_status[$key]=up; done
current_selection=0
python3() { [[ "$*" != *--summary* ]] || printf 'helper\033[2J\302\233\ttext\036tail\n'; }
refresh_component_statuses() { :; }
activate_profile >/dev/null
printf '%s\n' "$profiles_summary"
''', locale)
            self.assertEqual(output, 'helper [2J  text\ntail\n')

    def test_foreground_metadata_reader_uses_builtins_and_validates(self):
        output = self.shell(r'''
init_components --loading
status_loader_dir="$FIXTURE/status"; status_checks_running=true; status_loader_pid=$$
printf '365Bench\tsysBenches/365Bench\nbad name\t../outside\n' > "$status_loader_dir/catalog"
printf 'science\t2\tScience\tHostile\033[2J\nbad id\t1\tBad\tBad\nunknown\twrong\t-\t-\n' > "$status_loader_dir/bench-categories"
printf '365Bench\tscience\t-\tDesc\033[2J\tOne|Two\tTools\nbad name\tscience\t-\t-\t-\t-\n' > "$status_loader_dir/bench-meta"
jq() { echo UNEXPECTED_JQ; return 91; }; python3() { echo UNEXPECTED_PYTHON; return 91; }
poll_status_loader
printf '%s\n' "${bench_items[*]}" "${setup_bench_path[365Bench]}" \
 "${bench_category_label[science]}" "${bench_category_summary[science]}" \
 "${bench_category_order[unknown]}" "${bench_category_label[unknown]}" \
 "${bench_meta_description[365Bench]}" "${bench_meta_tagline[365Bench]}" "$setup_benches_state"
''')
        self.assertEqual(output, '365Bench\nsysBenches/365Bench\nScience\nHostile [2J\n999\nunknown\nDesc [2J\n\nready\n')

    def test_sync_metadata_matches_worker_format_and_modes_skip_loading(self):
        output = self.shell(r'''
init_components() { bench_items=(365Bench); }
setup_load_bench_metadata_sync
printf '%s\n' "${bench_meta_description[365Bench]}" "${bench_category_label[science]}" "$setup_benches_state"
''')
        self.assertEqual(output, 'Desc [2J\nScience [2J\nready\n')
        for mode in ('--apply-plan', '--dependencies-plan'):
            output = self.shell(r'''
ensure_setup_platform() { :; }; ensure_workstation_requirements() { :; }
init_components() { :; }; load_statuses() { :; }; load_selection() { :; }
ensure_selected_dependencies() { :; }; process_selections() { :; }
workbenches_release_checkout() { return 1; }
setup_load_bench_metadata_sync() { echo UNEXPECTED_METADATA; return 99; }
main ''' + mode + ' "$FIXTURE/selection.json"')
            self.assertNotIn('UNEXPECTED_METADATA', output)

    def test_bench_metadata_readiness_states(self):
        for catalog, meta, done, expected in ((False, False, False, 'loading'),
                                             (True, False, False, 'loading'),
                                             (True, True, False, 'ready'),
                                             (True, False, True, 'ready'),
                                             (False, False, True, 'unavailable')):
            with self.subTest(catalog=catalog, meta=meta, done=done):
                directory = self.root / 'status'
                for p in directory.iterdir(): p.unlink()
                if catalog: (directory / 'catalog').write_text('365Bench\tsysBenches/365Bench\n')
                if meta: (directory / 'bench-meta').write_text('365Bench\t-\t-\t-\t-\t-\n')
                if done: (directory / 'done').touch()
                output = self.shell(r'''
init_components --loading
for key in "${requirement_items[@]}"; do component_status[$key]=up; done
status_loader_dir="$FIXTURE/status"; status_checks_running=true; status_loader_pid=$$
# Keep this process alive; stop must not signal its own PID.
stop_status_loader() { status_checks_running=false; status_loader_dir=''; }
poll_status_loader
printf '%s\n' "$setup_benches_state"
''')
                self.assertEqual(output.strip(), expected)

    def test_derived_categories_counts_and_vanished_queue(self):
        output = self.shell(r'''
init_components --loading
status_loader_dir="$FIXTURE/status"; status_checks_running=true; status_loader_pid=$$
printf 'cloudBench\tsysBenches/cloudBench\n365Bench\tsysBenches/365Bench\nquantumBench\tdevBenches/quantumBench\notherBench\toutside/otherBench\n' > "$status_loader_dir/catalog"
printf 'science\t2\tScience\tScience summary\nsoftware-engineering\t1\tSoftware Engineering\tSoftware summary\nelectrical-engineering\t4\tElectrical Engineering\t-\nsystem-administration\t3\tSystem Administration\t-\n' > "$status_loader_dir/bench-categories"
printf 'quantumBench\tquantum-computing\t-\t-\t-\t-\n' > "$status_loader_dir/bench-meta"
poll_status_loader
component_status[bench_365Bench]=installed; component_status[bench_cloudBench]='image only'
component_checked[bench_365Bench]=true; component_action[bench_365Bench]=update
setup_refresh_bench_counts
printf '%s\n' "${setup_bench_categories[*]}" "${setup_bench_members[system-administration]}" \
 "${bench_category_label[quantum-computing]}" "${setup_bench_category_of[otherBench]}" \
 "${setup_bench_installed[system-administration]}" "${setup_bench_queued[system-administration]}"
printf 'cloudBench\tsysBenches/cloudBench\n' > "$status_loader_dir/catalog"
poll_status_loader
printf 'vanished=%s:%s\n' "${component_checked[bench_365Bench]-false}" "${component_action[bench_365Bench]-}"
''')
        self.assertEqual(output, 'software-engineering science system-administration electrical-engineering other-benches quantum-computing\n365Bench cloudBench\nQuantum Computing\nother-benches\n2\n1\nvanished=false:\n')

    def test_no_metadata_degrades_to_one_other_group(self):
        output = self.shell(r'''
init_components --loading
status_loader_dir="$FIXTURE/status"; status_checks_running=true; status_loader_pid=$$
printf '365Bench\tsysBenches/365Bench\n' > "$status_loader_dir/catalog"
touch "$status_loader_dir/done"
stop_status_loader() { status_checks_running=false; status_loader_dir=''; }
poll_status_loader
printf '%s\n' "${setup_bench_category_of[365Bench]}" "${setup_bench_members[other-benches]}"
''')
        self.assertEqual(output, 'other-benches\n365Bench\n')

    def test_input_sequences_consume_full_key(self):
        for sequence, expected in [(r'\e[Z', 'backtab'), (r'\e[5~', 'pageup'),
                                   (r'\e[6~', 'pagedown'), (r'\t', 'tab'),
                                   ('[', 'pageup'), (']', 'pagedown'), (r'\e[9~', 'unknown')]:
            output = self.shell('init_components --loading\n' +
                                "handle_input < <(printf '" + sequence + "Q')\n" +
                                'printf \'%s\\n\' "$setup_input_key"\n')
            self.assertEqual(output.strip(), expected)

    def test_step_order_clamps_and_arrival_focus(self):
        output = self.shell(r'''
init_components --loading
CURRENT_SECTION=3
for ((i=0;i<7;i++)); do
    printf '%s ' "$CURRENT_SECTION"
    handle_input < <(printf '\e[C')
done
printf '\n'
for ((i=0;i<7;i++)); do
    printf '%s ' "$CURRENT_SECTION"
    handle_input < <(printf '\e[D')
done
''')
        self.assertEqual(output.splitlines(), ['3 0 1 2 4 5 5 ', '5 4 2 1 0 3 3 '])

    def test_shared_ready_markers_on_every_step(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location('acceptance_markers', ROOT/'devcontainer.test/test-workstation-acceptance.py')
        markers = importlib.util.module_from_spec(spec); spec.loader.exec_module(markers)
        import re
        for section in (3,0,1,2,4,5):
            frame = self.shell(r'''
init_components --loading
for key in "${!component_description[@]}"; do component_status[$key]=installed; done
for key in "${requirement_items[@]}"; do component_status[$key]=up; done
tput() { case $1 in cols) echo 80;; lines) echo 24;; esac; }
status_checks_running=false
CURRENT_SECTION=''' + str(section) + r'''
render_setup_frame
''')
            frame = re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]', '', frame)
            self.assertRegex(frame, markers.READY, f'section {section}')
            if section==3: self.assertRegex(frame, markers.STRIP_READY)

    def test_enter_reviews_before_apply_and_gate_is_enforced(self):
        output = self.shell(r'''
init_components --loading
for key in "${requirement_items[@]}"; do component_status[$key]=up; done
CURRENT_SECTION=1; setup_harness_zone=harness; component_status[codex_cli]=installed; current_selection=2
handle_input <<< ' '
handle_input <<< ''; printf 'review=%s action=%s\n' "$CURRENT_SECTION" "${component_action[codex_cli]}"
handle_input <<< ''; printf 'apply=%s\n' "$?"
status_checks_running=true
handle_input <<< ''; printf 'blocked=%s\n' "$?"
status_checks_running=false; component_status[docker]=down
handle_input <<< ''; printf 'down=%s\n' "$?"
''')
        self.assertIn('review=5 action=update', output)
        self.assertIn('apply=1', output)
        self.assertIn('blocked=0', output)
        self.assertIn('down=0', output)

    def test_review_is_read_only_and_selection_contract_unchanged(self):
        output = self.shell(r'''
init_components --loading
for key in "${requirement_items[@]}"; do component_status[$key]=up; done
component_checked[codex_cli]=true; component_action[codex_cli]=update
component_checked[host_shell]=true; component_action[host_shell]=install
component_checked[workspace_repo]=true; component_action[workspace_repo]=install
CURRENT_SECTION=5
handle_input <<< ' '; handle_input <<< D
selection_file="$FIXTURE/selection.json"; save_selection
setup_ui_height=40
render_setup_frame
''')
        self.assertIn('Nothing has changed yet. Enter applies these changes.', output)
        self.assertIn('INSTALL', output); self.assertIn('UPDATE', output)
        self.assertIn('replaces shell settings', output)
        self.assertIn('may create a GitHub repository', output)
        data = json.loads((self.root/'selection.json').read_text())
        self.assertEqual(data['schemaVersion'], 1)
        self.assertEqual({(e['key'], e['action']) for e in data['components']},
                         {('codex_cli','update'), ('host_shell','install'), ('workspace_repo','install')})
        self.assertEqual((self.root/'selection.json').stat().st_mode & 0o777, 0o600)

    def test_jump_roundtrips_restore_exact_focus(self):
        for section in (0,1,2,3,4,5):
            for jump, target in (('P',3),('G',4)):
                if section == target: continue
                output = self.shell(r'''
init_components --loading
bench_items=(365Bench cloudBench); setup_bench_categories_focusable=(system-administration)
CURRENT_SECTION=''' + str(section) + r'''; current_selection=1
setup_bench_zone=bench; setup_bench_category=system-administration; setup_review_offset=7
handle_input <<< ''' + jump + r'''
printf 'target=%s\n' "$CURRENT_SECTION"
handle_input <<< ''' + jump + r'''
printf '%s:%s:%s:%s:%s\n' "$CURRENT_SECTION" "$current_selection" "$setup_bench_zone" "$setup_bench_category" "$setup_review_offset"
''')
                self.assertIn(f'target={target}', output)
                self.assertIn(f'{section}:1:bench:system-administration:7', output)

    def test_unset_jump_defaults_and_readiness_return(self):
        output = self.shell(r'''
init_components --loading
setup_bench_categories_focusable=(software-engineering)
CURRENT_SECTION=3; handle_input <<< P
printf 'default=%s:%s:%s\n' "$CURRENT_SECTION" "$setup_bench_zone" "$setup_bench_category"
CURRENT_SECTION=5; setup_review_offset=8
status_loader_dir="$FIXTURE/status"; status_checks_running=true; status_loader_pid=$$
component_status[docker]=down; component_status[setup_tools]=up
touch "$status_loader_dir/done"
stop_status_loader() { status_checks_running=false; status_loader_dir=''; }
poll_status_loader
printf 'jump=%s\n' "$CURRENT_SECTION"
handle_input <<< P
printf 'return=%s:%s\n' "$CURRENT_SECTION" "$setup_review_offset"
''')
        self.assertIn('default=0:category:software-engineering', output)
        self.assertIn('jump=3', output)
        self.assertIn('return=5:8', output)

    def test_global_vault_refresh_and_quit_preserve_state(self):
        for section in (0,1,2,3,4,5):
            output = self.shell(r'''
init_components --loading
for key in "${requirement_items[@]}"; do component_status[$key]=up; done
component_status[workbenches_account]='sign in'
CURRENT_SECTION=''' + str(section) + r'''; current_selection=1
setup_bench_zone=bench; setup_bench_category=science
component_checked[codex_cli]=true; component_action[codex_cli]=update
refresh_component_statuses() { printf 'refresh\n'; }
python3() { return 130; }
draw_ui() { :; }
handle_input <<< V
printf '%s:%s:%s:%s:%s\n' "$CURRENT_SECTION" "$current_selection" "$setup_bench_zone" "$setup_bench_category" "$requirements_notice"
handle_input <<< R
printf 'queue=%s notice=%s\n' "${component_action[codex_cli]}" "$requirements_notice"
handle_input <<< Q; printf 'quit=%s\n' "$?"
''')
            self.assertIn(f'{section}:1:bench:science:Connection cancelled.', output)
            self.assertIn('queue=update notice=', output)
            self.assertIn('quit=2', output)

    def test_notice_is_bounded_and_shown_after_selector(self):
        output = self.shell(r'''
init_components --loading
CURRENT_SECTION=3; requirements_notice='A notice with a long explanation that must be cut at the frame edge.'
tput() { case $1 in cols) echo 37;; lines) echo 40;; esac; }
render_setup_frame
''')
        self.assertGreater(output.index('A notice with'), output.index('REQUIREMENTS ·'))
        self.assertEqual(output.count('A notice with'), 1)

    def test_component_selection_rules_and_separator(self):
        output=self.shell(r'''
init_components --loading
CURRENT_SECTION=1; setup_harness_zone=harness; current_selection=2; component_status[codex_cli]=installed
handle_input <<< ' '; printf '%s\n' "${component_action[codex_cli]}"
handle_input <<< D; printf '%s\n' "${component_action[codex_cli]}"
handle_input <<< D; printf '%s:%s\n' "${component_checked[codex_cli]}" "${component_action[codex_cli]}"
component_status[codex_cli]=loading; handle_input <<< ' '
printf 'loading=%s\n' "${component_checked[codex_cli]}"
CURRENT_SECTION=2; current_selection=5; component_status[host_shell]=configured
handle_input <<< D; printf 'shell=%s\n' "${component_action[host_shell]}"
''')
        self.assertEqual(output.splitlines(),['update','uninstall','false:','loading=false','shell='])

    def test_profiles_about_changes_with_focus(self):
        output=self.shell(r'''
init_components --loading
CURRENT_SECTION=4; setup_ui_width=60; setup_ui_height=24
setup_frame_lines=(); setup_frame_profiles
printf '%s\n' "${setup_about_lines[*]}"
current_selection=1; setup_about_offset=2
setup_frame_lines=(); setup_frame_profiles
printf '%s offset=%s\n' "${setup_about_lines[*]}" "$setup_about_offset"
''')
        self.assertIn('Personal identity, GitHub and company accounts.',output)
        self.assertIn('Organization sign-in.',output)
        self.assertIn('offset=0',output)

    def test_tools_category_navigation_preserves_global_selection_and_queue(self):
        output=self.shell(r'''
init_components --loading
for key in "${tool_items[@]}"; do component_status[$key]=installed; done
setup_arrive_step 2
handle_input <<< ' '
[[ "$setup_tool_zone" == tool && "${component_checked[vscode]}" != true ]] || exit 30
handle_input <<< $'\e[Z'; handle_input <<< $'\e[B'; handle_input <<< $'\t'
[[ "$setup_tool_category" == terminals && "${tool_items[$current_selection]}" == warp ]] || exit 31
handle_input <<< $'\e[B'; handle_input <<< ' '
[[ "$current_selection" == 2 && "${component_action[wave]}" == update ]] || exit 32
handle_input <<< $'\e[B'; [[ "${tool_items[$current_selection]}" == herder ]] || exit 33
handle_input <<< $'\e[B'; [[ "${tool_items[$current_selection]}" == foot ]] || exit 42
handle_input <<< $'\e[B'; [[ "${tool_items[$current_selection]}" == tmux ]] || exit 43
handle_input <<< $'\e[B'; [[ "${tool_items[$current_selection]}" == tmux ]] || exit 44
setup_focus_tool_key wave
handle_input <<< $'\e[A'; handle_input <<< D
[[ "$current_selection" == 1 && "${component_action[warp]}" == uninstall ]] || exit 34
handle_input <<< $'\e[A'
[[ "$setup_tool_zone" == category && "$setup_tool_category" == terminals ]] || exit 35
handle_input <<< D
[[ "${component_action[wave]}" == update && "${component_action[warp]}" == uninstall ]] || exit 36
handle_input <<< $'\t'
printf '%s:%s:%s\n' "$setup_tool_zone" "$setup_tool_category" "${tool_items[$current_selection]}"
''')
        self.assertEqual(output.strip(),'tool:terminals:warp')

    def test_tools_about_paging_and_jump_refresh_restore_exact_focus(self):
        output=self.shell(r'''
init_components --loading
for key in "${requirement_items[@]}"; do component_status[$key]=up; done
for key in "${tool_items[@]}"; do component_status[$key]=installed; done
CURRENT_SECTION=2; setup_tool_zone=tool; setup_tool_category=terminals; current_selection=1
component_about[warp]=''
for ((i=0;i<50;i++)); do component_about[warp]+='Long terminal details for paging. '; done
component_checked[wave]=true; component_action[wave]=update
setup_ui_width=36; setup_ui_height=24; setup_frame_build
handle_input <<< $'\e[6~'; [[ "$setup_about_offset" -gt 0 ]] || exit 30
saved_offset=$setup_about_offset
handle_input <<< G; setup_frame_build
handle_input <<< G; setup_frame_build
[[ "$CURRENT_SECTION" == 2 && "$setup_tool_zone" == tool && "$setup_tool_category" == terminals && "$current_selection" == 1 ]] || exit 31
[[ "$setup_about_offset" == "$saved_offset" ]] || exit 32
handle_input <<< P; setup_frame_build
handle_input <<< P; setup_frame_build
[[ "$CURRENT_SECTION" == 2 && "$setup_about_offset" == "$saved_offset" ]] || exit 33
status_async_ui=false
refresh_host_tool_inventory() { :; }; setup_load_bench_metadata_sync() { :; }; refresh_bench_inventory() { :; }
check_component_status() { echo installed; }; load_requirements() { :; }; draw_ui() { setup_frame_build; }
handle_input <<< R
[[ "$setup_tool_zone" == tool && "$setup_tool_category" == terminals && "$current_selection" == 1 && "$setup_about_offset" == "$saved_offset" ]] || exit 34
[[ "${component_action[wave]}" == update ]] || exit 35
handle_input <<< $'\e[5~'; [[ "$setup_about_offset" == 0 ]] || exit 36
handle_input <<< ']'; handle_input <<< $'\e[B'; setup_frame_build
[[ "$setup_about_anchor" == tool:wave && "$setup_about_offset" == 0 ]] || exit 37
echo restored
''')
        self.assertEqual(output.strip(),'restored')

    def test_harness_categories_keep_managed_indexes_and_block_manual_actions(self):
        output=self.shell(r'''
init_components --loading
for key in "${ai_items[@]}" "${tool_items[@]}"; do component_status[$key]=installed; done
setup_arrive_step 1
handle_input <<< D; handle_input <<< ' '
[[ "$setup_harness_zone" == harness && "${component_checked[claude_cli]}" != true ]] || exit 30
handle_input <<< $'\e[B'; handle_input <<< $'\e[B'; handle_input <<< ' '
[[ "$current_selection" == 2 && "${component_action[codex_cli]}" == update ]] || exit 31
handle_input <<< $'\t'; handle_input <<< $'\e[B'; handle_input <<< $'\t'
[[ "$setup_harness_category" == gui && "${ai_items[$current_selection]}" == opencode_desktop ]] || exit 32
handle_input <<< ' '; handle_input <<< D
[[ "${component_checked[opencode_desktop]}" != true && -z "${component_action[opencode_desktop]}" ]] || exit 33
handle_input <<< $'\e[Z'; handle_input <<< $'\e[B'; handle_input <<< $'\e[B'; handle_input <<< $'\t'
[[ "$setup_harness_category" == workflow && "$current_selection" == 7 ]] || exit 34
handle_input <<< ' '; handle_input <<< $'\e[B'; handle_input <<< D
[[ "${component_action[spec_kit]}" == update && "${component_action[openspec]}" == uninstall ]] || exit 35
handle_input <<< $'\e[B'; handle_input <<< ' '; handle_input <<< D
[[ "${ai_items[$current_selection]}" == omnigent && "${component_checked[omnigent]}" != true ]] || exit 36
handle_input <<< $'\e[B'; handle_input <<< $'\e[B'
[[ "${ai_items[$current_selection]}" == agenttower ]] || exit 37
handle_input <<< $'\t'; handle_input <<< D
[[ "$setup_harness_zone" == category && "${component_action[codex_cli]}" == update ]] || exit 38
setup_arrive_step 2; setup_tools_key tab; setup_tools_key down
[[ "${tool_items[$current_selection]}" == cursor_ide ]] || exit 39
handle_input <<< ' '; handle_input <<< D
[[ "${component_checked[cursor_ide]}" != true ]] || exit 40
selection_file="$FIXTURE/selection.json"; save_selection
for key in "${!setup_reference_labels[@]}"; do
    ! workstation_known_key "$key" || exit 41
done
printf '%s\n' "${component_action[codex_cli]}:${component_action[spec_kit]}:${component_action[openspec]}"
''')
        self.assertEqual(output.strip(),'update:update:uninstall')
        keys={entry['key'] for entry in json.loads((self.root/'selection.json').read_text())['components']}
        self.assertEqual(keys,{'codex_cli','spec_kit','openspec'})

    def test_harness_category_jump_refresh_and_about_restore(self):
        output=self.shell(r'''
init_components --loading
for key in "${requirement_items[@]}"; do component_status[$key]=up; done
setup_arrive_step 1; setup_harnesses_key down; setup_harnesses_key down; setup_harnesses_key down; setup_harnesses_key tab
setup_harnesses_key down; setup_harnesses_key down; setup_harnesses_key down
component_about[agenttower]=''
for ((i=0;i<50;i++)); do component_about[agenttower]+='Long workflow details for paging. '; done
setup_ui_width=36; setup_ui_height=24; setup_frame_build
handle_input <<< ']'; saved_offset=$setup_about_offset
[[ "$saved_offset" -gt 0 ]] || exit 30
for jump in G P; do
    handle_input <<< "$jump"; setup_frame_build
    handle_input <<< "$jump"; setup_frame_build
    [[ "$CURRENT_SECTION" == 1 && "$setup_harness_zone" == harness && "$setup_harness_category" == workflow && "${ai_items[$current_selection]}" == agenttower && "$setup_about_offset" == "$saved_offset" ]] || exit 31
done
status_async_ui=false
refresh_host_tool_inventory() { :; }; setup_load_bench_metadata_sync() { :; }; refresh_bench_inventory() { :; }
check_component_status() { echo installed; }; load_requirements() { :; }; draw_ui() { setup_frame_build; }
handle_input <<< R
[[ "$setup_harness_category" == workflow && "${ai_items[$current_selection]}" == agenttower && "$setup_about_offset" == "$saved_offset" ]] || exit 32
handle_input <<< $'\t'; setup_frame_build
[[ "$setup_about_anchor" == harness-category:workflow && "$setup_about_offset" == 0 ]] || exit 33
handle_input <<< G; setup_frame_build; handle_input <<< G; setup_frame_build
[[ "$setup_harness_zone" == category && "$setup_harness_category" == workflow ]] || exit 34
handle_input <<< $'\e[A'; setup_frame_build
[[ "$setup_harness_category" == extensions && "$setup_about_anchor" == harness-category:extensions ]] || exit 35
echo restored
''')
        self.assertEqual(output.strip(),'restored')

    def test_cli_group_picker_preserves_queue_focus_and_independent_scroll_on_jumps(self):
        output=self.shell(r'''
init_components --loading
for key in "${requirement_items[@]}"; do component_status[$key]=up; done
for key in "${ai_items[@]}"; do component_status[$key]=installed; done
component_checked[codex_cli]=true; component_action[codex_cli]=update
setup_arrive_step 1
handle_input <<< F; [[ "$setup_harness_zone" == group ]] || exit 30
handle_input <<< $'\e[B'; [[ "$setup_cli_group" == model_usa ]] || exit 31
handle_input <<< ' '; [[ "$setup_harness_zone" == harness && "${component_action[claude_cli]}" == '' ]] || exit 32
setup_focus_harness_key hermes_agent
component_about[hermes_agent]=''
for ((i=0;i<60;i++)); do component_about[hermes_agent]+='Long capability and interoperability detail. '; done
setup_ui_width=36; setup_ui_height=24; setup_frame_build
saved_list=${setup_harness_offsets[tui:model_usa]}
[[ "$saved_list" -gt 0 ]] || exit 33
handle_input <<< ']'; saved_about=$setup_about_offset
[[ "$saved_about" -gt 0 ]] || exit 34
for jump in G P; do
    handle_input <<< "$jump"; setup_frame_build; handle_input <<< "$jump"; setup_frame_build
    [[ "$CURRENT_SECTION" == 1 && "$setup_cli_group" == model_usa && "$setup_harness_zone" == harness && "${ai_items[$current_selection]}" == hermes_agent ]] || exit 35
    [[ "${setup_harness_offsets[tui:model_usa]}" == "$saved_list" && "$setup_about_offset" == "$saved_about" ]] || exit 36
done
status_async_ui=false
refresh_host_tool_inventory() { :; }; setup_load_bench_metadata_sync() { :; }; refresh_bench_inventory() { :; }
check_component_status() { echo installed; }; load_requirements() { :; }; draw_ui() { setup_frame_build; }
handle_input <<< R
[[ "$setup_cli_group" == model_usa && "$setup_about_offset" == "$saved_about" ]] || exit 37
handle_input <<< F; setup_frame_build
[[ "$setup_about_anchor" == harness-group:model_usa && "$setup_about_offset" == 0 ]] || exit 38
handle_input <<< $'\e[B'; setup_frame_build
[[ "$setup_cli_group" == model_china && "${ai_items[$current_selection]}" == qwen_cli ]] || exit 39
handle_input <<< $'\t'; handle_input <<< ' '; handle_input <<< D
[[ "${component_action[qwen_cli]}" == '' && "${component_action[codex_cli]}" == update ]] || exit 40
handle_input <<< F; handle_input <<< $'\e[A'; handle_input <<< $'\t'
setup_focus_harness_key hermes_agent; setup_frame_build
[[ "${setup_harness_offsets[tui:model_usa]}" == "$saved_list" ]] || exit 41
handle_input <<< F; handle_input <<< $'\e[Z'
[[ "$setup_harness_zone" == category && "$setup_cli_group" == model_usa ]] || exit 42
echo grouped
''')
        self.assertEqual(output.strip(),'grouped')

    def test_all_new_reference_products_ignore_action_keys_even_when_present(self):
        output=self.shell(r'''
init_components --loading
setup_cli_group=all
for family in harness tool; do
    CURRENT_SECTION=1; [[ "$family" != tool ]] || CURRENT_SECTION=2
    declare -n cats="setup_${family}_categories" cat="setup_${family}_category" zone="setup_${family}_zone" members="setup_${family}_members"
    zone=$family
    for cat_id in "${cats[@]}"; do
        cat=$cat_id
        for key in ${members[$cat]}; do
            [[ -n "${setup_reference_labels[$key]:-}" ]] || continue
            setup_focus_catalog_key "$family" "$key"
            component_status[$key]=installed
            handle_input <<< ' '; handle_input <<< D
            [[ "${component_checked[$key]}" != true && -z "${component_action[$key]}" ]] || exit 30
        done
    done
    unset -n cats cat zone members
done
selection_file="$FIXTURE/empty-catalog-plan.json"; save_selection
echo manual
''')
        self.assertEqual(output.strip(),'manual')
        self.assertEqual(json.loads((self.root/'empty-catalog-plan.json').read_text())['components'],[])

    def test_harness_about_pages_and_resets_on_selected_harness_change(self):
        output=self.shell(r'''
init_components --loading; CURRENT_SECTION=1; setup_harness_zone=harness
setup_ui_width=36; setup_ui_height=24
component_about[claude_cli]=''
for ((i=0;i<40;i++)); do component_about[claude_cli]+='Long harness details for paging. '; done
setup_frame_build
handle_input <<< ']'; [[ "$setup_about_offset" -gt 0 ]] || exit 30
handle_input <<< '['; [[ "$setup_about_offset" == 0 ]] || exit 31
handle_input <<< $'\e[6~'; [[ "$setup_about_offset" -gt 0 ]] || exit 32
handle_input <<< $'\e[B'; setup_frame_build
[[ "$setup_about_anchor" == harness:copilot_cli && "$setup_about_offset" == 0 ]] || exit 33
[[ "${component_checked[claude_cli]}" != true && "${component_checked[copilot_cli]}" != true ]] || exit 34
echo paged
''')
        self.assertEqual(output.strip(),'paged')

    def test_tools_setup_category_retains_configuration_only_actions(self):
        self.shell(r'''
init_components --loading
setup_arrive_step 2
for ((i=0;i<3;i++)); do handle_input <<< $'\e[B'; done
handle_input <<< $'\t'
[[ "$current_selection" == 5 && "${tool_items[$current_selection]}" == host_shell ]] || exit 30
component_status[host_shell]=configured
handle_input <<< ' '; handle_input <<< D
[[ "${component_action[host_shell]}" == install ]] || exit 31
handle_input <<< $'\e[B'
[[ "$current_selection" == 6 && "${tool_items[$current_selection]}" == workspace_repo ]] || exit 32
component_status[workspace_repo]=optional
handle_input <<< ' '; handle_input <<< D
[[ "${component_action[workspace_repo]}" == install ]] || exit 33
''')

    def test_workstation_about_pages_and_follows_focus_without_actions(self):
        output=self.shell(r'''
is_wsl_windows() { return 1; }
init_components --loading
CURRENT_SECTION=3; setup_ui_width=36; setup_ui_height=24; setup_ui_layout=tight
requirement_detail[docker]=''
for ((i=0;i<40;i++)); do requirement_detail[docker]+='Long current check detail. '; done
component_checked[codex_cli]=true; component_action[codex_cli]=install
activate_requirement() { echo UNEXPECTED_ACTION; return 99; }
setup_frame_footer_prepare; setup_frame_lines=(); setup_frame_head; setup_frame_selector; setup_frame_workstation
handle_input <<< ']'; printf 'bracket=%s\n' "$setup_about_offset"
handle_input <<< '['; printf 'top=%s\n' "$setup_about_offset"
handle_input <<< $'\e[6~'; printf 'page=%s\n' "$setup_about_offset"
handle_input <<< $'\e[5~'; printf 'top=%s\n' "$setup_about_offset"
current_selection=1; setup_about_offset=2
setup_frame_lines=(); setup_frame_workstation
printf '%s offset=%s\n' "$setup_about_anchor" "$setup_about_offset"
printf '%s\n' "${setup_about_lines[*]}" "queue=${component_action[codex_cli]}"
''')
        self.assertRegex(output,r'bracket=[1-9][0-9]*')
        self.assertRegex(output,r'page=[1-9][0-9]*')
        self.assertEqual(output.count('top=0'),2)
        self.assertIn('workstation:setup_tools offset=0',output)
        self.assertIn('Provides the shared tools',output)
        self.assertIn('queue=install',output)
        self.assertNotIn('UNEXPECTED_ACTION',output)

    def test_bench_zones_keep_global_indices_and_do_not_select_category(self):
        output=self.shell(r'''
init_components; setup_load_bench_metadata_sync
component_status[bench_365Bench]='not installed'
setup_arrive_step 0
handle_input <<< ' '
printf '%s:%s:%s\n' "$setup_bench_zone" "${bench_items[$current_selection]}" "${component_checked[bench_365Bench]}"
handle_input <<< ' '
printf 'queued=%s\n' "${component_action[bench_365Bench]}"
handle_input < <(printf '\e[A')
printf 'up=%s\n' "$setup_bench_zone"
handle_input < <(printf '\e[Z')
printf 'tab=%s\n' "$setup_bench_zone"
handle_input < <(printf '\t')
printf 'back=%s\n' "$setup_bench_zone"
''')
        self.assertEqual(output.splitlines(),['bench:365Bench:false','queued=install','up=category','tab=bench','back=category'])

    def test_bench_panel_about_and_responsive_columns(self):
        for width in (87,69,49,40):
            output=self.shell(r'''
init_components; setup_load_bench_metadata_sync
component_status[bench_365Bench]=installed
setup_refresh_bench_counts
setup_arrive_step 0; setup_bench_zone=bench
setup_ui_width=''' + str(width) + r'''; setup_ui_height=40
setup_frame_lines=(); setup_frame_benches
printf '%s\n' "${setup_frame_lines[@]}"
''')
            self.assertIn('365Bench',output)
            self.assertIn('ABOUT',output)
            self.assertIn('Desc [2J',output)
            self.assertIn('Use it for',output)
            self.assertIn('Contains',output)
            if width<50:self.assertNotIn('Installed',output)

    def test_refresh_preserves_bench_focus_and_prunes_return_target(self):
        output=self.shell(r'''
init_components; setup_load_bench_metadata_sync
setup_arrive_step 0; setup_bench_zone=bench; setup_focus_bench_name 365Bench
setup_remember_target profiles
component_checked[bench_365Bench]=true; component_action[bench_365Bench]=install
status_loader_dir="$FIXTURE/status"; status_checks_running=true; status_loader_pid=$$
printf 'alphaBench\tdevBenches/alphaBench\n365Bench\tsysBenches/365Bench\n' > "$status_loader_dir/catalog"
poll_status_loader
printf 'kept=%s:%s:%s\n' "${bench_items[$current_selection]}" "$setup_bench_zone" "${component_action[bench_365Bench]}"
printf 'alphaBench\tdevBenches/alphaBench\n' > "$status_loader_dir/catalog"
poll_status_loader
printf 'gone=%s:%s:%s\n' "$setup_bench_zone" "$profiles_return_zone" "$profiles_return_bench"
''')
        self.assertIn('kept=365Bench:bench:install',output)
        self.assertIn('gone=category:category:',output)

    def test_unavailable_screen_is_actionable_and_not_selectable(self):
        output=self.shell(r'''
init_components --loading
setup_benches_state=unavailable; CURRENT_SECTION=0
handle_input <<< ' '
setup_frame_lines=(); setup_frame_benches
printf '%s\n' "${setup_frame_lines[@]}"
''')
        self.assertIn('The bench list could not be loaded. R retries.',output)


def load_tests(loader, tests, pattern):
    import importlib.util
    spec=importlib.util.spec_from_file_location('tool_catalog_tests', ROOT/'devcontainer.test/test-tool-catalog.py')
    module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    tests.addTests(loader.loadTestsFromModule(module))
    return tests


if __name__ == '__main__': unittest.main()
