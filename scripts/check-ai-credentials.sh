#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_repo="${AI_HARNESS_ACCOUNT_REPO:-${1:-${XDG_CONFIG_HOME:-$HOME/.config}/workbenches}}"

exec python3 "$repo_dir/apps/credential-manager/credential_manager.py" \
  --source-repo "$source_repo"
