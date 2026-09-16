#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

for installer in \
    "$repo_root/base-image/install-ai-clis.sh" \
    "$repo_root/devBenches/base-image/install-ai-clis.sh"; do
    bash -n "$installer"
    summary_block="$(sed -n '/^if command -v chelper /,/^fi$/p' "$installer")"
    grep -Fq 'command -v chelper' <<<"$summary_block"
    grep -Fq 'Z.AI Coding Plan helper (chelper)' <<<"$summary_block"
    grep -Fq '[install skipped or failed]' <<<"$summary_block"

    minimax_summary_block="$(sed -n '/^if command -v mcode /,/^fi$/p' "$installer")"
    grep -Fq 'command -v mcode' <<<"$minimax_summary_block"
    grep -Fq "\$HOME/.minimax-code/bin/mcode" <<<"$minimax_summary_block"
    grep -Fq 'MiniMax Code (mcode)' <<<"$minimax_summary_block"
    grep -Fq '[install skipped or failed]' <<<"$minimax_summary_block"
done

cursor_install_block="$(sed -n '/^log_info "Installing Cursor CLI..."/,/^log_info "Installing MiniMax Code CLI/p' "$repo_root/base-image/install-ai-clis.sh")"
grep -Fq 'publish_cursor_bundle "$cursor_launcher"' <<<"$cursor_install_block"
grep -Fq 'cursor-agent --version >/dev/null 2>&1' <<<"$cursor_install_block"
grep -Fq 'missing_clis+=("cursor-agent(runnable)")' "$repo_root/base-image/install-ai-clis.sh"

# shellcheck source=../base-image/ai-cli-install-helpers.sh
. "$repo_root/base-image/ai-cli-install-helpers.sh"

cursor_case_root="$(mktemp -d)"
trap 'rm -rf "$cursor_case_root"' EXIT

assert_cursor_publication_failure_preserves_source() {
    local failing_command="$1"
    local case_dir="$cursor_case_root/fail-$failing_command"
    local versions_root="$case_dir/local/share/cursor-agent/versions"
    local bin_dir="$case_dir/local/bin"
    local bundle_dir="$versions_root/test-version"
    local destination="$case_dir/opt/cursor-agent"
    local global_launcher="$case_dir/usr/local/bin/cursor-agent"
    local mock_bin="$case_dir/mock-bin"

    mkdir -p "$bundle_dir" "$bin_dir" "$destination" "$mock_bin"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$bundle_dir/agent"
    printf '%s\n' '#!/usr/bin/env sh' 'exit 0' > "$bundle_dir/node"
    : > "$bundle_dir/index.js"
    : > "$destination/original"
    chmod 0755 "$bundle_dir/agent" "$bundle_dir/node"
    ln -s "$bundle_dir/agent" "$bin_dir/agent"
    printf '%s\n' '#!/usr/bin/env sh' 'exit 42' > "$mock_bin/$failing_command"
    chmod 0755 "$mock_bin/$failing_command"

    if PATH="$mock_bin:$PATH" publish_cursor_bundle \
        "$bin_dir/agent" \
        "$destination" \
        "$global_launcher" \
        "$versions_root" \
        "$bin_dir"; then
        echo "Cursor publication unexpectedly ignored $failing_command failure" >&2
        exit 1
    fi
    test -e "$bundle_dir/agent"
    test -L "$bin_dir/agent"
    test -f "$destination/original"
    test ! -e "$global_launcher"
}

assert_cursor_publication_failure_preserves_source cp
assert_cursor_publication_failure_preserves_source chmod

cursor_versions_root="$cursor_case_root/local/share/cursor-agent/versions"
cursor_bin_dir="$cursor_case_root/local/bin"
cursor_bundle_dir="$cursor_versions_root/agent-only"
cursor_destination="$cursor_case_root/opt/cursor-agent"
cursor_global_launcher="$cursor_case_root/usr/local/bin/cursor-agent"
mkdir -p "$cursor_bundle_dir" "$cursor_bin_dir"
printf '%s\n' '#!/usr/bin/env bash' \
    'script_path="$(readlink -f -- "${BASH_SOURCE[0]}")"' \
    'script_dir="$(cd -- "$(dirname -- "$script_path")" && pwd)"' \
    'test -x "$script_dir/node"' \
    'test -f "$script_dir/index.js"' \
    'printf "%s\n" "cursor-agent-test"' > "$cursor_bundle_dir/agent"
printf '%s\n' '#!/usr/bin/env sh' 'exit 0' > "$cursor_bundle_dir/node"
: > "$cursor_bundle_dir/index.js"
chmod 0755 "$cursor_bundle_dir/agent" "$cursor_bundle_dir/node"
ln -s "$cursor_bundle_dir/agent" "$cursor_bin_dir/agent"

publish_cursor_bundle \
    "$cursor_bin_dir/agent" \
    "$cursor_destination" \
    "$cursor_global_launcher" \
    "$cursor_versions_root" \
    "$cursor_bin_dir"

test "$(readlink "$cursor_global_launcher")" = "$cursor_destination/cursor-agent"
test ! -e "$cursor_bundle_dir"
test ! -e "$cursor_bin_dir/agent"
test -x "$cursor_destination/node"
test -f "$cursor_destination/index.js"
test "$($cursor_global_launcher --version)" = "cursor-agent-test"

printf 'ai-cli optional install summaries are status-aware\n'
