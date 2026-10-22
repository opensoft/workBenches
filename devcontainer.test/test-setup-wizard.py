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


if __name__ == '__main__': unittest.main()
