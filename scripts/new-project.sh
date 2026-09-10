#!/usr/bin/env bash
# Compatibility entrypoint: generic creation now belongs to openRepoProject.
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$script_dir/project" new "$@"
