#!/usr/bin/env python3
"""Read-only workstation readiness; never installs software or reads secrets."""
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys


def run(args):
    try:
        result = subprocess.run(args, capture_output=True, timeout=8)
        output = result.stdout
        return result.returncode, output.decode('utf-16' if output.startswith((b'\xff\xfe', b'\xfe\xff')) else 'utf-16-le' if b'\x00' in output else 'utf-8', errors='replace').strip()
    except (OSError, subprocess.TimeoutExpired):
        return 1, ''


def operating_system():
    system, release = platform.system(), platform.release()
    distro = {}
    try:
        for line in Path('/etc/os-release').read_text().splitlines():
            key, _, value = line.partition('=')
            distro[key] = value.strip('"')
    except OSError:
        pass
    wsl = system == 'Linux' and ('microsoft' in release.lower() or bool(os.environ.get('WSL_DISTRO_NAME')))
    native_windows = system == 'Windows' or system.startswith(('MINGW', 'MSYS', 'CYGWIN'))
    label = 'Windows / WSL' if wsl else 'Windows' if native_windows else 'macOS' if system == 'Darwin' else system
    name = distro.get('PRETTY_NAME', '')
    if name and system == 'Linux':
        label += ' — ' + name
    return label, wsl, native_windows, release


def snapshot():
    label, wsl, windows, release = operating_system()
    rows = []
    if wsl or windows:
        ready = wsl and 'microsoft-standard' in release.lower()
        if wsl and not ready and shutil.which('wsl.exe') and os.environ.get('WSL_DISTRO_NAME'):
            status, listing = run(['wsl.exe', '--list', '--verbose'])
            ready = status == 0 and any(line.strip().lstrip('*').strip().rsplit(None, 1)[-1:] == ['2']
                                       and line.strip().lstrip('*').strip().startswith(os.environ['WSL_DISTRO_NAME'] + ' ')
                                       for line in listing.splitlines())
        rows.append({'key': 'wsl', 'label': 'WSL 2 running', 'ready': ready,
                     'detail': 'ready' if ready else 'Run setup inside a WSL 2 Linux distribution'})
    missing = [name for name in ('python3', 'jq', 'git', 'curl') if not shutil.which(name)]
    rows.append({'key': 'setup_tools', 'label': 'Setup tools', 'ready': not missing,
                 'detail': ', '.join(missing) + ' missing' if missing else 'Python, jq, Git, curl ready'})
    if not shutil.which('docker'):
        detail, ready = 'not installed', False
    else:
        status, output = run(['docker', 'info', '--format', '{{.OSType}}'])
        ready = status == 0 and output == 'linux'
        detail = 'ready (Linux containers)' if ready else 'switch to Linux containers' if status == 0 and output == 'windows' else 'daemon / user access unavailable'
    rows.append({'key': 'docker', 'label': 'Docker', 'ready': ready, 'detail': detail})
    return {'os': label, 'requirements': rows}


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else 'json'
    if command == 'os':
        print(operating_system()[0])
        return 0
    data = snapshot()
    if command == 'json':
        print(json.dumps(data))
    elif command == 'os':
        print(data['os'])
    elif command == 'rows':
        for row in data['requirements']:
            print('\t'.join((row['key'], row['label'], 'ready' if row['ready'] else 'missing', row['detail'])))
    elif command == 'check':
        return 0 if all(row['ready'] for row in data['requirements']) else 1
    else:
        return 2
    return 0


if __name__ == '__main__':
    sys.exit(main())
