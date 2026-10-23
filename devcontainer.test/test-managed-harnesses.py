#!/usr/bin/env python3
"""Owned-prefix, transaction, publisher archive and environment boundary tests."""
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import shutil
import sys
import tarfile
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from setup_harnesses import HarnessError, Installer, Runner, registry

ROW = dict(id='sample', label='Sample', kind='script', command='sample', executable='sample',
           platforms=['linux', 'darwin'], verify=['--version'], source='https://example.test/source',
           url='https://example.test/install', note='Synthetic fixture')


class FixtureInstaller(Installer):
    version = 'sample 1.0.0'
    fail = False

    def populate(self, row, payload, env):
        command = payload / 'sample'
        command.write_text('#!/bin/sh\nprintf "%s\\n" ' + repr(self.version) + '\nexit ' + ('1' if self.fail else '0') + '\n')
        command.chmod(0o755)
        return command


class InstallTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.home = Path(self.temp.name)
        self.installer = FixtureInstaller({'sample': ROW}, home=self.home, runner=Runner(local=True))

    def tearDown(self):
        self.temp.cleanup()

    def test_current_inventory_is_complete_and_commands_do_not_collide(self):
        rows = registry()
        catalog = json.loads((ROOT / 'config/setup-tool-catalog.json').read_text())
        baseline = {'claude_cli', 'codex_cli', 'copilot_cli', 'antigravity_cli', 'opencode_cli', 'pi_cli'}
        cli = {r['id'] for r in catalog['entries'] if r['section'] == 'harness' and r['category'] == 'tui'}
        self.assertEqual(set(rows), cli - baseline)
        self.assertEqual(len(rows), 71)
        commands = [r['command'] for r in rows.values() if r['kind'] != 'unavailable']
        self.assertEqual(len(commands), len(set(commands)))
        self.assertEqual(rows['kimi_legacy']['command'], 'kimi-legacy')
        self.assertEqual(rows['prime_agent']['command'], 'prime-agent')
        self.assertEqual(rows['devon_cli']['executable'], 'devon-tui')
        self.assertEqual(rows['autocoderover']['kind'], 'git-requirements')
        self.assertEqual(rows['mentat_cli']['kind'], 'unavailable')

    def test_install_update_and_owned_only_removal(self):
        auth = self.home / '.vendor-auth'; auth.write_text('synthetic-account')
        project = self.home / 'project'; project.mkdir()
        self.assertEqual(self.installer.status('sample'), 'not installed')
        self.installer.install('sample')
        launcher = self.home / '.local/bin/sample'
        self.assertEqual(subprocess.check_output([launcher], text=True).strip(), 'sample 1.0.0')
        self.installer.version = 'sample 2.0.0'
        self.installer.install('sample')
        self.assertEqual(subprocess.check_output([launcher], text=True).strip(), 'sample 2.0.0')
        self.assertEqual(self.installer.status('sample'), 'installed')
        receipt = (self.installer.base / 'sample/current/receipt.json')
        self.assertEqual(receipt.stat().st_mode & 0o777, 0o600)
        self.installer.uninstall('sample')
        self.assertFalse(launcher.exists())
        self.assertTrue(auth.exists())
        self.assertTrue(project.exists())

    def test_failed_update_preserves_previous_version(self):
        self.installer.install('sample')
        active = self.installer.base / 'sample/current'
        before = active.resolve()
        self.installer.fail = True
        with self.assertRaises(HarnessError):
            self.installer.install('sample')
        self.assertEqual(active.resolve(), before)
        self.assertEqual(len(list((active.parent / 'versions').iterdir())), 1)

    def test_interrupted_update_cleans_candidate(self):
        self.installer.install('sample')
        active = self.installer.base / 'sample/current'
        before = active.resolve()
        with patch.object(self.installer, 'populate', side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt):
                self.installer.install('sample')
        self.assertEqual(active.resolve(), before)
        self.assertEqual(len(list((active.parent / 'versions').iterdir())), 1)

    def test_activation_is_rolled_back_if_public_link_fails(self):
        original = Path.symlink_to
        def failing(path, target, **kwargs):
            if path == self.home / '.local/bin/sample':
                raise OSError('synthetic filesystem failure')
            return original(path, target, **kwargs)
        with patch.object(Path, 'symlink_to', failing):
            with self.assertRaises(OSError):
                self.installer.install('sample')
        self.assertFalse((self.installer.base / 'sample/current').exists())

    def test_external_launcher_and_redirected_directory_are_preserved(self):
        self.installer.bin.mkdir(parents=True)
        foreign = self.installer.bin / 'sample'; foreign.write_text('external')
        with self.assertRaises(HarnessError): self.installer.install('sample')
        self.assertEqual(foreign.read_text(), 'external')
        foreign.unlink()
        self.installer.bin.rmdir()
        self.installer.bin.symlink_to(self.home / 'elsewhere')
        with self.assertRaises(HarnessError): self.installer.install('sample')

    def test_removal_is_idempotent_so_partial_target_removal_can_retry(self):
        self.installer.install('sample')
        self.installer.uninstall('sample')
        foreign = self.installer.bin / 'sample'; foreign.write_text('unrelated external copy')
        self.installer.uninstall('sample')
        self.assertEqual(foreign.read_text(), 'unrelated external copy')

    def test_tampering_and_forged_receipt_block_removal(self):
        self.installer.install('sample')
        active = self.installer.base / 'sample/current'
        (active / 'sample').write_text('changed')
        self.assertEqual(self.installer.status('sample'), 'needs check')
        with self.assertRaises(HarnessError): self.installer.uninstall('sample')
        receipt = json.loads((active / 'receipt.json').read_text())
        receipt['entry'] = '../../../../../outside'
        (active / 'receipt.json').write_text(json.dumps(receipt))
        with self.assertRaises(HarnessError): self.installer.status('sample')

    def test_installer_environment_drops_credentials(self):
        payload = self.home / 'payload'; payload.mkdir()
        with patch.dict(os.environ, {'SYNTHETIC_API_KEY': 'test-secret', 'CLAUDE_CONFIG_DIR': '/example/account'}):
            env = self.installer.environment(payload)
        self.assertNotIn('SYNTHETIC_API_KEY', env)
        self.assertNotIn('CLAUDE_CONFIG_DIR', env)
        result = Runner(local=True).run(['sh', '-c', 'test -z "${SYNTHETIC_API_KEY:-}"'], cwd=payload, env=env)
        self.assertEqual(result.returncode, 0)

    def test_native_callback_helper_clears_inherited_secrets(self):
        control = self.home / 'operation-fixture'; control.touch()
        result = subprocess.run(['bash', str(ROOT / 'scripts/harness-native-command.sh'),
                                 str(self.home), str(self.home), str(self.home), '', str(control), '10', 'CI=1', '--',
                                 'sh', '-c', 'test -z "${SYNTHETIC_API_KEY:-}" && test "$CI" = 1'],
                                env=dict(os.environ, SYNTHETIC_API_KEY='fixture'), capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(Path(str(control) + '.done').exists())

    def test_native_callback_cancellation_kills_the_publisher_process_group(self):
        control = self.home / 'operation-fixture'; control.touch()
        sentinel = self.home / 'must-not-write'
        process = subprocess.Popen(['bash', str(ROOT / 'scripts/harness-native-command.sh'),
                                    str(self.home), str(self.home), str(self.home), '', str(control), '10', '--',
                                    'sh', '-c', 'sleep 1; touch "$1"', 'sh', str(sentinel)],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        time.sleep(0.15); control.unlink()
        process.communicate(timeout=4)
        self.assertEqual(process.returncode, 130)
        time.sleep(1)
        self.assertFalse(sentinel.exists())

    def test_local_timeout_kills_descendants(self):
        sentinel = self.home / 'must-not-write'
        with self.assertRaises(subprocess.TimeoutExpired):
            Runner(local=True).run(['sh', '-c', 'sleep 1; touch "$1"', 'sh', str(sentinel)],
                                   cwd=self.home, env=dict(os.environ), timeout=0.1)
        time.sleep(1)
        self.assertFalse(sentinel.exists())

    def test_platform_comes_from_native_host_when_using_tools(self):
        from unittest.mock import Mock
        runner = Runner(local=True)
        runner.host = Mock()
        runner.host.run.return_value = subprocess.CompletedProcess([], 0, 'Darwin\n', '')
        installer = Installer({'sample': dict(ROW, platforms=['linux'])}, home=self.home, runner=runner)
        with self.assertRaises(HarnessError): installer.install('sample')
        self.assertFalse(installer.base.exists())

    def test_archive_checksum_and_traversal_are_rejected(self):
        for filename, checksum in [('../escape', True), ('sample', False)]:
            with self.subTest(filename=filename):
                stream = io.BytesIO()
                with tarfile.open(fileobj=stream, mode='w:gz') as bundle:
                    item = tarfile.TarInfo(filename); item.size = 4
                    bundle.addfile(item, io.BytesIO(b'test'))
                body = stream.getvalue()
                release = json.dumps({'assets': [{'name': 'fixture.tar.gz', 'browser_download_url': 'https://example.test/archive'}]}).encode()
                data = {'https://api.github.com/repos/fixture/repo/releases/latest': release,
                        'https://example.test/archive': body,
                        'https://example.test/archive.sha256': (hashlib.sha256(body).hexdigest() if checksum else '0'*64).encode()}
                row = dict(ROW, kind='release', repository='fixture/repo', asset=r'fixture\.tar\.gz')
                installer = Installer({'sample': row}, home=self.home, runner=Runner(local=True), fetch=data.__getitem__)
                with self.assertRaises(HarnessError): installer.install('sample')
                self.assertFalse((self.home / 'escape').exists())

    def test_unavailable_and_wrong_platform_fail_before_mutation(self):
        with self.assertRaises(HarnessError): Installer(home=self.home).install('mentat_cli')
        installer = Installer({'sample': dict(ROW, platforms=['unsupported'])}, home=self.home)
        with self.assertRaises(HarnessError): installer.install('sample')
        self.assertFalse(installer.base.exists())

    def test_publisher_script_is_confined_to_staging_home(self):
        script = b'#!/bin/sh\nmkdir -p "$HOME/.local/bin"\nprintf "#!/bin/sh\\necho fixture-3.0.0\\n" > "$HOME/.local/bin/sample"\nchmod +x "$HOME/.local/bin/sample"\n'
        installer = Installer({'sample': ROW}, home=self.home, runner=Runner(local=True), fetch=lambda _: script)
        installer.install('sample')
        self.assertEqual(installer.status('sample'), 'installed')
        self.assertFalse((self.home / '.local/bin/sample').resolve().parent == self.home / '.local/bin')

    def test_staging_home_dependent_publisher_shim_cannot_activate(self):
        script = b'''#!/bin/sh
mkdir -p "$HOME/.local/bin"
touch "$HOME/install-only-asset"
cat > "$HOME/.local/bin/sample" <<'EOF'
#!/bin/sh
test -f "$HOME/install-only-asset"
EOF
chmod +x "$HOME/.local/bin/sample"
'''
        installer = Installer({'sample': ROW}, home=self.home, runner=Runner(local=True), fetch=lambda _: script)
        with self.assertRaises(HarnessError): installer.install('sample')
        self.assertFalse((installer.base / 'sample/current').exists())

    def test_npm_private_policy_identity_and_lifecycle_hook_contract(self):
        class PublisherRunner:
            tools = {}
            wrong = False
            def system(self): return 'linux'
            def which(self, name): return '/native/' + name
            def run(runner, argv, *, cwd, env, timeout=1800):
                self.assertNotIn('SYNTHETIC_API_KEY', env)
                if 'install' in argv:
                    prefix = Path(argv[argv.index('--prefix') + 1])
                    self.assertTrue(prefix.is_dir())
                    self.assertIn('--strict-allow-scripts', argv)
                    policy = Path(env['NPM_CONFIG_USERCONFIG']).read_text()
                    self.assertIn('allow-scripts[]=@fixture/sample\n', policy)
                    package = prefix / 'lib/node_modules/@fixture/sample'; package.mkdir(parents=True)
                    (package / 'package.json').write_text(json.dumps({'name': 'other' if runner.wrong else '@fixture/sample', 'version': '3.2.1'}))
                    (prefix / 'bin').mkdir(exist_ok=True); entry = prefix / 'bin/sample'; entry.write_text('fixture native hook output')
                return subprocess.CompletedProcess(argv, 0, '3.2.1\n', '')
        runner = PublisherRunner()
        row = dict(ROW, kind='npm', package='@fixture/sample')
        installer = Installer({'sample': row}, home=self.home, runner=runner)
        with patch.dict(os.environ, SYNTHETIC_API_KEY='fixture'):
            self.assertEqual(installer.install('sample'), '3.2.1')
        previous = (installer.base / 'sample/current').resolve()
        runner.wrong = True
        with self.assertRaisesRegex(HarnessError, 'identity'):
            installer.install('sample')
        self.assertEqual((installer.base / 'sample/current').resolve(), previous)

    def test_release_binary_uses_publisher_digest(self):
        body = b'#!/bin/sh\necho fixture-4.0.0\n'
        release = json.dumps({'assets': [{'name': 'fixture-bin', 'browser_download_url': 'https://example.test/bin',
                                         'digest': 'sha256:' + hashlib.sha256(body).hexdigest()}]}).encode()
        data = {'https://api.github.com/repos/fixture/repo/releases/latest': release, 'https://example.test/bin': body}
        row = dict(ROW, kind='release', repository='fixture/repo', asset='fixture-bin', format='binary')
        installer = Installer({'sample': row}, home=self.home, runner=Runner(local=True), fetch=data.__getitem__)
        self.assertEqual(installer.install('sample'), 'fixture-4.0.0')
        self.assertEqual(installer.status('sample'), 'installed')

    def test_redirected_ancestor_blocks_status_and_removal(self):
        other = self.home / 'other'; other.mkdir()
        (self.home / '.local').symlink_to(other)
        with self.assertRaises(HarnessError): self.installer.status('sample')
        with self.assertRaises(HarnessError): self.installer.uninstall('sample')

    def test_registry_rejects_executable_metadata_and_path_escapes(self):
        for mutation in ({'unexpected': 'command'}, {'search': ['../../outside']}, {'verify': '--help'},
                         {'arguments': '--help'}, {'kind': []}, {'environment': {'HOME': '/outside'}},
                         {'environment': {'API_KEY': 'fixture'}}, {'shell': 'eval'},
                         {'url': 'https://user:fixture@example.test/install'}):
            path = self.home / 'registry.json'
            path.write_text(json.dumps({'schemaVersion': 1, 'entries': [dict(ROW, **mutation)]}))
            with self.assertRaises(HarnessError): registry(path)

    def test_source_build_contracts_produce_runnable_launchers(self):
        for kind, companion in [('git-python', False), ('git-python', True), ('git-requirements', False), ('git-node', False)]:
            with self.subTest(kind=kind, companion=companion):
                home = self.home / (kind + str(companion)); home.mkdir()
                row = dict(ROW, kind=kind, package='fixture-backend', entry='app/main.py')
                if companion: row['tuiPackage'] = 'fixture-tui'
                if kind == 'git-node': row.update(entry='apps/cli/cli.cjs', interpreter='node')
                calls = []
                class SourceRunner:
                    tools = {}
                    def system(self): return 'linux'
                    def which(self, name): return shutil.which(name) or '/fixture/' + name
                    def run(self, argv, *, cwd, env, timeout=1800):
                        calls.append(argv)
                        tool = Path(argv[0]).name
                        payload = Path(env['UV_TOOL_DIR']).parent
                        if tool == 'git' and argv[1] == 'clone':
                            source = Path(argv[-1]); source.mkdir()
                            (source / 'package.json').write_text(json.dumps({'packageManager': 'pnpm@10.33.2'}))
                            (source / 'requirements.txt').write_text('fixture\n')
                            (source / 'app').mkdir(); (source / 'app/main.py').write_text('print("sourcefixture")\n')
                        elif tool == 'git':
                            return subprocess.CompletedProcess(argv, 0, 'a'*40 + '\n', '')
                        elif tool == 'uv' and argv[1] == 'venv':
                            binary = Path(argv[-1]) / 'bin/python'; binary.parent.mkdir(parents=True)
                            binary.symlink_to(sys.executable)
                        elif tool == 'uv' and argv[1] == 'tool':
                            directory = Path(env['UV_TOOL_BIN_DIR']); directory.mkdir()
                            name = 'fixture-backend' if companion else 'sample'
                            binary = directory / name; binary.write_text('#!/bin/sh\necho sourcefixture\n'); binary.chmod(0o755)
                        elif tool == 'npm':
                            prefix = Path(argv[argv.index('--prefix') + 1]); (prefix / 'bin').mkdir(parents=True, exist_ok=True)
                            binary = prefix / 'bin' / ('pnpm' if kind == 'git-node' else 'sample')
                            binary.write_text('#!/bin/sh\nfixture-backend\n' if companion else '#!/bin/sh\nexit 0\n'); binary.chmod(0o755)
                        elif tool == 'pnpm' and '--filter' in argv:
                            binary = Path(cwd) / row['entry']; binary.parent.mkdir(parents=True)
                            binary.write_text('console.log("sourcefixture");\n')
                        elif tool == 'sample':
                            return Runner(local=True).run(argv, cwd=cwd, env=env, timeout=timeout)
                        return subprocess.CompletedProcess(argv, 0, '', '')
                installer = Installer({'sample': row}, home=home, runner=SourceRunner())
                self.assertEqual(installer.install('sample'), 'git ' + 'a'*40)
                output = subprocess.check_output([home / '.local/bin/sample'], text=True).strip()
                self.assertEqual(output, 'sourcefixture')
                self.assertEqual(installer.status('sample'), 'installed')
                if kind == 'git-node':
                    self.assertTrue(any('pnpm@10.33.2' in argv for argv in calls))
                    self.assertTrue(any('@zcode/cli...' in argv for argv in calls))


if __name__ == '__main__': unittest.main()
