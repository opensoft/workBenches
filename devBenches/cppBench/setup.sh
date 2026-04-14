#!/bin/bash

set -euo pipefail

export USER=$(whoami)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
LAYER2_IMAGE="cpp-bench:latest"
USER_IMAGE="cpp-bench:$USER"

echo "🚀 Starting the C++ DevBench Container"
echo "   User: $USER"

if ! docker image inspect "$LAYER2_IMAGE" >/dev/null 2>&1; then
    echo ""
    echo "🔧 Docker image not found. Building $LAYER2_IMAGE..."
    "$SCRIPT_DIR/scripts/build-layer.sh"
else
    echo "✓ Base image '$LAYER2_IMAGE' found"
    echo "🔧 Ensuring user image '$USER_IMAGE'..."
    "$REPO_DIR/scripts/ensure-layer3.sh" --base "$LAYER2_IMAGE" --user "$USER" --chown "/opt/vcpkg"
fi

echo "🔧 Starting container with user mapping..."

# Start the container with proper user mapping (no --build since using pre-built image)
docker-compose -f .devcontainer/docker-compose.yml up -d

if [ $? -eq 0 ]; then
    echo "✅ Container started successfully!"
    echo ""
    echo "🎯 Next steps:"
    echo "   - Open VS Code and select 'Reopen in Container'"
    echo "   - Or run: docker exec -it cpp_bench zsh"
    echo ""
    echo "🔍 To check container status:"
    echo "   docker ps | grep cpp_bench"
    echo ""
    echo "🔨 C++ Development Ready:"
    echo "   - GCC 12 and Clang 15 compilers"
    echo "   - CMake, Ninja, Make build systems"
    echo "   - vcpkg and Conan package managers"
    echo "   - GDB, Valgrind debuggers"
    echo "   - Boost, Eigen, GTest libraries"
else
    echo "❌ Container failed to start. Check Docker logs:"
    echo "   docker-compose -f .devcontainer/docker-compose.yml logs"
fi
