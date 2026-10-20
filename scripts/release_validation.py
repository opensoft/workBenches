"""Commit-bound release suites and fail-closed evidence validation (stdlib only)."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import platform
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import tarfile
import time
import uuid

HERE = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = HERE / 'config/release-tests.json'
SHA = re.compile(r'[a-f0-9]{40}')
HEX = re.compile(r'[a-f0-9]{64}')
CI_SUITES = {'source', 'setup', 'launchers', 'estate'}


class ValidationError(ValueError): pass


def read(path):
    path = Path(path)
    if path.is_symlink() or path.stat().st_size > 2 * 1024 * 1024:
        raise ValidationError('unsafe_or_oversized_evidence')
    return json.loads(path.read_text())


def digest(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def version(value):
    match = re.fullmatch(r'(0|[1-9]\d*)\.(0|[1-9]\d*)(?:\.(0|[1-9]\d*))?(?:-[0-9A-Za-z.-]+)?', value)
    if not match: raise ValidationError('invalid_version')
    return tuple(int(n or 0) for n in match.groups())


def git(root, *args):
    result = subprocess.run(['git', '-C', str(root), *args], text=True, capture_output=True, timeout=60)
    if result.returncode: raise ValidationError('git_' + args[0] + '_failed')
    return result.stdout.strip()


def load_manifest(path=DEFAULT_MANIFEST):
    data = read(path)
    if data.get('schemaVersion') != 1 or type(data.get('maxAgeSeconds')) is not int or not 60 <= data['maxAgeSeconds'] <= 172800:
        raise ValidationError('invalid_manifest')
    if not isinstance(data.get('suites'), dict) or not data['suites']: raise ValidationError('empty_manifest')
    for name, suite in data['suites'].items():
        if not re.fullmatch(r'[a-z][a-z0-9-]{0,60}', name) or suite.get('kind') not in ('hosted', 'external'):
            raise ValidationError('invalid_suite')
        version(suite['minVersion'])
        if suite['kind'] == 'hosted':
            commands = suite.get('commands')
            if not isinstance(commands, list) or not commands: raise ValidationError('empty_suite')
            ids = set()
            for command in commands:
                if command['id'] in ids: raise ValidationError('duplicate_case')
                ids.add(command['id'])
                validate_argv(command['argv'])
                if 'minVersion' in command: version(command['minVersion'])
            for command in suite.get('cleanup', []): validate_argv(command)
        else:
            if not suite.get('cases') or len(set(suite['cases'])) != len(suite['cases']): raise ValidationError('invalid_external_cases')
            if not isinstance(suite.get('labels'), list) or 'self-hosted' not in suite['labels']: raise ValidationError('invalid_runner_labels')
    return data


def validate_argv(argv):
    if not isinstance(argv, list) or not argv or any(not isinstance(a, str) or not a or '\0' in a for a in argv):
        raise ValidationError('invalid_argv')


def selected(manifest, product_version, mode):
    if mode not in ('ci', 'fixtures', 'release'): raise ValidationError('invalid_mode')
    current = version(product_version)
    if '.'.join(map(str, current[:2])) not in manifest.get('supportedReleaseLines', []):
        raise ValidationError('unsupported_release_line')
    result = {name: suite for name, suite in manifest['suites'].items()
            if current >= version(suite['minVersion']) and
            (mode == 'release' or suite['kind'] == 'hosted' and (mode != 'ci' or name in CI_SUITES))}
    if 'source' not in result: raise ValidationError('source_suite_required')
    return result


def cases(suite, product_version):
    if suite['kind'] == 'external': return suite['cases']
    return [c['id'] for c in suite['commands'] if version(product_version) >= version(c.get('minVersion', '0.0'))]


def source(root, manifest_path, expected=None, ref=None):
    root = Path(root).resolve()
    commit = git(root, 'rev-parse', 'HEAD')
    if not SHA.fullmatch(commit) or expected is not None and commit != expected: raise ValidationError('wrong_commit')
    if git(root, 'status', '--porcelain', '--untracked-files=normal'): raise ValidationError('dirty_source')
    product = (root / 'VERSION').read_text().strip(); version(product)
    lock = read(root / 'config/release-lock.json')
    if lock.get('version') != product: raise ValidationError('version_lock_mismatch')
    label = ref or commit
    # A future release branch with an inherited old VERSION would otherwise
    # silently omit its version-gated suites (for example v1.7 device SSH).
    branch = re.fullmatch(r'(?:refs/heads/)?release/(\d+\.\d+(?:\.\d+)?)', label)
    tag = re.fullmatch(r'(?:refs/tags/)?v(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)', label)
    if branch:
        width = len(branch[1].split('.'))
        if version(branch[1])[:width] != version(product)[:width]:
            raise ValidationError('release_ref_version_mismatch')
    if tag and tag[1] != product: raise ValidationError('release_ref_version_mismatch')
    return dict(commit=commit, version=product, lockSha256=digest(root / 'config/release-lock.json'),
                manifestSha256=digest(manifest_path), ref=label)


def context():
    return dict(runId=os.environ.get('GITHUB_RUN_ID', 'local'), attempt=os.environ.get('GITHUB_RUN_ATTEMPT', '1'),
                repository=os.environ.get('GITHUB_REPOSITORY', 'local'),
                automationCommit=os.environ.get('WB_AUTOMATION_SHA', git(HERE, 'rev-parse', 'HEAD')))


def base_report(name, identity):
    return dict(schemaVersion=1, suite=name, source=identity, run=context(), status='blocked',
                startedAt=int(time.time()), finishedAt=int(time.time()), cleanup='not_run', cases=[],
                runner={'system': platform.system(), 'machine': platform.machine(), 'python': platform.python_version()}, reason='not_run')


def atomic(path, value):
    path = Path(path)
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(mode='w', dir=path.parent, delete=False) as out:
        temporary = Path(out.name)
        try:
            json.dump(value, out, indent=2, allow_nan=False); out.write('\n'); out.flush(); os.fsync(out.fileno())
            os.replace(temporary, path)
        finally: temporary.unlink(missing_ok=True)


def tool_versions():
    result = {}
    for name, argv in [('git', ['git', '--version']),
                       ('docker', ['docker', 'version', '--format', '{{.Client.Version}}/{{.Server.Version}}'])]:
        try:
            done = subprocess.run(argv, capture_output=True, text=True, timeout=5)
            if done.returncode == 0:
                # Only numeric versions enter artifacts, never arbitrary command output.
                values = re.findall(r'\b\d+\.\d+(?:\.\d+)?\b', done.stdout)
                if values: result[name] = values[:2]
        except (OSError, subprocess.TimeoutExpired): pass
    return result


def failure_location(raw):
    """Extract identifiers only; never exception messages, paths or log lines."""
    result = {}
    classes = rb'(AssertionError|RuntimeError|ValueError|KeyError|TypeError|FileNotFoundError|PermissionError|TimeoutExpired|CalledProcessError|HTTPError|URLError|SSLError)'
    found = re.findall(rb'(?:^|\n)(?:[^\n|]*\|\s*)?(?:subprocess\.|urllib\.error\.|ssl\.)?' + classes + rb'(?::|\r?$)', raw, re.M)
    if found: result['exception'] = found[-1].decode('ascii')
    case_names = rb'(quit|empty|default-cli-install|cancel-account-setup|live-vault-cli-install|repeat-unchanged|repeat-update|failed-npm-update|bench-install|repeat-installed-bench|bench-uninstall-preserves-local-work)'
    failed_case = re.findall(rb"AssertionError: \('" + case_names + rb"', (-?[0-9]{1,3})\)", raw)
    if failed_case:
        result.update(case=failed_case[-1][0].decode('ascii'), exitCode=int(failed_case[-1][1]))
    frames = re.findall(rb'File "[^"\n]*(test-workstation-acceptance\.py|test-wsl-workstation-acceptance\.py|test-component-lifecycle\.py)", line ([0-9]{1,7})', raw)
    if frames:
        result.update(file=frames[-1][0].decode('ascii'), line=int(frames[-1][1]))
    if re.search(rb'no space left on device|disk quota exceeded|\bENOSPC\b', raw, re.I):
        result['category'] = 'disk_full'
    return result


def native_failure_location(raw):
    result = {}
    for match in re.findall(rb'NATIVE_QA_FAILURE (\{[^\n]{1,2048}\})', raw):
        try: value = json.loads(match)
        except ValueError: continue
        if value.get('phase') not in ('native-command', 'shell-install', 'shell-repeat', 'workstation-driver'): continue
        result['phase'] = value['phase']
        if type(value.get('exitCode')) is int and -255 <= value['exitCode'] <= 255: result['exitCode'] = value['exitCode']
        if value.get('file') in ('test-workstation-acceptance.py', 'test-wsl-workstation-acceptance.py', 'test-component-lifecycle.py'):
            result['file'] = value['file']
            if type(value.get('line')) is int and 0 < value['line'] < 10000000: result['line'] = value['line']
        if value.get('exception') in ('AssertionError', 'RuntimeError', 'ValueError', 'KeyError', 'TypeError', 'FileNotFoundError', 'PermissionError', 'TimeoutExpired', 'CalledProcessError', 'HTTPError', 'URLError', 'SSLError'):
            result['exception'] = value['exception']
    return result



def build_failure_hints(raw):
    """Known error categories only; arbitrary log text never leaves the worker."""
    patterns = {
        'image_layer_depth': rb'max depth exceeded|too many layers|layer limit',
        'disk_full': rb'no space left on device|disk quota exceeded|\bENOSPC\b',
        'out_of_memory': rb'out of memory|OOMKilled|exit code: 137',
        'illegal_instruction': rb'illegal instruction',
        'dns_failure': rb'could not resolve host|temporary failure in name resolution|\bENOTFOUND\b|\bEAI_AGAIN\b',
        'network_timeout': rb'connection timed out|\bETIMEDOUT\b|operation timed out',
        'tls_failure': rb'certificate verify failed|SSL certificate problem',
        'permission_denied': rb'permission denied|\bEACCES\b',
        'missing_executable': rb'command not found|executable file not found',
        'python_dependency': rb'no matching distribution found|requires a different Python',
        'git_ref_unavailable': rb'not our ref|reference is not a tree|couldn.t find remote ref',
        'invalid_runtime': rb'\bEBADENGINE\b|unsupported engine',
        'apt_failure': rb'(?:^|\n)E: (?:Unable to locate|Failed to fetch|The repository|Unable to correct)',
        'docker_build_failure': rb'failed to solve:|did not complete successfully: exit code:',
        'image_pull_failure': rb'failed to resolve source metadata|pull access denied|toomanyrequests',
        'frozen_source_failure': rb'Release stopped:',
        'layer_zero_failure': rb'Layer 0 build failed',
        'layer_one_failure': rb'Layer 1a .* build failed',
        'bench_setup_failure': rb'Failed to (?:setup|install)|bench setup failed',
    }
    hints = [name for name, pattern in patterns.items() if re.search(pattern, raw, re.I)]
    result = {'hints': hints} if hints else {}
    codes = re.findall(rb'curl: \(22\)[^\n]*?([45][0-9]{2})\b', raw)
    if codes: result['httpStatus'] = int(codes[-1])
    exits = re.findall(rb'did not complete successfully: exit code: ([0-9]{1,3})', raw)
    if exits: result['buildExitCode'] = int(exits[-1])
    installers = []
    for line in raw.splitlines():
        if not re.search(rb'\b(?:error|failed|failure)\b', line, re.I): continue
        for name in ('OpenRepoTools', 'OpenRepoShape', 'Codex', 'Claude', 'OpenCode', 'Copilot', 'NotebookLM', 'Letta', 'Playwright', 'Hadolint', 'actionlint'):
            if name.lower().encode() in line.lower() and name not in installers: installers.append(name)
    if installers: result['installers'] = installers
    return result


def encrypt_fixture_diagnostics(files, certificate, output):
    """Optional CMS envelope: only ciphertext may leave the fixture worker.

    The decryption key is never available to CI. Generated fixture logs are not
    release evidence, and are never uploaded as plaintext on encryption failure.
    """
    if not certificate or output is None or output.is_symlink(): return {}
    if len(certificate) > 16384: return {}
    try:
        with tempfile.TemporaryDirectory(prefix='fixture-envelope-') as temporary:
            private = Path(temporary)
            cert = private / 'recipient.pem'; cert.write_text(certificate)
            plain = private / 'fixture.tgz'
            with tarfile.open(plain, 'w:gz') as archive:
                for name, path in files:
                    if path.is_symlink() or not path.is_file(): continue
                    with path.open('rb') as stream:
                        stream.seek(0, 2); stream.seek(max(0, stream.tell() - 8 * 1024 * 1024))
                        data = stream.read()
                    info = tarfile.TarInfo(name); info.size = len(data); info.mode = 0o600
                    archive.addfile(info, io.BytesIO(data))
            output.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
            with tempfile.TemporaryFile() as log:
                result = subprocess.run(['openssl', 'cms', '-encrypt', '-binary', '-aes-256-gcm',
                    '-in', str(plain), '-out', str(output), '-outform', 'DER', '-recip', str(cert)],
                    stdout=log, stderr=log, timeout=30)
            if result.returncode or not output.is_file():
                output.unlink(missing_ok=True); return {}
            return {'file': 'fresh-install-debug.cms',
                    'certificateSha256': hashlib.sha256(certificate.encode()).hexdigest()}
    except (OSError, subprocess.TimeoutExpired):
        output.unlink(missing_ok=True)
        return {}


def workstation_diagnostics(root, project, environment, encrypted_output=None):
    # Private snapshots are deleted, including the terminal transcript. Only
    # fixed categories/headers and numeric statuses can enter public evidence.
    with tempfile.TemporaryDirectory(prefix='workstation-private-logs-') as temporary:
        directory = Path(temporary)
        result = {}; envelope_files = []
        def copy(source, destination):
            with tempfile.TemporaryFile() as output:
                try:
                    done = subprocess.run(['docker', 'compose', '-p', project, '-f', 'devcontainer.test/docker-compose.yml',
                        'cp', source, str(destination)], cwd=root, env=environment,
                        stdout=output, stderr=output, timeout=60)
                    return done.returncode == 0
                except (OSError, subprocess.TimeoutExpired): return False
        def tail(path):
            with path.open('rb') as stream:
                stream.seek(0, 2); stream.seek(max(0, stream.tell() - 256 * 1024))
                return stream.read()
        try:
            logs = directory / 'logs'; logs.mkdir()
            if copy('workstation-acceptance:/home/node/projects/workBenches/logs/.', logs):
                files = [p for p in logs.rglob('*.log') if p.is_file() and not p.is_symlink()
                         and p.resolve().is_relative_to(logs)]
                if files:
                    latest = max(files, key=lambda p:p.stat().st_mtime)
                    envelope_files.append(('setup.log', latest))
                    raw = tail(latest)
                    result.update(logsRead=1, **build_failure_hints(raw))
                    headers = re.findall(rb'\[(SETUP STARTED|DOCKER CHECK|LAYER 0 BUILD|LAYER 1 BUILDS|INTERACTIVE SETUP|SETUP COMPLETE|SETUP CANCELLED)\]', raw)
                    if headers: result['lastSetupSection'] = headers[-1].decode('ascii')
            terminal = directory / 'bench-terminal.txt'
            if copy('workstation-acceptance:/report/bench-install.txt', terminal) and terminal.is_file() and not terminal.is_symlink():
                result['terminal'] = build_failure_hints(tail(terminal))
                envelope_files.append(('bench-terminal.txt', terminal))
        except OSError:
            # Optional diagnosis must never mask the original failing case.
            pass
        if envelope_files and encrypted_output is not None:
            encrypted = encrypt_fixture_diagnostics(envelope_files, environment.get('OPENBENCHES_QA_FAILURE_CERT_PEM'), encrypted_output)
            if encrypted: result['encryptedDiagnostics'] = encrypted
        return result


def execute(argv, root, environment, timeout, diagnostic=None):
    # Raw stdout/stderr can contain generated credentials. Keep them in a
    # private temporary file and delete after execution; upload metadata only.
    with tempfile.TemporaryFile() as log:
        try:
            process = subprocess.run(argv, cwd=root, env=environment, stdout=log, stderr=log, timeout=timeout)
            passed = process.returncode == 0
            if not passed and diagnostic is not None:
                log.seek(0, 2); size = log.tell(); log.seek(max(0, size - 256 * 1024))
                diagnostic.update(failure_location(log.read()))
                try: diagnostic['workspaceFreeBytes'] = shutil.disk_usage(root).free
                except OSError: pass
            return passed
        except (OSError, subprocess.TimeoutExpired) as error:
            if diagnostic is not None:
                diagnostic['exception'] = 'TimeoutExpired' if isinstance(error, subprocess.TimeoutExpired) else 'OSError'
            return False


def run_suite(root, manifest_path, name, output, expected=None, ref=None, external_config=None):
    # Workflow checkouts use relative paths; children run inside that checkout.
    root = Path(root).resolve()
    manifest = load_manifest(manifest_path)
    identity = source(root, manifest_path, expected, ref)
    suite = manifest['suites'].get(name)
    if not suite or version(identity['version']) < version(suite['minVersion']): raise ValidationError('suite_not_applicable')
    report = base_report(name, identity)
    try:
        if suite['kind'] == 'external':
            run_external(root, suite, report, external_config)
        else:
            project = 'wb-release-' + name + '-' + uuid.uuid4().hex[:10]
            replacements = {'{project}': project, '{root}': str(Path(root).resolve())}
            def argv(items): return [replacements.get(a, a) for a in items]
            environment = dict(os.environ, WORKBENCHES_SOURCE_ROOT=str(Path(root).resolve()),
                WORKBENCHES_ACCEPTANCE_REF=identity['ref'], WORKBENCHES_ACCEPTANCE_SHA=identity['commit'],
                WORKBENCHES_ACCEPTANCE_FROZEN='1', WORKBENCHES_FROZEN='1')
            socket = Path('/var/run/docker.sock')
            if socket.exists(): environment['WORKBENCHES_DOCKER_GID'] = str(socket.stat().st_gid)
            environment.setdefault('CT_FUNCTIONS_FILE', str(Path(root) / 'devBenches/base-image/files/ct/ct-functions.zsh'))
            environment.setdefault('SPECKIT_WORKTREE_FALLBACK_FILE', str(Path(root) / 'devBenches/base-image/files/speckit-worktree/templates/specify/shell/worktrees.sh'))
            try:
                for command in suite['commands']:
                    if command['id'] not in cases(suite, identity['version']): continue
                    diagnostic = {}
                    passed = execute(argv(command['argv']), root, environment, suite.get('timeoutSeconds', 900), diagnostic)
                    report['cases'].append({'id': command['id'], 'status': 'passed' if passed else 'failed'})
                    print(name + '/' + command['id'] + ': ' + ('passed' if passed else 'failed'), flush=True)
                    if not passed:
                        if name == 'fresh-install':
                            component = workstation_diagnostics(root, project, environment, Path(output) / 'fresh-install-debug.cms')
                            if component: diagnostic['component'] = component
                        if diagnostic:
                            report['runner']['failure'] = diagnostic
                            print(name + ': safe failure location ' + json.dumps(diagnostic), flush=True)
                        break
            finally:
                # Evaluate every cleanup, even after another cleanup fails.
                cleaned = [execute(argv(c), root, environment, 180) for c in suite.get('cleanup', [])]
                report['cleanup'] = 'passed' if all(cleaned) else 'failed'
            report['status'] = 'passed' if report['cleanup'] == 'passed' and report['cases'] == [dict(id=k, status='passed') for k in cases(suite, identity['version'])] else 'failed'
            report['reason'] = 'complete' if report['status'] == 'passed' else 'suite_or_cleanup_failed'
        if source(root, manifest_path, expected, ref) != identity:
            report.update(status='failed', reason='source_changed')
    except (ValueError, OSError, KeyError, TypeError):
        report.update(status='failed', reason='invalid_execution_or_evidence')
    finally:
        report['finishedAt'] = int(time.time())
        report['runner']['tools'] = tool_versions()
        atomic(Path(output) / (name + '.json'), report)
    return report


def approved_adapter(config_path, entry):
    argv = entry.get('argv')
    validate_argv(argv)
    if not Path(argv[0]).is_absolute(): raise ValidationError('absolute_adapter_required')
    for path in (Path(config_path), Path(argv[0])):
        info = path.stat()
        if path.is_symlink() or info.st_uid != 0 or info.st_mode & 0o022:
            raise ValidationError('root_managed_qa_configuration_required')
    if not HEX.fullmatch(entry.get('sha256', '')) or digest(argv[0]) != entry['sha256']:
        raise ValidationError('adapter_pin_mismatch')
    return argv


def run_external(root, suite, report, config_path):
    if not config_path or not Path(config_path).is_file():
        report['reason'] = 'qa_runner_configuration_missing'; return
    config = read(config_path)
    if config.get('enabled') is not True or config.get('disposable') is not True:
        report['reason'] = 'disposable_qa_runner_required'; return
    entry = config.get('adapters', {}).get(report['suite'])
    if not isinstance(entry, dict):
        report['reason'] = 'approved_adapter_missing'; return
    adapter = approved_adapter(config_path, entry)
    # QA adapters receive source/context on stdin; credentials stay in their
    # protected local store. Never accept an arbitrary report upload as a pass.
    request = {'source': report['source'], 'run': report['run'], 'suite': report['suite'],
               'requiredCases': suite['cases'], 'root': str(Path(root).resolve()), 'resetId': config['resetId']}
    with tempfile.TemporaryFile() as error, tempfile.TemporaryFile() as output:
        try:
            process = subprocess.Popen(adapter, stdin=subprocess.PIPE, stdout=output,
                stderr=error, cwd=root, start_new_session=True)
            try:
                process.communicate(json.dumps(request).encode(), timeout=suite['timeoutSeconds'])
            except subprocess.TimeoutExpired:
                try: os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError: pass
                try: process.communicate(timeout=30)
                except subprocess.TimeoutExpired:
                    try: os.killpg(process.pid, signal.SIGKILL)
                    except ProcessLookupError: pass
                    process.wait(timeout=5)
                report.update(status='failed', reason='adapter_timed_out'); return
        except OSError:
            report.update(status='failed', reason='adapter_failed'); return
        output.seek(0, 2)
        if process.returncode or output.tell() > 65536:
            error.seek(0, 2); size = error.tell(); error.seek(max(0, size - 65536))
            diagnostic = native_failure_location(error.read())
            if diagnostic: report['runner']['failure'] = diagnostic
            report.update(status='failed', reason='adapter_failed'); return
        output.seek(0); raw = output.read()
    value = json.loads(raw)
    # Minimal allowlist prevents tokens, device codes, cookies and private traces
    # from entering public Actions artifacts. Case IDs/status are manifest-bound.
    if set(value) != {'source', 'run', 'suite', 'cases', 'cleanup', 'resetId', 'status'}:
        raise ValidationError('unsafe_adapter_report')
    if any(value[k] != request[k] for k in ('source', 'run', 'suite', 'resetId')):
        raise ValidationError('adapter_source_mismatch')
    expected = [dict(id=case, status='passed') for case in suite['cases']]
    if value['cases'] != expected or value['cleanup'] != 'passed' or value['status'] != 'passed':
        report.update(status='failed', reason='external_acceptance_incomplete'); return
    report.update(cases=expected, cleanup='passed', status='passed', reason='complete')


def gate(root, manifest_path, reports_path, mode, expected=None, ref=None, run=None, now=None):
    manifest = load_manifest(manifest_path)
    identity = source(root, manifest_path, expected, ref)
    needed = selected(manifest, identity['version'], mode)
    reports = {}; errors = []
    for path in Path(reports_path).glob('*.json'):
        value = read(path)
        name = value.get('suite')
        if name in reports: raise ValidationError('duplicate_suite_evidence')
        reports[name] = value
    errors.extend({'suite': str(name), 'reason': 'unexpected_suite'} for name in reports if name not in needed)
    now = int(time.time()) if now is None else now
    run = context() if run is None else run
    for name, suite in needed.items():
        value = reports.get(name)
        problem = None
        if not value: problem = 'missing'
        elif set(value) != set(base_report(name, identity)): problem = 'unexpected_report_fields'
        elif value['schemaVersion'] != 1 or value['source'] != identity or value['run'] != run: problem = 'wrong_source_or_run'
        elif type(value['finishedAt']) is not int or type(value['startedAt']) is not int or not value['startedAt'] <= value['finishedAt'] <= now + 60 or now - value['startedAt'] > manifest['maxAgeSeconds']: problem = 'stale_or_invalid_time'
        elif value['status'] != 'passed' or value['cleanup'] != 'passed' or value['reason'] != 'complete':
            safe_reasons = {'qa_configuration_missing', 'matching_runner_unavailable', 'qa_runner_configuration_missing', 'disposable_qa_runner_required', 'approved_adapter_missing', 'unprotected_candidate_ref', 'source_trust_check_unavailable'}
            problem = ('blocked_' + value['reason']) if value['status'] == 'blocked' and value['reason'] in safe_reasons else 'not_passed'
        elif value['cases'] != [dict(id=k, status='passed') for k in cases(suite, identity['version'])]: problem = 'incomplete_cases'
        if problem: errors.append({'suite': name, 'reason': problem})
    return dict(schemaVersion=1, source=identity, run=run, mode=mode, status='failed' if errors else 'passed',
                publishable=mode == 'release' and not errors, errors=errors, required=list(needed), generatedAt=now)


def plan(root, manifest_path, mode, expected=None, ref=None):
    manifest = load_manifest(manifest_path); identity = source(root, manifest_path, expected, ref)
    suites = selected(manifest, identity['version'], mode)
    return dict(source=identity, hosted=[name for name, s in suites.items() if s['kind'] == 'hosted'],
                external=[dict(suite=name, labels=s['labels']) for name, s in suites.items() if s['kind'] == 'external'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('plan', 'run', 'gate'))
    parser.add_argument('--root', type=Path, default=HERE)
    parser.add_argument('--manifest', type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument('--commit')
    parser.add_argument('--ref')
    parser.add_argument('--mode', choices=('ci', 'fixtures', 'release'), default='ci')
    parser.add_argument('--suite')
    parser.add_argument('--reports', type=Path, default=Path('artifacts/release-evidence'))
    parser.add_argument('--qa-config', type=Path)
    args = parser.parse_args()
    try:
        if args.action == 'plan': value = plan(args.root, args.manifest, args.mode, args.commit, args.ref)
        elif args.action == 'run': value = run_suite(args.root, args.manifest, args.suite, args.reports, args.commit, args.ref, args.qa_config)
        else:
            value = gate(args.root, args.manifest, args.reports, args.mode, args.commit, args.ref)
            atomic(args.reports / 'summary.report', value)
        print(json.dumps(value if args.action != 'run' else {'suite': value['suite'], 'status': value['status'], 'reason': value['reason']}, indent=2))
        return 0 if value.get('status', 'passed') == 'passed' else 1
    except (ValueError, OSError, KeyError, TypeError):
        print('Release validation refused invalid configuration, source or evidence.', file=sys.stderr)
        return 2
