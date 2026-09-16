#!/usr/bin/env bash
# Launch an interactive shell inside a workBench container from Wave Terminal.

set -euo pipefail

# THE WORKSTATION THIS CONTAINER BELONGS TO — `R-A11-14` (A11 Addendum 3 on
# brettheap/new-workstation#20, ratified by Brett Heap 2026-09-13 "a11 addendum
# 3 yes"). The lane register and the Amendment 7 object log are keyed on the
# workstation, and `hostname -s` INSIDE a bench container is the container id —
# an identifier that has existed for an hour and will not exist tomorrow
# (new-workstation#20, Evidence 6, where a forked orchestrator wrote one into an
# append-only log). Every lane writer therefore reads LANES_WORKSTATION and
# REFUSES without it, and the two things that START the sessions those writers
# run in are this script and `claude-profile`: so the host names itself HERE,
# where the name is still true, and the value travels in with the shell.
#
# An already-configured value wins. A host that is itself a container guesses
# nothing — and this test is made HERE, at the top, because `container` is a
# variable of this script's own a few lines below, and by the time that
# assignment has run the environment marker cannot be read any more.
lanes_workstation="${LANES_WORKSTATION:-}"
if [[ -z "$lanes_workstation" && ! -e /.dockerenv && ! -e /run/.containerenv && -z "${container:-}" ]]; then
    lanes_workstation="$(hostname -s 2>/dev/null || hostname 2>/dev/null || true)"
fi
lanes_workstation_env=()
[[ -z "$lanes_workstation" ]] \
    || lanes_workstation_env=(--env "LANES_WORKSTATION=$lanes_workstation")

# ...AND WHERE THE LANE WILL BE RUNNING — lane-collision-protocol Amendment 18
# clause (a) (opensoft/workBenches#98), the same ruling two variables along. The
# record now carries `host <name>; os <linux|macos|wsl|windows>; container
# <name|none>` beside the workstation, because a pid does not cross a pid
# namespace and a lane live in one bench container read NOT LIVE from another on
# the same host. `claude-profile` exports all three for the sessions it starts;
# THIS script is the half that gets them into a bench container in the first
# place, and it is the only place that can answer the third: a container cannot
# name itself — its `hostname` is the id docker gave it — while the bench it is
# about to open is named right here.
#
# An already-set value wins, as above, and the `hostname` read is under the same
# container fence and for the same reason. Read HERE, at the top, for the same
# reason the workstation is: `container` is a variable of this script's own a few
# lines below and the environment marker cannot be read once it has been
# assigned. LANES_CONTAINER alone is built at the `docker exec` itself, after
# `resolve_bench_defaults` has settled which bench this is.
lanes_host="${LANES_HOST:-}"
if [[ -z "$lanes_host" && ! -e /.dockerenv && ! -e /run/.containerenv && -z "${container:-}" ]]; then
    lanes_host="$(hostname -s 2>/dev/null || hostname 2>/dev/null || true)"
fi
lanes_host_env=()
[[ -z "$lanes_host" ]] \
    || lanes_host_env=(--env "LANES_HOST=$lanes_host")

# The four words are the amendment's whole vocabulary and the lane tooling drops
# an `os` that is none of them (opensoft/openRepoTools#83), so a kernel this case
# cannot name exports nothing rather than a fifth word. The HOST's word is what
# travels in, and it is the container's word too: a container shares the host's
# kernel, so the probe inside it would read the very same `/proc/version`.
# `windows` is passed through and never derived here — this script is bash, and
# on a Windows machine that is WSL2, which says `wsl`.
lanes_os="${LANES_OS:-}"
if [[ -z "$lanes_os" ]]; then
    case "$(uname -s 2>/dev/null || true)" in
        Darwin)
            lanes_os=macos
            ;;
        Linux)
            lanes_kernel=""
            [[ ! -r /proc/version ]] || lanes_kernel="$(cat /proc/version 2>/dev/null || true)"
            lanes_kernel="$lanes_kernel $(uname -r 2>/dev/null || true)"
            lanes_kernel="$(printf '%s' "$lanes_kernel" | tr '[:upper:]' '[:lower:]')"
            case "$lanes_kernel" in
                *microsoft*|*wsl*) lanes_os=wsl ;;
                *) lanes_os=linux ;;
            esac
            ;;
        CYGWIN*|MINGW*|MSYS*|Windows_NT)
            lanes_os=windows
            ;;
    esac
fi
lanes_os_env=()
[[ -z "$lanes_os" ]] \
    || lanes_os_env=(--env "LANES_OS=$lanes_os")

home_dir="${HOME:?HOME is required}"
default_user="$(id -un 2>/dev/null || printf 'user')"
workbenches_root="${WORKBENCHES_ROOT:-$home_dir/projects/workBenches}"
container="py-bench"
container_user="${USER:-$default_user}"
workdir="/workspace"
shell_path="zsh"
block_title="pyBench"
check_only=false
repair_requested=false
profile_launcher_marker="/usr/local/share/workbenches/profile-launchers.sha256"
bench_dir="$workbenches_root/devBenches/pyBench"
bench_dir_resolved=false
compose_file="$bench_dir/.devcontainer/docker-compose.yml"
compose_file_explicit=false
wslg_root="${WAVE_WSLG_ROOT:-/mnt/wslg}"
base_image="py-bench:latest"
layer3_chown=""
compose_project="dev-benches"

resolve_bench_defaults() {
    case "$container" in
        pyBench|py-bench)
            container="py-bench"
            bench_dir="$workbenches_root/devBenches/pyBench"
            bench_dir_resolved=true
            [[ "$compose_file_explicit" == true ]] || compose_file="$bench_dir/.devcontainer/docker-compose.yml"
            base_image="py-bench:latest"
            layer3_chown=""
            compose_project="dev-benches"
            ;;
        dotNetBench|dotnetBench|dotnet-bench)
            container="dotnet-bench"
            bench_dir="$workbenches_root/devBenches/dotNetBench"
            bench_dir_resolved=true
            [[ "$compose_file_explicit" == true ]] || compose_file="$bench_dir/.devcontainer/docker-compose.yml"
            base_image="dotnet-bench:latest"
            layer3_chown=""
            compose_project="dev-benches"
            ;;
        cppBench|C++Bench|c++Bench|cpp-bench)
            container="cpp-bench"
            bench_dir="$workbenches_root/devBenches/cppBench"
            bench_dir_resolved=true
            [[ "$compose_file_explicit" == true ]] || compose_file="$bench_dir/.devcontainer/docker-compose.yml"
            base_image="cpp-bench:latest"
            layer3_chown="/opt/vcpkg"
            compose_project="dev-benches"
            ;;
        rustBench|rust-bench)
            container="rust-bench"
            bench_dir="$workbenches_root/devBenches/rustBench"
            bench_dir_resolved=true
            [[ "$compose_file_explicit" == true ]] || compose_file="$bench_dir/.devcontainer/docker-compose.yml"
            base_image="rust-bench:latest"
            layer3_chown="/opt/rust"
            compose_project="dev-benches"
            ;;
        flutterBench|flutter-bench)
            container="flutter-bench"
            bench_dir="$workbenches_root/devBenches/flutterBench"
            bench_dir_resolved=true
            [[ "$compose_file_explicit" == true ]] || compose_file="$bench_dir/.devcontainer/docker-compose.yml"
            base_image="flutter-bench:latest"
            layer3_chown="/opt/flutter /opt/flutter-3.27.0 /opt/android-sdk"
            compose_project="dev-benches"
            ;;
        cloudBench|cloud-bench)
            container="cloud-bench"
            bench_dir="$workbenches_root/sysBenches/cloudBench/devcontainer.example"
            bench_dir_resolved=true
            [[ "$compose_file_explicit" == true ]] || compose_file="$bench_dir/docker-compose.yml"
            base_image="cloud-bench:latest"
            layer3_chown=""
            compose_project="sys-benches"
            ;;
        365Bench|m365Bench|m365-bench)
            container="m365-bench"
            bench_dir="$workbenches_root/sysBenches/365Bench"
            bench_dir_resolved=true
            [[ "$compose_file_explicit" == true ]] || compose_file="$bench_dir/.devcontainer/docker-compose.yml"
            base_image="m365-bench:latest"
            layer3_chown=""
            compose_project="sys-benches"
            ;;
        *)
            base_image="${container}:latest"
            layer3_chown=""
            compose_project=""
            ;;
    esac
}

usage() {
    cat <<'EOF'
Usage: wave-container-shell.sh [options] [container]

Options:
  --workbenches-root PATH  workBenches checkout path
  --compose-file PATH      Compose file used to create the container
  --user NAME              Container user (default: current WSL user)
  --workdir PATH           Container working directory (default: /workspace)
  --shell PATH             Shell to run inside the container (default: zsh)
  --title TEXT             Wave block/terminal title (default: pyBench)
  --check                  Verify that the container can run a command, then exit
  --repair                 Recreate an existing container before opening it
  -h, --help               Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --workbenches-root) workbenches_root="$2"; shift 2 ;;
        --compose-file) compose_file="$2"; compose_file_explicit=true; shift 2 ;;
        --user) container_user="$2"; shift 2 ;;
        --workdir) workdir="$2"; shift 2 ;;
        --shell) shell_path="$2"; shift 2 ;;
        --title) block_title="$2"; shift 2 ;;
        --check) check_only=true; shift ;;
        --repair) repair_requested=true; shift ;;
        -h|--help) usage; exit 0 ;;
        --*) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
        *) container="$1"; shift ;;
    esac
done

workbenches_root="${workbenches_root%/}"
resolve_bench_defaults
container_history_dir="/home/${container_user}/.workbenches-history"
container_history_file="${container_history_dir}/.zsh_history"

if [[ ! -d "$workbenches_root" ]]; then
    echo "workBenches root does not exist: $workbenches_root" >&2
    exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
    echo "docker was not found in this WSL distro." >&2
    exit 1
fi

expected_layer3_image="${base_image%%:*}:${container_user}"
container_exists=false
if docker container inspect "$container" >/dev/null 2>&1; then
    container_exists=true
    configured_image="$(docker container inspect -f '{{.Config.Image}}' "$container")"
    container_image_id="$(docker container inspect -f '{{.Image}}' "$container")"
    expected_image_id="$(docker image inspect -f '{{.Id}}' "$expected_layer3_image" 2>/dev/null || true)"

    if [[ "$configured_image" != "$expected_layer3_image" ]] && \
       [[ -z "$expected_image_id" || "$container_image_id" != "$expected_image_id" ]]; then
        echo "Refusing to use container '$container': it is configured from '$configured_image' ($container_image_id), but Wave '$block_title' requires '$expected_layer3_image'." >&2
        echo "Leave the foreign container unchanged; stop it if needed, then rename or remove it to free this name before creating the workBench container." >&2
        exit 1
    fi
fi

prepare_script="$workbenches_root/scripts/prepare-bench-start.sh"
if [[ ! -x "$prepare_script" ]]; then
    echo "Safe bench startup helper is missing or not executable: $prepare_script" >&2
    exit 1
fi

if [[ "$container" == "py-bench" && "$container_exists" != true ]] \
    && ! docker image inspect "$base_image" >/dev/null 2>&1; then
    pybench_ensure_images="$bench_dir/scripts/ensure-images.sh"
    if [[ ! -x "$pybench_ensure_images" ]]; then
        echo "pyBench image bootstrap helper is missing or not executable: $pybench_ensure_images" >&2
        exit 1
    fi
    "$pybench_ensure_images" --user "$container_user"
fi

prepare_args=(
    --container "$container"
    --base "$base_image"
    --user "$container_user"
    --project "$compose_project"
    --service "$container"
)
if [[ -n "$layer3_chown" ]]; then
    prepare_args+=(--chown "$layer3_chown")
fi
"$prepare_script" "${prepare_args[@]}"

# Layer 3 preparation can reconcile a stopped stale container. Re-read the
# name after it returns so subsequent lifecycle decisions use current state.
container_exists=false
if docker container inspect "$container" >/dev/null 2>&1; then
    container_exists=true
fi

if [[ "$check_only" != true ]]; then
    if [[ -t 1 ]]; then
        printf '\033]0;%s\007' "$block_title"
    fi
    echo "Opening '$block_title' container shell..."
fi

run_devcontainer_up() {
    local remove_flag=()
    local devcontainer_timeout="${WAVE_DEVCONTAINER_UP_TIMEOUT:-25s}"
    if [[ "${1:-}" == "--remove-existing-container" ]]; then
        remove_flag=(--remove-existing-container)
    fi

    run_with_timeout() {
        if command -v timeout >/dev/null 2>&1; then
            timeout --foreground "$devcontainer_timeout" "$@"
        else
            "$@"
        fi
    }

    if command -v devcontainer >/dev/null 2>&1; then
        run_with_timeout devcontainer up --workspace-folder "$bench_dir" "${remove_flag[@]}"
    elif command -v npx >/dev/null 2>&1; then
        run_with_timeout npx -y @devcontainers/cli up --workspace-folder "$bench_dir" "${remove_flag[@]}"
    else
        return 127
    fi
}

ensure_host_sources() {
    mkdir -p \
        "$home_dir/projects" \
        "$home_dir/.ssh" \
        "$home_dir/.azure" \
        "$home_dir/.aws" \
        "$home_dir/.kube" \
        "$home_dir/.config/gh" \
        "$home_dir/.claude" \
        "$home_dir/.claude-profiles" \
        "$home_dir/.codex" \
        "$home_dir/.chatgpt-profiles" \
        "$home_dir/.opencode-profiles" \
        "$home_dir/.gemini-profiles" \
        "$home_dir/.grok-profiles" \
        "$home_dir/.glm-profiles" \
        "$home_dir/.omnigent" \
        "$home_dir/.agents" \
        "$home_dir/.pi" \
        "$home_dir/.pi-profiles" \
        "$home_dir/.config/workbenches" \
        "$home_dir/.local/lib/workbenches" \
        "$home_dir/.local/state/workbenches" \
        "$home_dir/.config/sonarqube" \
        "$home_dir/.gemini" \
        "$home_dir/.grok" \
        "$home_dir/.copilot-cli" \
        "$home_dir/.notebooklm" \
        "$home_dir/.notebooklm-mcp-cli" \
        "$home_dir/.local/state/opensoft/agenttower/logs"

    for file in "$home_dir/.zshrc" "$home_dir/.p10k.zsh" "$home_dir/.bashrc" "$home_dir/.gitconfig" "$home_dir/.claude.json"; do
        [[ -e "$file" ]] || touch "$file"
    done
}

write_wave_compose_override() {
    ensure_host_sources

    local override_dir="${WAVE_WORKBENCHES_COMPOSE_CACHE:-$home_dir/.cache/workbenches/wave-compose}"
    local override_file="$override_dir/$container.override.yml"
    local history_volume="${container//-/}history"

    mkdir -p "$override_dir"
    cat > "$override_file" <<EOF
services:
  $container:
    volumes:
      - ${home_dir}/projects:/workspace/projects:cached
      - ${history_volume}:${container_history_dir}
      - ${home_dir}/.zshrc:/home/${container_user}/.zshrc:ro
      - ${home_dir}/.oh-my-zsh:/home/${container_user}/.oh-my-zsh:ro
      - ${home_dir}/.p10k.zsh:/home/${container_user}/.p10k.zsh:ro
      - ${home_dir}/.bashrc:/home/${container_user}/.bashrc:ro
      - ${home_dir}/.gitconfig:/home/${container_user}/.gitconfig:ro
      - ${home_dir}/.ssh:/home/${container_user}/.ssh:ro
      - ${home_dir}/.config/gh:/home/${container_user}/.config/gh:ro
      - ${home_dir}/.azure:/home/${container_user}/.azure:ro
      - ${home_dir}/.aws:/home/${container_user}/.aws:ro
      - ${home_dir}/.kube:/home/${container_user}/.kube:ro
      - ${home_dir}/.claude:/home/${container_user}/.claude:cached
      - ${home_dir}/.claude.json:/home/${container_user}/.claude.json:cached
      - ${home_dir}/.claude-profiles:/home/${container_user}/.claude-profiles:cached
      - ${home_dir}/.codex:/home/${container_user}/.codex:cached
      - ${home_dir}/.chatgpt-profiles:/home/${container_user}/.chatgpt-profiles:cached
      - ${home_dir}/.opencode-profiles:/home/${container_user}/.opencode-profiles:cached
      - ${home_dir}/.config/workbenches:/home/${container_user}/.config/workbenches:ro
      - ${home_dir}/.local/lib/workbenches:/home/${container_user}/.local/lib/workbenches:ro
      - ${home_dir}/.local/state/workbenches:/home/${container_user}/.local/state/workbenches:cached
      - ${home_dir}/.gemini-profiles:/home/${container_user}/.gemini-profiles:cached
      - ${home_dir}/.grok-profiles:/home/${container_user}/.grok-profiles:cached
      - ${home_dir}/.glm-profiles:/home/${container_user}/.glm-profiles:cached
      - ${home_dir}/.omnigent:/home/${container_user}/.omnigent:cached
      - ${home_dir}/.agents:/home/${container_user}/.agents:cached
      - ${home_dir}/.pi:/home/${container_user}/.pi:cached
      - ${home_dir}/.pi-profiles:/home/${container_user}/.pi-profiles:cached
      - ${home_dir}/.config/sonarqube:/home/${container_user}/.config/sonarqube:ro
      - ${home_dir}/.gemini:/home/${container_user}/.gemini:cached
      - ${home_dir}/.grok:/home/${container_user}/.grok:ro
      - ${home_dir}/.copilot-cli:/home/${container_user}/.copilot-cli:ro
      - ${home_dir}/.notebooklm:/home/${container_user}/.notebooklm:cached
      - ${home_dir}/.notebooklm-mcp-cli:/home/${container_user}/.notebooklm-mcp-cli:cached
      - /var/run/docker.sock:/var/run/docker.sock
      - ${home_dir}/.local/state/opensoft/agenttower/logs:/home/${container_user}/.local/state/opensoft/agenttower/logs:cached

volumes:
  ${history_volume}:
EOF

    printf '%s\n' "$override_file"
}

create_with_compose() {
    if [[ ! -f "$compose_file" ]]; then
        echo "Container '$container' does not exist and compose file is missing: $compose_file" >&2
        if [[ "$container" == "flutter-bench" ]]; then
            echo "flutterBench is registered but is not installed at $bench_dir." >&2
        fi
        exit 1
    fi

    local compose_dir compose_bench_dir
    compose_dir="$(dirname "$compose_file")"
    if [[ "$bench_dir_resolved" == true ]]; then
        compose_bench_dir="$bench_dir"
    else
        compose_bench_dir="$(dirname "$compose_dir")"
    fi
    if [[ ! -f "$compose_dir/.env" && -f "$compose_bench_dir/.env" ]]; then
        cp "$compose_bench_dir/.env" "$compose_dir/.env"
    fi

    local override_file
    local compose_args
    override_file="$(write_wave_compose_override)"
    compose_args=(-f "$compose_file")
    if [[ "$container" == "py-bench" ]]; then
        local shared_network="devbench-shared"
        local sonarqube_mcp_script="$workbenches_root/devBenches/scripts/ensure-sonarqube-mcp.sh"
        local rocm_configure_script="$bench_dir/scripts/configure-amd-rocm-wsl.sh"
        local rocm_compose_file="$bench_dir/.devcontainer/docker-compose.amd-rocm.generated.yml"
        if [[ ! -x "$sonarqube_mcp_script" ]]; then
            echo "pyBench SonarQube MCP bootstrap helper is missing or not executable: $sonarqube_mcp_script" >&2
            exit 1
        fi
        if [[ ! -x "$rocm_configure_script" ]]; then
            echo "pyBench AMD ROCm configuration helper is missing or not executable: $rocm_configure_script" >&2
            exit 1
        fi
        if ! docker network inspect "$shared_network" >/dev/null 2>&1; then
            if ! docker network create "$shared_network" >/dev/null 2>&1 \
                && ! docker network inspect "$shared_network" >/dev/null 2>&1; then
                echo "Could not create the external pyBench network: $shared_network" >&2
                exit 1
            fi
        fi
        "$sonarqube_mcp_script"
        "$rocm_configure_script"
        if [[ ! -f "$rocm_compose_file" ]]; then
            echo "pyBench AMD ROCm override was not generated: $rocm_compose_file" >&2
            exit 1
        fi
        compose_args+=(-f "$rocm_compose_file")
    fi
    if [[ "$container" == "rust-bench" && -d "$wslg_root" ]]; then
        local wslg_compose_file="$bench_dir/.devcontainer/docker-compose.wslg.yml"
        if [[ ! -f "$wslg_compose_file" ]]; then
            echo "rustBench WSLg override is missing: $wslg_compose_file" >&2
            exit 1
        fi
        compose_args+=(-f "$wslg_compose_file")
    fi
    compose_args+=(-f "$override_file")
    echo "Creating $container with docker compose..."
    docker compose "${compose_args[@]}" up -d "$container"
}

recreate_with_compose() {
    echo "Recreating $container with Wave compose mounts..."
    docker rm -f "$container" >/dev/null 2>&1 || true
    create_with_compose
}

uses_devcontainer_lifecycle() {
    [[ "$compose_file_explicit" != true \
        && "$container" != "py-bench" \
        && -f "$bench_dir/.devcontainer/devcontainer.json" ]]
}

create_for_declared_lifecycle() {
    if uses_devcontainer_lifecycle; then
        echo "Creating $container with Dev Containers CLI..."
        if ! run_devcontainer_up; then
            echo "Dev Containers CLI did not complete; the declared devcontainer lifecycle was not replaced with a partial Compose launch." >&2
            return 1
        fi
    else
        create_with_compose
    fi
}

repair_for_declared_lifecycle() {
    if uses_devcontainer_lifecycle; then
        echo "Recreating $container with Dev Containers CLI..."
        run_devcontainer_up --remove-existing-container
    else
        recreate_with_compose
    fi
}

recreate_stopped_for_declared_lifecycle() {
    echo "Recreating stopped container $container with its declared lifecycle..."
    if docker rm "$container" >/dev/null 2>&1; then
        create_for_declared_lifecycle
        return 0
    fi

    if [[ "$(docker container inspect -f '{{.State.Running}}' "$container" 2>/dev/null)" == "true" ]]; then
        echo "Container '$container' started while Wave mounts were being checked; preserving the live container." >&2
        echo "Run this launcher with --repair when it is safe to recreate the container." >&2
        return 0
    fi

    echo "Could not remove stopped container '$container' for automatic Wave mount repair." >&2
    return 1
}

mount_destination_covers() {
    local mount_destination="$1"
    local required_path="$2"

    [[ "$mount_destination" == "$required_path" || "$required_path" == "$mount_destination"/* ]]
}

container_missing_required_mounts() {
    local mount_destinations
    mount_destinations="$(docker container inspect -f '{{range .Mounts}}{{println .Destination}}{{end}}' "$container" 2>/dev/null || true)"

    local required_mounts=()
    required_mounts=(
        "/workspace/projects"
        "$container_history_dir"
        "/home/${container_user}/.zshrc"
        "/home/${container_user}/.oh-my-zsh"
        "/home/${container_user}/.p10k.zsh"
        "/home/${container_user}/.claude-profiles"
        "/home/${container_user}/.chatgpt-profiles"
        "/home/${container_user}/.opencode-profiles"
        "/home/${container_user}/.config/workbenches"
        "/home/${container_user}/.local/lib/workbenches"
        "/home/${container_user}/.local/state/workbenches"
        "/home/${container_user}/.pi-profiles"
        "/home/${container_user}/.gemini-profiles"
        "/home/${container_user}/.grok-profiles"
        "/home/${container_user}/.glm-profiles"
    )
    if [[ "$container" == "rust-bench" ]]; then
        required_mounts+=("/home/${container_user}/.cargo")
        if [[ -d /mnt/wslg ]]; then
            required_mounts+=("/mnt/wslg")
        fi
    fi

    local mount
    local destination
    for mount in "${required_mounts[@]}"; do
        local found=false
        while IFS= read -r destination; do
            if mount_destination_covers "$destination" "$mount"; then
                found=true
                break
            fi
        done <<<"$mount_destinations"

        if [[ "$found" != true ]]; then
            return 0
        fi
    done

    return 1
}

if [[ "$repair_requested" == true && "$container_exists" == true ]]; then
    repair_for_declared_lifecycle
elif [[ "$container_exists" != true ]]; then
    # pyBench's initialize command and Compose overlays are reproduced by
    # prepare-bench-start plus create_with_compose. Other devcontainer.json
    # benches retain their declared lifecycle and additional Compose files.
    create_for_declared_lifecycle
elif [[ -f "$bench_dir/.devcontainer/devcontainer.json" ]] && container_missing_required_mounts; then
    recreate_stopped_for_declared_lifecycle
fi

if [[ "$(docker container inspect -f '{{.State.Running}}' "$container")" != "true" ]]; then
    echo "Starting $container..."
    docker start "$container" >/dev/null
fi

ensure_container_history() {
    docker exec --user root "$container" sh -c \
        "mkdir -p '$container_history_dir' && touch '$container_history_file' && chown -R '${container_user}:${container_user}' '$container_history_dir'"
}

ensure_user_cargo_cache() {
    [[ "$container" == "rust-bench" ]] || return 0
    docker exec --user root "$container" sh -c \
        "mkdir -p '/home/${container_user}/.cargo' && chown -R '${container_user}:${container_user}' '/home/${container_user}/.cargo'"
}

claude_launcher="$workbenches_root/base-image/files/claude-profile"
codex_launcher="$workbenches_root/base-image/files/codex-profile"
opencode_launcher="$workbenches_root/base-image/files/opencode-profile"
mcp_sync_launcher="$workbenches_root/base-image/files/workbenches-mcp-sync"
provider_launcher="$workbenches_root/base-image/files/provider-profile"
pi_launcher="$workbenches_root/base-image/files/pi-profile"

install_ai_profile_launchers() {
    if [[ ! -f "$claude_launcher" \
        && ! -f "$codex_launcher" \
        && ! -f "$opencode_launcher" \
        && ! -f "$mcp_sync_launcher" \
        && ! -f "$provider_launcher" \
        && ! -f "$pi_launcher" ]]; then
        return 0
    fi

    local launchers=(
        "$claude_launcher"
        "$codex_launcher"
        "$opencode_launcher"
        "$mcp_sync_launcher"
        "$provider_launcher"
        "$pi_launcher"
    )
    local bundle_hash
    bundle_hash="$(
        for launcher in "${launchers[@]}"; do
            if [[ -f "$launcher" ]]; then
                sha256sum "$launcher" | awk '{print $1}'
            else
                printf '%s\n' missing
            fi
        done | sha256sum | awk '{print $1}'
    )"

    local installed_hash
    installed_hash="$(docker exec --user root "$container" sh -c "cat '$profile_launcher_marker' 2>/dev/null" || true)"
    if [[ "$installed_hash" != "$bundle_hash" ]]; then
        if [[ -f "$claude_launcher" ]]; then
            docker cp "$claude_launcher" "$container:/usr/local/bin/claude-profile"
            docker exec --user root "$container" sh -c \
                'chmod 0755 /usr/local/bin/claude-profile && ln -sfn claude-profile /usr/local/bin/pclaude'
        fi
        if [[ -f "$codex_launcher" ]]; then
            docker cp "$codex_launcher" "$container:/usr/local/bin/codex-profile"
            docker exec --user root "$container" sh -c \
                'chmod 0755 /usr/local/bin/codex-profile && ln -sfn codex-profile /usr/local/bin/pcodex'
        fi
        if [[ -f "$opencode_launcher" ]]; then
            docker cp "$opencode_launcher" "$container:/usr/local/bin/opencode-profile"
            docker exec --user root "$container" sh -c \
                'chmod 0755 /usr/local/bin/opencode-profile && ln -sfn opencode-profile /usr/local/bin/popencode'
        fi
        if [[ -f "$mcp_sync_launcher" ]]; then
            docker cp "$mcp_sync_launcher" "$container:/usr/local/bin/workbenches-mcp-sync"
            docker exec --user root "$container" sh -c \
                'chmod 0755 /usr/local/bin/workbenches-mcp-sync'
        fi
        if [[ -f "$provider_launcher" ]]; then
            docker cp "$provider_launcher" "$container:/usr/local/bin/provider-profile"
            docker exec --user root "$container" sh -c \
                'chmod 0755 /usr/local/bin/provider-profile
                 for name in gemini-profile pgemini grok-profile pgrok glm-profile zai-profile pglm pzai; do
                   ln -sfn provider-profile "/usr/local/bin/$name"
                 done'
        fi
        if [[ -f "$pi_launcher" ]]; then
            docker cp "$pi_launcher" "$container:/usr/local/bin/pi-profile"
            docker exec --user root "$container" sh -c \
                'chmod 0755 /usr/local/bin/pi-profile && ln -sfn pi-profile /usr/local/bin/ppi'
        fi
        docker exec --user root "$container" sh -c \
            "mkdir -p '$(dirname "$profile_launcher_marker")' && printf '%s\n' '$bundle_hash' > '$profile_launcher_marker'"
    fi

    docker exec --user root "$container" sh -c \
        "mkdir -p '/home/${container_user}/.local/bin' '/home/${container_user}/.local/state' && chown '${container_user}:${container_user}' '/home/${container_user}/.local' '/home/${container_user}/.local/bin' '/home/${container_user}/.local/state'"
}

ensure_user_cargo_cache
ensure_container_history
install_ai_profile_launchers

if [[ "$check_only" == true ]]; then
    docker exec --user "$container_user" \
        --env "HISTFILE=$container_history_file" \
        --env "WORKBENCHES_HAS_CLAUDE_LAUNCHER=$([[ -f "$claude_launcher" ]] && printf 1 || printf 0)" \
        --env "WORKBENCHES_HAS_CODEX_LAUNCHER=$([[ -f "$codex_launcher" ]] && printf 1 || printf 0)" \
        --env "WORKBENCHES_HAS_OPENCODE_LAUNCHER=$([[ -f "$opencode_launcher" ]] && printf 1 || printf 0)" \
        --env "WORKBENCHES_HAS_PROVIDER_LAUNCHER=$([[ -f "$provider_launcher" ]] && printf 1 || printf 0)" \
        --env "WORKBENCHES_HAS_PI_LAUNCHER=$([[ -f "$pi_launcher" ]] && printf 1 || printf 0)" \
        --workdir "$workdir" "$container" "$shell_path" -lc \
        'set -e
         printf "%s\n" "wave-container-shell-ok"
         whoami
         pwd
         test "$HISTFILE" = "$HOME/.workbenches-history/.zsh_history"
         if test "$WORKBENCHES_HAS_CLAUDE_LAUNCHER" = 1; then command -v claude-profile; command -v pclaude; fi
         if test "$WORKBENCHES_HAS_CODEX_LAUNCHER" = 1; then command -v codex-profile; command -v pcodex; fi
         if test "$WORKBENCHES_HAS_OPENCODE_LAUNCHER" = 1; then command -v opencode-profile; command -v popencode; test -f "$HOME/.config/workbenches/opencode-profiles.json"; test -d "$HOME/.opencode-profiles"; fi
         if test "$WORKBENCHES_HAS_CODEX_LAUNCHER" = 1; then command -v workbenches-mcp-sync; fi
         if test "$WORKBENCHES_HAS_PROVIDER_LAUNCHER" = 1; then command -v pgemini; command -v pgrok; command -v pglm; fi
         if test "$WORKBENCHES_HAS_PI_LAUNCHER" = 1; then command -v ppi; fi
         test -d "$HOME/.claude-profiles"
         test -d "$HOME/.chatgpt-profiles"
         test -d "$HOME/.opencode-profiles"
         test -d "$HOME/.pi-profiles"
         test -d "$HOME/.gemini-profiles"
         test -d "$HOME/.grok-profiles"
         test -d "$HOME/.glm-profiles"'
    exit 0
fi

set_wave_title() {
    if [[ -t 1 ]]; then
        printf '\033]0;%s\007' "$block_title"
    fi

    if command -v wsh >/dev/null 2>&1; then
        wsh setmeta -b this "frame:title=$block_title" "frame:text=$block_title" >/dev/null 2>&1 || true
    fi
}

set_wave_title
echo "Entering container '$container' as $container_user in $workdir..."

tty_args=(-i)
if [[ -t 0 && -t 1 ]]; then
    tty_args=(-it)
fi

term_name="${TERM:-xterm-256color}"
if [[ "$term_name" == "dumb" ]]; then
    term_name="xterm-256color"
fi

color_term="${COLORTERM:-truecolor}"
shell_args=()
if [[ "$(basename "$shell_path")" == "zsh" ]]; then
    shell_args=(-l)
fi

# THE BENCH NAMES ITSELF ON THE WAY IN (Amendment 18 clause (a)). `$container`
# is this script's own resolved bench — `py-bench`, `cloud-bench`, or whatever
# name the caller gave — which is exactly the `container <name>` the lane record
# wants and the one thing the process inside cannot work out for itself. Always
# passed, never conditional: this line is only ever reached for a container that
# is about to be entered, so there is no case here in which the answer is `none`.
exec docker exec "${tty_args[@]}" \
    ${lanes_workstation_env[@]+"${lanes_workstation_env[@]}"} \
    ${lanes_host_env[@]+"${lanes_host_env[@]}"} \
    ${lanes_os_env[@]+"${lanes_os_env[@]}"} \
    --env "LANES_CONTAINER=$container" \
    --env "TERM=$term_name" \
    --env "COLORTERM=$color_term" \
    --env "CLICOLOR=1" \
    --env "FORCE_COLOR=1" \
    --env "HISTFILE=$container_history_file" \
    --user "$container_user" \
    --workdir "$workdir" \
    "$container" \
    "$shell_path" "${shell_args[@]}"
