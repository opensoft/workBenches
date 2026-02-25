#!/bin/bash
# Build Flutter Bench Layer 2 (flutter-bench:${USER})
# Requires Layer 1 (devbench-base:${USER}) to exist

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER=$(whoami)

echo "🚀 Building Flutter Bench Layer 2"
echo "   User: $USER"
echo ""

# Check if devbench-base exists, build it if missing
if ! docker image inspect "devbench-base:$USER" >/dev/null 2>&1; then
    echo "⚠ Base image 'devbench-base:$USER' not found. Building automatically..."
    echo ""

    LAYER1_BUILD="$SCRIPT_DIR/../../base-image/build.sh"
    if [ ! -f "$LAYER1_BUILD" ]; then
        echo "❌ Error: Layer 1 build script not found: ${LAYER1_BUILD}"
        exit 1
    fi

    # Layer 1 build script will check for Layer 0 and error if missing
    "$LAYER1_BUILD" --user "$USER"
    echo ""
fi

echo "✓ Base image 'devbench-base:$USER' found"
echo ""
echo "Building flutter-bench:$USER (this will take a while - Flutter & Android SDK installation)..."
echo ""

# Build Layer 2
docker build \
    --build-arg BASE_IMAGE="devbench-base:$USER" \
    --build-arg USERNAME="$USER" \
    -t "flutter-bench:$USER" \
    -f "$SCRIPT_DIR/../Dockerfile.layer2" \
    "$SCRIPT_DIR/.."

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Successfully built flutter-bench:$USER"
    echo ""
    echo "Layer sizes:"
    docker images | grep -E "devbench-base|flutter-bench" | grep "$USER"
    echo ""
    echo "🎯 Next steps:"
    echo "   - Run: ../setup.sh  (to start the container)"
    echo "   - Or rebuild with: ./build-layer.sh"
else
    echo ""
    echo "❌ Build failed. Check the output above for errors."
    exit 1
fi
