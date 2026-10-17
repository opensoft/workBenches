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
    library = Path(__file__).resolve().parent / 'lib/tools-container.sh'
    result = subprocess.run(['bash', '-c', 'source "$1"; workbenches_requirement_rows', 'requirements', str(library)],
                            capture_output=True, text=True, timeout=90, check=True)
    rows = []
    for line in result.stdout.splitlines():
        key, label, state, detail = line.split('\t', 3)
        rows.append({'key': key, 'label': label, 'state': state, 'ready': state == 'up',
                     'required': key != 'vault', 'detail': detail})
    return {'os': os.environ.get('WORKBENCHES_HOST_OS_LABEL') or operating_system()[0], 'requirements': rows}


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else 'json'
    if command == 'os':
        print(os.environ.get('WORKBENCHES_HOST_OS_LABEL') or operating_system()[0])
        return 0
    data = snapshot()
    if command == 'json':
        print(json.dumps(data))
    elif command == 'os':
        print(data['os'])
    elif command == 'rows':
        for row in data['requirements']:
            print('\t'.join((row['key'], row['label'], row['state'], row['detail'])))
    elif command == 'check':
        return 0 if all(row['ready'] for row in data['requirements'] if row['required']) else 1
    else:
        return 2
    return 0


if __name__ == '__main__':
    sys.exit(main())
