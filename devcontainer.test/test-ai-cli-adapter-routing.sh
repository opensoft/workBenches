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

mkdir -p "$temporary_home/bin" "$temporary_home/kimi-profile"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$temporary_home/bin/kimi"
chmod +x "$temporary_home/bin/kimi"
PATH="$temporary_home/bin:$PATH"
KIMI_CODE_HOME="$temporary_home/kimi-profile"
DSH_HOME="$temporary_home/dsh-profile"
mkdir -p "$DSH_HOME"
export PATH KIMI_CODE_HOME DSH_HOME
[[ "$(check_generic_cli_status "kimi-code" "kimi" "$KIMI_CODE_HOME")" == "$CLI_AUTHENTICATED" ]]

generic_calls="$temporary_home/generic-calls"
check_generic_cli_status() {
    printf '%s|%s|%s\n' "$1" "$2" "${3-}" >>"$generic_calls"
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
grep -qx "dsh|dsh|$DSH_HOME" "$generic_calls"
grep -qx "kimi-code|kimi|$KIMI_CODE_HOME" "$generic_calls"

saved_priority=("${PROVIDER_PRIORITY[@]}")
PROVIDER_PRIORITY=("" antigravity qwen)
[[ "$(get_authenticated_cli)" == qwen ]]
if get_unauthenticated_clis >/dev/null 2>&1; then
    echo "unexpected unauthenticated provider from unknown-entry fixture" >&2
    exit 1
fi
PROVIDER_PRIORITY=("${saved_priority[@]}")

PROVIDER_PRIORITY=(qwen)
ROUTING_PROVIDER_PRIORITY=(codex)
check_generic_cli_status() {
    printf '%s\n' "$CLI_INSTALLED_NOT_AUTH"
}
check_codex_status() {
    printf '%s\n' "$CLI_NOT_INSTALLED"
}
[[ "$(get_unauthenticated_clis)" == qwen ]]
if get_unauthenticated_routing_clis >/dev/null 2>&1; then
    echo "direct-only provider unexpectedly entered the routing login prompt" >&2
    exit 1
fi

get_unauthenticated_clis() {
    printf '%s\n' codex
}
get_unauthenticated_routing_clis() {
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
