#!/usr/bin/env bash
# Focused regression tests for Claude's tmux-backed profile launcher and panel.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LAUNCHER="${1:-$REPO_ROOT/base-image/files/claude-profile}"
STATUSLINE="${2:-$REPO_ROOT/base-image/files/claude-statusline-command.sh}"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

# This test drives the real launcher and statusline scripts against a fake
# tmux/claude sandbox built below, then asserts on the fake tmux/claude logs
# that sandbox produces. Both scripts also read tmux identity straight from
# the environment (WORKBENCHES_CLAUDE_TMUX*, TMUX*, WORKBENCHES_TMUX_*), and
# the launcher separately reads CLAUDE_LANE to decide whether to hand the
# launch off to `lane-start` instead of the fake claude. If this test itself
# is run from inside a real tmux session — a live claude-profile-launched
# Claude Code pane included — those variables leak in from the caller and
# are indistinguishable from the sandbox's own state. That alone corrupts
# the assertions below, and it can also abort the launcher outright: with a
# real TMUX inherited but only the fake tmux binary on PATH, the launcher's
# export_tmux_identity() queries tmux, gets back nothing the fake
# understands, and its last command's failure under `set -e` kills the
# launcher before it ever reaches Claude. A leaked CLAUDE_LANE is worse in a
# different way: if a real `lane-start` happens to be on PATH (as it is in
# exactly the lane sessions this test is likeliest to be run from), the
# launcher hands the whole launch to it instead of the fake claude — a test
# run invoking real lane tooling. Mirrors the same guard in
# test-claude-profile-lane-start.sh, extended to also cover
# WORKBENCHES_CLAUDE_TMUX (the opt-out switch claude_run_is_interactive
# reads) and CLAUDE_LANE (the launcher's lane-start hand-off switch). Clear
# all of it before the sandbox runs, so the sandbox's own state is always
# authoritative. (CLAUDE_BIN/CLAUDE_PROFILES_HOME/CLAUDE_PROFILES_MANIFEST/
# WORKBENCHES_SHARED_MCP_FAMILIES are already owned below via common_env's
# explicit assignments on every launcher invocation, so an inherited value
# for any of those is always overridden rather than leaked; CLAUDE_CONFIG_DIR
# is only ever written by the launcher for its children, never read as one
# of its own inputs, so nothing to clear there either.)
unset TMUX TMUX_PANE WORKBENCHES_CLAUDE_TMUX WORKBENCHES_CLAUDE_TMUX_CHILD \
    WORKBENCHES_TMUX_SESSION WORKBENCHES_TMUX_PANE CLAUDE_LANE 2>/dev/null || true

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
status_home="$TEST_ROOT/status-home"
mkdir -p "$status_config" "$status_home"
# The panel prints claude-restart-check's line first when one is installed
# (opensoft/workBenches#119). The seam names nothing here, so the panels
# below are the four lines they always were even on a host whose PATH has the
# real check and whose Claude binary has moved under the session running this.
no_restart_check="$TEST_ROOT/no-claude-restart-check"

# The renderer publishes usage snapshots under $HOME/.claude/usage-snapshots
# regardless of CLAUDE_CONFIG_DIR; pin HOME to a throwaway directory so this
# test never leaves artifacts under the caller's real home directory.

# The attach target is first so narrow panels cannot clip it from the right.
panel="$(env HOME="$status_home" CLAUDE_CONFIG_DIR="$status_config" CLAUDE_PROFILE_NAME=team-002 \
    WORKBENCHES_TMUX_SESSION=agent-tower-42 WORKBENCHES_TMUX_PANE=%7 \
    WORKBENCHES_CLAUDE_RESTART_CHECK_BIN="$no_restart_check" \
    COLUMNS=70 bash "$STATUSLINE" <<< "$status_input" | strip_ansi)"
first_line="${panel%%$'\n'*}"
[[ "$first_line" == '[TMUX] | tmux:agent-tower-42/%7 | [WORK]'* ]] \
    || fail "tmux attach target is not the first panel field: $first_line"

# A direct Claude process reports the missing runtime instead of hiding it.
panel="$(env -u TMUX -u TMUX_PANE -u WORKBENCHES_TMUX_SESSION \
    -u WORKBENCHES_TMUX_PANE HOME="$status_home" CLAUDE_CONFIG_DIR="$status_config" COLUMNS=70 \
    WORKBENCHES_CLAUDE_RESTART_CHECK_BIN="$no_restart_check" \
    bash "$STATUSLINE" <<< "$status_input" | strip_ansi)"
first_line="${panel%%$'\n'*}"
[[ "$first_line" == '[TMUX] | none | [WORK]'* ]] \
    || fail "non-tmux panel did not display an explicit none state: $first_line"

# A RUNNING SESSION IS TOLD WHEN ITS BINARY MOVED (opensoft/workBenches#119;
# openspec/changes/launch-current-claude, claude-session-restart-notice). A
# stub claude-restart-check on PATH stands in for opensoft/openRepoTools'
# command and records its arguments. Claude runs the panel under `/bin/sh -c`,
# which does not exec it, so the script's $PPID is that shell and claude is its
# parent; `render` does the same and records the shell's pid.
restart_bin="$TEST_ROOT/restart-bin"
restart_log="$TEST_ROOT/restart-check.log"
render_pid="$TEST_ROOT/render.pid"
render_json="$TEST_ROOT/render.json"
mkdir -p "$restart_bin"
cat > "$restart_bin/claude-restart-check" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "${RESTART_CHECK_LOG:?}"
[[ -z "${RESTART_CHECK_LINE:-}" ]] || printf '%s\n' "$RESTART_CHECK_LINE"
exit 0
EOF
chmod +x "$restart_bin/claude-restart-check"
render() {
    env -u TMUX -u TMUX_PANE -u WORKBENCHES_TMUX_SESSION -u WORKBENCHES_TMUX_PANE \
        -u WORKBENCHES_CLAUDE_RESTART_CHECK_BIN \
        HOME="$status_home" CLAUDE_CONFIG_DIR="$status_config" COLUMNS=70 "$@" \
        sh -c 'printf "%s\n" "$$" > "$1"; bash "$2" < "$3"; :' render "$render_pid" "$STATUSLINE" "$render_json"
}
jq -c '{version: "2.1.283"} + .' <<<"$status_input" > "$render_json"
restart_text='RESTART NEEDED: running 2.1.283, installed 2.1.284; /ctx at your next breakpoint'

# Not installed: the four-line panel, byte for byte.
absent_panel="$(render WORKBENCHES_CLAUDE_RESTART_CHECK_BIN="$no_restart_check")"
[[ "$(wc -l <<<"$absent_panel")" -eq 4 && "$(strip_ansi <<<"${absent_panel%%$'\n'*}")" == '[TMUX] | none | [WORK]'* ]] \
    || fail "restart check absent: the panel changed: $absent_panel"

# Installed, nothing to say: the same bytes, and it was asked about the
# running version from the JSON and about the shell Claude started the panel in.
rm -f "$restart_log"
quiet_panel="$(render PATH="$restart_bin:$PATH" RESTART_CHECK_LOG="$restart_log")"
[[ "$quiet_panel" == "$absent_panel" ]] \
    || fail "restart check with nothing to say changed the panel: $quiet_panel"
[[ "$(cat "$restart_log")" == "--running 2.1.283 --pid $(cat "$render_pid")" ]] \
    || fail "restart check was not given the JSON version and the panel's parent: $(cat "$restart_log")"

# Installed, the binary moved: its one green line comes FIRST, the four lines
# after it are unchanged, and nothing else is printed.
notice_panel="$(render PATH="$restart_bin:$PATH" RESTART_CHECK_LOG="$restart_log" \
    RESTART_CHECK_LINE=$'\033[32m'"$restart_text"$'\033[0m')"
[[ "${notice_panel%%$'\n'*}" == $'\033[32m'"$restart_text"$'\033[0m' ]] \
    || fail "restart line is not the first panel line: ${notice_panel%%$'\n'*}"
[[ "${notice_panel#*$'\n'}" == "$absent_panel" ]] \
    || fail "restart line changed the rest of the panel: $notice_panel"
[[ "$(wc -l <<<"$notice_panel")" -eq 5 ]] \
    || fail "restart line added more than one line: $notice_panel"

# A JSON with no version (an older Claude) asks without --running.
printf '%s\n' "$status_input" > "$render_json"
render PATH="$restart_bin:$PATH" RESTART_CHECK_LOG="$restart_log" >/dev/null
[[ "$(cat "$restart_log")" == "--pid $(cat "$render_pid")" ]] \
    || fail "restart check was given a running version the JSON did not carry: $(cat "$restart_log")"

echo "claude tmux statusline tests passed"
