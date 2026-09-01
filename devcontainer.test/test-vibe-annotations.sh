#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="$REPO_ROOT/scripts/vibe-annotations.compose.yml"
ENSURE_SCRIPT="$REPO_ROOT/scripts/ensure-vibe-annotations.sh"
LAUNCHER="$REPO_ROOT/base-image/files/codex-profile"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

bash -n "$ENSURE_SCRIPT"
bash -n "$LAUNCHER"

VIBE_ANNOTATIONS_HOME_DIR="$TEST_ROOT/vibe" \
  docker compose -f "$COMPOSE_FILE" config --quiet

grep -q '127.0.0.1}:3846:3846' "$COMPOSE_FILE" \
  || fail "Vibe service must remain loopback-only on the host"
grep -q 'restart: unless-stopped' "$COMPOSE_FILE" \
  || fail "Vibe service must survive Docker restarts"
grep -q '/workspace/projects/.workbenches/vibe' "$COMPOSE_FILE" \
  || fail "Vibe attachment paths must be visible through the standard projects mount"

PROFILE_BASE="$TEST_ROOT/profiles-home"
PROFILE_DIR="$PROFILE_BASE/profiles/max/max-002"
MANIFEST="$TEST_ROOT/openai-profiles.json"
FAKE_CODEX="$TEST_ROOT/codex"
FAKE_CODEX_LOG="$TEST_ROOT/codex.log"
mkdir -p "$PROFILE_DIR"
printf '%s\n' \
  '{"profiles":[{"name":"max-002","email":"test@example.invalid","family":"opensoft","aliases":[],"profilePath":"max/max-002"}]}' \
  > "$MANIFEST"
cat > "$FAKE_CODEX" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
for argument in "$@"; do
  printf 'arg=%s\n' "$argument"
done > "$FAKE_CODEX_LOG"
EOF
chmod +x "$FAKE_CODEX"

VIBE_URL='http://host.docker.internal:3846/mcp?quote="yes"'
env \
  WORKBENCHES_SHARED_MCP_HOME="$TEST_ROOT/shared-mcp" \
  CODEX_BIN="$FAKE_CODEX" \
  CODEX_PROFILES_HOME="$PROFILE_BASE" \
  CODEX_PROFILES_MANIFEST="$MANIFEST" \
  CODEX_VIBE_ANNOTATIONS_MCP_URL="$VIBE_URL" \
  FAKE_CODEX_LOG="$FAKE_CODEX_LOG" \
  "$LAUNCHER" run max-002 mcp list

QUOTED_URL="$(jq -Rn --arg value "$VIBE_URL" '$value')"
grep -Fxq "arg=mcp_servers.vibe-annotations.url=$QUOTED_URL" "$FAKE_CODEX_LOG" \
  || fail "Codex profile launcher did not pass the quoted Vibe MCP URL"
[[ "$(grep -c '^arg=mcp_servers\.vibe-annotations\.url=' "$FAKE_CODEX_LOG")" -eq 1 ]] \
  || fail "Codex profile launcher must pass exactly one Vibe MCP override"

echo "Vibe Annotations shared-service tests passed"
