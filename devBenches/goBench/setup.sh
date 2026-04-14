#!/bin/bash
USER=$(whoami)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! docker image inspect "go-bench:$USER" >/dev/null 2>&1; then
    echo "🔧 Docker image not found. Building go-bench layers..."
    "$SCRIPT_DIR/scripts/build-layer.sh" --user "$USER" || { echo "❌ Image build failed"; exit 1; }
fi

docker-compose -f .devcontainer/docker-compose.yml up -d
