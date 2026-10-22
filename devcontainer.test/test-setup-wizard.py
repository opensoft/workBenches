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


if __name__ == '__main__': unittest.main()
