#!/bin/bash
# Build script for Layer 1b: Sys/DevOps Base Image
# Creates: sys-bench-base:latest (user-agnostic)

set -e

echo "=========================================="
echo "Building Layer 1b: Sys/DevOps Base (user-agnostic)"
echo "=========================================="
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_DIR/scripts/lib/image-names.sh"

CANONICAL_IMAGE="$(family_base_image sys)"
LEGACY_IMAGE="$(legacy_family_base_image sys)"
cd "$SCRIPT_DIR"

# Parse arguments (--user is accepted but ignored for backward compat)
while [[ $# -gt 0 ]]; do
    case $1 in
        --user) shift 2 ;;
        *) shift ;;
    esac
done

echo "Configuration:"
echo "  Tag: $CANONICAL_IMAGE (user-agnostic)"
echo "  Legacy alias: $LEGACY_IMAGE"
echo ""

# Check if Layer 0 exists
if ! docker image inspect "workbench-base:latest" >/dev/null 2>&1; then
    echo "❌ Error: Layer 0 (workbench-base:latest) not found!"
    echo ""
    echo "Please build Layer 0 first:"
    echo "  cd ../../base-image"
    echo "  ./build.sh"
    exit 1
fi

# Build the image
echo "Building $CANONICAL_IMAGE..."
docker build \
    -t "$CANONICAL_IMAGE" \
    .
tag_family_base_legacy_alias sys

echo ""
echo "✓ Layer 1b built successfully!"
echo "  Image: $CANONICAL_IMAGE"
echo "  Legacy alias: $LEGACY_IMAGE"
echo ""
echo "Next step: Build bench-specific images or test"
