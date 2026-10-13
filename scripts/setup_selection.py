"""Validate and describe a private setup selection before applying it."""
import json
import os
from pathlib import Path
import sys

REPO = Path(__file__).resolve().parents[1]
TOOLS = {'claude_cli', 'copilot_cli', 'codex_cli', 'antigravity_cli', 'opencode_cli',
         'pi_cli', 'spec_kit', 'openspec', 'vscode', 'warp', 'wave', 'amnezia_vpn', '0dcloud_vpn',
         'host_shell', 'workspace_repo', 'ai_accounts'}
AI = {'claude_cli': 'claude', 'codex_cli': 'openai', 'pi_cli': 'pi', 'opencode_cli': 'omniroute',
      'copilot_cli': 'copilot', 'antigravity_cli': 'antigravity'}
NODE = {'codex_cli', 'copilot_cli', 'pi_cli', 'openspec'}


def load(path):
    path = Path(path)
    info = path.lstat()
    if path.is_symlink() or not path.is_file() or info.st_uid != os.getuid() or info.st_mode & 0o077 or info.st_size > 65536:
        raise ValueError('selection must be a private regular file')
    data = json.loads(path.read_text())
    benches = json.loads((REPO / 'config/bench-config.json').read_text())['benches']
    known = TOOLS | {'bench_' + name for name in benches}
    if not isinstance(data, dict) or data.get('schemaVersion') != 1 or not isinstance(data.get('components'), list):
        raise ValueError('invalid selection')
    seen = set()
    for entry in data['components']:
        if not isinstance(entry, dict) or entry.get('key') not in known or entry.get('action') not in ('install', 'update', 'uninstall') or entry['key'] in seen:
            raise ValueError('invalid or duplicate component')
        if entry['key'] in ('host_shell', 'workspace_repo', 'ai_accounts') and entry['action'] != 'install':
            raise ValueError('optional setup entries only support configuration')
        seen.add(entry['key'])
    return data['components'], benches


def main():
    entries, benches = load(sys.argv[2])
    command = sys.argv[1]
    keys = {entry['key'] for entry in entries if entry['action'] in ('install', 'update')}
    if command == 'rows':
        for entry in entries:
            print(entry['key'] + '\t' + entry['action'])
    elif command == 'providers':
        print(','.join(sorted({AI[key] for key in keys if key in AI})))
    elif command == 'node':
        return 0 if keys & NODE else 1
    elif command == 'docker':
        return 0 if keys or any(entry['key'].startswith('bench_') for entry in entries) else 1
    elif command == 'benches':
        for key in sorted(keys):
            if key.startswith('bench_'):
                path = benches[key[6:]].get('path', '')
                if not path.startswith(('devBenches/', 'sysBenches/', 'bioBenches/')) or '..' in Path(path).parts:
                    raise ValueError('invalid bench path')
                print(path)
    elif command == 'empty':
        return 0 if not entries else 1
    elif command == 'selected':
        return 0 if sys.argv[3] in keys else 1
    elif command == 'review':
        labels = {'host_shell': 'Shell setup', 'workspace_repo': 'Org workspace',
                  'ai_accounts': 'AI accounts', 'codex_cli': 'Codex', 'claude_cli': 'Claude',
                  'copilot_cli': 'Copilot', 'pi_cli': 'Pi', 'opencode_cli': 'OpenCode'}
        for action, title in (('install', 'Installing'), ('update', 'Updating'), ('uninstall', 'Removing')):
            names = [labels.get(entry['key'], entry['key'].removeprefix('bench_'))
                     for entry in entries if entry['action'] == action]
            if names:
                print(title + ': ' + ', '.join(names))
    else:
        raise ValueError('unknown selection command')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, TypeError):
        print('Invalid setup selection; return to component selection.', file=sys.stderr)
        sys.exit(2)
