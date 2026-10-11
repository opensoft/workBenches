#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/docker-prerequisite.sh"
source "$(dirname "${BASH_SOURCE[0]}")/setup-prompts.sh"

ensure_setup_dependencies() {
    local dependency choice status
    local -a missing=()
    for dependency in python3 jq git curl; do
        command -v "$dependency" >/dev/null 2>&1 || missing+=("$dependency")
    done
    [[ ${#missing[@]} -gt 0 ]] || return 0
    echo "Missing setup dependencies: ${missing[*]}"
    [[ -t 0 ]] || return 1
    setup_read 'Install these dependencies now? [y/N]' choice
    [[ "${choice,,}" == y || "${choice,,}" == yes ]] || return 130
    case "$(workbenches_docker_os)" in
        arch|endeavouros|manjaro|omarchy) sudo pacman -S --needed "${missing[@]/python3/python}" ;;
        ubuntu|debian|pop) sudo apt update && sudo apt install -y "${missing[@]}" ;;
        fedora|rhel|centos) sudo dnf install -y "${missing[@]}" ;;
        alpine) sudo apk add "${missing[@]}" ;;
        Darwin|darwin|macos) brew install "${missing[@]/python3/python}" ;;
        *) echo "Install ${missing[*]} with your OS package manager, then rerun setup."; return 1 ;;
    esac
    status=$?
    setup_propagate_cancel "$status"
    [[ "$status" == 0 ]] || return "$status"
    for dependency in "${missing[@]}"; do command -v "$dependency" >/dev/null 2>&1 || return 1; done
}

# Preserve writable Node-manager prefixes. System-owned prefixes fall back to
# the user's standard executable directory, without sudo or ownership changes.
ensure_npm_install_location() {
    local prefix
    prefix="$(npm config get prefix 2>/dev/null)" || return 1
    if ! python3 - "$prefix" <<'WRITABLE'
import os, pathlib, sys, tempfile
root = pathlib.Path(sys.argv[1])
try:
    if not root.is_absolute():
        raise OSError('invalid npm prefix')
    for path in (root, root / 'bin', root / 'lib', root / 'lib/node_modules'):
        while not path.exists():
            path = path.parent
        with tempfile.TemporaryFile(dir=path):
            pass
except OSError:
    sys.exit(1)
WRITABLE
    then
        prefix="$HOME/.local"
        mkdir -p "$prefix/bin" "$prefix/lib/node_modules" || return 1
        unset NPM_CONFIG_PREFIX
        export npm_config_prefix="$prefix"
        npm config set prefix "$prefix" --location=user >/dev/null || return 1
        export WORKBENCHES_NPM_PREFIX_CHANGED=1
        echo "npm's global location is not writable. Using $prefix for your CLI tools."
    fi
    export PATH="$prefix/bin:$PATH"
}

persist_npm_user_path() {
    [[ "${WORKBENCHES_NPM_PREFIX_CHANGED:-}" == 1 ]] || return 0
    python3 - <<'SHELLPATH'
import os
from pathlib import Path
marker = '# workBenches user npm executables'
block = '\n' + marker + '\ncase "$PATH" in "$HOME/.local/bin"|"$HOME/.local/bin":*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac\n'
for name in ('.profile', '.bashrc', '.zshrc'):
    path = Path.home() / name
    try:
        fd = os.open(path, os.O_RDWR | os.O_APPEND | os.O_CREAT | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, 'r+') as stream:
            if marker not in stream.read():
                stream.write(block)
    except OSError:
        print(f'Add $HOME/.local/bin to PATH in {path} to use your npm tools in new terminals.')
SHELLPATH
}
