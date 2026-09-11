#!/usr/bin/env bash
# Regression tests for claude-statusline-command.sh's usage-snapshot publisher.
#
# claude-usage-guard.sh (a UserPromptSubmit hook) and the claude-usage command
# both read $HOME/.claude/usage-snapshots/* instead of the statusline payload
# itself, so the publisher block has to keep writing them correctly AND must
# never let a broken write reach the visible status line (fail-quiet).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATUSLINE="${1:-$REPO_ROOT/base-image/files/claude-statusline-command.sh}"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

strip_ansi() {
    sed $'s/\033\[[0-9;]*m//g'
}

# Mirrors the script's own profile_key derivation exactly.
snapshot_key() {
    printf '%s' "$1" | sed 's/[^A-Za-z0-9._-]/_/g'
}

# A non-tmux invocation with a fixed HOME/CLAUDE_CONFIG_DIR, isolated from any
# ambient tmux session so results do not depend on how/where this test runs.
run_statusline() {
    local home_dir="$1" payload="$2"
    env -u TMUX -u TMUX_PANE -u WORKBENCHES_TMUX_SESSION -u WORKBENCHES_TMUX_PANE \
        HOME="$home_dir" CLAUDE_CONFIG_DIR="$PROFILE_CONFIG" COLUMNS=120 \
        bash "$STATUSLINE" <<<"$payload"
}

PROFILE_CONFIG="$TEST_ROOT/profiles/opensoft/team/team-snap"
mkdir -p "$PROFILE_CONFIG"
profile_key=$(snapshot_key "$PROFILE_CONFIG")

SESSION_ID="test-session-abc123"
FIVE_HOUR_PCT=42
FIVE_HOUR_RESET=1999999000
FABLE_WEEKLY_PCT=17
FABLE_WEEKLY_RESET=1999999999
CONTEXT_PCT=55

payload_full=$(jq -n \
    --arg sid "$SESSION_ID" \
    --argjson five_pct "$FIVE_HOUR_PCT" --argjson five_reset "$FIVE_HOUR_RESET" \
    --argjson fable_pct "$FABLE_WEEKLY_PCT" --argjson fable_reset "$FABLE_WEEKLY_RESET" \
    --argjson ctx "$CONTEXT_PCT" \
    '{
        session_id: $sid,
        workspace: {current_dir: "/workspace/project"},
        model: {display_name: "Fable"},
        context_window: {used_percentage: $ctx},
        rate_limits: {
            five_hour: {used_percentage: $five_pct, resets_at: $five_reset},
            seven_day_fable: {used_percentage: $fable_pct, resets_at: $fable_reset}
        }
    }')

# --- Fixture 1: a full rate_limits + context_window payload ----------------

FAKE_HOME="$TEST_ROOT/home"
mkdir -p "$FAKE_HOME"
snap_dir="$FAKE_HOME/.claude/usage-snapshots"
profile_snap="$snap_dir/profile.$profile_key.json"
session_snap="$snap_dir/session.$SESSION_ID.json"

run_statusline "$FAKE_HOME" "$payload_full" >/dev/null

# (a) the profile snapshot file exists at the derived path.
[[ -f $profile_snap ]] || fail "profile snapshot was not written to $profile_snap"

# (b) five_hour/fable_weekly match the payload; reset fields are numbers.
[[ "$(jq -r '.five_hour' "$profile_snap")" == "$FIVE_HOUR_PCT" ]] \
    || fail "profile snapshot five_hour did not match the payload"
[[ "$(jq -r '.fable_weekly' "$profile_snap")" == "$FABLE_WEEKLY_PCT" ]] \
    || fail "profile snapshot fable_weekly did not match the payload"
[[ "$(jq -r '.five_hour_reset' "$profile_snap")" == "$FIVE_HOUR_RESET" ]] \
    || fail "profile snapshot five_hour_reset did not match the payload"
[[ "$(jq -r '.fable_weekly_reset' "$profile_snap")" == "$FABLE_WEEKLY_RESET" ]] \
    || fail "profile snapshot fable_weekly_reset did not match the payload"
[[ "$(jq -r '.five_hour_reset | type' "$profile_snap")" == "number" ]] \
    || fail "five_hour_reset is not a JSON number"
[[ "$(jq -r '.fable_weekly_reset | type' "$profile_snap")" == "number" ]] \
    || fail "fable_weekly_reset is not a JSON number"

# (c) the session-keyed file carries the context value.
[[ -f $session_snap ]] || fail "session snapshot was not written to $session_snap"
[[ "$(jq -r '.context_pct' "$session_snap")" == "$CONTEXT_PCT" ]] \
    || fail "session snapshot context_pct did not match the payload"

echo "usage-snapshot publisher populated both files correctly"

# --- Fixture 2: no rate_limits at all -> fail-quiet nulls, still exit 0 ----

FAKE_HOME_NO_LIMITS="$TEST_ROOT/home-no-limits"
mkdir -p "$FAKE_HOME_NO_LIMITS"
payload_no_limits='{"session_id":"test-session-no-limits","workspace":{"current_dir":"/workspace/project"},"model":{"display_name":"Fable"},"context_window":{"used_percentage":12}}'

set +e
output_no_limits=$(run_statusline "$FAKE_HOME_NO_LIMITS" "$payload_no_limits")
status=$?
set -e
[[ $status -eq 0 ]] || fail "statusline exited $status for a payload with no rate_limits"
[[ "$(wc -l <<<"$output_no_limits")" -eq 4 ]] \
    || fail "statusline did not print a 4-line panel for a payload with no rate_limits"

profile_snap_no_limits="$FAKE_HOME_NO_LIMITS/.claude/usage-snapshots/profile.$profile_key.json"
[[ -f $profile_snap_no_limits ]] \
    || fail "profile snapshot was not written for a payload with no rate_limits"
[[ "$(jq -r '.five_hour' "$profile_snap_no_limits")" == "null" ]] \
    || fail "five_hour was not null when rate_limits was absent"
[[ "$(jq -r '.fable_weekly' "$profile_snap_no_limits")" == "null" ]] \
    || fail "fable_weekly was not null when rate_limits was absent"
[[ "$(jq -r '.five_hour_reset' "$profile_snap_no_limits")" == "null" ]] \
    || fail "five_hour_reset was not null when rate_limits was absent"
[[ "$(jq -r '.fable_weekly_reset' "$profile_snap_no_limits")" == "null" ]] \
    || fail "fable_weekly_reset was not null when rate_limits was absent"

echo "missing rate_limits still exits 0 and publishes fail-quiet nulls"

# --- Fixture 3: an unwritable snapshot directory must not change the ------
#     visible status line (the publisher's own failure stays invisible). ---

FAKE_HOME_WRITABLE="$TEST_ROOT/home-writable"
FAKE_HOME_UNWRITABLE="$TEST_ROOT/home-unwritable"
mkdir -p "$FAKE_HOME_WRITABLE" "$FAKE_HOME_UNWRITABLE/.claude"
# Block `mkdir -p "$HOME/.claude/usage-snapshots"` by occupying that path with
# a plain file instead of a directory. This fails regardless of process uid,
# unlike a read-only-directory simulation which root can bypass.
: >"$FAKE_HOME_UNWRITABLE/.claude/usage-snapshots"

out_writable=$(run_statusline "$FAKE_HOME_WRITABLE" "$payload_full" | strip_ansi)
out_unwritable=$(run_statusline "$FAKE_HOME_UNWRITABLE" "$payload_full" | strip_ansi)

[[ "$out_writable" == "$out_unwritable" ]] \
    || fail "visible status line differed depending on snapshot-directory writability"
[[ -f "$FAKE_HOME_UNWRITABLE/.claude/usage-snapshots" ]] \
    || fail "sentinel file was unexpectedly replaced by a directory"
[[ -f "$FAKE_HOME_WRITABLE/.claude/usage-snapshots/profile.$profile_key.json" ]] \
    || fail "control run with a writable HOME unexpectedly did not publish a snapshot"

echo "an unwritable snapshot directory does not change the visible status line"

echo "claude statusline snapshot tests passed"
