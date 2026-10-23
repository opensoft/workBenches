#!/usr/bin/env python3
"""Reviewed-target binding, private desired state and reconstruction identity."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from setup_harnesses import HarnessError
import setup_harness_targets as targets


class TargetTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.home = Path(self.temp.name)
        self.home_patch = patch.object(Path, 'home', return_value=self.home); self.home_patch.start()
        self.addCleanup(self.home_patch.stop); self.addCleanup(self.temp.cleanup)

    def api(self, running=True):
        api = Mock()
        api.local_docker_environment.return_value = {'DOCKER_HOST': 'unix:///fixture.sock'}
        api.bench_identity.return_value = (ROOT / 'devBenches/pyBench', 'py-bench', {'py-bench:latest'})
        row = {'Id': 'a'*64, 'Config': {'User': 'developer'}, 'State': {'Running': running}}
        api.bench_resources.return_value = ({'py-bench:latest'}, [row])
        return api

    def test_preflight_rejects_foreign_resource_before_any_selection_write(self):
        api = self.api(); api.bench_resources.side_effect = ValueError('foreign checkout')
        with self.assertRaises(ValueError): targets.prepare(['pyBench'], api)
        self.assertFalse((self.home / '.config').exists())

    def test_live_target_is_pinned_to_immutable_id_and_nonroot_user(self):
        prepared = targets.prepare(['pyBench'], self.api())
        run = Mock(return_value=subprocess.CompletedProcess([], 0, 'verified', ''))
        self.assertEqual(targets.apply('install', 'qwen_cli', prepared, run), [])
        argv = run.call_args.args[0]
        self.assertEqual(argv[:6], ['docker', 'exec', '-i', '--user', 'developer', 'a'*64])
        data = json.loads(run.call_args.kwargs['input'])
        self.assertEqual(data['key'], 'qwen_cli')
        self.assertEqual(set(data['files']), {'scripts/setup_harnesses.py', 'scripts/harness-native-command.sh', 'config/harness-installers.json'})
        path = targets.selection_path('py-bench')
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertEqual(targets.read_selection(path), {'qwen_cli'})
        self.assertEqual(run.call_args.kwargs['env'], {'DOCKER_HOST': 'unix:///fixture.sock'})

    def test_stopped_bench_persists_pending_without_start_or_exec(self):
        prepared = targets.prepare(['pyBench'], self.api(running=False))
        run = Mock()
        self.assertEqual(targets.apply('install', 'qwen_cli', prepared, run), ['pyBench'])
        run.assert_not_called()
        self.assertEqual(targets.read_selection(targets.selection_path('py-bench')), {'qwen_cli'})
        targets.apply('uninstall', 'qwen_cli', prepared, run)
        self.assertEqual(targets.read_selection(targets.selection_path('py-bench')), set())

    def test_live_failure_keeps_rebuild_intent_and_reports_pending(self):
        prepared = targets.prepare(['pyBench'], self.api())
        run = Mock(return_value=subprocess.CompletedProcess([], 1, '', 'fixture failure'))
        self.assertEqual(targets.apply('update', 'qwen_cli', prepared, run), ['pyBench'])
        self.assertEqual(targets.read_selection(targets.selection_path('py-bench')), {'qwen_cli'})

    def test_interruption_cancels_only_the_same_target_operation(self):
        prepared = targets.prepare(['pyBench'], self.api())
        run = Mock(side_effect=[KeyboardInterrupt(), subprocess.CompletedProcess([], 0, '', '')])
        with self.assertRaises(KeyboardInterrupt): targets.apply('install', 'qwen_cli', prepared, run)
        original = json.loads(run.call_args_list[0].kwargs['input'])
        cancel = run.call_args_list[1].args[0]
        self.assertEqual(cancel[:5], ['docker', 'exec', '--user', 'developer', 'a'*64])
        self.assertEqual(cancel[-1], original['operation'])
        self.assertEqual(targets.read_selection(targets.selection_path('py-bench')), {'qwen_cli'})

    def test_root_duplicate_and_ambiguous_targets_are_rejected(self):
        api = self.api()
        with self.assertRaises(HarnessError): targets.prepare(['pyBench', 'pyBench'], api)
        row = {'Id': 'a'*64, 'Config': {'User': 'root'}}
        api.bench_resources.return_value = (set(), [row])
        with self.assertRaises(HarnessError): targets.prepare(['pyBench'], api)
        api.bench_resources.return_value = (set(), [row, row])
        with self.assertRaises(HarnessError): targets.prepare(['pyBench'], api)

    def test_symlink_public_and_unknown_selection_files_are_rejected(self):
        directory = self.home / 'selection'; directory.mkdir()
        for text, mode in [('qwen_cli\n', 0o644), ('unknown\n', 0o600), ('qwen_cli\nqwen_cli\n', 0o600),
                           ('qwen_cli\0\n', 0o600), ('qwen_cli\r\n', 0o600), ('qwen_cli', 0o600)]:
            path = directory / 'test.list'; path.write_text(text); path.chmod(mode)
            with self.assertRaises(HarnessError): targets.read_selection(path)
        target = directory / 'real'; target.write_text('qwen_cli\n'); target.chmod(0o600)
        link = directory / 'link'; link.symlink_to(target)
        with self.assertRaises(HarnessError): targets.read_selection(link)

    def test_personalized_image_fingerprint_changes_only_for_selected_bench(self):
        script = 'source scripts/lib/layer3-recipe.sh; layer3_recipe_sha256 user-layer "$1"'
        def digest(repo):
            return subprocess.check_output(['bash', '-c', script, 'bash', repo], cwd=ROOT,
                                           env=dict(os.environ, HOME=str(self.home)), text=True).strip()
        before = digest('py-bench'); other = digest('go-bench')
        path = targets.selection_path('py-bench')
        targets.write_selection(path, {'qwen_cli'})
        self.assertNotEqual(digest('py-bench'), before)
        self.assertEqual(digest('go-bench'), other)
        path.chmod(0o644)
        result = subprocess.run(['bash', '-c', script, 'bash', 'py-bench'], cwd=ROOT,
                                env=dict(os.environ, HOME=str(self.home)), capture_output=True)
        self.assertNotEqual(result.returncode, 0)


if __name__ == '__main__': unittest.main()
