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
    CLAUDE_LANE CLAUDE_NO_LANE LANES_WORKSTATION LANES_HOST LANES_OS \
    LANES_CONTAINER 2>/dev/null || true

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
EXPECTED_SCENARIOS=49
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
# THE ENVIRONMENT THE STARTED SESSION COMES UP WITH — the only place the
# launcher's exports can be observed, since they are read by everything
# downstream and printed by nothing (lane-collision-protocol Amendment 18
# clause (a), opensoft/workBenches#98; `R-A11-14` for the workstation beside
# them).
LANE_START_ENV_LOG="$TEST_ROOT/lane-start-env.log"
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
        # FAKE_TMUX_DISPLAY_FAIL simulates tmux being unable to answer at
        # all — "no such session"/"no such pane" is exactly what asking
        # about a window whose pane has ALREADY closed looks like
        # (opensoft/workBenches#95/#96's lane_window_confirmed_elsewhere).
        [[ -z "${FAKE_TMUX_DISPLAY_FAIL:-}" ]] || exit 1
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
# ...and the four values that say WHERE the session it is about to start is
# running (Amendment 18 clause (a), beside `R-A11-14`'s workstation). Logged
# with `${X-<unset>}` rather than `${X:-}`: "exported as nothing at all" and
# "exported as an empty string" are different answers here — the first is what
# makes the lane tooling fall back to its own probe — and a reader of this log
# has to be able to tell them apart.
{
    printf 'LANES_WORKSTATION=%s\n' "${LANES_WORKSTATION-<unset>}"
    printf 'LANES_HOST=%s\n' "${LANES_HOST-<unset>}"
    printf 'LANES_OS=%s\n' "${LANES_OS-<unset>}"
    printf 'LANES_CONTAINER=%s\n' "${LANES_CONTAINER-<unset>}"
} >> "${FAKE_LANE_START_ENV_LOG:-/dev/null}"
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
    took_sigint)
        # A Claude lane-start took the lane for (the window IS renamed) and
        # that then died to a signal — 130, neither of lane-start's own two
        # documented codes nor the clean 0 a long-lived run ends in
        # (opensoft/workBenches#96, Copilot round 1: coverage for a status
        # this launcher's rule keeps regardless of the window).
        tmux rename-window "$lane_argument" >/dev/null 2>&1 || true
        "${CLAUDE_BIN:?}" ${rest[@]+"${rest[@]}"}
        exit 130
        ;;
    hugestderr)
        # Enough bytes to prove the retained file is bounded regardless of
        # how much the exec'd chain wrote before dying fast (Copilot round 2
        # on opensoft/workBenches#96, claude-profile:2813). `|| true`: `yes`
        # exits on SIGPIPE once `head` stops reading, which is itself a
        # nonzero status `pipefail` would otherwise hand to this `set -e`
        # script.
        yes 'x' | head -c 300000 >&2 || true
        exit 0
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
    fastexit)
        # opensoft/workBenches#95: the exec'd Claude exits AT ONCE, status 0 —
        # today's two measured causes are a title `--resume` opening the
        # interactive picker in a pane whose only command then ends, and (what
        # this fake's own text stands for) the harness refusing `--resume
        # <uuid>` because a bg/fork record already holds that id. Nothing is
        # renamed and nothing reaches $CLAUDE_BIN, because the process that
        # would have done either never got that far.
        echo "Session 4a91f1dc is running as a background session (pid 4242). Add --fork-session to start a new one." >&2
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
    "FAKE_LANE_START_ENV_LOG=$LANE_START_ENV_LOG"
    "FAKE_LANES_EDIT_LOG=$LANES_EDIT_LOG"
    "FAKE_LANE_LOG=$LANE_PICKER_LOG"
    "FAKE_LANE_START_HELP=$AMENDMENT_8_HELP"
    "WORKBENCHES_SHARED_MCP_FAMILIES=disabled"
    "LANES_WORKSTATION=Eagle"
    "TMUX=fake-session"
    # opensoft/workBenches#95: the lane defect capture is kept, and its tail
    # printed, on a run that exits FAST — every fake here always does, having
    # no interactive session to hold open — so 0 tells the launcher that
    # merely being instant is not "fast" for this suite's purposes. A
    # scenario that means to test the keep-and-print behaviour overrides this
    # back up per-launch instead of relying on real elapsed time.
    "WORKBENCHES_CLAUDE_LANE_DEFECT_SECONDS=0"
    # Copilot round 1 on opensoft/workBenches#96: a KEPT capture is deliberate
    # (11g), but its file still lands wherever the launcher's own
    # `${TMPDIR:-/tmp}` points — the real host /tmp unless this suite says
    # otherwise — and this trap only removes $TEST_ROOT. A test-local TMPDIR
    # means every capture this suite's scenarios keep OR delete is cleaned
    # with the sandbox regardless.
    "TMPDIR=$TEST_ROOT"
)

claude_args='--allow-dangerously-skip-permissions --dangerously-skip-permissions --permission-mode bypassPermissions'
note='no lane for this window; run lane-start <repo> <n> inside it'

reset_logs() {
    rm -f "$CLAUDE_LOG" "$TMUX_LOG" "$LANE_START_LOG" "$LANE_START_ENV_LOG" "$LANES_EDIT_LOG" \
        "$LANE_PICKER_LOG" "$ERR_LOG"
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
# ...AND THE CAPTURE IS KEPT, WITH ITS TAIL PRINTED (Copilot round 1 on
# opensoft/workBenches#96, extending this scenario per that round's own
# request): status 2 in a window ALREADY the lane's is exactly the ambiguous
# case `lane_window_confirmed_elsewhere` cannot clear — this ex-Claude status
# could just as easily be lane-start's own environment refusal as Claude's
# own exit code — so the launcher keeps rather than guesses, here as much as
# on the genuinely fast paths 11g covers.
capture_path="$(grep -m1 -F 'lane defect capture:' "$ERR_LOG" | sed -n 's/.*lane defect capture: //p')"
[[ -n "$capture_path" ]] \
    || fail "took the lane, Claude exited 2: the capture path was never printed ('$(cat "$ERR_LOG")')"; assertion
[[ -e "$capture_path" ]] \
    || fail "took the lane, Claude exited 2: the capture was deleted although the window is already the lane's own, an ambiguous status ($capture_path)"; assertion
grep -Fq 'lane defect capture kept' "$ERR_LOG" \
    || fail "took the lane, Claude exited 2: no kept-capture notice was printed ('$(cat "$ERR_LOG")')"; assertion
rm -f "$capture_path"

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

# 11g. THE LANE DEFECT CAPTURE ITSELF (opensoft/workBenches#95,
# `claude-profile` around the mktemp/tee that wraps every lane-start
# invocation): three properties, one scenario, because the scenario that
# proves the third also has both pieces of content the first two need.
#
#   1. THE PATH IS PRINTED BEFORE THE EXEC — the one line an operator
#      glancing at a pane already on its way out, or a scrollback that
#      outlives the pane by a moment, might still catch. Checked here by
#      LINE NUMBER against lane-start's own teed-through text, not merely by
#      presence: "before" means before, not "also present somewhere".
#   2. A FAST EXIT — status 0 that did NOT hold the pane open for
#      $WORKBENCHES_CLAUDE_LANE_DEFECT_SECONDS — KEEPS the capture file
#      rather than deleting it, because the window this launcher may have
#      just made can close in the same breath lane-start returns.
#   3. AND ITS TAIL, PLUS THE TWO KNOWN CAUSES WITH THEIR CURES, ARE PRINTED
#      to this launcher's OWN stderr (the parent shell outlives the tmux
#      window): a title resume's picker with its cure (resume by the exact
#      uuid), and a background/fork holder's with its three (`claude
#      agents`, `claude attach <id>`, `lane-end <lane> --retire <pid>`).
#
# `WORKBENCHES_CLAUDE_LANE_DEFECT_SECONDS` is overridden UP, per-launch, so
# this fake's near-instant return still counts as "fast" against a real
# threshold — exactly as a real Claude that exited in under 20s would,
# without this suite waiting out a real 20s per scenario. common_env's own
# override to 0 is what a CLEAN run relies on instead (11h, next).
launch \
    "FAKE_TMUX_WINDOW=claude" \
    "FAKE_LANE_START_DECLINE=fastexit" \
    "WORKBENCHES_CLAUDE_LANE_DEFECT_SECONDS=9999" \
    -- --lane openRepoProject-1 run team002 --resume session-fastexit
[[ "$launch_status" -eq 0 ]] \
    || fail "fast exit: the launcher exited $launch_status instead of relaying lane-start's 0"; assertion
[[ ! -e "$CLAUDE_LOG" ]] \
    || fail "fast exit: a Claude ran although the exec'd chain never reached one ($(cat "$CLAUDE_LOG" 2>/dev/null))"; assertion
capture_path="$(grep -m1 -F 'lane defect capture:' "$ERR_LOG" | sed -n 's/.*lane defect capture: //p')"
[[ -n "$capture_path" ]] \
    || fail "fast exit: the capture path was never printed ('$(cat "$ERR_LOG")')"; assertion
capture_line="$(grep -n -F 'lane defect capture:' "$ERR_LOG" | head -n 1 | cut -d : -f 1)"
lanestart_line="$(grep -n -F 'background session' "$ERR_LOG" | head -n 1 | cut -d : -f 1)"
[[ -n "$capture_line" && -n "$lanestart_line" && "$capture_line" -lt "$lanestart_line" ]] \
    || fail "fast exit: the capture path did not print before the exec (breadcrumb line ${capture_line:-?}, lane-start's own output line ${lanestart_line:-?}: '$(cat "$ERR_LOG")')"; assertion
[[ -e "$capture_path" ]] \
    || fail "fast exit: the capture file was deleted although the run exited fast ($capture_path)"; assertion
grep -Fq 'lane defect capture kept' "$ERR_LOG" \
    || fail "fast exit: no kept-capture notice was printed ('$(cat "$ERR_LOG")')"; assertion
grep -Fq 'background session' "$ERR_LOG" \
    || fail "fast exit: the capture's own tail was not printed to this launcher's stderr ('$(cat "$ERR_LOG")')"; assertion
grep -Fq 'title resume' "$ERR_LOG" \
    || fail "fast exit: the title-resume cause was not named ('$(cat "$ERR_LOG")')"; assertion
grep -Fq 'claude agents' "$ERR_LOG" \
    || fail "fast exit: the background/fork holder's claude-agents cure was not named ('$(cat "$ERR_LOG")')"; assertion
grep -Fq 'lane-end openRepoProject-1 --retire' "$ERR_LOG" \
    || fail "fast exit: the background/fork holder's lane-end cure was not named with THIS lane ('$(cat "$ERR_LOG")')"; assertion
rm -f "$capture_path"

# 11h. ...AND THE ORDINARY, LONG-HELD RUN DELETES IT AND SAYS NOTHING BEYOND
# THE BREADCRUMB. A status 0 that held the pane at least
# $WORKBENCHES_CLAUDE_LANE_DEFECT_SECONDS is what common_env's 0 override
# makes even this instant fake count as, so no per-launch override is needed
# here — this IS the default this suite otherwise runs under throughout.
launch \
    "FAKE_TMUX_WINDOW=claude" \
    "FAKE_LANE_START_DECLINE=bare" \
    -- --lane openRepoProject-1 run team002 --resume session-cleanrun
[[ "$launch_status" -eq 0 ]] \
    || fail "clean run: the launcher exited $launch_status"; assertion
capture_path="$(grep -m1 -F 'lane defect capture:' "$ERR_LOG" | sed -n 's/.*lane defect capture: //p')"
[[ -n "$capture_path" ]] \
    || fail "clean run: the capture path was never printed ('$(cat "$ERR_LOG")')"; assertion
if [[ -e "$capture_path" ]]; then
    rm -f "$capture_path"
    fail "clean run: the capture file survived a clean, long-held run ($capture_path)"
fi
assertion
[[ "$(wc -l < "$ERR_LOG")" -eq 1 ]] \
    || fail "clean run: printed $(wc -l < "$ERR_LOG") lines, not just the capture breadcrumb ('$(cat "$ERR_LOG")')"; assertion

# 11i. STATUS 2, WINDOW CONFIRMED ELSEWHERE (Copilot round 1 on
# opensoft/workBenches#96): lane-start's own documented refusal — nothing
# renamed, nothing written, Claude never started — in a window a tmux read
# actually SUCCEEDED at naming something other than the lane. This is the one
# half of the 1/2 disjunct that DOES delete; 11j (next) and the extension on
# 11d above are its other two.
launch \
    "FAKE_TMUX_WINDOW=claude" \
    "FAKE_LANE_START_DECLINE=exit2" \
    -- --lane openRepoProject-1 run team002 --resume session-status2-elsewhere
[[ "$launch_status" -eq 0 ]] \
    || fail "status 2, window elsewhere: the launcher exited $launch_status instead of dropping to a bare Claude"; assertion
capture_path="$(grep -m1 -F 'lane defect capture:' "$ERR_LOG" | sed -n 's/.*lane defect capture: //p')"
[[ -n "$capture_path" ]] \
    || fail "status 2, window elsewhere: the capture path was never printed ('$(cat "$ERR_LOG")')"; assertion
if [[ -e "$capture_path" ]]; then
    rm -f "$capture_path"
    fail "status 2, window elsewhere: the capture survived lane-start's own documented refusal in a confirmed-different window ($capture_path)"
fi
assertion

# 11j. STATUS 2, TMUX UNREADABLE (Copilot round 1 on opensoft/workBenches#96,
# claude-profile:2742): the window read that would settle whether this status
# is lane-start's own refusal or a taken lane's own Claude FAILS OUTRIGHT —
# `FAKE_TMUX_DISPLAY_FAIL` stands for a session or pane that has already
# closed, which is indistinguishable from "not yet asked" and is exactly the
# case `lane_window_confirmed_elsewhere` exists to keep for rather than
# mis-delete via a bare `! lane_window_is` (this scenario is the regression
# that fix closes: it fails against the launcher this PR opened with).
launch \
    "FAKE_TMUX_DISPLAY_FAIL=1" \
    "FAKE_LANE_START_DECLINE=exit2" \
    -- --lane openRepoProject-1 run team002 --resume session-status2-unreadable
capture_path="$(grep -m1 -F 'lane defect capture:' "$ERR_LOG" | sed -n 's/.*lane defect capture: //p')"
[[ -n "$capture_path" ]] \
    || fail "status 2, tmux unreadable: the capture path was never printed ('$(cat "$ERR_LOG")')"; assertion
[[ -e "$capture_path" ]] \
    || fail "status 2, tmux unreadable: the capture was deleted although this launcher could not confirm the window was NOT the lane's own ($capture_path)"; assertion
grep -Fq 'lane defect capture kept' "$ERR_LOG" \
    || fail "status 2, tmux unreadable: no kept-capture notice was printed ('$(cat "$ERR_LOG")')"; assertion
rm -f "$capture_path"

# 11k. A STATUS THAT IS NEITHER 1, 2 NOR 0 — a signal, here 130 — from a
# Claude lane-start DID take the lane for (Copilot round 1 on
# opensoft/workBenches#96): the rule keeps on this status regardless of the
# window, because only status 0 is ever eligible for the elapsed-time
# "ordinary long-lived run" branch at all.
WINDOW_FILE="$TEST_ROOT/tmux-window-sigint.name"
printf 'claude\n' > "$WINDOW_FILE"
launch \
    "FAKE_TMUX_WINDOW_FILE=$WINDOW_FILE" \
    "FAKE_LANE_START_DECLINE=took_sigint" \
    -- --lane openRepoProject-1 run team002 --resume session-sigint
[[ "$launch_status" -eq 130 ]] \
    || fail "status 130: the launcher exited $launch_status instead of handing back 130"; assertion
capture_path="$(grep -m1 -F 'lane defect capture:' "$ERR_LOG" | sed -n 's/.*lane defect capture: //p')"
[[ -n "$capture_path" ]] \
    || fail "status 130: the capture path was never printed ('$(cat "$ERR_LOG")')"; assertion
[[ -e "$capture_path" ]] \
    || fail "status 130: the capture was deleted although the run's status was neither 1, 2 nor a long-held 0 ($capture_path)"; assertion
grep -Fq 'lane defect capture kept' "$ERR_LOG" \
    || fail "status 130: no kept-capture notice was printed ('$(cat "$ERR_LOG")')"; assertion
rm -f "$capture_path"

# 11m. A MALFORMED WORKBENCHES_CLAUDE_LANE_DEFECT_SECONDS FALLS BACK TO THE
# DOCUMENTED DEFAULT (Copilot round 2 on opensoft/workBenches#96,
# claude-profile:2756): a non-numeric override must not reach the `-ge`
# comparison at all, and must not silently defeat the retention rule either
# — a well-under-20s run still keeps.
launch \
    "FAKE_TMUX_WINDOW=claude" \
    "FAKE_LANE_START_DECLINE=fastexit" \
    "WORKBENCHES_CLAUDE_LANE_DEFECT_SECONDS=not-a-number" \
    -- --lane openRepoProject-1 run team002 --resume session-malformed-threshold
[[ "$launch_status" -eq 0 ]] \
    || fail "malformed threshold: the launcher exited $launch_status instead of relaying lane-start's 0"; assertion
capture_path="$(grep -m1 -F 'lane defect capture:' "$ERR_LOG" | sed -n 's/.*lane defect capture: //p')"
[[ -n "$capture_path" ]] \
    || fail "malformed threshold: the capture path was never printed ('$(cat "$ERR_LOG")')"; assertion
[[ -e "$capture_path" ]] \
    || fail "malformed threshold: the capture was deleted — a malformed override must fall back to the real default, and this run is well under 20s ($capture_path)"; assertion
grep -q 'integer expression expected' "$ERR_LOG" \
    && fail "malformed threshold: the malformed value reached the comparison unvalidated ('$(cat "$ERR_LOG")')"; assertion
rm -f "$capture_path"

# 11n. ...AND SO DOES A NEGATIVE ONE — Copilot round 2's own sharper case: a
# negative override would otherwise make "elapsed >= threshold" true for
# EVERY status-0 run, no matter how fast it exited, defeating the rule
# entirely rather than merely erroring.
launch \
    "FAKE_TMUX_WINDOW=claude" \
    "FAKE_LANE_START_DECLINE=fastexit" \
    "WORKBENCHES_CLAUDE_LANE_DEFECT_SECONDS=-5" \
    -- --lane openRepoProject-1 run team002 --resume session-negative-threshold
capture_path="$(grep -m1 -F 'lane defect capture:' "$ERR_LOG" | sed -n 's/.*lane defect capture: //p')"
[[ -n "$capture_path" ]] \
    || fail "negative threshold: the capture path was never printed ('$(cat "$ERR_LOG")')"; assertion
[[ -e "$capture_path" ]] \
    || fail "negative threshold: the capture was deleted — a negative override defeated the retention rule instead of falling back to the default ($capture_path)"; assertion
rm -f "$capture_path"

# 11o. A CAPTURE LARGER THAN THE BYTE CAP IS TRUNCATED TO ITS OWN TAIL, AND
# KEEPS THE ORIGINAL'S 0600 PERMISSIONS (Copilot round 2 on
# opensoft/workBenches#96, claude-profile:2813): bounded by BYTES so one very
# long stream cannot escape the cap the way a line count could, and written
# via `mktemp` rather than a plain `>` so the replacement is not created
# world-readable under the shell's umask.
launch \
    "FAKE_TMUX_WINDOW=claude" \
    "FAKE_LANE_START_DECLINE=hugestderr" \
    "WORKBENCHES_CLAUDE_LANE_DEFECT_SECONDS=9999" \
    -- --lane openRepoProject-1 run team002 --resume session-huge
capture_path="$(grep -m1 -F 'lane defect capture:' "$ERR_LOG" | sed -n 's/.*lane defect capture: //p')"
[[ -n "$capture_path" ]] \
    || fail "huge capture: the capture path was never printed ('$(cat "$ERR_LOG")')"; assertion
[[ -e "$capture_path" ]] \
    || fail "huge capture: the capture was deleted although this is a fast exit ($capture_path)"; assertion
capture_size="$(wc -c < "$capture_path")"
[[ "$capture_size" -le 200000 ]] \
    || fail "huge capture: the retained file was $capture_size bytes, not bounded to the 200000-byte cap ($capture_path)"; assertion
if command -v stat >/dev/null 2>&1; then
    capture_mode="$(stat -c '%a' "$capture_path" 2>/dev/null || stat -f '%Lp' "$capture_path" 2>/dev/null || true)"
    [[ -z "$capture_mode" || "$capture_mode" == "600" ]] \
        || fail "huge capture: the truncated file's mode was $capture_mode, not the 600 mktemp gives the original ($capture_path)"; assertion
fi
rm -f "$capture_path"

# 11p. lane_window_confirmed_elsewhere REQUIRES $TMUX, LIKE ITS SIBLINGS
# lane_window_is AND export_tmux_identity DO (Copilot round 3 on
# opensoft/workBenches#96, claude-profile:1457): a --lane launch genuinely
# outside tmux (lane-start's own status-1 environment refusal, "not inside
# tmux") must not have its capture deleted because some UNRELATED tmux
# server happens to be reachable and answers with a window name that is not
# the lane's — that answer is not about THIS launch at all.
launch \
    "TMUX=" \
    "FAKE_TMUX_WINDOW=some-other-sessions-window" \
    "FAKE_LANE_START_DECLINE=exit2" \
    -- --lane openRepoProject-1 run team002 --resume session-outside-tmux
capture_path="$(grep -m1 -F 'lane defect capture:' "$ERR_LOG" | sed -n 's/.*lane defect capture: //p')"
[[ -n "$capture_path" ]] \
    || fail "outside tmux: the capture path was never printed ('$(cat "$ERR_LOG")')"; assertion
[[ -e "$capture_path" ]] \
    || fail "outside tmux: the capture was deleted based on an unrelated tmux server's window name, although this launch has no \$TMUX of its own ($capture_path)"; assertion
rm -f "$capture_path"

# 11q. A LEADING-ZERO WORKBENCHES_CLAUDE_LANE_DEFECT_SECONDS COMPARES AS
# DECIMAL, NOT OCTAL (Copilot round 3 on opensoft/workBenches#96,
# claude-profile:2776): bash's `[[ -ge ]]` reads a leading-zero operand as
# octal, where "08"/"09" are not even valid octal digits and error outright
# rather than merely misreading.
launch \
    "FAKE_TMUX_WINDOW=claude" \
    "FAKE_LANE_START_DECLINE=fastexit" \
    "WORKBENCHES_CLAUDE_LANE_DEFECT_SECONDS=08" \
    -- --lane openRepoProject-1 run team002 --resume session-octal-threshold
capture_path="$(grep -m1 -F 'lane defect capture:' "$ERR_LOG" | sed -n 's/.*lane defect capture: //p')"
[[ -n "$capture_path" ]] \
    || fail "octal threshold: the capture path was never printed ('$(cat "$ERR_LOG")')"; assertion
grep -qi 'value too great for base\|syntax error in expression' "$ERR_LOG" \
    && fail "octal threshold: the leading-zero override reached the comparison unnormalized ('$(cat "$ERR_LOG")')"; assertion
[[ -e "$capture_path" ]] \
    || fail "octal threshold: the capture was deleted although 0s is well under a threshold of 8 ($capture_path)"; assertion
rm -f "$capture_path"

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

# ---------------------------------------------------------------------------
# 14. WHERE THE LANE IS RUNNING — lane-collision-protocol Amendment 18 clause
# (a) (in force 2026-09-14T13:15Z), the launcher half, opensoft/workBenches#98.
#
# `LANES_WORKSTATION` says whose register a lane's rows belong to. It cannot say
# which CONTAINER on that machine the lane is live in, and a pid does not cross
# a pid namespace: two bench containers on one host share the profile directory,
# so a lane live and writing in cloudBench read NOT LIVE from pyBench and
# `lane-start` there took the name — two bindings, one lane, one append-only
# log. The amendment puts `host <name>; os <linux|macos|wsl|windows>; container
# <name|none>` on every STARTED, RESUMED and PAUSED and has this launcher export
# the three beside the workstation it already exports; opensoft/openRepoTools#83
# is the half that READS them, falls back to its own probes where they are
# unset, and DROPS an `os` that is none of the four words.
#
# Every scenario below is deterministic on both kinds of machine this suite runs
# on. The container branch is FORCED with the `container=` environment marker,
# which is a container everywhere. The one branch that needs the machine's real
# answer reads whether the SUITE itself is in a container — the same three
# markers the launcher's own fence reads — and asserts against that rather than
# skipping, because a scenario that does not run is one the pinned count above
# cannot see.
suite_in_container=false
[[ ! -e /.dockerenv && ! -e /run/.containerenv && -z "${container:-}" ]] || suite_in_container=true

# 14a. DERIVED AND EXPORTED WITH NOTHING SET FOR THEM ANYWHERE. The OS is
# knowable on any machine this can run on, so it is always one of the four
# words; the other two are the host's own answers where this is a host, and
# NOTHING AT ALL where it is a container nobody named — never a container id
# offered as a machine's name, never `none` offered by a launcher standing
# inside a container. `<unset>` in this log is the fake lane-start's way of
# saying the variable does not exist in the started session's environment, which
# is exactly what makes openRepoTools#83 fall back to its own probe.
launch "FAKE_TMUX_WINDOW=mine-5" "FAKE_LANE_WITH_ROW=mine-5" \
    -- run team002 --resume session-a18-derived
grep -Eq '^LANES_OS=(linux|macos|wsl|windows)$' "$LANE_START_ENV_LOG" \
    || fail "Amendment 18(a): the session was started with an OS that is none of the four words ('$(grep '^LANES_OS=' "$LANE_START_ENV_LOG" 2>/dev/null)')"; assertion
if [[ "$suite_in_container" == true ]]; then
    grep -Fxq 'LANES_HOST=<unset>' "$LANE_START_ENV_LOG" \
        || fail "Amendment 18(a): a container that was told no host handed the session one anyway ('$(grep '^LANES_HOST=' "$LANE_START_ENV_LOG" 2>/dev/null)')"; assertion
    grep -Fxq 'LANES_CONTAINER=<unset>' "$LANE_START_ENV_LOG" \
        || fail "Amendment 18(a): a container nobody named was named by the launcher standing in it ('$(grep '^LANES_CONTAINER=' "$LANE_START_ENV_LOG" 2>/dev/null)')"; assertion
else
    grep -Fxq "LANES_HOST=$(hostname -s 2>/dev/null || hostname 2>/dev/null || true)" "$LANE_START_ENV_LOG" \
        || fail "Amendment 18(a): the host's own short name did not reach the session ('$(grep '^LANES_HOST=' "$LANE_START_ENV_LOG" 2>/dev/null)')"; assertion
    grep -Fxq 'LANES_CONTAINER=none' "$LANE_START_ENV_LOG" \
        || fail "Amendment 18(a): a session started on the host itself did not say so with the amendment's own word ('$(grep '^LANES_CONTAINER=' "$LANE_START_ENV_LOG" 2>/dev/null)')"; assertion
fi

# 14b. AN ALREADY-SET VALUE WINS, AND IT WINS INSIDE A CONTAINER — the rule the
# workstation is resolved by, one variable along and three times, and the only
# way a container's own name ever gets in at all: a container cannot name
# itself, so `LANES_CONTAINER` is written in from outside by whoever opened it.
# `windows` is here on purpose: it is the one word of the four this launcher
# never derives — its bash is WSL2 on a Windows machine, which reads `wsl` — so
# passing it through unchanged is the whole of how it can ever appear on a lane
# line.
launch "FAKE_TMUX_WINDOW=mine-5" "FAKE_LANE_WITH_ROW=mine-5" "container=docker" \
    "LANES_HOST=eagle" "LANES_OS=windows" "LANES_CONTAINER=py-bench" \
    -- run team002 --resume session-a18-configured
grep -Fxq 'LANES_HOST=eagle' "$LANE_START_ENV_LOG" \
    || fail "Amendment 18(a): a configured host did not survive the launch ('$(grep '^LANES_HOST=' "$LANE_START_ENV_LOG" 2>/dev/null)')"; assertion
grep -Fxq 'LANES_OS=windows' "$LANE_START_ENV_LOG" \
    || fail "Amendment 18(a): the one OS word the launcher only passes through was rewritten ('$(grep '^LANES_OS=' "$LANE_START_ENV_LOG" 2>/dev/null)')"; assertion
grep -Fxq 'LANES_CONTAINER=py-bench' "$LANE_START_ENV_LOG" \
    || fail "Amendment 18(a): the bench name threaded in from outside was lost ('$(grep '^LANES_CONTAINER=' "$LANE_START_ENV_LOG" 2>/dev/null)')"; assertion

# 14c. A CONTAINER THAT NAMES NEITHER INVENTS NEITHER — the workstation's own
# rule (`R-A11-14`: nothing is exported where there is no answer, because both
# lane logs are append-only), twice. The OS is still answered, because the
# kernel is readable from inside a container and is the same kernel: it is the
# two NAMES a container cannot work out for itself, not the platform.
launch "FAKE_TMUX_WINDOW=mine-5" "FAKE_LANE_WITH_ROW=mine-5" "container=docker" \
    "LANES_HOST=" "LANES_OS=" "LANES_CONTAINER=" \
    -- run team002 --resume session-a18-not-invented
grep -Fxq 'LANES_HOST=' "$LANE_START_ENV_LOG" \
    || fail "Amendment 18(a): a container with no host configured handed the session one ('$(grep '^LANES_HOST=' "$LANE_START_ENV_LOG" 2>/dev/null)')"; assertion
grep -Fxq 'LANES_CONTAINER=' "$LANE_START_ENV_LOG" \
    || fail "Amendment 18(a): a container nobody named named itself ('$(grep '^LANES_CONTAINER=' "$LANE_START_ENV_LOG" 2>/dev/null)')"; assertion
grep -Eq '^LANES_OS=(linux|macos|wsl|windows)$' "$LANE_START_ENV_LOG" \
    || fail "Amendment 18(a): the OS went unanswered in a container, where the kernel is readable ('$(grep '^LANES_OS=' "$LANE_START_ENV_LOG" 2>/dev/null)')"; assertion

# 14d. ...AND ALL FOUR ARE THREADED ACROSS THE RE-EXEC, where inheritance is not
# reliable: `tmux new-session` hands the child the SERVER's environment, so a
# value reaches the session the launcher creates outside tmux only by being
# written into the command string — the launcher's own reason for threading the
# workstation, and the same reason for the three beside it.
tty_launch "TMUX=" "FAKE_TMUX_WINDOW=claude" "FAKE_SWAPPED_STATUS=8" "CLAUDE_LANE=a18-carried" \
    "LANES_HOST=eagle" "LANES_OS=wsl" "LANES_CONTAINER=py-bench" \
    -- run team002 --resume session-a18-threaded
for a18_pair in LANES_WORKSTATION=Eagle LANES_HOST=eagle LANES_OS=wsl LANES_CONTAINER=py-bench; do
    grep -q "$a18_pair" "$TMUX_LOG" \
        || fail "Amendment 18(a): $a18_pair was not threaded into the tmux session the launcher created ($(cat "$TMUX_LOG"))"; assertion
done
# ...and the three are CLEARED in the same command string before they are set
# (Copilot round 1, opensoft/workBenches#101). Omitting an assignment does not
# make the child's variable unset — the command runs in the tmux SERVER's
# environment, which is the whole reason anything is threaded — so the clears
# are what make "no answer" mean no answer.
for a18_clear in '-u LANES_HOST' '-u LANES_OS' '-u LANES_CONTAINER'; do
    grep -q -e "$a18_clear" "$TMUX_LOG" \
        || fail "Amendment 18(a): the tmux command string does not clear ${a18_clear#-u } before setting it, so the server's own value reaches the child ($(cat "$TMUX_LOG"))"; assertion
done

# 14e. A VALUE THE LAUNCHER HAS NO ANSWER FOR IS CLEARED AND NOT PASSED — the
# other half of the same fix, and the case it exists for: inside a container
# nobody named, the child must come up with no `LANES_HOST` and no
# `LANES_CONTAINER` at all, so the lane tooling falls back to its own probe
# instead of reading whatever the tmux server was started with. The OS is still
# assigned, because it is still answered.
tty_launch "TMUX=" "FAKE_TMUX_WINDOW=claude" "FAKE_SWAPPED_STATUS=8" "CLAUDE_LANE=a18-unanswered" \
    "container=docker" "LANES_HOST=" "LANES_OS=" "LANES_CONTAINER=" \
    -- run team002 --resume session-a18-unanswered
grep -q 'LANES_HOST=' "$TMUX_LOG" \
    && fail "Amendment 18(a): a host the launcher could not name was assigned into the tmux command string anyway ($(cat "$TMUX_LOG"))"; assertion
grep -q 'LANES_CONTAINER=' "$TMUX_LOG" \
    && fail "Amendment 18(a): a container the launcher could not name was assigned into the tmux command string anyway ($(cat "$TMUX_LOG"))"; assertion
grep -Eq 'LANES_OS=(linux|macos|wsl|windows)' "$TMUX_LOG" \
    || fail "Amendment 18(a): the OS, which IS answered in a container, was not threaded ($(cat "$TMUX_LOG"))"; assertion
for a18_clear in '-u LANES_HOST' '-u LANES_OS' '-u LANES_CONTAINER'; do
    grep -q -e "$a18_clear" "$TMUX_LOG" \
        || fail "Amendment 18(a): ${a18_clear#-u } is neither cleared nor set, so the child inherits the tmux server's own ($(cat "$TMUX_LOG"))"; assertion
done

# 14f. THE STATIC HALF. Every reader takes the configured value first, the
# export is called, all three are threaded, and the container launcher carries
# the same three into the bench it opens — including the one fact only it can
# answer, the bench's own name. A scenario cannot reach the second half at all:
# `scripts/wave-container-shell.sh` runs `docker exec` against a real daemon.
scenario
WAVE_SHELL="$REPO_ROOT/scripts/wave-container-shell.sh"
grep -Fq 'name="${LANES_HOST:-}"' "$LAUNCHER" \
    || fail "Amendment 18(a): the launcher does not take an already-set LANES_HOST first"; assertion
grep -Fq 'name="${LANES_OS:-}"' "$LAUNCHER" \
    || fail "Amendment 18(a): the launcher does not take an already-set LANES_OS first, so the one word it never derives could never be passed through"; assertion
grep -Fq 'name="${LANES_CONTAINER:-}"' "$LAUNCHER" \
    || fail "Amendment 18(a): the launcher does not take an already-set LANES_CONTAINER first, which is the only way a container is ever named"; assertion
grep -Fq 'lane_export_binding_facts' "$LAUNCHER" \
    || fail "Amendment 18(a): nothing calls the export, so the session comes up without the three anyway"; assertion
for a18_var in LANES_HOST LANES_OS LANES_CONTAINER; do
    grep -Fq "env_prefix+=(\"$a18_var=\$$a18_var\")" "$LAUNCHER" \
        || fail "Amendment 18(a): $a18_var is not threaded across the re-exec, where a fresh export is not reliably inherited"; assertion
done
grep -Fq 'lanes_host="${LANES_HOST:-}"' "$WAVE_SHELL" \
    || fail "Amendment 18(a): the container launcher does not take an already-configured host first"; assertion
grep -Fq 'lanes_os="${LANES_OS:-}"' "$WAVE_SHELL" \
    || fail "Amendment 18(a): the container launcher does not take an already-configured OS first"; assertion
grep -Fq 'lanes_host_env=(--env "LANES_HOST=$lanes_host")' "$WAVE_SHELL" \
    || fail "Amendment 18(a): the bench container is opened without the host's name"; assertion
grep -Fq 'lanes_os_env=(--env "LANES_OS=$lanes_os")' "$WAVE_SHELL" \
    || fail "Amendment 18(a): the bench container is opened without the OS word"; assertion
grep -Fq -e '--env "LANES_CONTAINER=$container"' "$WAVE_SHELL" \
    || fail "Amendment 18(a): the bench container is opened without being told its own name, which is the one fact only that script has"; assertion
grep -Fq '${lanes_host_env[@]+"${lanes_host_env[@]}"}' "$WAVE_SHELL" \
    || fail "Amendment 18(a): the host is resolved for the container and never passed to docker exec"; assertion
grep -Fq '${lanes_os_env[@]+"${lanes_os_env[@]}"}' "$WAVE_SHELL" \
    || fail "Amendment 18(a): the OS is resolved for the container and never passed to docker exec"; assertion
# ...and the host is resolved BEFORE that script assigns `container` for its own
# purposes, for the same reason the workstation is: the systemd container marker
# is an environment variable of exactly that name, and after `container=` has run
# it cannot be read at all.
a18_host_line="$(grep -n 'lanes_host="${LANES_HOST:-}"' "$WAVE_SHELL" | head -n 1 | cut -d : -f 1)"
a18_bench_line="$(grep -n '^container="py-bench"' "$WAVE_SHELL" | head -n 1 | cut -d : -f 1)"
[[ -n "$a18_host_line" && -n "$a18_bench_line" && "$a18_host_line" -lt "$a18_bench_line" ]] \
    || fail "Amendment 18(a): the container marker is read at line $a18_host_line, after that script overwrites \$container at line $a18_bench_line"; assertion
# ...and --help says where all four come from, because the one per-host act for
# a machine whose values are not its defaults is to set them, and nothing else
# in this launcher prints them.
"$LAUNCHER" --help > "$TEST_ROOT/help.out" 2>&1 || true
grep -Fq 'AND WHERE THE LANE IS RUNNING IS EXPORTED BESIDE IT' "$TEST_ROOT/help.out" \
    || fail "Amendment 18(a): --help does not say where host, os and container come from"; assertion
for a18_word in linux macos wsl windows; do
    grep -Fq "$a18_word" "$TEST_ROOT/help.out" \
        || fail "Amendment 18(a): --help does not name the OS word '$a18_word', and the tooling drops any word that is not one of the four"; assertion
done

[[ "$scenarios" -eq "$EXPECTED_SCENARIOS" ]] \
    || fail "$scenarios scenarios ran, $EXPECTED_SCENARIOS expected — one was added or lost without saying so"
echo "claude-profile lane default: $scenarios scenarios, $assertions assertions passed"
