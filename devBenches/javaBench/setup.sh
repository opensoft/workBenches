#!/bin/bash

# Get current user info
export USER=$(whoami)

echo "🚀 Starting the Java DevBench Container"
echo "   User: $USER"

# Check if the java-bench image exists
if ! docker image inspect "java-bench:$USER" >/dev/null 2>&1; then
    echo ""
    echo "❌ Error: Docker image 'java-bench:$USER' not found!"
    echo ""
    echo "You need to build the Java bench image first:"
    echo "  ./scripts/build-layer.sh"
    echo ""
    echo "This will:"
    echo "  1. Check that devbench-base:$USER exists (build ../base-image if needed)"
    echo "  2. Build the Java-specific layer on top of it"
    echo "  3. Install OpenJDK 21, Maven, Gradle, Spring CLI, and SDKMan"
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
    echo "   - Or run: docker exec -it java_bench zsh"
    echo ""
    echo "🔍 To check container status:"
    echo "   docker ps | grep java_bench"
    echo ""
    echo "☕ Java Development Ready:"
    echo "   - OpenJDK 21 (LTS)"
    echo "   - Maven and Gradle build tools"
    echo "   - Spring Boot CLI"
    echo "   - SDKMan for version management"
    echo "   - M2 repository at /workspace/m2repo"
else
    echo "❌ Container failed to start. Check Docker logs:"
    echo "   docker-compose -f .devcontainer/docker-compose.yml logs"
fi
