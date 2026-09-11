#!/usr/bin/env bash
# Regression for the environment-isolation guard at the top of
# test-claude-tmux-statusline.sh (`unset TMUX TMUX_PANE
# WORKBENCHES_CLAUDE_TMUX WORKBENCHES_CLAUDE_TMUX_CHILD
# WORKBENCHES_TMUX_SESSION WORKBENCHES_TMUX_PANE CLAUDE_LANE`, added closing
# workBenches#52 via PR #53). devcontainer.test/test.sh always runs that
# test from a clean container shell that never had any of those variables
# set in the first place, so that entry point cannot tell the guard apart
# from no guard at all — a future edit that shrinks or drops a name from
# the unset list would still pass test.sh's run untouched. This is the
# wrapper/subprocess regression Copilot's final review on PR #53 asked for
# (submitted 2026-09-11T13:31:30Z, 29 seconds before the PR merged, and so
# never actioned there): invoke test-claude-tmux-statusline.sh with
# representative tmux/lane variables already set in the *calling*
# environment — the shape of a live claude-profile-launched, lane-started
# Claude Code pane, mirroring workBenches#52's own reproduction — and fail
# unless that test still passes underneath the contamination.
#
# CLAUDE_LANE is the one name on that list that is unsafe to leak with a
# reachable real value: if the guard fails to unset it, claude-profile
# hands the *entire* launch to a real `lane-start` before any tmux or
# interactive check runs (base-image/files/claude-profile, the `lane`
# hand-off near the top of the `run` action). This script cannot trigger
# that for real, regardless of whether the guard under test does its job:
# PATH below is pinned to /usr/bin:/bin, which never contains lane-start (a
# user-local install, e.g. ~/.local/bin) on this repo's own dev hosts or in
# the test container. So a regressed guard can only ever reach
# claude-profile's existing "lane-start missing" refusal (exit 2, no tmux
# session created) — never a real hand-off. Same pattern as the
# refusal_env scenario in test-claude-profile-lane-start.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LAUNCHER="${1:-$REPO_ROOT/base-image/files/claude-profile}"
STATUSLINE="${2:-$REPO_ROOT/base-image/files/claude-statusline-command.sh}"
TARGET_TEST="$SCRIPT_DIR/test-claude-tmux-statusline.sh"
BASH_BIN="$(command -v bash)"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
OUT="$TEST_ROOT/subprocess.log"

# Representative values for every name the guard unsets: a real-looking
# tmux socket/pane pair, both WORKBENCHES_CLAUDE_TMUX switches, a lane
# session id, and a lane name. PATH excludes lane-start entirely (see
# header) no matter what the guard under test does.
contaminated_env=(
    "PATH=/usr/bin:/bin"
    "HOME=$HOME"
    "TMUX=/tmp/tmux-1000/default,1234,0"
    "TMUX_PANE=%99"
    "WORKBENCHES_CLAUDE_TMUX=1"
    "WORKBENCHES_CLAUDE_TMUX_CHILD=1"
    "WORKBENCHES_TMUX_SESSION=x"
    "WORKBENCHES_TMUX_PANE=%99"
    "CLAUDE_LANE=some-lane"
)

set +e
env "${contaminated_env[@]}" "$BASH_BIN" "$TARGET_TEST" "$LAUNCHER" "$STATUSLINE" > "$OUT" 2>&1
status=$?
set -e

[[ "$status" -eq 0 ]] \
    || fail "test-claude-tmux-statusline.sh did not survive representative tmux/lane contamination (exit $status): $(cat "$OUT")"
grep -q 'claude tmux statusline tests passed' "$OUT" \
    || fail "test-claude-tmux-statusline.sh exited 0 but did not print its pass line under contamination: $(cat "$OUT")"

echo "claude tmux statusline env-isolation regression passed"
