#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
launcher="${LAUNCHER_UNDER_TEST:-$repo_root/scripts/wave-container-shell.sh}"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

run_launcher_case() {
    local case_name="$1"
    local running="$2"
    local mounts="$3"
    shift 3

    local case_root
    case_root="$(mktemp -d)"
    local fake_home="$case_root/home"
    local fake_root="$case_root/workBenches"
    local mock_bin="$case_root/bin"
    local docker_log="$case_root/docker.log"
    mkdir -p "$fake_home" "$fake_root/devBenches/pyBench/.devcontainer" "$mock_bin"
    : > "$fake_root/devBenches/pyBench/.devcontainer/devcontainer.json"
    : > "$fake_root/devBenches/pyBench/.devcontainer/docker-compose.yml"

    cat > "$mock_bin/docker" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$MOCK_DOCKER_LOG"

if [[ "${1:-}" == "container" && "${2:-}" == "inspect" ]]; then
    if [[ "${3:-}" == "-f" ]]; then
        case "${4:-}" in
            *State.Running*) printf '%s\n' "$MOCK_RUNNING" ;;
            *Mounts*)
                if [[ "$MOCK_MOUNTS" == "complete" ]]; then
                    cat <<'MOUNTS'
/workspace/projects
/home/tester/.workbenches-history
/home/tester/.zshrc
/home/tester/.oh-my-zsh
/home/tester/.p10k.zsh
/home/tester/.claude-profiles
/home/tester/.chatgpt-profiles
/home/tester/.pi-profiles
/home/tester/.gemini-profiles
/home/tester/.grok-profiles
/home/tester/.glm-profiles
MOUNTS
                else
                    printf '%s\n' /workspace/projects
                fi
                ;;
        esac
    fi
    exit 0
fi

exit 0
MOCK
    chmod +x "$mock_bin/docker"

    local output
    if ! output="$(
        env \
            HOME="$fake_home" \
            USER=tester \
            PATH="$mock_bin:$PATH" \
            MOCK_DOCKER_LOG="$docker_log" \
            MOCK_RUNNING="$running" \
            MOCK_MOUNTS="$mounts" \
            "$launcher" \
                --workbenches-root "$fake_root" \
                --shell sh \
                --check \
                "$@" \
                py-bench 2>&1
    )"; then
        echo "$output" >&2
        rm -rf "$case_root"
        fail "$case_name launcher invocation failed"
    fi

    CASE_OUTPUT="$output"
    CASE_DOCKER_LOG="$(cat "$docker_log")"
    rm -rf "$case_root"
}

bash -n "$launcher"
"$launcher" --help | grep -q -- '--repair' || fail "help does not document --repair"

run_launcher_case preserve-running true missing
grep -q 'preserving the live container' <<<"$CASE_OUTPUT" || fail "running container was not preserved with a warning"
if grep -q '^rm -f py-bench$' <<<"$CASE_DOCKER_LOG"; then
    fail "normal launch removed a running container"
fi
if grep -q '^compose ' <<<"$CASE_DOCKER_LOG"; then
    fail "normal launch recreated a running container"
fi

run_launcher_case explicit-repair true complete --repair
grep -q '^rm -f py-bench$' <<<"$CASE_DOCKER_LOG" || fail "--repair did not remove the existing container"
grep -q '^compose ' <<<"$CASE_DOCKER_LOG" || fail "--repair did not recreate the container"

run_launcher_case stopped-auto-repair false missing
grep -q '^rm -f py-bench$' <<<"$CASE_DOCKER_LOG" || fail "stopped container with missing mounts was not removed"
grep -q '^compose ' <<<"$CASE_DOCKER_LOG" || fail "stopped container with missing mounts was not recreated"

echo "PASS: wave container launcher lifecycle tests"
