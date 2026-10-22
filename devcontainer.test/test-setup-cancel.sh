#!/usr/bin/env bash
set -euo pipefail
export WORKBENCHES_TEST_NATIVE_TOOLS=1

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT
fixture="$test_root/workBenches"
mkdir -p "$fixture/scripts/lib" "$fixture/config" "$fixture/devBenches/testBench" \
    "$fixture/sysBenches/testBench" "$test_root/bin" "$test_root/home/.config/workbenches"
cp "$repo_root/setup.sh" "$fixture/"
cp "$repo_root/bootstrap.sh" "$fixture/"
cp "$repo_root/scripts/lib/"{docker-prerequisite.sh,tools-container.sh,setup-status-loader.sh,setup-prerequisites.sh,setup-workstation-lifecycle.sh,setup-prompts.sh} "$fixture/scripts/lib/"
cp "$repo_root/scripts/setup_selection.py" "$fixture/scripts/"
cp "$repo_root/scripts/setup-bench-home.py" "$fixture/scripts/"
cp "$repo_root/scripts/shared-images.py" "$fixture/scripts/"
export WORKBENCHES_BUILD_LOCAL=1
cp "$repo_root/scripts/interactive-setup.sh" "$fixture/scripts/interactive-setup-real.sh"
cp "$repo_root/scripts/lib/image-names.sh" "$fixture/scripts/lib/"
printf '{"profiles":[{}]}' > "$test_root/home/.config/workbenches/openai-profiles.json"
printf '%s\n' '{"benches":{"dev":{"path":"devBenches/testBench"},"sys":{"path":"sysBenches/testBench"}}}' > "$fixture/config/bench-config.json"

# Run the actual input handler and main loop, with setup operations isolated.
cat > "$fixture/scripts/interactive-setup.sh" <<'EOF'
#!/usr/bin/env bash
source "$(dirname "$0")/interactive-setup-real.sh"
check_and_install_dependencies() { :; }
init_components() {
  if [[ "${TEST_EMPTY_SELECTION:-}" != 1 ]]; then
    component_checked[bench_dev]=true
    component_checked[bench_sys]=true
    component_checked[codex_cli]=true
    component_action[bench_dev]=install
    component_action[bench_sys]=install
    component_action[codex_cli]=install
  fi
}
load_statuses() { :; }
draw_ui() { :; }
get_checked_state() { :; }
ensure_selected_dependencies() { :; }
process_selections() { echo apply >> "$TEST_ACTION_LOG"; return "${TEST_APPLY_EXIT:-0}"; }
clear() { :; }
if [[ -n "${TEST_UI_EXIT:-}" ]]; then exit "$TEST_UI_EXIT"; fi
main "$@"
EOF
for category in devBenches sysBenches; do
    cat > "$fixture/$category/setup.sh" <<'EOF'
#!/usr/bin/env bash
echo build >> "$TEST_ACTION_LOG"
EOF
done
printf '#!/usr/bin/env bash\n[[ "$1" != info ]] || echo linux\nexit 0\n' > "$test_root/bin/docker"
printf '#!/usr/bin/env bash\nif [[ "$*" == "config get prefix" ]]; then echo "$HOME/.local"; fi\n' > "$test_root/bin/npm"
export TEST_REAL_PYTHON="$(command -v python3)"
cat > "$test_root/bin/python3" <<'PYTHON'
#!/usr/bin/env bash
case "$1" in
  */setup_selection.py|-|-c) exec "$TEST_REAL_PYTHON" "$@" ;;
  *) exit 0 ;;
esac
PYTHON
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
run_case 'cancelled credential recovery stops the entire setup' $'\e[C\n\n' 130 '' '' 130
run_case 'Enter builds required families before applying selections' $'\e[C\n\n' 0 $'build\nbuild\napply'

TEST_EMPTY_SELECTION=1 run_case 'empty Enter exits without applying or building' $'\e[C\n\n' 0 ''

TEST_APPLY_EXIT=9 run_case 'failed selected install preserves its error after base builds' $'\e[C\n\n' 9 $'build\nbuild\napply'
