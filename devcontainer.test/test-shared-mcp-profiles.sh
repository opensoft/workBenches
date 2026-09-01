#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER="$REPO_ROOT/base-image/files/workbenches-mcp-sync"
CODEX_LAUNCHER="$REPO_ROOT/base-image/files/codex-profile"
CLAUDE_LAUNCHER="$REPO_ROOT/base-image/files/claude-profile"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

export WORKBENCHES_SHARED_MCP_HOME="$TEST_ROOT/shared-mcp"
export WORKBENCHES_MCP_CONTEXT=container
export WORKBENCHES_MCP_SYNC_BIN="$HELPER"

"$HELPER" put-http \
  opensoft \
  vibe-annotations \
  http://127.0.0.1:3846/mcp \
  http://host.docker.internal:3846/mcp >/dev/null

claude_shared_config="$("$HELPER" claude-config opensoft)"
jq -e '.mcpServers["vibe-annotations"].url == "http://host.docker.internal:3846/mcp"' \
  "$claude_shared_config" >/dev/null || fail "Claude did not receive the container endpoint"

CODEX_BASE="$TEST_ROOT/codex-profiles"
CODEX_PROFILE="$CODEX_BASE/profiles/opensoft/team/team-001"
CODEX_MANIFEST="$TEST_ROOT/openai-profiles.json"
FAKE_CODEX="$TEST_ROOT/codex"
FAKE_CODEX_STATE="$TEST_ROOT/codex-state.json"
FAKE_CODEX_LOG="$TEST_ROOT/codex.log"
mkdir -p "$CODEX_PROFILE"
printf '%s\n' '[]' >"$FAKE_CODEX_STATE"
jq -n '{profiles:[{name:"team-001",email:"team-001@example.invalid",family:"opensoft",aliases:["team001"],profilePath:"opensoft/team/team-001"}]}' \
  >"$CODEX_MANIFEST"

cat >"$FAKE_CODEX" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >"$FAKE_CODEX_LOG"
arguments=("$@")
for ((index = 0; index < ${#arguments[@]}; index++)); do
  if [[ "${arguments[$index]}" == mcp && "${arguments[$((index + 1))]:-}" == list ]]; then
    cat "$FAKE_CODEX_STATE"
    exit 0
  fi
  if [[ "${arguments[$index]}" == mcp && "${arguments[$((index + 1))]:-}" == add ]]; then
    name="${arguments[$((index + 2))]}"
    url=""
    for ((cursor = index + 3; cursor < ${#arguments[@]}; cursor++)); do
      if [[ "${arguments[$cursor]}" == --url ]]; then
        url="${arguments[$((cursor + 1))]}"
      fi
    done
    tmp="${FAKE_CODEX_STATE}.tmp"
    jq --arg name "$name" --arg url "$url" '
      map(select(.name != $name))
      + [{name:$name,enabled:true,transport:{type:"streamable_http",url:$url,bearer_token_env_var:null,http_headers:null,env_http_headers:null},startup_timeout_sec:null,tool_timeout_sec:null}]
    ' "$FAKE_CODEX_STATE" >"$tmp"
    mv "$tmp" "$FAKE_CODEX_STATE"
    exit 0
  fi
done
exit 0
EOF
chmod +x "$FAKE_CODEX"

CODEX_BIN="$FAKE_CODEX" \
CODEX_PROFILES_HOME="$CODEX_BASE" \
CODEX_PROFILES_MANIFEST="$CODEX_MANIFEST" \
FAKE_CODEX_STATE="$FAKE_CODEX_STATE" \
FAKE_CODEX_LOG="$FAKE_CODEX_LOG" \
  "$CODEX_LAUNCHER" run team001 mcp add from-codex --url https://codex.example.invalid/mcp >/dev/null

jq -e '.mcpServers["from-codex"].url == "https://codex.example.invalid/mcp"' \
  "$("$HELPER" claude-config opensoft)" >/dev/null || fail "Codex add was not rendered for Claude"

CLAUDE_BASE="$TEST_ROOT/claude-profiles"
CLAUDE_PROFILE="$CLAUDE_BASE/profiles/opensoft/team/team-002"
CLAUDE_MANIFEST="$TEST_ROOT/claude-profiles.json"
FAKE_CLAUDE="$TEST_ROOT/claude"
FAKE_CLAUDE_LOG="$TEST_ROOT/claude.log"
mkdir -p "$CLAUDE_PROFILE"
printf '%s\n' '{"hasCompletedOnboarding":true,"mcpServers":{}}' >"$CLAUDE_PROFILE/.claude.json"
jq -n '{profiles:[{name:"team-002",email:"team-002@example.invalid",family:"opensoft",aliases:["team002"],profilePath:"opensoft/team/team-002"}]}' \
  >"$CLAUDE_MANIFEST"

cat >"$FAKE_CLAUDE" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >"$FAKE_CLAUDE_LOG"
arguments=("$@")
for ((index = 0; index < ${#arguments[@]}; index++)); do
  if [[ "${arguments[$index]}" == mcp \
    && ( "${arguments[$((index + 1))]:-}" == add || "${arguments[$((index + 1))]:-}" == add-json ) ]]; then
    name=""
    url=""
    for ((cursor = index + 2; cursor < ${#arguments[@]}; cursor++)); do
      case "${arguments[$cursor]}" in
        --scope|-s|--transport|-t) cursor=$((cursor + 1)) ;;
        --scope=*|--transport=*) ;;
        --*) ;;
        *)
          if [[ -z "$name" ]]; then name="${arguments[$cursor]}";
          elif [[ -z "$url" ]]; then url="${arguments[$cursor]}"; fi
          ;;
      esac
    done
    tmp="$CLAUDE_CONFIG_DIR/.claude.json.tmp"
    jq --arg name "$name" --arg url "$url" \
      '.mcpServers[$name] = {type:"http",url:$url}' \
      "$CLAUDE_CONFIG_DIR/.claude.json" >"$tmp"
    mv "$tmp" "$CLAUDE_CONFIG_DIR/.claude.json"
  fi
done
exit 0
EOF
chmod +x "$FAKE_CLAUDE"

CLAUDE_BIN="$FAKE_CLAUDE" \
CLAUDE_PROFILES_HOME="$CLAUDE_BASE" \
CLAUDE_PROFILES_MANIFEST="$CLAUDE_MANIFEST" \
FAKE_CLAUDE_LOG="$FAKE_CLAUDE_LOG" \
  "$CLAUDE_LAUNCHER" run team002 mcp add --transport http from-claude https://claude.example.invalid/mcp >/dev/null

jq -e '
  .mcpServers["from-codex"].url == "https://codex.example.invalid/mcp"
  and .mcpServers["from-claude"].url == "https://claude.example.invalid/mcp"
' "$CLAUDE_PROFILE/.claude.json" >/dev/null \
  || fail "Claude profile did not materialize the shared registry"
"$HELPER" codex-args opensoft | grep -Fq 'mcp_servers.from-claude.url=' \
  || fail "Claude add was not rendered for Codex"

CODEX_BIN="$FAKE_CODEX" \
CODEX_PROFILES_HOME="$CODEX_BASE" \
CODEX_PROFILES_MANIFEST="$CODEX_MANIFEST" \
FAKE_CODEX_STATE="$FAKE_CODEX_STATE" \
FAKE_CODEX_LOG="$FAKE_CODEX_LOG" \
  "$CODEX_LAUNCHER" run team001 mcp list >/dev/null
grep -Fq 'mcp_servers.from-claude.url=' "$FAKE_CODEX_LOG" \
  || fail "Codex launcher did not load the Claude-added shared definition"

CLAUDE_BIN="$FAKE_CLAUDE" \
CLAUDE_PROFILES_HOME="$CLAUDE_BASE" \
CLAUDE_PROFILES_MANIFEST="$CLAUDE_MANIFEST" \
FAKE_CLAUDE_LOG="$FAKE_CLAUDE_LOG" \
  "$CLAUDE_LAUNCHER" run team002 mcp list >/dev/null
jq -e '.mcpServers["vibe-annotations"] != null' "$CLAUDE_PROFILE/.claude.json" >/dev/null \
  || fail "Claude launcher did not retain the shared registry"

CLAUDE_BIN="$FAKE_CLAUDE" \
CLAUDE_PROFILES_HOME="$CLAUDE_BASE" \
CLAUDE_PROFILES_MANIFEST="$CLAUDE_MANIFEST" \
FAKE_CLAUDE_LOG="$FAKE_CLAUDE_LOG" \
  "$CLAUDE_LAUNCHER" run team002 mcp remove from-codex >/dev/null
! "$HELPER" has opensoft from-codex || fail "shared removal did not update the registry"
jq -e '.mcpServers["from-codex"] == null' "$CLAUDE_PROFILE/.claude.json" >/dev/null \
  || fail "shared removal left a stale Claude profile definition"

[[ "$(stat -c '%a' "$WORKBENCHES_SHARED_MCP_HOME/opensoft/registry.json")" == 600 ]] \
  || fail "shared registry is not mode 0600"

echo "shared MCP profile tests passed"
