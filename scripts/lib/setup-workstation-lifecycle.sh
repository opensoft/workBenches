#!/usr/bin/env bash
# Selected workstation changes only. Rendering never calls these helpers.
if ! declare -p setup_managed_harnesses >/dev/null 2>&1; then
    source "$(dirname "${BASH_SOURCE[0]}")/setup-tool-catalog.generated.sh"
fi
declare -A workstation_plan_actions=()
declare -A workstation_service_labels=([wsl]='WSL 2' [docker]=Docker [setup_tools]=Tools [vault]=Vault)
workstation_managed_id=''
workstation_plan_only=false
workstation_plan_any=false

workstation_service_key() {
    case "$1" in wsl|docker|setup_tools|vault) return 0 ;; *) return 1 ;; esac
}

workstation_known_key() {
    [[ -z "${setup_managed_harnesses[$1]:-}" ]] || return 0
    case "$1" in
        wsl|docker|setup_tools|vault|claude_cli|copilot_cli|codex_cli|antigravity_cli|opencode_cli|pi_cli|spec_kit|openspec|vscode|warp|wave|amnezia_vpn|0dcloud_vpn|host_shell|workspace_repo|ai_accounts|workbenches_account) return 0 ;;
        bench_?*) [[ "$1" =~ ^bench_[a-zA-Z0-9_+-]+$ ]] ;;
        *) return 1 ;;
    esac
}

workstation_plan_from_ui() {
    local key
    workstation_plan_actions=(); workstation_plan_only=true; workstation_plan_any=false
    for key in "${!component_checked[@]}"; do
        [[ "${component_checked[$key]}" == true && -n "${component_action[$key]}" ]] || continue
        if workstation_service_key "$key"; then
            workstation_plan_actions[$key]="${component_action[$key]}"; workstation_plan_any=true
        else workstation_plan_only=false; fi
    done
    [[ "$workstation_plan_any" == true ]] || workstation_plan_only=false
}

# Read the complete generated JSON before any prerequisite mutation. This
# restricted native reader also works when Docker/Tools/Python are missing.
workstation_plan_read() {
    local file=$1 mode bytes content body key action rest
    local envelope='^[[:space:]]*\{[[:space:]]*"schemaVersion"[[:space:]]*:[[:space:]]*1[[:space:]]*,[[:space:]]*"components"[[:space:]]*:[[:space:]]*\[(.*)\][[:space:]]*\}[[:space:]]*$'
    local entry='^[[:space:]]*\{[[:space:]]*"key"[[:space:]]*:[[:space:]]*"([a-zA-Z0-9_+-]+)"[[:space:]]*,[[:space:]]*"action"[[:space:]]*:[[:space:]]*"(install|update|uninstall)"[[:space:]]*\}[[:space:]]*(.*)$'
    local -A seen=()
    workstation_plan_actions=(); workstation_plan_only=true; workstation_plan_any=false
    [[ -f "$file" && ! -L "$file" && -O "$file" ]] || return 2
    mode=$(stat -c '%a' -- "$file" 2>/dev/null) || mode=$(stat -f '%Lp' "$file") || return 2
    [[ "$mode" =~ ^[0-7]+$ ]] && (( (8#$mode & 077) == 0 )) || return 2
    bytes=$(wc -c < "$file") || return 2
    ((bytes <= 65536)) || return 2
    # NUL is not JSON whitespace; a NUL delimiter must never be discarded.
    if IFS= read -r -d '' content < "$file"; then return 2; fi
    [[ "$content" =~ $envelope ]] || return 2
    body=${BASH_REMATCH[1]}
    while [[ "$body" == *[![:space:]]* ]]; do
        [[ "$body" =~ $entry ]] || return 2
        key=${BASH_REMATCH[1]}; action=${BASH_REMATCH[2]}; rest=${BASH_REMATCH[3]}
        workstation_known_key "$key" && [[ -z "${seen[$key]}" ]] || return 2
        seen[$key]=true
        case "$key" in host_shell|workspace_repo|ai_accounts|workbenches_account) [[ "$action" == install ]] || return 2 ;; esac
        if workstation_service_key "$key"; then
            [[ "$action" != update ]] || return 2
            workstation_plan_actions[$key]=$action; workstation_plan_any=true
        else workstation_plan_only=false; fi
        if [[ -z "$rest" ]]; then body=''
        else
            [[ "$rest" == ,* ]] || return 2
            body=${rest:1}; [[ "$body" == *[![:space:]]* ]] || return 2
        fi
    done
    [[ "$workstation_plan_any" == true ]] || workstation_plan_only=false
}

workstation_save_selection() {
    local target=$1 temporary key action separator=''
    [[ ! -L "$target" && ( ! -e "$target" || ( -f "$target" && -O "$target" ) ) ]] || return 2
    temporary=$(umask 077; mktemp "$target.tmp.XXXXXX") || return 1
    {
        printf '{"schemaVersion":1,"components":['
        for key in "${!component_checked[@]}"; do
            [[ "${component_checked[$key]}" == true && -n "${component_action[$key]}" ]] || continue
            action=${component_action[$key]}
            workstation_known_key "$key" && [[ "$action" =~ ^(install|update|uninstall)$ ]] || { rm -f -- "$temporary"; return 2; }
            printf '%s{"key":"%s","action":"%s"}' "$separator" "$key" "$action"
            separator=,
        done
        printf ']}\n'
    } > "$temporary" || { rm -f -- "$temporary"; return 1; }
    # Do not follow a destination replaced by a directory symlink after the check.
    if [[ "$(uname -s)" == Darwin ]]; then
        mv -fh -- "$temporary" "$target" || { rm -f -- "$temporary"; return 1; }
    else
        mv -fT -- "$temporary" "$target" || { rm -f -- "$temporary"; return 1; }
    fi
}

workstation_managed_record() {
    local key=$1 name role role_found record owner home running
    workstation_managed_id=''
    case "$key" in setup_tools) name=$WORKBENCHES_TOOLS_CONTAINER; role=tools ;; vault) name=$WORKBENCHES_VAULT_CONTAINER; role=vault ;; *) return 2 ;; esac
    record=$(workbenches_runtime_docker container inspect "$name" --format '{{index .Config.Labels "dev.opensoft.workbenches.role"}}|{{index .Config.Labels "dev.opensoft.workbenches.uid"}}|{{index .Config.Labels "dev.opensoft.workbenches.home"}}|{{.State.Running}}|{{.Id}}' 2>&1) || {
        case "$record" in *'No such container'*|*'No such object'*) return 3 ;; *) printf '%s\n' "$record" >&2; return 1 ;; esac
    }
    IFS='|' read -r role_found owner home running workstation_managed_id <<< "$record"
    [[ "$role_found" == "$role" && "$owner" == "$(id -u)" && "$home" == "$HOME" ]] || { echo "$name belongs to another installation; preserved." >&2; return 1; }
    [[ "$workstation_managed_id" =~ ^[0-9a-f]{64}$ ]] || { echo 'Invalid container identity; preserved.' >&2; return 1; }
}

workstation_remove_preflight() {
    local key=$1 status
    case "$key" in
        setup_tools|vault)
            if workstation_managed_record "$key"; then return 0; else status=$?; [[ "$status" == 3 ]]; fi ;;
        wsl)
            echo 'Remove WSL from Windows Settings outside this running distribution. Preserve/export your distributions first. No distribution was unregistered or changed.' >&2
            return 1 ;;
        docker)
            if workbenches_is_wsl || [[ "$(uname -s)" == Darwin ]]; then
                echo 'Docker Desktop uninstall deletes container data. Back up and uninstall from the host: https://docs.docker.com/desktop/uninstall/ . Nothing was removed.' >&2
                return 1
            fi
            workbenches_pin_docker || return 1
            case "$WORKBENCHES_DOCKER_ENDPOINT" in unix:///var/run/docker.sock|unix:///run/docker.sock) ;; *) echo 'Native Engine removal requires the local system Docker context; nothing was removed.' >&2; return 1 ;; esac
            case "$(workbenches_docker_os)" in
                arch|endeavouros|manjaro|omarchy) pacman -Q docker >/dev/null 2>&1 ;;
                ubuntu|debian|pop) dpkg-query -W -f='${Status}' docker.io 2>/dev/null | grep -q 'install ok installed' || dpkg-query -W -f='${Status}' docker-ce 2>/dev/null | grep -q 'install ok installed' ;;
                fedora|rhel|centos) rpm -q docker >/dev/null 2>&1 || rpm -q docker-ce >/dev/null 2>&1 ;;
                alpine) apk info -e docker >/dev/null 2>&1 ;;
                *) echo 'Uninstall this Docker provider with its host package manager after preserving its data.' >&2; return 1 ;;
            esac || { echo 'No supported native Docker Engine package found; nothing was removed.' >&2; return 1; } ;;
    esac
}

workstation_plan_preflight() {
    local key
    for key in vault setup_tools docker wsl; do
        [[ "${workstation_plan_actions[$key]}" == uninstall ]] || continue
        workstation_remove_preflight "$key" || return "$?"
    done
}

workstation_plan_prepare() {
    local key
    workstation_plan_preflight || return "$?"
    for key in wsl docker setup_tools vault; do
        [[ "${workstation_plan_actions[$key]}" == install ]] || continue
        echo "Installing/starting: ${workstation_service_labels[$key]}"
        case "$key" in
            wsl) [[ "$(workbenches_wsl_state)" == up ]] || { echo 'Configure WSL 2 from Administrator PowerShell outside this session, then rerun setup. No WSL restart was attempted.' >&2; return 1; } ;;
            docker)
                if command -v docker >/dev/null 2>&1; then ensure_docker --start || return "$?"
                else ensure_docker --install || return "$?"; fi ;;
            setup_tools) workbenches_tools_activate || return "$?" ;;
            vault) workbenches_vault_start || return "$?" ;;
        esac
    done
}

workstation_remove_managed() {
    local key=$1 name status
    if workstation_managed_record "$key"; then :; else status=$?; [[ "$status" == 3 ]] && return 0; return "$status"; fi
    # Pin the verified immutable ID so a replaced name cannot target a foreign container.
    name=$workstation_managed_id
    workbenches_runtime_docker container stop --time 10 "$name" >/dev/null || return "$?"
    workbenches_runtime_docker container rm "$name" >/dev/null
}

workstation_remove_docker() {
    local package os
    local -a packages=()
    workstation_remove_preflight docker || return "$?"
    os=$(workbenches_docker_os)
    case "$os" in
        arch|endeavouros|manjaro|omarchy)
            for package in docker docker-compose docker-buildx; do pacman -Q "$package" >/dev/null 2>&1 && packages+=("$package"); done
            sudo systemctl stop docker.socket docker.service || return "$?"
            sudo pacman -R -- "${packages[@]}" ;;
        ubuntu|debian|pop)
            for package in docker.io docker-ce docker-ce-cli docker-buildx-plugin docker-compose-plugin; do
                [[ "$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null)" == 'install ok installed' ]] && packages+=("$package")
            done
            sudo systemctl stop docker.socket docker.service || return "$?"
            sudo apt-get remove --no-auto-remove -- "${packages[@]}" ;;
        fedora|rhel|centos)
            for package in docker docker-ce docker-ce-cli docker-buildx-plugin docker-compose-plugin; do rpm -q "$package" >/dev/null 2>&1 && packages+=("$package"); done
            sudo systemctl stop docker.socket docker.service || return "$?"
            sudo dnf remove --setopt=clean_requirements_on_remove=False -- "${packages[@]}" ;;
        alpine) sudo rc-service docker stop && sudo apk del docker ;;
    esac
}

workstation_plan_finish() {
    local key
    for key in vault setup_tools docker wsl; do
        [[ "${workstation_plan_actions[$key]}" == uninstall ]] || continue
        echo "Removing: ${workstation_service_labels[$key]} (projects, images, volumes and credentials retained)"
        case "$key" in
            vault|setup_tools) workstation_remove_managed "$key" || return "$?" ;;
            docker) workstation_remove_docker || return "$?" ;;
            wsl) workstation_remove_preflight wsl; return 1 ;;
        esac
    done
}
