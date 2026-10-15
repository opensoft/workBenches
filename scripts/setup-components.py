#!/usr/bin/env python3
"""Inspect installation artifacts and remove explicitly selected components."""
import argparse
import getpass
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

from setup_prompts import cancellation_signals

ROOT = Path(__file__).resolve().parents[1]
COMMANDS = {
    'claude_cli': ('claude',), 'copilot_cli': ('copilot',), 'codex_cli': ('codex',),
    'antigravity_cli': ('agy',), 'opencode_cli': ('opencode',), 'pi_cli': ('pi',),
    'spec_kit': ('specify',), 'openspec': ('openspec',), 'vscode': ('code',),
    'warp': ('warp-terminal',), 'wave': ('wave', 'waveterm', 'wave-terminal'),
    'amnezia_vpn': ('AmneziaVPN', 'amnezia-vpn'), '0dcloud_vpn': ('0dcloud',),
}
NPM = {'claude_cli': '@anthropic-ai/claude-code', 'copilot_cli': '@github/copilot',
       'codex_cli': '@openai/codex', 'opencode_cli': 'opencode-ai',
       'pi_cli': '@earendil-works/pi-coding-agent', 'openspec': '@fission-ai/openspec'}
PACKAGES = {
    'claude_cli': ('claude-code', 'claude-code-bin'),
    'copilot_cli': ('github-copilot-cli', 'github-copilot-cli-bin'),
    'codex_cli': ('codex', 'codex-bin'), 'antigravity_cli': ('antigravity',),
    'opencode_cli': ('opencode', 'opencode-bin'), 'pi_cli': ('pi-coding-agent',),
    'spec_kit': ('specify-cli',), 'openspec': ('openspec',),
    'vscode': ('code', 'visual-studio-code-bin', 'visual-studio-code'),
    'warp': ('warp-terminal', 'warp-terminal-bin'),
    'wave': ('waveterm', 'waveterm-bin', 'wave-terminal'),
    'amnezia_vpn': ('amnezia-vpn', 'amneziavpn'), '0dcloud_vpn': ('0dcloud',),
}
FLATPAKS = {'vscode': 'com.visualstudio.code', 'warp': 'dev.warp.Warp',
            'wave': 'dev.waveterm.waveterm', 'amnezia_vpn': 'org.amnezia.AmneziaVPN'}


def read_command(argv, env=None):
    return subprocess.run(argv, capture_output=True, text=True, timeout=15, env=env)


def apply_command(argv, env=None):
    result = subprocess.run(argv, env=env)
    if result.returncode in (130, -2, 143, -15):
        raise SystemExit(130 if result.returncode in (130, -2) else 143)
    if result.returncode:
        raise ValueError('Removal command failed; retry after resolving its error')


def executable_paths(component):
    home = Path.home()
    result = []
    for command in COMMANDS[component]:
        located = shutil.which(command)
        if located:
            result.append(Path(located).absolute())
        for prefix in (home / '.local/bin', home / '.npm-global/bin',
                       home / '.opencode/bin', home / '.antigravity/bin'):
            path = prefix / command
            if path.is_file() and os.access(path, os.X_OK):
                result.append(path.absolute())
    return list(dict.fromkeys(result))


def package_installation(component, executable=None):
    """Only known package IDs are eligible; never remove a shared dependency."""
    allowed = PACKAGES[component]
    if shutil.which('pacman'):
        for name in allowed:
            if read_command(['pacman', '-Q', name]).returncode == 0:
                return ['pacman', '-R', '--', name]
    if shutil.which('dpkg-query') and shutil.which('apt-get'):
        for name in allowed:
            row = read_command(['dpkg-query', '-W', '-f=${Status}', name])
            if row.returncode == 0 and row.stdout.strip() == 'install ok installed':
                return ['apt-get', 'remove', '--no-auto-remove', '--', name]
    if shutil.which('rpm') and shutil.which('dnf'):
        for name in allowed:
            if read_command(['rpm', '-q', name]).returncode == 0:
                return ['dnf', '--setopt=clean_requirements_on_remove=False', 'remove', name]
    if shutil.which('snap'):
        for name in allowed:
            if read_command(['snap', 'list', name]).returncode == 0:
                return ['snap', 'remove', name]
    if component in FLATPAKS and shutil.which('flatpak'):
        name = FLATPAKS[component]
        for scope in ('--user', '--system'):
            if read_command(['flatpak', scope, 'info', name]).returncode == 0:
                return ['flatpak', scope, 'uninstall', name]
    return None


def tool_installed(component):
    return bool(executable_paths(component) or package_installation(component))


def npm_removal(component, path):
    package = NPM.get(component)
    npm = shutil.which('npm')
    if not package or not npm:
        return None
    prefixes = [path.parent.parent]
    result = read_command([npm, 'prefix', '--global'])
    if result.returncode == 0 and result.stdout.strip():
        prefixes.append(Path(result.stdout.strip()))
    for prefix in dict.fromkeys(prefixes):
        directory = prefix / 'lib/node_modules' / package
        try:
            metadata = json.loads((directory / 'package.json').read_text())
        except (OSError, ValueError):
            continue
        if metadata.get('name') == package and path.resolve().is_relative_to(directory.resolve()):
            command = [npm, 'uninstall', '--global', '--ignore-scripts', '--prefix', str(prefix), package]
            if not os.access(directory.parent, os.W_OK):
                command.insert(0, 'sudo')
            return command
    return None


def native_removal(component, path):
    home = Path.home()
    if component == 'claude_cli' and path == home / '.local/bin/claude':
        payload = home / '.local/share/claude'
        if payload.is_symlink() or not path.resolve().is_relative_to(payload):
            return False
        path.unlink()
        if payload.exists():
            shutil.rmtree(payload)
        return True
    known = {'opencode_cli': home / '.opencode/bin/opencode',
             'antigravity_cli': home / '.antigravity/bin/agy'}
    if known.get(component) == path:
        if not path.resolve().is_relative_to(path.parent.resolve()):
            raise ValueError('Native launcher points outside its installation directory')
        path.unlink()
        return True
    if path == home / '.local/bin' / COMMANDS[component][0] and not path.is_symlink():
        # Official standalone Unix installers place native executables here.
        # Keep custom shell/Python wrappers whose ownership is unknown.
        with path.open('rb') as stream:
            if stream.read(4) == b'\x7fELF':
                path.unlink()
                return True
    return False


def uninstall_tool(component):
    # Remove all recognized copies, then verify actual absence. A successful
    # package command against an empty/wrong prefix is not an uninstall.
    for _ in range(8):
        paths = executable_paths(component)
        package = package_installation(component)
        if not paths and not package:
            print('Component is uninstalled. Credentials, profiles, and projects were preserved.')
            return
        if package:
            privileged = package[0] != 'flatpak' or '--system' in package
            apply_command(['sudo', *package] if privileged else package)
        elif component == 'spec_kit' and shutil.which('uv'):
            apply_command(['uv', 'tool', 'uninstall', 'specify-cli'])
        else:
            path = paths[0]
            command = npm_removal(component, path)
            if command:
                apply_command(command)
            elif not native_removal(component, path):
                raise ValueError(f'Unrecognized installation at {path}; remove it with its original installer. No files were deleted from this installation')
        if executable_paths(component) == paths and package_installation(component) == package:
            raise ValueError('Component is still installed after removal; check the installer output')
    raise ValueError('Component is still installed after removal; check for another installation')


def bench_identity(name):
    benches = json.loads((ROOT / 'config/bench-config.json').read_text())['benches']
    relative = Path(benches[name]['path'])
    if relative.is_absolute() or '..' in relative.parts or len(relative.parts) != 2 or relative.parts[0] not in ('devBenches', 'sysBenches', 'bioBenches'):
        raise ValueError('Invalid bench checkout path')
    repo = {'dotNetBench': 'dotnet-bench', '365Bench': 'm365-bench'}.get(name)
    if not repo:
        repo = re.sub(r'([a-z0-9])([A-Z])', r'\1-\2', name).lower()
    user = os.environ.get('USER') or getpass.getuser()
    directory = ROOT / relative
    if directory.resolve() != directory.absolute():
        raise ValueError('Bench checkout path contains a symlink; its runtime was preserved')
    return directory, repo, {repo + ':latest', repo + ':' + user}


def local_docker_environment():
    context = os.environ.get('DOCKER_CONTEXT')
    endpoint = os.environ.get('DOCKER_HOST') if not context else None
    if not endpoint:
        command = ['docker', 'context', 'inspect']
        if context:
            command.append(context)
        result = read_command(command + ['--format', '{{.Endpoints.docker.Host}}'])
        if result.returncode:
            raise ValueError('Cannot verify the local Docker context')
        endpoint = result.stdout.strip()
    if not endpoint.startswith('unix://'):
        raise ValueError('Bench management requires a local Docker socket')
    # Keep every operation on the endpoint just verified, even if another
    # terminal changes the default context while setup is running.
    env = dict(os.environ, DOCKER_HOST=endpoint)
    env.pop('DOCKER_CONTEXT', None)
    return env


def docker_inventory(env=None):
    env = env or local_docker_environment()
    result = read_command(['docker', 'image', 'ls', '--format', '{{.Repository}}:{{.Tag}}'], env=env)
    if result.returncode:
        raise ValueError('Docker image inventory is unavailable')
    images = set(result.stdout.splitlines())
    result = read_command(['docker', 'ps', '-aq'], env=env)
    if result.returncode:
        raise ValueError('Docker container inventory is unavailable')
    ids = result.stdout.split()
    containers = []
    if ids:
        result = read_command(['docker', 'inspect', *ids], env=env)
        if result.returncode:
            raise ValueError('Docker container inventory changed; refresh and retry')
        containers = json.loads(result.stdout)
    return images, containers


def bench_resources(name, inventory):
    directory, repo, refs = bench_identity(name)
    images, containers = inventory
    selected = []
    for row in containers:
        image = row.get('Config', {}).get('Image', '')
        container_name = row.get('Name', '').lstrip('/')
        if container_name == repo:
            labels = row.get('Config', {}).get('Labels') or {}
            working = labels.get('com.docker.compose.project.working_dir')
            if image not in refs or (working and not Path(working).resolve().is_relative_to(directory.resolve())):
                raise ValueError(f'{repo} belongs to another installation; it was preserved')
            selected.append(row)
    return images & refs, selected


def bench_statuses():
    names = json.loads((ROOT / 'config/bench-config.json').read_text())['benches']
    try:
        inventory = docker_inventory()
    except (OSError, ValueError, subprocess.TimeoutExpired):
        for name in names:
            print(name + '\tneeds docker')
        return
    for name in names:
        try:
            images, containers = bench_resources(name, inventory)
            _, repo, _ = bench_identity(name)
            user = os.environ.get('USER') or getpass.getuser()
            state = 'installed' if containers or repo + ':' + user in images else ('image only' if images else 'needs setup')
        except ValueError:
            state = 'needs check'
        print(name + '\t' + state)


def uninstall_bench(name):
    # Do not mutate a remote Docker host using local checkout metadata.
    env = local_docker_environment()
    inventory = docker_inventory(env=env)
    images, containers = bench_resources(name, inventory)
    ids = [row['Id'] for row in containers]
    if any(row.get('Config', {}).get('Image') in images and row['Id'] not in ids for row in inventory[1]):
        raise ValueError('Another container uses a selected image; its container and image were preserved')
    print(f'Uninstalling {name}: {len(ids)} container(s), {len(images)} image tag(s).')
    for row in containers:
        if row.get('State', {}).get('Running'):
            apply_command(['docker', 'container', 'stop', '--time', '10', row['Id']], env=env)
        apply_command(['docker', 'container', 'rm', row['Id']], env=env)
    if images:
        apply_command(['docker', 'image', 'rm', *sorted(images)], env=env)
    remaining_images, remaining_containers = bench_resources(name, docker_inventory(env=env))
    if remaining_images or remaining_containers:
        raise ValueError('Bench artifacts remain; refresh and retry')
    print(f'{name} uninstalled. Checkout, projects, credentials, volumes, and shared base images were preserved.')


def main():
    cancellation_signals()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('tool-status', 'bench-statuses', 'uninstall'))
    parser.add_argument('component', nargs='?')
    args = parser.parse_args()
    if args.action != 'bench-statuses' and not args.component:
        parser.error('this action requires a component')
    if args.action == 'bench-statuses':
        bench_statuses()
    elif args.action == 'tool-status':
        print('installed' if tool_installed(args.component) else 'not installed')
    elif args.component.startswith('bench_'):
        uninstall_bench(args.component[6:])
    else:
        uninstall_tool(args.component)


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, subprocess.TimeoutExpired) as error:
        print(f'Component change needs attention: {error}', file=sys.stderr)
        sys.exit(1)
