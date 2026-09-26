#!/usr/bin/env bash
# Regression tests for remembered Claude profile selection shared by pclaude
# (profile-only) and lclaude (lane-aware).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLAUDE_PROFILE_SOURCE="${1:-$REPO_ROOT/base-image/files/claude-profile}"
PCLAUDE_SOURCE="${2:-$REPO_ROOT/base-image/files/pclaude}"
LCLAUDE_SOURCE="${3:-$REPO_ROOT/base-image/files/lclaude}"

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

PROFILE_BASE="$TEST_ROOT/profiles-home"
MANIFEST="$TEST_ROOT/claude-profiles.json"
FAKE_HOME="$TEST_ROOT/home"
FAKE_BIN="$TEST_ROOT/bin"
CLAUDE_LOG="$TEST_ROOT/claude.log"
ERR_LOG="$TEST_ROOT/stderr.log"
LAST_PROFILE="$PROFILE_BASE/.last-profile"

mkdir -p \
    "$PROFILE_BASE/profiles/opensoft/team/team-002" \
    "$PROFILE_BASE/profiles/opensoft/team/team-003" \
    "$FAKE_HOME" "$FAKE_BIN"

printf '%s\n' '{"profiles":[' \
    '{"name":"team-002","email":"two@example.invalid","family":"testing","aliases":["team002"],"profilePath":"opensoft/team/team-002"},' \
    '{"name":"team-003","email":"three@example.invalid","family":"testing","aliases":["team003"],"profilePath":"opensoft/team/team-003"}' \
    ']}' | tr -d '\n' > "$MANIFEST"
printf '\n' >> "$MANIFEST"

printf '%s\n' '{"name":"team-002","family":"testing","email":"two@example.invalid","aliases":["team002"]}' \
    > "$PROFILE_BASE/profiles/opensoft/team/team-002/.profile.json"
printf '%s\n' '{"name":"team-003","family":"testing","email":"three@example.invalid","aliases":["team003"]}' \
    > "$PROFILE_BASE/profiles/opensoft/team/team-003/.profile.json"

ln -s "$CLAUDE_PROFILE_SOURCE" "$FAKE_BIN/claude-profile"
ln -s "$PCLAUDE_SOURCE" "$FAKE_BIN/pclaude"
ln -s "$LCLAUDE_SOURCE" "$FAKE_BIN/lclaude"

cat > "$FAKE_BIN/claude" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
{
    printf 'CONFIG=%s\n' "${CLAUDE_CONFIG_DIR:-<unset>}"
    printf 'PROFILE=%s\n' "${CLAUDE_PROFILE_NAME:-<unset>}"
    printf 'PROFILE_ONLY=%s\n' "${WORKBENCHES_CLAUDE_PROFILE_ONLY:-<unset>}"
    printf 'ARGS=%s\n' "$*"
} >> "${FAKE_CLAUDE_LOG:?}"
EOF
chmod +x "$FAKE_BIN/claude"

common_env=(
    "PATH=$FAKE_BIN:/usr/bin:/bin"
    "HOME=$FAKE_HOME"
    "CLAUDE_BIN=$FAKE_BIN/claude"
    "CLAUDE_PROFILES_HOME=$PROFILE_BASE"
    "CLAUDE_PROFILES_MANIFEST=$MANIFEST"
    "FAKE_CLAUDE_LOG=$CLAUDE_LOG"
    "WORKBENCHES_CLAUDE_TMUX=off"
    "WORKBENCHES_SHARED_MCP_FAMILIES=disabled"
)

run_ok() {
    env "${common_env[@]}" "$@" >/dev/null 2>"$ERR_LOG" \
        || fail "command failed: $* ($(cat "$ERR_LOG"))"
}

run_fails() {
    if env "${common_env[@]}" "$@" >/dev/null 2>"$ERR_LOG"; then
        fail "command unexpectedly succeeded: $*"
    fi
}

# No remembered profile means no guess and no Claude launch.
run_ok claude-profile
[[ ! -e "$CLAUDE_LOG" ]] || fail "bare claude-profile no longer lists profiles"
run_fails pclaude
grep -q 'no last Claude profile' "$ERR_LOG" \
    || fail "missing-state diagnostic was not actionable: $(cat "$ERR_LOG")"
[[ ! -e "$CLAUDE_LOG" ]] || fail "Claude launched with no remembered profile"

# An explicit alias records only the canonical name after a valid run.
run_ok pclaude team002 --print hello
[[ "$(cat "$LAST_PROFILE")" == team-002 ]] \
    || fail "alias did not persist canonical profile: $(cat "$LAST_PROFILE")"
last_profile_mode="$(stat -c '%a' "$LAST_PROFILE" 2>/dev/null \
    || stat -f '%Lp' "$LAST_PROFILE" 2>/dev/null)"
[[ "$last_profile_mode" == 600 ]] \
    || fail "last-profile mode is $last_profile_mode, expected 600"
grep -q "CONFIG=$PROFILE_BASE/profiles/opensoft/team/team-002" "$CLAUDE_LOG" \
    || fail "explicit alias used the wrong config: $(cat "$CLAUDE_LOG")"
grep -q '^PROFILE=team-002$' "$CLAUDE_LOG" \
    || fail "canonical profile was not exported: $(cat "$CLAUDE_LOG")"
grep -q '^PROFILE_ONLY=1$' "$CLAUDE_LOG" \
    || fail "pclaude did not export profile-only mode: $(cat "$CLAUDE_LOG")"

# The reader falls back to BSD/macOS stat syntax when GNU stat is unavailable.
cat > "$FAKE_BIN/stat" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == -c ]]; then
    exit 1
fi
if [[ "${1:-}" == -f && "${2:-}" == %Lp ]]; then
    printf '600\n'
    exit 0
fi
exit 2
EOF
chmod +x "$FAKE_BIN/stat"
: > "$CLAUDE_LOG"
run_ok pclaude
grep -q '^PROFILE=team-002$' "$CLAUDE_LOG" \
    || fail "BSD stat fallback did not allow the remembered profile"
rm -f "$FAKE_BIN/stat"

# An explicit run verb may omit the profile while still carrying Claude
# options; the option remains in Claude's argv rather than being resolved as a
# profile name.
: > "$CLAUDE_LOG"
run_ok pclaude run --print hello
grep -q '^PROFILE=team-002$' "$CLAUDE_LOG" \
    || fail "run with an option did not reuse the remembered profile"
grep -q '^ARGS=.*--print hello$' "$CLAUDE_LOG" \
    || fail "run with an omitted profile did not preserve Claude arguments: $(cat "$CLAUDE_LOG")"

# Leading launcher options may be the entire wrapper invocation; after they
# are consumed, pclaude still defaults to a remembered-profile run.
: > "$CLAUDE_LOG"
run_ok pclaude --no-lane
grep -q '^PROFILE=team-002$' "$CLAUDE_LOG" \
    || fail "launcher-only options listed profiles instead of running the remembered profile"

# A delimiter makes omitted-profile positional Claude subcommands unambiguous
# without turning an invalid explicit profile into a silent Claude argument.
: > "$CLAUDE_LOG"
run_ok pclaude run -- mcp list
grep -q '^PROFILE=team-002$' "$CLAUDE_LOG" \
    || fail "delimited positional command did not reuse the remembered profile"
grep -q '^ARGS=.*mcp list$' "$CLAUDE_LOG" \
    || fail "delimited positional command was not preserved: $(cat "$CLAUDE_LOG")"
if grep -q '^ARGS=.*-- mcp list$' "$CLAUDE_LOG"; then
    fail "launcher delimiter leaked into Claude arguments: $(cat "$CLAUDE_LOG")"
fi

# A run that fails required lane preflight does not replace the selection.
run_fails pclaude --lane example-1 team003 --print hello
[[ "$(cat "$LAST_PROFILE")" == team-002 ]] \
    || fail "failed lane preflight changed the remembered profile"

# A later lane preflight refusal (after lane-start is found) also leaves the
# remembered selection unchanged.
cat > "$FAKE_BIN/lane-start" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
cat > "$FAKE_BIN/lanes-edit.sh" <<EOF
#!/usr/bin/env bash
case "\${1:-}" in
  session-start|guard) exit 0 ;;
  lane-dir) printf '%s\n' "$TEST_ROOT/missing-lane-checkout"; exit 0 ;;
  *) exit 8 ;;
esac
EOF
chmod +x "$FAKE_BIN/lane-start" "$FAKE_BIN/lanes-edit.sh"
run_fails lclaude --lane example-1 team003 --print hello
[[ "$(cat "$LAST_PROFILE")" == team-002 ]] \
    || fail "late lane preflight refusal changed the remembered profile"
rm -f "$FAKE_BIN/lane-start" "$FAKE_BIN/lanes-edit.sh"

# A lane-start refusal in an existing lane window starts no Claude and must not
# replace the remembered profile.
HANDOFF_PROFILE_LOG="$TEST_ROOT/handoff-profile.log"
cat > "$FAKE_BIN/lane-start" <<EOF
#!/usr/bin/env bash
cat "$LAST_PROFILE" > "$HANDOFF_PROFILE_LOG"
exit 1
EOF
cat > "$FAKE_BIN/lanes-edit.sh" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  session-start|guard) exit 0 ;;
  lane-dir) exit 8 ;;
  *) exit 8 ;;
esac
EOF
cat > "$FAKE_BIN/tmux" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *'#W'*) printf 'example-1\n' ;;
  *'#{pane_pid}'*) printf '999999\n' ;;
  *'#S:#I'*) printf 'fake:0\n' ;;
  *'#{window_id}'*) printf '@1\n' ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$FAKE_BIN/lane-start" "$FAKE_BIN/lanes-edit.sh" "$FAKE_BIN/tmux"
: > "$CLAUDE_LOG"
run_fails TMUX=fake lclaude --lane example-1 team003 --print hello
[[ "$(cat "$LAST_PROFILE")" == team-002 ]] \
    || fail "lane-start refusal changed the remembered profile"
[[ "$(cat "$HANDOFF_PROFILE_LOG")" == team-003 ]] \
    || fail "lane-start did not observe the new profile at handoff time"
[[ ! -s "$CLAUDE_LOG" ]] \
    || fail "lane-start refusal unexpectedly launched Claude: $(cat "$CLAUDE_LOG")"
rm -f "$FAKE_BIN/lane-start" "$FAKE_BIN/lanes-edit.sh" "$FAKE_BIN/tmux"

# Bare pclaude reuses the record and remains profile-only.
: > "$CLAUDE_LOG"
run_ok pclaude
grep -q "CONFIG=$PROFILE_BASE/profiles/opensoft/team/team-002" "$CLAUDE_LOG" \
    || fail "bare pclaude did not reuse team-002: $(cat "$CLAUDE_LOG")"
grep -q '^PROFILE_ONLY=1$' "$CLAUDE_LOG" \
    || fail "bare pclaude lost profile-only mode: $(cat "$CLAUDE_LOG")"

# Status may inspect another profile but must not change run selection.
run_ok pclaude status team003
[[ "$(cat "$LAST_PROFILE")" == team-002 ]] \
    || fail "status changed the remembered profile: $(cat "$LAST_PROFILE")"

# Explicit lclaude remains lane-aware and becomes the shared remembered value.
: > "$CLAUDE_LOG"
run_ok lclaude team003 --print hello
[[ "$(cat "$LAST_PROFILE")" == team-003 ]] \
    || fail "lclaude did not update the shared remembered profile"
grep -q '^PROFILE_ONLY=<unset>$' "$CLAUDE_LOG" \
    || fail "lclaude was incorrectly marked profile-only: $(cat "$CLAUDE_LOG")"

# Bare lclaude uses the same record and remains lane-aware.
: > "$CLAUDE_LOG"
run_ok lclaude
grep -q "CONFIG=$PROFILE_BASE/profiles/opensoft/team/team-003" "$CLAUDE_LOG" \
    || fail "bare lclaude did not reuse team-003: $(cat "$CLAUDE_LOG")"
grep -q '^PROFILE_ONLY=<unset>$' "$CLAUDE_LOG" \
    || fail "bare lclaude was incorrectly marked profile-only: $(cat "$CLAUDE_LOG")"

# A stale record is named and never passed to Claude.
: > "$CLAUDE_LOG"
printf '%s\n' team-deleted > "$LAST_PROFILE"
chmod 600 "$LAST_PROFILE"
run_fails pclaude
grep -q 'team-deleted' "$ERR_LOG" \
    || fail "stale-state diagnostic omitted the profile: $(cat "$ERR_LOG")"
[[ ! -s "$CLAUDE_LOG" ]] || fail "Claude launched with a stale remembered profile"

# Unsafe and malformed records fail closed.
rm -f "$LAST_PROFILE"
printf '%s\n' team-002 > "$TEST_ROOT/target"
ln -s "$TEST_ROOT/target" "$LAST_PROFILE"
run_fails pclaude
grep -qi 'symbolic link\|regular file' "$ERR_LOG" \
    || fail "symlink diagnostic was not explicit: $(cat "$ERR_LOG")"

rm -f "$LAST_PROFILE"
printf 'team-002\nteam-003\n' > "$LAST_PROFILE"
chmod 600 "$LAST_PROFILE"
run_fails pclaude
grep -qi 'one profile name\|single line' "$ERR_LOG" \
    || fail "multiline diagnostic was not explicit: $(cat "$ERR_LOG")"

: > "$LAST_PROFILE"
chmod 600 "$LAST_PROFILE"
run_fails pclaude
grep -qi 'one profile name\|single line' "$ERR_LOG" \
    || fail "empty-state diagnostic was not explicit: $(cat "$ERR_LOG")"

printf '%s\n' team-002 > "$LAST_PROFILE"
chmod 644 "$LAST_PROFILE"
run_fails pclaude
grep -q 'mode 0600' "$ERR_LOG" \
    || fail "unsafe-mode diagnostic was not explicit: $(cat "$ERR_LOG")"

rm -f "$LAST_PROFILE"
mkdir "$LAST_PROFILE"
run_fails pclaude
grep -q 'regular file' "$ERR_LOG" \
    || fail "non-regular diagnostic was not explicit: $(cat "$ERR_LOG")"

echo "claude-profile remembered-profile tests passed"
