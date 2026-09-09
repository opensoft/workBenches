#!/usr/bin/env bash
set -euo pipefail

ADAPTER=${1:-"$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/devBenches/scripts/ai-cli-adapter.sh"}
temporary_home=$(mktemp -d)
trap 'rm -rf -- "$temporary_home"' EXIT

mkdir -p "$temporary_home/.config/workbenches"
printf '%s\n' qwen codex kimi2 minimax >"$temporary_home/.config/workbenches/ai-provider-priority.conf"

HOME=$temporary_home
unset _AI_CLI_ADAPTER_SOURCED
source "$ADAPTER"

[[ "${PROVIDER_PRIORITY[*]}" == "qwen codex kimi2 minimax" ]]
[[ "${ROUTING_PROVIDER_PRIORITY[*]}" == "codex" ]]

check_generic_cli_status() {
    printf '%s\n' "$CLI_AUTHENTICATED"
}
check_codex_status() {
    printf '%s\n' "$CLI_AUTHENTICATED"
}

[[ "$(get_authenticated_cli)" == "qwen" ]]
[[ "$(get_authenticated_routing_cli)" == "codex" ]]

inventory=$(get_all_cli_status)
grep -qx 'qwen=authenticated' <<<"$inventory"
grep -qx 'kimi2=authenticated' <<<"$inventory"
grep -qx 'minimax=authenticated' <<<"$inventory"

printf 'ai-cli adapter inventory and routing checks passed\n'
