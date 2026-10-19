#!/usr/bin/env bash
# Native launcher: use declared Tools when workstation Python is absent.
set -euo pipefail
self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
root="$(cd "$(dirname "$self")/.." && pwd)"
if [[ "${1:-}" == --start ]]; then
    state="${XDG_CONFIG_HOME:-$HOME/.config}/workbenches"
    [[ ! -L "$state" ]] || exit 1
    [[ ! -L "$state/device-agent.log" ]] || exit 1
    umask 077
    mkdir -p "$state"
    unset WORKBENCHES_HOST_RPC
    nohup bash "$self" --watch </dev/null >>"$state/device-agent.log" 2>&1 &
    exit 0
fi
if [[ -f /.dockerenv ]] && command -v python3 >/dev/null 2>&1; then
    exec python3 "$root/scripts/device-agent.py" "$@"
fi
source "$root/scripts/lib/setup-prerequisites.sh"
ensure_workstation_requirements
python3 "$root/scripts/device-agent.py" "$@"
