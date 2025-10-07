#!/bin/bash

DEVBENCH_DIR="/home/brett/projects/DevBench/JavaBench"
CONTAINER_NAME="java_bench"

cd "$DEVBENCH_DIR"

echo "🚀 DevJava - Starting JavaBench Container..."

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

echo "🔗 Connecting to JavaBench container..."
echo "📁 You'll be in: /workspace (your projects folder)"
echo "🛠️  Available: Java 21/17/11, Maven, Spring Boot, and 50+ dev tools"
echo ""

# Connect to the container
docker exec -it "$CONTAINER_NAME" zsh