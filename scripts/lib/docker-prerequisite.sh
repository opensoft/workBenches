#!/usr/bin/env bash

# Host prerequisites only. No credentials are read or stored by this helper.
workbenches_is_wsl() {
    [[ -n "${WSL_DISTRO_NAME:-}" ]] || [[ "$(uname -r)" == *[Mm]icrosoft* ]]
}

workbenches_docker_info() {
    # Preserve shell Docker wrappers. Native daemon probes have a deadline so
    # a bad context cannot hang setup.
    if declare -F docker >/dev/null || ! command -v python3 >/dev/null 2>&1; then
        docker info >/dev/null 2>&1
    else
        python3 -c 'import subprocess, sys
try:
    result = subprocess.run(["docker", "info"], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=8)
    sys.exit(result.returncode if result.returncode >= 0 else 128 - result.returncode)
except (OSError, subprocess.TimeoutExpired):
    sys.exit(1)
' >/dev/null 2>&1
    fi
}

workbenches_docker_os() {
    if [[ -f /etc/os-release ]]; then
        (. /etc/os-release; printf '%s\n' "${ID:-unknown}")
    else
        uname -s
    fi
}

workbenches_install_docker() {
    if workbenches_is_wsl; then
        echo 'Use Docker Desktop with its WSL 2 backend and Linux containers.'
        echo 'After installation: start Docker Desktop, then enable this distribution in Settings > Resources > WSL Integration.'
        if command -v powershell.exe >/dev/null 2>&1; then
            powershell.exe -NoProfile -Command 'if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { Write-Host "Install Docker Desktop from https://docs.docker.com/desktop/setup/install/windows-install/"; exit 1 }; winget install --exact --id Docker.DockerDesktop --accept-source-agreements --accept-package-agreements; exit $LASTEXITCODE' || return "$?"
        else
            echo 'Install Docker Desktop for Windows, then press R to recheck:'
            echo '  https://docs.docker.com/desktop/setup/install/windows-install/'
            return 1
        fi
        return 0
    fi
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

    if workbenches_docker_info; then
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
                    if workbenches_docker_info; then
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
    if workbenches_is_wsl; then
        echo 'Start Docker Desktop, select Linux containers, and enable this distribution under Settings > Resources > WSL Integration.'
    elif [[ "$endpoint" == unix:///var/run/docker.sock || "$endpoint" == unix:///run/docker.sock ]] && [[ -t 0 ]] &&
         command -v usermod >/dev/null 2>&1 && getent group docker >/dev/null 2>&1 &&
         ! id -nG | tr ' ' '\n' | grep -qx docker; then
        echo 'The docker group grants administrator-equivalent access to this machine.'
        if ! read -r -p 'Add your user to the docker group? [y/N] (Q to cancel): ' choice; then return 130; fi
        case "$choice" in
            y|Y|yes|YES|Yes)
                sudo usermod -aG docker "$(id -un)" || return "$?"
                echo 'Sign out and back in to activate group access, then rerun ./setup.sh.'
                return 1 ;;
            q|Q) return 130 ;;
        esac
    fi
    echo "Check your Docker context, daemon and local Docker access permissions."
    echo "  https://docs.docker.com/engine/install/linux-postinstall/"
    return 1
}
