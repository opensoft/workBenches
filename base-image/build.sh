#!/bin/bash
# Build script for Layer 0: System Base Image
# Creates: workbench-base:latest (user-agnostic)

set -e

echo "=========================================="
echo "Building Layer 0: System Base (user-agnostic)"
echo "=========================================="
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Parse arguments (--user is accepted but ignored for backward compat)
NO_CACHE="${NO_CACHE:-false}"
while [[ $# -gt 0 ]]; do
    case $1 in
        --user) shift 2 ;;
        --no-cache) NO_CACHE=true; shift ;;
        *) shift ;;
    esac
done

echo "Configuration:"
echo "  Tag: workbench-base:latest (user-agnostic)"
echo "  No cache: $NO_CACHE"
echo ""

# Build the image
echo "Building workbench-base:latest..."
docker build \
    $([ "$NO_CACHE" = true ] && printf '%s\n' "--no-cache") \
    -t "workbench-base:latest" \
    .

echo ""
echo "✓ Layer 0 built successfully!"
echo "  Image: workbench-base:latest"
echo ""
echo "Next step: Build Layer 1"
echo "  cd ../devBenches/base-image"
echo "  ./build.sh"
