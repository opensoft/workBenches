#!/bin/bash

# Get current user info
export USER=$(whoami)

echo "🚀 Starting the C++ DevBench Container"
echo "   User: $USER"

# Check if the cpp-bench image exists
if ! docker image inspect "cpp-bench:$USER" >/dev/null 2>&1; then
    echo ""
    echo "❌ Error: Docker image 'cpp-bench:$USER' not found!"
    echo ""
    echo "You need to build the C++ bench image first:"
    echo "  ./scripts/build-layer.sh"
    echo ""
    echo "This will:"
    echo "  1. Check that devbench-base:$USER exists (build ../base-image if needed)"
    echo "  2. Build the C++-specific layer on top of it"
    echo "  3. Install GCC 12, Clang 15, CMake, vcpkg, Conan, and analyzers"
    exit 1
fi

# Validate we have the required info
if [ -z "$USER" ]; then
    echo "❌ Error: Could not determine user info"
    echo "   USER=$USER"
    exit 1
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
