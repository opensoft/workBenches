#!/usr/bin/env bash
set -euo pipefail

ADAPTER=${1:-"$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/devBenches/scripts/ai-cli-adapter.sh"}
temporary_home=$(mktemp -d)
trap 'rm -rf -- "$temporary_home"' EXIT

mkdir -p "$temporary_home/.config/workbenches"
printf '%s\n' qwen codex kimi2 minimax deepseek >"$temporary_home/.config/workbenches/ai-provider-priority.conf"

HOME=$temporary_home
unset _AI_CLI_ADAPTER_SOURCED
source "$ADAPTER"

[[ "${PROVIDER_PRIORITY[*]}" == "qwen codex kimi2 minimax deepseek" ]]
[[ "${ROUTING_PROVIDER_PRIORITY[*]}" == "codex" ]]

generic_calls="$temporary_home/generic-calls"
check_generic_cli_status() {
    printf '%s|%s\n' "$1" "$2" >>"$generic_calls"
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
grep -qx 'deepseek=authenticated' <<<"$inventory"
grep -qx 'dsh|dsh' "$generic_calls"

get_unauthenticated_clis() {
    printf '%s\n' codex
}
get_authenticated_cli() {
    printf '%s\n' qwen
}
get_authenticated_routing_cli() {
    printf '%s\n' codex
}

authentication_output="$(prompt_cli_authentication <<< $'\n')"
[[ "$(tail -n 1 <<<"$authentication_output")" == codex ]]

printf 'ai-cli adapter inventory and routing checks passed\n'
