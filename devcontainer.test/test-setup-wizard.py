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
CURRENT_SECTION=1; component_status[codex_cli]=installed; current_selection=2
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


if __name__ == '__main__': unittest.main()
