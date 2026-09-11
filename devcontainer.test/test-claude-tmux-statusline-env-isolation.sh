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
#
# An end-to-end run alone is not enough to make every one of the seven
# names load-bearing (Copilot's review of an earlier version of this file,
# PR #56 commit 005dc18): claude-profile never reads TMUX_PANE or either
# WORKBENCHES_TMUX_* name at all; the inner test's own two statusline
# assertions overwrite (WORKBENCHES_TMUX_SESSION/PANE to fixed sandbox
# values) or explicitly unset (`env -u ...`) both WORKBENCHES_TMUX_* names
# regardless of what the guard does; and WORKBENCHES_CLAUDE_TMUX only
# changes claude_run_is_interactive's answer when it is exactly "off", not
# the "1" set below. So an end-to-end assertion alone could still pass with
# any of those four silently dropped from the guard's unset list.
#
# This script therefore runs two assertions, in this order:
#   1. Direct — probe the guard's own effect on a freshly started child's
#      environment: none of the seven names may still be set afterward.
#      This alone makes every single name load-bearing, and names exactly
#      which one leaked when it doesn't.
#   2. End-to-end — the real test, run as a subprocess, must still pass
#      underneath the same contamination.
# The direct probe runs first deliberately: if it ran second, a name whose
# absence also breaks the end-to-end run (TMUX, WORKBENCHES_CLAUDE_TMUX_CHILD,
# CLAUDE_LANE) would be caught there first, with a message that describes
# the symptom but does not name the missing variable.

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

# The seven names the guard unsets, paired with representative contaminated
# values: a real-looking tmux socket/pane pair, both WORKBENCHES_CLAUDE_TMUX
# switches, a lane session id, and a lane name — the shape of a live
# claude-profile-launched, lane-started Claude Code pane. Both assertions
# below share this same list and the same contaminated_env built from it.
GUARD_NAMES=(
    TMUX
    TMUX_PANE
    WORKBENCHES_CLAUDE_TMUX
    WORKBENCHES_CLAUDE_TMUX_CHILD
    WORKBENCHES_TMUX_SESSION
    WORKBENCHES_TMUX_PANE
    CLAUDE_LANE
)
GUARD_VALUES=(
    "/tmp/tmux-1000/default,1234,0"
    "%99"
    "1"
    "1"
    "x"
    "%99"
    "some-lane"
)

# PATH excludes lane-start entirely (see header) no matter what the guard
# under test does.
contaminated_env=("PATH=/usr/bin:/bin" "HOME=$HOME")
for i in "${!GUARD_NAMES[@]}"; do
    contaminated_env+=("${GUARD_NAMES[$i]}=${GUARD_VALUES[$i]}")
done

# ---------------------------------------------------------------------------
# 1. Direct: probe the guard's own effect on a freshly started child's
# environment, so every one of the seven names is load-bearing on its own —
# not just the subset an end-to-end run happens to observe.
#
# Locate the guard's `unset ...` statement, however many physical lines its
# backslash continuation spans, and fail loudly if it is no longer there to
# find rather than silently checking nothing. Anchored on the bare `unset `
# keyword (verified the only occurrence in this file), not `unset TMUX `
# specifically: one of the seven mutation rounds this script is proven
# against removes TMUX itself, which would no longer match a pattern that
# required it. `|| true` on the pipeline is required: under this script's
# own set -e -o pipefail, grep finding nothing (the guard truly gone) would
# otherwise abort silently right here instead of reaching the loud "could
# not locate" fail() below.
guard_start_line="$(grep -n '^unset ' "$TARGET_TEST" | head -1 | cut -d: -f1 || true)"
[[ -n "$guard_start_line" ]] \
    || fail "could not locate the env-isolation guard's 'unset ...' line in $TARGET_TEST — did it move or get reworded?"

guard_end_line="$guard_start_line"
while [[ "$(sed -n "${guard_end_line}p" "$TARGET_TEST")" == *\\ ]]; do
    guard_end_line=$((guard_end_line + 1))
done

# A temp copy of the inner test's own source, truncated right after that
# statement (keeping its shebang/set -euo pipefail preamble intact so it
# behaves the same way), with a probe of all seven names appended. The `if`
# form (not `declare -p ... && echo ...`) is required: under this
# preamble's own set -e, a bare `&&`-chained command whose first half fails
# would abort the probe before it ever reports anything — the exact shape
# of failure #52 itself was about.
GUARD_PROBE="$TEST_ROOT/guard-probe.sh"
head -n "$guard_end_line" "$TARGET_TEST" > "$GUARD_PROBE"
{
    printf '\n# --- appended by test-claude-tmux-statusline-env-isolation.sh ---\n'
    printf 'for _guard_check_name in'
    printf ' %s' "${GUARD_NAMES[@]}"
    printf '; do\n'
    printf '    if declare -p "$_guard_check_name" >/dev/null 2>&1; then\n'
    printf '        echo "STILL-SET:$_guard_check_name"\n'
    printf '    fi\n'
    printf 'done\n'
} >> "$GUARD_PROBE"

GUARD_OUT="$TEST_ROOT/guard-probe.log"
set +e
env "${contaminated_env[@]}" "$BASH_BIN" "$GUARD_PROBE" > "$GUARD_OUT" 2>&1
guard_status=$?
set -e

[[ "$guard_status" -eq 0 ]] \
    || fail "guard probe itself errored (exit $guard_status) before it could report which names survived: $(cat "$GUARD_OUT")"

# `|| true` on the pipeline: under set -e -o pipefail, grep finding zero
# STILL-SET lines (the guard doing its job — the expected, common case)
# exits 1, and pipefail makes that the pipeline's status; without `|| true`
# this assignment would abort the script silently instead of falling
# through to the all-clear path below. (Yes, this is the same class of bug
# this whole file exists to catch — found the hard way while writing it.)
still_set="$(grep '^STILL-SET:' "$GUARD_OUT" | cut -d: -f2 | tr '\n' ' ' || true)"
still_set="${still_set% }"
[[ -z "$still_set" ]] \
    || fail "guard did not unset: $still_set (probe output: $(cat "$GUARD_OUT"))"

# ---------------------------------------------------------------------------
# 2. End-to-end: the real test, run as a subprocess, must still pass
# underneath the contamination above.
OUT="$TEST_ROOT/subprocess.log"
set +e
env "${contaminated_env[@]}" "$BASH_BIN" "$TARGET_TEST" "$LAUNCHER" "$STATUSLINE" > "$OUT" 2>&1
status=$?
set -e

[[ "$status" -eq 0 ]] \
    || fail "test-claude-tmux-statusline.sh did not survive representative tmux/lane contamination (exit $status): $(cat "$OUT")"
grep -q 'claude tmux statusline tests passed' "$OUT" \
    || fail "test-claude-tmux-statusline.sh exited 0 but did not print its pass line under contamination: $(cat "$OUT")"

echo "claude tmux statusline env-isolation regression passed"
