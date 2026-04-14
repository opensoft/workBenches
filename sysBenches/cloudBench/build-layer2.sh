#!/bin/bash
# Build script for Layer 2: Cloud Admin Bench Image
# Creates: cloud-bench:latest

set -e

echo "=========================================="
echo "Building Layer 2: Cloud Admin Bench"
echo "=========================================="
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_DIR/scripts/lib/image-names.sh"
cd "$SCRIPT_DIR"

BASE_IMAGE="$(resolve_existing_image "$(family_base_image sys)" "$(legacy_family_base_image sys 2>/dev/null || true)" || true)"

echo "Configuration:"
echo "  Tag: cloud-bench:latest (user-agnostic)"
echo "  Base image: ${BASE_IMAGE:-$(family_base_image sys)}"
echo ""

# Check if Layer 1b exists
if [ -z "$BASE_IMAGE" ]; then
    echo "❌ Error: Layer 1b ($(family_base_image sys)) not found!"
    echo ""
    echo "Please build Layer 1b first:"
    echo "  cd ../base-image"
    echo "  ./build.sh"
    exit 1
fi

# Build the image
echo "Building cloud-bench:latest..."
docker build \
    --build-arg BASE_IMAGE="$BASE_IMAGE" \
    -f Dockerfile.layer2 \
    -t "cloud-bench:latest" \
    .

echo ""
echo "✓ Layer 2 (Cloud Admin) built successfully!"
echo "  Image: cloud-bench:latest"
echo ""
echo "Layer 3 (user personalization) is handled by"
echo "build-layer.sh or scripts/ensure-layer3.sh."
