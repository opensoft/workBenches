#!/usr/bin/env python3
"""Release evidence must fail closed; no runners, credentials or cloud required."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import release_validation as rv


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    value = importlib.util.module_from_spec(spec); spec.loader.exec_module(value)
    return value


publisher = module('publisher', 'scripts/publish-validated-release.py')
preflight = module('preflight', 'scripts/release-qa-preflight.py')
watchdog = module('watchdog', 'scripts/release-qa-watchdog.py')
native = module('native', 'scripts/release-qa-native.py')
native_controller = module('native_controller', 'qa/release/run-native-arch.py')
image_source = module('image_source', 'scripts/release-qa-image-source.py')


class ReleaseAutomationTests(unittest.TestCase):
    def test_native_capacity_refusal_preserves_host_and_does_not_create_job(self):
        golden = Path(self.temp.name) / 'golden'; golden.mkdir()
        rv.atomic(golden / 'prepared.json', {'state': 'prepared-not-registered', 'cleanup': 'vm-stopped'})
        state = Path(self.temp.name) / 'new-native-job'
        with patch.object(native_controller.os, 'access', return_value=True), \
             patch.object(native_controller, 'native_capacity_available', return_value=False), \
             patch.object(native_controller.VM, 'launch') as launch:
            with self.assertRaisesRegex(ValueError, 'host headroom'):
                native_controller.run(golden, state, self.root, ROOT)
        launch.assert_not_called()
        self.assertFalse(state.exists())

    def test_invalid_vm_memory_cannot_start_a_process(self):
        with patch.object(native_controller.VM.subprocess, 'Popen') as launch:
            for memory in (True, 0, 32769, '8192'):
                with self.assertRaises(ValueError):
                    native_controller.VM.launch(self.reports, {'memoryMiB': memory})
        launch.assert_not_called()

    def test_signal_failure_reports_exit_and_resource_delta_without_private_output(self):
        fixture_value = 'fixture-process-output'
        diagnostic = {}
        with patch.object(rv, 'host_resources', side_effect=[{'oomKills': 3}, {'oomKills': 3}]):
            passed = rv.execute([sys.executable, '-c',
                f'import os,signal; print({fixture_value!r},flush=True); os.kill(os.getpid(),signal.SIGKILL)'],
                self.root, dict(os.environ), 10, diagnostic)
        self.assertFalse(passed)
        self.assertEqual(diagnostic['exitCode'], -9)
        self.assertEqual(diagnostic['resources']['oomKillDelta'], 0)
        self.assertNotIn(fixture_value, json.dumps(diagnostic))

    def test_failed_fixture_command_output_is_encrypted_before_log_closes(self):
        import tarfile
        fixture_value = 'private-fixture-driver-output'
        cert, key = self.certificate()
        encrypted = self.reports / 'fresh-install-debug.cms'
        real_run = subprocess.run
        def command(argv, **kwargs):
            if argv[:2] == ['docker', 'compose']:
                return subprocess.CompletedProcess(argv, 1)
            return real_run(argv, **kwargs)
        diagnostic = {}
        with patch.object(rv.subprocess, 'run', side_effect=command):
            capture = lambda log: rv.workstation_diagnostics(self.root, 'fixture',
                                                             dict(os.environ, OPENBENCHES_QA_FAILURE_CERT_PEM=cert.read_text()),
                                                             encrypted, log)
            self.assertFalse(rv.execute([sys.executable, '-c', f'print({fixture_value!r}); raise SystemExit(7)'],
                                       self.root, dict(os.environ), 10, diagnostic, capture))
        self.assertEqual(diagnostic['exitCode'], 7)
        self.assertNotIn(fixture_value, json.dumps(diagnostic))
        self.assertNotIn(fixture_value.encode(), encrypted.read_bytes())
        decoded = self.reports / 'decoded.tgz'
        subprocess.run(['openssl', 'cms', '-decrypt', '-binary', '-inform', 'DER', '-in', str(encrypted),
                        '-inkey', str(key), '-recip', str(cert), '-out', str(decoded)], check=True, capture_output=True)
        with tarfile.open(decoded) as archive:
            self.assertEqual(archive.getnames(), ['fixture-driver.log'])
            self.assertIn(fixture_value.encode(), archive.extractfile('fixture-driver.log').read())

    def test_image_plan_is_data_and_must_match_exact_expected_commit(self):
        path = Path(self.temp.name) / 'image-plan.json'
        identity = dict(commit='a' * 40, version='1.6.0-rc.3')
        rv.atomic(path, {'source': identity})
        self.assertEqual(image_source.planned_identity(path, 'a' * 40), identity)
        for expected in ('b' * 40, 'main', 'a' * 40 + '\n'):
            with self.assertRaises(rv.ValidationError): image_source.planned_identity(path, expected)
        rv.atomic(path, {'source': dict(identity, version='../../other')})
        with self.assertRaises(rv.ValidationError): image_source.planned_identity(path, 'a' * 40)

    def test_image_publication_requires_current_main_or_exact_protected_release(self):
        identity = dict(commit='a' * 40, version='1.6.0-rc.3')
        for main, release, expected in (
            ('a' * 40, {}, True),
            ('b' * 40, {'protected': True, 'commit': {'sha': 'a' * 40}}, True),
            ('b' * 40, {'protected': False, 'commit': {'sha': 'a' * 40}}, False),
            ('b' * 40, {'protected': True, 'commit': {'sha': 'c' * 40}}, False),
            ('b' * 40, {}, False),
        ):
            with self.subTest(main=main, release=release):
                calls = []
                def fetch(path):
                    calls.append(path)
                    return {'commit': {'sha': main}} if path == 'branches/main' else release
                self.assertEqual(image_source.authorize(identity, fetch), expected)
                self.assertEqual(calls, ['branches/main'] if main == identity['commit'] else
                                 ['branches/main', 'branches/release%2F1.6.0'])

    def test_image_source_lookup_failure_cannot_authorize_publication(self):
        def unavailable(path): raise OSError('unavailable')
        with self.assertRaises(OSError):
            image_source.authorize(dict(commit='a' * 40, version='1.6.0'), unavailable)

    def test_current_automation_keeps_legacy_entrypoints_for_supported_candidates(self):
        manifest = rv.load_manifest()
        supported = manifest['supportedReleaseLines']
        self.assertTrue({'1.5', '1.6', '1.7'}.issubset(supported), supported)
        current = (ROOT / 'VERSION').read_text().strip()
        for product in dict.fromkeys([line + '.0' for line in supported] + [current]):
            with self.subTest(product=product):
                source = rv.selected(manifest, product, 'release')['source']
                selected = rv.cases(source, product)
                commands = {command['id']: command['argv'] for command in source['commands']
                            if command['id'] in selected}
                self.assertEqual(commands['source-lock'],
                                 ['python3', 'scripts/release-workbenches.py', 'check'])
                self.assertEqual(commands['release-regressions'],
                                 ['python3', 'devcontainer.test/test-release-version.py'])

    def test_legacy_shared_image_release_asset_reader_is_unchanged(self):
        shared = module('legacy_shared_images', 'scripts/shared-images.py')
        source = 'legacy-source'
        image = 'ghcr.io/opensoft/workbenches-base@sha256:' + 'd' * 64
        release_tag = 'shared-images-historical'
        payload = json.dumps({'schemaVersion': 1, 'images': {'base': {'linux/amd64': {
            'sourceHash': source, 'image': image}}}}).encode()
        row = {'Os': 'linux', 'Architecture': 'amd64', 'Config': {'Labels': {shared.LABEL: source}}}
        calls = []

        class Response:
            def __enter__(self): return self
            def __exit__(self, *args): return False
            def read(self, limit): return payload[:limit]

        def command(argv, **kwargs):
            calls.append((argv, kwargs))
            if argv[:2] == ['docker', 'info']:
                return subprocess.CompletedProcess(argv, 0, stdout='linux/x86_64\n')
            if argv[:2] == ['docker', 'context']:
                return subprocess.CompletedProcess(argv, 0, stdout='unix:///fixture.sock\n')
            return subprocess.CompletedProcess(argv, 0)

        with patch.object(shared, 'fingerprint', return_value=source), \
             patch.object(shared, 'release_tag', return_value=release_tag), \
             patch.object(shared, 'inspect', side_effect=[None, row]), \
             patch.object(shared.subprocess, 'run', side_effect=command), \
             patch.object(shared.urllib.request, 'urlopen', return_value=Response()) as network, \
             patch.dict(os.environ, {'DOCKER_HOST': 'unix:///fixture.sock', 'DOCKER_CONTEXT': ''}):
            self.assertEqual(shared.ensure('base'), 0)
        network.assert_called_once_with(
            f'https://github.com/opensoft/workBenches/releases/download/{release_tag}/shared-images.json', timeout=8)
        pulls = [(argv, kwargs) for argv, kwargs in calls if argv[:2] == ['docker', 'pull']]
        self.assertEqual(len(pulls), 1)
        self.assertEqual(pulls[0][0], ['docker', 'pull', '--platform', 'linux/amd64', image])
        self.assertEqual(pulls[0][1]['env']['DOCKER_HOST'], 'unix:///fixture.sock')
        self.assertIn('DOCKER_CONFIG', pulls[0][1]['env'])
        self.assertNotIn('DOCKER_CONTEXT', pulls[0][1]['env'])
        self.assertIn(['docker', 'tag', image, 'workbench-base:latest'], [argv for argv, _ in calls])

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'source'; self.root.mkdir()
        self.reports = Path(self.temp.name) / 'reports'; self.reports.mkdir()
        self.manifest_path = Path(self.temp.name) / 'manifest.json'
        self.config = {'schemaVersion': 1, 'maxAgeSeconds': 3600, 'supportedReleaseLines': ['1.5', '1.6', '1.7'], 'suites': {
            'source': {'kind': 'hosted', 'minVersion': '1.5', 'commands': [{'id': 'unit', 'argv': [sys.executable, '-c', 'pass']}]},
            'native': {'kind': 'external', 'minVersion': '1.6', 'labels': ['self-hosted', 'Linux', 'qa'], 'cases': ['login', 'cleanup'], 'timeoutSeconds': 10}}}
        rv.atomic(self.manifest_path, self.config)
        (self.root / 'config').mkdir(); (self.root / 'VERSION').write_text('1.6.0\n')
        rv.atomic(self.root / 'config/release-lock.json', {'version': '1.6.0'})
        subprocess.run(['git', 'init', '-q', str(self.root)], check=True)
        self.commit()
        self.identity = rv.source(self.root, self.manifest_path)
        self.run = rv.context()

    def commit(self):
        subprocess.run(['git', '-C', str(self.root), 'add', '.'], check=True)
        subprocess.run(['git', '-C', str(self.root), '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.test', 'commit', '-qm', 'fixture'], check=True)

    def evidence(self):
        for name, suite in self.config['suites'].items():
            report = rv.base_report(name, self.identity)
            report.update(status='passed', cleanup='passed', reason='complete', cases=[dict(id=c, status='passed') for c in rv.cases(suite, '1.6.0')])
            rv.atomic(self.reports / (name + '.json'), report)

    def gate(self, mode='release'):
        return rv.gate(self.root, self.manifest_path, self.reports, mode, run=self.run)

    def mutate(self, suite, action):
        path = self.reports / (suite + '.json'); value = rv.read(path); action(value); rv.atomic(path, value)

    def test_complete_release_requires_both_fixture_and_live_evidence(self):
        self.evidence(); self.assertTrue(self.gate()['publishable'])

    def test_fixture_success_never_authorizes_publication(self):
        self.evidence(); (self.reports / 'native.json').unlink()
        result = self.gate('fixtures'); self.assertEqual(result['status'], 'passed'); self.assertFalse(result['publishable'])

    def test_missing_native_evidence_blocks_release(self):
        self.evidence(); (self.reports / 'native.json').unlink()
        result = self.gate(); self.assertFalse(result['publishable']); self.assertEqual(result['errors'][0]['reason'], 'missing')

    def test_failure_skip_blocked_and_cleanup_failure_block(self):
        for field, value in [('status', 'failed'), ('status', 'skipped'), ('status', 'blocked'), ('cleanup', 'failed')]:
            with self.subTest(field=field, value=value):
                self.evidence(); self.mutate('native', lambda r: r.update({field: value}))
                self.assertFalse(self.gate()['publishable'])

    def test_sha_lock_manifest_version_and_ref_mismatch_block(self):
        for field in self.identity:
            with self.subTest(field=field):
                self.evidence(); self.mutate('source', lambda r: r['source'].update({field: 'wrong'}))
                self.assertFalse(self.gate()['publishable'])

    def test_wrong_run_attempt_repository_or_automation_commit_block(self):
        for field in self.run:
            self.evidence(); self.mutate('native', lambda r: r['run'].update({field: 'wrong'}))
            self.assertFalse(self.gate()['publishable'])

    def test_old_and_future_and_reversed_timestamps_block(self):
        for updates in [{'startedAt': int(time.time()) - 3601}, {'finishedAt': int(time.time()) + 1000},
                        {'startedAt': int(time.time()) + 10, 'finishedAt': int(time.time())}]:
            self.evidence(); self.mutate('native', lambda r: r.update(updates)); self.assertFalse(self.gate()['publishable'])

    def test_missing_duplicate_extra_or_failing_case_blocks(self):
        for cases in [[], [dict(id='login', status='passed')], [dict(id='login', status='passed')] * 2,
                      [dict(id='login', status='passed'), dict(id='cleanup', status='failed')]]:
            self.evidence(); self.mutate('native', lambda r: r.update(cases=cases)); self.assertFalse(self.gate()['publishable'])

    def test_duplicate_suite_artifacts_are_rejected(self):
        self.evidence(); (self.reports / 'copied.json').write_bytes((self.reports / 'native.json').read_bytes())
        with self.assertRaises(rv.ValidationError): self.gate()

    def test_unknown_report_or_secret_field_cannot_enter_passed_bundle(self):
        self.evidence(); self.mutate('native', lambda r: r.update(token='do-not-upload'))
        self.assertFalse(self.gate()['publishable'])
        self.evidence(); rv.atomic(self.reports / 'unrelated.json', dict(suite='unrelated'))
        self.assertFalse(self.gate()['publishable'])

    def test_symlinked_or_oversized_evidence_is_rejected(self):
        self.evidence(); source = self.reports / 'source.json'; original = source.read_bytes(); source.unlink()
        target = Path(self.temp.name) / 'report'; target.write_bytes(original); source.symlink_to(target)
        with self.assertRaises(rv.ValidationError): self.gate()
        source.unlink(); source.write_bytes(b'x' * (2 * 1024 * 1024 + 1))
        with self.assertRaises(rv.ValidationError): self.gate()

    def test_source_must_be_clean_and_match_expected_commit(self):
        with self.assertRaises(rv.ValidationError): rv.source(self.root, self.manifest_path, 'a' * 40)
        (self.root / 'untracked').touch()
        with self.assertRaises(rv.ValidationError): rv.source(self.root, self.manifest_path)

    def test_release_ref_cannot_hide_future_version_suites(self):
        for ref in ('release/1.7.0', 'refs/heads/release/1.7.0', 'origin/release/1.7.0',
                    'refs/remotes/origin/release/1.7.0', 'release/1.6.1',
                    'v1.7.0', 'refs/tags/v1.7.0', 'v1.6.0-rc.3'):
            with self.subTest(ref=ref), self.assertRaisesRegex(rv.ValidationError, 'release_ref_version_mismatch'):
                rv.source(self.root, self.manifest_path, ref=ref)

    def test_matching_release_refs_and_feature_refs_keep_source_version(self):
        for ref in ('release/1.6.0', 'refs/heads/release/1.6.0', 'origin/release/1.6.0', 'release/1.6',
                    'v1.6.0', 'refs/tags/v1.6.0', 'main', 'feature/1.7-device-qa'):
            with self.subTest(ref=ref):
                value = rv.source(self.root, self.manifest_path, ref=ref)
                self.assertEqual(value['version'], '1.6.0')
                self.assertEqual(value['ref'], ref)

    def test_development_version_selects_future_suite_on_matching_branch(self):
        (self.root / 'VERSION').write_text('1.7.0-dev.1\n')
        rv.atomic(self.root / 'config/release-lock.json', {'version': '1.7.0-dev.1'})
        self.commit()
        value = rv.source(self.root, self.manifest_path, ref='release/1.7.0')
        manifest = rv.load_manifest()
        self.assertIn('device-ssh', rv.selected(manifest, value['version'], 'fixtures'))

    def test_unknown_release_line_cannot_get_empty_success(self):
        manifest = rv.load_manifest(self.manifest_path)
        for product in ('0.0.1', '9.0.0'):
            with self.assertRaises(rv.ValidationError): rv.selected(manifest, product, 'release')

    def test_version_specific_device_suite_is_not_required_for_v16(self):
        manifest = rv.load_manifest()
        self.assertNotIn('device-ssh', rv.selected(manifest, '1.6.0', 'release'))
        self.assertIn('device-ssh', rv.selected(manifest, '1.7.0', 'release'))
        self.assertIn('provider-live', rv.selected(manifest, '1.6.0-rc.3', 'release'))

    def test_manifest_has_all_required_release_layers(self):
        suites = rv.selected(rv.load_manifest(), '1.6.0', 'release')
        for name in ('source', 'setup', 'launchers', 'estate', 'tools', 'lifecycle', 'broker', 'credentials',
                     'fresh-install', 'arch-native', 'wsl-native', 'github-live', 'company-live', 'provider-live'):
            self.assertIn(name, suites)

    def test_hosted_runner_records_only_actual_passed_commands(self):
        value = rv.run_suite(self.root, self.manifest_path, 'source', self.reports)
        self.assertEqual(value['status'], 'passed'); self.assertEqual(value['cases'], [dict(id='unit', status='passed')])

    def test_relative_candidate_checkout_resolves_helper_files_from_child_cwd(self):
        helpers = {
            'CT_FUNCTIONS_FILE': 'devBenches/base-image/files/ct/ct-functions.zsh',
            'SPECKIT_WORKTREE_FALLBACK_FILE': 'devBenches/base-image/files/speckit-worktree/templates/specify/shell/worktrees.sh',
        }
        for name, relative in helpers.items():
            path = self.root / relative; path.parent.mkdir(parents=True, exist_ok=True); path.write_text(name)
        self.commit()
        code = 'import os; from pathlib import Path; ' + '; '.join(
            f'assert Path(os.environ[{name!r}]).read_text() == {name!r}' for name in helpers)
        self.config['suites']['source']['commands'][0]['argv'] = [sys.executable, '-c', code]
        rv.atomic(self.manifest_path, self.config)
        env = {k:v for k,v in os.environ.items() if k not in helpers}
        result = subprocess.run([sys.executable, str(ROOT / 'scripts/release-validation.py'), 'run',
            '--root', 'source', '--manifest', str(self.manifest_path), '--suite', 'source',
            '--reports', str(self.reports)], cwd=self.temp.name, env=env, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(rv.read(self.reports / 'source.json')['status'], 'passed')

    def test_lifecycle_waits_for_child_exit_after_terminal_eof(self):
        lifecycle = module('lifecycle', 'devcontainer.test/test-component-lifecycle.py')
        class Child:
            returncode = None
            def poll(self): return self.returncode
            def wait(self, timeout=None): self.returncode = 0; return 0
            def kill(self): raise AssertionError('Successful child killed before reaping')
        child = Child()
        frame = 'REQUIREMENTS · 2/2 ready Navigation:'.encode()
        with patch.object(lifecycle.subprocess, 'Popen', return_value=child), \
             patch.object(lifecycle.select, 'select', return_value=([1], [], [])), \
             patch.object(lifecycle.os, 'read', side_effect=[frame, OSError()]), \
             patch.object(lifecycle.os, 'write'):
            self.assertIn('Navigation:', lifecycle.setup_tui(self.root, b'\n', {}))
        self.assertEqual(child.returncode, 0)

    def test_failure_diagnostics_never_include_messages_or_private_paths(self):
        secret = 'NEVER_SERIALIZE_THIS_PASSWORD'
        raw = (f'workstation-acceptance-1 | File "/private/{secret}/test-workstation-acceptance.py", line 276, in main\n'
               f'workstation-acceptance-1 | RuntimeError: {secret}\n').encode()
        detail = rv.failure_location(raw)
        self.assertEqual(detail, dict(exception='RuntimeError', file='test-workstation-acceptance.py', line=276))
        self.assertNotIn(secret, json.dumps(detail))
        diagnostic = {}
        passed = rv.execute([sys.executable, '-c', f'raise RuntimeError({secret!r})'], self.root, dict(os.environ), 10, diagnostic)
        self.assertFalse(passed)
        self.assertEqual(diagnostic['exception'], 'RuntimeError')
        self.assertIsInstance(diagnostic['workspaceFreeBytes'], int)
        self.assertNotIn(secret, json.dumps(diagnostic))
        self.assertEqual(rv.failure_location(b'no space left on device'), {'category':'disk_full'})
        self.assertEqual(rv.failure_location(b'subprocess.CalledProcessError: private-value'), {'exception':'CalledProcessError'})
        self.assertEqual(rv.failure_location(b'UnknownException: private-value'), {})
        self.assertEqual(rv.failure_location(b"AssertionError: ('failed-npm-update', 0)"), {'exception':'AssertionError', 'case':'failed-npm-update', 'exitCode':0})
        self.assertEqual(rv.failure_location(b"AssertionError: ('PRIVATE-PASSWORD', 1)"), {'exception':'AssertionError'})

    def test_native_failure_diagnostics_allow_identifiers_only(self):
        raw = b'NATIVE_QA_FAILURE {"phase":"workstation-driver","exitCode":1,"file":"test-wsl-workstation-acceptance.py","line":196,"exception":"AssertionError","secret":"DO_NOT_EXPOSE"}'
        value = rv.native_failure_location(raw)
        self.assertEqual(value, dict(phase='workstation-driver', exitCode=1, file='test-wsl-workstation-acceptance.py', line=196, exception='AssertionError'))
        self.assertNotIn('DO_NOT_EXPOSE', json.dumps(value))
        self.assertEqual(rv.native_failure_location(raw.replace(b'workstation-driver', b'DO_NOT_EXPOSE')), {})

    def certificate(self):
        cert = Path(self.temp.name) / 'native-cert.pem'; key = cert.with_name('native-key.pem')
        subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
                        '-subj', '/CN=QA fixture/', '-keyout', str(key), '-out', str(cert)],
                       check=True, capture_output=True)
        return cert, key

    def test_native_ciphertext_survives_plaintext_cleanup(self):
        import tarfile
        fixture_value = b'private-native-fixture-value'
        cert, key = self.certificate()
        logs = self.root / 'logs'; logs.mkdir(); setup = logs / 'setup-test.log'; setup.write_bytes(fixture_value)
        terminal = self.reports / 'wsl-bench-install.txt'; terminal.write_bytes(fixture_value)
        result = self.reports / 'wsl-all-results.json'
        rv.atomic(result, {'results': [{'case':'bench-install', 'status':'failed', 'private':fixture_value.decode()}]})
        destination = Path(self.temp.name) / 'encrypted-native'
        with tempfile.TemporaryFile() as output:
            output.write(fixture_value)
            metadata = native.native_diagnostics(self.root, self.reports, output, 'arch-native', destination, cert.read_text())
        self.assertEqual(metadata['case'], 'bench-install')
        self.assertNotIn(fixture_value.decode(), json.dumps(metadata))
        encrypted = destination / metadata['encryptedDiagnostics']['file']
        self.assertNotIn(fixture_value, encrypted.read_bytes())
        for path in (setup, terminal, result, self.reports / 'driver-failure.log'): path.unlink()
        decoded = Path(self.temp.name) / 'native-decoded.tgz'
        subprocess.run(['openssl', 'cms', '-decrypt', '-binary', '-inform', 'DER', '-in', str(encrypted),
                        '-inkey', str(key), '-recip', str(cert), '-out', str(decoded)], check=True, capture_output=True)
        with tarfile.open(decoded) as archive:
            self.assertEqual(set(archive.getnames()), {'native-driver.log', 'driver-results.json', 'setup.log', 'bench-terminal.txt'})
            self.assertEqual(archive.extractfile('setup.log').read(), fixture_value)
        public = dict(phase='workstation-driver', **metadata)
        self.assertEqual(rv.native_failure_location(('NATIVE_QA_FAILURE '+json.dumps(public)).encode()), public)

    def test_native_completion_failure_preserves_private_report_after_cleanup(self):
        import tarfile
        fixture_value = 'private-completion-report'
        cert, key = self.certificate()
        report = self.reports / 'wsl-all-results.json'
        report.write_text(json.dumps({'complete': False, 'notRun': ['bench-remove'],
                                     'private': fixture_value, 'results': []}))
        destination = Path(self.temp.name) / 'completion-diagnostics'
        metadata = native.native_completion_diagnostics('native_driver_incomplete', self.root,
            self.reports, 'arch-native', destination, cert.read_text())
        encrypted = destination / metadata['encryptedDiagnostics']['file']
        report.unlink()
        (self.reports / 'driver-failure.log').unlink()
        decoded = Path(self.temp.name) / 'completion-decoded.tgz'
        subprocess.run(['openssl', 'cms', '-decrypt', '-binary', '-inform', 'DER', '-in', str(encrypted),
                        '-inkey', str(key), '-recip', str(cert), '-out', str(decoded)], check=True, capture_output=True)
        with tarfile.open(decoded) as archive:
            self.assertEqual(json.loads(archive.extractfile('driver-results.json').read())['private'], fixture_value)
        self.assertNotIn(fixture_value, json.dumps(metadata))
        self.assertEqual(metadata['reason'], 'native_driver_incomplete')
        self.assertEqual(rv.native_failure_location(('NATIVE_QA_FAILURE '+json.dumps(metadata)).encode()), metadata)
        with self.assertRaises(ValueError):
            native.native_completion_diagnostics(fixture_value, self.root, self.reports,
                                                  'arch-native', destination, None)
        raw = b'NATIVE_QA_FAILURE {"phase":"cleanup-verification","reason":"private-value","private":"private-value"}'
        self.assertEqual(rv.native_failure_location(raw), {'phase': 'cleanup-verification'})

    def test_native_diagnostics_have_no_plaintext_or_unknown_field_fallback(self):
        rv.atomic(self.reports / 'wsl-all-results.json', {'results':[{'case':'DO_NOT_EXPOSE', 'status':'failed'}]})
        destination = Path(self.temp.name) / 'no-diagnostics'
        with tempfile.TemporaryFile() as output:
            output.write(b'DO_NOT_EXPOSE')
            self.assertEqual(native.native_diagnostics(self.root, self.reports, output, 'arch-native', destination, None), {})
            self.assertEqual(native.native_diagnostics(self.root, self.reports, output, 'arch-native', destination, 'invalid cert'), {})
        self.assertFalse(list(destination.glob('*.cms')))
        raw = b'NATIVE_QA_FAILURE {"phase":"workstation-driver","case":"DO_NOT_EXPOSE","encryptedDiagnostics":{"file":"../../private","certificateSha256":"private"}}'
        self.assertEqual(rv.native_failure_location(raw), {'phase':'workstation-driver'})
        self.assertEqual(rv.native_failure_location(raw.replace(b'"case":"DO_NOT_EXPOSE"', b'"case":[]')), {'phase':'workstation-driver'})

    def test_controller_forwards_only_public_certificate_from_pem_bundle(self):
        cert, key = self.certificate()
        bundle = cert.with_name('bundle.pem'); bundle.write_bytes(cert.read_bytes()+key.read_bytes())
        public = native_controller.public_certificate(bundle)
        self.assertEqual(public, cert.read_text())
        self.assertNotIn('PRIVATE KEY', public)
        with self.assertRaises(ValueError): native_controller.public_certificate(key)

    def test_private_build_logs_emit_only_allowlisted_hints(self):
        secret = 'NEVER_EXPOSE_PRIVATE_BUILD_TOKEN'
        raw = f'ERROR: OpenRepoTools failed: {secret}\nmax depth exceeded\ncurl: (22) requested URL error: 502'.encode()
        value = rv.build_failure_hints(raw)
        self.assertEqual(value, dict(hints=['image_layer_depth'], httpStatus=502, installers=['OpenRepoTools']))
        self.assertNotIn(secret, json.dumps(value))
        seen = []
        def copy_logs(argv, **kwargs):
            directory = Path(argv[-1]); seen.append(directory)
            if argv[-2].endswith('/report/bench-install.txt'):
                directory.write_text('Layer 0 build failed\n' + secret)
                return subprocess.CompletedProcess(argv, 0)
            older = directory / 'old.log'; older.write_text('no space left on device')
            latest = directory / 'current.log'; latest.write_bytes(raw)
            os.utime(older, (1, 1)); os.utime(latest, (2, 2))
            return subprocess.CompletedProcess(argv, 0)
        with patch.object(rv.subprocess, 'run', side_effect=copy_logs):
            result = rv.workstation_diagnostics(self.root, 'private-fixture-project', {})
        self.assertEqual(result, dict(logsRead=1, terminal={'hints': ['layer_zero_failure']}, **value))
        self.assertNotIn(secret, json.dumps(result))
        self.assertFalse(seen[0].exists(), 'Private copies must be deleted after parsing')

    def test_optional_diagnosis_is_encrypted_and_tamper_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp); key = directory / 'key.pem'; cert = directory / 'cert.pem'
            subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:3072', '-nodes', '-keyout', str(key),
                '-out', str(cert), '-days', '1', '-subj', '/CN=fixture-test'], check=True, capture_output=True)
            plain = directory / 'private.log'; plain.write_bytes(b'NEVER_PUBLISH_FIXTURE_PLAINTEXT')
            encrypted = directory / 'fresh-install-debug.cms'
            metadata = rv.encrypt_fixture_diagnostics([('setup.log', plain)], cert.read_text(), encrypted)
            self.assertEqual(metadata['file'], 'fresh-install-debug.cms')
            self.assertNotIn(plain.read_bytes(), encrypted.read_bytes())
            decoded = directory / 'decoded.tgz'
            argv = ['openssl', 'cms', '-decrypt', '-binary', '-inform', 'DER', '-in', str(encrypted),
                    '-inkey', str(key), '-recip', str(cert), '-out', str(decoded)]
            subprocess.run(argv, check=True, capture_output=True)
            import tarfile
            with tarfile.open(decoded) as archive:
                self.assertEqual(archive.getnames(), ['setup.log'])
                self.assertEqual(archive.extractfile('setup.log').read(), plain.read_bytes())
            raw = bytearray(encrypted.read_bytes()); raw[-1] ^= 1; encrypted.write_bytes(raw)
            self.assertNotEqual(subprocess.run(argv, capture_output=True).returncode, 0)
            self.assertEqual(rv.encrypt_fixture_diagnostics([('setup.log', plain)], 'invalid certificate', encrypted), {})
            self.assertFalse(encrypted.exists())

    def test_command_failure_still_cleans_up_and_cannot_pass(self):
        self.config['suites']['source']['cleanup'] = [[sys.executable, '-c', 'pass']]
        rv.atomic(self.manifest_path, self.config)
        with patch.object(rv, 'execute', side_effect=[False, True]) as execute:
            value = rv.run_suite(self.root, self.manifest_path, 'source', self.reports)
        self.assertEqual(execute.call_count, 2); self.assertEqual(value['cleanup'], 'passed'); self.assertEqual(value['status'], 'failed')

    def test_failed_cleanup_prevents_success(self):
        self.config['suites']['source']['cleanup'] = [[sys.executable, '-c', 'pass']]
        rv.atomic(self.manifest_path, self.config)
        with patch.object(rv, 'execute', side_effect=[True, False]):
            value = rv.run_suite(self.root, self.manifest_path, 'source', self.reports)
        self.assertEqual(value['status'], 'failed'); self.assertEqual(value['cleanup'], 'failed')

    def test_missing_external_configuration_is_blocked_not_skipped(self):
        value = rv.run_suite(self.root, self.manifest_path, 'native', self.reports)
        self.assertEqual(value['status'], 'blocked'); self.assertEqual(value['reason'], 'qa_runner_configuration_missing')

    def test_adapter_success_requires_exact_source_cases_and_safe_fields(self):
        report = rv.base_report('native', self.identity)
        cfg = Path(self.temp.name) / 'qa.json'
        rv.atomic(cfg, dict(enabled=True, disposable=True, resetId='boot-1', adapters={'native': {'argv':['/approved'], 'sha256':'0'*64}}))
        expected = dict(source=self.identity, run=report['run'], suite='native', resetId='boot-1',
                        status='passed', cleanup='passed', cases=[dict(id=c, status='passed') for c in ['login', 'cleanup']])
        for value, passed in [(expected, True), (dict(expected, token='bad'), False),
                              (dict(expected, cases=[]), False), (dict(expected, source={}), False)]:
            current = copy.deepcopy(report)
            class Process:
                returncode = 0
                def communicate(self, data=None, timeout=None):
                    return None, None
            def spawn(*args, **kwargs):
                kwargs['stdout'].write(json.dumps(value).encode())
                return Process()
            with patch.object(rv, 'approved_adapter', return_value=['/approved']), patch.object(rv.subprocess, 'Popen', side_effect=spawn):
                if 'token' in value or value.get('source') == {}:
                    with self.assertRaises(rv.ValidationError): rv.run_external(self.root, self.config['suites']['native'], current, cfg)
                else:
                    rv.run_external(self.root, self.config['suites']['native'], current, cfg)
                    self.assertEqual(current['status'] == 'passed', passed)

    def test_preflight_missing_busy_or_offline_runners_emit_blocked_evidence(self):
        plan = {'source': self.identity, 'external':[{'suite':'native', 'labels':['self-hosted', 'qa']}]}
        for runners, configured in [([], True), ([{'status':'offline','busy':False,'labels':[{'name':'self-hosted'},{'name':'qa'}]}],True),
                                    ([{'status':'online','busy':True,'labels':[{'name':'self-hosted'},{'name':'qa'}]}],True), ([],False)]:
            ready, blocked = preflight.readiness(plan, runners, configured)
            self.assertEqual(ready, []); self.assertEqual(blocked[0]['status'], 'blocked')
        ready, blocked = preflight.readiness(plan, [{'status':'online','busy':False,'labels':[{'name':'self-hosted'},{'name':'qa'}]}], True)
        self.assertEqual(len(ready), 1); self.assertEqual(blocked, [])

    def test_private_workers_require_main_or_a_protected_candidate_branch(self):
        plan = {'source':dict(commit='a'*40,version='1.6.0-rc.3')}
        self.assertTrue(preflight.trusted_source(plan, lambda path: {'commit': {'sha': 'a'*40}}))
        def fetch(path, candidate):
            if path == 'branches/main': return {'commit': {'sha': 'b'*40}}
            self.assertEqual(path, 'branches/release%2F1.6.0')
            return candidate
        self.assertTrue(preflight.trusted_source(plan, lambda path: fetch(path, {'commit': {'sha':'a'*40}, 'protected':True})))
        self.assertFalse(preflight.trusted_source(plan, lambda path: fetch(path, {'commit': {'sha':'a'*40}, 'protected':False})))

    def test_protected_branch_does_not_authorize_an_unrelated_or_stale_sha(self):
        plan = {'source':dict(commit='a'*40,version='1.6.0-rc.3')}
        for candidate in ({'commit': {'sha':'c'*40}, 'protected':True}, {'protected':True}):
            def fetch(path):
                return {'commit': {'sha':'b'*40}} if path == 'branches/main' else candidate
            self.assertFalse(preflight.trusted_source(plan, fetch))

    def test_watchdog_distinguishes_intentional_serial_queue_from_stall(self):
        self.assertEqual(watchdog.stalled([]), 'waiting')
        self.assertEqual(watchdog.stalled([{'name':'Protected QA (arch) / qa','status':'queued'}]), 'waiting')
        self.assertEqual(watchdog.stalled([{'name':'Protected QA (arch) / qa','status':'in_progress'},
                                          {'name':'Protected QA (wsl) / qa','status':'queued'}]), 'active')
        self.assertEqual(watchdog.stalled([{'name':'Protected QA (arch) / qa','status':'completed'}]), 'finished')

    def test_publisher_does_not_move_existing_tags_and_can_resume_matching_tag(self):
        repository, tag, commit, run_id = 'o/r', 'v1.6.0', 'a'*40, '17'
        ref = json.dumps({'object':{'type':'tag','sha':'b'*40}})
        matching = {'tag':tag, 'object':{'type':'commit','sha':commit},
                    'message':'workBenches 1.6.0\nValidated source ' + commit + '\nEvidence https://github.com/o/r/actions/runs/17'}
        with patch.object(publisher, 'gh', side_effect=[ref, json.dumps(matching)]):
            self.assertTrue(publisher.existing_tag(repository, tag, commit, run_id))
        with patch.object(publisher, 'gh', return_value=None): self.assertFalse(publisher.existing_tag(repository, tag, commit, run_id))
        for bad in [dict(matching, tag='v1.5.0'), dict(matching, object={'type':'commit','sha':'c'*40}), dict(matching, message='unverified')]:
            with patch.object(publisher, 'gh', side_effect=[ref,json.dumps(bad)]):
                with self.assertRaises(rv.ValidationError): publisher.existing_tag(repository, tag, commit, run_id)

    def test_publication_never_writes_for_fixture_or_missing_native_evidence(self):
        notes = self.root / 'docs/release-1.6.0.md'; notes.parent.mkdir(); notes.write_text('Fixture release')
        self.commit(); self.identity = rv.source(self.root, self.manifest_path)
        commit = self.identity['commit']; metadata = dict(path='.github/workflows/release-validation.yml', head_branch='main',
            event='workflow_dispatch', conclusion='success', status='completed', head_sha=commit,
            head_repository={'full_name':'o/r'}, id=17, run_attempt=1)
        run = publisher.run_identity(metadata, 'o/r', commit)
        for mode, missing in [('fixtures',False), ('release',True)]:
            self.evidence()
            for path in self.reports.glob('*.json'):
                value = rv.read(path); value['run'] = run; rv.atomic(path, value)
            writes = []
            def fake_gh(*args, **kwargs):
                if '--method' in args: writes.append(args); raise AssertionError('Unexpected tag/release write')
                if args[0] == 'api':
                    return json.dumps(metadata if 'actions/runs/' in args[1] else {'object':{'sha':commit}})
                if args[:2] == ('run','download'):
                    directory = Path(args[args.index('--dir') + 1]); directory.mkdir(parents=True, exist_ok=True)
                    if args[args.index('--pattern') + 1] == 'release-summary':
                        rv.atomic(directory / 'summary.report', {'publishable':mode=='release','mode':mode,'run':run,'source':self.identity})
                    else:
                        for path in self.reports.glob('*.json'):
                            if missing and path.stem == 'native': continue
                            target = directory / path.stem / path.name; target.parent.mkdir(); target.write_bytes(path.read_bytes())
                    return ''
                raise AssertionError(args)
            with patch.object(publisher,'DEFAULT_MANIFEST',self.manifest_path), patch.object(publisher,'gh',side_effect=fake_gh), \
                 patch.dict(os.environ,{'GITHUB_REPOSITORY':'o/r'}), patch.object(sys,'argv',['publish','--root',str(self.root),'--run-id','17','--version','1.6.0','--publish']):
                with self.assertRaises(rv.ValidationError): publisher.main()
            self.assertEqual(writes, [])

    def test_arch_vm_configuration_has_no_passwords_or_runner_registration(self):
        vm = module('arch_vm', 'qa/release/prepare-arch-vm.py')
        config = json.loads(vm.cloud_config('ssh-ed25519 PUBLIC_FIXTURE', 'reset-fixture', b'wrapper').split('\n', 1)[1])
        self.assertFalse(config['ssh_pwauth'])
        self.assertTrue(config['disable_root'])
        self.assertEqual(len(config['users']), 1)
        self.assertTrue(config['users'][0]['lock_passwd'])
        self.assertEqual(config['users'][0]['ssh_authorized_keys'], ['ssh-ed25519 PUBLIC_FIXTURE'])
        self.assertTrue(all(f['owner'] == 'root:root' for f in config['write_files']))
        self.assertNotIn('token', json.dumps(config).lower())
        self.assertNotIn('config.sh', json.dumps(config))
        self.assertEqual(config['power_state']['mode'], 'reboot')

    def test_arch_vm_refuses_unpinned_image_without_creating_state(self):
        vm = module('arch_vm', 'qa/release/prepare-arch-vm.py')
        image = Path(self.temp.name) / 'image'; image.write_bytes(b'untrusted-image')
        state = Path(self.temp.name) / 'vm-state'
        with self.assertRaisesRegex(ValueError, 'checksum'):
            vm.prepare(image, state)
        self.assertFalse(state.exists())

    def test_arch_vm_never_overwrites_an_existing_disk_directory(self):
        vm = module('arch_vm', 'qa/release/prepare-arch-vm.py')
        sentinel = self.reports / 'existing-disk'; sentinel.write_text('preserve')
        with patch.object(vm, 'digest', return_value=vm.IMAGE_SHA256), \
             patch.object(vm.subprocess, 'run') as run:
            with self.assertRaisesRegex(ValueError, 'must be new'):
                vm.prepare(self.root / 'image', self.reports)
        run.assert_not_called()
        self.assertEqual(sentinel.read_text(), 'preserve')

    def test_arch_vm_shutdown_requires_vm_exit_even_when_ssh_disconnects(self):
        vm = module('arch_vm', 'qa/release/prepare-arch-vm.py')
        class Guest:
            returncode = 0
            def wait(self, timeout): pass
        guest = Guest()
        with patch.object(vm.subprocess, 'run', return_value=subprocess.CompletedProcess([], 255)):
            vm.power_off(guest, ['ssh'])
            with patch.object(guest, 'wait', side_effect=subprocess.TimeoutExpired('qemu', 90)):
                with self.assertRaises(subprocess.TimeoutExpired): vm.power_off(guest, ['ssh'])
            guest.returncode = 1
            with self.assertRaises(ValueError): vm.power_off(guest, ['ssh'])

    def test_publisher_requires_trusted_main_successful_exact_workflow_run(self):
        value = dict(path='.github/workflows/release-validation.yml', head_branch='main', event='workflow_dispatch',
                     conclusion='success', status='completed', head_sha='a'*40, head_repository={'full_name':'o/r'}, id=7, run_attempt=1)
        self.assertEqual(publisher.run_identity(value, 'o/r', 'a'*40)['runId'], '7')
        for key, bad in [('path','.github/workflows/other.yml'), ('head_branch','feature'), ('event','pull_request'),
                         ('conclusion','failure'), ('status','in_progress'), ('head_sha','b'*40), ('head_repository',{'full_name':'other/repo'})]:
            with self.assertRaises(rv.ValidationError): publisher.run_identity(dict(value, **{key:bad}), 'o/r', 'a'*40)


if __name__ == '__main__': unittest.main()
