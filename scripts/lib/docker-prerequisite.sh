#!/usr/bin/env bash

# Host prerequisites only. No credentials are read or stored by this helper.
workbenches_docker_os() {
    if [[ -f /etc/os-release ]]; then
        (. /etc/os-release; printf '%s\n' "${ID:-unknown}")
    else
        uname -s
    fi
}

workbenches_install_docker() {
    case "$(workbenches_docker_os)" in
        ubuntu|debian|pop)
            echo "Installing Docker with sudo apt."
            sudo apt update && sudo apt install -y docker.io
            ;;
        fedora|rhel|centos)
            echo "Installing Docker with sudo dnf."
            sudo dnf install -y docker
            ;;
        alpine)
            echo "Installing Docker with sudo apk."
            sudo apk add docker
            ;;
        arch|endeavouros|manjaro|omarchy)
            echo "Installing Docker, Compose and Buildx with sudo pacman."
            sudo pacman -S --needed docker docker-compose docker-buildx
            ;;
        Darwin|darwin|macos)
            echo "Install Docker Desktop for macOS, then rerun ./setup.sh:"
            echo "  https://www.docker.com/products/docker-desktop/"
            return 1
            ;;
        *)
            echo "Install Docker for your OS, then rerun ./setup.sh:"
            echo "  https://docs.docker.com/get-docker/"
            return 1
            ;;
    esac
}

ensure_docker() {
    local choice status endpoint
    if ! command -v docker >/dev/null 2>&1; then
        echo "Docker is not installed. It is required for workBenches images and container credential recovery."
        if [[ ! -t 0 ]]; then
            echo "Install Docker in an interactive terminal, then rerun ./setup.sh."
            return 1
        fi
        if ! read -r -p "Attempt to install Docker now? [y/N] (Q to cancel): " choice; then
            return 130
        fi
        case "$choice" in
            y|Y|yes|YES|Yes) ;;
            *) echo "Docker installation declined; setup stopped."; return 130 ;;
        esac
        # Leave local password entry to sudo; never capture it in setup.
        if workbenches_install_docker; then
            :
        else
            status=$?
            echo "Docker installation did not complete; setup stopped."
            return "$status"
        fi
        if ! command -v docker >/dev/null 2>&1; then
            echo "Docker is still unavailable. Install it, then rerun ./setup.sh."
            return 1
        fi
    fi

    if docker info >/dev/null 2>&1; then
        echo "Docker is available and its daemon is accessible."
        return 0
    else
        status=$?
        case "$status" in 130|143) return "$status" ;; esac
    fi

    # Offer to start only the selected, local system daemon. A remote or
    # rootless Docker context must not cause changes to the system daemon.
    if [[ -n "${DOCKER_CONTEXT:-}" ]]; then
        endpoint="$(docker context inspect "$DOCKER_CONTEXT" --format '{{.Endpoints.docker.Host}}' 2>/dev/null)" || endpoint=""
    elif [[ -n "${DOCKER_HOST:-}" ]]; then
        endpoint="$DOCKER_HOST"
    else
        endpoint="$(docker context inspect --format '{{.Endpoints.docker.Host}}' 2>/dev/null)" || endpoint=""
    fi
    if [[ "$endpoint" == unix:///var/run/docker.sock || "$endpoint" == unix:///run/docker.sock ]] &&
       command -v systemctl >/dev/null 2>&1 &&
       [[ "$(systemctl show -p LoadState --value docker.service 2>/dev/null)" == loaded ]] &&
       ! systemctl is-active --quiet docker.service && [[ -t 0 ]]; then
        if ! read -r -p "Start the local Docker service now? [y/N] (Q to cancel): " choice; then
            return 130
        fi
        case "$choice" in
            y|Y|yes|YES|Yes)
                if sudo systemctl start docker.service; then
                    if docker info >/dev/null 2>&1; then
                        echo "Docker is available and its daemon is accessible."
                        return 0
                    else
                        status=$?
                        case "$status" in 130|143) return "$status" ;; esac
                    fi
                else
                    status=$?
                    echo "Starting Docker did not complete; setup stopped."
                    return "$status"
                fi
                ;;
            *) echo "Starting Docker declined; setup stopped."; return 130 ;;
        esac
    fi

    echo "Docker is installed but its daemon is not accessible to this user. Setup stopped."
    echo "Check your Docker context, daemon and local Docker access permissions."
    echo "  https://docs.docker.com/engine/install/linux-postinstall/"
    return 1
}
