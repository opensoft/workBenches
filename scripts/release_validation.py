"""Commit-bound release suites and fail-closed evidence validation (stdlib only)."""
import argparse
import hashlib
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
    return dict(commit=commit, version=product, lockSha256=digest(root / 'config/release-lock.json'),
                manifestSha256=digest(manifest_path), ref=ref or commit)


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
    frames = re.findall(rb'File "[^"\n]*(test-workstation-acceptance\.py|test-component-lifecycle\.py)", line ([0-9]{1,7})', raw)
    if frames:
        result.update(file=frames[-1][0].decode('ascii'), line=int(frames[-1][1]))
    if re.search(rb'no space left on device|disk quota exceeded|\bENOSPC\b', raw, re.I):
        result['category'] = 'disk_full'
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
