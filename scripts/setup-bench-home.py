#!/usr/bin/env python3
"""Prepare shared bench bind sources as the host user before Docker creates them.

The settings file .claude.json is distinct from .claude/.credentials.json.
Existing settings and credential files are never opened or replaced.
"""
import os
from pathlib import Path
import sys

DIRECTORIES = (
    'projects', '.ssh', '.azure', '.aws', '.kube', '.config/gh', '.claude',
    '.claude-profiles', '.codex', '.chatgpt-profiles', '.opencode-profiles',
    '.gemini-profiles', '.grok-profiles', '.glm-profiles', '.omnigent', '.agents',
    '.pi', '.pi-profiles', '.config/workbenches', '.local/lib/workbenches',
    '.local/state/workbenches', '.config/sonarqube', '.gemini', '.grok',
    '.copilot-cli', '.notebooklm', '.notebooklm-mcp-cli',
    '.local/state/opensoft/agenttower/logs',
)
SETTINGS = {'.zshrc': b'', '.p10k.zsh': b'', '.bashrc': b'', '.gitconfig': b'', '.claude.json': b'{}\n'}


def prepare(home):
    os.umask(0o077)
    # Validate the complete set before creating anything. Follow an existing
    # user-selected link only to check its type; never write through it.
    for name in DIRECTORIES:
        path = home / name
        if (path.exists() or path.is_symlink()) and not path.is_dir():
            raise ValueError(f'Expected a directory at {path}; restore the bind source before installing a bench.')
    for name in SETTINGS:
        path = home / name
        if (path.exists() or path.is_symlink()) and not path.is_file():
            raise ValueError(f'Expected a settings file at {path}; restore the bind source before installing a bench.')
    for name in DIRECTORIES:
        (home / name).mkdir(mode=0o700, parents=True, exist_ok=True)
    for name, initial in SETTINGS.items():
        path = home / name
        try:
            descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        except FileExistsError:
            continue
        with os.fdopen(descriptor, 'wb') as stream:
            stream.write(initial)
    print('Bench folders and settings are ready.')


if __name__ == '__main__':
    try:
        prepare(Path.home())
    except (OSError, ValueError) as error:
        print(f'Bench home preparation failed: {error}', file=sys.stderr)
        sys.exit(1)
