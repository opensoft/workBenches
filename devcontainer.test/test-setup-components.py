#!/usr/bin/env python3
"""Installation evidence and scoped removal using disposable fixtures."""
import importlib.util
import contextlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
spec = importlib.util.spec_from_file_location('components', ROOT / 'scripts/setup-components.py')
components = importlib.util.module_from_spec(spec)
spec.loader.exec_module(components)


class ToolRemovalTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(); self.addCleanup(self.temporary.cleanup)
        self.home = Path(self.temporary.name)
        self.addCleanup(patch.stopall)
        patch.object(components.Path, 'home', return_value=self.home).start()
        patch.object(components, 'package_installation', return_value=None).start()
        self.which = patch.object(components.shutil, 'which', return_value=None).start()

    def executable(self, path):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text('#!/bin/sh\nexit 0\n'); path.chmod(0o755)
        return path

    def test_saved_terminal_settings_are_not_installed_apps(self):
        for name in ('.warp', '.waveterm'):
            (self.home / name).mkdir()
        self.assertFalse(components.tool_installed('warp'))
        self.assertFalse(components.tool_installed('wave'))

    def test_native_binary_outside_path_is_detected(self):
        binary = self.executable(self.home / '.local/bin/claude')
        self.assertEqual(components.executable_paths('claude_cli'), [binary])

    def test_native_claude_removal_preserves_credentials_and_projects(self):
        version = self.executable(self.home / '.local/share/claude/versions/1.0')
        launcher = self.home / '.local/bin/claude'; launcher.parent.mkdir(parents=True)
        launcher.symlink_to(version)
        credential = self.home / '.claude/.credentials.json'; credential.parent.mkdir()
        credential.write_text('fixture credential')
        project = self.home / 'projects/local-work'; project.parent.mkdir()
        project.write_text('fixture project')
        components.uninstall_tool('claude_cli')
        self.assertFalse(launcher.exists())
        self.assertFalse(version.exists())
        self.assertEqual(credential.read_text(), 'fixture credential')
        self.assertEqual(project.read_text(), 'fixture project')

    def test_native_launcher_to_unrecognized_target_is_preserved(self):
        target = self.executable(self.home / 'personal/claude')
        launcher = self.home / '.local/bin/claude'; launcher.parent.mkdir(parents=True)
        launcher.symlink_to(target)
        with self.assertRaisesRegex(ValueError, 'Unrecognized installation'):
            components.uninstall_tool('claude_cli')
        self.assertTrue(launcher.is_symlink())
        self.assertTrue(target.is_file())

    def npm_fixture(self, component):
        prefix = self.home / 'actual-prefix'
        package = prefix / 'lib/node_modules' / components.NPM[component]
        package.mkdir(parents=True)
        (package / 'package.json').write_text(json.dumps({'name': components.NPM[component]}))
        target = self.executable(package / 'cli.js')
        launcher = prefix / 'bin' / components.COMMANDS[component][0]
        launcher.parent.mkdir(parents=True); launcher.symlink_to(target)
        return prefix, launcher

    def test_npm_removes_actual_prefix_instead_of_new_empty_prefix(self):
        prefix, launcher = self.npm_fixture('codex_cli')
        self.which.side_effect = lambda name: '/fixture/npm' if name == 'npm' else None
        with patch.object(components, 'read_command', return_value=subprocess.CompletedProcess([], 0, str(self.home / 'empty-prefix'))):
            command = components.npm_removal('codex_cli', launcher)
        self.assertEqual(command, ['/fixture/npm', 'uninstall', '--global', '--ignore-scripts', '--prefix', str(prefix), '@openai/codex'])

    def test_npm_does_not_remove_unrelated_binary(self):
        _, _ = self.npm_fixture('codex_cli')
        unrelated = self.executable(self.home / 'personal/codex')
        self.which.side_effect = lambda name: '/fixture/npm' if name == 'npm' else None
        with patch.object(components, 'read_command', return_value=subprocess.CompletedProcess([], 0, str(self.home / 'actual-prefix'))):
            self.assertIsNone(components.npm_removal('codex_cli', unrelated))
        self.assertTrue(unrelated.is_file())

    def test_npm_removal_is_verified_and_failed_removal_stays_installed(self):
        for succeeds in (False, True):
            with self.subTest(succeeds=succeeds):
                prefix, launcher = self.npm_fixture('pi_cli')
                self.which.side_effect = lambda name: str(launcher) if name == 'pi' and launcher.exists() else ('/fixture/npm' if name == 'npm' else None)
                def apply(_):
                    if succeeds: launcher.unlink()
                with patch.object(components, 'read_command', return_value=subprocess.CompletedProcess([], 0, str(prefix))), patch.object(components, 'apply_command', side_effect=apply):
                    if succeeds:
                        components.uninstall_tool('pi_cli')
                    else:
                        with self.assertRaisesRegex(ValueError, 'still installed'):
                            components.uninstall_tool('pi_cli')
                        self.assertTrue(launcher.exists())
                        launcher.unlink()
                # Keep this subtest's metadata out of the next fixture.
                import shutil
                shutil.rmtree(prefix)

    def test_native_agy_standalone_binary_is_removed(self):
        binary = self.executable(self.home / '.local/bin/agy')
        binary.write_bytes(b'\x7fELFfixture native binary')
        components.uninstall_tool('antigravity_cli')
        self.assertFalse(binary.exists())

    def test_custom_local_wrapper_is_preserved(self):
        binary = self.executable(self.home / '.local/bin/agy')
        with self.assertRaisesRegex(ValueError, 'Unrecognized installation'):
            components.uninstall_tool('antigravity_cli')
        self.assertTrue(binary.exists())

    def test_setup_removes_host_cli_without_installing_docker_or_node(self):
        repo = self.home / 'repo'; repo.mkdir()
        import shutil
        shutil.copytree(ROOT / 'scripts', repo / 'scripts', ignore=shutil.ignore_patterns('__pycache__'))
        shutil.copytree(ROOT / 'config', repo / 'config')
        shutil.copytree(ROOT / 'credential-container', repo / 'credential-container', ignore=shutil.ignore_patterns('__pycache__'))
        for name in ('setup.sh', 'bootstrap.sh'): shutil.copy(ROOT / name, repo / name)
        prefix = self.home / '.local'
        package = prefix / 'lib/node_modules/@openai/codex'; package.mkdir(parents=True)
        (package / 'package.json').write_text('{"name":"@openai/codex"}')
        target = self.executable(package / 'cli.js')
        launcher = prefix / 'bin/codex'; launcher.parent.mkdir(parents=True); launcher.symlink_to(target)
        binary = self.home / 'fake-bin'; binary.mkdir()
        # Expose only required utilities. Never let a fixture fall through to
        # the engineer's real CLI installations or package-manager executables.
        for name in ('bash', 'sh', 'python3', 'git', 'jq', 'curl', 'date', 'dirname',
                     'mkdir', 'tee', 'ls', 'tail', 'xargs', 'rm', 'mktemp', 'whoami',
                     'uname', 'tput', 'clear', 'cat', 'cmp', 'hostname', 'grep', 'head'):
            # shutil.which is patched for unit probes in this class; resolve
            # the utilities through the subprocess shell instead.
            located = subprocess.check_output(['/bin/sh', '-c', 'command -v "$1"', 'sh', name], text=True).strip()
            (binary / name).symlink_to(located)
        for name, body in {
            'docker': '#!/bin/bash\necho "docker $*" >> "$HOME/actions"\nexit 99\n',
            'npm': '#!/bin/bash\nif [[ "$1" == prefix ]]; then echo "$HOME/empty-prefix"; elif [[ "$1" == uninstall ]]; then echo uninstall >> "$HOME/actions"; rm "$HOME/.local/bin/codex"; else echo "unexpected npm $*" >> "$HOME/actions"; exit 99; fi\n',
        }.items():
            path = binary / name; path.write_text(body); path.chmod(0o755)
        interactive = repo / 'scripts/interactive-setup.sh'
        interactive.rename(repo / 'scripts/interactive-real.sh')
        interactive.write_text('''#!/bin/bash
if [[ "$1" == --select-only ]]; then
    echo '{"schemaVersion":1,"components":[{"key":"codex_cli","action":"uninstall"}]}' > "$2"
else exec bash "$(dirname "$0")/interactive-real.sh" "$@"; fi
''')
        interactive.chmod(0o755)
        env = {key: value for key, value in os.environ.items() if not key.startswith(('WORKBENCHES_', 'OPENAI_', 'ANTHROPIC_', 'CODEX_', 'CLAUDE_'))}
        env.update(HOME=str(self.home), XDG_CONFIG_HOME=str(self.home / '.config'),
                   XDG_DATA_HOME=str(self.home / '.local/share'), AGENT_PROTOCOL_ROOT=str(self.home / '.agents'),
                   PATH=str(binary) + ':' + str(prefix / 'bin'), TERM='xterm')
        result = subprocess.run(['bash', str(repo / 'setup.sh')], env=env,
                                stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(launcher.exists())
        self.assertIn('Host-tool removal does not require Docker', result.stdout)
        actions = (self.home / 'actions').read_text().splitlines()
        self.assertIn('uninstall', actions)
        self.assertFalse(any('docker info' in action or 'unexpected npm' in action for action in actions), actions)


class BenchRemovalTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(); self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / 'config').mkdir()
        (self.root / 'config/bench-config.json').write_text(json.dumps({'benches': {'pyBench': {'path': 'devBenches/pyBench'}}}))
        self.checkout = self.root / 'devBenches/pyBench'; self.checkout.mkdir(parents=True)
        self.note = self.checkout / 'local-work'; self.note.write_text('keep local work')
        self.container = {'Id': 'selected', 'Name': '/py-bench', 'Config': {'Image': 'py-bench:latest', 'Labels': {'com.docker.compose.project.working_dir': str(self.checkout)}}, 'State': {'Running': True}}
        self.images = {'py-bench:latest', 'py-bench:fixture', 'dev-bench-base:latest', 'unrelated:latest'}
        self.containers = [self.container]
        self.calls = []
        self.addCleanup(patch.stopall)
        patch.object(components, 'ROOT', self.root).start()
        patch.dict(os.environ, {'USER': 'fixture', 'DOCKER_HOST': 'unix:///fixture.sock'}).start()
        patch.object(components, 'docker_inventory', side_effect=lambda env=None: (self.images.copy(), self.containers.copy())).start()
        def apply(argv, env=None):
            self.calls.append(argv)
            if argv[1:3] == ['container', 'rm']: self.containers = []
            if argv[1:3] == ['image', 'rm']: self.images -= set(argv[3:])
        patch.object(components, 'apply_command', side_effect=apply).start()

    def test_only_selected_runtime_is_removed_and_local_work_is_preserved(self):
        components.uninstall_bench('pyBench')
        self.assertEqual(self.calls, [['docker', 'container', 'stop', '--time', '10', 'selected'], ['docker', 'container', 'rm', 'selected'], ['docker', 'image', 'rm', 'py-bench:fixture', 'py-bench:latest']])
        self.assertEqual(self.images, {'dev-bench-base:latest', 'unrelated:latest'})
        self.assertEqual(self.note.read_text(), 'keep local work')
        self.assertEqual(components.bench_resources('pyBench', components.docker_inventory()), (set(), []))

    def test_stopped_container_is_removed_without_stop(self):
        self.container['State']['Running'] = False
        components.uninstall_bench('pyBench')
        self.assertFalse(any('stop' in command for command in self.calls))

    def test_foreign_container_with_same_name_blocks_removal(self):
        self.container['Config']['Labels']['com.docker.compose.project.working_dir'] = '/other/project'
        with self.assertRaisesRegex(ValueError, 'another installation'):
            components.uninstall_bench('pyBench')
        self.assertEqual(self.calls, [])

    def test_other_container_using_image_is_preserved(self):
        self.containers.append({'Id': 'other', 'Name': '/other', 'Config': {'Image': 'py-bench:latest'}})
        with self.assertRaisesRegex(ValueError, 'Another container'):
            components.uninstall_bench('pyBench')
        self.assertEqual(self.calls, [])

    def test_remote_docker_context_cannot_be_modified(self):
        with patch.dict(os.environ, {'DOCKER_HOST': 'ssh://remote'}):
            with self.assertRaisesRegex(ValueError, 'local Docker socket'):
                components.uninstall_bench('pyBench')
        self.assertEqual(self.calls, [])

    def test_explicit_context_overrides_a_local_host_environment(self):
        with patch.dict(os.environ, {'DOCKER_CONTEXT': 'remote', 'DOCKER_HOST': 'unix:///fixture.sock'}), patch.object(components, 'read_command', return_value=subprocess.CompletedProcess([], 0, 'ssh://remote')) as read:
            with self.assertRaisesRegex(ValueError, 'local Docker socket'):
                components.uninstall_bench('pyBench')
            self.assertEqual(read.call_args.args[0][:4], ['docker', 'context', 'inspect', 'remote'])
        self.assertEqual(self.calls, [])

    def test_symlink_checkout_cannot_claim_another_runtime(self):
        target = self.root / 'other-project'; target.mkdir()
        self.checkout.rename(self.root / 'saved-checkout')
        self.checkout.symlink_to(target, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'symlink'):
            components.uninstall_bench('pyBench')
        self.assertEqual(self.calls, [])

    def test_repeated_removal_is_an_idempotent_noop(self):
        self.images = {'dev-bench-base:latest'}; self.containers = []
        components.uninstall_bench('pyBench')
        self.assertEqual(self.calls, [])

    def test_base_image_only_is_not_reported_as_a_complete_install(self):
        self.containers = []; self.images = {'py-bench:latest', 'dev-bench-base:latest'}
        with contextlib.redirect_stdout(io.StringIO()) as output:
            components.bench_statuses()
        self.assertEqual(output.getvalue(), 'pyBench\timage only\n')
        self.images.add('py-bench:fixture')
        with contextlib.redirect_stdout(io.StringIO()) as output:
            components.bench_statuses()
        self.assertEqual(output.getvalue(), 'pyBench\tinstalled\n')


class TuiAndWindowsTests(unittest.TestCase):
    def test_refresh_preserves_pending_selection(self):
        with tempfile.TemporaryDirectory() as temporary:
            env = dict(os.environ, WORKBENCHES_SETUP_LOG_FILE=str(Path(temporary) / 'ui.log'))
            command = f'''source "{ROOT}/scripts/interactive-setup.sh"
init_components
component_status[codex_cli]=installed
component_checked[codex_cli]=true
component_action[codex_cli]=update
refresh_component_statuses() {{ component_status[codex_cli]='needs creds'; }}
draw_ui() {{ :; }}
handle_input
printf '%s:%s:%s' "${{component_checked[codex_cli]}}" "${{component_action[codex_cli]}}" "${{component_status[codex_cli]}}"
'''
            result = subprocess.run(['bash', '-c', command], env=env, input='R', capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, 'true:update:needs creds')

    def test_configured_actions_are_reconfigured_without_deleting_data(self):
        with tempfile.TemporaryDirectory() as temporary:
            env = dict(os.environ, WORKBENCHES_SETUP_LOG_FILE=str(Path(temporary) / 'ui.log'))
            command = f'''source "{ROOT}/scripts/interactive-setup.sh"
init_components
component_status[host_shell]=configured
CURRENT_SECTION=2; current_selection=5
handle_input; handle_input
printf '%s:%s' "${{component_checked[host_shell]}}" "${{component_action[host_shell]}}"
'''
            result = subprocess.run(['bash', '-c', command], env=env, input=' D', capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, 'true:install')

    def test_windows_removal_uses_exact_package_and_propagates_failure(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary); log = directory / 'commands'
            binary = directory / 'powershell.exe'
            binary.write_text('#!/bin/bash\nprintf "%s\\n" "$*" >> "$TEST_LOG"\nexit "$TEST_WINDOWS_EXIT"\n')
            binary.chmod(0o755)
            for status, expected in ((0, 0), (7, 1)):
                env = dict(os.environ, WSL_DISTRO_NAME='fixture', TEST_LOG=str(log),
                           TEST_WINDOWS_EXIT=str(status), WORKBENCH_LOG_FILE=str(directory / 'windows.log'),
                           PATH=str(directory) + ':' + os.environ['PATH'])
                result = subprocess.run(['bash', str(ROOT / 'scripts/setup-windows-tools.sh'), '--uninstall', 'wave'],
                                        env=env, capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
                command = log.read_text()
                self.assertIn("uninstall --exact --id 'CommandLine.Wave'", command)
                self.assertIn('exit $LASTEXITCODE', command)


if __name__ == '__main__':
    unittest.main()
