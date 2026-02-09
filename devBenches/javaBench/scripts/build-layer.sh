#!/bin/bash
# Build Java Bench Layer 2 (java-bench:${USER})
# Requires Layer 1 (devbench-base:${USER}) to exist

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USER=$(whoami)

echo "🚀 Building Java Bench Layer 2"
echo "   User: $USER"
echo ""

# Check if devbench-base exists
if ! docker image inspect "devbench-base:$USER" >/dev/null 2>&1; then
    echo "❌ Error: Base image 'devbench-base:$USER' not found!"
    echo ""
    echo "You need to build the base image first:"
    echo "  cd ../base-image"
    echo "  ./build-base.sh"
    echo ""
    exit 1
fi

echo "✓ Base image 'devbench-base:$USER' found"
echo ""
echo "Building java-bench:$USER (OpenJDK 21, Maven, Gradle, Spring CLI)..."
echo ""

# Build Layer 2
docker build \
    --build-arg BASE_IMAGE="devbench-base:$USER" \
    --build-arg USERNAME="$USER" \
    -t "java-bench:$USER" \
    -f "$SCRIPT_DIR/../Dockerfile.layer2" \
    "$SCRIPT_DIR/.."

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Successfully built java-bench:$USER"
    echo ""
    echo "Layer sizes:"
    docker images | grep -E "devbench-base|java-bench" | grep "$USER"
    echo ""
    echo "🎯 Next steps:"
    echo "   - Run: ../setup.sh  (to start the container)"
    echo "   - Or rebuild with: ./build-layer.sh"
else
    echo ""
    echo "❌ Build failed. Check the output above for errors."
    exit 1
fi
