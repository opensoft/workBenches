#!/usr/bin/env bash
# Launch an interactive shell inside a workBench container from Wave Terminal.

set -euo pipefail

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
compose_file="$bench_dir/.devcontainer/docker-compose.yml"
base_image="py-bench:latest"
layer3_chown=""
compose_project="dev-benches"

resolve_bench_defaults() {
    case "$container" in
        pyBench|py-bench)
            container="py-bench"
            bench_dir="$workbenches_root/devBenches/pyBench"
            compose_file="$bench_dir/.devcontainer/docker-compose.yml"
            base_image="py-bench:latest"
            layer3_chown=""
            compose_project="dev-benches"
            ;;
        cppBench|C++Bench|c++Bench|cpp-bench)
            container="cpp-bench"
            bench_dir="$workbenches_root/devBenches/cppBench"
            compose_file="$bench_dir/.devcontainer/docker-compose.yml"
            base_image="cpp-bench:latest"
            layer3_chown="/opt/vcpkg"
            compose_project="dev-benches"
            ;;
        rustBench|rust-bench)
            container="rust-bench"
            bench_dir="$workbenches_root/devBenches/rustBench"
            compose_file="$bench_dir/.devcontainer/docker-compose.yml"
            base_image="rust-bench:latest"
            layer3_chown="/opt/rust"
            compose_project="dev-benches"
            ;;
        flutterBench|flutter-bench)
            container="flutter-bench"
            bench_dir="$workbenches_root/devBenches/flutterBench"
            compose_file="$bench_dir/.devcontainer/docker-compose.yml"
            base_image="flutter-bench:latest"
            layer3_chown="/opt/flutter /opt/flutter-3.27.0 /opt/android-sdk"
            compose_project="dev-benches"
            ;;
        cloudBench|cloud-bench)
            container="cloud-bench"
            bench_dir="$workbenches_root/sysBenches/cloudBench/devcontainer.example"
            compose_file="$bench_dir/docker-compose.yml"
            base_image="cloud-bench:latest"
            layer3_chown=""
            compose_project="sys-benches"
            ;;
        365Bench|m365Bench|m365-bench)
            container="m365-bench"
            bench_dir="$workbenches_root/sysBenches/365Bench"
            compose_file="$bench_dir/.devcontainer/docker-compose.yml"
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
        --compose-file) compose_file="$2"; shift 2 ;;
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

prepare_script="$workbenches_root/scripts/prepare-bench-start.sh"
if [[ ! -x "$prepare_script" ]]; then
    echo "Safe bench startup helper is missing or not executable: $prepare_script" >&2
    exit 1
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

    local compose_dir
    compose_dir="$(dirname "$compose_file")"
    bench_dir="$(dirname "$compose_dir")"
    if [[ ! -f "$compose_dir/.env" && -f "$bench_dir/.env" ]]; then
        cp "$bench_dir/.env" "$compose_dir/.env"
    fi

    local override_file
    local compose_args
    override_file="$(write_wave_compose_override)"
    compose_args=(-f "$compose_file")
    if [[ "$container" == "rust-bench" && -d /mnt/wslg ]]; then
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

recreate_stopped_with_compose() {
    echo "Recreating stopped container $container with Wave compose mounts..."
    if docker rm "$container" >/dev/null 2>&1; then
        create_with_compose
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

container_exists=false
if docker container inspect "$container" >/dev/null 2>&1; then
    container_exists=true
fi

if [[ "$repair_requested" == true && "$container_exists" == true ]]; then
    recreate_with_compose
elif [[ "$container_exists" != true ]]; then
    if [[ -f "$bench_dir/.devcontainer/devcontainer.json" ]]; then
        echo "Creating $container with Dev Containers CLI..."
        if ! run_devcontainer_up; then
            echo "Dev Containers CLI did not complete; creating $container with Wave compose mounts." >&2
            docker rm -f "$container" >/dev/null 2>&1 || true
            create_with_compose
        fi
    else
        create_with_compose
    fi
elif [[ -f "$bench_dir/.devcontainer/devcontainer.json" ]] && container_missing_required_mounts; then
    recreate_stopped_with_compose
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
    if [[ -f "$claude_launcher" ]]; then
        docker exec --user "$container_user" "$container" sh -c \
            'ln -sfn /usr/local/bin/claude "$HOME/.local/bin/claude"'
    fi
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

exec docker exec "${tty_args[@]}" \
    --env "TERM=$term_name" \
    --env "COLORTERM=$color_term" \
    --env "CLICOLOR=1" \
    --env "FORCE_COLOR=1" \
    --env "HISTFILE=$container_history_file" \
    --user "$container_user" \
    --workdir "$workdir" \
    "$container" \
    "$shell_path" "${shell_args[@]}"
