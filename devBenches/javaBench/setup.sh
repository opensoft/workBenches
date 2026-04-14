#!/bin/bash

set -euo pipefail

# Get current user info
export USER=$(whoami)

echo "🚀 Starting the Java DevBench Container"
echo "   User: $USER"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
LAYER2_IMAGE="java-bench:latest"
USER_IMAGE="java-bench:$USER"

if ! docker image inspect "$LAYER2_IMAGE" >/dev/null 2>&1; then
    echo ""
    echo "🔧 Docker image not found. Building java-bench:latest..."
    "$SCRIPT_DIR/scripts/build-layer.sh"
else
    echo "✓ Base image '$LAYER2_IMAGE' found"
    echo ""
    echo "🔧 Ensuring user image '$USER_IMAGE'..."
    "$REPO_DIR/scripts/ensure-layer3.sh" --base "$LAYER2_IMAGE" --user "$USER"
fi

# Validate we have the required info
if [ -z "$USER" ]; then
    echo "❌ Error: Could not determine user info"
    echo "   USER=$USER"
    exit 1
fi

echo "🔧 Starting container with user mapping..."

# Start the container with proper user mapping (no --build since using pre-built image)
if docker-compose -f "$SCRIPT_DIR/.devcontainer/docker-compose.yml" up -d; then
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
