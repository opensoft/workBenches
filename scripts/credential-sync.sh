#!/usr/bin/env bash
# Run through declared Tools on minimal hosts. No global Python installation.
set -euo pipefail
self="$(readlink -f "${BASH_SOURCE[0]}")"
root="$(cd "$(dirname "$self")/.." && pwd)"
source "$root/scripts/lib/openbenches-compat.sh"
if [[ "${1:-}" == --start || "${1:-}" == --install ]]; then
    state="$(openbenches_config_root)"
    mkdir -p "$state" "$HOME/.local/bin"
    chmod 700 "$state"
    targets=("$HOME/.local/bin/workbenches-credential-sync" "$HOME/.local/bin/openbenches-credential-sync")
    for target in "${targets[@]}"; do
        if [[ -e "$target" || -L "$target" ]]; then
            [[ -L "$target" && "$(readlink -f "$target")" == "$self" ]] || { echo "Existing sync command was preserved; resolve its name collision first: $target" >&2; exit 1; }
        fi
    done
    for target in "${targets[@]}"; do
        openbenches_link_command "$self" "$target"
    done
    umask 077
    touch "$state/company-sync-enabled"
    [[ "$1" != --install ]] || exit 0
    unset WORKBENCHES_HOST_RPC OPENBENCHES_HOST_RPC WB_HOST_RPC
    nohup bash "$self" --watch </dev/null >>"$state/credential-sync-agent.log" 2>&1 &
    echo 'Company sync agent requested. View Profiles sync status to check readiness.'
    exit 0
fi
if [[ -f /.dockerenv ]] && command -v python3 >/dev/null 2>&1; then
    exec python3 "$root/scripts/credential-sync.py" "$@"
fi
source "$root/scripts/lib/setup-prerequisites.sh"
ensure_workstation_requirements
python3 "$root/scripts/credential-sync.py" "$@"
