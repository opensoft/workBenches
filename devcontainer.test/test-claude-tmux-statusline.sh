#!/usr/bin/env bash
# Focused regression tests for Claude's tmux-backed profile launcher and panel.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LAUNCHER="${1:-$REPO_ROOT/base-image/files/claude-profile}"
STATUSLINE="${2:-$REPO_ROOT/base-image/files/claude-statusline-command.sh}"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

strip_ansi() {
    sed $'s/\033\[[0-9;]*m//g'
}

PROFILE_BASE="$TEST_ROOT/profiles-home"
PROFILE_DIR="$PROFILE_BASE/profiles/opensoft/team/team-002"
MANIFEST="$TEST_ROOT/claude-profiles.json"
FAKE_BIN="$TEST_ROOT/bin"
FAKE_CLAUDE="$FAKE_BIN/claude"
FAKE_CLAUDE_LOG="$TEST_ROOT/claude.log"
FAKE_TMUX_LOG="$TEST_ROOT/tmux.log"
mkdir -p "$PROFILE_DIR" "$FAKE_BIN"

printf '%s\n' \
    '{"profiles":[{"name":"team-002","email":"test@example.invalid","family":"testing","aliases":["team002"],"profilePath":"opensoft/team/team-002"}]}' \
    > "$MANIFEST"
printf '%s\n' '{"name":"team-002","family":"testing","email":"test@example.invalid","aliases":["team002"]}' \
    > "$PROFILE_DIR/.profile.json"

cat > "$FAKE_CLAUDE" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" > "${FAKE_CLAUDE_LOG:?}"
EOF
chmod +x "$FAKE_CLAUDE"

cat > "$FAKE_BIN/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${FAKE_TMUX_LOG:?}"
EOF
chmod +x "$FAKE_BIN/tmux"

common_env=(
    "PATH=$FAKE_BIN:$PATH"
    "CLAUDE_BIN=$FAKE_CLAUDE"
    "CLAUDE_PROFILES_HOME=$PROFILE_BASE"
    "CLAUDE_PROFILES_MANIFEST=$MANIFEST"
    "FAKE_CLAUDE_LOG=$FAKE_CLAUDE_LOG"
    "FAKE_TMUX_LOG=$FAKE_TMUX_LOG"
    "WORKBENCHES_SHARED_MCP_FAMILIES=disabled"
)

# A terminal-backed profile launch creates and attaches to a named tmux session.
printf -v tty_command 'env'
for value in "${common_env[@]}" "$LAUNCHER" run team002 --resume session-123; do
    printf -v value '%q' "$value"
    tty_command+=" $value"
done
script -qefc "$tty_command" /dev/null >/dev/null
grep -Eq '^new-session -d -s claude-team-002-[0-9]{14}-[0-9]+ ' "$FAKE_TMUX_LOG" \
    || fail "interactive pclaude did not create a profile-named tmux session"
grep -q 'WORKBENCHES_CLAUDE_TMUX_CHILD=1' "$FAKE_TMUX_LOG" \
    || fail "tmux child recursion guard was not exported"
grep -q -- '--resume session-123' "$FAKE_TMUX_LOG" \
    || fail "interactive Claude arguments were not forwarded into tmux"
grep -Eq '^attach-session -t claude-team-002-' "$FAKE_TMUX_LOG" \
    || fail "interactive pclaude did not attach to the created session"
[[ ! -e "$FAKE_CLAUDE_LOG" ]] \
    || fail "fake tmux must own the interactive Claude launch"

# Command-style invocations stay direct and do not create another tmux session.
tmux_lines_before="$(wc -l < "$FAKE_TMUX_LOG")"
env "${common_env[@]}" "$LAUNCHER" run team002 mcp list
[[ "$(wc -l < "$FAKE_TMUX_LOG")" -eq "$tmux_lines_before" ]] \
    || fail "noninteractive mcp command unexpectedly created tmux state"
grep -q 'mcp list$' "$FAKE_CLAUDE_LOG" \
    || fail "noninteractive mcp command did not reach Claude directly"

status_input='{"workspace":{"current_dir":"/workspace/project"},"model":{"display_name":"Fable"},"context_window":{"used_percentage":12}}'
status_config="$TEST_ROOT/status-config"
mkdir -p "$status_config"

# The attach target is first so narrow panels cannot clip it from the right.
panel="$(env CLAUDE_CONFIG_DIR="$status_config" CLAUDE_PROFILE_NAME=team-002 \
    WORKBENCHES_TMUX_SESSION=agent-tower-42 WORKBENCHES_TMUX_PANE=%7 \
    COLUMNS=70 bash "$STATUSLINE" <<< "$status_input" | strip_ansi)"
first_line="${panel%%$'\n'*}"
[[ "$first_line" == '[TMUX] | tmux:agent-tower-42/%7 | [WORK]'* ]] \
    || fail "tmux attach target is not the first panel field: $first_line"

# A direct Claude process reports the missing runtime instead of hiding it.
panel="$(env -u TMUX -u TMUX_PANE -u WORKBENCHES_TMUX_SESSION \
    -u WORKBENCHES_TMUX_PANE CLAUDE_CONFIG_DIR="$status_config" COLUMNS=70 \
    bash "$STATUSLINE" <<< "$status_input" | strip_ansi)"
first_line="${panel%%$'\n'*}"
[[ "$first_line" == '[TMUX] | none | [WORK]'* ]] \
    || fail "non-tmux panel did not display an explicit none state: $first_line"

echo "claude tmux statusline tests passed"
