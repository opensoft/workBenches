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

mkdir -p \
    "$temporary_home/bin" \
    "$temporary_home/.qwen" \
    "$temporary_home/kimi-profile" \
    "$temporary_home/minimax-data" \
    "$temporary_home/dsh-profile"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$temporary_home/bin/qwen"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$temporary_home/bin/kimi"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$temporary_home/bin/mcode"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$temporary_home/bin/dsh"
chmod +x "$temporary_home/bin/qwen"
chmod +x "$temporary_home/bin/kimi"
chmod +x "$temporary_home/bin/mcode"
chmod +x "$temporary_home/bin/dsh"
PATH="$temporary_home/bin:$PATH"
KIMI_CODE_HOME="$temporary_home/kimi-profile"
DSH_HOME="$temporary_home/dsh-profile"
MINIMAX_DATA_DIR="$temporary_home/minimax-data"
export PATH KIMI_CODE_HOME DSH_HOME MINIMAX_DATA_DIR

# Installation creates these profile roots before credentials exist.
printf '%s\n' '{"security":{"auth":{"selectedType":"openai"}}}' \
    >"$temporary_home/.qwen/settings.json"
printf '%s\n' '[providers."managed:kimi-code"]' 'api_key = ""' \
    >"$KIMI_CODE_HOME/config.toml"
printf '%s\n' 'version: 1' 'refs: {}' >"$DSH_HOME/.credentials.yaml"
[[ "$(check_qwen_status)" == "$CLI_INSTALLED_NOT_AUTH" ]]
[[ "$(check_kimi_status)" == "$CLI_INSTALLED_NOT_AUTH" ]]
[[ "$(check_deepseek_status)" == "$CLI_INSTALLED_NOT_AUTH" ]]
[[ "$(check_minimax_status)" == "$CLI_INSTALLED_NOT_AUTH" ]]

mkdir -p "$KIMI_CODE_HOME/credentials"
printf '%s\n' '{"accessToken":"fixture-token"}' \
    >"$KIMI_CODE_HOME/credentials/managed:kimi-code.json"
[[ "$(check_kimi_status)" == "$CLI_AUTHENTICATED" ]]
: >"$KIMI_CODE_HOME/credentials/managed:kimi-code.json"

printf '%s\n' \
    '{"modelProviders":{"anthropic":[{"envKey":"OTHER_PROVIDER_KEY"}]},"env":{"OTHER_PROVIDER_KEY":"fixture-key"},"security":{"auth":{"selectedType":"openai"}}}' \
    >"$temporary_home/.qwen/settings.json"
[[ "$(check_qwen_status)" == "$CLI_INSTALLED_NOT_AUTH" ]]

printf '%s\n' \
    '{"modelProviders":{"vertex-ai":[{"id":"fixture-model"}]},"security":{"auth":{"selectedType":"vertex-ai"}}}' \
    >"$temporary_home/.qwen/settings.json"
[[ "$(GOOGLE_CLOUD_PROJECT=fixture-project check_qwen_status)" == "$CLI_INSTALLED_NOT_AUTH" ]]

printf '%s\n' \
    '{"modelProviders":{"openai":[{"envKey":"QWEN_TEST_API_KEY"}]},"env":{"QWEN_TEST_API_KEY":"fixture-key"},"security":{"auth":{"selectedType":"openai"}}}' \
    >"$temporary_home/.qwen/settings.json"
printf '%s\n' '[providers."managed:kimi-code"]' 'api_key = "fixture-key"' \
    >"$KIMI_CODE_HOME/config.toml"
printf '%s\n' 'version: 1' 'refs:' '  DEEPSEEK_API_KEY: fixture-key' \
    >"$DSH_HOME/.credentials.yaml"
printf '%s\n' '{"version":1,"auth":{"accessToken":"fixture-token"}}' \
    >"$MINIMAX_DATA_DIR/local-runtime.auth.json"
[[ "$(check_qwen_status)" == "$CLI_AUTHENTICATED" ]]
[[ "$(check_kimi_status)" == "$CLI_AUTHENTICATED" ]]
[[ "$(check_deepseek_status)" == "$CLI_AUTHENTICATED" ]]
[[ "$(check_minimax_status)" == "$CLI_AUTHENTICATED" ]]

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
check_qwen_status() {
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
