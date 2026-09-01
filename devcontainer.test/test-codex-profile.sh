#!/usr/bin/env bash
# Focused regression tests for the shared Codex profile launcher.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LAUNCHER="${1:-$REPO_ROOT/base-image/files/codex-profile}"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_file_equals() {
    local expected="$1"
    local actual="$2"
    if ! diff -u "$expected" "$actual"; then
        fail "launcher invocation did not match expected arguments"
    fi
}

PROFILE_BASE="$TEST_ROOT/profiles-home"
PROFILE_DIR="$PROFILE_BASE/profiles/max/max-002"
MANIFEST="$TEST_ROOT/openai-profiles.json"
FAKE_CODEX="$TEST_ROOT/codex"
FAKE_CODEX_LOG="$TEST_ROOT/codex.log"
EXPECTED="$TEST_ROOT/expected.log"

mkdir -p "$PROFILE_DIR"

printf '%s\n' \
    '{"profiles":[{"name":"max-002","email":"test@example.invalid","family":"opensoft","aliases":[],"profilePath":"max/max-002"}]}' \
    > "$MANIFEST"

cat > "$FAKE_CODEX" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: "${FAKE_CODEX_LOG:?}"
{
    printf 'CODEX_HOME=%s\n' "${CODEX_HOME:-}"
    for argument in "$@"; do
        printf 'arg=%s\n' "$argument"
    done
} > "$FAKE_CODEX_LOG"
EOF
chmod +x "$FAKE_CODEX"

run_launcher() {
    local runtime_url="$1"
    shift
    local common_env=(
        "CODEX_BIN=$FAKE_CODEX"
        "CODEX_PROFILES_HOME=$PROFILE_BASE"
        "CODEX_PROFILES_MANIFEST=$MANIFEST"
        "FAKE_CODEX_LOG=$FAKE_CODEX_LOG"
        "WORKBENCHES_SHARED_MCP_HOME=$TEST_ROOT/shared-mcp"
        "WORKBENCHES_DISABLE_DEFAULT_VIBE_MCP=1"
    )
    if [[ "$runtime_url" == "__UNSET__" ]]; then
        env -u CODEX_SONARQUBE_MCP_URL "${common_env[@]}" "$@"
    else
        env "${common_env[@]}" "CODEX_SONARQUBE_MCP_URL=$runtime_url" "$@"
    fi
}

# No runtime URL means the shared profile remains the only MCP URL source.
run_launcher __UNSET__ \
    "$LAUNCHER" run max-002 mcp list
{
    printf 'CODEX_HOME=%s\n' "$PROFILE_DIR"
    printf '%s\n' \
        'arg=-c' \
        'arg=forced_login_method="chatgpt"' \
        'arg=-c' \
        'arg=cli_auth_credentials_store="file"' \
        'arg=mcp' \
        'arg=list'
} > "$EXPECTED"
assert_file_equals "$EXPECTED" "$FAKE_CODEX_LOG"

# An explicitly empty value is also inactive.
run_launcher "" \
    "$LAUNCHER" run max-002 mcp list
assert_file_equals "$EXPECTED" "$FAKE_CODEX_LOG"

# A runtime URL becomes exactly one SonarQube-only override and remains one
# argument even when TOML quoting is required.
SONARQUBE_URL='http://sonarqube-mcp-proxy:64130/mcp?quote="yes"&slash=\segment'
QUOTED_URL="$(jq -Rn --arg value "$SONARQUBE_URL" '$value')"
run_launcher "$SONARQUBE_URL" \
    "$LAUNCHER" run max-002 mcp list --json
{
    printf 'CODEX_HOME=%s\n' "$PROFILE_DIR"
    printf '%s\n' \
        'arg=-c' \
        'arg=forced_login_method="chatgpt"' \
        'arg=-c' \
        'arg=cli_auth_credentials_store="file"' \
        'arg=-c'
    printf 'arg=mcp_servers.sonarqube.url=%s\n' "$QUOTED_URL"
    printf '%s\n' \
        'arg=mcp' \
        'arg=list' \
        'arg=--json'
} > "$EXPECTED"
assert_file_equals "$EXPECTED" "$FAKE_CODEX_LOG"

[[ "$(grep -c '^arg=mcp_servers\.sonarqube\.url=' "$FAKE_CODEX_LOG")" -eq 1 ]] \
    || fail "expected exactly one SonarQube MCP URL override"
[[ "$(grep -c '^arg=mcp_servers\.' "$FAKE_CODEX_LOG")" -eq 1 ]] \
    || fail "launcher changed an unrelated MCP setting"
! grep -q 'SONARQUBE_TOKEN' "$LAUNCHER" \
    || fail "launcher must not read or forward SonarQube tokens"

echo "codex-profile runtime override tests passed"
