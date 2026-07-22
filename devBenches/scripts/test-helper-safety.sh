#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

BIN_DIR="$TMP_ROOT/bin"
DOCKER_LOG="$TMP_ROOT/docker.log"
mkdir -p "$BIN_DIR"

cat > "$BIN_DIR/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-} ${2:-}" in
  "compose version"|"network inspect")
    exit 0
    ;;
  "volume create"|"network create")
    exit 0
    ;;
esac

if [[ "${1:-}" == "compose" ]]; then
  printf 'compose org_set=%s org=%s url=%s\n' \
    "${SONARQUBE_ORG+x}" "${SONARQUBE_ORG:-}" "${SONARQUBE_URL:-}" >> "$DOCKER_LOG"
  exit 0
fi

if [[ "${1:-} ${2:-}" == "container inspect" ]]; then
  exit 0
fi

if [[ "${1:-} ${2:-}" == "image inspect" ]]; then
  if [[ "${3:-}" == "--format" ]]; then
    printf 'sha256:expected\n'
  fi
  exit 0
fi

if [[ "${1:-}" == "inspect" && "${2:-}" == "--format" ]]; then
  case "${3:-}" in
    '{{.Image}}') printf 'sha256:current\n' ;;
    '{{.Config.Image}}') printf 'current:image\n' ;;
    *compose.project*) printf '%s\n' "${MOCK_CURRENT_PROJECT:-expected-project}" ;;
    *compose.service*) printf '%s\n' "${MOCK_CURRENT_SERVICE:-expected-service}" ;;
    *) exit 1 ;;
  esac
  exit 0
fi

if [[ "${1:-} ${2:-}" == "rm -f" ]]; then
  printf 'removed=%s\n' "${3:-}" >> "$DOCKER_LOG"
  exit 0
fi

printf 'unexpected docker invocation: %s\n' "$*" >&2
exit 1
EOF
chmod +x "$BIN_DIR/docker"

run_sonar_case() {
  env -i \
    HOME="$TMP_ROOT/home" \
    PATH="$BIN_DIR:/usr/bin:/bin" \
    DOCKER_LOG="$DOCKER_LOG" \
    SONARQUBE_ENV_FILE="$TMP_ROOT/missing.env" \
    SONARQUBE_TOKEN="test-token" \
    "$@" \
    "$SCRIPT_DIR/ensure-sonarqube-mcp.sh" >/dev/null
}

: > "$DOCKER_LOG"
run_sonar_case SONARQUBE_URL=https://sonarcloud.io SONAR_ORGANIZATION=customer-org
grep -Fx 'compose org_set=x org=customer-org url=https://sonarcloud.io' "$DOCKER_LOG" >/dev/null

: > "$DOCKER_LOG"
run_sonar_case SONARQUBE_URL=https://sonarcloud.io
grep -Fx 'compose org_set=x org=opensoft url=https://sonarcloud.io' "$DOCKER_LOG" >/dev/null

: > "$DOCKER_LOG"
run_sonar_case SONARQUBE_URL=https://sonar.example.test
grep -Fx 'compose org_set= org= url=https://sonar.example.test' "$DOCKER_LOG" >/dev/null

: > "$DOCKER_LOG"
if PATH="$BIN_DIR:$PATH" DOCKER_LOG="$DOCKER_LOG" \
  MOCK_CURRENT_PROJECT=other-project MOCK_CURRENT_SERVICE=other-service \
  "$REPO_ROOT/scripts/reconcile-devcontainer-container.sh" \
    --container protected-container \
    --image expected:image \
    --project expected-project \
    --service expected-service \
    --replace-existing >/dev/null 2>&1; then
  echo "ownership mismatch unexpectedly succeeded" >&2
  exit 1
fi
if grep -q '^removed=' "$DOCKER_LOG"; then
  echo "ownership mismatch removed the protected container" >&2
  exit 1
fi

: > "$DOCKER_LOG"
PATH="$BIN_DIR:$PATH" DOCKER_LOG="$DOCKER_LOG" \
  MOCK_CURRENT_PROJECT=expected-project MOCK_CURRENT_SERVICE=expected-service \
  "$REPO_ROOT/scripts/reconcile-devcontainer-container.sh" \
    --container managed-container \
    --image expected:image \
    --project expected-project \
    --service expected-service \
    --replace-existing >/dev/null
grep -Fx 'removed=managed-container' "$DOCKER_LOG" >/dev/null

printf 'helper safety tests passed\n'
