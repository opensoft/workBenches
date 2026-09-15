#!/usr/bin/env bash
# Regression tests for claude-profile's LANE DEFAULT — lane-collision-protocol
# Amendment 8(c), and its Amendment 18 Addendum 1 picker (opensoft/workBenches#79).
# `--lane` used to be opt-in; a `run` that starts a conversation now resolves
# the lane itself, in this order:
#
#   1. --lane / CLAUDE_LANE            -> handed to lane-start bare
#   2. the current tmux window's name, when `lanes-edit.sh register-row`
#      answers 0 for it                -> handed to lane-start bare
#   3. THE PICKER: `lane`, on PATH, given a terminal to ask on, inside
#      tmux only (Amendment 18 Addendum 1, clause (i-5))
#                                      -> `lane` runs bare in the pane and
#                                         this launcher exits with its status
#   4. nothing                         -> today's behaviour, plus one line,
#                                         and not even that where the clause
#                                         (e) SessionStart hook is ensured
#
# and never refuses on ITS OWN ACCOUNT — A8 Addendum 2 R-A8-3, the ruling on
# F-W1: a missing lanes-edit.sh, no tmux to take a window in, and `--no-lane`
# all end in a Claude. Step 3 is now the one exception, and it is `lane`'s own
# contract rather than a refusal: `lane` exit 0 covers BOTH the pick being
# ACTED ON and a decline (`q`, blank) of a question that had a lane on it; exit
# 8 is narrower than "the operator quit" — it means there was NOTHING THERE TO
# PICK at all, a decline included. Either way this launcher is left with
# NOTHING to start, because starting a Claude behind a pick already acted on —
# or behind a decline nobody asked to be overridden — is worse than the lane
# collision this protocol exists to prevent. `lane` exit 2, A REFUSAL, falls
# through to step 4 — and so does exit 1, A READ FAILED, documented as
# pre-pick and no riskier a fall-through than 2's PROVIDED the window's name
# agrees nothing was taken (`lane`'s AVAILABLE branch execs into a launch
# that renames this window and exits with whatever THAT run ends with, so a
# renamed window means 1/2/64 are kept exactly like an acted-on pick's
# 0 — Copilot round 2 on opensoft/workBenches#82, `claude-profile:1743`); a
# status `lane --help` does not document at all gets no such benefit of the
# doubt either way and is propagated exactly as 0/8 are (same PR, round 1,
# `claude-profile:1704`). Missing `lane-start` no longer skips this step
# either (round 1, `claude-profile:1698`): two of the picker's three
# branches never touch it.
# `--yes`/`--confirm` are gone from this order entirely: they were
# lane-start's, for the swap-record guess step 3 used to be before Amendment 18
# Addendum 1 replaced it with the picker.
# Everything the launcher shells out to is faked here — tmux, lanes-edit.sh,
# lane-start, lane and claude — so the assertions are about the launcher's own
# resolution and nothing else.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LAUNCHER="${1:-$REPO_ROOT/base-image/files/claude-profile}"

# Ambient lane/tmux state from the shell running this test — including a shell
# that is itself a claude-profile-launched tmux child — must not reach the
# launcher: every scenario below sets the tmux and lane state it means to test.
unset TMUX TMUX_PANE WORKBENCHES_CLAUDE_TMUX WORKBENCHES_CLAUDE_TMUX_CHILD \
    WORKBENCHES_CLAUDE_WINDOW WORKBENCHES_TMUX_SESSION WORKBENCHES_TMUX_PANE \
    CLAUDE_LANE CLAUDE_NO_LANE LANES_WORKSTATION 2>/dev/null || true

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

# A scenario is one run of the launcher; an assertion is one check made about
# it. Both are counted and printed, because a scenario that silently stops
# running — or a `launch` that never happened — is otherwise invisible in a
# suite whose only output is the word "passed" (F-W6). Every check below ends
# `|| fail "…"; assertion`, so the counter advances exactly when the check
# passed and `fail` has already exited when it did not. The scenario count is
# pinned as well as printed, so deleting one fails the suite rather than
# quietly changing a number; the assertion count is printed and not pinned,
# because checks are added to existing scenarios all the time and a scenario
# that stops running is the thing worth catching.
EXPECTED_SCENARIOS=33
scenarios=0
assertions=0
scenario() { scenarios=$((scenarios + 1)); }
assertion() { assertions=$((assertions + 1)); }

PROFILE_BASE="$TEST_ROOT/profiles-home"
PROFILE_DIR="$PROFILE_BASE/profiles/opensoft/team/team-002"
MANIFEST="$TEST_ROOT/claude-profiles.json"
FAKE_BIN="$TEST_ROOT/bin"
FAKE_CLAUDE="$FAKE_BIN/claude"
CLAUDE_LOG="$TEST_ROOT/claude.log"
TMUX_LOG="$TEST_ROOT/tmux.log"
LANE_START_LOG="$TEST_ROOT/lane-start.log"
LANES_EDIT_LOG="$TEST_ROOT/lanes-edit.log"
LANE_PICKER_LOG="$TEST_ROOT/lane-picker.log"
ERR_LOG="$TEST_ROOT/stderr.log"
# A HOME of this test's own: lanes_edit_bin's last resort is the
# ~/projects/xFactory/lanes-edit.sh symlink the protocol names, and the real
# one is installed on the workstation that runs this.
FAKE_HOME="$TEST_ROOT/home"
mkdir -p "$PROFILE_DIR" "$FAKE_BIN" "$FAKE_HOME"

printf '%s\n' \
    '{"profiles":[{"name":"team-002","email":"test@example.invalid","family":"testing","aliases":["team002"],"profilePath":"opensoft/team/team-002"}]}' \
    > "$MANIFEST"
printf '%s\n' '{"name":"team-002","family":"testing","email":"test@example.invalid","aliases":["team002"]}' \
    > "$PROFILE_DIR/.profile.json"

cat > "$FAKE_CLAUDE" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${FAKE_CLAUDE_LOG:?}"
EOF

# `display-message -p '#W'` is the window name the launcher resolves a lane
# from; '#S' and '#{pane_id}' are export_tmux_identity's, unrelated.
#
# `rename-window` matters because it is the one act of lane-start's the
# launcher can OBSERVE: taking a lane renames the window to it, so the name
# read back after lane-start ran says whether it took the lane or declined it.
# A scenario that needs that distinction sets FAKE_TMUX_WINDOW_FILE and the
# name lives there; every other scenario keeps the static FAKE_TMUX_WINDOW.
cat > "$FAKE_BIN/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${FAKE_TMUX_LOG:?}"
case "${1:-}" in
    display-message)
        case "${3:-}" in
            '#W')
                if [[ -n "${FAKE_TMUX_WINDOW_FILE:-}" && -s "${FAKE_TMUX_WINDOW_FILE}" ]]; then
                    cat "$FAKE_TMUX_WINDOW_FILE"
                else
                    printf '%s\n' "${FAKE_TMUX_WINDOW:-claude}"
                fi
                ;;
            *) printf 'fake\n' ;;
        esac
        ;;
    rename-window)
        [[ -z "${FAKE_TMUX_WINDOW_FILE:-}" ]] || printf '%s\n' "${2:-}" > "$FAKE_TMUX_WINDOW_FILE"
        ;;
esac
EOF

# The lane register, read-only, as Amendment 8 has the launcher read it:
#   register-row <name>  0 = <name> is a lane with a row, 8 = no row,
#                        2 = not even a lane-shaped name
#   swapped [<ws>]       0 = rows `<lane>\t<UTC>\t<window>`, most recent
#                        first; 8 = none; 2 = a lanes-edit.sh from before
#                        Amendment 8, which has no such subcommand
cat > "$FAKE_BIN/lanes-edit.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
{
    printf 'argv=%s\n' "$*"
    printf 'LANES_NO_FETCH=%s\n' "${LANES_NO_FETCH:-}"
} >> "${FAKE_LANES_EDIT_LOG:?}"
# A lanes-edit.sh from before Amendment 8 has no `swapped` case AT ALL, so it
# answers the unknown-subcommand line below — which is the real one's answer
# too. One that HAS the subcommand can still exit 2 for a usage error of its
# own. Same status, two different situations, and only the words tell them
# apart (F-W4). This is decided before the case rather than by breaking out of
# it: `break` is meaningless outside a loop, so a fake that used one answered
# the swapped arm anyway and this scenario tested nothing it claimed to.
if [[ -n "${FAKE_SWAPPED_UNKNOWN:-}" && "${1:-}" == swapped ]]; then
    echo "unknown subcommand '${1:-}'" >&2
    exit 2
fi
case "${1:-}" in
    register-row)
        if [[ -n "${FAKE_LANE_WITH_ROW:-}" && "${2:-}" == "${FAKE_LANE_WITH_ROW}" ]]; then
            printf '| %s | row |\n' "$2"
            exit 0
        fi
        exit "${FAKE_REGISTER_ROW_OTHER:-8}"
        ;;
    swapped)
        if [[ "${FAKE_SWAPPED_STATUS:-8}" -eq 0 || -n "${FAKE_SWAPPED_ROWS_ANYWAY:-}" ]]; then
            printf '%b' "${FAKE_SWAPPED_ROWS:-}"
        fi
        exit "${FAKE_SWAPPED_STATUS:-8}"
        ;;
esac
echo "unknown subcommand '${1:-}'" >&2
exit 2
EOF

# lane-start logs the argv it was launched with, and answers --help with
# whatever help this scenario says it has — which is how the launcher decides
# whether this lane-start knows --confirm/--yes at all.
cat > "$FAKE_BIN/lane-start" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == --help ]]; then
    printf '%s\n' "${FAKE_LANE_START_HELP:-}"
    exit 0
fi
printf '%s\n' "$*" >> "${FAKE_LANE_START_LOG:?}"
# The lane is the last argument before `--`; everything after it is Claude's.
lane_argument=""; rest=(); seen=false
for argument in "$@"; do
    if [[ "$seen" == true ]]; then rest+=("$argument")
    elif [[ "$argument" == -- ]]; then seen=true
    else lane_argument="$argument"
    fi
done
# What a DECLINED confirm does. `exit2` is the interim brett-wip#4 lane-start,
# which exits 2 and launches nothing; `bare` is the one A8 Addendum 2 R-A8-3
# rules for, which launches Claude itself with no lane and exits 0. `took2` is
# neither: it TOOK the lane — renaming the window, as lane-start does — and the
# Claude it exec'd exited 2 on its own. Unset is a lane-start that took the
# lane and whose Claude exited 0.
case "${FAKE_LANE_START_DECLINE:-}" in
    exit2) exit 2 ;;
    bare)
        "${CLAUDE_BIN:?}" ${rest[@]+"${rest[@]}"}
        exit 0
        ;;
    took2)
        tmux rename-window "$lane_argument" >/dev/null 2>&1 || true
        "${CLAUDE_BIN:?}" ${rest[@]+"${rest[@]}"}
        exit 2
        ;;
    defect)
        # lanes-edit.sh live-holder's own DEFECT wording (decision 8(e)), read
        # by lane-start before it asks the confirm question at all: a live
        # FORK is never a holder, so lane-start still asks, and this fake
        # answers the question the same way `bare` does but launches NOTHING
        # itself — isolating whether THE LAUNCHER, not lane-start, is the one
        # that stops rather than starts a second live process on the fork.
        echo "DEFECT: d1ac715c is a live FORK of lane $lane_argument's transcript (pid 1721264, bg, cwd /workspace/projects/openRepoTools) — it is NOT a holder of this lane and must not write the register. Retire it: lane-end $lane_argument --retire 1721264" >&2
        exit 0
        ;;
    defect_taken)
        # The SAME DEFECT, answered Y: a live fork is never a holder (decision
        # 8(e)) and does not stand in front of the question, so taking the
        # lane in THIS window anyway — retiring the fork as a separate act —
        # is a legitimate answer. The window IS renamed and Claude IS
        # launched, exactly as an ordinary take, isolating that claude-profile
        # must key its new stop on the window staying UNRENAMED (the `defect`
        # case above), never on the DEFECT line existing by itself.
        echo "DEFECT: d1ac715c is a live FORK of lane $lane_argument's transcript (pid 1721264, bg, cwd /workspace/projects/openRepoTools) — it is NOT a holder of this lane and must not write the register. Retire it: lane-end $lane_argument --retire 1721264" >&2
        tmux rename-window "$lane_argument" >/dev/null 2>&1 || true
        "${CLAUDE_BIN:?}" ${rest[@]+"${rest[@]}"}
        exit 0
        ;;
esac
EOF

# THE PICKER (lane-collision-protocol Amendment 18 Addendum 1, clause (i-5)).
# `lane` does not exist yet on any real machine (opensoft/openRepoTools#43
# builds it in parallel), so this fake stands in for its whole contract: it
# logs the argv it was run with — bare, always, per clause (i-5) — and exits
# with whatever this scenario says its pick came to. Exit 0 is a pick ACTED
# ON, exit 8 is a QUIT or nothing to pick, exit 2 is A REFUSAL; this launcher
# never hands it `--dir`, `--confirm`, `--resume` or anything else.
#
# FAKE_LANE_RENAME simulates the AVAILABLE branch's real shape: `lane` does
# not run and wait for the launch it picks, it `exec`s straight into
# `pclaude --lane <lane> <profile>`, which — through lane-start — renames the
# window the moment it takes the lane (Amendment 5(f)) and THEN exits with
# whatever that whole chain, Claude included, ends with. A scenario that sets
# this renames the window BEFORE exiting with FAKE_LANE_EXIT, so the fake can
# stand in for "a lane WAS taken and this status is Claude's own" as well as
# for `lane`'s own pre-pick statuses (Copilot round 2 on #82,
# `claude-profile:1743`).
cat > "$FAKE_BIN/lane" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${FAKE_LANE_LOG:?}"
[[ -z "${FAKE_LANE_RENAME:-}" ]] || tmux rename-window "$FAKE_LANE_RENAME" >/dev/null 2>&1 || true
exit "${FAKE_LANE_EXIT:-8}"
EOF

chmod +x "$FAKE_CLAUDE" "$FAKE_BIN/tmux" "$FAKE_BIN/lanes-edit.sh" "$FAKE_BIN/lane-start" "$FAKE_BIN/lane"

AMENDMENT_8_HELP='OPTIONS
  --dir <path>     the lane s checkout
  --confirm        ask on the tty before taking a window whose name is not
                   the lane
  --yes            skip that question
  -h, --help'
OLD_HELP='OPTIONS
  --dir <path>     the lane s checkout
  --dry-run        print every step
  -h, --help'

# PATH carries the fakes and nothing else that could answer for them: a real
# lane-start and a real lanes-edit.sh are installed in ~/.local/bin and
# ~/projects/xFactory on a workstation that has run brett-wip's link-estates.
# TMUX set means claude_run_is_interactive is false, so the launcher resolves
# the lane in this process instead of re-exec'ing into a new tmux session
# (scenario 10 covers that side).
common_env=(
    "PATH=$FAKE_BIN:/usr/bin:/bin"
    "HOME=$FAKE_HOME"
    "CLAUDE_BIN=$FAKE_CLAUDE"
    "CLAUDE_PROFILES_HOME=$PROFILE_BASE"
    "CLAUDE_PROFILES_MANIFEST=$MANIFEST"
    "FAKE_CLAUDE_LOG=$CLAUDE_LOG"
    "FAKE_TMUX_LOG=$TMUX_LOG"
    "FAKE_LANE_START_LOG=$LANE_START_LOG"
    "FAKE_LANES_EDIT_LOG=$LANES_EDIT_LOG"
    "FAKE_LANE_LOG=$LANE_PICKER_LOG"
    "FAKE_LANE_START_HELP=$AMENDMENT_8_HELP"
    "WORKBENCHES_SHARED_MCP_FAMILIES=disabled"
    "LANES_WORKSTATION=Eagle"
    "TMUX=fake-session"
)

claude_args='--allow-dangerously-skip-permissions --dangerously-skip-permissions --permission-mode bypassPermissions'
note='no lane for this window; run lane-start <repo> <n> inside it'

reset_logs() {
    rm -f "$CLAUDE_LOG" "$TMUX_LOG" "$LANE_START_LOG" "$LANES_EDIT_LOG" "$LANE_PICKER_LOG" "$ERR_LOG"
}

# launch <scenario env>... -- <launcher args>...
#
# STDIN IS ALWAYS /dev/null HERE — never a terminal — so THE PICKER (step 3,
# Amendment 18 Addendum 1) never fires by accident in a scenario that is not
# testing it: every scenario below that reaches step 3 with nothing to offer
# is thereby testing "no terminal on stdin", the same fall-through no `lane` on
# PATH gets, whether or not it says so. Scenarios that must prove the picker
# DOES fire use `tty_launch` below instead, which gives it a real one.
launch() {
    local -a scenario_env=()
    while [[ $# -gt 0 && "$1" != "--" ]]; do
        scenario_env+=("$1")
        shift
    done
    shift
    reset_logs
    scenario
    set +e
    env "${common_env[@]}" "${scenario_env[@]}" "$LAUNCHER" "$@" \
        </dev/null >/dev/null 2>"$ERR_LOG"
    launch_status=$?
    set -e
}

lane_start_argv() { cat "$LANE_START_LOG" 2>/dev/null || true; }
lane_picker_argv() { cat "$LANE_PICKER_LOG" 2>/dev/null || true; }

# tty_launch <scenario env>... -- <launcher args>...
#
# A REAL pty on stdin AND stdout (via `script -qefc`), so THE PICKER's own
# `[[ -t 0 ]]` (step 3, Amendment 18 Addendum 1) reads true here where
# `launch`'s /dev/null makes it false — this is how a scenario proves the
# picker DOES fire. `-e` is `script`'s own flag to return the wrapped
# command's exit status rather than its own, so `tty_launch_status` is
# `env ... "$LAUNCHER" ...`'s status and not `script`'s.
tty_launch() {
    local -a scenario_env=()
    while [[ $# -gt 0 && "$1" != "--" ]]; do
        scenario_env+=("$1")
        shift
    done
    shift
    reset_logs
    local tty_command value
    printf -v tty_command 'env'
    for value in "${common_env[@]}" "${scenario_env[@]}" "$LAUNCHER" "$@"; do
        printf -v value '%q' "$value"
        tty_command+=" $value"
    done
    scenario
    set +e
    script -qefc "$tty_command" "$TEST_ROOT/typescript.log" >/dev/null
    tty_launch_status=$?
    set -e
}

# ---------------------------------------------------------------------------
# 0. --help documents the default and the way out of it.
scenario
env "${common_env[@]}" "$LAUNCHER" --help > "$TEST_ROOT/help.out"
grep -q -- '--no-lane' "$TEST_ROOT/help.out" || fail "--help does not document --no-lane"; assertion
grep -q 'CLAUDE_NO_LANE' "$TEST_ROOT/help.out" || fail "--help does not document CLAUDE_NO_LANE"; assertion
grep -q 'THE LANE DEFAULT' "$TEST_ROOT/help.out" || fail "--help does not document the lane default"; assertion
grep -q -- '--lane' "$TEST_ROOT/help.out" || fail "--help no longer documents --lane"; assertion
grep -q 'CLAUDE_LANE' "$TEST_ROOT/help.out" || fail "--help no longer documents CLAUDE_LANE"; assertion
grep -q -- '--yes' "$TEST_ROOT/help.out" \
    && fail "--help still promises --yes, which is passed nowhere (F-W2)"; assertion

# ---------------------------------------------------------------------------
# 1. The window's own name, when the register has a row for it: the lane, and
# --yes — the operator is standing in the lane's window, there is nothing to
# ask. The record is not read TO RESOLVE A LANE: precedence 3's own read,
# `lanes-edit.sh window-lane`, is never made, because precedence 2 answered
# above it. (Amendment 11(3) gives the launcher one other reason to read
# `swapped` — the lane's own recorded DIRECTORY, rung 2 of SPEC §4's four —
# and that is a question about a directory, not about which lane this is.)
launch \
    "FAKE_TMUX_WINDOW=openRepoProject-1" \
    "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=someOtherLane-9\t2026-09-12T17:04Z\tclaude-x:0\n" \
    -- run team002 --resume session-w
[[ -e "$LANE_START_LOG" ]] || fail "window lane: lane-start was never invoked"; assertion
grep -Fxq -- "openRepoProject-1 -- $claude_args --resume session-w" "$LANE_START_LOG" \
    || fail "window lane: lane-start argv was '$(lane_start_argv)'"; assertion
grep -q -- '--yes' "$LANE_START_LOG" \
    && fail "window lane: --yes was passed, and it is inert without --confirm (F-W2)"; assertion
[[ ! -e "$CLAUDE_LOG" ]] || fail "window lane: Claude was exec'd directly"; assertion
grep -Fq 'argv=register-row openRepoProject-1' "$LANES_EDIT_LOG" \
    || fail "window lane: register-row was not asked about the window name"; assertion
grep -Fq 'argv=window-lane' "$LANES_EDIT_LOG" \
    && fail "window lane: precedence 3 was read even though the window answered"; assertion
grep -Fxq 'LANES_NO_FETCH=1' "$LANES_EDIT_LOG" \
    || fail "window lane: the register read was not made with LANES_NO_FETCH=1"; assertion
grep -q "$note" "$ERR_LOG" && fail "window lane: printed the no-lane note anyway"; assertion

# ---------------------------------------------------------------------------
# 2. THE PICKER (lane-collision-protocol Amendment 18 Addendum 1, clause
# (i-5)). Window is not a lane and nothing names it, `lane` is on PATH and
# stdin is a REAL terminal (tty_launch), so this launcher hands it the pane —
# BARE, no `--dir`, no `--confirm`, no `--resume`, nothing at all — and STOPS.
# `lane` exit 0 is the pick ACTED ON: an available lane through lane-start
# (another launch of this same launcher), a live one through the attach, an
# elsewhere one through the handoff request — any of which may already have
# started a Claude of its own, so this launcher starts NOTHING behind it and
# exits with `lane`'s own status instead.
tty_launch "FAKE_TMUX_WINDOW=claude" "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    "FAKE_LANE_EXIT=0" -- run team002 --resume session-picker-acted
[[ "$tty_launch_status" -eq 0 ]] \
    || fail "picker acted on: the launcher exited $tty_launch_status instead of lane's own 0"; assertion
[[ -e "$LANE_PICKER_LOG" ]] || fail "picker acted on: lane was never invoked"; assertion
[[ -z "$(lane_picker_argv)" ]] \
    || fail "picker acted on: lane argv was '$(lane_picker_argv)', not bare"; assertion
[[ ! -e "$LANE_START_LOG" ]] \
    || fail "picker acted on: this launcher also ran lane-start ('$(lane_start_argv)')"; assertion
[[ ! -e "$CLAUDE_LOG" ]] \
    || fail "picker acted on: this launcher also launched a Claude of its own"; assertion

# 2b. `lane` exit 8 is a QUIT, or nothing was there to pick. Declining the
# picker is not asking for a bare session instead (F-W1's own reasoning, aimed
# the other way): this launcher starts nothing here either, and exits with
# `lane`'s status exactly as an acted-on pick does.
tty_launch "FAKE_TMUX_WINDOW=claude" "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    "FAKE_LANE_EXIT=8" -- run team002 --resume session-picker-quit
[[ "$tty_launch_status" -eq 8 ]] \
    || fail "picker quit: the launcher exited $tty_launch_status instead of lane's own 8"; assertion
[[ -e "$LANE_PICKER_LOG" ]] || fail "picker quit: lane was never invoked"; assertion
[[ ! -e "$LANE_START_LOG" ]] \
    || fail "picker quit: this launcher also ran lane-start ('$(lane_start_argv)')"; assertion
[[ ! -e "$CLAUDE_LOG" ]] \
    || fail "picker quit: this launcher launched a Claude of its own after a quit"; assertion

# 2c. `lane` exit 2 is A REFUSAL — not an answer at all — and it falls through
# to step 4 exactly as no `lane` on PATH or no terminal does: a bare Claude,
# and one line naming why.
tty_launch "FAKE_TMUX_WINDOW=claude" "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    "FAKE_LANE_EXIT=2" -- run team002 --resume session-picker-refused
[[ "$tty_launch_status" -eq 0 ]] \
    || fail "picker refused: the launcher exited $tty_launch_status instead of falling through"; assertion
[[ -e "$LANE_PICKER_LOG" ]] || fail "picker refused: lane was never invoked"; assertion
[[ ! -e "$LANE_START_LOG" ]] \
    || fail "picker refused: lane-start was invoked ('$(lane_start_argv)')"; assertion
grep -Fxq -- "$claude_args --resume session-picker-refused" "$CLAUDE_LOG" \
    || fail "picker refused: Claude did not receive its arguments unchanged"; assertion
grep -q 'lane exited 2' "$TEST_ROOT/typescript.log" \
    || fail "picker refused: the reason was not named ($(cat "$TEST_ROOT/typescript.log"))"; assertion
grep -q "$note" "$TEST_ROOT/typescript.log" || fail "picker refused: the note was not printed"; assertion

# 2c-1. `lane` exit 1 — A READ FAILED (`lane --help`'s own words, never "there
# are no lanes", Amendment 7(d)) — falls through exactly as exit 2 does
# (Copilot round on #82, `claude-profile:1704`): `lane`'s own `die` for it
# runs during the read phase, provably before any pick, so this is no riskier
# a fall-through than a refusal is.
tty_launch "FAKE_TMUX_WINDOW=claude" "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    "FAKE_LANE_EXIT=1" -- run team002 --resume session-picker-readfailed
[[ "$tty_launch_status" -eq 0 ]] \
    || fail "picker read failed: the launcher exited $tty_launch_status instead of falling through"; assertion
[[ -e "$LANE_PICKER_LOG" ]] || fail "picker read failed: lane was never invoked"; assertion
grep -Fxq -- "$claude_args --resume session-picker-readfailed" "$CLAUDE_LOG" \
    || fail "picker read failed: Claude did not receive its arguments unchanged"; assertion
grep -q 'lane exited 1' "$TEST_ROOT/typescript.log" \
    || fail "picker read failed: the reason was not named ($(cat "$TEST_ROOT/typescript.log"))"; assertion

# 2c-2. A STATUS `lane --help` DOES NOT NAME AT ALL — a signal (130), a crash
# — is NEVER read as a refusal (Copilot round on #82, `claude-profile:1704`):
# unlike 1 and 2, this launcher cannot prove `lane` failed before a pick, so
# treating it as safe to walk past could start a SECOND Claude behind
# whatever `lane` already did. It is propagated exactly as an ACTED-ON pick
# would be.
tty_launch "FAKE_TMUX_WINDOW=claude" "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    "FAKE_LANE_EXIT=130" -- run team002 --resume session-picker-signal
[[ "$tty_launch_status" -eq 130 ]] \
    || fail "picker undocumented status: the launcher exited $tty_launch_status instead of lane's own 130"; assertion
[[ -e "$LANE_PICKER_LOG" ]] || fail "picker undocumented status: lane was never invoked"; assertion
[[ ! -e "$LANE_START_LOG" ]] \
    || fail "picker undocumented status: this launcher also ran lane-start ('$(lane_start_argv)')"; assertion
[[ ! -e "$CLAUDE_LOG" ]] \
    || fail "picker undocumented status: this launcher started a bare Claude behind an unrecognised status"; assertion

# 2c-3. AND A DOCUMENTED STATUS BEHIND A RENAMED WINDOW IS NEVER PRE-PICK
# EITHER (Copilot round 2 on #82, `claude-profile:1743`): `lane`'s AVAILABLE
# branch does not run and wait for the launch it picks, it `exec`s straight
# into one that renames this window the moment lane-start takes the lane
# (Amendment 5(f)) and THEN exits with whatever that whole chain ends with —
# Claude's own status, in the ordinary case, which can plausibly BE 1 or 2
# just as `lane`'s own pre-pick codes can. The window says which: renamed
# here, so this status is Claude's, not lane's, and starting a bare Claude
# behind it would be the second process this whole protocol exists to
# prevent.
WINDOW_FILE="$TEST_ROOT/tmux-window-picker-taken.name"
printf 'claude\n' > "$WINDOW_FILE"
tty_launch "FAKE_TMUX_WINDOW_FILE=$WINDOW_FILE" "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    "FAKE_LANE_EXIT=2" "FAKE_LANE_RENAME=openRepoProject-1" \
    -- run team002 --resume session-picker-taken-then-2
[[ "$tty_launch_status" -eq 2 ]] \
    || fail "picker took a lane, status 2 after: the launcher exited $tty_launch_status instead of lane's own 2"; assertion
[[ -e "$LANE_PICKER_LOG" ]] || fail "picker took a lane, status 2 after: lane was never invoked"; assertion
[[ ! -e "$CLAUDE_LOG" ]] \
    || fail "picker took a lane, status 2 after: this launcher started a SECOND Claude behind the one lane already took"; assertion
[[ "$(cat "$WINDOW_FILE")" == openRepoProject-1 ]] \
    || fail "picker took a lane, status 2 after: the window was not left renamed for the lane ('$(cat "$WINDOW_FILE")')"; assertion

# 2d. No `lane` on PATH at all — a machine opensoft/openRepoTools#43 has not
# reached yet. Given the SAME terminal 2/2b/2c had, step 3 still answers
# nothing, exactly as a `lane` that refused does: a bare Claude, one line, and
# the picker never even attempted.
NO_LANE_PICKER_BIN="$TEST_ROOT/bin-no-lane-picker"
mkdir -p "$NO_LANE_PICKER_BIN"
cp "$FAKE_CLAUDE" "$NO_LANE_PICKER_BIN/claude"
cp "$FAKE_BIN/tmux" "$NO_LANE_PICKER_BIN/tmux"
cp "$FAKE_BIN/lanes-edit.sh" "$NO_LANE_PICKER_BIN/lanes-edit.sh"
cp "$FAKE_BIN/lane-start" "$NO_LANE_PICKER_BIN/lane-start"
chmod +x "$NO_LANE_PICKER_BIN"/*
tty_launch "PATH=$NO_LANE_PICKER_BIN:/usr/bin:/bin" "FAKE_TMUX_WINDOW=claude" \
    "FAKE_LANE_WITH_ROW=openRepoProject-1" -- run team002 --resume session-nolanebin
[[ "$tty_launch_status" -eq 0 ]] \
    || fail "no lane on PATH: the launcher exited $tty_launch_status"; assertion
[[ ! -e "$LANE_PICKER_LOG" ]] \
    || fail "no lane on PATH: something answered for lane ('$(lane_picker_argv)')"; assertion
[[ ! -e "$LANE_START_LOG" ]] \
    || fail "no lane on PATH: lane-start was invoked ('$(lane_start_argv)')"; assertion
grep -Fxq -- "$claude_args --resume session-nolanebin" "$CLAUDE_LOG" \
    || fail "no lane on PATH: Claude did not receive its arguments unchanged"; assertion
grep -q "$note" "$TEST_ROOT/typescript.log" || fail "no lane on PATH: the note was not printed"; assertion

# 2e. --lane keeps skipping the picker (clause (i-5)): given the SAME terminal
# and the SAME `lane` on PATH that 2/2b/2c would have used, the operator's own
# word at precedence 1 never lets the launch reach step 3 at all.
tty_launch "FAKE_TMUX_WINDOW=claude" "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    -- --lane spoken-bypass run team002 --resume session-lane-bypass
[[ ! -e "$LANE_PICKER_LOG" ]] \
    || fail "--lane bypass: the picker ran anyway ('$(lane_picker_argv)')"; assertion
grep -Fxq -- "spoken-bypass -- $claude_args --resume session-lane-bypass" "$LANE_START_LOG" \
    || fail "--lane bypass: lane-start argv was '$(lane_start_argv)'"; assertion

# 2f. LANE-START MISSING DOES NOT SKIP THE PICKER (Copilot round on #82,
# `claude-profile:1698`): two of `lane`'s three branches — LIVE HERE and BOUND
# ELSEWHERE — never touch lane-start at all, so a workstation that has `lane`
# and a terminal but is missing lane-start still hands the picker the pane
# rather than giving up before it is even tried. A REFUSAL (exit 2) falls
# through to precedence 5 exactly as it would with lane-start present,
# landing on the SAME lane-start-missing notice 9a pins — proving the picker
# was tried and lane-start, not the picker, is what precedence 5 blames.
NO_LANE_START_BIN="$TEST_ROOT/bin-no-lane-start"
mkdir -p "$NO_LANE_START_BIN"
cp "$FAKE_CLAUDE" "$NO_LANE_START_BIN/claude"
cp "$FAKE_BIN/tmux" "$NO_LANE_START_BIN/tmux"
cp "$FAKE_BIN/lanes-edit.sh" "$NO_LANE_START_BIN/lanes-edit.sh"
cp "$FAKE_BIN/lane" "$NO_LANE_START_BIN/lane"
chmod +x "$NO_LANE_START_BIN"/*
tty_launch "PATH=$NO_LANE_START_BIN:/usr/bin:/bin" "FAKE_TMUX_WINDOW=claude" \
    "FAKE_LANE_EXIT=2" -- run team002 --resume session-nolanestart-refused
[[ "$tty_launch_status" -eq 0 ]] \
    || fail "no lane-start, picker refused: the launcher exited $tty_launch_status"; assertion
[[ -e "$LANE_PICKER_LOG" ]] \
    || fail "no lane-start, picker refused: the picker was skipped instead of tried"; assertion
[[ -z "$(lane_picker_argv)" ]] \
    || fail "no lane-start, picker refused: lane argv was '$(lane_picker_argv)', not bare"; assertion
grep -Fxq -- "$claude_args --resume session-nolanestart-refused" "$CLAUDE_LOG" \
    || fail "no lane-start, picker refused: Claude did not receive its arguments unchanged"; assertion
grep -q 'lane-start is not on PATH' "$TEST_ROOT/typescript.log" \
    || fail "no lane-start, picker refused: precedence 5 did not name lane-start ($(cat "$TEST_ROOT/typescript.log"))"; assertion
grep -q "$note" "$TEST_ROOT/typescript.log" \
    && fail "no lane-start, picker refused: the standing note told the operator to run the tool that is missing"; assertion

# 2g. AND WHERE THE PICKER FINDS SOMETHING TO ACT ON OR DECLINE, ITS STATUS IS
# STILL THIS LAUNCHER'S — lane-start missing changes what precedence 5 says,
# never whether precedence 4 governs first. Exit 8 (nothing to pick) leaves
# this launcher with NOTHING to start, not even the bare Claude lane-start's
# own absence would otherwise still have produced.
tty_launch "PATH=$NO_LANE_START_BIN:/usr/bin:/bin" "FAKE_TMUX_WINDOW=claude" \
    "FAKE_LANE_EXIT=8" -- run team002 --resume session-nolanestart-quit
[[ "$tty_launch_status" -eq 8 ]] \
    || fail "no lane-start, picker quit: the launcher exited $tty_launch_status instead of lane's own 8"; assertion
[[ -e "$LANE_PICKER_LOG" ]] \
    || fail "no lane-start, picker quit: the picker was skipped instead of tried"; assertion
[[ ! -e "$CLAUDE_LOG" ]] \
    || fail "no lane-start, picker quit: this launcher launched a Claude of its own after a quit"; assertion

# ---------------------------------------------------------------------------
# 3. NO TERMINAL ON STDIN: `lane` is on PATH (common_env's FAKE_BIN carries it)
# and would answer, but `launch`'s stdin is /dev/null, so step 3 answers
# nothing exactly as no `lane` on PATH does — today's behaviour, and one line.
launch \
    "FAKE_TMUX_WINDOW=claude" \
    "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    -- run team002 --resume session-n
[[ ! -e "$LANE_START_LOG" ]] || fail "no lane: lane-start was invoked ('$(lane_start_argv)')"; assertion
[[ ! -e "$LANE_PICKER_LOG" ]] \
    || fail "no lane: the picker ran with no terminal on stdin ('$(lane_picker_argv)')"; assertion
grep -Fxq -- "$claude_args --resume session-n" "$CLAUDE_LOG" \
    || fail "no lane: Claude did not receive its arguments unchanged ($(cat "$CLAUDE_LOG" 2>/dev/null))"; assertion
grep -q "$note" "$ERR_LOG" || fail "no lane: the note was not printed ($(cat "$ERR_LOG"))"; assertion

# ---------------------------------------------------------------------------
# 5. A window name that is not even lane-shaped: register-row answers 2, not 8,
# and only 0 is a lane.
launch \
    "FAKE_TMUX_WINDOW=1:zsh*" \
    "FAKE_REGISTER_ROW_OTHER=2" \
    "FAKE_SWAPPED_STATUS=8" \
    -- run team002 --resume session-badname
[[ ! -e "$LANE_START_LOG" ]] || fail "unshaped window name: lane-start was invoked ('$(lane_start_argv)')"; assertion
grep -Fq 'argv=register-row 1:zsh*' "$LANES_EDIT_LOG" \
    || fail "unshaped window name: register-row was not asked ($(cat "$LANES_EDIT_LOG"))"; assertion
grep -q "$note" "$ERR_LOG" || fail "unshaped window name: the note was not printed"; assertion

# ---------------------------------------------------------------------------
# 6. An explicit --lane beats both, and is not confirmed: it is what the
# operator said. The register is not read to RESOLVE a lane — neither the
# window name nor the swap record is looked up, which is the whole of what
# "beats both" means. (Amendment 11(3) added ONE other reason to read it: where
# lane-start's own default directory does not exist, the launcher asks the
# lane's OWN swap record and its own log where the lane lives, so a checkout
# that is not `$PROJECTS_ROOT/<repo>` does not end the launch. That is a
# question about a directory, not about which lane this is, and it is asked
# about the lane the operator named and no other. What must never happen is a
# read that could RESOLVE a lane — no `register-row <window>`, no
# `window-lane` — and those are what the two assertions below pin.)
launch \
    "FAKE_TMUX_WINDOW=openRepoProject-1" \
    "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=someOtherLane-9\t2026-09-12T17:04Z\tclaude-x:0\n" \
    -- --lane spoken-3 run team002 --resume session-f
grep -Fxq -- "spoken-3 -- $claude_args --resume session-f" "$LANE_START_LOG" \
    || fail "--lane: lane-start argv was '$(lane_start_argv)'"; assertion
grep -Fq 'argv=register-row openRepoProject-1' "$LANES_EDIT_LOG" \
    && fail "--lane: the window name was looked up for a lane the operator named ($(cat "$LANES_EDIT_LOG"))"; assertion
grep -Fq 'argv=window-lane' "$LANES_EDIT_LOG" \
    && fail "--lane: precedence 3 was read for a lane the operator named ($(cat "$LANES_EDIT_LOG"))"; assertion

# CLAUDE_LANE is the same thing by another route.
launch \
    "FAKE_TMUX_WINDOW=openRepoProject-1" \
    "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    "CLAUDE_LANE=spoken-4" \
    -- run team002 --resume session-fe
grep -Fxq -- "spoken-4 -- $claude_args --resume session-fe" "$LANE_START_LOG" \
    || fail "CLAUDE_LANE: lane-start argv was '$(lane_start_argv)'"; assertion

# ---------------------------------------------------------------------------
# 7. --no-lane opts out entirely — over a window that IS a lane, over a record
# that has one, and over CLAUDE_LANE — and says nothing.
launch \
    "FAKE_TMUX_WINDOW=openRepoProject-1" \
    "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=openRepoProject-1\t2026-09-12T17:04Z\tclaude-a:0\n" \
    "CLAUDE_LANE=spoken-5" \
    -- --no-lane run team002 --resume session-none
[[ ! -e "$LANE_START_LOG" ]] || fail "--no-lane: lane-start was invoked ('$(lane_start_argv)')"; assertion
[[ ! -e "$LANES_EDIT_LOG" ]] || fail "--no-lane: the register was read anyway"; assertion
grep -Fxq -- "$claude_args --resume session-none" "$CLAUDE_LOG" \
    || fail "--no-lane: Claude did not receive its arguments unchanged"; assertion
grep -q "$note" "$ERR_LOG" && fail "--no-lane: printed the no-lane note at an operator who opted out"; assertion

# CLAUDE_NO_LANE=1 is the same thing by another route.
launch \
    "FAKE_TMUX_WINDOW=openRepoProject-1" \
    "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    "CLAUDE_NO_LANE=1" \
    -- run team002 --resume session-none-env
[[ ! -e "$LANE_START_LOG" ]] || fail "CLAUDE_NO_LANE: lane-start was invoked ('$(lane_start_argv)')"; assertion

# ---------------------------------------------------------------------------
# 8. A lane-start from before Amendment 8, which knows neither `--confirm` nor
# `--yes` (this launcher passes it neither any more either way). The window's
# lane still goes to it, bare — that is today's behaviour, unaffected by which
# flags a lane-start does or does not know.
launch \
    "FAKE_TMUX_WINDOW=openRepoProject-1" \
    "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    "FAKE_LANE_START_HELP=$OLD_HELP" \
    -- run team002 --resume session-oldls
grep -Fxq -- "openRepoProject-1 -- $claude_args --resume session-oldls" "$LANE_START_LOG" \
    || fail "old lane-start, window lane: lane-start argv was '$(lane_start_argv)'"; assertion

# ---------------------------------------------------------------------------
# 9. No lanes-edit.sh to read: nothing can be resolved, and the launcher says
# so once rather than refusing.
launch \
    "FAKE_TMUX_WINDOW=openRepoProject-1" \
    "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    "WORKBENCHES_LANES_EDIT_BIN=$TEST_ROOT/nowhere/lanes-edit.sh" \
    -- run team002 --resume session-nolanesedit
[[ ! -e "$LANE_START_LOG" ]] || fail "no lanes-edit.sh: lane-start was invoked ('$(lane_start_argv)')"; assertion
[[ ! -e "$LANES_EDIT_LOG" ]] || fail "no lanes-edit.sh: something answered for it"; assertion
grep -Fxq -- "$claude_args --resume session-nolanesedit" "$CLAUDE_LOG" \
    || fail "no lanes-edit.sh: Claude did not receive its arguments unchanged"; assertion
grep -q "$note" "$ERR_LOG" || fail "no lanes-edit.sh: the note was not printed"; assertion

# 9a. A machine with no lane estate at all — no lane-start on PATH. This was
# Amendment 8(c)'s one SILENT degrade-table row, on the reasoning that a machine
# without the feature should not hear about it on every launch. **Evidence 5
# (new-workstation#20, 2026-09-13T17:29:58Z) overturned it**, and this suite
# moves with the rule rather than pinning the version of it that was measured
# wrong: after this workstation was rebuilt the `~/.local/bin` links were gone
# while `/usr/local/bin/claude-profile` was still there, so three restarts took
# this row and came up with no register stamp, a record name the harness derived
# and a window left as `claude` — in silence, because `--resume <uuid>` went on
# continuing the right transcript. The launcher now states the fact on its first
# line and names the install act. What is UNCHANGED, and is what this scenario
# still holds, is everything else about the row: Claude starts, the launcher
# exits 0, lane-start is never invoked, and the register is never read — the
# resolution stops before it has anything to read it with.
#
# The A11 suite's 5h-i holds the wording of the notice itself; here it is the
# A8(c) degrade table that has to agree with it, because these two suites test
# one resolution from two amendments and must not drift into two pictures of
# the estate.
NO_ESTATE_BIN="$TEST_ROOT/bin-no-estate"
mkdir -p "$NO_ESTATE_BIN"
cp "$FAKE_CLAUDE" "$NO_ESTATE_BIN/claude"
cp "$FAKE_BIN/tmux" "$NO_ESTATE_BIN/tmux"
cp "$FAKE_BIN/lanes-edit.sh" "$NO_ESTATE_BIN/lanes-edit.sh"
reset_logs
scenario
env "${common_env[@]}" "PATH=$NO_ESTATE_BIN:/usr/bin:/bin" "FAKE_TMUX_WINDOW=openRepoProject-1" \
    "FAKE_LANE_WITH_ROW=openRepoProject-1" "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=openRepoProject-1\t2026-09-12T17:04Z\tclaude-a:0\n" \
    "$LAUNCHER" run team002 --resume session-noestate >/dev/null 2>"$ERR_LOG"
grep -Fxq -- "$claude_args --resume session-noestate" "$CLAUDE_LOG" \
    || fail "no lane estate: Claude did not receive its arguments unchanged"; assertion
grep -Fq 'lane-start is not on PATH' "$ERR_LOG" \
    || fail "no lane estate: the launcher degraded in silence, which Evidence 5 ruled out ($(cat "$ERR_LOG"))"; assertion
grep -Fq 'link-estates' "$ERR_LOG" \
    || fail "no lane estate: the notice does not name the install act ($(cat "$ERR_LOG"))"; assertion
grep -Fq "$note" "$ERR_LOG" \
    && fail "no lane estate: the standing note told the operator to run the tool that is missing ($(cat "$ERR_LOG"))"; assertion
[[ ! -e "$LANE_START_LOG" ]] || fail "no lane estate: lane-start was invoked ('$(lane_start_argv)')"; assertion
[[ ! -e "$LANES_EDIT_LOG" ]] \
    || fail "no lane estate: the register was read with no lane-start to hand a lane to ($(cat "$LANES_EDIT_LOG"))"; assertion

# ---------------------------------------------------------------------------
# 9b. A launch that is not a conversation — `mcp`, `doctor`, `--version` — is
# not a lane's session, so it is neither handed to lane-start nor lectured
# about lanes, even standing in a lane's own window.
launch \
    "FAKE_TMUX_WINDOW=openRepoProject-1" \
    "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=openRepoProject-1\t2026-09-12T17:04Z\tclaude-a:0\n" \
    -- run team002 --version
[[ ! -e "$LANE_START_LOG" ]] || fail "--version: it was handed to lane-start ('$(lane_start_argv)')"; assertion
[[ ! -e "$LANES_EDIT_LOG" ]] || fail "--version: the register was read for a launch that is no conversation"; assertion
grep -Fxq -- "$claude_args --version" "$CLAUDE_LOG" \
    || fail "--version: Claude did not receive its arguments unchanged ($(cat "$CLAUDE_LOG" 2>/dev/null))"; assertion
grep -q "$note" "$ERR_LOG" && fail "--version: the no-lane note was printed at a launch that wanted no lane"; assertion

# ---------------------------------------------------------------------------
# 10. The re-exec into a new tmux session. That session's window is named for
# the command that made it, never for a lane, so a child of the re-exec must
# read the window name the parent captured and must never ask tmux itself.
launch \
    "WORKBENCHES_CLAUDE_TMUX_CHILD=1" \
    "WORKBENCHES_CLAUDE_WINDOW=openRepoProject-1" \
    "FAKE_TMUX_WINDOW=claude-team-002-20260912170400-1234" \
    "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    "FAKE_SWAPPED_STATUS=8" \
    -- run team002 --resume session-child
grep -Fxq -- "openRepoProject-1 -- $claude_args --resume session-child" "$LANE_START_LOG" \
    || fail "tmux child: the carried window name was not the lane ('$(lane_start_argv)')"; assertion
grep -Fxq 'display-message -p #W' "$TMUX_LOG" \
    && fail "tmux child: the launcher asked tmux for the new session's window name"; assertion

# With nothing carried across, a child resolves no window lane at all — even
# when the new session's window happens to be named like one.
launch \
    "WORKBENCHES_CLAUDE_TMUX_CHILD=1" \
    "FAKE_TMUX_WINDOW=openRepoProject-1" \
    "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    "FAKE_SWAPPED_STATUS=8" \
    -- run team002 --resume session-child-bare
[[ ! -e "$LANE_START_LOG" ]] \
    || fail "tmux child: a lane was taken from the new session's own window ('$(lane_start_argv)')"; assertion
grep -Fq 'argv=register-row' "$LANES_EDIT_LOG" \
    && fail "tmux child: the new session's window name was looked up in the register"; assertion

# The parent side: a launch that re-execs into a new tmux session threads the
# lane and the opt-out to the child. It carries no window name, because the
# re-exec happens only when the launch did NOT come from a tmux window at all
# (claude_run_is_interactive requires an empty TMUX) — there is nothing to
# carry, and the child must not invent one.
tty_launch "TMUX=" "FAKE_TMUX_WINDOW=openRepoProject-1" "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    "CLAUDE_LANE=carried-1" -- run team002 --resume session-tty
grep -q 'new-session' "$TMUX_LOG" || fail "re-exec: no tmux session was created ($(cat "$TMUX_LOG" 2>/dev/null))"; assertion
grep -q 'CLAUDE_LANE=carried-1' "$TMUX_LOG" || fail "re-exec: the lane was not carried into the new session"; assertion
grep -q 'WORKBENCHES_CLAUDE_WINDOW=' "$TMUX_LOG" \
    && fail "re-exec: a window name was carried from a launch that came from no window"; assertion

tty_launch "TMUX=" "FAKE_TMUX_WINDOW=openRepoProject-1" "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    "CLAUDE_NO_LANE=1" -- run team002 --resume session-tty
grep -q 'CLAUDE_NO_LANE=1' "$TMUX_LOG" || fail "re-exec: --no-lane was not carried into the new session"; assertion

# ---------------------------------------------------------------------------
# 11. A lane-start that TAKES a certain lane (the window's own name, precedence
# 2) and whose Claude exits non-zero hands that status back unchanged: 1 and 2
# are lane-start's own two refusal codes elsewhere in this order, but this
# window is already the lane's, so a refusal here would leave tmux printing
# `[exited]` over a window with no Claude in it — the same fence that used to
# disambiguate a DECLINED `--confirm` from a taken lane whose own Claude
# happened to exit 2, before Amendment 18 Addendum 1 removed `--confirm` from
# this file entirely (that disambiguation is untouched — Amendment 11's own
# suite still exercises it — and does not depend on the picker in any way).
launch \
    "FAKE_TMUX_WINDOW=openRepoProject-1" \
    "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    -- run team002 --resume session-taken
grep -Fxq -- "openRepoProject-1 -- $claude_args --resume session-taken" "$LANE_START_LOG" \
    || fail "taken lane: lane-start argv was '$(lane_start_argv)'"; assertion
[[ ! -e "$CLAUDE_LOG" ]] \
    || fail "taken lane: the launcher launched a Claude of its own behind lane-start"; assertion

# 11d. A lane-start that TOOK the lane and whose Claude exited 2 by itself.
# Rebased onto precedence 1 (an explicit `--lane`, opensoft/workBenches#82):
# the workstation's-newest-swap-record guess this scenario used to reach
# through `lane-start --confirm` is GONE (lane-collision-protocol Amendment 18
# Addendum 1, clause (i-5) — see the picker note above act 1's own comment
# block), so the same defect-capture wrapping around lane-start is exercised
# here through the one remaining "certain, not-already-the-window" source
# instead: `--lane` never renames anything on its own, so the window starts
# unrenamed exactly as the retired guess left it. 2 is the decline's status,
# but this 2 came from a Claude that already ran, and a launcher that read it
# as a decline would start a SECOND Claude behind the first. The window is
# what tells them apart: taking a lane renames it, declining leaves it alone.
WINDOW_FILE="$TEST_ROOT/tmux-window.name"
printf 'claude\n' > "$WINDOW_FILE"
launch \
    "FAKE_TMUX_WINDOW_FILE=$WINDOW_FILE" \
    "FAKE_LANE_START_DECLINE=took2" \
    -- --lane openRepoProject-1 run team002 --resume session-took2
grep -Fxq -- "openRepoProject-1 -- $claude_args --resume session-took2" "$LANE_START_LOG" \
    || fail "took the lane, Claude exited 2: lane-start argv was '$(lane_start_argv)'"; assertion
[[ "$(wc -l < "$CLAUDE_LOG")" -eq 1 ]] \
    || fail "took the lane, Claude exited 2: Claude ran $(wc -l < "$CLAUDE_LOG") times ($(cat "$CLAUDE_LOG"))"; assertion
[[ "$launch_status" -eq 2 ]] \
    || fail "took the lane, Claude exited 2: the launcher exited $launch_status instead of handing back 2"; assertion
grep -q 'did not take' "$ERR_LOG" \
    && fail "took the lane, Claude exited 2: a taken lane was reported as a decline ($(cat "$ERR_LOG"))"; assertion

# 11e. THE LIVE-FORK DEFECT (opensoft/workBenches#77, Amendment 18 DRAFT
# clause (h), found 2026-09-14T12:07Z), rebased onto precedence 1 for the same
# reason 11d is (opensoft/workBenches#82 retires the guess this used to reach
# through; the defect-capture tee around lane-start's bare call is
# unconditional now — every lane source that is not already the window's own
# name shares it, `--lane` included). lane-start still asks even where
# lanes-edit.sh's live-holder has already named a live FORK of this lane's
# transcript as a DEFECT — a fork is never a holder (decision 8(e)) — and the
# operator answers `N` at 0, exactly as 11b. But a decline here must not risk
# a SECOND live process on that same forked transcript, so this launcher must
# not treat lane-start's own account of the confirm (0, "handled") as license
# to fall through: it starts NOTHING of its own in this window, names the
# retire act the DEFECT line itself named, and stops — never a bare Claude
# that resumes the transcript lane-start had just called a live fork.
launch \
    "FAKE_TMUX_WINDOW=claude" \
    "FAKE_LANE_START_DECLINE=defect" \
    -- --lane openRepoProject-1 run team002 --resume session-defect
grep -Fxq -- "openRepoProject-1 -- $claude_args --resume session-defect" "$LANE_START_LOG" \
    || fail "live-fork defect: lane-start argv was '$(lane_start_argv)'"; assertion
[[ ! -e "$CLAUDE_LOG" ]] \
    || fail "live-fork defect: the launcher started a Claude of its own in this window ($(cat "$CLAUDE_LOG" 2>/dev/null)), risking a second live process on the fork"; assertion
grep -Fq 'DEFECT' "$ERR_LOG" \
    || fail "live-fork defect: lane-start's own DEFECT line did not reach the operator ($(cat "$ERR_LOG"))"; assertion
grep -Fq 'Retire it: lane-end openRepoProject-1 --retire 1721264' "$ERR_LOG" \
    || fail "live-fork defect: the retire act lane-start named was not printed back ($(cat "$ERR_LOG"))"; assertion
grep -q -- '--resume' "$ERR_LOG" \
    && fail "live-fork defect: the launcher's own argv or notice named a --resume ($(cat "$ERR_LOG"))"; assertion
[[ "$launch_status" -ne 0 ]] \
    || fail "live-fork defect: the launcher exited 0, as if a Claude had safely started here"; assertion

# 11f. THE SAME DEFECT, ANSWERED Y (opensoft/workBenches#77), rebased onto
# precedence 1 for the same reason 11d and 11e are. lane-start still asks
# after naming a live-fork DEFECT (decision 8(e): a fork is not a holder, so
# it never stands in front of the question) — and the operator can still take
# the lane in this window, retiring the fork as a separate act. The window IS
# renamed here, unlike 11e, so the new defect-stop must NOT fire: it is the
# window staying UNRENAMED that says the confirm was declined, never the
# DEFECT line by itself — a lane that WAS taken launches exactly as an
# ordinary take does.
WINDOW_FILE="$TEST_ROOT/tmux-window-defect-taken.name"
printf 'claude\n' > "$WINDOW_FILE"
launch \
    "FAKE_TMUX_WINDOW_FILE=$WINDOW_FILE" \
    "FAKE_LANE_START_DECLINE=defect_taken" \
    -- --lane openRepoProject-1 run team002 --resume session-defect-taken
grep -Fxq -- "openRepoProject-1 -- $claude_args --resume session-defect-taken" "$LANE_START_LOG" \
    || fail "live-fork defect, taken: lane-start argv was '$(lane_start_argv)'"; assertion
[[ "$(wc -l < "$CLAUDE_LOG")" -eq 1 ]] \
    || fail "live-fork defect, taken: Claude ran $(wc -l < "$CLAUDE_LOG") times ($(cat "$CLAUDE_LOG"))"; assertion
[[ "$launch_status" -eq 0 ]] \
    || fail "live-fork defect, taken: the launcher exited $launch_status instead of relaying lane-start's 0"; assertion
# lane-start's own DEFECT line (tee'd straight through) names "Retire it:"
# once on its own account; the launcher's stop wording ("is not taken in
# this window") is the tell of a SECOND, unwanted verdict layered on a lane
# that was, in fact, taken.
grep -q 'is not taken in this window' "$ERR_LOG" \
    && fail "live-fork defect, taken: a taken lane was stopped for a defect it took anyway ($(cat "$ERR_LOG"))"; assertion
[[ "$(grep -c 'Retire it' "$ERR_LOG")" -eq 1 ]] \
    || fail "live-fork defect, taken: 'Retire it' appeared $(grep -c 'Retire it' "$ERR_LOG") times, not lane-start's one ($(cat "$ERR_LOG"))"; assertion

# ---------------------------------------------------------------------------
# 12. OUTSIDE TMUX there is no window to take, so the record is not even read.
# `lane-start` takes a lane by renaming the current tmux window; handing it a
# guess it cannot act on is how a resolution that "never refuses a launch"
# refuses one (the documented direct launch: WORKBENCHES_CLAUDE_TMUX=off, or a
# launch that is not on a tty). The window rule needs no such guard — without
# tmux it has no name to offer.
launch \
    "TMUX=" \
    "FAKE_TMUX_WINDOW=openRepoProject-1" \
    "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=openRepoProject-1\t2026-09-12T17:04Z\tclaude-a:0\n" \
    -- run team002 --resume session-notmux
[[ ! -e "$LANE_START_LOG" ]] || fail "outside tmux: lane-start was invoked ('$(lane_start_argv)')"; assertion
grep -Fxq -- "$claude_args --resume session-notmux" "$CLAUDE_LOG" \
    || fail "outside tmux: Claude did not receive its arguments unchanged"; assertion
[[ ! -e "$LANES_EDIT_LOG" ]] \
    || fail "outside tmux: the register was read for a window that does not exist ($(cat "$LANES_EDIT_LOG"))"; assertion
grep -q "$note" "$ERR_LOG" || fail "outside tmux: the note was not printed ($(cat "$ERR_LOG"))"; assertion

# ---------------------------------------------------------------------------
# 13. ONE no-lane notice, not two (A8 Addendum 2 R-A8-7; Amendment 8(e): the
# hook's block is "the ONLY no-lane notice in the estate" and "clause (c) step
# 4 stands down wherever this hook can speak"). The launcher knows whether the
# hook will speak, because it is the launcher that ensures it: the entry goes
# into the profile's settings only when ~/projects/xFactory/lanes-edit.sh
# exists AND has the `session-start` subcommand.
XFACTORY_DIR="$FAKE_HOME/projects/xFactory"
mkdir -p "$XFACTORY_DIR"

# 13a. The estate is installed but predates Amendment 8 — no `session-start`.
# Nothing else will say it, so the launcher still does, and no entry is written
# against a subcommand that would answer it with a usage block.
printf '#!/usr/bin/env bash\ncase "$1" in who) : ;; esac\n' > "$XFACTORY_DIR/lanes-edit.sh"
launch \
    "FAKE_TMUX_WINDOW=claude" \
    "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    "FAKE_SWAPPED_STATUS=8" \
    -- run team002 --resume session-hookless
grep -q "$note" "$ERR_LOG" \
    || fail "no session-start subcommand: the note stood down with nothing to say it ($(cat "$ERR_LOG"))"; assertion
jq -e '.hooks.SessionStart // empty' "$PROFILE_DIR/settings.json" >/dev/null 2>&1 \
    && fail "no session-start subcommand: an entry was written against a lanes-edit.sh that has none"; assertion

# 13b. The estate HAS `session-start`, so the hook is ensured and will print
# the same instruction with the repo and the number filled in. The launcher
# says nothing at all.
printf '#!/usr/bin/env bash\ncase "$1" in session-start) : ;; esac\n' > "$XFACTORY_DIR/lanes-edit.sh"
launch \
    "FAKE_TMUX_WINDOW=claude" \
    "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    "FAKE_SWAPPED_STATUS=8" \
    -- run team002 --resume session-hooked
grep -Fxq -- "$claude_args --resume session-hooked" "$CLAUDE_LOG" \
    || fail "hook ensured: Claude did not receive its arguments unchanged"; assertion
[[ ! -s "$ERR_LOG" ]] \
    || fail "hook ensured: the launcher said it too ($(cat "$ERR_LOG"))"; assertion
jq -e '.hooks.SessionStart' "$PROFILE_DIR/settings.json" >/dev/null 2>&1 \
    || fail "hook ensured: no SessionStart entry in the profile's settings"; assertion
rm -rf "$FAKE_HOME/projects"

[[ "$scenarios" -eq "$EXPECTED_SCENARIOS" ]] \
    || fail "$scenarios scenarios ran, $EXPECTED_SCENARIOS expected — one was added or lost without saying so"
echo "claude-profile lane default: $scenarios scenarios, $assertions assertions passed"
