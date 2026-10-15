#!/usr/bin/env python3
"""Selected setup boundaries and checkout preservation using disposable fixtures."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
spec = importlib.util.spec_from_file_location('removal', ROOT / 'scripts/remove-bench-checkout.py')
removal = importlib.util.module_from_spec(spec)
spec.loader.exec_module(removal)


class SelectedSetupTests(unittest.TestCase):
    def test_optional_steps_run_only_when_selected_and_accounts_follow_installation(self):
        for keys, expected, npm_status in (
            (['codex_cli'], ['cli'], 0),
            (['host_shell'], ['shell'], 0),
            (['workspace_repo'], ['estate', 'workspace'], 0),
            (['workbenches_account'], [], 0),
            (['codex_cli', 'ai_accounts'], ['cli', 'accounts'], 0),
            (['codex_cli', 'ai_accounts'], ['cli'], 42),
        ):
            with self.subTest(keys=keys), tempfile.TemporaryDirectory() as temporary:
                home = Path(temporary); repo = home / 'repo'; repo.mkdir()
                shutil.copytree(ROOT / 'scripts', repo / 'scripts', ignore=shutil.ignore_patterns('__pycache__'))
                shutil.copytree(ROOT / 'config', repo / 'config')
                shutil.copytree(ROOT / 'credential-container', repo / 'credential-container', ignore=shutil.ignore_patterns('__pycache__'))
                shutil.copy(ROOT / 'setup.sh', repo / 'setup.sh')
                shutil.copy(ROOT / 'bootstrap.sh', repo / 'bootstrap.sh')
                binary = home / 'bin'; binary.mkdir()
                action_log = home / 'actions'
                scripts = {
                    'docker': '#!/bin/bash\nif [[ "$1" == info ]]; then echo linux; fi\nexit 0\n',
                    'node': '#!/bin/bash\necho v24.0.0\n',
                    'codex': '#!/bin/bash\necho "codex-cli 1.0"\n',
                    'npm': '#!/bin/bash\nif [[ "$*" == "config get prefix" ]]; then echo "$HOME/.local"; elif [[ "$1" == install || "$1" == update ]]; then echo cli >> "$ACTION_LOG"; exit "${NPM_FAULT:-0}"; fi\n',
                }
                for name, body in scripts.items():
                    file = binary / name; file.write_text(body); file.chmod(0o755)
                for name, label in (('setup-shell.sh', 'shell'), ('setup-estate-commands.sh', 'estate'),
                                    ('setup-workspace-repo.sh', 'workspace'), ('setup-ai-profiles.sh', 'accounts'),
                                    ('setup-project-command.py', 'project')):
                    file = repo / 'scripts' / name
                    body = f'#!/bin/bash\necho {label} >> "$ACTION_LOG"\n'
                    if label == 'accounts':
                        body += 'printf later > "$WORKBENCHES_AUTH_ROUTE_FILE"\n'
                    file.write_text(body); file.chmod(0o755)
                selection = {'schemaVersion': 1, 'components': [{'key': key, 'action': 'update' if key == 'codex_cli' else 'install'} for key in keys]}
                interactive = repo / 'scripts/interactive-setup.sh'
                interactive.rename(repo / 'scripts/interactive-real.sh')
                interactive.write_text('#!/bin/bash\nif [[ "$1" == --select-only ]]; then\n'
                                       + "printf '%s' '" + json.dumps(selection) + "' > \"$2\"\n"
                                       + 'else exec bash "$(dirname "$0")/interactive-real.sh" "$@"; fi\n')
                interactive.chmod(0o755)
                env = {key: value for key, value in os.environ.items()
                       if not key.startswith(('WORKBENCHES_', 'OPENAI_', 'ANTHROPIC_', 'CODEX_', 'CLAUDE_'))}
                env.update(HOME=str(home), XDG_CONFIG_HOME=str(home / '.config'),
                           AGENT_PROTOCOL_ROOT=str(home / '.agents'), ACTION_LOG=str(action_log),
                           NPM_FAULT=str(npm_status),
                           PATH=str(binary) + ':' + os.environ['PATH'], TERM='xterm')
                input_options = {'input': '\n'} if 'workbenches_account' in keys else {'stdin': subprocess.DEVNULL}
                result = subprocess.run(['bash', str(repo / 'setup.sh')], env=env,
                                        **input_options, capture_output=True, text=True, timeout=15)
                self.assertEqual(result.returncode, 1 if npm_status else 0, result.stdout + result.stderr)
                self.assertEqual(action_log.read_text().splitlines() if action_log.exists() else [], expected)
                if 'workbenches_account' in keys:
                    self.assertIn('optional account setup deferred', result.stdout)
                    self.assertFalse((home / '.config/workbenches/account-session.json').exists())
                self.assertNotIn('Apply these changes?', result.stdout)
                self.assertNotIn('Authentication requirements', result.stdout)
                self.assertNotIn('Press Enter to continue', result.stdout)
                if 'ai_accounts' not in keys:
                    self.assertNotIn('Authentication route', result.stdout)
                elif not npm_status:
                    self.assertIn('Authentication pending', result.stdout)


class CheckoutRemovalTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(); self.addCleanup(self.temporary.cleanup)
        self.git_env = dict(os.environ, GIT_CONFIG_GLOBAL='/dev/null', GIT_CONFIG_NOSYSTEM='1')
        self.root = Path(self.temporary.name); self.checkout = self.root / 'devBenches/testBench'
        seed = self.root / 'seed'; seed.mkdir()
        self.run_git(seed, 'init', '-q')
        (seed / 'README').write_text('shared source')
        (seed / '.gitignore').write_text('.private\n')
        self.run_git(seed, 'add', '.')
        self.run_git(seed, 'commit', '-qm', 'seed')
        subprocess.run(['git', 'clone', '-q', str(seed), str(self.checkout)], check=True, env=self.git_env)
        (self.root / 'config').mkdir()
        (self.root / 'config/bench-config.json').write_text(json.dumps({'benches': {'testBench': {'path': 'devBenches/testBench'}}}))
        self.addCleanup(patch.stopall)
        patch.object(removal, 'ROOT', self.root).start()
        patch.object(removal.sys, 'argv', ['remove', '--bench', 'testBench']).start()
        patch.object(removal.sys.stdin, 'isatty', return_value=True).start()
        self.real_output = subprocess.check_output
        def output(argv, **kwargs):
            if argv[0] == 'docker':
                return ''
            return self.real_output(argv, **kwargs)
        self.command = patch.object(removal.subprocess, 'check_output', side_effect=output).start()
        self.answer = patch.object(removal, 'prompt', return_value='y').start()

    def run_git(self, directory, *args):
        return subprocess.run(['git', '-C', str(directory), '-c', 'user.name=Fixture',
                               '-c', 'user.email=fixture@example.test', *args], check=True,
                              capture_output=True, text=True, env=self.git_env)

    def blocked(self):
        with self.assertRaises((ValueError, subprocess.CalledProcessError)):
            removal.main()
        self.assertTrue(self.checkout.exists())
        self.answer.assert_not_called()

    def test_modified_source_is_preserved_without_prompting(self):
        (self.checkout / 'README').write_text('local edit'); self.blocked()

    def test_untracked_files_are_preserved_without_prompting(self):
        (self.checkout / 'notes').write_text('local work'); self.blocked()

    def test_ignored_files_are_preserved_without_prompting(self):
        (self.checkout / '.private').write_text('test marker'); self.blocked()

    def test_local_only_commits_on_another_branch_are_preserved(self):
        branch = self.run_git(self.checkout, 'branch', '--show-current').stdout.strip()
        self.run_git(self.checkout, 'checkout', '-qb', 'local-only')
        (self.checkout / 'README').write_text('local commit')
        self.run_git(self.checkout, 'commit', '-qam', 'local work')
        self.run_git(self.checkout, 'checkout', '-q', branch)
        self.blocked()

    def test_running_container_blocks_checkout_removal(self):
        def output(argv, **kwargs):
            if argv[:2] == ['docker', 'ps']: return 'running\n'
            if argv[:2] == ['docker', 'inspect']:
                return json.dumps([{'Mounts': [{'Source': str(self.checkout)}]}])
            return self.real_output(argv, **kwargs)
        self.command.side_effect = output
        self.blocked()

    def test_clean_checkout_is_deleted_only_after_confirmation(self):
        marker = self.root / 'credentials'; marker.write_text('test marker')
        self.assertEqual(removal.main(), 0)
        self.answer.assert_called_once()
        self.assertFalse(self.checkout.exists())
        self.assertEqual(marker.read_text(), 'test marker')

    def test_declining_keeps_the_clean_checkout(self):
        self.answer.return_value = 'n'
        self.assertEqual(removal.main(), 1)
        self.assertTrue(self.checkout.exists())

    def test_closed_input_never_deletes(self):
        with patch.object(removal.sys.stdin, 'isatty', return_value=False):
            self.blocked()

    def test_local_work_created_during_confirmation_is_preserved(self):
        def answer(_):
            (self.checkout / 'new-work').write_text('arrived during prompt')
            return 'y'
        self.answer.side_effect = answer
        with self.assertRaisesRegex(ValueError, 'local changes'):
            removal.main()
        self.assertEqual((self.checkout / 'new-work').read_text(), 'arrived during prompt')

    def test_symlink_checkout_is_preserved(self):
        saved = self.root / 'saved'
        self.checkout.rename(saved)
        self.checkout.symlink_to(saved, target_is_directory=True)
        self.blocked()
        self.assertTrue(saved.is_dir())


if __name__ == '__main__':
    unittest.main()
