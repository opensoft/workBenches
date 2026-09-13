#!/usr/bin/env bash
# Regression tests for claude-profile's AMENDMENT 11 — the launcher half of
# lane-collision-protocol Amendment 11, ratified by Brett Heap 2026-09-13
# ("a11 1-5 yes, push them") on brettheap/new-workstation#20 and specified by
# that issue's `SPEC — Amendment 11` comment. Four things are pinned here:
#
#   (1) ONE WORD STARTS A LANE. `pclaude <profile>` IS `pclaude run <profile>`.
#       The fallthrough to `run` was unconditional before this — ANY first word
#       that was not an action became a profile, so `pclaude --resume` came back
#       as "Unknown Claude profile: --resume", which names the wrong thing. It
#       is now a decision with two tests: not an option, and a word this
#       launcher can RESOLVE. The four action words still win.
#
#   (2) THE WINDOW IS REUSED (act 1). Inside tmux the launcher creates NO
#       session and never renames the window; outside tmux it still makes one,
#       and that window is now born NAMED for the lane when the lane is certain,
#       with automatic-rename off, so the NEXT restart typed in it binds by
#       name. Before this, every launch made a fresh session whose window tmux
#       names for the command that made it (8 of Eagle's 16 live windows were
#       called `claude`), so a restart could never bind by window name and
#       always fell to the swap record's one question — Evidence 1.
#
#   (3) THE LANE'S DIRECTORY. `lane-start`'s default is $PROJECTS_ROOT/<repo>,
#       and a checkout that is somewhere else ENDED the launch: `pclaude --lane
#       openXfactory-5 run team01l` exited 1 on "no such directory ... pass
#       --dir", the exec'd process was the only command of the tmux session the
#       launcher had just made, and tmux printed `[exited]` over a window with
#       no Claude in it — Evidence 2. The directory is now learnt and passed as
#       `--dir`, and lane-start is RUN on every path rather than exec'd, so a
#       refusal can never leave a window with no Claude.
#
#   (4) THE RECORD FOR *THIS* WINDOW — precedence step 3 (SPEC §2), between the
#       window name and the swapped guess. A row whose `window` sub-field names
#       this window's `<@id>` or `<session>:<index>` is an exact match on the
#       window the operator is standing in, so it goes to lane-start BARE. Only
#       the newest-first row of step 4 is still a guess, and still `--confirm`.
#
# Everything the launcher shells out to is faked — tmux, lanes-edit.sh,
# lane-start and claude — so the assertions are about the launcher's own
# resolution and nothing else. The fakes are deliberately the SAME SHAPE as
# test-claude-profile-lane-default.sh's, which pins Amendment 8(c): the two
# suites test one resolution from two amendments and must not drift into two
# different pictures of the estate.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LAUNCHER="${1:-$REPO_ROOT/base-image/files/claude-profile}"

# Ambient lane/tmux state from the shell running this test — including a shell
# that is itself a claude-profile-launched tmux child — must not reach the
# launcher: every scenario below sets the tmux and lane state it means to test.
unset TMUX TMUX_PANE WORKBENCHES_CLAUDE_TMUX WORKBENCHES_CLAUDE_TMUX_CHILD \
    WORKBENCHES_CLAUDE_WINDOW WORKBENCHES_CLAUDE_WINDOW_ID \
    WORKBENCHES_CLAUDE_WINDOW_REF WORKBENCHES_TMUX_SESSION \
    WORKBENCHES_TMUX_PANE CLAUDE_LANE CLAUDE_NO_LANE CLAUDE_LANE_DIR \
    LANES_WORKSTATION PROJECTS_ROOT WORKBENCHES_CLAUDE_LANE_DIR_FROM_CWD \
    2>/dev/null || true

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

# THE CWD IS PART OF THE STATE UNDER TEST, so this suite pins it. Amendment
# 11(3)'s last rung reads the cwd's own git checkout, which means a suite run
# from inside a checkout whose basename happens to be a lane's <repo> resolves a
# directory nobody asked for — and one run from `~/projects/openRepoProject`
# did exactly that, handing lane-start `--dir /home/brett/projects/...` in
# scenarios that are not about directories at all. Every scenario below either
# stands in $TEST_ROOT, which is nobody's checkout, or `cd`s into a tree it made
# itself. GIT_CEILING_DIRECTORIES stops `rev-parse --show-toplevel` walking out
# of $TEST_ROOT on a machine whose temp directory sits inside a repository.
cd "$TEST_ROOT"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

# A scenario is one run of the launcher; an assertion is one check made about
# it. Both are counted and printed, because a scenario that silently stops
# running — or a `launch` that never happened — is otherwise invisible in a
# suite whose only output is the word "passed". The scenario count is pinned as
# well as printed, so deleting one fails the suite rather than quietly changing
# a number.
EXPECTED_SCENARIOS=40
scenarios=0
assertions=0
scenario() { scenarios=$((scenarios + 1)); }
assertion() { assertions=$((assertions + 1)); }

PROFILE_BASE="$TEST_ROOT/profiles-home"
PROFILE_DIR="$PROFILE_BASE/profiles/opensoft/team/team-002"
RUN_PROFILE_DIR="$PROFILE_BASE/profiles/opensoft/team/run"
MANIFEST="$TEST_ROOT/claude-profiles.json"
FAKE_BIN="$TEST_ROOT/bin"
FAKE_CLAUDE="$FAKE_BIN/claude"
CLAUDE_LOG="$TEST_ROOT/claude.log"
TMUX_LOG="$TEST_ROOT/tmux.log"
LANE_START_LOG="$TEST_ROOT/lane-start.log"
LANES_EDIT_LOG="$TEST_ROOT/lanes-edit.log"
ERR_LOG="$TEST_ROOT/stderr.log"
OUT_LOG="$TEST_ROOT/stdout.log"
FAKE_HOME="$TEST_ROOT/home"
mkdir -p "$PROFILE_DIR" "$RUN_PROFILE_DIR" "$FAKE_BIN" "$FAKE_HOME"

# A profile called `run` exists in this estate ON PURPOSE. It is the one word
# whose meaning the amendment has to decide, and the decision is that the VERB
# wins and `pclaude run run` is the way to the profile — ambiguity resolved in
# the one direction an operator can undo.
printf '%s\n' \
    '{"profiles":[{"name":"team-002","email":"test@example.invalid","family":"testing","aliases":["team002"],"profilePath":"opensoft/team/team-002"},{"name":"run","email":"run@example.invalid","family":"testing","aliases":[],"profilePath":"opensoft/team/run"}]}' \
    > "$MANIFEST"
printf '%s\n' '{"name":"team-002","family":"testing","email":"test@example.invalid","aliases":["team002"]}' \
    > "$PROFILE_DIR/.profile.json"
printf '%s\n' '{"name":"run","family":"testing","email":"run@example.invalid","aliases":[]}' \
    > "$RUN_PROFILE_DIR/.profile.json"

cat > "$FAKE_CLAUDE" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${FAKE_CLAUDE_LOG:?}"
EOF

# tmux. `display-message -p '#W'` is the window NAME the launcher resolves a
# lane from; `#S:#I` and `#{window_id}` are the window's ADDRESS, which
# Amendment 11(5) records as information and precedence step 3 matches the swap
# record against. They are separate probes in the launcher and separate arms
# here, deliberately: a combined format string would change what the one read
# every other part of this feature is specified against sees.
#
# `rename-window` matters because it is the one act of lane-start's the
# launcher can OBSERVE: taking a lane renames the window to it, so the name read
# back after lane-start ran says whether it took the lane or refused it.
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
            '#S:#I')            printf '%s\n' "${FAKE_TMUX_WINDOW_REF-fake-session:0}" ;;
            '#{window_id}')     printf '%s\n' "${FAKE_TMUX_WINDOW_ID-@7}" ;;
            *) printf 'fake\n' ;;
        esac
        ;;
    rename-window)
        [[ -z "${FAKE_TMUX_WINDOW_FILE:-}" ]] || printf '%s\n' "${2:-}" > "$FAKE_TMUX_WINDOW_FILE"
        ;;
    attach-session) exit 0 ;;
esac
EOF

# The lane register, read-only, as Amendment 8 and Amendment 11 have the
# launcher read it:
#   register-row <name>   0 = <name> is a lane with a row, 8 = no row,
#                         2 = not even a lane-shaped name
#   swapped [<ws>]        0 = rows `<lane>\t<UTC>\t<window>[\t<dir>]`, most
#                         recent first; 8 = none; 2 = a helper predating
#                         Amendment 8, which has no such subcommand
#   lane-dir <lane>       0 = the lane's recorded directory on stdout, 8 = none
#                         (SPEC §11). A helper that does not have it yet answers
#                         the unknown-subcommand line and 2, and THAT is the
#                         estate as it stands today: FAKE_LANE_DIR unset is the
#                         real workstation.
cat > "$FAKE_BIN/lanes-edit.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
{
    printf 'argv=%s\n' "$*"
    printf 'LANES_NO_FETCH=%s\n' "${LANES_NO_FETCH:-}"
} >> "${FAKE_LANES_EDIT_LOG:?}"
case "${1:-}" in
    register-row)
        if [[ -n "${FAKE_LANE_WITH_ROW:-}" && "${2:-}" == "${FAKE_LANE_WITH_ROW}" ]]; then
            printf '| %s | row |\n' "$2"
            exit 0
        fi
        exit "${FAKE_REGISTER_ROW_OTHER:-8}"
        ;;
    swapped)
        if [[ "${FAKE_SWAPPED_STATUS:-8}" -eq 0 ]]; then
            printf '%b' "${FAKE_SWAPPED_ROWS:-}"
        fi
        exit "${FAKE_SWAPPED_STATUS:-8}"
        ;;
    lane-dir)
        if [[ -n "${FAKE_LANE_DIR:-}" ]]; then
            printf '%s\n' "$FAKE_LANE_DIR"
            exit 0
        fi
        [[ -z "${FAKE_LANE_DIR_NONE:-}" ]] || exit 8
        ;;
esac
echo "unknown subcommand '${1:-}'" >&2
exit 2
EOF

# lane-start logs the argv it was launched with, answers --help with whatever
# help this scenario says it has, and exits with whatever status this scenario
# gives it. FAKE_LANE_START_STATUS is the Amendment 11 seam: 1 is the status of
# Evidence 2's refusal ("no such directory ... pass --dir"), and lane-start
# documents 1 and 2 as its ONLY refusals.
cat > "$FAKE_BIN/lane-start" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == --help ]]; then
    printf '%s\n' "${FAKE_LANE_START_HELP:-}"
    exit 0
fi
printf '%s\n' "$*" >> "${FAKE_LANE_START_LOG:?}"
lane_argument=""; rest=(); seen=false
for argument in "$@"; do
    if [[ "$seen" == true ]]; then rest+=("$argument")
    elif [[ "$argument" == -- ]]; then seen=true
    else lane_argument="$argument"
    fi
done
case "${FAKE_LANE_START_DECLINE:-}" in
    # `took` renames the window as lane-start does when it takes a lane, then
    # runs Claude and exits with FAKE_LANE_START_STATUS as Claude's own status.
    took)
        tmux rename-window "$lane_argument" >/dev/null 2>&1 || true
        "${CLAUDE_BIN:?}" ${rest[@]+"${rest[@]}"}
        exit "${FAKE_LANE_START_STATUS:-0}"
        ;;
esac
# The refusal: nothing renamed, nothing written, no Claude.
echo "lane-start: refused (fake)" >&2
exit "${FAKE_LANE_START_STATUS:-0}"
EOF

chmod +x "$FAKE_CLAUDE" "$FAKE_BIN/tmux" "$FAKE_BIN/lanes-edit.sh" "$FAKE_BIN/lane-start"

AMENDMENT_11_HELP='OPTIONS
  --dir <path>     the lane s checkout
  --confirm        ask on the tty before taking a window whose name is not
                   the lane
  --yes            skip that question
  -h, --help'
# A lane-start with no --dir at all. There has never been one, but the probe
# exists so that there CAN be, and a probe nothing tests is a probe that lies.
NO_DIR_HELP='OPTIONS
  --confirm        ask before taking a window
  -h, --help'

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
    "FAKE_LANE_START_HELP=$AMENDMENT_11_HELP"
    "WORKBENCHES_SHARED_MCP_FAMILIES=disabled"
    "LANES_WORKSTATION=Eagle"
    "TMUX=fake-session"
    # lane-start's own default, pointed at a tree of this suite's own so that
    # the first fence of the cwd rung is OPEN by default: the scenarios that
    # must not reach that rung then prove it on the rung's own terms, not on an
    # accident of where the suite was run.
    "PROJECTS_ROOT=$TEST_ROOT/projects"
    "GIT_CEILING_DIRECTORIES=$TEST_ROOT"
)

claude_args='--allow-dangerously-skip-permissions --dangerously-skip-permissions --permission-mode bypassPermissions'
note='no lane for this window; run lane-start <repo> <n> inside it'

reset_logs() {
    rm -f "$CLAUDE_LOG" "$TMUX_LOG" "$LANE_START_LOG" "$LANES_EDIT_LOG" "$ERR_LOG" "$OUT_LOG"
}

# launch <scenario env>... -- <launcher args>...
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
        >"$OUT_LOG" 2>"$ERR_LOG"
    launch_status=$?
    set -e
}

# A launch on a real terminal, which is the only way claude_run_is_interactive
# can answer true and therefore the only way the tmux re-exec is reachable.
tty_launch() {
    local -a scenario_env=()
    while [[ $# -gt 0 && "$1" != "--" ]]; do
        scenario_env+=("$1")
        shift
    done
    shift
    reset_logs
    scenario
    local tty_command value
    printf -v tty_command 'env'
    for value in "${common_env[@]}" "${scenario_env[@]}" "$LAUNCHER" "$@"; do
        printf -v value '%q' "$value"
        tty_command+=" $value"
    done
    set +e
    script -qefc "$tty_command" "$TEST_ROOT/typescript.log" >/dev/null 2>&1
    launch_status=$?
    set -e
}

lane_start_argv() { cat "$LANE_START_LOG" 2>/dev/null || true; }

# ===========================================================================
# 1. ONE WORD STARTS A LANE — Amendment 11(1), SPEC §1.
# ===========================================================================

# 1a. THE SCENARIO SPEC §1 OWES: `pclaude team002` and `pclaude run team002`
# build the same argv. Not "both launch" — the SAME argv, because the whole
# claim is that the verb is noise and nothing downstream can tell which form
# was typed.
launch "FAKE_TMUX_WINDOW=claude" "FAKE_SWAPPED_STATUS=8" \
    -- team002 --resume session-oneword
oneword_claude="$(cat "$CLAUDE_LOG")"
launch "FAKE_TMUX_WINDOW=claude" "FAKE_SWAPPED_STATUS=8" \
    -- run team002 --resume session-oneword
[[ "$oneword_claude" == "$(cat "$CLAUDE_LOG")" ]] \
    || fail "one word: 'team002' built '$oneword_claude', 'run team002' built '$(cat "$CLAUDE_LOG")'"; assertion
[[ "$oneword_claude" == "$claude_args --resume session-oneword" ]] \
    || fail "one word: the argv was '$oneword_claude'"; assertion

# 1b. An ALIAS is a profile too. `profile_metadata` resolves names and aliases
# alike, and the one-word test is that same resolution — so every word
# `pclaude list` prints starts one word, and nothing else does.
launch "FAKE_TMUX_WINDOW=claude" "FAKE_SWAPPED_STATUS=8" \
    -- team-002 --resume session-alias
grep -Fxq -- "$claude_args --resume session-alias" "$CLAUDE_LOG" \
    || fail "one word by alias: Claude's argv was '$(cat "$CLAUDE_LOG" 2>/dev/null)'"; assertion

# 1c. THE ACTION WORDS WIN over a profile of the same name. This estate has a
# profile called `run`; `pclaude run` is still the verb, so it reads the next
# word as the profile and refuses when there is none, rather than launching the
# profile called `run`.
launch "FAKE_TMUX_WINDOW=claude" "FAKE_SWAPPED_STATUS=8" -- run
[[ "$launch_status" -ne 0 ]] \
    || fail "verb wins: bare 'run' launched something (status $launch_status)"; assertion
[[ ! -e "$CLAUDE_LOG" ]] \
    || fail "verb wins: 'run' with no profile launched Claude ($(cat "$CLAUDE_LOG"))"; assertion

# 1d. ...and `pclaude run run` is the way to it. The ambiguity is decided in the
# one direction an operator can undo.
launch "FAKE_TMUX_WINDOW=claude" "FAKE_SWAPPED_STATUS=8" \
    -- run run --resume session-runrun
grep -Fxq -- "$claude_args --resume session-runrun" "$CLAUDE_LOG" \
    || fail "run run: the profile called 'run' did not launch ($(cat "$CLAUDE_LOG" 2>/dev/null))"; assertion

# 1e. `list` is still `list`, not a launch. Same rule from the other side: the
# action word is read as the action even where a profile could answer to it.
launch "FAKE_TMUX_WINDOW=claude" "FAKE_SWAPPED_STATUS=8" -- list
[[ "$launch_status" -eq 0 ]] || fail "list: exited $launch_status"; assertion
grep -q 'team-002' "$OUT_LOG" || fail "list: did not list the profiles ($(cat "$OUT_LOG"))"; assertion
[[ ! -e "$CLAUDE_LOG" ]] || fail "list: launched Claude"; assertion

# 1f. MUTATION — a word that is not a profile is REFUSED BY NAME, exit 2. The
# old fallthrough launched it and let the `run` arm report it, which is the
# same sentence one step later; what matters is that a typo can never become a
# launch, and SPEC §1 keeps the wording.
launch "FAKE_TMUX_WINDOW=claude" "FAKE_SWAPPED_STATUS=8" -- teamOO2
[[ "$launch_status" -eq 2 ]] \
    || fail "typo: exited $launch_status, and SPEC §1 says 2"; assertion
grep -q 'Unknown Claude profile: teamOO2' "$ERR_LOG" \
    || fail "typo: the message was '$(cat "$ERR_LOG")'"; assertion
[[ ! -e "$CLAUDE_LOG" ]] || fail "typo: it became a launch anyway"; assertion
[[ ! -e "$LANE_START_LOG" ]] || fail "typo: it reached lane-start"; assertion

# 1g. MUTATION — AN OPTION IS NEVER A PROFILE. This is the case the
# unconditional fallthrough got wrong: `pclaude --resume <id>` took `--resume`
# as the PROFILE, the one argument Claude never sees, and reported "Unknown
# Claude profile: --resume". A leading `-` ends the option loop precisely
# because what follows belongs to Claude.
launch "FAKE_TMUX_WINDOW=claude" "FAKE_SWAPPED_STATUS=8" -- --resume abc123
[[ "$launch_status" -eq 2 ]] || fail "option as profile: exited $launch_status"; assertion
grep -q 'is an option' "$ERR_LOG" \
    || fail "option as profile: the message was '$(cat "$ERR_LOG")'"; assertion
grep -q 'Unknown Claude profile: --resume' "$ERR_LOG" \
    && fail "option as profile: it was still reported as a profile ($(cat "$ERR_LOG"))"; assertion

# 1h. The leading options still lead — before the one-word profile, as they
# always were before the action. `--lane` and `--dir` after the profile are
# Claude's arguments and are not read here, which is what "leading" means.
launch "FAKE_TMUX_WINDOW=claude" "FAKE_LANE_WITH_ROW=nothing" "FAKE_SWAPPED_STATUS=8" \
    -- --lane spoken-3 team002 --resume session-leading
grep -Fxq -- "spoken-3 -- $claude_args --resume session-leading" "$LANE_START_LOG" \
    || fail "leading --lane before one word: lane-start argv was '$(lane_start_argv)'"; assertion

launch "FAKE_TMUX_WINDOW=claude" "FAKE_SWAPPED_STATUS=8" \
    -- team002 --lane spoken-9
grep -Fxq -- "$claude_args --lane spoken-9" "$CLAUDE_LOG" \
    || fail "trailing --lane: it was eaten by the launcher instead of passed to Claude ($(cat "$CLAUDE_LOG" 2>/dev/null))"; assertion
[[ ! -e "$LANE_START_LOG" ]] \
    || fail "trailing --lane: a lane was taken from Claude's own arguments ('$(lane_start_argv)')"; assertion

# 1i. `--help` documents the one-word form and the two new options, and still
# promises `--yes` nowhere.
scenario
env "${common_env[@]}" "$LAUNCHER" --help > "$TEST_ROOT/help.out"
grep -q 'ONE WORD STARTS A LANE' "$TEST_ROOT/help.out" \
    || fail "--help does not document the one-word form"; assertion
grep -q 'THE WINDOW IS REUSED' "$TEST_ROOT/help.out" \
    || fail "--help does not document window reuse"; assertion
grep -q "THE LANE'S DIRECTORY" "$TEST_ROOT/help.out" \
    || fail "--help does not document the directory"; assertion
grep -q -- '--dir <path>' "$TEST_ROOT/help.out" || fail "--help does not document --dir"; assertion
grep -q 'CLAUDE_LANE_DIR' "$TEST_ROOT/help.out" || fail "--help does not document CLAUDE_LANE_DIR"; assertion
grep -q -- '--yes' "$TEST_ROOT/help.out" \
    && fail "--help promises --yes, which is passed nowhere (F-W2)"; assertion

# ===========================================================================
# 2. THE WINDOW IS REUSED — Amendment 11(2) act 1, SPEC §3.
# ===========================================================================

# 2a. INSIDE TMUX, ON A TTY: no session is created. This is act 1 itself. Both
# conditions matter — a tty is what makes claude_run_is_interactive able to
# answer true at all, so a test without one would pass for the wrong reason.
tty_launch "TMUX=fake-session" "FAKE_TMUX_WINDOW=openRepoProject-1" \
    "FAKE_LANE_WITH_ROW=openRepoProject-1" "FAKE_SWAPPED_STATUS=8" \
    -- run team002 --resume session-inside
grep -q 'new-session' "$TMUX_LOG" \
    && fail "inside tmux: a tmux session was created ($(cat "$TMUX_LOG"))"; assertion
grep -Fxq -- "openRepoProject-1 -- $claude_args --resume session-inside" "$LANE_START_LOG" \
    || fail "inside tmux: the current window's lane was not taken ('$(lane_start_argv)')"; assertion
grep -q 'rename-window' "$TMUX_LOG" \
    && fail "inside tmux: the launcher renamed the window, which is lane-start's act alone (A5(f))"; assertion

# 2b. OUTSIDE TMUX, ON A TTY, WITH A CERTAIN LANE: a session IS created, and its
# window is born NAMED for the lane with automatic-rename off. The name is what
# the NEXT restart typed in that window binds by — the whole point of act 1 for
# the launch that has no window to reuse.
tty_launch "TMUX=" "FAKE_TMUX_WINDOW=claude" "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    "FAKE_SWAPPED_STATUS=8" "CLAUDE_LANE=carried-1" \
    -- run team002 --resume session-outside
grep -q 'new-session' "$TMUX_LOG" \
    || fail "outside tmux: no session was created ($(cat "$TMUX_LOG" 2>/dev/null))"; assertion
grep -q -- '-n carried-1' "$TMUX_LOG" \
    || fail "outside tmux: the new window was not named for the lane ($(cat "$TMUX_LOG"))"; assertion
grep -q 'set-window-option .* automatic-rename off' "$TMUX_LOG" \
    || fail "outside tmux: automatic-rename was left on, so the first command renames the window straight back ($(cat "$TMUX_LOG"))"; assertion
grep -q 'CLAUDE_LANE=carried-1' "$TMUX_LOG" \
    || fail "outside tmux: the lane was not carried into the new session"; assertion

# 2c. MUTATION — OUTSIDE TMUX WITH NO CERTAIN LANE, `-n` IS OMITTED. The swap
# record's newest-first row is an INFERENCE that Amendment 8(c) hands over as
# `--confirm` so lane-start asks before taking a window. Naming the window for
# it here would answer that question in advance and in the wrong place: the
# child would then find a window named for the lane and bind by NAME, silently,
# from a guess nobody confirmed.
tty_launch "TMUX=" "FAKE_TMUX_WINDOW=claude" "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=openRepoProject-1\t2026-09-12T17:04Z\tclaude-a:0\n" \
    -- run team002 --resume session-outside-guess
grep -q 'new-session' "$TMUX_LOG" || fail "outside tmux, no certain lane: no session was created"; assertion
grep -q -- ' -n ' "$TMUX_LOG" \
    && fail "outside tmux, no certain lane: the window was named from a guess nobody confirmed ($(cat "$TMUX_LOG"))"; assertion

# 2d. The window's ADDRESS crosses the re-exec beside its name. Amendment 11(5):
# the id is information and the name is the key, so both travel and neither is
# re-read on the far side — the new session's window is not the lane's window.
tty_launch "TMUX=" "FAKE_TMUX_WINDOW=claude" "FAKE_SWAPPED_STATUS=8" "CLAUDE_LANE=carried-2" \
    -- run team002 --resume session-addr
grep -q 'WORKBENCHES_CLAUDE_WINDOW=' "$TMUX_LOG" \
    && fail "re-exec: a window NAME was carried from a launch that came from no window ($(cat "$TMUX_LOG"))"; assertion
grep -q 'WORKBENCHES_CLAUDE_WINDOW_ID=' "$TMUX_LOG" \
    && fail "re-exec: a window ID was carried from a launch that came from no window ($(cat "$TMUX_LOG"))"; assertion

# 2e. A child of the re-exec takes the address that was threaded and never asks
# tmux for its own — the session it is in was made moments ago and its window is
# named for the command that made it.
launch "WORKBENCHES_CLAUDE_TMUX_CHILD=1" \
    "WORKBENCHES_CLAUDE_WINDOW=openRepoProject-1" \
    "WORKBENCHES_CLAUDE_WINDOW_ID=@71" \
    "WORKBENCHES_CLAUDE_WINDOW_REF=lane-session:3" \
    "FAKE_TMUX_WINDOW=claude-team-002-20260913060000-1234" \
    "FAKE_TMUX_WINDOW_ID=@999" \
    "FAKE_LANE_WITH_ROW=openRepoProject-1" "FAKE_SWAPPED_STATUS=8" \
    -- run team002 --resume session-child
grep -Fxq -- "openRepoProject-1 -- $claude_args --resume session-child" "$LANE_START_LOG" \
    || fail "tmux child: the carried window name was not the lane ('$(lane_start_argv)')"; assertion
grep -Fxq 'display-message -p #{window_id}' "$TMUX_LOG" \
    && fail "tmux child: the launcher asked tmux for the new session's window id"; assertion

# 2f. A WINDOW NAMED FOR ANOTHER LANE RESOLVES THAT LANE. The window is the key
# (Rule 4) and the launcher does not second-guess it; `--lane` is the way out
# and `--no-lane` is the other one. Stated here because it is the edge case an
# operator meets by walking into the wrong window, and a launcher that quietly
# preferred something else would be worse than one that is predictable.
launch "FAKE_TMUX_WINDOW=otherLane-4" "FAKE_LANE_WITH_ROW=otherLane-4" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=mineLane-1\t2026-09-12T17:04Z\tclaude-a:0\n" \
    -- run team002 --resume session-otherwindow
grep -Fxq -- "otherLane-4 -- $claude_args --resume session-otherwindow" "$LANE_START_LOG" \
    || fail "window of another lane: lane-start argv was '$(lane_start_argv)'"; assertion

launch "FAKE_TMUX_WINDOW=otherLane-4" "FAKE_LANE_WITH_ROW=otherLane-4" "FAKE_SWAPPED_STATUS=8" \
    -- --lane mineLane-1 run team002 --resume session-override
grep -Fxq -- "mineLane-1 -- $claude_args --resume session-override" "$LANE_START_LOG" \
    || fail "window of another lane, --lane given: lane-start argv was '$(lane_start_argv)'"; assertion

# ===========================================================================
# 3. THE RECORD FOR *THIS* WINDOW — precedence step 3, SPEC §2.
# ===========================================================================

# 3a. The record whose `window` field names THIS window's `<@id>`. It is an
# exact match on the window the operator is standing in, so it is taken BARE —
# no `--confirm`, no question — even though the row is not the newest one.
launch "FAKE_TMUX_WINDOW=zsh" "FAKE_LANE_WITH_ROW=nothing" \
    "FAKE_TMUX_WINDOW_ID=@97" "FAKE_TMUX_WINDOW_REF=some-session:2" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=newest-9\t2026-09-13T03:31:56Z\tclaude-x:0 @12\nmine-5\t2026-09-13T03:31:33Z\tclaude-y:0 @97\n" \
    -- run team002 --resume session-byid
grep -Fxq -- "mine-5 -- $claude_args --resume session-byid" "$LANE_START_LOG" \
    || fail "record by @id: lane-start argv was '$(lane_start_argv)'"; assertion
grep -q -- '--confirm' "$LANE_START_LOG" \
    && fail "record by @id: an EXACT match on this window was confirmed ($(lane_start_argv))"; assertion
grep -Fq 'newest-9' "$LANE_START_LOG" \
    && fail "record by @id: the newest row beat the row that names this window"; assertion

# 3b. ...and by `<session>:<index>` where no id is recorded. The id is the
# better key and is tried first, but a record written before ids were recorded
# still names its window, and that is still exact.
launch "FAKE_TMUX_WINDOW=zsh" "FAKE_LANE_WITH_ROW=nothing" \
    "FAKE_TMUX_WINDOW_ID=@97" "FAKE_TMUX_WINDOW_REF=claude-y:0" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=newest-9\t2026-09-13T03:31:56Z\tclaude-x:0\nmine-5\t2026-09-13T03:31:33Z\tclaude-y:0\n" \
    -- run team002 --resume session-byref
grep -Fxq -- "mine-5 -- $claude_args --resume session-byref" "$LANE_START_LOG" \
    || fail "record by session:index: lane-start argv was '$(lane_start_argv)'"; assertion
grep -q -- '--confirm' "$LANE_START_LOG" \
    && fail "record by session:index: an exact match was confirmed"; assertion

# 3c. MUTATION — NO ROW NAMES THIS WINDOW, so the newest-first guess of
# precedence 4 applies and IT IS STILL CONFIRMED. The whole value of step 3 is
# that it is not a guess; a launcher that took the newest row bare because step
# 3 had merely been TRIED would have turned Amendment 8(c)'s one question into
# silence, and on 2026-09-13 the two newest records were 23 seconds apart.
launch "FAKE_TMUX_WINDOW=zsh" "FAKE_LANE_WITH_ROW=nothing" \
    "FAKE_TMUX_WINDOW_ID=@55" "FAKE_TMUX_WINDOW_REF=nobody:9" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=newest-9\t2026-09-13T03:31:56Z\tclaude-x:0 @12\nmine-5\t2026-09-13T03:31:33Z\tclaude-y:0 @97\n" \
    -- run team002 --resume session-noexact
grep -Fxq -- "--confirm newest-9 -- $claude_args --resume session-noexact" "$LANE_START_LOG" \
    || fail "no exact record: lane-start argv was '$(lane_start_argv)'"; assertion

# 3d. The WINDOW NAME still beats the record, and when it answers the record is
# not read at all. Precedence 2 is first for a reason: it is the register's own
# word about a live window, and the record is a copy of an address.
launch "FAKE_TMUX_WINDOW=openRepoProject-1" "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    "FAKE_TMUX_WINDOW_ID=@97" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=mine-5\t2026-09-13T03:31:33Z\tclaude-y:0 @97\n" \
    -- run team002 --resume session-namewins
grep -Fxq -- "openRepoProject-1 -- $claude_args --resume session-namewins" "$LANE_START_LOG" \
    || fail "name beats record: lane-start argv was '$(lane_start_argv)'"; assertion
grep -Fq 'argv=swapped' "$LANES_EDIT_LOG" \
    && fail "name beats record: the record was read even though the window answered"; assertion

# ===========================================================================
# 4. THE LANE'S DIRECTORY — Amendment 11(3), SPEC §4 and §11.
# ===========================================================================

LANE_TREE="$TEST_ROOT/trees/openXfactory"
RECORD_TREE="$TEST_ROOT/trees/from-record"
mkdir -p "$LANE_TREE" "$RECORD_TREE"

# 4a. `--dir` is passed straight through, exactly as typed. It is the
# operator's word, and it is NOT tested for existence here: lane-start's own
# refusal names the path and the flag that fixes it, and a launcher that
# silently dropped what it was told would hide that.
launch "FAKE_TMUX_WINDOW=openRepoProject-1" "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    "FAKE_SWAPPED_STATUS=8" \
    -- --dir "$LANE_TREE" run team002 --resume session-dirflag
grep -Fxq -- "--dir $LANE_TREE openRepoProject-1 -- $claude_args --resume session-dirflag" "$LANE_START_LOG" \
    || fail "--dir: lane-start argv was '$(lane_start_argv)'"; assertion

launch "FAKE_TMUX_WINDOW=openRepoProject-1" "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    "FAKE_SWAPPED_STATUS=8" "CLAUDE_LANE_DIR=$LANE_TREE" \
    -- run team002 --resume session-direnv
grep -Fxq -- "--dir $LANE_TREE openRepoProject-1 -- $claude_args --resume session-direnv" "$LANE_START_LOG" \
    || fail "CLAUDE_LANE_DIR: lane-start argv was '$(lane_start_argv)'"; assertion

# 4b. The SWAP RECORD's fourth tab-separated field (SPEC §11). It comes free
# with the row the lane itself was resolved from, so nothing is read twice for
# it — and it is the field the tooling PR will start writing.
launch "FAKE_TMUX_WINDOW=zsh" "FAKE_LANE_WITH_ROW=nothing" \
    "FAKE_TMUX_WINDOW_ID=@97" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=mine-5\t2026-09-13T03:31:33Z\tclaude-y:0 @97\t$RECORD_TREE\n" \
    -- run team002 --resume session-dirrecord
grep -Fxq -- "--dir $RECORD_TREE mine-5 -- $claude_args --resume session-dirrecord" "$LANE_START_LOG" \
    || fail "record dir: lane-start argv was '$(lane_start_argv)'"; assertion

# 4c. `lanes-edit.sh lane-dir <lane>` (SPEC §11), for a lane whose record is not
# what resolved it.
launch "FAKE_TMUX_WINDOW=openXfactory-5" "FAKE_LANE_WITH_ROW=openXfactory-5" \
    "FAKE_SWAPPED_STATUS=8" "FAKE_LANE_DIR=$LANE_TREE" \
    -- run team002 --resume session-lanedir
grep -Fxq -- "--dir $LANE_TREE openXfactory-5 -- $claude_args --resume session-lanedir" "$LANE_START_LOG" \
    || fail "lane-dir: lane-start argv was '$(lane_start_argv)'"; assertion
grep -Fq 'argv=lane-dir openXfactory-5' "$LANES_EDIT_LOG" \
    || fail "lane-dir: it was never asked ($(cat "$LANES_EDIT_LOG"))"; assertion
grep -Fxq 'LANES_NO_FETCH=1' "$LANES_EDIT_LOG" \
    || fail "lane-dir: the read was made without LANES_NO_FETCH=1, so a launch waits on the network"; assertion

# 4d. DEGRADATION — today's helper has no `lane-dir` at all: it answers the
# unknown-subcommand line and exits 2. Only 0 with an existing directory is an
# answer, so that line can never be mistaken for a path, and the launch is
# byte-for-byte what it was before Amendment 11.
launch "FAKE_TMUX_WINDOW=openRepoProject-1" "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    "FAKE_SWAPPED_STATUS=8" \
    -- run team002 --resume session-nolanedir
grep -Fxq -- "openRepoProject-1 -- $claude_args --resume session-nolanedir" "$LANE_START_LOG" \
    || fail "no lane-dir subcommand: lane-start argv was '$(lane_start_argv)'"; assertion
grep -q -- '--dir' "$LANE_START_LOG" \
    && fail "no lane-dir subcommand: an unknown-subcommand line became a directory ($(lane_start_argv))"; assertion

# 4e. DEGRADATION — a lane-start with no `--dir` in its help is handed none,
# whatever the launcher learnt. The probe is the same `--help` read `--confirm`
# uses, and a probe nothing tests is a probe that lies.
launch "FAKE_TMUX_WINDOW=openRepoProject-1" "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    "FAKE_SWAPPED_STATUS=8" "FAKE_LANE_START_HELP=$NO_DIR_HELP" \
    -- --dir "$LANE_TREE" run team002 --resume session-nodirflag
grep -Fxq -- "openRepoProject-1 -- $claude_args --resume session-nodirflag" "$LANE_START_LOG" \
    || fail "lane-start without --dir: lane-start argv was '$(lane_start_argv)'"; assertion

# 4f. THE CWD RUNG, and Evidence 2's own shapes. The lane is `openXfactory-5`,
# `$PROJECTS_ROOT/openXfactory` does not exist, and the cwd's checkout is
# `.../openxFactory` — the same word in a different case, which is exactly what
# made lane-start die. It fires, and it fires only because BOTH fences are open.
CWD_TREE="$TEST_ROOT/xFactory/openxFactory"
mkdir -p "$CWD_TREE"
git -C "$CWD_TREE" init -q 2>/dev/null || true
reset_logs
scenario
set +e
( cd "$CWD_TREE" && env "${common_env[@]}" \
    "FAKE_TMUX_WINDOW=openXfactory-5" "FAKE_LANE_WITH_ROW=openXfactory-5" \
    "FAKE_SWAPPED_STATUS=8" "PROJECTS_ROOT=$TEST_ROOT/projects" \
    "$LAUNCHER" run team002 --resume session-cwd >/dev/null 2>"$ERR_LOG" )
launch_status=$?
set -e
grep -Fxq -- "--dir $CWD_TREE openXfactory-5 -- $claude_args --resume session-cwd" "$LANE_START_LOG" \
    || fail "cwd rung: lane-start argv was '$(lane_start_argv)'"; assertion

# 4g. MUTATION — THE FIRST FENCE. With `$PROJECTS_ROOT/<repo>` present,
# lane-start's own default works and the rung must not fire. A derived path that
# overrode a working default could move a lane into another tree, where
# lane-start writes THAT tree's origin into the lane's Amendment 7 STARTED line
# as its HOME — a home every `#n` the lane writes then inherits.
mkdir -p "$TEST_ROOT/projects/openXfactory"
reset_logs
scenario
set +e
( cd "$CWD_TREE" && env "${common_env[@]}" \
    "FAKE_TMUX_WINDOW=openXfactory-5" "FAKE_LANE_WITH_ROW=openXfactory-5" \
    "FAKE_SWAPPED_STATUS=8" "PROJECTS_ROOT=$TEST_ROOT/projects" \
    "$LAUNCHER" run team002 --resume session-cwd-fenced >/dev/null 2>"$ERR_LOG" )
launch_status=$?
set -e
grep -q -- '--dir' "$LANE_START_LOG" \
    && fail "cwd rung, default present: a working default was overridden ($(lane_start_argv))"; assertion
grep -Fxq -- "openXfactory-5 -- $claude_args --resume session-cwd-fenced" "$LANE_START_LOG" \
    || fail "cwd rung, default present: lane-start argv was '$(lane_start_argv)'"; assertion
rm -rf "$TEST_ROOT/projects/openXfactory"

# 4h. MUTATION — THE SECOND FENCE. A checkout whose basename is NOT the lane's
# `<repo>` token is not this lane's tree, whatever the operator happens to be
# standing in. Without this fence the rung would start any lane in any
# directory that merely happened to be a git checkout.
OTHER_TREE="$TEST_ROOT/elsewhere/unrelated"
mkdir -p "$OTHER_TREE"
git -C "$OTHER_TREE" init -q 2>/dev/null || true
reset_logs
scenario
set +e
( cd "$OTHER_TREE" && env "${common_env[@]}" \
    "FAKE_TMUX_WINDOW=openXfactory-5" "FAKE_LANE_WITH_ROW=openXfactory-5" \
    "FAKE_SWAPPED_STATUS=8" "PROJECTS_ROOT=$TEST_ROOT/projects" \
    "$LAUNCHER" run team002 --resume session-cwd-unrelated >/dev/null 2>"$ERR_LOG" )
launch_status=$?
set -e
grep -q -- '--dir' "$LANE_START_LOG" \
    && fail "cwd rung, unrelated checkout: it was taken as the lane's tree ($(lane_start_argv))"; assertion

# 4i. ...and the opt-out turns the inference off entirely, leaving lane-start's
# default in place.
reset_logs
scenario
set +e
( cd "$CWD_TREE" && env "${common_env[@]}" \
    "FAKE_TMUX_WINDOW=openXfactory-5" "FAKE_LANE_WITH_ROW=openXfactory-5" \
    "FAKE_SWAPPED_STATUS=8" "PROJECTS_ROOT=$TEST_ROOT/projects" \
    "WORKBENCHES_CLAUDE_LANE_DIR_FROM_CWD=off" \
    "$LAUNCHER" run team002 --resume session-cwd-off >/dev/null 2>"$ERR_LOG" )
launch_status=$?
set -e
grep -q -- '--dir' "$LANE_START_LOG" \
    && fail "cwd rung opt-out: it fired anyway ($(lane_start_argv))"; assertion

# 4j. THE ORDER. The operator's word beats every derived answer, and the record
# beats `lane-dir`. Set all three at once and exactly one may reach lane-start.
launch "FAKE_TMUX_WINDOW=zsh" "FAKE_LANE_WITH_ROW=nothing" \
    "FAKE_TMUX_WINDOW_ID=@97" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=mine-5\t2026-09-13T03:31:33Z\tclaude-y:0 @97\t$RECORD_TREE\n" \
    "FAKE_LANE_DIR=$LANE_TREE" \
    -- --dir "$TEST_ROOT/trees" run team002 --resume session-dirorder
grep -Fxq -- "--dir $TEST_ROOT/trees mine-5 -- $claude_args --resume session-dirorder" "$LANE_START_LOG" \
    || fail "dir order: the flag did not win ('$(lane_start_argv)')"; assertion

launch "FAKE_TMUX_WINDOW=zsh" "FAKE_LANE_WITH_ROW=nothing" \
    "FAKE_TMUX_WINDOW_ID=@97" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=mine-5\t2026-09-13T03:31:33Z\tclaude-y:0 @97\t$RECORD_TREE\n" \
    "FAKE_LANE_DIR=$LANE_TREE" \
    -- run team002 --resume session-dirorder2
grep -Fxq -- "--dir $RECORD_TREE mine-5 -- $claude_args --resume session-dirorder2" "$LANE_START_LOG" \
    || fail "dir order: the record did not beat lane-dir ('$(lane_start_argv)')"; assertion
grep -Fq 'argv=lane-dir' "$LANES_EDIT_LOG" \
    && fail "dir order: lane-dir was read although the record had already answered"; assertion

# ===========================================================================
# 5. NOTHING CAN CLOSE THE WINDOW — R-A8-3 widened, Evidence 2.
# ===========================================================================

# 5a. EVIDENCE 2 ITSELF. `--lane <lane>` and a lane-start that exits 1 on "no
# such directory". Before Amendment 11 this path was `exec`ed, so the refusal
# killed the only command of the tmux session the launcher had just made and
# tmux printed `[exited]`. Now lane-start is RUN: the window keeps a Claude,
# with one line saying so, and the launcher exits 0.
launch "FAKE_TMUX_WINDOW=claude" "FAKE_LANE_WITH_ROW=nothing" "FAKE_SWAPPED_STATUS=8" \
    "FAKE_LANE_START_STATUS=1" \
    -- --lane openXfactory-5 run team002 --resume session-evidence2
grep -Fxq -- "openXfactory-5 -- $claude_args --resume session-evidence2" "$LANE_START_LOG" \
    || fail "evidence 2: lane-start argv was '$(lane_start_argv)'"; assertion
grep -Fxq -- "$claude_args --resume session-evidence2" "$CLAUDE_LOG" \
    || fail "evidence 2: the window was left with no Claude in it ($(cat "$CLAUDE_LOG" 2>/dev/null))"; assertion
[[ "$launch_status" -eq 0 ]] \
    || fail "evidence 2: the launcher exited $launch_status over a Claude that started"; assertion
grep -q 'did not take openXfactory-5 (exit 1)' "$ERR_LOG" \
    || fail "evidence 2: the notice was '$(cat "$ERR_LOG")'"; assertion
[[ "$(wc -l < "$ERR_LOG")" -eq 2 ]] \
    || fail "evidence 2: one situation printed $(wc -l < "$ERR_LOG") lines beside lane-start's own ($(cat "$ERR_LOG"))"; assertion

# 5b. The same on the RECORD path, which is the restart Evidence 1 describes.
launch "FAKE_TMUX_WINDOW=zsh" "FAKE_LANE_WITH_ROW=nothing" \
    "FAKE_TMUX_WINDOW_ID=@97" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=mine-5\t2026-09-13T03:31:33Z\tclaude-y:0 @97\n" \
    "FAKE_LANE_START_STATUS=2" \
    -- run team002 --resume session-refused-record
grep -Fxq -- "$claude_args --resume session-refused-record" "$CLAUDE_LOG" \
    || fail "refused on the record path: no Claude ($(cat "$CLAUDE_LOG" 2>/dev/null))"; assertion
[[ "$launch_status" -eq 0 ]] || fail "refused on the record path: exited $launch_status"; assertion

# 5c. MUTATION — A CLAUDE THAT EXITED 1 IS NOT A REFUSAL. lane-start TOOK the
# lane (it renamed the window) and the Claude it exec'd returned 1 on its own.
# The status is handed back and no second Claude is started: two Claudes behind
# one another in a lane's window is worse than the dead end this all fixes.
WINDOW_FILE="$TEST_ROOT/tmux-window.name"
printf 'zsh\n' > "$WINDOW_FILE"
launch "FAKE_TMUX_WINDOW_FILE=$WINDOW_FILE" "FAKE_LANE_WITH_ROW=nothing" \
    "FAKE_TMUX_WINDOW_ID=@97" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=mine-5\t2026-09-13T03:31:33Z\tclaude-y:0 @97\n" \
    "FAKE_LANE_START_DECLINE=took" "FAKE_LANE_START_STATUS=1" \
    -- run team002 --resume session-claude-exited-1
[[ "$(wc -l < "$CLAUDE_LOG")" -eq 1 ]] \
    || fail "Claude exited 1: Claude ran $(wc -l < "$CLAUDE_LOG") times ($(cat "$CLAUDE_LOG"))"; assertion
[[ "$launch_status" -eq 1 ]] \
    || fail "Claude exited 1: the launcher exited $launch_status instead of handing back 1"; assertion
grep -q 'did not take' "$ERR_LOG" \
    && fail "Claude exited 1: a taken lane was reported as a refusal ($(cat "$ERR_LOG"))"; assertion

# 5d. MUTATION — A STATUS THAT IS NEITHER 1 NOR 2 IS CERTAINLY CLAUDE'S.
# lane-start documents exactly two refusals; anything else came from a Claude
# it exec'd, and is handed back whatever the window says.
launch "FAKE_TMUX_WINDOW=claude" "FAKE_LANE_WITH_ROW=nothing" "FAKE_SWAPPED_STATUS=8" \
    "FAKE_LANE_START_STATUS=130" \
    -- --lane openXfactory-5 run team002 --resume session-sigint
[[ "$launch_status" -eq 130 ]] \
    || fail "status 130: the launcher exited $launch_status instead of handing back 130"; assertion
[[ ! -e "$CLAUDE_LOG" ]] \
    || fail "status 130: a second Claude was started behind the first ($(cat "$CLAUDE_LOG"))"; assertion

# 5e. MUTATION — 0 IS NEVER A REFUSAL. A lane-start carrying the brett-wip half
# of Amendment 8 answers a declined `--confirm` by launching Claude BARE itself
# and exiting 0. A launcher that read the window instead of the status would
# start a second Claude behind that one.
launch "FAKE_TMUX_WINDOW=claude" "FAKE_LANE_WITH_ROW=nothing" "FAKE_SWAPPED_STATUS=8" \
    "FAKE_LANE_START_STATUS=0" \
    -- --lane openXfactory-5 run team002 --resume session-zero
[[ "$launch_status" -eq 0 ]] || fail "status 0: the launcher exited $launch_status"; assertion
[[ ! -e "$CLAUDE_LOG" ]] \
    || fail "status 0: the launcher started a Claude behind a lane-start that had finished ($(cat "$CLAUDE_LOG"))"; assertion

# 5f. And the lane identity is NOT published to a session that did not get the
# lane: the guard's automatic swap would otherwise write a PAUSED record for a
# lane this window never took.
launch "FAKE_TMUX_WINDOW=claude" "FAKE_LANE_WITH_ROW=nothing" "FAKE_SWAPPED_STATUS=8" \
    "FAKE_LANE_START_STATUS=1" \
    -- --lane openXfactory-5 run team002 --print env-check
grep -Fxq -- "$claude_args --print env-check" "$CLAUDE_LOG" \
    || fail "identity after a refusal: Claude did not start"; assertion

[[ "$scenarios" -eq "$EXPECTED_SCENARIOS" ]] \
    || fail "$scenarios scenarios ran, $EXPECTED_SCENARIOS expected — one was added or lost without saying so"
echo "claude-profile Amendment 11: $scenarios scenarios, $assertions assertions passed"
