#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[ensure-vibe-annotations] %s\n' "$*" >&2
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/vibe-annotations.compose.yml"
CONTAINER_NAME="${VIBE_ANNOTATIONS_CONTAINER:-vibe-annotations}"
NETWORK_NAME="${VIBE_ANNOTATIONS_NETWORK:-devbench-shared}"
VERSION="${VIBE_ANNOTATIONS_VERSION:-0.5.1}"
IMAGE="${VIBE_ANNOTATIONS_IMAGE:-workbenches/vibe-annotations:$VERSION}"
HOST_BIND="${VIBE_ANNOTATIONS_HOST_BIND:-127.0.0.1}"
HOST_PORT=3846
COMPOSE_PROJECT_NAME="${VIBE_ANNOTATIONS_COMPOSE_PROJECT:-dev-benches}"
VIBE_HOME="${VIBE_ANNOTATIONS_HOME_DIR:-$HOME/projects/.workbenches/vibe}"

usage() {
  cat <<'EOF'
Usage: ensure-vibe-annotations.sh [--recreate|--status|--stop]

Starts the one shared Vibe Annotations MCP service used by workBench
containers. The Windows browser extension connects to 127.0.0.1:3846;
Codex profile launchers inside benches connect through host.docker.internal.
EOF
}

action="start"
case "${1:-}" in
  "") ;;
  --recreate) action="recreate" ;;
  --status) action="status" ;;
  --stop) action="stop" ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

if ! command -v docker >/dev/null 2>&1; then
  log "Docker is required."
  exit 1
fi
if ! docker info >/dev/null 2>&1; then
  log "Docker is installed but is not running."
  exit 1
fi
if ! docker compose version >/dev/null 2>&1; then
  log "Docker Compose v2 is required."
  exit 1
fi

export VIBE_ANNOTATIONS_CONTAINER="$CONTAINER_NAME"
export VIBE_ANNOTATIONS_NETWORK="$NETWORK_NAME"
export VIBE_ANNOTATIONS_VERSION="$VERSION"
export VIBE_ANNOTATIONS_IMAGE="$IMAGE"
export VIBE_ANNOTATIONS_HOST_BIND="$HOST_BIND"
export VIBE_ANNOTATIONS_HOME_DIR="$VIBE_HOME"
export VIBE_ANNOTATIONS_UID="${VIBE_ANNOTATIONS_UID:-$(id -u)}"
export VIBE_ANNOTATIONS_GID="${VIBE_ANNOTATIONS_GID:-$(id -g)}"

compose=(docker compose -p "$COMPOSE_PROJECT_NAME" -f "$COMPOSE_FILE")

case "$action" in
  stop)
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    log "Shared Vibe Annotations service stopped."
    exit 0
    ;;
  status)
    if ! docker inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
      log "Shared Vibe Annotations service is not installed."
      exit 1
    fi
    docker inspect --format 'container={{.Name}} state={{.State.Status}} health={{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}} image={{.Config.Image}}' "$CONTAINER_NAME"
    curl --fail --silent --show-error --max-time 3 "http://$HOST_BIND:$HOST_PORT/health"
    printf '\n'
    exit 0
    ;;
  recreate)
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    ;;
esac

mkdir -p "$VIBE_HOME/.vibe-annotations"
chmod 700 "$VIBE_HOME" "$VIBE_HOME/.vibe-annotations"

if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
  docker network create "$NETWORK_NAME" >/dev/null
fi

COMPOSE_IGNORE_ORPHANS=True "${compose[@]}" up -d --build vibe-annotations

for _ in {1..30}; do
  if curl --fail --silent --max-time 2 "http://$HOST_BIND:$HOST_PORT/health" >/dev/null 2>&1; then
    installed_version="$(docker exec "$CONTAINER_NAME" vibe-annotations-server --version)"
    if [[ "$installed_version" != "$VERSION" ]]; then
      log "Version mismatch: expected $VERSION, got $installed_version."
      exit 1
    fi
    log "Shared Vibe Annotations v$installed_version is ready at http://$HOST_BIND:$HOST_PORT/mcp."
    log "Bench MCP URL: http://host.docker.internal:$HOST_PORT/mcp"
    log "Persistent data: $VIBE_HOME/.vibe-annotations"
    exit 0
  fi
  sleep 0.5
done

log "Service did not become healthy. Recent logs follow."
docker logs --tail 80 "$CONTAINER_NAME" >&2 || true
exit 1
