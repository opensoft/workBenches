#!/usr/bin/env bash
set -euo pipefail

log() {
  printf '[ensure-sonarqube-mcp] %s\n' "$*" >&2
}

CONTAINER_NAME="${SONARQUBE_MCP_CONTAINER:-devbench-sonarqube-mcp}"
PROXY_CONTAINER_NAME="${SONARQUBE_MCP_PROXY_CONTAINER:-devbench-sonarqube-mcp-proxy}"
NETWORK_NAME="${SONARQUBE_MCP_NETWORK:-devbench-shared}"
STORAGE_VOLUME="${SONARQUBE_MCP_STORAGE_VOLUME:-devbench-sonarqube-mcp-storage}"
IMAGE="${SONARQUBE_MCP_IMAGE:-mcp/sonarqube:latest}"
PROXY_IMAGE="${SONARQUBE_MCP_PROXY_IMAGE:-nginx:alpine}"
BACKEND_PORT="${SONARQUBE_MCP_BACKEND_PORT:-64131}"
PROXY_PORT="${SONARQUBE_MCP_PORT:-64130}"
HOST_BIND="${SONARQUBE_MCP_HOST_BIND:-127.0.0.1}"
SECRET_FILE="${SONARQUBE_ENV_FILE:-$HOME/.config/sonarqube/sonar.env}"
if [[ ! -f "$SECRET_FILE" && -f "$HOME/.config/ledgerlinc/secrets/sonar.env" ]]; then
  SECRET_FILE="$HOME/.config/ledgerlinc/secrets/sonar.env"
fi

case "${1:-}" in
  --stop)
    docker rm -f "$PROXY_CONTAINER_NAME" "$CONTAINER_NAME" >/dev/null 2>&1 || true
    exit 0
    ;;
  --recreate)
    docker rm -f "$PROXY_CONTAINER_NAME" "$CONTAINER_NAME" >/dev/null 2>&1 || true
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

if [[ -f "$SECRET_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$SECRET_FILE"
  set +a
fi

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

container_running() {
  [[ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null || true)" == "true" ]]
}

container_exists() {
  docker inspect "$1" >/dev/null 2>&1
}

ensure_backend() {
  if container_running "$CONTAINER_NAME"; then
    return 0
  fi

  if container_exists "$CONTAINER_NAME"; then
    docker start "$CONTAINER_NAME" >/dev/null
    return 0
  fi

  docker volume create "$STORAGE_VOLUME" >/dev/null

  docker run -d \
    --name "$CONTAINER_NAME" \
    --network "$NETWORK_NAME" \
    --restart unless-stopped \
    --pull=missing \
    --label devbench.shared-service=sonarqube-mcp \
    -e SONARQUBE_TOKEN \
    -e SONARQUBE_ORG \
    -e SONARQUBE_TRANSPORT=http \
    -e SONARQUBE_HTTP_HOST=0.0.0.0 \
    -e SONARQUBE_HTTP_PORT="$BACKEND_PORT" \
    -e SONARQUBE_HTTP_AUTH_MODE=TOKEN \
    -v "$STORAGE_VOLUME:/app/storage" \
    "$IMAGE" >/dev/null
}

ensure_proxy() {
  if container_running "$PROXY_CONTAINER_NAME"; then
    return 0
  fi

  if container_exists "$PROXY_CONTAINER_NAME"; then
    docker start "$PROXY_CONTAINER_NAME" >/dev/null
    return 0
  fi

  docker run -d \
    --name "$PROXY_CONTAINER_NAME" \
    --network "$NETWORK_NAME" \
    --restart unless-stopped \
    --pull=missing \
    --label devbench.shared-service=sonarqube-mcp-proxy \
    -p "${HOST_BIND}:${PROXY_PORT}:${PROXY_PORT}" \
    -e SONARQUBE_TOKEN \
    -e PROXY_PORT="$PROXY_PORT" \
    -e BACKEND_URL="http://${CONTAINER_NAME}:${BACKEND_PORT}" \
    "$PROXY_IMAGE" \
    sh -c 'cat > /etc/nginx/conf.d/default.conf <<EOF
server {
  listen ${PROXY_PORT};
  server_name _;

  location / {
    proxy_http_version 1.1;
    proxy_set_header Authorization "Bearer ${SONARQUBE_TOKEN}";
    proxy_set_header Host \$host;
    proxy_set_header Connection "";
    proxy_buffering off;
    proxy_request_buffering off;
    proxy_cache off;
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
    proxy_pass ${BACKEND_URL};
  }
}
EOF
exec nginx -g "daemon off;"
' >/dev/null
}

ensure_network
ensure_backend
ensure_proxy

log "Reusable SonarQube MCP is available at http://${HOST_BIND}:${PROXY_PORT}/mcp"
