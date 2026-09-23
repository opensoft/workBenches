#!/usr/bin/env bash
# Focused regression tests for claude-profile's opt-in --lane / CLAUDE_LANE
# hand-off to lane-start (opensoft/brett-wip, lanes/lane-start): without a
# lane named, the launcher's behaviour must be byte-for-byte unchanged; with
# one named, the final Claude launch is handed to `lane-start <lane> --
# <the same claude args>` instead of exec'd directly, with CLAUDE_BIN and
# CLAUDE_CONFIG_DIR carried over so lane-start starts the same Claude under
# the same profile.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LAUNCHER="${1:-$REPO_ROOT/base-image/files/claude-profile}"

# This test's own scenarios (a plain terminal with no lane, and a terminal
# already inside tmux) must not be undermined by ambient lane/tmux state
# inherited from whatever shell runs the test — including a shell that is
# itself a claude-profile-launched tmux child (WORKBENCHES_CLAUDE_TMUX_CHILD=1)
# or already inside some other tmux session (TMUX set to a real socket).
#
# THE LANE VARS WERE MISSING HERE (found post-merge of opensoft/workBenches#96,
# lane openRepoTools-3, 2026-09-15): this suite's own comment already promised
# "ambient lane... state... must not reach the launcher", but the unset list
# only ever covered tmux identity, never CLAUDE_LANE (precedence 1 for WHICH
# lane), CLAUDE_NO_LANE (an override that wins over --lane/CLAUDE_LANE
# entirely, per claude-profile's own --help) or CLAUDE_LANE_DIR (rung 1 of
# the SEPARATE directory-resolution order, not the lane-name one) — three
# vars whose ambient leakage this suite's own scenarios must not inherit.
# Run from a shell that is itself bound to a lane (CLAUDE_LANE=<that lane> in
# the environment, ordinary for an agent running this suite from inside its
# own lane), scenario 0's "no --lane, no CLAUDE_LANE" baseline inherited that
# ambient CLAUDE_LANE anyway, resolved a lane nobody asked for, handed the
# whole call to the fake lane-start — which this suite's own fake, correctly
# simulating a real one, never runs Claude through — and failed with "claude
# args did not arrive unchanged" for a claude.log that was never going to
# exist. Pre-existing and NOT a regression of #96: reproduced identically
# against the launcher and this suite as they stood immediately before #96
# merged. #96's new "lane defect capture: <path>" breadcrumb only made the
# fake lane-start's involvement visible on the FIRST line of the failure;
# the cause was always this suite's own incomplete isolation, matched here
# to the fuller list test-claude-profile-amendment-11.sh already uses.
unset TMUX TMUX_PANE WORKBENCHES_CLAUDE_TMUX WORKBENCHES_CLAUDE_TMUX_CHILD \
    WORKBENCHES_CLAUDE_WINDOW WORKBENCHES_CLAUDE_WINDOW_ID \
    WORKBENCHES_CLAUDE_WINDOW_REF WORKBENCHES_TMUX_SESSION \
    WORKBENCHES_TMUX_PANE CLAUDE_LANE CLAUDE_NO_LANE CLAUDE_LANE_DIR \
    LANES_WORKSTATION LANES_HOST LANES_OS LANES_CONTAINER PROJECTS_ROOT \
    2>/dev/null || true

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
FAKE_LANE_START="$FAKE_BIN/lane-start"
FAKE_LANE_START_LOG="$TEST_ROOT/lane-start.log"
FAKE_LANE_START_ENV="$TEST_ROOT/lane-start.env"
mkdir -p "$PROFILE_DIR" "$FAKE_BIN"
if [[ "${LAUNCHER##*/}" == lclaude ]]; then
    launcher_dir="$(dirname "$LAUNCHER")"
    ln -s "$launcher_dir/pclaude" "$FAKE_BIN/pclaude"
    ln -s "$launcher_dir/claude-profile" "$FAKE_BIN/claude-profile"
fi

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
case "${1:-}" in
    display-message) printf 'fake\n' ;;
esac
EOF
chmod +x "$FAKE_BIN/tmux"

cat > "$FAKE_LANE_START" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" > "${FAKE_LANE_START_LOG:?}"
{
    printf 'CLAUDE_BIN=%s\n' "${CLAUDE_BIN:-}"
    printf 'CLAUDE_CONFIG_DIR=%s\n' "${CLAUDE_CONFIG_DIR:-}"
} > "${FAKE_LANE_START_ENV:?}"
EOF
chmod +x "$FAKE_LANE_START"

# --lane's realistic case is a terminal already inside tmux (a lane is always
# started from an existing tmux window; lane-start itself refuses otherwise),
# which is also the simplest to simulate: TMUX set means claude_run_is_interactive
# is false, so the launcher does not try to wrap a NEW tmux session around it.
common_env=(
    "PATH=$FAKE_BIN:$PATH"
    "CLAUDE_BIN=$FAKE_CLAUDE"
    "CLAUDE_PROFILES_HOME=$PROFILE_BASE"
    "CLAUDE_PROFILES_MANIFEST=$MANIFEST"
    "FAKE_CLAUDE_LOG=$FAKE_CLAUDE_LOG"
    "FAKE_TMUX_LOG=$FAKE_TMUX_LOG"
    "FAKE_LANE_START_LOG=$FAKE_LANE_START_LOG"
    "FAKE_LANE_START_ENV=$FAKE_LANE_START_ENV"
    "WORKBENCHES_SHARED_MCP_FAMILIES=disabled"
    "TMUX=fake-session"
    # opensoft/workBenches#95: this suite is about the argv hand-off shape,
    # not the lane defect capture's own keep/delete semantics (pinned in
    # test-claude-profile-lane-default.sh), so 0 keeps every fake lane-start
    # call here — always instant, having no interactive session to hold open
    # — from being treated as a "fast exit" and leaving a kept capture file
    # behind in /tmp on every run of this suite.
    "WORKBENCHES_CLAUDE_LANE_DEFECT_SECONDS=0"
    # Copilot round 1 on opensoft/workBenches#96: belt and braces beside the
    # override above — a test-local TMPDIR means even a scenario that someday
    # exercises a kept capture here is cleaned by this file's own EXIT trap
    # rather than left in the real host /tmp.
    "TMPDIR=$TEST_ROOT"
)

expected_claude_args='--allow-dangerously-skip-permissions --dangerously-skip-permissions --permission-mode bypassPermissions'

# ---------------------------------------------------------------------------
# 0. --help documents --lane / CLAUDE_LANE (the Land proof's own command).
env "${common_env[@]}" "$LAUNCHER" --help > "$TEST_ROOT/help.out"
grep -q -- '--lane' "$TEST_ROOT/help.out" || fail "--help does not document --lane"
grep -q 'CLAUDE_LANE' "$TEST_ROOT/help.out" || fail "--help does not document CLAUDE_LANE"
grep -q 'lane-start' "$TEST_ROOT/help.out" || fail "--help does not mention lane-start"

# ---------------------------------------------------------------------------
# 1. No --lane, no CLAUDE_LANE: behaviour is the plain, direct Claude exec —
# lane-start is never invoked, and Claude receives exactly the same args.
env "${common_env[@]}" "$LAUNCHER" run team002 --resume session-1 >/dev/null
grep -Fxq -- "$expected_claude_args --resume session-1" "$FAKE_CLAUDE_LOG" \
    || fail "baseline: claude args did not arrive unchanged ($(cat "$FAKE_CLAUDE_LOG" 2>/dev/null))"
[[ ! -e "$FAKE_LANE_START_LOG" ]] \
    || fail "baseline: lane-start was invoked with no --lane/CLAUDE_LANE named"
rm -f "$FAKE_CLAUDE_LOG"

# ---------------------------------------------------------------------------
# 2. --lane hands the final launch to lane-start, with CLAUDE_BIN and
# CLAUDE_CONFIG_DIR set for it, and never touches Claude directly.
env "${common_env[@]}" "$LAUNCHER" --lane openRepoShape-2 run team002 --resume session-2 >/dev/null
[[ ! -e "$FAKE_CLAUDE_LOG" ]] \
    || fail "--lane: Claude was exec'd directly instead of being handed to lane-start"
[[ -e "$FAKE_LANE_START_LOG" ]] \
    || fail "--lane: lane-start was never invoked"
grep -Fxq -- "openRepoShape-2 -- $expected_claude_args --resume session-2" "$FAKE_LANE_START_LOG" \
    || fail "--lane: lane-start did not receive 'openRepoShape-2 -- <claude args>' ($(cat "$FAKE_LANE_START_LOG"))"
grep -Fxq "CLAUDE_BIN=$FAKE_CLAUDE" "$FAKE_LANE_START_ENV" \
    || fail "--lane: lane-start did not see CLAUDE_BIN=$FAKE_CLAUDE ($(cat "$FAKE_LANE_START_ENV"))"
grep -Fxq "CLAUDE_CONFIG_DIR=$PROFILE_DIR" "$FAKE_LANE_START_ENV" \
    || fail "--lane: lane-start did not see CLAUDE_CONFIG_DIR=$PROFILE_DIR ($(cat "$FAKE_LANE_START_ENV"))"
rm -f "$FAKE_LANE_START_LOG" "$FAKE_LANE_START_ENV"

# ---------------------------------------------------------------------------
# 3. Missing lane-start refuses (exit 2, names the fix) before any tmux
# session is created — even on the genuinely interactive path (a real pty,
# no ambient TMUX), where claude_run_is_interactive would otherwise be true
# and start_profile_tmux would fire.
NO_LANE_START_BIN="$TEST_ROOT/bin-no-lane-start"
mkdir -p "$NO_LANE_START_BIN"
if [[ "${LAUNCHER##*/}" == lclaude ]]; then
    ln -s "$launcher_dir/pclaude" "$NO_LANE_START_BIN/pclaude"
    ln -s "$launcher_dir/claude-profile" "$NO_LANE_START_BIN/claude-profile"
fi
cp "$FAKE_CLAUDE" "$NO_LANE_START_BIN/claude"
cp "$FAKE_BIN/tmux" "$NO_LANE_START_BIN/tmux"
NO_LANE_TMUX_LOG="$TEST_ROOT/tmux-no-lane-start.log"

# THE ACT THE REFUSAL NAMES IS CHOSEN BY CAPABILITY — `R-A11-13` (A11 Addendum
# 3 on new-workstation#20, ratified by Brett Heap 2026-09-13 "a11 addendum 3
# yes"). The launcher asks the installed `openRepoTools --help` whether it
# places the lane tools; where it does not, the act is the `scripts/link-estates`
# of the repository `~/.agents/workspace.yaml` names. So this scenario brings its
# own HOME and its own manifest: what is pinned is that the refusal names THIS
# machine's workspace repository, and a suite that read the real `$HOME` would
# pass or fail on whatever the workstation running it happens to have.
REFUSAL_HOME="$TEST_ROOT/refusal-home"
mkdir -p "$REFUSAL_HOME/.agents"
printf 'repository: opensoft/estate-wip\npath: %s/estate-wip\n' "$TEST_ROOT" \
    > "$REFUSAL_HOME/.agents/workspace.yaml"

refusal_env=(
    # A real lane-start may already be installed (e.g. ~/.local/bin on a
    # workstation whose workspace repository has run its scripts/link-estates)
    # — PATH must exclude it entirely to simulate it being genuinely absent,
    # not just shadowed. /usr/bin and /bin cover every standard tool the
    # launcher and the fakes need (jq, mktemp, date, coreutils).
    "PATH=$NO_LANE_START_BIN:/usr/bin:/bin"
    "HOME=$REFUSAL_HOME"
    "CLAUDE_BIN=$NO_LANE_START_BIN/claude"
    "CLAUDE_PROFILES_HOME=$PROFILE_BASE"
    "CLAUDE_PROFILES_MANIFEST=$MANIFEST"
    "FAKE_CLAUDE_LOG=$TEST_ROOT/claude-no-lane-start.log"
    "FAKE_TMUX_LOG=$NO_LANE_TMUX_LOG"
    "WORKBENCHES_SHARED_MCP_FAMILIES=disabled"
    "CLAUDE_LANE=openRepoShape-2"
)
printf -v tty_command 'env'
for value in "${refusal_env[@]}" "$LAUNCHER" run team002 --resume session-3; do
    printf -v value '%q' "$value"
    tty_command+=" $value"
done
set +e
script -qefc "$tty_command" "$TEST_ROOT/typescript-refusal.log" >/dev/null
refusal_status=$?
set -e
[[ "$refusal_status" -eq 2 ]] \
    || fail "missing lane-start: exit status was $refusal_status, not 2"
grep -q 'lane-start' "$TEST_ROOT/typescript-refusal.log" \
    || fail "missing lane-start: refusal did not mention lane-start"
# THIS MACHINE HAS NO CAPABLE `openRepoTools` AND NO LOCAL CHECKOUT YET
# (scenario 3b below covers the capable-tool case), so `lane_start_install_act`
# falls to its workspace.yaml branch and, with the checkout not present, prints
# the CLONE form -- never a hardcoded `opensoft/brett-wip`, one operator's own
# estate, but THIS machine's own workspace.yaml repository (`R-A11-13`).
# Amendment 9 adoption act 4b (`opensoft/workBenches#74`) does not change this
# branch: it deletes workBenches' OWN duplicate writers of the skill and the
# `/swap` command, not this fallback, which is `base-image/files/claude-profile`
# and is unchanged by 4b's merge.
grep -q "$TEST_ROOT/estate-wip/scripts/link-estates" "$TEST_ROOT/typescript-refusal.log" \
    || fail "missing lane-start: the refusal did not name the fix this machine can use — the scripts/link-estates of the repository its workspace.yaml names (R-A11-13)"
grep -q 'opensoft/estate-wip' "$TEST_ROOT/typescript-refusal.log" \
    || fail "missing lane-start: the refusal names no repository to clone, so link-estates stands with nothing in front of it (R-A11-13)"
grep -q 'brett-wip' "$TEST_ROOT/typescript-refusal.log" \
    && fail "missing lane-start: the refusal names a repository this machine never chose (R-A11-13)"
[[ ! -s "$NO_LANE_TMUX_LOG" ]] \
    || fail "missing lane-start: a tmux command ran before the refusal ($(cat "$NO_LANE_TMUX_LOG"))"

# 3b. ...AND ON A MACHINE WHOSE `openRepoTools` PLACES THE LANE TOOLS, THE SAME
# REFUSAL NAMES `openRepoTools --install` INSTEAD — the act workBenches' own
# setup.sh already runs, so the fix is a step this estate has and not a second
# installer. The capability is the installed tool's own `--help` and nothing
# else, so a fake one carrying Amendment 9 act 3's line is the whole scenario.
ORT_REFUSAL_BIN="$TEST_ROOT/bin-openrepotools"
mkdir -p "$ORT_REFUSAL_BIN"
cat > "$ORT_REFUSAL_BIN/openRepoTools" <<'ORTEOF'
#!/usr/bin/env bash
printf '%s\n' 'openRepoTools --install   install park, resume, status, lane-start, lanes-edit.sh'
ORTEOF
chmod +x "$ORT_REFUSAL_BIN/openRepoTools"
printf -v tty_command 'env'
for value in "${refusal_env[@]}" "PATH=$ORT_REFUSAL_BIN:$NO_LANE_START_BIN:/usr/bin:/bin" \
    "$LAUNCHER" run team002 --resume session-3b; do
    printf -v value '%q' "$value"
    tty_command+=" $value"
done
set +e
script -qefc "$tty_command" "$TEST_ROOT/typescript-refusal-ort.log" >/dev/null
refusal_ort_status=$?
set -e
[[ "$refusal_ort_status" -eq 2 ]] \
    || fail "missing lane-start, openRepoTools present: exit status was $refusal_ort_status, not 2"
grep -q 'openRepoTools --install' "$TEST_ROOT/typescript-refusal-ort.log" \
    || fail "missing lane-start: an openRepoTools that places the lane tools is not the act named (R-A11-13)"
grep -q 'link-estates' "$TEST_ROOT/typescript-refusal-ort.log" \
    && fail "missing lane-start: the superseded mechanism is named beside the one that works (R-A11-13)"

# ---------------------------------------------------------------------------
# 4. CLAUDE_LANE (env, no --lane flag) works the same as --lane.
env "${common_env[@]}" CLAUDE_LANE=openRepoShape-2 "$LAUNCHER" run team002 --resume session-4 >/dev/null
[[ ! -e "$FAKE_CLAUDE_LOG" ]] \
    || fail "CLAUDE_LANE: Claude was exec'd directly instead of being handed to lane-start"
grep -Fxq -- "openRepoShape-2 -- $expected_claude_args --resume session-4" "$FAKE_LANE_START_LOG" \
    || fail "CLAUDE_LANE: lane-start did not receive 'openRepoShape-2 -- <claude args>' ($(cat "$FAKE_LANE_START_LOG"))"

echo "claude-profile lane-start hand-off tests passed"
