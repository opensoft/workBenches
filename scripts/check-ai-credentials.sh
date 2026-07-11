#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_repo="${AI_HARNESS_ACCOUNT_REPO:-${1:-}}"

if [[ -z "$source_repo" || "$source_repo" == -* ]]; then
  cat >&2 <<EOF
Usage: AI_HARNESS_ACCOUNT_REPO=/path/to/private/account-registry \\
  $0

This compatibility command now launches the local Multiple AI Harness Account
Manager. It no longer extracts browser sessions, previews key values, or writes
API keys into shell startup files.

See: $repo_dir/docs/ai-harness-account-management.md
EOF
  exit 2
fi

exec python3 "$repo_dir/apps/credential-manager/credential_manager.py" \
  --source-repo "$source_repo"
