#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[ensure-sonarqube-mcp] %s\n' "$*" >&2
}

CONTAINER_NAME="${SONARQUBE_MCP_CONTAINER:-sonarqube-mcp}"
PROXY_CONTAINER_NAME="${SONARQUBE_MCP_PROXY_CONTAINER:-sonarqube-mcp-proxy}"
NETWORK_NAME="${SONARQUBE_MCP_NETWORK:-devbench-shared}"
STORAGE_VOLUME="${SONARQUBE_MCP_STORAGE_VOLUME:-devbench-sonarqube-mcp-storage}"
IMAGE="${SONARQUBE_MCP_IMAGE:-mcp/sonarqube:latest}"
PROXY_IMAGE="${SONARQUBE_MCP_PROXY_IMAGE:-nginx:alpine}"
BACKEND_PORT="${SONARQUBE_MCP_BACKEND_PORT:-64131}"
PROXY_PORT="${SONARQUBE_MCP_PORT:-64130}"
HOST_BIND="${SONARQUBE_MCP_HOST_BIND:-127.0.0.1}"
COMPOSE_PROJECT_NAME="${SONARQUBE_MCP_COMPOSE_PROJECT:-dev-benches}"
COMPOSE_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/sonarqube-mcp.compose.yml"
LEGACY_CONTAINER_NAME="devbench-sonarqube-mcp"
LEGACY_PROXY_CONTAINER_NAME="devbench-sonarqube-mcp-proxy"
SECRET_FILE="${SONARQUBE_ENV_FILE:-$HOME/.config/sonarqube/sonar.env}"
if [[ ! -f "$SECRET_FILE" && -f "$HOME/.config/ledgerlinc/secrets/sonar.env" ]]; then
  SECRET_FILE="$HOME/.config/ledgerlinc/secrets/sonar.env"
fi

case "${1:-}" in
  --stop)
    docker rm -f "$PROXY_CONTAINER_NAME" "$CONTAINER_NAME" "$LEGACY_PROXY_CONTAINER_NAME" "$LEGACY_CONTAINER_NAME" >/dev/null 2>&1 || true
    exit 0
    ;;
  --recreate)
    docker rm -f "$PROXY_CONTAINER_NAME" "$CONTAINER_NAME" "$LEGACY_PROXY_CONTAINER_NAME" "$LEGACY_CONTAINER_NAME" >/dev/null 2>&1 || true
    ;;
  "" )
    ;;
  * )
    log "usage: $0 [--recreate|--stop]"
    exit 2
    ;;
esac

if ! command -v docker >/dev/null 2>&1; then
  log "Docker is not available; skipping reusable SonarQube MCP startup."
  exit 0
fi

COMPOSE_CMD=()
if docker compose version >/dev/null 2>&1; then
  COMPOSE_CMD=(docker compose)
else
  log "Docker Compose v2 plugin is not available; skipping reusable SonarQube MCP startup."
  exit 0
fi

if [[ -f "$SECRET_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$SECRET_FILE"
  set +a
fi

SONARQUBE_TOKEN="${SONARQUBE_TOKEN:-${SONAR_TOKEN:-}}"

if [[ -z "${SONARQUBE_TOKEN:-}" ]]; then
  log "SONARQUBE_TOKEN is not set; skipping reusable SonarQube MCP startup."
  exit 0
fi

SONARQUBE_ORG="${SONARQUBE_ORG:-opensoft}"

ensure_network() {
  if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
    docker network create "$NETWORK_NAME" >/dev/null
  fi
}

ensure_storage_volume() {
  docker volume create "$STORAGE_VOLUME" >/dev/null
}

remove_legacy_containers() {
  if [[ "$LEGACY_CONTAINER_NAME" != "$CONTAINER_NAME" || "$LEGACY_PROXY_CONTAINER_NAME" != "$PROXY_CONTAINER_NAME" ]]; then
    docker rm -f "$LEGACY_PROXY_CONTAINER_NAME" "$LEGACY_CONTAINER_NAME" >/dev/null 2>&1 || true
  fi
}

ensure_compose_services() {
  export SONARQUBE_MCP_CONTAINER="$CONTAINER_NAME"
  export SONARQUBE_MCP_PROXY_CONTAINER="$PROXY_CONTAINER_NAME"
  export SONARQUBE_MCP_NETWORK="$NETWORK_NAME"
  export SONARQUBE_MCP_STORAGE_VOLUME="$STORAGE_VOLUME"
  export SONARQUBE_MCP_IMAGE="$IMAGE"
  export SONARQUBE_MCP_PROXY_IMAGE="$PROXY_IMAGE"
  export SONARQUBE_MCP_BACKEND_PORT="$BACKEND_PORT"
  export SONARQUBE_MCP_PORT="$PROXY_PORT"
  export SONARQUBE_MCP_HOST_BIND="$HOST_BIND"
  export SONARQUBE_ORG
  export SONARQUBE_TOKEN

  COMPOSE_IGNORE_ORPHANS=True "${COMPOSE_CMD[@]}" \
    -p "$COMPOSE_PROJECT_NAME" \
    -f "$COMPOSE_FILE" \
    up -d
}

ensure_network
ensure_storage_volume
remove_legacy_containers
ensure_compose_services

log "Reusable SonarQube MCP is available at http://${HOST_BIND}:${PROXY_PORT}/mcp"
