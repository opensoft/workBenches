#!/usr/bin/env bash
set -euo pipefail

# Count successful explicit assertions, including repeated fixture checks.
assertions=0
assertion() { assertions=$((assertions + 1)); }

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

for installer in \
    "$repo_root/base-image/install-ai-clis.sh" \
    "$repo_root/devBenches/base-image/install-ai-clis.sh"; do
    bash -n "$installer"
    assertion
    summary_block="$(sed -n '/^if command -v chelper /,/^fi$/p' "$installer")"
    grep -Fq 'command -v chelper' <<<"$summary_block"
    assertion
    grep -Fq 'Z.AI Coding Plan helper (chelper)' <<<"$summary_block"
    assertion
    grep -Fq '[install skipped or failed]' <<<"$summary_block"
    assertion

done

shared_installer="$repo_root/base-image/install-ai-clis.sh"
shared_minimax_summary="$(sed -n '/^if command -v mcode /,/^fi$/p' "$shared_installer" | tail -n 6)"
grep -Fq 'command -v mcode' <<<"$shared_minimax_summary"
assertion
grep -Fq 'command -v mcode-tools' <<<"$shared_minimax_summary"
assertion
grep -Fq 'MiniMax Code (mcode, mcode-tools)' <<<"$shared_minimax_summary"
assertion
grep -Fq '[install skipped or failed]' <<<"$shared_minimax_summary"
assertion
if grep -Fq '$HOME/.minimax-code/bin/mcode' <<<"$shared_minimax_summary"; then
    echo "shared installer summary still accepts the legacy user-local MiniMax path" >&2
    exit 1
fi
assertion

developer_installer="$repo_root/devBenches/base-image/install-ai-clis.sh"
developer_minimax_summary="$(sed -n '/^if command -v mcode /,/^fi$/p' "$developer_installer" | tail -n 5)"
grep -Fq 'command -v mcode' <<<"$developer_minimax_summary"
assertion
grep -Fq '$HOME/.minimax-code/bin/mcode' <<<"$developer_minimax_summary"
assertion
grep -Fq 'MiniMax Code (mcode)' <<<"$developer_minimax_summary"
assertion
grep -Fq '[install skipped or failed]' <<<"$developer_minimax_summary"
assertion

grep -Fq 'missing_clis+=("mcode-tools(runnable)")' "$shared_installer"
assertion
grep -Fq 'mcode-tools --version' "$shared_installer"
assertion

cursor_install_block="$(sed -n '/^log_info "Installing Cursor CLI..."/,/^log_info "Installing MiniMax Code CLI/p' "$repo_root/base-image/install-ai-clis.sh")"
grep -Fq 'publish_cursor_bundle "$cursor_launcher"' <<<"$cursor_install_block"
assertion
grep -Fq 'cursor-agent --version >/dev/null 2>&1' <<<"$cursor_install_block"
assertion
grep -Fq 'missing_clis+=("cursor-agent(runnable)")' "$repo_root/base-image/install-ai-clis.sh"
assertion

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
    assertion
    test -e "$bundle_dir/agent"
    assertion
    test -L "$bin_dir/agent"
    assertion
    test -f "$destination/original"
    assertion
    test ! -e "$global_launcher"
    assertion
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
assertion
test ! -e "$cursor_bundle_dir"
assertion
test ! -e "$cursor_bin_dir/agent"
assertion
test -x "$cursor_destination/node"
assertion
test -f "$cursor_destination/index.js"
assertion
test "$($cursor_global_launcher --version)" = "cursor-agent-test"
assertion

printf 'ai-cli optional install summaries are status-aware\n'
printf "COUNT: %s assertions passed\n" "$assertions"
