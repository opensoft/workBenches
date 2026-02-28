#!/bin/bash

# Setup script for workBenches
# This script launches the interactive configuration manager

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure Docker is installed and running
ensure_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "Docker is not installed. It is required to build workBenches images."
        if [ -t 0 ]; then
            read -p "Attempt to install Docker now? [y/N]: " install_choice
            case "$install_choice" in
                [Yy]*)
                    if [ -f /etc/os-release ]; then
                        . /etc/os-release
                        OS=$ID
                    else
                        OS=$(uname -s)
                    fi
                    case "$OS" in
                        ubuntu|debian|pop)
                            echo "Running: sudo apt update && sudo apt install -y docker.io"
                            sudo apt update && sudo apt install -y docker.io || true
                            ;;
                        fedora|rhel|centos)
                            echo "Running: sudo dnf install -y docker"
                            sudo dnf install -y docker || true
                            ;;
                        alpine)
                            echo "Running: sudo apk add docker"
                            sudo apk add docker || true
                            ;;
                        Darwin|darwin|macos)
                            echo "Please install Docker Desktop for macOS:"
                            echo "  https://www.docker.com/products/docker-desktop/"
                            ;;
                        *)
                            echo "Please install Docker for your OS:"
                            echo "  https://docs.docker.com/get-docker/"
                            ;;
                    esac
                    ;;
                *)
                    ;;
            esac
        fi
        if ! command -v docker >/dev/null 2>&1; then
            echo "Docker is still not available. Please install it, then re-run ./setup.sh"
            exit 1
        fi
    fi

    if ! docker info >/dev/null 2>&1; then
        echo "Docker is installed but not running."
        if command -v systemctl >/dev/null 2>&1; then
            echo "Try: sudo systemctl start docker"
        else
            echo "Please start Docker Desktop or your Docker daemon."
        fi
        exit 1
    fi
}

# Parse arguments
USERNAME=${1:-$(whoami)}
if [ "$USERNAME" = "--user" ]; then
    USERNAME="${2:-$(whoami)}"
fi

# Shell environment setup (zsh + Powerlevel10k + Oh My Zsh)
if [ -x "${SCRIPT_DIR}/scripts/setup-shell.sh" ]; then
    "${SCRIPT_DIR}/scripts/setup-shell.sh"
    echo ""
fi

# Docker prerequisite
ensure_docker

# Ensure Layer 0 base image exists
if ! docker image inspect "workbench-base:$USERNAME" >/dev/null 2>&1; then
    echo "Layer 0 image not found. Building workbench-base:$USERNAME..."
    "${SCRIPT_DIR}/base-image/build.sh" --user "$USERNAME"
fi

# Call the interactive setup script
# Use TypeScript/OpenTUI version if Bun is available, otherwise fall back to Bash
run_interactive_setup() {
    local setup_ui_dir="${SCRIPT_DIR}/scripts/setup-ui"

    # Check if Bun is installed and setup-ui exists
    if command -v bun >/dev/null 2>&1 && [ -f "$setup_ui_dir/package.json" ]; then
        echo "Starting interactive setup (OpenTUI)..."

        # Install dependencies if needed
        if [ ! -d "$setup_ui_dir/node_modules" ]; then
            echo "Installing dependencies..."
            (cd "$setup_ui_dir" && bun install) || {
                echo "Failed to install dependencies, falling back to Bash UI..."
                "${SCRIPT_DIR}/scripts/interactive-setup.sh"
                return
            }
        fi

        # Run the TypeScript version
        (cd "$setup_ui_dir" && bun run start) || {
            echo "TypeScript UI failed, falling back to Bash UI..."
            "${SCRIPT_DIR}/scripts/interactive-setup.sh"
        }
    else
        # Fall back to Bash version
        if ! command -v bun >/dev/null 2>&1; then
            echo "Bun not found. Using Bash UI."
            echo "For the modern UI experience, install Bun: curl -fsSL https://bun.sh/install | bash"
        fi
        "${SCRIPT_DIR}/scripts/interactive-setup.sh"
    fi
}

run_interactive_setup

# If any dev benches are installed, build the Layer 1a base image
if command -v jq >/dev/null 2>&1 && [ -f "$SCRIPT_DIR/config/bench-config.json" ]; then
    dev_installed=false
    while IFS= read -r bench_path; do
        case "$bench_path" in
            devBenches/*)
                if [ -d "$SCRIPT_DIR/$bench_path" ]; then
                    dev_installed=true
                    break
                fi
                ;;
        esac
    done < <(jq -r '.benches | to_entries[] | .value.path // empty' "$SCRIPT_DIR/config/bench-config.json")

    if [ "$dev_installed" = true ] && [ -x "$SCRIPT_DIR/devBenches/setup.sh" ]; then
        echo ""
        echo "Dev benches detected. Building Layer 1a base image..."
        "$SCRIPT_DIR/devBenches/setup.sh" --user "$USERNAME"
    fi
fi

# If any admin benches are installed, build the Layer 1b base image
if command -v jq >/dev/null 2>&1 && [ -f "$SCRIPT_DIR/config/bench-config.json" ]; then
    admin_installed=false
    while IFS= read -r bench_path; do
        case "$bench_path" in
            adminBenches/*)
                if [ -d "$SCRIPT_DIR/$bench_path" ]; then
                    admin_installed=true
                    break
                fi
                ;;
        esac
    done < <(jq -r '.benches | to_entries[] | .value.path // empty' "$SCRIPT_DIR/config/bench-config.json")

    if [ "$admin_installed" = true ] && [ -x "$SCRIPT_DIR/adminBenches/setup.sh" ]; then
        echo ""
        echo "Admin benches detected. Building Layer 1b base image..."
        "$SCRIPT_DIR/adminBenches/setup.sh" --user "$USERNAME"
    fi
fi

# If any bio benches are installed, build the Layer 1c base image
if command -v jq >/dev/null 2>&1 && [ -f "$SCRIPT_DIR/config/bench-config.json" ]; then
    bio_installed=false
    while IFS= read -r bench_path; do
        case "$bench_path" in
            bioBenches/*)
                if [ -d "$SCRIPT_DIR/$bench_path" ]; then
                    bio_installed=true
                    break
                fi
                ;;
        esac
    done < <(jq -r '.benches | to_entries[] | .value.path // empty' "$SCRIPT_DIR/config/bench-config.json")

    if [ "$bio_installed" = true ] && [ -x "$SCRIPT_DIR/bioBenches/setup.sh" ]; then
        echo ""
        echo "Bio benches detected. Building Layer 1c base image..."
        "$SCRIPT_DIR/bioBenches/setup.sh" --user "$USERNAME"
    fi
fi
