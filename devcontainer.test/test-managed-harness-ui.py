#!/usr/bin/env python3
"""The same trusted recipes must control both native and Python plan paths."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from setup_harnesses import registry
import setup_selection


class IntegrationTests(unittest.TestCase):
    def test_all_enabled_recipes_are_accepted_by_both_plan_readers(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'selection.json'
            enabled = [key for key, row in registry().items() if row['kind'] != 'unavailable']
            for action in ('install', 'update', 'uninstall'):
                path.write_text(json.dumps({'schemaVersion': 1, 'components': [{'key': key, 'action': action} for key in enabled]}))
                path.chmod(0o600)
                self.assertEqual(len(setup_selection.load(path)[0]), 70)
                result = subprocess.run(['bash', '-c', 'source scripts/lib/setup-workstation-lifecycle.sh; workstation_plan_read "$1"',
                                         'bash', str(path)], cwd=ROOT, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_unavailable_and_manual_gui_still_cannot_enter_apply_plan(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / 'selection.json'
            for key in ('mentat_cli', 'codex_gui', 'kimi_desktop', 'invented_cli'):
                path.write_text(json.dumps({'schemaVersion': 1, 'components': [{'key': key, 'action': 'install'}]})); path.chmod(0o600)
                with self.assertRaises(ValueError): setup_selection.load(path)
                result = subprocess.run(['bash', '-c', 'source scripts/lib/setup-workstation-lifecycle.sh; workstation_plan_read "$1"',
                                         'bash', str(path)], cwd=ROOT, capture_output=True)
                self.assertNotEqual(result.returncode, 0)

    def test_image_runtime_matches_canonical_sources(self):
        subprocess.run([sys.executable, 'scripts/setup-tool-catalog.py', '--check'], cwd=ROOT, check=True)

    def test_new_harnesses_do_not_enable_unimplemented_profile_adapters(self):
        self.assertNotIn('kimi_code', setup_selection.AI)
        self.assertNotIn('qwen_cli', setup_selection.AI)
        self.assertIn('kimi_code', setup_selection.NODE)
        self.assertIn('zcode_cli', setup_selection.NODE)

    def test_narrow_review_keeps_every_exact_target_readable(self):
        script = '''source scripts/interactive-setup.sh
init_components --loading
setup_ui_width=36; setup_ui_height=24
for key in "${requirement_items[@]}"; do component_status[$key]=up; done
bench_items=(365Bench selectedOneBench selectedTwoBench)
for key in "${bench_items[@]}"; do
 component_checked[bench_$key]=true; component_action[bench_$key]=update
done
component_checked[qwen_cli]=true; component_action[qwen_cli]=install
setup_frame_review
printf '%s\\n' "${setup_review_rows[@]}"
'''
        result = subprocess.run(['bash', '-c', script], cwd=ROOT, text=True, capture_output=True,
                                env=dict(os.environ, WORKBENCHES_SETUP_LOG_FILE='/dev/null'))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Targets: Workstation', result.stdout)
        for name in ('365Bench', 'selectedOneBench', 'selectedTwoBench'):
            self.assertIn(name, result.stdout)
        for row in result.stdout.splitlines():
            if 'Targets:' in row or 'selected' in row:
                self.assertLessEqual(len(row), 36)

    def test_bench_removal_can_retry_after_workstation_copy_was_removed(self):
        script = '''source scripts/interactive-setup.sh
init_components --loading
setup_cli_filters_clear
for key in "${ai_items[@]}"; do component_status[$key]='not installed'; done
component_checked[bench_365Bench]=true; component_action[bench_365Bench]=update
bench_items=(365Bench)
setup_arrive_step 1; setup_harness_zone=harness; setup_focus_harness_key qwen_cli
handle_input <<< D
[[ "${component_action[qwen_cli]}" == uninstall ]] || exit 1
setup_focus_harness_key codex_cli
handle_input <<< D
[[ -z "${component_action[codex_cli]}" ]] || exit 2
'''
        result = subprocess.run(['bash', '-c', script], cwd=ROOT, text=True, capture_output=True,
                                env=dict(os.environ, WORKBENCHES_SETUP_LOG_FILE='/dev/null'))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__': unittest.main()
