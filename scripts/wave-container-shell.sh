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
bench_dir="$workbenches_root/devBenches/pyBench"
compose_file="$bench_dir/.devcontainer/docker-compose.yml"

resolve_bench_defaults() {
    case "$container" in
        pyBench|py-bench)
            container="py-bench"
            bench_dir="$workbenches_root/devBenches/pyBench"
            compose_file="$bench_dir/.devcontainer/docker-compose.yml"
            ;;
        cppBench|C++Bench|c++Bench|cpp-bench)
            container="cpp-bench"
            bench_dir="$workbenches_root/devBenches/cppBench"
            compose_file="$bench_dir/.devcontainer/docker-compose.yml"
            ;;
        flutterBench|flutter-bench)
            container="flutter-bench"
            bench_dir="$workbenches_root/devBenches/flutterBench"
            compose_file="$bench_dir/.devcontainer/docker-compose.yml"
            ;;
        cloudBench|cloud-bench)
            container="cloud-bench"
            bench_dir="$workbenches_root/sysBenches/cloudBench/devcontainer.example"
            compose_file="$bench_dir/docker-compose.yml"
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
        -h|--help) usage; exit 0 ;;
        --*) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
        *) container="$1"; shift ;;
    esac
done

workbenches_root="${workbenches_root%/}"
resolve_bench_defaults

if [[ ! -d "$workbenches_root" ]]; then
    echo "workBenches root does not exist: $workbenches_root" >&2
    exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
    echo "docker was not found in this WSL distro." >&2
    exit 1
fi

run_devcontainer_up() {
    local remove_flag=()
    if [[ "${1:-}" == "--remove-existing-container" ]]; then
        remove_flag=(--remove-existing-container)
    fi

    if command -v devcontainer >/dev/null 2>&1; then
        devcontainer up --workspace-folder "$bench_dir" "${remove_flag[@]}"
    elif command -v npx >/dev/null 2>&1; then
        npx -y @devcontainers/cli up --workspace-folder "$bench_dir" "${remove_flag[@]}"
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
        "$home_dir/.gemini-profiles" \
        "$home_dir/.grok-profiles" \
        "$home_dir/.glm-profiles" \
        "$home_dir/.omnigent" \
        "$home_dir/.agents" \
        "$home_dir/.pi" \
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
      - ${history_volume}:/home/${container_user}/.zsh_history
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
      - ${home_dir}/.gemini-profiles:/home/${container_user}/.gemini-profiles:cached
      - ${home_dir}/.grok-profiles:/home/${container_user}/.grok-profiles:cached
      - ${home_dir}/.glm-profiles:/home/${container_user}/.glm-profiles:cached
      - ${home_dir}/.omnigent:/home/${container_user}/.omnigent:cached
      - ${home_dir}/.agents:/home/${container_user}/.agents:cached
      - ${home_dir}/.pi:/home/${container_user}/.pi:cached
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
    override_file="$(write_wave_compose_override)"
    echo "Creating $container with docker compose..."
    docker compose -f "$compose_file" -f "$override_file" up -d "$container"
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
        "/home/${container_user}/.zshrc"
        "/home/${container_user}/.oh-my-zsh"
        "/home/${container_user}/.p10k.zsh"
        "/home/${container_user}/.claude-profiles"
        "/home/${container_user}/.chatgpt-profiles"
        "/home/${container_user}/.gemini-profiles"
        "/home/${container_user}/.grok-profiles"
        "/home/${container_user}/.glm-profiles"
    )

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

        if [[ "$found" != true ]] || ! docker exec --user "$container_user" "$container" test -e "$mount" 2>/dev/null; then
            return 0
        fi
    done

    return 1
}

if ! docker container inspect "$container" >/dev/null 2>&1; then
    if [[ -f "$bench_dir/.devcontainer/devcontainer.json" ]]; then
        echo "Creating $container with Dev Containers CLI..."
        run_devcontainer_up || create_with_compose
    else
        create_with_compose
    fi
elif [[ -f "$bench_dir/.devcontainer/devcontainer.json" ]] && container_missing_required_mounts; then
    echo "Recreating $container with Dev Containers CLI so required mounts are applied..."
    if ! run_devcontainer_up --remove-existing-container; then
        echo "Dev Containers CLI failed; recreating $container with Wave compose mounts." >&2
        docker rm -f "$container" >/dev/null 2>&1 || true
        create_with_compose
    fi
fi

if [[ "$(docker container inspect -f '{{.State.Running}}' "$container")" != "true" ]]; then
    echo "Starting $container..."
    docker start "$container" >/dev/null
fi

install_ai_profile_launchers() {
    local claude_launcher="$workbenches_root/base-image/files/claude-profile"
    local codex_launcher="$workbenches_root/base-image/files/codex-profile"
    local provider_launcher="$workbenches_root/base-image/files/provider-profile"
    [[ -f "$claude_launcher" ]] || return 0

    docker cp "$claude_launcher" "$container:/usr/local/bin/claude-profile"
    docker exec --user root "$container" sh -c \
        'chmod 0755 /usr/local/bin/claude-profile && ln -sfn claude-profile /usr/local/bin/pclaude'
    if [[ -f "$codex_launcher" ]]; then
        docker cp "$codex_launcher" "$container:/usr/local/bin/codex-profile"
        docker exec --user root "$container" sh -c \
            'chmod 0755 /usr/local/bin/codex-profile && ln -sfn codex-profile /usr/local/bin/pcodex'
    fi
    if [[ -f "$provider_launcher" ]]; then
        docker cp "$provider_launcher" "$container:/usr/local/bin/provider-profile"
        docker exec --user root "$container" sh -c \
            'chmod 0755 /usr/local/bin/provider-profile
             for name in gemini-profile pgemini grok-profile pgrok glm-profile zai-profile pglm pzai; do
               ln -sfn provider-profile "/usr/local/bin/$name"
             done'
    fi
    docker exec --user root "$container" sh -c \
        "mkdir -p '/home/${container_user}/.local/bin' && chown '${container_user}:${container_user}' '/home/${container_user}/.local' '/home/${container_user}/.local/bin'"
    docker exec --user "$container_user" "$container" sh -c \
        'if [ ! -e "$HOME/.local/bin/claude" ]; then ln -s /usr/local/bin/claude "$HOME/.local/bin/claude"; fi'
}

install_ai_profile_launchers

if [[ "$check_only" == true ]]; then
    docker exec --user "$container_user" --workdir "$workdir" "$container" "$shell_path" -lc \
        'printf "%s\n" "wave-container-shell-ok"; whoami; pwd; command -v claude-profile; command -v pclaude; command -v codex-profile; command -v pcodex; command -v pgemini; command -v pgrok; command -v pglm; test -d "$HOME/.claude-profiles"; test -d "$HOME/.chatgpt-profiles"; test -d "$HOME/.gemini-profiles"; test -d "$HOME/.grok-profiles"; test -d "$HOME/.glm-profiles"'
    exit 0
fi

set_wave_title() {
    printf '\033]0;%s\007' "$block_title"

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
    --user "$container_user" \
    --workdir "$workdir" \
    "$container" \
    "$shell_path" "${shell_args[@]}"
