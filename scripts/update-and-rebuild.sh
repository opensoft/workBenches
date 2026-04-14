#!/bin/bash

# Update and rebuild workBench container layers with latest tool versions
# Optionally push to Docker Hub (opensoft org)
#
# Usage:
#   ./update-and-rebuild.sh --layer 0              # Rebuild Layer 0 only
#   ./update-and-rebuild.sh --layer 1a             # Rebuild Layer 1a only
#   ./update-and-rebuild.sh --all                  # Rebuild all layers 0-2 in order
#   ./update-and-rebuild.sh --all --push           # Rebuild all + push to registry
#   ./update-and-rebuild.sh --layer 0 --cascade    # Rebuild Layer 0 + all downstream
#   ./update-and-rebuild.sh --layer 1a --cascade   # Rebuild Layer 1a + Layer 2 benches using it
#   ./update-and-rebuild.sh --layer 3 --base cpp-bench:latest --chown /opt/vcpkg  # User layer
#
# Layers 0-2 are user-agnostic (tagged :latest). Layer 3 adds user personalization.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/image-names.sh"
USERNAME="${USERNAME:-$(whoami)}"
LAYER=""
PUSH=false
BUILD_ALL=false
CASCADE=false
DATE_TAG=$(date '+%Y%m%d')
LAYER3_BASE=""
LAYER3_CHOWN=""

# Registry config
REGISTRY_ENV="$REPO_DIR/config/registry.env"
if [ -f "$REGISTRY_ENV" ]; then
    source "$REGISTRY_ENV"
fi
REGISTRY="${REGISTRY:-docker.io/opensoft}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --layer) LAYER="$2"; shift 2 ;;
        --all) BUILD_ALL=true; shift ;;
        --push) PUSH=true; shift ;;
        --cascade) CASCADE=true; shift ;;
        --user) USERNAME="$2"; shift 2 ;;
        --base) LAYER3_BASE="$2"; shift 2 ;;
        --chown) LAYER3_CHOWN="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [--layer 0|1a|1b|1c|3] [--all] [--push] [--cascade] [--user USERNAME]"
            echo ""
            echo "Options:"
            echo "  --layer LAYER   Rebuild a specific layer (0, 1a, 1b, 1c, 3)"
            echo "  --all           Rebuild all layers 0-2 in dependency order (user-agnostic)"
            echo "  --push          Push rebuilt images to Docker Hub ($REGISTRY)"
            echo "  --cascade       Also rebuild all downstream layers that depend on the rebuilt layer"
            echo "  --user NAME     Username for Layer 3 image tags (default: $(whoami))"
            echo "  --base IMAGE    Base image for Layer 3 (e.g. cpp-bench:latest)"
            echo "  --chown DIRS    Extra dirs to chown in Layer 3 (e.g. /opt/vcpkg)"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [ "$BUILD_ALL" = false ] && [ -z "$LAYER" ]; then
    echo "Error: specify --layer or --all"
    echo "Run $0 --help for usage"
    exit 1
fi

# ========================================
# HELPERS
# ========================================

check_docker_login() {
    if [ "$PUSH" = true ]; then
        echo -e "${CYAN}Checking Docker Hub login...${NC}"
        if ! docker info 2>/dev/null | grep -q "Username"; then
            echo -e "${YELLOW}Not logged into Docker Hub.${NC}"
            echo "Please run: docker login"
            echo "Then re-run this script."
            exit 1
        fi
        echo -e "${GREEN}✓ Docker Hub login confirmed${NC}"
    fi
}

push_image() {
    local local_image="$1"
    local remote_name="$2"

    if [ "$PUSH" = false ]; then
        return
    fi

    echo -e "${CYAN}Pushing $remote_name...${NC}"

    # Tag with date and latest
    docker tag "$local_image" "$REGISTRY/$remote_name:${DATE_TAG}"
    docker tag "$local_image" "$REGISTRY/$remote_name:latest"

    # Push both tags
    docker push "$REGISTRY/$remote_name:${DATE_TAG}"
    docker push "$REGISTRY/$remote_name:latest"

    echo -e "${GREEN}✓ Pushed $REGISTRY/$remote_name:${DATE_TAG}${NC}"
    echo -e "${GREEN}✓ Pushed $REGISTRY/$remote_name:latest${NC}"
}

build_timer_start() {
    BUILD_START=$(date +%s)
}

build_timer_end() {
    local layer_name="$1"
    local elapsed=$(( $(date +%s) - BUILD_START ))
    local mins=$((elapsed / 60))
    local secs=$((elapsed % 60))
    echo -e "${GREEN}✓ $layer_name built in ${mins}m ${secs}s${NC}"
}

# ========================================
# CASCADE: Discover and rebuild downstream Layer 2 benches
# ========================================

dockerfile_uses_base_image() {
    local dockerfile="$1"
    local base_image="$2"

    if grep -qE "^[[:space:]]*FROM[[:space:]]+(\\$\{[^}]+:-)?${base_image}([[:space:]]|$)" "$dockerfile" 2>/dev/null || \
       grep -qE "^[[:space:]]*FROM[[:space:]]+${base_image}([[:space:]]|$)" "$dockerfile" 2>/dev/null; then
        return 0
    fi

    if grep -qE "^[[:space:]]*ARG[[:space:]]+BASE_IMAGE=${base_image}([[:space:]]|$)" "$dockerfile" 2>/dev/null && \
       grep -qE "^[[:space:]]*FROM[[:space:]]+\\\$\\{BASE_IMAGE\\}([[:space:]]|$)" "$dockerfile" 2>/dev/null; then
        return 0
    fi

    return 1
}

# Scan Dockerfiles for FROM lines to find benches that depend on a given base image
find_downstream_benches() {
    local base_image="$1"
    local -a found=()

    # Search all bench directories for Dockerfiles referencing this base image
    for search_dir in "$REPO_DIR/devBenches" "$REPO_DIR/sysBenches" "$REPO_DIR/bioBenches"; do
        [ -d "$search_dir" ] || continue
        while IFS= read -r -d '' dockerfile; do
            # Skip base-image directories (those are Layer 1, not Layer 2)
            if [[ "$dockerfile" == */base-image/* ]]; then
                continue
            fi
            if dockerfile_uses_base_image "$dockerfile" "$base_image"; then
                local bench_dir
                bench_dir=$(dirname "$dockerfile")
                # If Dockerfile is inside .devcontainer, go up one level
                if [[ "$bench_dir" == */.devcontainer ]]; then
                    bench_dir=$(dirname "$bench_dir")
                fi
                found+=("$bench_dir")
            fi
        done < <(find "$search_dir" -maxdepth 4 -name 'Dockerfile*' -print0 2>/dev/null)
    done

    # Deduplicate
    printf '%s\n' "${found[@]}" | sort -u
}

# Rebuild a Layer 2 bench directory
build_layer2_bench() {
    local bench_dir="$1"
    local bench_name
    bench_name=$(basename "$bench_dir")

    echo ""
    echo -e "${BOLD}${CYAN}═══ Rebuilding Layer 2: $bench_name ═══${NC}"

    # Look for a build script
    local build_script=""
    for candidate in \
        "$bench_dir/build-layer2.sh" \
        "$bench_dir/scripts/build-layer2.sh" \
        "$bench_dir/build-layer.sh" \
        "$bench_dir/scripts/build-layer.sh" \
        "$bench_dir/build.sh" \
        "$bench_dir/.devcontainer/build.sh"; do
        if [ -x "$candidate" ]; then
            build_script="$candidate"
            break
        fi
    done

    if [ -n "$build_script" ]; then
        build_timer_start
        "$build_script" --user "$USERNAME" 2>/dev/null || "$build_script" "$USERNAME" 2>/dev/null || "$build_script"
        build_timer_end "Layer 2: $bench_name"
    else
        # Fall back to docker build if there's a Dockerfile
        local dockerfile=""
        for candidate in "$bench_dir/Dockerfile.layer2" "$bench_dir/Dockerfile" "$bench_dir/.devcontainer/Dockerfile"; do
            if [ -f "$candidate" ]; then
                dockerfile="$candidate"
                break
            fi
        done

        if [ -n "$dockerfile" ]; then
            build_timer_start
            local context_dir
            local image_repo
            context_dir=$(dirname "$dockerfile")
            image_repo=$(bench_dir_to_image_repo "$bench_name")
            docker build -t "${image_repo}:latest" -f "$dockerfile" "$context_dir"
            build_timer_end "Layer 2: $bench_name"
        else
            echo -e "${YELLOW}  No build script or Dockerfile found in $bench_dir — skipping${NC}"
        fi
    fi
}

# Cascade rebuild all downstream dependents of a base image
cascade_rebuild() {
    local base_image="$1"

    echo ""
    echo -e "${BOLD}${CYAN}Scanning for downstream benches depending on ${base_image}...${NC}"

    local downstream
    downstream=$(find_downstream_benches "$base_image")

    if [ -z "$downstream" ]; then
        echo "  No downstream Layer 2 benches found for $base_image"
        return
    fi

    echo "  Found downstream benches:"
    while IFS= read -r bench_dir; do
        echo "    - $(basename "$bench_dir") ($bench_dir)"
    done <<< "$downstream"

    while IFS= read -r bench_dir; do
        build_layer2_bench "$bench_dir"
    done <<< "$downstream"
}

# ========================================
# BUILD FUNCTIONS
# ========================================

build_layer0() {
    local build_dir="$REPO_DIR/base-image"
    local image="workbench-base:latest"

    echo ""
    echo -e "${BOLD}${CYAN}═══ Building Layer 0: System Base (user-agnostic) ═══${NC}"

    if [ ! -f "$build_dir/build.sh" ]; then
        echo -e "${RED}✗ $build_dir/build.sh not found${NC}"
        return 1
    fi

    build_timer_start
    "$build_dir/build.sh"
    build_timer_end "Layer 0"

    push_image "$image" "workbench-base"
}

build_layer1a() {
    local build_dir="$REPO_DIR/devBenches/base-image"
    local image
    image=$(family_base_image dev)

    echo ""
    echo -e "${BOLD}${CYAN}═══ Building Layer 1a: Developer Base (user-agnostic) ═══${NC}"

    # Check dependency
    if ! docker image inspect "workbench-base:latest" >/dev/null 2>&1; then
        echo -e "${YELLOW}Layer 0 not found. Building it first...${NC}"
        build_layer0
    fi

    if [ ! -f "$build_dir/build.sh" ]; then
        echo -e "${RED}✗ $build_dir/build.sh not found${NC}"
        return 1
    fi

    build_timer_start
    "$build_dir/build.sh"
    build_timer_end "Layer 1a"

    push_image "$image" "$(family_base_repo dev)"
}

build_layer1b() {
    local build_dir="$REPO_DIR/sysBenches/base-image"
    local image
    image=$(family_base_image sys)

    echo ""
    echo -e "${BOLD}${CYAN}═══ Building Layer 1b: Sys/DevOps Base (user-agnostic) ═══${NC}"

    # Check dependency
    if ! docker image inspect "workbench-base:latest" >/dev/null 2>&1; then
        echo -e "${YELLOW}Layer 0 not found. Building it first...${NC}"
        build_layer0
    fi

    if [ ! -f "$build_dir/build.sh" ]; then
        echo -e "${RED}✗ $build_dir/build.sh not found${NC}"
        return 1
    fi

    build_timer_start
    "$build_dir/build.sh"
    build_timer_end "Layer 1b"

    push_image "$image" "$(family_base_repo sys)"
}

build_layer1c() {
    local build_dir="$REPO_DIR/bioBenches/base-image"
    local image
    image=$(family_base_image bio)

    echo ""
    echo -e "${BOLD}${CYAN}═══ Building Layer 1c: Bio Base (user-agnostic) ═══${NC}"

    # Check dependency
    if ! docker image inspect "workbench-base:latest" >/dev/null 2>&1; then
        echo -e "${YELLOW}Layer 0 not found. Building it first...${NC}"
        build_layer0
    fi

    if [ ! -f "$build_dir/build.sh" ]; then
        echo -e "${RED}✗ $build_dir/build.sh not found${NC}"
        return 1
    fi

    build_timer_start
    "$build_dir/build.sh"
    build_timer_end "Layer 1c"

    push_image "$image" "$(family_base_repo bio)"
}

build_layer3() {
    local user_layer_dir="$REPO_DIR/user-layer"

    echo ""
    echo -e "${BOLD}${CYAN}═══ Building Layer 3: User Personalization ($USERNAME) ═══${NC}"

    if [ -z "$LAYER3_BASE" ]; then
        echo -e "${RED}✗ --base is required for Layer 3${NC}"
        echo "  Example: $0 --layer 3 --base cpp-bench:latest --chown /opt/vcpkg"
        return 1
    fi

    if [ ! -f "$user_layer_dir/build.sh" ]; then
        echo -e "${RED}✗ $user_layer_dir/build.sh not found${NC}"
        return 1
    fi

    build_timer_start
    local chown_args=""
    if [ -n "$LAYER3_CHOWN" ]; then
        chown_args="--chown $LAYER3_CHOWN"
    fi
    "$user_layer_dir/build.sh" --base "$LAYER3_BASE" --user "$USERNAME" $chown_args
    build_timer_end "Layer 3"
}

# ========================================
# MAIN
# ========================================

echo "=========================================="
echo "workBenches Update & Rebuild"
echo "=========================================="
echo "User: $USERNAME"
echo "Registry: $REGISTRY"
echo "Push: $PUSH"
echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"

# Check Docker
if ! docker info >/dev/null 2>&1; then
    echo -e "${RED}Docker is not running. Please start Docker first.${NC}"
    exit 1
fi

# Check login if pushing
check_docker_login

TOTAL_START=$(date +%s)

if [ "$BUILD_ALL" = true ]; then
    echo ""
    echo -e "${BOLD}Rebuilding all layers in dependency order...${NC}"
    build_layer0
    build_layer1a
    build_layer1b
    build_layer1c
    if [ "$CASCADE" = true ]; then
        cascade_rebuild "$(family_base_image dev)"
        cascade_rebuild "$(family_base_image sys)"
        cascade_rebuild "$(family_base_image bio)"
    fi
else
    case "$LAYER" in
        0)
            build_layer0
            if [ "$CASCADE" = true ]; then
                echo -e "${CYAN}Cascading: rebuilding Layer 1 images...${NC}"
                build_layer1a
                build_layer1b
                build_layer1c
                cascade_rebuild "$(family_base_image dev)"
                cascade_rebuild "$(family_base_image sys)"
                cascade_rebuild "$(family_base_image bio)"
            fi
            ;;
        1a)
            build_layer1a
            if [ "$CASCADE" = true ]; then
                cascade_rebuild "$(family_base_image dev)"
            fi
            ;;
        1b)
            build_layer1b
            if [ "$CASCADE" = true ]; then
                cascade_rebuild "$(family_base_image sys)"
            fi
            ;;
        1c)
            build_layer1c
            if [ "$CASCADE" = true ]; then
                cascade_rebuild "$(family_base_image bio)"
            fi
            ;;
        3)
            build_layer3
            ;;
        *)
            echo "Unknown layer: $LAYER"
            echo "Valid layers: 0, 1a, 1b, 1c, 3"
            exit 1
            ;;
    esac
fi

TOTAL_ELAPSED=$(( $(date +%s) - TOTAL_START ))
TOTAL_MINS=$((TOTAL_ELAPSED / 60))
TOTAL_SECS=$((TOTAL_ELAPSED % 60))

echo ""
echo "=========================================="
echo -e "${GREEN}✓ Build complete in ${TOTAL_MINS}m ${TOTAL_SECS}s${NC}"
echo "=========================================="

# Run version check after build
echo ""
echo -e "${CYAN}Running version check on rebuilt images...${NC}"
if [ "$BUILD_ALL" = true ]; then
    "$SCRIPT_DIR/check-versions.sh" --user "$USERNAME"
else
    "$SCRIPT_DIR/check-versions.sh" --layer "$LAYER" --user "$USERNAME"
fi
