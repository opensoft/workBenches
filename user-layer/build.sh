#!/bin/bash
# Build script for Layer 3: User Personalization
# Creates: <bench-name>:$USERNAME from <bench-name>:latest
#
# Usage:
#   ./build.sh --base cpp-bench:latest                    # Uses defaults
#   ./build.sh --base cpp-bench:latest --chown /opt/vcpkg # Extra dirs to chown
#   ./build.sh --base go-bench:latest --chown "/go"       # Go bench
#   ./build.sh --base cpp-bench:latest --user brett        # Explicit user

set -euo pipefail

echo "=========================================="
echo "Building Layer 3: User Personalization"
echo "=========================================="
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Defaults
USERNAME=$(whoami)
USER_UID=$(id -u)
USER_GID=$(id -g)
DOCKER_SOCKET_GID=""
BASE_IMAGE=""
BASE_IMAGE_ID=""
EXTRA_CHOWN_DIRS=""
NO_CACHE="${NO_CACHE:-false}"
LAYER3_RECIPE_SHA256=""
CODEX_VERSION=""
CODEX_VERSION_PROBE_TIMEOUT_SECONDS="${WORKBENCHES_CODEX_VERSION_PROBE_TIMEOUT_SECONDS:-30}"

run_with_optional_timeout() {
    local timeout_seconds="$1"
    shift

    if command -v timeout >/dev/null 2>&1; then
        timeout "${timeout_seconds}s" "$@"
    else
        "$@"
    fi
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --base) BASE_IMAGE="$2"; shift 2 ;;
        --user) USERNAME="$2"; shift 2 ;;
        --uid) USER_UID="$2"; shift 2 ;;
        --gid) USER_GID="$2"; shift 2 ;;
        --docker-gid) DOCKER_SOCKET_GID="$2"; shift 2 ;;
        --chown) EXTRA_CHOWN_DIRS="$2"; shift 2 ;;
        --recipe-sha256) LAYER3_RECIPE_SHA256="$2"; shift 2 ;;
        --codex-version) CODEX_VERSION="$2"; shift 2 ;;
        --no-cache) NO_CACHE=true; shift ;;
        -h|--help)
            echo "Usage: $0 --base <image:latest> [--user USERNAME] [--chown \"dir1 dir2\"] [--no-cache]"
            echo ""
            echo "Options:"
            echo "  --base IMAGE    Base Layer 2 image (required). e.g. cpp-bench:latest"
            echo "  --user NAME     Username (default: \$(whoami))"
            echo "  --uid UID       User UID (default: \$(id -u))"
            echo "  --gid GID       User GID (default: \$(id -g))"
            echo "  --chown DIRS    Space-separated dirs to chown to user (e.g. \"/opt/vcpkg /go\")"
            echo "  --recipe-sha256 SHA256  Layer 3 recipe fingerprint (computed automatically by default)"
            echo "  --codex-version VERSION  Exact Codex version baked into Layer 3 (default: inherit from base image)"
            echo "  --no-cache      Force Docker to rebuild without cached layers"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [ -z "$BASE_IMAGE" ]; then
    echo "❌ Error: --base is required"
    echo "Run $0 --help for usage"
    exit 1
fi
if [[ ! "$CODEX_VERSION_PROBE_TIMEOUT_SECONDS" =~ ^[1-9][0-9]*$ ]]; then
    echo "❌ Error: WORKBENCHES_CODEX_VERSION_PROBE_TIMEOUT_SECONDS must be a positive integer" >&2
    exit 1
fi

# Resolve the mutable caller-facing tag once. The same immutable image ID is
# used for both the version probe and Dockerfile FROM so a concurrent retag
# cannot make those operations observe different Layer 2 images.
if ! BASE_IMAGE_ID="$(docker image inspect --format '{{.Id}}' "$BASE_IMAGE" 2>/dev/null)" \
    || [[ ! "$BASE_IMAGE_ID" =~ ^sha256:[0-9a-fA-F]{64}$ ]]; then
    echo "❌ Error: could not resolve '$BASE_IMAGE' to an immutable image ID"
    echo ""
    echo "Please build the Layer 2 image first."
    exit 1
fi

if [ -z "$LAYER3_RECIPE_SHA256" ]; then
    LAYER3_RECIPE_SHA256="$(
        cd "$SCRIPT_DIR"
        find . -type f -print0 \
            | LC_ALL=C sort -z \
            | xargs -0 sha256sum \
            | sha256sum \
            | awk '{print $1}'
    )"
fi

# Derive output tag: replace :latest with :$USERNAME
OUTPUT_IMAGE="${BASE_IMAGE%%:*}:${USERNAME}"

# Resolve the default from the exact base image rather than npm's mutable
# latest dist-tag. The resulting build argument also invalidates Docker's
# Layer 3 cache whenever the shared Layer 0 Codex version changes.
if [ -z "$CODEX_VERSION" ]; then
    codex_version_output=""
    if ! codex_version_output="$(run_with_optional_timeout \
        "$CODEX_VERSION_PROBE_TIMEOUT_SECONDS" \
        docker run --rm --network none --entrypoint="" "$BASE_IMAGE_ID" \
            sh -c 'codex --version' 2>/dev/null)"; then
        echo "❌ Error: Codex version probe failed or timed out for '$BASE_IMAGE' ($BASE_IMAGE_ID)" >&2
        exit 1
    fi
    CODEX_VERSION="$(printf '%s\n' "$codex_version_output" | awk 'NR == 1 { print $NF; exit }')"
fi
if [[ ! "$CODEX_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$ ]]; then
    echo "❌ Error: could not resolve an exact Codex version from '$BASE_IMAGE': '$CODEX_VERSION'" >&2
    exit 1
fi

echo "Configuration:"
echo "  Base image:  $BASE_IMAGE"
echo "  Base ID:     $BASE_IMAGE_ID"
echo "  Output:      $OUTPUT_IMAGE"
echo "  Username:    $USERNAME"
echo "  UID/GID:     $USER_UID/$USER_GID"
echo "  Docker GID:  ${DOCKER_SOCKET_GID:-none}"
echo "  Extra chown: ${EXTRA_CHOWN_DIRS:-none}"
echo "  No cache:    $NO_CACHE"
echo "  Recipe SHA:  $LAYER3_RECIPE_SHA256"
echo "  Codex:       $CODEX_VERSION"
echo ""

# Build Layer 3
echo "Building $OUTPUT_IMAGE..."
docker build \
    $([ "$NO_CACHE" = true ] && printf '%s\n' "--no-cache") \
    --build-arg BASE_IMAGE="$BASE_IMAGE_ID" \
    --build-arg USERNAME="$USERNAME" \
    --build-arg USER_UID="$USER_UID" \
    --build-arg USER_GID="$USER_GID" \
    --build-arg DOCKER_SOCKET_GID="$DOCKER_SOCKET_GID" \
    --build-arg EXTRA_CHOWN_DIRS="$EXTRA_CHOWN_DIRS" \
    --build-arg LAYER3_RECIPE_SHA256="$LAYER3_RECIPE_SHA256" \
    --build-arg CODEX_VERSION="$CODEX_VERSION" \
    -t "$OUTPUT_IMAGE" \
    -f "$SCRIPT_DIR/Dockerfile" \
    "$SCRIPT_DIR"

echo ""
echo "✓ Layer 3 built successfully!"
echo "  Image: $OUTPUT_IMAGE"
echo ""
echo "The image is ready for use in devcontainer.json:"
echo "  \"image\": \"$OUTPUT_IMAGE\""
