#!/bin/bash
# Build C++ Bench Layer 2 (cpp-bench:latest) + Layer 3 (cpp-bench:$USERNAME)
# Requires Layer 1 (devbench-base:latest) to exist

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
USERNAME=$(whoami)

echo "🚀 Building C++ Bench"
echo ""

# Check if devbench-base:latest exists
if ! docker image inspect "devbench-base:latest" >/dev/null 2>&1; then
    echo "❌ Error: Base image 'devbench-base:latest' not found!"
    echo ""
    echo "You need to build the base image first:"
    echo "  cd ../../base-image && ./build.sh"
    echo ""
    exit 1
fi

echo "✓ Base image 'devbench-base:latest' found"
echo ""

# Build Layer 2 (user-agnostic)
echo "Building cpp-bench:latest (GCC, Clang, CMake, vcpkg, Conan)..."
echo ""

docker build \
    -t "cpp-bench:latest" \
    -f "$SCRIPT_DIR/../Dockerfile.layer2" \
    "$SCRIPT_DIR/.."

echo ""
echo "✅ Layer 2 built: cpp-bench:latest"
echo ""

# Build Layer 3 (user personalization)
echo "Building cpp-bench:$USERNAME (user layer)..."
echo ""

"$REPO_DIR/user-layer/build.sh" --base "cpp-bench:latest" --user "$USERNAME" --chown "/opt/vcpkg"

echo ""
echo "✅ Successfully built cpp-bench:$USERNAME"
echo ""
echo "Layer sizes:"
docker images | grep -E "devbench-base|cpp-bench"
echo ""
echo "🎯 Next steps:"
echo "   - Run: ../setup.sh  (to start the container)"
echo "   - Or rebuild with: ./build-layer.sh"
