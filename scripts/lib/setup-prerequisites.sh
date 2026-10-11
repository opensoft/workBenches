#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/docker-prerequisite.sh"
source "$(dirname "${BASH_SOURCE[0]}")/setup-prompts.sh"

ensure_setup_dependencies() {
    local dependency choice status
    local -a missing=()
    for dependency in python3 jq git curl; do
        command -v "$dependency" >/dev/null 2>&1 || missing+=("$dependency")
    done
    [[ ${#missing[@]} -gt 0 ]] || return 0
    echo "Missing setup dependencies: ${missing[*]}"
    [[ -t 0 ]] || return 1
    setup_read 'Install these dependencies now? [y/N]' choice
    [[ "${choice,,}" == y || "${choice,,}" == yes ]] || return 130
    case "$(workbenches_docker_os)" in
        arch|endeavouros|manjaro|omarchy) sudo pacman -S --needed "${missing[@]/python3/python}" ;;
        ubuntu|debian|pop) sudo apt update && sudo apt install -y "${missing[@]}" ;;
        fedora|rhel|centos) sudo dnf install -y "${missing[@]}" ;;
        alpine) sudo apk add "${missing[@]}" ;;
        Darwin|darwin|macos) brew install "${missing[@]/python3/python}" ;;
        *) echo "Install ${missing[*]} with your OS package manager, then rerun setup."; return 1 ;;
    esac
    status=$?
    setup_propagate_cancel "$status"
    [[ "$status" == 0 ]] || return "$status"
    for dependency in "${missing[@]}"; do command -v "$dependency" >/dev/null 2>&1 || return 1; done
}
