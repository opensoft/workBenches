#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_dir/scripts/lib/openbenches-compat.sh"
source_repo="${AI_HARNESS_ACCOUNT_REPO:-${1:-$(openbenches_config_root)}}"

exec python3 "$repo_dir/apps/credential-manager/credential_manager.py" \
  --source-repo "$source_repo"
