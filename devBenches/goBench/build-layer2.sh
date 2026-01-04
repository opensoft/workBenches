#!/bin/bash
# Build script for Layer 2: Go Bench Image
# Creates: go-bench:$USERNAME

set -e

echo "=========================================="
echo "Building Layer 2: Go Bench"
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
echo "  Base image: devbench-base:$USERNAME"
echo ""

# Check if Layer 1 exists
if ! docker image inspect "devbench-base:$USERNAME" >/dev/null 2>&1; then
    echo "❌ Error: Layer 1 (devbench-base:$USERNAME) not found!"
    echo ""
    echo "Please build Layer 1 first:"
    echo "  cd ../base-image"
    echo "  ./build.sh --user $USERNAME"
    exit 1
fi

# Build the image
echo "Building go-bench:$USERNAME..."
docker build \
    --build-arg BASE_IMAGE="devbench-base:$USERNAME" \
    --build-arg USERNAME="$USERNAME" \
    -f Dockerfile.layer2 \
    -t "go-bench:$USERNAME" \
    .

echo ""
echo "✓ Layer 2 (Go) built successfully!"
echo "  Image: go-bench:$USERNAME"
echo ""
echo "Next step: Update workspaces to use this image"
echo "  Edit docker-compose.yml and replace 'build:' with:"
echo "    image: go-bench:$USERNAME"
