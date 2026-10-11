#!/usr/bin/env bash
set -euo pipefail
umask 077

# User-local fallback for machines without Docker; no system Python changes.
tool_dir="${XDG_DATA_HOME:-$HOME/.local/share}/workbenches/tools/azure-cli"
if [[ -x "$tool_dir/bin/az" ]]; then
    echo "Azure CLI is already installed at $tool_dir/bin/az"
    exit 0
fi
command -v python3 >/dev/null 2>&1 || {
    echo "Python 3.10+ with venv support is required. Alternatively, install Azure CLI using your platform's package manager." >&2
    exit 1
}
python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' || {
    echo 'Azure CLI requires Python 3.10 or newer.' >&2
    exit 1
}
mkdir -p "$(dirname "$tool_dir")"
[[ ! -L "$tool_dir" ]] || { echo 'Azure CLI tool directory must not be a symlink.' >&2; exit 1; }
python3 -m venv "$tool_dir"
"$tool_dir/bin/python" -m pip install --disable-pip-version-check 'azure-cli==2.91.0'
"$tool_dir/bin/az" version --output none
echo "Azure CLI installed at $tool_dir/bin/az"
