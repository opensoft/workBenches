#!/usr/bin/env bash
# Runs in Tools under one native-host callback session; read-only inventory only.
source "$(dirname "${BASH_SOURCE[0]}")/interactive-setup.sh"
status_worker_dir=$1
[[ -d "$status_worker_dir" && ! -L "$status_worker_dir" ]] || exit 1
status_collect_inventory
