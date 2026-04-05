#!/bin/bash
# Build script for Layer 1b: Admin/DevOps Base Image (adminbench-base)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="$SCRIPT_DIR/../.build-state.json"
STATE_KEY="adminbench-base"

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

calc_hash() {
    local -a files=("$SCRIPT_DIR/base-image/Dockerfile" "$SCRIPT_DIR/base-image/build.sh")
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "${files[@]}" 2>/dev/null | sha256sum | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "${files[@]}" 2>/dev/null | shasum -a 256 | awk '{print $1}'
    else
        echo ""
    fi
}

read_state() {
    local key="$1"
    if [ ! -f "$STATE_FILE" ]; then
        echo ""
        return
    fi
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$STATE_FILE" "$key" <<'PY'
import json
import sys

path = sys.argv[1]
key = sys.argv[2]
try:
    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
    print(data.get(key, ""))
except Exception:
    print("")
PY
    else
        echo ""
    fi
}

write_state() {
    local key="$1"
    local value="$2"
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$STATE_FILE" "$key" "$value" <<'PY'
import json
import os
import sys

path = sys.argv[1]
key = sys.argv[2]
value = sys.argv[3]

data = {}
if os.path.exists(path):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except Exception:
        data = {}

data[key] = value
tmp = path + ".tmp"
with open(tmp, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2, sort_keys=True)
os.replace(tmp, path)
PY
    fi
}

ensure_docker

echo "=========================================="
echo "Building Layer 1b: AdminBenches Base"
echo "=========================================="
echo ""
echo "Configuration:"
echo "  Username: $USERNAME"
echo ""

current_hash=$(calc_hash)
stored_hash=$(read_state "$STATE_KEY")
if [ -z "$current_hash" ]; then
    echo "Warning: sha256sum/shasum not found; skipping change detection."
fi
image_exists=0
if docker image inspect "adminbench-base:$USERNAME" >/dev/null 2>&1; then
    image_exists=1
fi

rebuild=0
if [ "$FORCE_REBUILD" -eq 1 ] || [ "$image_exists" -eq 0 ]; then
    rebuild=1
elif [ -n "$current_hash" ] && [ "$current_hash" != "$stored_hash" ]; then
    rebuild=1
fi

if [ "$rebuild" -eq 1 ]; then
    if [ "$FORCE_REBUILD" -eq 1 ]; then
        echo "Forcing rebuild of adminbench-base:$USERNAME..."
    elif [ "$image_exists" -eq 0 ]; then
        echo "adminbench-base:$USERNAME not found. Building..."
    else
        echo "Detected base-image changes. Rebuilding adminbench-base:$USERNAME..."
    fi
    "$SCRIPT_DIR/base-image/build.sh" --user "$USERNAME"
    if [ -n "$current_hash" ]; then
        write_state "$STATE_KEY" "$current_hash"
    fi
else
    echo "adminbench-base:$USERNAME is up to date."
fi
