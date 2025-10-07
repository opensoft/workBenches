#!/bin/bash

DEVBENCH_DIR="/home/brett/projects/DevBench/dotNetBench"
CONTAINER_NAME="dot_net_bench"

cd "$DEVBENCH_DIR"

echo "🚀 DevDotNet - Starting dotNetBench Container..."

# Check if container is already running
if docker ps --format "table {{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
    echo "✅ Container is already running, connecting..."
else
    echo "🔧 Container not running, starting it first..."
    ./start-monster.sh
    
    # Wait a moment for container to fully start
    sleep 3
    
    # Check if it started successfully
    if ! docker ps --format "table {{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
        echo "❌ Failed to start container. Check Docker logs."
        read -p "Press Enter to exit..."
        exit 1
    fi
fi

echo "🔗 Connecting to dotNetBench container..."
echo "📁 You'll be in: /workspace (your projects folder)"
echo "🛠️  Available: .NET 8, ASP.NET Core, 21 global tools, and 50+ dev tools"
echo ""

# Connect to the container
docker exec -it "$CONTAINER_NAME" zsh