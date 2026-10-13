#!/bin/bash
# Build script for Layer 1: Developer Base Image (dev-bench-base)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_DIR/scripts/lib/image-names.sh"
BASE_IMAGE="$(family_base_image dev)"

# Ensure Docker is installed and running
ensure_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "Docker is not installed. It is required to build workBench images."
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
USERNAME="$(whoami)"
FORCE_REBUILD=0
while [ $# -gt 0 ]; do
    case "$1" in
        --user)
            USERNAME="${2:-$USERNAME}"
            shift 2
            ;;
        --force)
            FORCE_REBUILD=1
            shift
            ;;
        *)
            USERNAME="$1"
            shift
            ;;
    esac
done


ensure_docker

# Vibe Annotations is one host-local MCP service shared by every language
# bench. Keep it outside individual bench lifecycles so the Windows browser
# extension has exactly one stable localhost:3846 endpoint.
if [ -x "$REPO_DIR/scripts/ensure-vibe-annotations.sh" ]; then
    "$REPO_DIR/scripts/ensure-vibe-annotations.sh" || \
        echo "Warning: shared Vibe Annotations service setup failed."
fi
if [ -x "$REPO_DIR/scripts/workbenches-mcp-sync" ]; then
    "$REPO_DIR/scripts/workbenches-mcp-sync" put-http \
        opensoft \
        vibe-annotations \
        http://127.0.0.1:3846/mcp \
        http://host.docker.internal:3846/mcp || \
        echo "Warning: shared Vibe Annotations MCP registry setup failed."
fi

echo "=========================================="
echo "Building Layer 1a: DevBenches Base"
echo "=========================================="
echo ""
echo "Configuration:"
echo "  Tag: $BASE_IMAGE (user-agnostic)"
echo ""

if [ "$FORCE_REBUILD" -eq 0 ] && python3 "$REPO_DIR/scripts/shared-images.py" ensure dev; then
    tag_family_base_legacy_alias dev
    echo "$BASE_IMAGE is ready."
else
    image_status=$?
    case "$image_status" in 130|143) exit "$image_status" ;; esac
    echo "Building the developer image from local sources..."
    "$SCRIPT_DIR/base-image/build.sh" --user "$USERNAME"
fi
