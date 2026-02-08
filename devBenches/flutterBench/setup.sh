#!/bin/bash

# Get current user info
export USER=$(whoami)

echo "🚀 Starting the Flutter DevBench Container"
echo "   User: $USER"

# Check if the flutter-bench image exists
if ! docker image inspect "flutter-bench:$USER" >/dev/null 2>&1; then
    echo ""
    echo "❌ Error: Docker image 'flutter-bench:$USER' not found!"
    echo ""
    echo "You need to build the Flutter bench image first:"
    echo "  ./scripts/build-layer.sh"
    echo ""
    echo "This will:"
    echo "  1. Check that devbench-base:$USER exists (build ../base-image if needed)"
    echo "  2. Build the Flutter-specific layer on top of it"
    echo "  3. Install Flutter SDK, Android SDK, and mobile dev tools"
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
    echo "   - Or run: docker exec -it flutter_bench zsh"
    echo ""
    echo "🔍 To check container status:"
    echo "   docker ps | grep flutter_bench"
    echo ""
    echo "📱 Flutter Development Ready:"
    echo "   - Flutter SDK installed at /opt/flutter"
    echo "   - Android SDK with emulator support"
    echo "   - 15+ Flutter development tools"
    echo "   - Firebase, Fastlane, Shorebird ready"
    echo "   - Design workflow with Figma integration"
else
    echo "❌ Container failed to start. Check Docker logs:"
    echo "   docker-compose -f .devcontainer/docker-compose.yml logs"
fi
