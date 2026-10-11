#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT
fixture="$test_root/workBenches"
mkdir -p "$fixture/scripts/lib" "$fixture/config" "$fixture/devBenches/testBench" \
    "$fixture/sysBenches/testBench" "$test_root/bin" "$test_root/home/.config/workbenches"
cp "$repo_root/setup.sh" "$fixture/"
cp "$repo_root/bootstrap.sh" "$fixture/"
cp "$repo_root/scripts/interactive-setup.sh" "$fixture/scripts/interactive-setup-real.sh"
cp "$repo_root/scripts/lib/image-names.sh" "$fixture/scripts/lib/"
printf '{}' > "$test_root/home/.config/workbenches/test-profiles.json"
printf '%s\n' '{"benches":{"dev":{"path":"devBenches/testBench"},"sys":{"path":"sysBenches/testBench"}}}' > "$fixture/config/bench-config.json"

# Run the actual input handler and main loop, with setup operations isolated.
cat > "$fixture/scripts/interactive-setup.sh" <<'EOF'
#!/usr/bin/env bash
source "$(dirname "$0")/interactive-setup-real.sh"
check_and_install_dependencies() { :; }
init_components() { :; }
load_statuses() { :; }
draw_ui() { :; }
get_checked_state() { :; }
process_selections() { echo apply >> "$TEST_ACTION_LOG"; }
clear() { :; }
if [[ -n "${TEST_UI_EXIT:-}" ]]; then exit "$TEST_UI_EXIT"; fi
main
EOF
for category in devBenches sysBenches; do
    cat > "$fixture/$category/setup.sh" <<'EOF'
#!/usr/bin/env bash
echo build >> "$TEST_ACTION_LOG"
EOF
done
printf '#!/usr/bin/env bash\nexit 0\n' > "$test_root/bin/docker"
printf '#!/usr/bin/env bash\nexit 0\n' > "$test_root/bin/python3"
printf '#!/usr/bin/env bash\nexit "${TEST_AI_SETUP_EXIT:-0}"\n' > "$fixture/scripts/setup-ai-profiles.sh"
chmod +x "$fixture/scripts/interactive-setup.sh" "$fixture/scripts/setup-ai-profiles.sh" \
    "$fixture/devBenches/setup.sh" "$fixture/sysBenches/setup.sh" "$test_root/bin/"*

run_case() {
    local label="$1" input="$2" expected_status="$3" expected_actions="$4" ui_exit="${5:-}" ai_exit="${6:-0}"
    local actual_status=0 actual_actions
    : > "$test_root/actions"
    printf '%s' "$input" | env HOME="$test_root/home" XDG_CONFIG_HOME="$test_root/home/.config" \
        AGENT_PROTOCOL_ROOT="$test_root/home/.agents" PATH="$test_root/bin:$PATH" \
        WORKBENCHES_SKIP_WAVE_WIDGETS=1 TEST_ACTION_LOG="$test_root/actions" TEST_UI_EXIT="$ui_exit" TEST_AI_SETUP_EXIT="$ai_exit" \
        bash "$fixture/setup.sh" tester > "$test_root/output" 2>&1 || actual_status=$?
    actual_actions="$(cat "$test_root/actions")"
    if [[ "$actual_status" != "$expected_status" || "$actual_actions" != "$expected_actions" ]]; then
        printf 'FAIL: %s: status %s (expected %s), actions [%s] (expected [%s])\n' \
            "$label" "$actual_status" "$expected_status" "$actual_actions" "$expected_actions" >&2
        cat "$test_root/output" >&2
        exit 1
    fi
    printf 'PASS: %s\n' "$label"
}

run_case 'uppercase Q cancels without applying or building' Q 130 ''
run_case 'lowercase q cancels without applying or building' q 130 ''
run_case 'closed input cancels without applying or building' '' 130 ''
run_case 'UI failure stops setup' '' 7 '' 7
run_case 'terminated UI stops setup' '' 143 '' 143
run_case 'cancelled credential recovery stops the entire setup' '' 130 '' '' 130
run_case 'Enter still applies selections and builds' $'\n' 0 $'apply\nbuild\nbuild'
