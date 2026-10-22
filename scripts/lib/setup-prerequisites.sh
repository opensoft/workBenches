#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/docker-prerequisite.sh"
source "$(dirname "${BASH_SOURCE[0]}")/setup-prompts.sh"
source "$(dirname "${BASH_SOURCE[0]}")/tools-container.sh"
source "$(dirname "${BASH_SOURCE[0]}")/setup-workstation-lifecycle.sh"

# setup.sh runs in Linux/WSL or macOS. Git Bash cannot host Linux benches.
ensure_setup_platform() {
    local choice
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*)
            echo 'workBenches Setup — Windows'
            echo 'Requirements: WSL 2 running, Docker with Linux containers.'
            echo 'Open your WSL 2 distribution and run ./setup.sh there.'
            echo 'If WSL is missing, install it from an Administrator PowerShell:'
            echo '  wsl --install -d Ubuntu'
            echo 'Restart Windows if requested; launch Ubuntu and create your Linux user.'
            if [[ -t 0 ]] && command -v powershell.exe >/dev/null 2>&1; then
                setup_read 'Install WSL/Ubuntu now? [y/N] (Q cancels)' choice
                case "$choice" in
                    y|Y|yes|YES) powershell.exe -NoProfile -Command "\$p = Start-Process wsl.exe -ArgumentList '--install','-d','Ubuntu','--no-launch' -Verb RunAs -Wait -PassThru; exit \$p.ExitCode" || return "$?" ;;
                    *) return 130 ;;
                esac
            fi
            return 1 ;;
    esac
}

show_setup_requirements() {
    local key label state detail action
    echo "workBenches Setup — $(workbenches_setup_os)"
    echo 'Requirements'
    while IFS=$'\t' read -r key label state detail; do
        [[ "$key" != vault ]] || continue
        action="$(workbenches_requirement_action "$key" "$state")"
        printf '  %-20s %-7s [%s] — %s\n' "$label (required)" "${state^}" "$action" "$detail"
    done < <(workbenches_requirement_rows)
    echo '  Vault                optional — credential access, sign in when needed'
}

ensure_workstation_requirements() {
    local choice state action missing_wsl=false
    # Docker and WSL are checked with Bash before any container tool is needed.
    while true; do
        missing_wsl=false
        if [[ "$(workbenches_setup_os)" == Windows* && "$(workbenches_wsl_state)" != up ]]; then missing_wsl=true; fi
        state="$(workbenches_docker_state)"
        if [[ "$missing_wsl" == false && "$state" == up ]]; then
            workbenches_tools_activate
            return "$?"
        fi
        show_setup_requirements
        [[ -t 0 ]] || { echo 'Resolve missing requirements in an interactive terminal, then rerun ./setup.sh.'; return 1; }
        action="$(workbenches_requirement_action docker "$state") Docker"
        [[ "$missing_wsl" != true ]] || action='Configure WSL 2'
        setup_read "Enter: $action   R: recheck   Q: quit" choice
        case "$choice" in q|Q) return 130 ;; r|R) continue ;; '') ;; *) continue ;; esac
        if [[ "$missing_wsl" == true ]]; then
            echo 'WSL 2 is required. From Windows PowerShell, run:'
            printf '  wsl --set-version "%s" 2\n' "${WSL_DISTRO_NAME:-Ubuntu}"
            echo 'Reopen the distribution and rerun ./setup.sh.'
            return 1
        fi
        action="$(workbenches_requirement_action docker "$state")"
        if ensure_docker "--${action,,}"; then :; else
            local requirement_status=$?
            case "$requirement_status" in 130|143) return "$requirement_status" ;; esac
            echo 'Resolve the Docker issue above, then press R to recheck (Q quits).'
        fi
    done
}

ensure_setup_dependencies() {
    workbenches_tools_activate
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
