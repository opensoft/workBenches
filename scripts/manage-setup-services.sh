#!/usr/bin/env bash
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib/tools-container.sh"
case "${1:-}:${2:-}" in
    status:docker) workbenches_docker_state ;;
    status:tools) workbenches_tools_state ;;
    status:vault) workbenches_vault_state ;;
    start:tools) workbenches_tools_start ;;
    start:vault) workbenches_vault_start ;;
    *) echo 'Usage: manage-setup-services.sh status docker|tools|vault | start tools|vault' >&2; exit 2 ;;
esac
