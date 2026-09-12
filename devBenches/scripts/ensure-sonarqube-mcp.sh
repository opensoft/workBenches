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

# Host-side Claude/Codex profiles and bench (container) configs must resolve
# SonarQube MCP through different addresses: the host cannot resolve the
# Docker service name without an /etc/hosts entry nobody writes (WSL
# regenerates /etc/hosts on boot), while a bench container cannot reach the
# host's 127.0.0.1 loopback. workbenches-mcp-sync's shared MCP registry
# already supports both (`url` for host, `containerUrl` for a bench), but
# nothing previously taught it the SonarQube proxy's two addresses.
REPO_ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SHARED_MCP_HELPER="$REPO_ROOT_DIR/scripts/workbenches-mcp-sync"
SHARED_MCP_FAMILY="${SONARQUBE_MCP_SHARED_FAMILY:-opensoft}"

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
  while IFS='=' read -r key value || [[ -n "$key" ]]; do
    case "$key" in
      ''|\#*) continue ;;
      SONARQUBE_TOKEN|SONARQUBE_ORG|SONAR_TOKEN|SONAR_ORGANIZATION|SONAR_HOST_URL|SONARQUBE_URL|SONARQUBE_CLOUD_URL)
        export "$key=$value"
        ;;
    esac
  done < "$SECRET_FILE"
fi

SONARQUBE_TOKEN="${SONARQUBE_TOKEN:-${SONAR_TOKEN:-}}"

if [[ -z "${SONARQUBE_TOKEN:-}" ]]; then
  log "SONARQUBE_TOKEN is not set; skipping reusable SonarQube MCP startup."
  exit 0
fi

SONARQUBE_URL="${SONARQUBE_URL:-${SONAR_HOST_URL:-${SONARQUBE_CLOUD_URL:-https://sonarcloud.io}}}"
SONARQUBE_ORG="${SONARQUBE_ORG:-${SONAR_ORGANIZATION:-}}"

# The SonarQube MCP server uses the presence of SONARQUBE_ORG to select Cloud
# mode. Preserve the existing Opensoft default for the supported Cloud
# endpoints, but leave the variable unset for self-hosted SonarQube Server.
if [[ -z "$SONARQUBE_ORG" ]]; then
  case "${SONARQUBE_URL%/}" in
    https://sonarcloud.io|https://sonarqube.us)
      SONARQUBE_ORG="opensoft"
      ;;
    *)
      unset SONARQUBE_ORG
      ;;
  esac
fi

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
  if [[ -n "${SONARQUBE_ORG:-}" ]]; then
    export SONARQUBE_ORG
  else
    unset SONARQUBE_ORG
  fi
  export SONARQUBE_TOKEN
  export SONARQUBE_URL

  COMPOSE_IGNORE_ORPHANS=True "${COMPOSE_CMD[@]}" \
    -p "$COMPOSE_PROJECT_NAME" \
    -f "$COMPOSE_FILE" \
    up -d
}

register_shared_mcp_route() {
  [[ -x "$SHARED_MCP_HELPER" ]] || return 0
  "$SHARED_MCP_HELPER" put-http \
    "$SHARED_MCP_FAMILY" \
    sonarqube \
    "http://${HOST_BIND}:${PROXY_PORT}/mcp" \
    "http://${PROXY_CONTAINER_NAME}:${PROXY_PORT}/mcp" \
    || log "Warning: shared SonarQube MCP registry setup failed."
}

ensure_network
ensure_storage_volume
remove_legacy_containers
ensure_compose_services
register_shared_mcp_route

log "Reusable SonarQube MCP is available at http://${HOST_BIND}:${PROXY_PORT}/mcp"
