#!/bin/bash
# ensure-layer3.sh — Ensure Layer 3 (user personalization) image exists and is up-to-date
#
# Called from devcontainer.json initializeCommand before the container starts.
# Fast path: if the user image already exists and is newer than the base, exits in <1s.
#
# Usage:
#   bash ensure-layer3.sh --base cpp-bench:latest --chown /opt/vcpkg
#   bash ensure-layer3.sh --base go-bench:latest --chown /go
#   bash ensure-layer3.sh --base frappe-bench:latest --chown /opt/frappe-bench-template

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Defaults
BASE_IMAGE=""
EXTRA_CHOWN=""
USERNAME=$(whoami)
USER_UID=$(id -u)
USER_GID=$(id -g)
DOCKER_SOCKET_GID=""
FORCE=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --base) BASE_IMAGE="$2"; shift 2 ;;
        --chown) EXTRA_CHOWN="$2"; shift 2 ;;
        --user) USERNAME="$2"; shift 2 ;;
        --force) FORCE=true; shift ;;
        -h|--help)
            echo "Usage: $0 --base <image>:latest [--chown \"dir1 dir2\"] [--force]"
            echo ""
            echo "Ensures a Layer 3 (user) image exists for the given base."
            echo "Skips rebuild if the user image is already up-to-date."
            echo ""
            echo "Options:"
            echo "  --base IMAGE    Base Layer 2 image (required). e.g. cpp-bench:latest"
            echo "  --chown DIRS    Space-separated dirs to chown to user in Layer 3"
            echo "  --user NAME     Username (default: \$(whoami))"
            echo "  --force         Force rebuild even if image is up-to-date"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [ -z "$BASE_IMAGE" ]; then
    echo -e "${RED}✗ Error: --base is required${NC}"
    echo "Run $0 --help for usage"
    exit 1
fi

if [ -S /var/run/docker.sock ]; then
    DOCKER_SOCKET_GID=$(stat -c '%g' /var/run/docker.sock 2>/dev/null || true)
fi

# Derive the user image name: replace tag with username
# e.g. cpp-bench:latest -> cpp-bench:brett
BASE_NAME="${BASE_IMAGE%%:*}"
USER_IMAGE="${BASE_NAME}:${USERNAME}"

echo -e "${CYAN}ensure-layer3: Checking ${USER_IMAGE}...${NC}"

# Check if base image exists
if ! docker image inspect "$BASE_IMAGE" >/dev/null 2>&1; then
    echo -e "${RED}✗ Base image '$BASE_IMAGE' not found!${NC}"
    echo "  Build the Layer 2 image first, or run a cascade rebuild."
    exit 1
fi

# Fast path: check if user image exists and is newer than base
if [ "$FORCE" = false ] && docker image inspect "$USER_IMAGE" >/dev/null 2>&1; then
    BASE_CREATED=$(docker inspect --format '{{.Created}}' "$BASE_IMAGE" 2>/dev/null)
    USER_CREATED=$(docker inspect --format '{{.Created}}' "$USER_IMAGE" 2>/dev/null)

    if [[ -n "$BASE_CREATED" && -n "$USER_CREATED" ]]; then
        # Compare timestamps (ISO 8601 strings sort lexicographically)
        if [[ "$USER_CREATED" > "$BASE_CREATED" ]]; then
            # Verify the user actually exists inside the image
            if docker run --rm "$USER_IMAGE" getent passwd "$USERNAME" >/dev/null 2>&1; then
                if [ -n "$DOCKER_SOCKET_GID" ] && ! docker run --rm --entrypoint "" "$USER_IMAGE" sh -c "id -G $USERNAME | tr ' ' '\n' | grep -qx '$DOCKER_SOCKET_GID'" >/dev/null 2>&1; then
                    echo -e "${YELLOW}⟳ Docker socket group '$DOCKER_SOCKET_GID' missing from ${USER_IMAGE}, rebuilding...${NC}"
                else
                    echo -e "${GREEN}✓ ${USER_IMAGE} is up-to-date (newer than ${BASE_IMAGE})${NC}"
                    exit 0
                fi
            else
                echo -e "${YELLOW}⟳ User '$USERNAME' missing from ${USER_IMAGE}, rebuilding...${NC}"
            fi
        else
            echo -e "${YELLOW}⟳ ${USER_IMAGE} is stale (older than ${BASE_IMAGE}), rebuilding...${NC}"
        fi
    fi
else
    if [ "$FORCE" = true ]; then
        echo -e "${YELLOW}⟳ Force rebuild requested${NC}"
    else
        echo -e "${YELLOW}⟳ ${USER_IMAGE} not found, building...${NC}"
    fi
fi

# Build Layer 3
BUILD_SCRIPT="$REPO_DIR/user-layer/build.sh"

if [ ! -x "$BUILD_SCRIPT" ]; then
    echo -e "${RED}✗ user-layer/build.sh not found or not executable${NC}"
    exit 1
fi

BUILD_ARGS=(--base "$BASE_IMAGE" --user "$USERNAME" --uid "$USER_UID" --gid "$USER_GID")
if [ -n "$DOCKER_SOCKET_GID" ]; then
    BUILD_ARGS+=(--docker-gid "$DOCKER_SOCKET_GID")
fi
if [ -n "$EXTRA_CHOWN" ]; then
    BUILD_ARGS+=(--chown "$EXTRA_CHOWN")
fi

"$BUILD_SCRIPT" "${BUILD_ARGS[@]}"

echo -e "${GREEN}✓ ${USER_IMAGE} ready${NC}"
