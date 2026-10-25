#!/usr/bin/env bash
# Docker-only bootstrap for setup tools and cloud file access. No host packages.
WORKBENCHES_TOOLS_ROOT="${WORKBENCHES_TOOLS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
WORKBENCHES_TOOLS_CONTAINER="${WORKBENCHES_TOOLS_CONTAINER:-workbenches-tools}"
WORKBENCHES_TOOLS_IMAGE="${WORKBENCHES_TOOLS_IMAGE:-workbenches/tools:2026.10.25-v1}"
WORKBENCHES_SERVICES_NETWORK="${WORKBENCHES_SERVICES_NETWORK:-workbenches-services-$(id -u)}"
WORKBENCHES_VAULT_CONTAINER="${WORKBENCHES_VAULT_CONTAINER:-workbenches-vault}"
WORKBENCHES_VAULT_IMAGE="${WORKBENCHES_VAULT_IMAGE:-workbenches/vault:2026.10.15-v1}"

workbenches_vault_jobs() {
    printf '%s/workbenches/vault/jobs\n' "${XDG_CACHE_HOME:-$HOME/.cache}"
}

workbenches_vault_state() {
    workbenches_managed_state "$WORKBENCHES_VAULT_CONTAINER" vault "${1:-}"
}

workbenches_setup_os() {
    if [[ -n "${WORKBENCHES_HOST_OS_LABEL:-}" ]]; then printf '%s\n' "$WORKBENCHES_HOST_OS_LABEL"; return; fi
    local label system release distro
    system="$(uname -s)"; release="$(uname -r)"
    label=$system
    case "$system" in Darwin) label=macOS ;; MINGW*|MSYS*|CYGWIN*) label=Windows ;; esac
    if [[ "$system" == Linux && ( -n "${WSL_DISTRO_NAME:-}" || "${release,,}" == *microsoft* ) ]]; then label='Windows / WSL'; fi
    if [[ "$system" == Linux && -f /etc/os-release ]]; then
        distro="$(. /etc/os-release; printf '%s' "${PRETTY_NAME:-}")"
        [[ -z "$distro" ]] || label+=" — $distro"
    fi
    printf '%s\n' "$label"
}

workbenches_wsl_state() {
    local release line
    release="$(uname -r)"
    if [[ "${release,,}" == *microsoft-standard* ]]; then printf 'up\n'; return; fi
    if [[ -n "${WSL_DISTRO_NAME:-}" ]] && command -v wsl.exe >/dev/null 2>&1; then
        while IFS= read -r line; do
            line="${line#"${line%%[![:space:]]*}"}"
            line="${line#\*}"; line="${line#"${line%%[![:space:]]*}"}"
            if [[ "$line" == "$WSL_DISTRO_NAME "* && "$line" =~ [[:space:]]2$ ]]; then printf 'up\n'; return; fi
        done < <(workbenches_bounded 8 wsl.exe --list --verbose 2>/dev/null | tr -d '\000\r')
    fi
    printf 'down\n'
}

# Shared labels for the dependency-free bootstrap screen and full TUI.
workbenches_requirement_action() {
    local key=$1 state=$2 account="${3:-}"
    if [[ "$key" == wsl ]]; then
        if [[ "$state" == up ]]; then printf Check; else printf Configure; fi
        return
    fi
    case "$state" in
        missing) printf Install ;;
        down) printf Start ;;
        up)
            if [[ "$key" == vault ]]; then
                if [[ "$account" == loading ]]; then printf Loading
                elif [[ "$account" == 'signed in' ]]; then printf 'Sign out'; else printf Connect; fi
            else
                printf Check
            fi ;;
        loading) printf Loading ;;
        *) printf Check ;;
    esac
}

workbenches_requirement_rows() {
    local state label
    label="$(workbenches_setup_os)"
    if [[ "$label" == Windows* ]]; then
        state="$(workbenches_wsl_state)"
        printf 'wsl\tWSL 2\t%s\tRun setup inside your WSL 2 distribution.\n' "$state"
    fi
    state="$(workbenches_docker_state)"
    case "$state" in
        up) printf 'docker\tDocker\tup\tLinux containers and daemon access are available.\n' ;;
        missing) printf 'docker\tDocker\tmissing\tInstall Docker to run workBenches.\n' ;;
        *) printf 'docker\tDocker\tdown\tStart Docker, select Linux containers, or fix daemon access.\n' ;;
    esac
    printf 'setup_tools\tTools\t%s\tPython 3, jq, Git, curl and Rclone run in workBenches/tools.\n' "$(workbenches_tools_state "$state")"
    printf 'vault\tVault\t%s\tOptional credential-access helper; sign-in and unlock are separate.\n' "$(workbenches_vault_state "$state")"
}

workbenches_bounded() {
    local seconds=$1; shift
    "$@" &
    local command_pid=$! result timer
    (sleep "$seconds"; kill -TERM "$command_pid" 2>/dev/null) </dev/null >/dev/null 2>&1 &
    timer=$!
    wait "$command_pid"; result=$?
    kill "$timer" 2>/dev/null || true
    wait "$timer" 2>/dev/null || true
    return "$result"
}

workbenches_runtime_docker() {
    if [[ -n "${WORKBENCHES_DOCKER_ENDPOINT:-}" ]]; then
        docker --host "$WORKBENCHES_DOCKER_ENDPOINT" "$@"
    else
        docker "$@"
    fi
}

workbenches_pin_docker() {
    local endpoint
    if [[ -n "${DOCKER_CONTEXT:-}" ]]; then
        endpoint="$(workbenches_bounded 8 docker context inspect "$DOCKER_CONTEXT" --format '{{.Endpoints.docker.Host}}' 2>/dev/null)" || return 1
    elif [[ -n "${DOCKER_HOST:-}" ]]; then
        endpoint=$DOCKER_HOST
    else
        endpoint="$(workbenches_bounded 8 docker context inspect --format '{{.Endpoints.docker.Host}}' 2>/dev/null)" || return 1
    fi
    [[ "$endpoint" == unix:///* ]] || { echo 'Tools requires the selected local Docker engine.' >&2; return 1; }
    WORKBENCHES_DOCKER_ENDPOINT=$endpoint
    export WORKBENCHES_DOCKER_ENDPOINT
}

workbenches_docker_state() {
    if ! command -v docker >/dev/null 2>&1; then printf 'missing\n'; return; fi
    local kind
    kind="$(workbenches_bounded 8 docker info --format '{{.OSType}}' 2>/dev/null)" || { printf 'down\n'; return; }
    if [[ "$kind" == linux ]]; then printf 'up\n'; else printf 'down\n'; fi
}

workbenches_managed_state() {
    local name=$1 role=$2 record owner user running health home
    [[ "${3:-$(workbenches_docker_state)}" == up ]] || { printf 'down\n'; return; }
    record="$(workbenches_bounded 8 workbenches_runtime_docker container inspect "$name" --format '{{index .Config.Labels "dev.opensoft.workbenches.role"}}|{{index .Config.Labels "dev.opensoft.workbenches.uid"}}|{{.State.Running}}|{{if .State.Health}}{{.State.Health.Status}}{{end}}|{{index .Config.Labels "dev.opensoft.workbenches.home"}}' 2>&1)" || {
        case "$record" in *'No such container'*|*'No such object'*) printf 'missing\n' ;; *) printf 'down\n' ;; esac
        return
    }
    IFS='|' read -r owner user running health home <<< "$record"
    if [[ "$owner" == "$role" && "$user" == "$(id -u)" && "$home" == "$HOME" && "$running" == true && "$health" == healthy ]]; then
        printf 'up\n'
    else
        printf 'down\n'
    fi
}

workbenches_tools_state() {
    workbenches_managed_state "$WORKBENCHES_TOOLS_CONTAINER" tools "${1:-}"
}

workbenches_tools_image_fingerprint() {
    cksum "$WORKBENCHES_TOOLS_ROOT/tools-container/"{Dockerfile,workbenches_host.py,host-command,rclone_login.py,rclone-open} | cksum | { read -r checksum rest; printf '%s\n' "$checksum"; }
}

workbenches_tools_fingerprint() {
    local checksum rest
    IFS=' ' read -r checksum rest < <({ cksum "$WORKBENCHES_TOOLS_ROOT/tools-container/"{Dockerfile,workbenches_host.py,host-command,rclone_login.py,rclone-open}; printf '%s\n' 'runtime-v3' "$HOME" "$WORKBENCHES_TOOLS_ROOT" "${TMPDIR:-/tmp}" "${SSH_AUTH_SOCK:-}" "${XDG_CONFIG_HOME:-}" "${XDG_CACHE_HOME:-}" "${XDG_DATA_HOME:-}"; } | cksum)
    printf '%s\n' "$checksum"
}

workbenches_services_network() {
    local owner
    owner="$(workbenches_runtime_docker network inspect "$WORKBENCHES_SERVICES_NETWORK" --format '{{index .Labels "dev.opensoft.workbenches.uid"}}' 2>/dev/null)" || owner=''
    if [[ -n "$owner" ]]; then
        [[ "$owner" == "$(id -u)" ]] || { echo 'The setup network belongs to another installation.' >&2; return 1; }
    else
        workbenches_runtime_docker network create \
            --label "dev.opensoft.workbenches.uid=$(id -u)" \
            --opt "com.docker.network.driver.mtu=${WORKBENCHES_SERVICES_MTU:-1280}" \
            "$WORKBENCHES_SERVICES_NETWORK" >/dev/null || return "$?"
    fi
}

workbenches_tools_start() {
    [[ "$(workbenches_docker_state)" == up ]] || { echo 'Docker must be Up before Tools can start.' >&2; return 1; }
    workbenches_pin_docker || return 1
    local expected image_expected record role owner fingerprint home socket socket_group system ready=false
    expected="$(workbenches_tools_fingerprint)" || return 1
    image_expected="$(workbenches_tools_image_fingerprint)" || return 1
    record="$(workbenches_runtime_docker container inspect "$WORKBENCHES_TOOLS_CONTAINER" --format '{{index .Config.Labels "dev.opensoft.workbenches.role"}}|{{index .Config.Labels "dev.opensoft.workbenches.uid"}}|{{index .Config.Labels "dev.opensoft.workbenches.fingerprint"}}|{{index .Config.Labels "dev.opensoft.workbenches.home"}}' 2>/dev/null)" || record=''
    if [[ -n "$record" ]]; then
        IFS='|' read -r role owner fingerprint home <<< "$record"
        [[ "$role" == tools && "$owner" == "$(id -u)" && "$home" == "$HOME" ]] || { echo 'Tools container name belongs to another installation; it was preserved.' >&2; return 1; }
        if [[ "$fingerprint" != "$expected" ]]; then
            workbenches_runtime_docker container stop --time 10 "$WORKBENCHES_TOOLS_CONTAINER" >/dev/null || return 1
            workbenches_runtime_docker container rm "$WORKBENCHES_TOOLS_CONTAINER" >/dev/null || return 1
            record=''
        fi
    fi
    if [[ -z "$record" ]]; then
        fingerprint="$(workbenches_runtime_docker image inspect "$WORKBENCHES_TOOLS_IMAGE" --format '{{index .Config.Labels "dev.opensoft.workbenches.fingerprint"}}' 2>/dev/null)" || fingerprint=''
        if [[ "$fingerprint" != "$image_expected" ]]; then
            echo 'Preparing workBenches/tools…' >&2
            workbenches_runtime_docker build --network "${WORKBENCHES_TOOLS_BUILD_NETWORK:-host}" \
                --label "dev.opensoft.workbenches.fingerprint=$image_expected" \
                --tag "$WORKBENCHES_TOOLS_IMAGE" "$WORKBENCHES_TOOLS_ROOT/tools-container" >&2 || return "$?"
        fi
        workbenches_services_network || return "$?"
        socket="${WORKBENCHES_DOCKER_ENDPOINT#unix://}"
        system="$(workbenches_runtime_docker info --format '{{.OperatingSystem}}')" || return 1
        if [[ "$system" == *'Docker Desktop'* ]]; then
            socket=/var/run/docker.sock
            socket_group=0
            # WSL exposes Desktop's real Linux socket group, which need not
            # be root. macOS's host socket group does not describe the VM socket.
            if [[ "$(uname -s)" == Linux ]]; then
                socket_group="$(stat -c %g "${WORKBENCHES_DOCKER_ENDPOINT#unix://}")" || return 1
            fi
        else
            socket_group="$(stat -c %g "$socket" 2>/dev/null || stat -f %g "$socket" 2>/dev/null)" || return 1
        fi
        local identity_root="${XDG_CACHE_HOME:-$HOME/.cache}/workbenches/tools/identity"
        (umask 077; mkdir -p "$identity_root") || return 1
        (umask 077
         { if [[ "$(id -u)" != 0 ]]; then printf 'root:x:0:0:root:/root:/bin/sh\n'; fi
           printf '%s:x:%s:%s:workBenches:%s:/bin/bash\n' "$(id -un)" "$(id -u)" "$(id -g)" "$HOME";
         } > "$identity_root/passwd"
         { if [[ "$(id -g)" != 0 ]]; then printf 'root:x:0:\n'; fi
           printf '%s:x:%s:\n' "$(id -gn)" "$(id -g)";
         } > "$identity_root/group"
        ) || return 1
        local -a mounts=(--mount "type=bind,src=$HOME,dst=$HOME"
            --mount "type=bind,src=$identity_root/passwd,dst=/etc/passwd,readonly"
            --mount "type=bind,src=$identity_root/group,dst=/etc/group,readonly")
        case "$WORKBENCHES_TOOLS_ROOT/" in "$HOME/"*) ;; *) mounts+=(--mount "type=bind,src=$WORKBENCHES_TOOLS_ROOT,dst=$WORKBENCHES_TOOLS_ROOT") ;; esac
        local temporary_root="${TMPDIR:-/tmp}"
        case "$temporary_root/" in "$HOME/"*) ;; *) mounts+=(--mount "type=bind,src=$temporary_root,dst=$temporary_root") ;; esac
        local extra
        for extra in "${XDG_CONFIG_HOME:-}" "${XDG_CACHE_HOME:-}" "${XDG_DATA_HOME:-}"; do
            [[ -n "$extra" && -d "$extra" ]] || continue
            case "$extra/" in "$HOME/"*|"$temporary_root/"*|"$WORKBENCHES_TOOLS_ROOT/"*) continue ;; esac
            mounts+=(--mount "type=bind,src=$extra,dst=$extra")
        done
        if [[ -n "${SSH_AUTH_SOCK:-}" && -S "$SSH_AUTH_SOCK" ]]; then
            local agent_source="$SSH_AUTH_SOCK"
            [[ "$system" != *'Docker Desktop'* ]] || agent_source=/run/host-services/ssh-auth.sock
            mounts+=(--mount "type=bind,src=$agent_source,dst=$SSH_AUTH_SOCK")
        fi
        workbenches_runtime_docker create --name "$WORKBENCHES_TOOLS_CONTAINER" \
            --network "$WORKBENCHES_SERVICES_NETWORK" \
            --label dev.opensoft.workbenches.role=tools --label "dev.opensoft.workbenches.uid=$(id -u)" \
            --label "dev.opensoft.workbenches.home=$HOME" \
            --label "dev.opensoft.workbenches.fingerprint=$expected" \
            --user "$(id -u):$(id -g)" --group-add "$socket_group" \
            --read-only --cap-drop ALL --security-opt no-new-privileges \
            --mount "type=bind,src=$socket,dst=$socket" "${mounts[@]}" \
            --env "HOME=$HOME" --env "USER=${USER:-$(id -un)}" \
            --env "DOCKER_HOST=unix://$socket" \
            "$WORKBENCHES_TOOLS_IMAGE" >/dev/null || return "$?"
    fi
    workbenches_runtime_docker container start "$WORKBENCHES_TOOLS_CONTAINER" >/dev/null || return "$?"
    local attempt
    for ((attempt=0; attempt<20; attempt++)); do
        if [[ "$(workbenches_tools_state)" == up ]]; then ready=true; break; fi
        sleep 0.5
    done
    [[ "$ready" == true ]] || { echo 'Tools is Down: its health check did not pass.' >&2; return 1; }
    local engine tools_engine
    engine="$(workbenches_runtime_docker info --format '{{.ID}}')" || return 1
    tools_engine="$(workbenches_runtime_docker exec "$WORKBENCHES_TOOLS_CONTAINER" docker info --format '{{.ID}}')" || return 1
    [[ -n "$engine" && "$engine" == "$tools_engine" ]] || { echo 'Tools cannot access the selected Docker engine.' >&2; return 1; }
}

workbenches_tools_activate() {
    # Native transport exists only for focused unit suites, which test the
    # installer independently of Docker. Production always uses the container.
    [[ "${WORKBENCHES_TEST_NATIVE_TOOLS:-}" != 1 ]] || return 0
    workbenches_tools_start || return "$?"
    workbenches_tools_use_shims
}

# Adopt an already verified runtime without re-running container checks.
workbenches_tools_use_shims() {
    [[ "${WORKBENCHES_TEST_NATIVE_TOOLS:-}" != 1 ]] || return 0
    WORKBENCHES_NATIVE_PATH="${WORKBENCHES_NATIVE_PATH:-$PATH}"
    WORKBENCHES_TOOLS_BIN="${XDG_CACHE_HOME:-$HOME/.cache}/workbenches/tools/bin"
    mkdir -p "$WORKBENCHES_TOOLS_BIN" || return 1
    local tool
    for tool in python3 jq git curl rclone; do
        ln -sf "$WORKBENCHES_TOOLS_ROOT/scripts/tools-command.sh" "$WORKBENCHES_TOOLS_BIN/$tool" || return 1
    done
    export WORKBENCHES_TOOLS_ROOT WORKBENCHES_TOOLS_CONTAINER WORKBENCHES_NATIVE_PATH WORKBENCHES_TOOLS_BIN
    WORKBENCHES_HOST_OS_LABEL="$(workbenches_setup_os)"
    export WORKBENCHES_HOST_OS_LABEL
    export WORKBENCHES_CONTAINER_TOOLS=1
    case "$WORKBENCHES_HOST_OS_LABEL" in
        macOS*) export LANES_OS=macos; export BROWSER="${BROWSER:-open}" ;; Windows*) export LANES_OS=wsl ;; *) export LANES_OS=linux ;;
    esac
    export PATH="$WORKBENCHES_TOOLS_BIN:$WORKBENCHES_NATIVE_PATH"
}

workbenches_vault_start() {
    [[ "$(workbenches_docker_state)" == up ]] || { echo 'Docker must be Up before Vault can start.' >&2; return 1; }
    workbenches_pin_docker || return 1
    local expected image_expected rest record role owner fingerprint home jobs attempt
    IFS=' ' read -r image_expected rest < <(cksum "$WORKBENCHES_TOOLS_ROOT/credential-container/"{Dockerfile,credential_recovery.py} | cksum)
    jobs="$(workbenches_vault_jobs)"
    IFS=' ' read -r expected rest < <(printf '%s\n' "$image_expected" "$jobs" 'vault-runtime-v1' | cksum)
    record="$(workbenches_runtime_docker container inspect "$WORKBENCHES_VAULT_CONTAINER" --format '{{index .Config.Labels "dev.opensoft.workbenches.role"}}|{{index .Config.Labels "dev.opensoft.workbenches.uid"}}|{{index .Config.Labels "dev.opensoft.workbenches.fingerprint"}}|{{index .Config.Labels "dev.opensoft.workbenches.home"}}' 2>/dev/null)" || record=''
    if [[ -n "$record" ]]; then
        IFS='|' read -r role owner fingerprint home <<< "$record"
        [[ "$role" == vault && "$owner" == "$(id -u)" && "$home" == "$HOME" ]] || { echo 'Vault container name belongs to another installation; it was preserved.' >&2; return 1; }
        if [[ "$fingerprint" != "$expected" ]]; then
            workbenches_runtime_docker container stop --time 10 "$WORKBENCHES_VAULT_CONTAINER" >/dev/null || return 1
            workbenches_runtime_docker container rm "$WORKBENCHES_VAULT_CONTAINER" >/dev/null || return 1
            record=''
        fi
    fi
    if [[ -z "$record" ]]; then
        fingerprint="$(workbenches_runtime_docker image inspect "$WORKBENCHES_VAULT_IMAGE" --format '{{index .Config.Labels "dev.opensoft.workbenches.fingerprint"}}' 2>/dev/null)" || fingerprint=''
        if [[ "$fingerprint" != "$image_expected" ]]; then
            echo 'Preparing workBenches/vault…' >&2
            workbenches_runtime_docker build --network "${WORKBENCHES_TOOLS_BUILD_NETWORK:-host}" \
                --target vault --label "dev.opensoft.workbenches.fingerprint=$image_expected" \
                --tag "$WORKBENCHES_VAULT_IMAGE" "$WORKBENCHES_TOOLS_ROOT/credential-container" >&2 || return "$?"
        fi
        workbenches_services_network || return "$?"
        jobs="$(workbenches_vault_jobs)"
        (umask 077; mkdir -p "$jobs") || return 1
        workbenches_runtime_docker create --name "$WORKBENCHES_VAULT_CONTAINER" \
            --network "$WORKBENCHES_SERVICES_NETWORK" \
            --label dev.opensoft.workbenches.role=vault --label "dev.opensoft.workbenches.uid=$(id -u)" \
            --label "dev.opensoft.workbenches.home=$HOME" \
            --label "dev.opensoft.workbenches.fingerprint=$expected" \
            --user "$(id -u):$(id -g)" --read-only --cap-drop ALL --security-opt no-new-privileges \
            --tmpfs /tmp:rw,nosuid,nodev,mode=1777,size=512m \
            --mount "type=bind,src=$jobs,dst=$jobs" "$WORKBENCHES_VAULT_IMAGE" >/dev/null || return "$?"
    fi
    workbenches_runtime_docker container start "$WORKBENCHES_VAULT_CONTAINER" >/dev/null || return "$?"
    for ((attempt=0; attempt<40; attempt++)); do
        [[ "$(workbenches_vault_state)" != up ]] || return 0
        sleep 0.5
    done
    echo 'Vault is Down: its health check did not pass.' >&2
    return 1
}
