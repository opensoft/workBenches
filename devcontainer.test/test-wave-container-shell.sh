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
    local rm_refuse="$4"
    local after_refusal_running="$5"
    local bench="$6"
    shift 6

    local case_root
    case_root="$(mktemp -d)"
    local fake_home="$case_root/home"
    local fake_root="$case_root/workBenches"
    local mock_bin="$case_root/bin"
    local docker_log="$case_root/docker.log"
    local prepare_log="$case_root/prepare.log"
    local ensure_images_log="$case_root/ensure-images.log"
    local rocm_log="$case_root/rocm.log"
    local sonarqube_log="$case_root/sonarqube.log"
    local lifecycle_log="$case_root/lifecycle.log"
    local wslg_root="$case_root/no-wslg"
    local explicit_compose="$fake_root/custom-compose.yml"
    local expected_env_dir=""
    local expected_config_image
    case "$bench" in
        py-bench) expected_config_image="py-bench:tester" ;;
        dotNetBench) expected_config_image="dotnet-bench:tester" ;;
        rustBench) expected_config_image="rust-bench:tester" ;;
        custom-bench) expected_config_image="custom-bench:tester" ;;
        *) expected_config_image="${bench}:tester" ;;
    esac
    mkdir -p "$fake_home" "$fake_root/devBenches/pyBench/.devcontainer" "$fake_root/devBenches/pyBench/scripts" "$fake_root/devBenches/dotNetBench/.devcontainer" "$fake_root/devBenches/rustBench/.devcontainer" "$fake_root/customBench/.devcontainer" "$fake_root/devBenches/scripts" "$fake_root/scripts" "$mock_bin"
    : > "$fake_root/devBenches/pyBench/.devcontainer/devcontainer.json"
    : > "$fake_root/devBenches/pyBench/.devcontainer/docker-compose.yml"
    : > "$fake_root/devBenches/dotNetBench/.devcontainer/devcontainer.json"
    : > "$fake_root/devBenches/dotNetBench/.devcontainer/docker-compose.yml"
    : > "$fake_root/devBenches/rustBench/.devcontainer/devcontainer.json"
    : > "$fake_root/devBenches/rustBench/.devcontainer/docker-compose.yml"
    : > "$fake_root/devBenches/rustBench/.devcontainer/docker-compose.wslg.yml"
    : > "$fake_root/custom-compose.yml"
    : > "$fake_root/customBench/.devcontainer/docker-compose.yml"
    printf '%s\n' 'CUSTOM_BENCH_VALUE=present' > "$fake_root/customBench/.env"
    cat > "$fake_root/devBenches/pyBench/scripts/configure-amd-rocm-wsl.sh" <<'ROCM'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' configured > "$MOCK_ROCM_LOG"
printf '%s\n' rocm >> "$MOCK_LIFECYCLE_LOG"
: > "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.devcontainer" && pwd)/docker-compose.amd-rocm.generated.yml"
ROCM
    chmod +x "$fake_root/devBenches/pyBench/scripts/configure-amd-rocm-wsl.sh"
    cat > "$fake_root/devBenches/pyBench/scripts/ensure-images.sh" <<'IMAGES'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" > "$MOCK_ENSURE_IMAGES_LOG"
IMAGES
    chmod +x "$fake_root/devBenches/pyBench/scripts/ensure-images.sh"
    cat > "$fake_root/devBenches/scripts/ensure-sonarqube-mcp.sh" <<'SONARQUBE'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' configured > "$MOCK_SONARQUBE_LOG"
printf '%s\n' sonarqube >> "$MOCK_LIFECYCLE_LOG"
SONARQUBE
    chmod +x "$fake_root/devBenches/scripts/ensure-sonarqube-mcp.sh"
    if [[ "${CASE_GENERIC_COMPOSE:-false}" == true ]]; then
        explicit_compose="$fake_root/customBench/.devcontainer/docker-compose.yml"
        expected_env_dir="$fake_root/customBench/.devcontainer"
    fi
    if [[ "${CASE_WSLG_ENABLED:-false}" == true ]]; then
        wslg_root="$fake_root/wslg"
        mkdir -p "$wslg_root"
    fi

    cat > "$fake_root/scripts/prepare-bench-start.sh" <<'PREPARE'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$MOCK_PREPARE_LOG"
PREPARE
    chmod +x "$fake_root/scripts/prepare-bench-start.sh"

    cat > "$mock_bin/docker" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$MOCK_DOCKER_LOG"

if [[ "${1:-}" == "compose" ]]; then
    printf '%s\n' compose >> "$MOCK_LIFECYCLE_LOG"
    if [[ " $* " == *" up "* ]]; then
        : > "$MOCK_CONTAINER_STATE"
    fi
fi

if [[ "${1:-}" == "network" && "${2:-}" == "inspect" ]]; then
    [[ "$MOCK_NETWORK_EXISTS" == true ]]
    exit
fi

if [[ "${1:-}" == "network" && "${2:-}" == "create" ]]; then
    printf '%s\n' network-create >> "$MOCK_LIFECYCLE_LOG"
    exit 0
fi

if [[ "${1:-}" == "compose" && -n "$MOCK_EXPECT_ENV_DIR" ]]; then
    [[ -f "$MOCK_EXPECT_ENV_DIR/.env" ]] || exit 1
    printf '%s\n' compose-env-present >> "$MOCK_DOCKER_LOG"
fi

if [[ "${1:-}" == "container" && "${2:-}" == "inspect" ]]; then
    if [[ "$MOCK_CONTAINER_EXISTS" != true && ! -f "$MOCK_CONTAINER_STATE" ]]; then
        exit 1
    fi
    if [[ "${3:-}" == "-f" ]]; then
        case "${4:-}" in
            *State.Running*)
                if [[ -f "$MOCK_RM_REFUSED_MARKER" ]]; then
                    printf '%s\n' "$MOCK_AFTER_REFUSAL_RUNNING"
                else
                    printf '%s\n' "$MOCK_RUNNING"
                fi
                ;;
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
/home/tester/.opencode-profiles
/home/tester/.config/workbenches
/home/tester/.local/lib/workbenches
/home/tester/.local/state/workbenches
/home/tester/.pi-profiles
/home/tester/.gemini-profiles
/home/tester/.grok-profiles
/home/tester/.glm-profiles
MOUNTS
                else
                    printf '%s\n' /workspace/projects
                fi
                ;;
            *Config.Image*)
                printf '%s\n' "$MOCK_CONFIG_IMAGE"
                ;;
            *.Image*)
                printf '%s\n' "$MOCK_CONTAINER_IMAGE_ID"
                ;;
        esac
    fi
    exit 0
fi

if [[ "${1:-}" == "image" && "${2:-}" == "inspect" ]]; then
    if [[ "${!#}" == "py-bench:latest" && "$MOCK_LAYER2_EXISTS" != true ]]; then
        exit 1
    fi
    printf '%s\n' "$MOCK_EXPECTED_IMAGE_ID"
    exit 0
fi

if [[ "${1:-}" == "rm" && "${2:-}" != "-f" && "$MOCK_RM_REFUSE" == "true" ]]; then
    : > "$MOCK_RM_REFUSED_MARKER"
    exit 1
fi

exit 0
MOCK
    chmod +x "$mock_bin/docker"

    cat > "$mock_bin/devcontainer" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf 'devcontainer %s\n' "$*" >> "$MOCK_DOCKER_LOG"
if [[ "${1:-}" == "up" ]]; then
    : > "$MOCK_CONTAINER_STATE"
fi
MOCK
    chmod +x "$mock_bin/devcontainer"

    local launcher_args=()
    if [[ "${CASE_EXPLICIT_COMPOSE:-false}" == true ]]; then
        launcher_args+=(--compose-file "$explicit_compose")
    fi
    # `--check` stops at the verification shell, which is what every lifecycle
    # case above wants. CASE_NO_CHECK lets a case run the launcher all the way
    # to the `exec docker exec` a person actually lands in — the only place the
    # lane environment it threads can be observed (lane-collision-protocol
    # Amendment 18 clause (a), opensoft/workBenches#98; Copilot round 1 on
    # PR #101, which asked for the runtime path this suite is the CI cover for).
    # The mock `docker` logs its argv and exits 0, so the exec'd command is a
    # log line rather than a shell.
    local check_args=(--check)
    [[ "${CASE_NO_CHECK:-false}" != true ]] || check_args=()

    local output
    local launcher_status=0
    output="$(
        env \
            HOME="$fake_home" \
            USER=tester \
            PATH="$mock_bin:$PATH" \
            MOCK_DOCKER_LOG="$docker_log" \
            MOCK_EXPECT_ENV_DIR="$expected_env_dir" \
            WAVE_WSLG_ROOT="$wslg_root" \
            MOCK_CONTAINER_EXISTS="${CASE_CONTAINER_EXISTS:-true}" \
            MOCK_CONTAINER_STATE="$case_root/container-created" \
            MOCK_PREPARE_LOG="$prepare_log" \
            MOCK_ENSURE_IMAGES_LOG="$ensure_images_log" \
            MOCK_ROCM_LOG="$rocm_log" \
            MOCK_SONARQUBE_LOG="$sonarqube_log" \
            MOCK_LIFECYCLE_LOG="$lifecycle_log" \
            MOCK_NETWORK_EXISTS="${CASE_NETWORK_EXISTS:-true}" \
            MOCK_LAYER2_EXISTS="${CASE_LAYER2_EXISTS:-true}" \
            MOCK_RUNNING="$running" \
            MOCK_MOUNTS="$mounts" \
            MOCK_RM_REFUSE="$rm_refuse" \
            MOCK_RM_REFUSED_MARKER="$case_root/rm-refused" \
            MOCK_AFTER_REFUSAL_RUNNING="$after_refusal_running" \
            MOCK_CONFIG_IMAGE="${CASE_CONFIG_IMAGE:-$expected_config_image}" \
            MOCK_CONTAINER_IMAGE_ID="${CASE_CONTAINER_IMAGE_ID:-sha256:expected}" \
            MOCK_EXPECTED_IMAGE_ID="${CASE_EXPECTED_IMAGE_ID:-sha256:expected}" \
            "$launcher" \
                --workbenches-root "$fake_root" \
                --shell sh \
                ${check_args[@]+"${check_args[@]}"} \
                "${launcher_args[@]}" \
                "$@" \
                "$bench" 2>&1
    )" || launcher_status=$?
    if [[ "$launcher_status" -ne "${CASE_EXPECT_STATUS:-0}" ]]; then
        echo "$output" >&2
        rm -rf "$case_root"
        fail "$case_name launcher invocation returned $launcher_status, expected ${CASE_EXPECT_STATUS:-0}"
    fi

    CASE_OUTPUT="$output"
    CASE_DOCKER_LOG="$(cat "$docker_log")"
    CASE_PREPARE_LOG="$(cat "$prepare_log" 2>/dev/null || true)"
    CASE_ENSURE_IMAGES_LOG="$(cat "$ensure_images_log" 2>/dev/null || true)"
    CASE_ROCM_LOG="$(cat "$rocm_log" 2>/dev/null || true)"
    CASE_SONARQUBE_LOG="$(cat "$sonarqube_log" 2>/dev/null || true)"
    CASE_LIFECYCLE_LOG="$(cat "$lifecycle_log" 2>/dev/null || true)"
    rm -rf "$case_root"
}

bash -n "$launcher"
"$launcher" --help | grep -q -- '--repair' || fail "help does not document --repair"
if grep -Fq 'ln -sfn /usr/local/bin/claude "$HOME/.local/bin/claude"' "$launcher"; then
    fail "launcher can overwrite the host Claude binary link through a writable home mount"
fi

run_launcher_case preserve-running true missing true true py-bench
grep -q -- '--container py-bench --base py-bench:latest --user tester --project dev-benches --service py-bench' <<<"$CASE_PREPARE_LOG" \
    || fail "safe startup helper did not receive the pyBench lifecycle contract"
grep -q 'preserving the live container' <<<"$CASE_OUTPUT" || fail "running container was not preserved with a warning"
if grep -q '^rm -f py-bench$' <<<"$CASE_DOCKER_LOG"; then
    fail "normal launch removed a running container"
fi

CASE_EXPECT_STATUS=1 \
CASE_CONFIG_IMAGE='ghcr.io/codexfactory/browser-ui-repair-bench:latest' \
CASE_CONTAINER_IMAGE_ID='sha256:foreign' \
CASE_EXPECTED_IMAGE_ID='sha256:expected' \
run_launcher_case foreign-container-collision false missing false false py-bench
grep -q "Refusing to use container 'py-bench'" <<<"$CASE_OUTPUT" || fail "foreign container collision was not reported"
if [[ -n "$CASE_PREPARE_LOG" ]]; then
    fail "foreign container collision invoked the Layer 3 preparation helper"
fi
if grep -Eq '^(start|rm|compose|exec|cp) ' <<<"$CASE_DOCKER_LOG"; then
    fail "foreign container collision mutated the named container"
fi
if grep -q '^compose ' <<<"$CASE_DOCKER_LOG"; then
    fail "normal launch recreated a running container"
fi

run_launcher_case explicit-repair true complete false true py-bench --repair
grep -q '^rm -f py-bench$' <<<"$CASE_DOCKER_LOG" || fail "--repair did not remove the existing container"
grep -q '^compose ' <<<"$CASE_DOCKER_LOG" || fail "--repair did not recreate the container"

run_launcher_case stopped-auto-repair false missing false false py-bench
grep -q '^rm py-bench$' <<<"$CASE_DOCKER_LOG" || fail "stopped container with missing mounts was not removed safely"
grep -q '^compose ' <<<"$CASE_DOCKER_LOG" || fail "stopped container with missing mounts was not recreated"

run_launcher_case started-during-check false missing true true py-bench
grep -q 'started while Wave mounts were being checked' <<<"$CASE_OUTPUT" || fail "container start race was not reported"
if grep -q '^rm -f py-bench$' <<<"$CASE_DOCKER_LOG"; then
    fail "automatic repair force-removed a container that started during checks"
fi
if grep -q '^compose ' <<<"$CASE_DOCKER_LOG"; then
    fail "automatic repair recreated a container that started during checks"
fi

run_launcher_case dotnet-defaults false missing false false dotNetBench
grep -q -- '--container dotnet-bench --base dotnet-bench:latest --user tester --project dev-benches --service dotnet-bench' <<<"$CASE_PREPARE_LOG" \
    || fail "safe startup helper did not receive the dotNetBench lifecycle contract"

CASE_EXPLICIT_COMPOSE=true run_launcher_case dotnet-explicit-compose false missing false false dotNetBench
grep -q -- "compose -f .*/custom-compose.yml" <<<"$CASE_DOCKER_LOG" \
    || fail "dotNetBench replaced the explicitly supplied Compose file"

CASE_CONTAINER_EXISTS=false CASE_EXPLICIT_COMPOSE=true run_launcher_case dotnet-explicit-compose-first-create false missing false false dotNetBench
grep -q -- "compose -f .*/custom-compose.yml" <<<"$CASE_DOCKER_LOG" \
    || fail "first creation did not use the explicitly supplied Compose file"
if grep -q '^devcontainer ' <<<"$CASE_DOCKER_LOG"; then
    fail "first creation ignored the explicit Compose file through Dev Containers CLI"
fi

CASE_CONTAINER_EXISTS=false run_launcher_case dotnet-devcontainer-first-create false missing false false dotNetBench
grep -q -- "^devcontainer up --workspace-folder .*/devBenches/dotNetBench$" <<<"$CASE_DOCKER_LOG" \
    || fail "default first creation did not preserve the declared Dev Containers lifecycle"
if grep -q '^compose ' <<<"$CASE_DOCKER_LOG"; then
    fail "default first creation replaced the declared Dev Containers lifecycle with direct Compose"
fi

CASE_CONTAINER_EXISTS=false CASE_NETWORK_EXISTS=false CASE_LAYER2_EXISTS=false run_launcher_case wave-default-compose-first-create false missing false false py-bench
[[ "$CASE_ENSURE_IMAGES_LOG" == "--user tester" ]] \
    || fail "Wave first creation did not bootstrap a missing pyBench image stack"
grep -q -- "compose -f .*/devBenches/pyBench/.devcontainer/docker-compose.yml -f .*/devBenches/pyBench/.devcontainer/docker-compose.amd-rocm.generated.yml -f .*/py-bench.override.yml up -d py-bench" <<<"$CASE_DOCKER_LOG" \
    || fail "Wave first creation did not use the bench Compose file, generated ROCm overlay, and Wave override"
grep -q '^network create devbench-shared$' <<<"$CASE_DOCKER_LOG" \
    || fail "Wave first creation did not create pyBench's missing external network"
[[ "$CASE_ROCM_LOG" == configured ]] || fail "Wave first creation did not regenerate the pyBench ROCm override"
[[ "$CASE_SONARQUBE_LOG" == configured ]] || fail "Wave first creation did not bootstrap the reusable SonarQube MCP service"
[[ "$CASE_LIFECYCLE_LOG" == $'network-create\nsonarqube\nrocm\ncompose' ]] \
    || fail "Wave first creation did not prepare the network, SonarQube MCP, and ROCm before Compose"
if grep -q '^devcontainer ' <<<"$CASE_DOCKER_LOG"; then
    fail "Wave first creation used Dev Containers CLI instead of its Compose lifecycle"
fi

CASE_CONTAINER_EXISTS=false CASE_EXPLICIT_COMPOSE=true CASE_WSLG_ENABLED=true run_launcher_case rust-explicit-compose-first-create false missing false false rustBench
grep -q -- "compose -f .*/custom-compose.yml -f .*/devBenches/rustBench/.devcontainer/docker-compose.wslg.yml" <<<"$CASE_DOCKER_LOG" \
    || fail "rustBench resolved its WSLg override relative to the explicit Compose file"

CASE_CONTAINER_EXISTS=false CASE_EXPLICIT_COMPOSE=true CASE_GENERIC_COMPOSE=true run_launcher_case generic-explicit-compose-first-create false missing false false custom-bench
grep -q '^compose-env-present$' <<<"$CASE_DOCKER_LOG" \
    || fail "generic container did not copy its bench-root .env beside the Compose file"

# ---------------------------------------------------------------------------
# THE LANE ENVIRONMENT THE CONTAINER IS OPENED WITH — lane-collision-protocol
# Amendment 18 clause (a) (opensoft/workBenches#98), asserted on the `docker
# exec` a person actually lands in rather than on this script's source (Copilot
# round 1 on PR #101). The record carries `host <name>; os
# <linux|macos|wsl|windows>; container <name|none>` beside the workstation,
# because a pid does not cross a pid namespace and a lane live in one bench
# container read NOT LIVE from another on the same host; this script is what
# gets those facts INTO a bench container, and the container name is the one
# fact the process inside cannot work out for itself.
lanes_exec_line() { grep '^exec ' <<<"$CASE_DOCKER_LOG" | tail -n 1; }

# 1. CONFIGURED VALUES TRAVEL IN, AND THE CONTAINER IS NAMED WITH THE BENCH
# THIS SCRIPT RESOLVED — `dotNetBench` on the command line, `dotnet-bench` in
# the environment, which is the name the lane record must carry.
export LANES_WORKSTATION=Eagle LANES_HOST=eagle LANES_OS=wsl
CASE_NO_CHECK=true run_launcher_case lanes-env-configured true complete false true dotNetBench
unset LANES_WORKSTATION LANES_HOST LANES_OS
grep -q -- '--env LANES_WORKSTATION=Eagle' <<<"$(lanes_exec_line)" \
    || fail "the workstation did not reach the container's shell ($(lanes_exec_line))"
grep -q -- '--env LANES_HOST=eagle' <<<"$(lanes_exec_line)" \
    || fail "the host did not reach the container's shell ($(lanes_exec_line))"
grep -q -- '--env LANES_OS=wsl' <<<"$(lanes_exec_line)" \
    || fail "the OS did not reach the container's shell ($(lanes_exec_line))"
grep -q -- '--env LANES_CONTAINER=dotnet-bench' <<<"$(lanes_exec_line)" \
    || fail "the container was not told its own resolved bench name ($(lanes_exec_line))"

# 2. WHAT THIS SCRIPT CANNOT ANSWER IT DOES NOT INVENT. Run from inside a
# container itself — forced with the `container=` marker, which is a container
# everywhere — with nothing configured: the host is not passed at all rather
# than passed as the container id this script would otherwise read from
# `hostname`, and neither is the workstation, whose own rule (`R-A11-14`) this
# follows. The OS is still passed, because the kernel is readable from inside a
# container and is the same kernel; and the bench is still named, because this
# script knows which one it is opening.
env_before_os="${LANES_OS:-}"
unset LANES_WORKSTATION LANES_HOST LANES_OS LANES_CONTAINER 2>/dev/null || true
export container=docker
CASE_NO_CHECK=true run_launcher_case lanes-env-unconfigured true complete false true py-bench
unset container
[[ -z "$env_before_os" ]] || export LANES_OS="$env_before_os"
if grep -q -- '--env LANES_HOST=' <<<"$(lanes_exec_line)"; then
    fail "a container that could name no host passed one in anyway ($(lanes_exec_line))"
fi
if grep -q -- '--env LANES_WORKSTATION=' <<<"$(lanes_exec_line)"; then
    fail "a container that could name no workstation passed one in anyway ($(lanes_exec_line))"
fi
grep -Eq -- '--env LANES_OS=(linux|macos|wsl|windows)( |$)' <<<"$(lanes_exec_line)" \
    || fail "the OS was unanswered or is none of the four words ($(lanes_exec_line))"
grep -q -- '--env LANES_CONTAINER=py-bench' <<<"$(lanes_exec_line)" \
    || fail "the bench name, which this script always knows, was not passed ($(lanes_exec_line))"

echo "PASS: wave container launcher lifecycle tests"
