"""Source-qualified, user-owned CLI installation; never handles provider credentials."""
from __future__ import annotations

import contextlib
import fcntl
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shlex
import shutil
import signal
import subprocess
import tarfile
import urllib.request
from urllib.parse import urlparse
import uuid
import time

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / 'config/harness-installers.json'
ID = re.compile(r'^[a-z][a-z0-9_]*$')
COMMAND = re.compile(r'^[A-Za-z0-9][A-Za-z0-9._+-]*$')
KINDS = {'npm', 'python', 'script', 'git-python', 'git-node', 'git-requirements', 'release', 'unavailable'}
FIELDS = {'id', 'label', 'kind', 'command', 'executable', 'platforms', 'verify', 'source', 'note',
          'package', 'observedVersion', 'url', 'python', 'shell', 'arguments', 'search', 'entry',
          'interpreter', 'environment', 'tuiPackage', 'repository', 'asset', 'checksums', 'format',
          'tagPrefix', 'archMapping', 'cwdVariable'}


class HarnessError(ValueError):
    pass


def registry(path=REGISTRY):
    data = json.loads(Path(path).read_text())
    if not isinstance(data, dict) or data.get('schemaVersion') != 1 or set(data) != {'schemaVersion', 'entries'} or not isinstance(data.get('entries'), list):
        raise HarnessError('Invalid harness installer registry')
    rows = {}
    for row in data['entries']:
        if not isinstance(row, dict) or not set(row) <= FIELDS:
            raise HarnessError('Unknown harness recipe fields')
        if not isinstance(row.get('id'), str) or not ID.fullmatch(row['id']) or row['id'] in rows or not isinstance(row.get('kind'), str) or row['kind'] not in KINDS:
            raise HarnessError('Invalid or duplicate harness recipe')
        for field in ('label', 'source', 'note'):
            if not isinstance(row.get(field), str) or not row[field].strip() or any(not c.isprintable() for c in row[field]):
                raise HarnessError('Harness recipe needs printable publisher provenance and scope')
        for field in ('source', 'url'):
            if field in row:
                value = row[field]
                if not isinstance(value, str) or any(c.isspace() for c in value):
                    raise HarnessError('Invalid publisher URL')
                parsed = urlparse(value)
                if parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password:
                    raise HarnessError('Publisher URLs require HTTPS without credentials')
        if row['kind'] != 'unavailable':
            if any(not isinstance(row.get(field), str) or not COMMAND.fullmatch(row[field]) for field in ('command', 'executable')):
                raise HarnessError('Invalid harness command')
            if not isinstance(row.get('platforms'), list) or not row['platforms'] or any(p not in ('linux', 'darwin') for p in row['platforms']):
                raise HarnessError('Invalid harness platforms')
            if not isinstance(row.get('verify'), list) or not row['verify']:
                raise HarnessError('Harness needs a noninteractive verification command')
            for field in ('verify', 'arguments', 'search'):
                values = row.get(field, [])
                if not isinstance(values, list) or any(not isinstance(value, str) or not value or any(not c.isprintable() for c in value) for value in values):
                    raise HarnessError('Invalid harness argument/path list')
            if row['kind'] in {'script', 'git-python', 'git-node', 'git-requirements'} and not row.get('url', '').startswith('https://'):
                raise HarnessError('Installer/source URL must use HTTPS')
            if row['kind'] in {'npm', 'python', 'git-python'}:
                pattern = r'(?:@[a-z0-9-]+/)?[a-z0-9][a-z0-9_.-]*' if row['kind'] == 'npm' else r'[A-Za-z0-9][A-Za-z0-9_.-]*(?:\[[A-Za-z0-9_,.-]+\])?'
                if not isinstance(row.get('package'), str) or not re.fullmatch(pattern, row['package']):
                    raise HarnessError('Invalid package identity')
            if not isinstance(row.get('entry', 'placeholder'), str):
                raise HarnessError('Invalid source entry path')
            for relative in row.get('search', []) + [row.get('entry', 'placeholder')]:
                if Path(relative).is_absolute() or '..' in Path(relative).parts:
                    raise HarnessError('Recipe path escapes its prefix')
            if row.get('shell', 'bash') not in ('bash', 'sh', 'node'):
                raise HarnessError('Unsupported installer interpreter')
            if row.get('interpreter', 'node') not in ('node', 'python3'):
                raise HarnessError('Unsupported runtime interpreter')
            if 'python' in row and (not isinstance(row['python'], str) or not re.fullmatch(r'3\.\d+', row['python'])):
                raise HarnessError('Invalid Python runtime version')
            if row.get('cwdVariable') and (not isinstance(row['cwdVariable'], str) or not re.fullmatch(r'[A-Z][A-Z0-9_]*', row['cwdVariable']) or row['cwdVariable'] in {'HOME', 'PATH'}):
                raise HarnessError('Invalid project directory environment name')
            if not isinstance(row.get('environment', {}), dict):
                raise HarnessError('Invalid installer environment')
            if any(not re.fullmatch(r'[A-Z][A-Z0-9_]*', key) or key in {'PATH', 'HOME'} or re.search(r'(?:TOKEN|API_KEY|PASSWORD|SECRET)', key) or not isinstance(value, str)
                   for key, value in row.get('environment', {}).items()):
                raise HarnessError('Invalid installer environment')
            if row['kind'] == 'release' and (not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', row.get('repository', '')) or not row.get('asset')):
                raise HarnessError('Invalid publisher release identity')
        rows[row['id']] = row
    return rows


def atomic_json(path, value):
    temporary = path.with_name('.' + path.name + '-' + uuid.uuid4().hex)
    try:
        with open(temporary, 'x', opener=lambda name, flags: os.open(name, flags, 0o600)) as output:
            output.write(json.dumps(value, indent=2) + '\n')
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def safe_directory(path, boundary):
    path, boundary = Path(path), Path(boundary)
    if not path.is_relative_to(boundary):
        raise HarnessError('Installation path escapes its owned root')
    current = boundary
    for part in ('', *path.relative_to(boundary).parts):
        if part:
            current /= part
        if current.is_symlink() or current.exists() and (not current.is_dir() or current.stat().st_uid != os.getuid()):
            raise HarnessError('Installation directory is not owned or is a symlink')
        current.mkdir(mode=0o700, exist_ok=True)


def inspect_directory(path, boundary):
    if not path.is_relative_to(boundary):
        raise HarnessError('Installation directory escapes its home')
    for current in [boundary, *(boundary.joinpath(*path.relative_to(boundary).parts[:i])
                                 for i in range(1, len(path.relative_to(boundary).parts) + 1))]:
        if current.is_symlink() or current.exists() and (not current.is_dir() or current.stat().st_uid != os.getuid() or current.stat().st_mode & 0o022):
            raise HarnessError('Foreign, writable or redirected installation directory')


class Runner:
    def __init__(self, local=False):
        self.host = None
        if not local and os.environ.get('WORKBENCHES_HOST_RPC'):
            import workbenches_host
            self.host = workbenches_host
        self.tools = {}

    def system(self):
        if not hasattr(self, '_system'):
            self._system = self.host.run(['uname', '-s'], capture_output=True, text=True).stdout.strip().lower() if self.host else platform.system().lower()
        return self._system

    def machine(self):
        if not hasattr(self, '_machine'):
            self._machine = self.host.run(['uname', '-m'], capture_output=True, text=True).stdout.strip() if self.host else platform.machine()
        return self._machine

    def which(self, name):
        if name not in self.tools:
            value = self.host.which(name) if self.host else shutil.which(name)
            if value and '/mise/shims/' in value:
                result = self.host.run(['mise', 'which', name], capture_output=True, text=True) if self.host else subprocess.run(
                    ['mise', 'which', name], capture_output=True, text=True)
                if result.returncode == 0:
                    value = result.stdout.strip()
            self.tools[name] = value
        return self.tools[name]

    def run(self, arguments, *, cwd, env, timeout=1800):
        if self.host:
            helper = Path(__file__).with_name('harness-native-command.sh')
            # The host boundary deliberately ignores a container PATH. The
            # native helper adds only owned guards and resolved native tools.
            dirs = list(dict.fromkeys(str(Path(p).parent) for name in ('node', 'npm', 'uv', 'bun', 'python3')
                                      if (p := self.which(name))))
            control = Path(env['HARNESS_GUARD_BIN']) / ('operation-' + uuid.uuid4().hex)
            control.touch(mode=0o600)
            done = Path(str(control) + '.done')
            try:
                return self.host.run(['bash', str(helper), str(cwd), str(env['HOME']),
                                      env['HARNESS_GUARD_BIN'], os.pathsep.join(dirs), str(control), str(timeout),
                                      *[key + '=' + value for key, value in env.items() if key != 'PATH'], '--', *arguments],
                                     env=env, capture_output=True, text=True, timeout=timeout + 15)
            finally:
                control.unlink(missing_ok=True)
                deadline = time.monotonic() + 4
                while not done.exists() and time.monotonic() < deadline:
                    time.sleep(0.05)
                self.cancelled_unconfirmed = not done.exists()
                done.unlink(missing_ok=True)
        process = subprocess.Popen(arguments, cwd=cwd, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   text=True, stdin=subprocess.DEVNULL, start_new_session=True)
        try:
            stdout, stderr = process.communicate(timeout=timeout)
            return subprocess.CompletedProcess(arguments, process.returncode, stdout, stderr)
        except BaseException:
            try:
                os.killpg(process.pid, signal.SIGTERM)
                process.communicate(timeout=2)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.communicate()
            except ProcessLookupError:
                pass
            raise


class Installer:
    def __init__(self, rows=None, *, home=None, runner=None, fetch=None):
        self.rows = registry() if rows is None else rows
        self.home = Path(home or Path.home()).absolute()
        self.base = self.home / '.local/share/workbenches/harnesses'
        self.bin = self.home / '.local/bin'
        self.runner = runner or Runner()
        self.fetch = fetch or self.download

    @staticmethod
    def download(url):
        if not url.startswith('https://'):
            raise HarnessError('Download requires HTTPS')
        request = urllib.request.Request(url, headers={'User-Agent': 'workBenches/1.7 harness-installer'})
        with urllib.request.urlopen(request, timeout=60) as response:
            if not response.geturl().startswith('https://'):
                raise HarnessError('Insecure download redirect')
            body = response.read(512 * 1024 * 1024 + 1)
            if len(body) > 512 * 1024 * 1024:
                raise HarnessError('Publisher download exceeds size limit')
            return body

    def recipe(self, key):
        if os.getuid() == 0:
            raise HarnessError('Managed harnesses must run as the intended non-root user')
        if key not in self.rows:
            raise HarnessError('Unknown managed harness')
        row = self.rows[key]
        if row['kind'] == 'unavailable':
            raise HarnessError(row['note'])
        if self.runner.system() not in row['platforms']:
            raise HarnessError('This publisher distribution does not support this platform')
        return row

    @contextlib.contextmanager
    def locked(self, key):
        if key not in self.rows:
            raise HarnessError('Unknown harness')
        safe_directory(self.base, self.home)
        path = self.base / (key + '.lock')
        fd = os.open(path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        try:
            if os.fstat(fd).st_uid != os.getuid():
                raise HarnessError('Foreign harness lock')
            fcntl.flock(fd, fcntl.LOCK_EX)
            yield
        finally:
            os.close(fd)

    def checked(self, arguments, payload, env, cwd=None):
        result = self.runner.run(arguments, cwd=cwd or payload, env=env)
        if result.returncode:
            if result.returncode in (130, 143):
                raise SystemExit(result.returncode)
            # Installer environments contain no provider credentials. Keep raw
            # vendor output out of status/receipts and fail without activation.
            raise HarnessError(f'{Path(arguments[0]).name} failed (exit {result.returncode}); '
                               'check the publisher prerequisites and retry; previous installation retained')
        return result

    def tool(self, name):
        value = self.runner.which(name)
        if not value and name in {'uv', 'bun', 'pnpm'} and hasattr(self, 'payload'):
            payload, env = self.payload, self.install_env
            if name == 'pnpm':
                self.checked([self.tool('npm'), 'install', '-g', '--prefix', str(payload / 'build-tools'), 'pnpm@latest'], payload, env)
                value = str(payload / 'build-tools/bin/pnpm')
            else:
                url = 'https://astral.sh/uv/install.sh' if name == 'uv' else 'https://bun.sh/install'
                script = payload / (name + '-installer.sh'); script.write_bytes(self.fetch(url))
                extra = {'UV_INSTALL_DIR': str(payload / 'build-tools/bin'), 'UV_NO_MODIFY_PATH': '1'} if name == 'uv' else {'BUN_INSTALL': str(payload / 'build-tools')}
                self.checked([self.tool('bash'), str(script)], payload, dict(env, **extra))
                value = str(payload / 'build-tools/bin' / name)
            if not Path(value).is_file():
                raise HarnessError(name + ' prerequisite installer did not produce its command')
            env['PATH'] = str(Path(value).parent) + ':' + env['PATH']
            self.runner.tools[name] = value
        if not value:
            raise HarnessError(f'{name} is required; install this prerequisite and retry')
        return value

    def environment(self, payload):
        home = payload / 'installer-home'; home.mkdir(mode=0o700)
        guard = payload / 'guards'; guard.mkdir(mode=0o700)
        sudo = guard / 'sudo'
        sudo.write_text('#!/bin/sh\necho "Privileged installer changes are not permitted" >&2\nexit 1\n')
        sudo.chmod(0o755)
        keep = {'PATH', 'LANG', 'LC_ALL', 'TERM', 'HTTP_PROXY', 'HTTPS_PROXY', 'NO_PROXY', 'SSL_CERT_FILE', 'SSL_CERT_DIR'}
        env = {key: value for key, value in os.environ.items() if key in keep}
        env.update(HOME=str(home), CI='1', NONINTERACTIVE='1', HARNESS_GUARD_BIN=str(guard),
                   PATH=str(guard) + os.pathsep + env.get('PATH', '/usr/local/bin:/usr/bin:/bin'),
                   UV_TOOL_DIR=str(payload / 'uv-tools'), UV_TOOL_BIN_DIR=str(payload / 'uv-bin'),
                   UV_PYTHON_INSTALL_DIR=str(payload / 'python'), UV_CACHE_DIR=str(payload / 'cache'),
                   PIP_NO_INPUT='1', GIT_TERMINAL_PROMPT='0')
        return env

    def populate(self, row, payload, env):
        kind, executable = row['kind'], row['executable']
        if kind == 'npm':
            npm = self.tool('npm')
            (payload / 'npm/lib/node_modules').mkdir(parents=True)
            (payload / 'npm/bin').mkdir()
            # Use a private userconfig: never alter the user's lifecycle policy.
            config = payload / 'npmrc'
            allowed = [row['package'], 'node-pty', 'koffi', 'sharp', '@qwen-code/audio-capture',
                       '@deepseek-ai/dsh-subprocess-local', '@google/genai', 'protobufjs']
            config.write_text('include[]=optional\n' + ''.join('allow-scripts[]=' + name + '\n' for name in allowed))
            env['NPM_CONFIG_USERCONFIG'] = str(config)
            self.checked([npm, 'install', '--global', '--prefix', str(payload / 'npm'),
                          '--prefer-online', '--include=optional', '--strict-allow-scripts', '--no-audit', '--no-fund', row['package'] + '@latest'], payload, env)
            return payload / 'npm/bin' / executable
        if kind == 'python':
            self.checked([self.tool('uv'), 'tool', 'install', '--python', row.get('python', '3.12'),
                          row['package']], payload, env)
            return payload / 'uv-bin' / executable
        if kind == 'script':
            env.update({key: value.replace('{home}', env['HOME']) for key, value in row.get('environment', {}).items()})
            body = self.fetch(row['url'])
            if len(body) > 1024 * 1024:
                raise HarnessError('Publisher installer exceeds size limit')
            suffix = '.mjs' if row.get('shell') == 'node' else '.sh'
            script = payload / ('publisher-installer' + suffix); script.write_bytes(body)
            self.checked([self.tool(row.get('shell', 'bash')), str(script), *row.get('arguments', [])], payload, env)
            for relative in row.get('search', ['installer-home/.local/bin/' + executable,
                                             'installer-home/.cargo/bin/' + executable,
                                             'installer-home/.cursor/bin/' + executable,
                                             'installer-home/.amp/bin/' + executable]):
                candidate = payload / relative
                if candidate.is_file():
                    return candidate
            raise HarnessError('Publisher installer completed without the expected executable')
        if kind in {'git-python', 'git-node', 'git-requirements'}:
            source = payload / 'source'
            self.checked([self.tool('git'), 'clone', '--depth', '1', row['url'], str(source)], payload, env)
            if kind == 'git-python':
                self.checked([self.tool('uv'), 'tool', 'install', '--python', row.get('python', '3.12'),
                              '--from', str(source), row['package']], payload, env)
                if row.get('tuiPackage'):
                    self.checked([self.tool('npm'), 'install', '--global', '--prefix', str(payload / 'npm'),
                                  '--no-audit', '--no-fund', row['tuiPackage'] + '@latest'], payload, env)
                    return payload / 'npm/bin' / executable
                return payload / 'uv-bin' / executable
            if kind == 'git-requirements':
                uv = self.tool('uv')
                self.checked([uv, 'venv', '--python', row.get('python', '3.11'), str(payload / 'venv')], payload, env)
                python = payload / 'venv/bin/python'
                self.checked([uv, 'pip', 'install', '--python', str(python), '-r', str(source / 'requirements.txt')], payload, env)
                launcher = payload / executable
                launcher.write_text('#!/usr/bin/env bash\nexport PYTHONPATH=' + shlex.quote(str(source)) + '\nexec '
                                    + shlex.join([str(python), str(source / row['entry'])]) + ' "$@"\n')
                launcher.chmod(0o755)
                return launcher
            # Honor the source project's package-manager contract without
            # changing a workstation-global Corepack/pnpm installation.
            manager = json.loads((source / 'package.json').read_text()).get('packageManager', '')
            if not re.fullmatch(r'pnpm@\d+\.\d+\.\d+(?:\+sha\d+\.[A-Za-z0-9]+)?', manager):
                raise HarnessError('Source project must declare an exact pnpm package manager')
            (payload / 'build-tools/lib/node_modules').mkdir(parents=True, exist_ok=True)
            (payload / 'build-tools/bin').mkdir(exist_ok=True)
            self.checked([self.tool('npm'), 'install', '-g', '--prefix', str(payload / 'build-tools'),
                          manager.split('+')[0]], payload, env)
            pnpm = str(payload / 'build-tools/bin/pnpm')
            env['PATH'] = str(payload / 'build-tools/bin') + ':' + env['PATH']
            self.checked([pnpm, 'install', '--frozen-lockfile'], payload, env, cwd=source)
            self.checked([pnpm, '--filter', '@zcode/cli...', 'build'], payload, env, cwd=source)
            return source / row['entry']
        if kind == 'release':
            api = 'https://api.github.com/repos/' + row['repository'] + '/releases/latest'
            release = json.loads(self.fetch(api))
            if row.get('tagPrefix') and not release.get('tag_name', '').startswith(row['tagPrefix']):
                raise HarnessError('Latest publisher release is a different product; retry after a CLI release')
            arch = {'x86_64': 'x86_64', 'aarch64': 'aarch64', 'arm64': 'aarch64'}.get(self.runner.machine())
            arch = row.get('archMapping', {}).get(arch, arch)
            pattern = row['asset'].replace('{arch}', arch or 'UNSUPPORTED')
            assets = [a for a in release['assets'] if re.fullmatch(pattern, a['name'])]
            if len(assets) != 1:
                raise HarnessError('No unique publisher release for this architecture')
            url = assets[0]['browser_download_url']; body = self.fetch(url)
            if row.get('checksums'):
                checksum_assets = [a for a in release['assets'] if a['name'] == row['checksums']]
                if len(checksum_assets) != 1:
                    raise HarnessError('Publisher checksum manifest missing')
                lines = self.fetch(checksum_assets[0]['browser_download_url']).decode().splitlines()
                matches = [line.split()[0] for line in lines if len(line.split()) == 2
                           and line.split()[1].lstrip('*') == assets[0]['name']]
                if len(matches) != 1:
                    raise HarnessError('Publisher archive missing from checksum manifest')
                expected = matches[0]
            elif assets[0].get('digest', '').startswith('sha256:'):
                expected = assets[0]['digest'][7:]
            else:
                expected = self.fetch(url + '.sha256').decode().split()[0]
            if not re.fullmatch(r'[0-9a-fA-F]{64}', expected) or hashlib.sha256(body).hexdigest() != expected.lower():
                raise HarnessError('Publisher archive checksum mismatch')
            if row.get('format') == 'binary':
                entry = payload / executable; entry.write_bytes(body); entry.chmod(0o755)
                return entry
            archive = payload / 'release.tar.gz'; archive.write_bytes(body)
            output = payload / 'release'; output.mkdir()
            with tarfile.open(archive) as bundle:
                members = bundle.getmembers()
                if sum(m.size for m in members) > 1024 * 1024 * 1024 or len(members) > 20000:
                    raise HarnessError('Publisher archive exceeds extraction limit')
                for member in members:
                    name = Path(member.name)
                    if name.is_absolute() or '..' in name.parts or not (member.isdir() or member.isfile()):
                        raise HarnessError('Unsafe publisher archive member')
                    member.mode &= 0o755
                # Python 3.10 is still used by the declared workstation test
                # bench. All links, special files and traversal were rejected
                # above before extracting anything.
                bundle.extractall(output, members=members)
            candidates = [p for p in output.rglob(executable) if p.is_file()]
            if len(candidates) != 1:
                raise HarnessError('Publisher archive does not identify one executable')
            return candidates[0]
        raise HarnessError('Unsupported recipe kind')

    def install(self, key):
        row = self.recipe(key)
        with self.locked(key):
            component = self.base / key
            safe_directory(component / 'versions', self.home)
            safe_directory(self.bin, self.home)
            launcher = self.bin / row['command']
            destination = component / 'current/bin' / row['command']
            if launcher.exists() or launcher.is_symlink():
                if not launcher.is_symlink() or os.readlink(launcher) != str(destination):
                    raise HarnessError('An unrelated launcher occupies ' + row['command'] + '; it was preserved')
            active = component / 'current'
            previous = os.readlink(active) if active.is_symlink() else None
            if active.exists() and not active.is_symlink():
                raise HarnessError('Harness activation path is not a managed symlink')
            if previous is not None:
                self.status(key)  # Validate the old target before replacing it.
            payload = component / 'versions' / uuid.uuid4().hex
            payload.mkdir(mode=0o700)
            promoted = False
            created_launcher = False
            try:
                env = self.environment(payload)
                self.payload, self.install_env = payload, env
                if key == 'letta_code':
                    self.tool('bun')
                entry = self.populate(row, payload, env)
                if not entry.is_file() or not entry.resolve().is_relative_to(payload.resolve()):
                    raise HarnessError('Installed executable is missing or escapes the owned prefix')
                arguments = ([self.tool(row['interpreter'])] if row.get('interpreter') else []) + [str(entry)]
                bins = payload / 'bin'; bins.mkdir()
                wrapper = bins / row['command']
                runtime_path = [str(payload / 'uv-bin'), str(payload / 'npm/bin'), str(payload / 'build-tools/bin')]
                runtime_path += list(dict.fromkeys(str(Path(p).parent) for name in ('node', 'bun') if (p := self.runner.which(name))))
                cwd_export = ''
                if row.get('cwdVariable'):
                    name = row['cwdVariable']
                    cwd_export = 'export ' + name + '="${' + name + ':-$PWD}"\n'
                wrapper.write_text('#!/usr/bin/env bash\n' + cwd_export + 'export PATH=' + shlex.quote(':'.join(runtime_path)) + ':"$PATH"\nexec ' + shlex.join(arguments) + ' "$@"\n')
                wrapper.chmod(0o755)
                probe_home = payload / 'probe-home'; probe_home.mkdir(mode=0o700)
                # Verify the actual launcher from a fresh runtime home. A
                # publisher shim tied to its staging HOME must not be promoted.
                verify_env = dict(env, HOME=str(probe_home))
                result = self.checked([str(wrapper), *row['verify']], payload, verify_env)
                output = re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]', '', result.stdout or '')
                version = next((line.strip()[:160] for line in output.splitlines() if line.strip()), 'command verified')
                version = ''.join(c for c in version if c.isprintable())
                if row['kind'] == 'npm':
                    metadata = json.loads((payload / 'npm/lib/node_modules' / row['package'] / 'package.json').read_text())
                    if metadata.get('name') != row['package'] or not isinstance(metadata.get('version'), str):
                        raise HarnessError('Installed npm package identity does not match the reviewed recipe')
                    version = metadata['version']
                elif row['kind'].startswith('git-'):
                    proof = self.checked([self.tool('git'), 'rev-parse', 'HEAD'], payload, env, cwd=payload / 'source')
                    if not re.fullmatch(r'[0-9a-f]{40,64}', proof.stdout.strip()):
                        raise HarnessError('Source checkout identity is unavailable')
                    version = 'git ' + proof.stdout.strip()
                elif row['kind'] == 'python':
                    from email.parser import Parser
                    expected_name = re.sub(r'[-_.]+', '-', row['package'].split('[')[0]).lower()
                    versions = set()
                    for metadata_path in (payload / 'uv-tools').rglob('*.dist-info/METADATA'):
                        metadata = Parser().parsestr(metadata_path.read_text())
                        if re.sub(r'[-_.]+', '-', metadata.get('Name', '')).lower() == expected_name:
                            versions.add(metadata.get('Version', ''))
                    if len(versions) != 1 or not next(iter(versions)):
                        raise HarnessError('Installed Python distribution identity is unavailable')
                    version = versions.pop()
                atomic_json(payload / 'receipt.json', {'schemaVersion': 1, 'id': key,
                    'command': row['command'], 'version': version, 'source': row['source'],
                    'entry': str(entry.relative_to(payload)), 'entryHash': hashlib.sha256(entry.read_bytes()).hexdigest(),
                    'launcherHash': hashlib.sha256(wrapper.read_bytes()).hexdigest()})
                if launcher.exists() or launcher.is_symlink():
                    if not launcher.is_symlink() or os.readlink(launcher) != str(destination):
                        raise HarnessError('Public launcher changed during installation; it was preserved')
                temporary = component / ('.activate-' + uuid.uuid4().hex)
                temporary.symlink_to(payload.relative_to(component))
                os.replace(temporary, active)
                promoted = True
                if not launcher.is_symlink():
                    launcher.symlink_to(destination)
                    created_launcher = True
                print(f'{row["id"]}: installed and verified ({version})')
                return version
            except BaseException:
                if promoted:
                    if previous is None:
                        active.unlink()
                    else:
                        rollback = component / ('.rollback-' + uuid.uuid4().hex)
                        rollback.symlink_to(previous)
                        os.replace(rollback, active)
                if created_launcher:
                    launcher.unlink()
                if not getattr(self.runner, 'cancelled_unconfirmed', False):
                    shutil.rmtree(payload)
                raise

    def status(self, key):
        row = self.recipe(key)
        active = self.base / key / 'current'
        inspect_directory(self.base / key / 'versions', self.home)
        inspect_directory(self.bin, self.home)
        if not active.is_symlink():
            return 'not installed'
        payload = active.resolve()
        if not payload.is_relative_to(self.base / key / 'versions'):
            raise HarnessError('Harness activation escapes its owned prefix')
        receipt_path = payload / 'receipt.json'
        if receipt_path.is_symlink() or not receipt_path.is_file() or receipt_path.stat().st_uid != os.getuid() or receipt_path.stat().st_mode & 0o077 or receipt_path.stat().st_size > 65536:
            raise HarnessError('Invalid harness receipt')
        receipt = json.loads(receipt_path.read_text())
        fields = {'schemaVersion', 'id', 'command', 'version', 'source', 'entry', 'entryHash', 'launcherHash'}
        if not isinstance(receipt, dict) or set(receipt) != fields or receipt.get('schemaVersion') != 1 or any(not isinstance(receipt[field], str) for field in fields - {'schemaVersion'}):
            raise HarnessError('Invalid harness receipt schema')
        if Path(receipt['entry']).is_absolute() or '..' in Path(receipt['entry']).parts or receipt['source'] != row['source']:
            raise HarnessError('Mismatched harness receipt path/source')
        entry = payload / receipt['entry']
        if receipt.get('id') != key or receipt.get('command') != row['command'] or not entry.resolve().is_relative_to(payload):
            raise HarnessError('Mismatched harness receipt')
        if not entry.is_file() or hashlib.sha256(entry.read_bytes()).hexdigest() != receipt['entryHash']:
            return 'needs check'
        wrapper = payload / 'bin' / row['command']
        if wrapper.is_symlink() or not wrapper.is_file() or hashlib.sha256(wrapper.read_bytes()).hexdigest() != receipt['launcherHash']:
            return 'needs check'
        launcher = self.bin / row['command']
        if not launcher.is_symlink() or os.readlink(launcher) != str(active / 'bin' / row['command']):
            return 'needs check'
        return 'installed'

    def workstation_status(self, key):
        state = self.status(key)
        if state != 'installed':
            return state
        command = self.rows[key]['command']
        # Query the native command search, not the Tools container's PATH.
        self.runner.tools.pop(command, None)
        located = self.runner.which(command)
        if not located or Path(located).resolve() != (self.bin / command).resolve():
            return 'needs path'
        return state

    def report_path_setup(self, key):
        command = self.rows[key]['command']
        print(f'{key}: PATH setup needed; verified launcher retained at {self.bin / command}.')
        print('Add export PATH="$HOME/.local/bin:$PATH" to your shell startup file, then open a new terminal.')

    def uninstall(self, key):
        row = self.recipe(key)
        with self.locked(key):
            if self.status(key) == 'not installed':
                print(f'{key}: no managed installation remains; external installations preserved')
                return
            if self.status(key) != 'installed':
                raise HarnessError('Installation changed; inspect it before removal')
            component = self.base / key
            launcher = self.bin / row['command']
            expected = component / 'current/bin' / row['command']
            if not launcher.is_symlink() or os.readlink(launcher) != str(expected):
                raise HarnessError('Launcher changed; no installation files were removed')
            launcher.unlink()
            shutil.rmtree(component)
            print(f'{key}: managed installation removed; credentials and projects preserved')
