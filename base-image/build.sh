#!/bin/bash
# Build script for Layer 0: System Base Image
# Creates: workbench-base:$USERNAME

set -e

echo "=========================================="
echo "Building Layer 0: System Base"
echo "=========================================="
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Parse arguments
USERNAME=${1:-$(whoami)}
if [ "$USERNAME" = "--user" ]; then
    USERNAME="${2:-$(whoami)}"
fi

# Get UID and GID
USER_UID=$(id -u)
USER_GID=$(id -g)

echo "Configuration:"
echo "  Username: $USERNAME"
echo "  UID: $USER_UID"
echo "  GID: $USER_GID"
echo ""

# Build the image
echo "Building workbench-base:$USERNAME..."
docker build \
    --build-arg USERNAME="$USERNAME" \
    --build-arg USER_UID="$USER_UID" \
    --build-arg USER_GID="$USER_GID" \
    -t "workbench-base:$USERNAME" \
    .

echo ""
echo "✓ Layer 0 built successfully!"
echo "  Image: workbench-base:$USERNAME"
echo ""
echo "Next step: Build Layer 1 with your user"
echo "  cd ../devBenches/base-image"
echo "  ./build.sh --user $USERNAME"
