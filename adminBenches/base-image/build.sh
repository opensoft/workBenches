#!/bin/bash
# Build script for Layer 1b: Admin/DevOps Base Image
# Creates: adminbench-base:$USERNAME

set -e

echo "=========================================="
echo "Building Layer 1b: Admin/DevOps Base"
echo "=========================================="
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Parse arguments
USERNAME=${1:-$(whoami)}
if [ "$USERNAME" = "--user" ]; then
    USERNAME="${2:-$(whoami)}"
fi

echo "Configuration:"
echo "  Username: $USERNAME"
echo ""

# Check if Layer 0 exists
if ! docker image inspect "workbench-base:$USERNAME" >/dev/null 2>&1; then
    echo "❌ Error: Layer 0 (workbench-base:$USERNAME) not found!"
    echo ""
    echo "Please build Layer 0 first:"
    echo "  cd ../../base-image"
    echo "  ./build.sh --user $USERNAME"
    exit 1
fi

# Build the image
echo "Building adminbench-base:$USERNAME..."
docker build \
    --build-arg USERNAME="$USERNAME" \
    -t "adminbench-base:$USERNAME" \
    .

echo ""
echo "✓ Layer 1b built successfully!"
echo "  Image: adminbench-base:$USERNAME"
echo ""
echo "Next step: Build bench-specific images or test"
echo "  cd ../devcontainer.test"
echo "  docker compose up -d"
