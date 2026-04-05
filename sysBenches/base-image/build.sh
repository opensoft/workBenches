#!/bin/bash
# Build script for Layer 1b: Admin/DevOps Base Image
# Creates: adminbench-base:latest (user-agnostic)

set -e

echo "=========================================="
echo "Building Layer 1b: Admin/DevOps Base (user-agnostic)"
echo "=========================================="
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Parse arguments (--user is accepted but ignored for backward compat)
while [[ $# -gt 0 ]]; do
    case $1 in
        --user) shift 2 ;;
        *) shift ;;
    esac
done

echo "Configuration:"
echo "  Tag: adminbench-base:latest (user-agnostic)"
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
echo "Building adminbench-base:latest..."
docker build \
    -t "adminbench-base:latest" \
    .

echo ""
echo "✓ Layer 1b built successfully!"
echo "  Image: adminbench-base:latest"
echo ""
echo "Next step: Build bench-specific images or test"
