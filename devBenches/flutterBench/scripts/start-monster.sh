#!/bin/bash

# Get current user info
export UID=$(id -u)
export GID=$(id -g) 
export USER=$(whoami)

echo "🚀 Starting the Flutter DevBench Monster Container"
echo "   User: $USER (UID: $UID, GID: $GID)"

# Validate we have the required info
if [ -z "$USER" ] || [ -z "$UID" ] || [ -z "$GID" ]; then
    echo "❌ Error: Could not determine user info"
    echo "   USER=$USER, UID=$UID, GID=$GID"
    exit 1
fi

echo "🔧 Building container with user mapping..."

# Start the container with proper user mapping
docker-compose -f .devcontainer/docker-compose.yml up -d --build

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