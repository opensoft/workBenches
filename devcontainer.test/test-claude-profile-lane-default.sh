#!/usr/bin/env bash
# Regression tests for claude-profile's LANE DEFAULT — lane-collision-protocol
# Amendment 8(c). `--lane` used to be opt-in; a `run` that starts a
# conversation now resolves the lane itself, in this order:
#
#   1. --lane / CLAUDE_LANE            -> handed to lane-start as --yes
#   2. the current tmux window's name, when `lanes-edit.sh register-row`
#      answers 0 for it                -> handed to lane-start as --yes
#   3. `lanes-edit.sh swapped <ws>`, first row
#                                      -> handed to lane-start as --confirm
#   4. nothing                         -> today's behaviour, plus one line
#
# and never refuses: a lanes-edit.sh with no `swapped` subcommand (exit 2), a
# lane-start with no `--confirm`, a missing lanes-edit.sh and `--no-lane` all
# fall back to 4. Everything the launcher shells out to is faked here — tmux,
# lanes-edit.sh, lane-start and claude — so the assertions are about the
# launcher's own resolution and nothing else.

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

PROFILE_BASE="$TEST_ROOT/profiles-home"
PROFILE_DIR="$PROFILE_BASE/profiles/opensoft/team/team-002"
MANIFEST="$TEST_ROOT/claude-profiles.json"
FAKE_BIN="$TEST_ROOT/bin"
FAKE_CLAUDE="$FAKE_BIN/claude"
CLAUDE_LOG="$TEST_ROOT/claude.log"
TMUX_LOG="$TEST_ROOT/tmux.log"
LANE_START_LOG="$TEST_ROOT/lane-start.log"
LANES_EDIT_LOG="$TEST_ROOT/lanes-edit.log"
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
cat > "$FAKE_BIN/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${FAKE_TMUX_LOG:?}"
if [[ "${1:-}" == display-message ]]; then
    case "${3:-}" in
        '#W') printf '%s\n' "${FAKE_TMUX_WINDOW:-claude}" ;;
        *) printf 'fake\n' ;;
    esac
fi
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
EOF

chmod +x "$FAKE_CLAUDE" "$FAKE_BIN/tmux" "$FAKE_BIN/lanes-edit.sh" "$FAKE_BIN/lane-start"

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
    "FAKE_LANE_START_HELP=$AMENDMENT_8_HELP"
    "WORKBENCHES_SHARED_MCP_FAMILIES=disabled"
    "LANES_WORKSTATION=Eagle"
    "TMUX=fake-session"
)

claude_args='--allow-dangerously-skip-permissions --dangerously-skip-permissions --permission-mode bypassPermissions'
note='no lane for this window; run lane-start <repo> <n> inside it'

reset_logs() {
    rm -f "$CLAUDE_LOG" "$TMUX_LOG" "$LANE_START_LOG" "$LANES_EDIT_LOG" "$ERR_LOG"
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
    env "${common_env[@]}" "${scenario_env[@]}" "$LAUNCHER" "$@" \
        >/dev/null 2>"$ERR_LOG"
}

lane_start_argv() { cat "$LANE_START_LOG" 2>/dev/null || true; }

# ---------------------------------------------------------------------------
# 0. --help documents the default and the way out of it.
env "${common_env[@]}" "$LAUNCHER" --help > "$TEST_ROOT/help.out"
grep -q -- '--no-lane' "$TEST_ROOT/help.out" || fail "--help does not document --no-lane"
grep -q 'CLAUDE_NO_LANE' "$TEST_ROOT/help.out" || fail "--help does not document CLAUDE_NO_LANE"
grep -q 'THE LANE DEFAULT' "$TEST_ROOT/help.out" || fail "--help does not document the lane default"
grep -q -- '--lane' "$TEST_ROOT/help.out" || fail "--help no longer documents --lane"
grep -q 'CLAUDE_LANE' "$TEST_ROOT/help.out" || fail "--help no longer documents CLAUDE_LANE"

# ---------------------------------------------------------------------------
# 1. The window's own name, when the register has a row for it: the lane, and
# --yes — the operator is standing in the lane's window, there is nothing to
# ask. The record is not even read.
launch \
    "FAKE_TMUX_WINDOW=openRepoProject-1" \
    "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=someOtherLane-9\t2026-09-12T17:04Z\tclaude-x:0\n" \
    -- run team002 --resume session-w
[[ -e "$LANE_START_LOG" ]] || fail "window lane: lane-start was never invoked"
grep -Fxq -- "--yes openRepoProject-1 -- $claude_args --resume session-w" "$LANE_START_LOG" \
    || fail "window lane: lane-start argv was '$(lane_start_argv)'"
[[ ! -e "$CLAUDE_LOG" ]] || fail "window lane: Claude was exec'd directly"
grep -Fq 'argv=register-row openRepoProject-1' "$LANES_EDIT_LOG" \
    || fail "window lane: register-row was not asked about the window name"
grep -Fq 'argv=swapped' "$LANES_EDIT_LOG" \
    && fail "window lane: the swap record was read even though the window answered"
grep -Fxq 'LANES_NO_FETCH=1' "$LANES_EDIT_LOG" \
    || fail "window lane: the register read was not made with LANES_NO_FETCH=1"
grep -q "$note" "$ERR_LOG" && fail "window lane: printed the no-lane note anyway"

# ---------------------------------------------------------------------------
# 2. Window is not a lane, the record has one: the record's FIRST row, and
# --confirm — nothing has named this window, so lane-start asks before it does.
launch \
    "FAKE_TMUX_WINDOW=claude" \
    "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=openRepoProject-1\t2026-09-12T17:04Z\tclaude-a:0\nxFactory-2\t2026-09-12T15:00Z\tclaude-b:1\n" \
    -- run team002 --resume session-r
grep -Fxq -- "--confirm openRepoProject-1 -- $claude_args --resume session-r" "$LANE_START_LOG" \
    || fail "record lane: lane-start argv was '$(lane_start_argv)'"
grep -Fq 'xFactory-2' "$LANE_START_LOG" \
    && fail "record lane: a row other than the first was taken"
[[ ! -e "$CLAUDE_LOG" ]] || fail "record lane: Claude was exec'd directly"
grep -Fq 'argv=swapped Eagle' "$LANES_EDIT_LOG" \
    || fail "record lane: swapped was not asked about this workstation ($(cat "$LANES_EDIT_LOG"))"

# 2b. The record's rows are `<lane>\t<UTC>\t<window>`. A row that does not
# separate them with a tab is not a row this launcher can read a lane out of,
# and it hands lane-start nothing rather than a whole line.
launch \
    "FAKE_TMUX_WINDOW=claude" \
    "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=openRepoProject-1 2026-09-12T17:04Z claude-a:0\n" \
    -- run team002 --resume session-untabbed
[[ ! -e "$LANE_START_LOG" ]] \
    || fail "untabbed record row: lane-start was handed '$(lane_start_argv)'"
grep -Fxq -- "$claude_args --resume session-untabbed" "$CLAUDE_LOG" \
    || fail "untabbed record row: Claude did not receive its arguments unchanged"
grep -q "$note" "$ERR_LOG" || fail "untabbed record row: the note was not printed"

# ---------------------------------------------------------------------------
# 3. No window lane and no swapped lane: today's behaviour, and one line.
launch \
    "FAKE_TMUX_WINDOW=claude" \
    "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    "FAKE_SWAPPED_STATUS=8" \
    -- run team002 --resume session-n
[[ ! -e "$LANE_START_LOG" ]] || fail "no lane: lane-start was invoked ('$(lane_start_argv)')"
grep -Fxq -- "$claude_args --resume session-n" "$CLAUDE_LOG" \
    || fail "no lane: Claude did not receive its arguments unchanged ($(cat "$CLAUDE_LOG" 2>/dev/null))"
grep -q "$note" "$ERR_LOG" || fail "no lane: the note was not printed ($(cat "$ERR_LOG"))"

# ---------------------------------------------------------------------------
# 4. A lanes-edit.sh from before Amendment 8 answers 2 to `swapped`. The
# launcher degrades to today's behaviour rather than reading that as a lane.
launch \
    "FAKE_TMUX_WINDOW=claude" \
    "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    "FAKE_SWAPPED_STATUS=2" \
    -- run team002 --resume session-old
[[ ! -e "$LANE_START_LOG" ]] || fail "no swapped subcommand: lane-start was invoked ('$(lane_start_argv)')"
grep -Fxq -- "$claude_args --resume session-old" "$CLAUDE_LOG" \
    || fail "no swapped subcommand: Claude did not receive its arguments unchanged"
grep -q "$note" "$ERR_LOG" || fail "no swapped subcommand: the note was not printed"

# 4b. And a `swapped` that fails HALFWAY, after printing a row a launcher could
# otherwise read as a lane: output from a read that did not succeed is not a
# lane either.
launch \
    "FAKE_TMUX_WINDOW=claude" \
    "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    "FAKE_SWAPPED_STATUS=2" \
    "FAKE_SWAPPED_ROWS_ANYWAY=1" \
    "FAKE_SWAPPED_ROWS=openRepoProject-1\t2026-09-12T17:04Z\tclaude-a:0\n" \
    -- run team002 --resume session-halfread
[[ ! -e "$LANE_START_LOG" ]] \
    || fail "failed swapped read: its output was taken as a lane ('$(lane_start_argv)')"
grep -Fxq -- "$claude_args --resume session-halfread" "$CLAUDE_LOG" \
    || fail "failed swapped read: Claude did not receive its arguments unchanged"
grep -q "$note" "$ERR_LOG" || fail "failed swapped read: the note was not printed"

# ---------------------------------------------------------------------------
# 5. A window name that is not even lane-shaped: register-row answers 2, not 8,
# and only 0 is a lane.
launch \
    "FAKE_TMUX_WINDOW=1:zsh*" \
    "FAKE_REGISTER_ROW_OTHER=2" \
    "FAKE_SWAPPED_STATUS=8" \
    -- run team002 --resume session-badname
[[ ! -e "$LANE_START_LOG" ]] || fail "unshaped window name: lane-start was invoked ('$(lane_start_argv)')"
grep -Fq 'argv=register-row 1:zsh*' "$LANES_EDIT_LOG" \
    || fail "unshaped window name: register-row was not asked ($(cat "$LANES_EDIT_LOG"))"
grep -q "$note" "$ERR_LOG" || fail "unshaped window name: the note was not printed"

# ---------------------------------------------------------------------------
# 6. An explicit --lane beats both, and is not confirmed: it is what the
# operator said. The register is not read at all.
launch \
    "FAKE_TMUX_WINDOW=openRepoProject-1" \
    "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=someOtherLane-9\t2026-09-12T17:04Z\tclaude-x:0\n" \
    -- --lane spoken-3 run team002 --resume session-f
grep -Fxq -- "--yes spoken-3 -- $claude_args --resume session-f" "$LANE_START_LOG" \
    || fail "--lane: lane-start argv was '$(lane_start_argv)'"
[[ ! -e "$LANES_EDIT_LOG" ]] \
    || fail "--lane: the register was read for a lane the operator named ($(cat "$LANES_EDIT_LOG"))"

# CLAUDE_LANE is the same thing by another route.
launch \
    "FAKE_TMUX_WINDOW=openRepoProject-1" \
    "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    "CLAUDE_LANE=spoken-4" \
    -- run team002 --resume session-fe
grep -Fxq -- "--yes spoken-4 -- $claude_args --resume session-fe" "$LANE_START_LOG" \
    || fail "CLAUDE_LANE: lane-start argv was '$(lane_start_argv)'"

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
[[ ! -e "$LANE_START_LOG" ]] || fail "--no-lane: lane-start was invoked ('$(lane_start_argv)')"
[[ ! -e "$LANES_EDIT_LOG" ]] || fail "--no-lane: the register was read anyway"
grep -Fxq -- "$claude_args --resume session-none" "$CLAUDE_LOG" \
    || fail "--no-lane: Claude did not receive its arguments unchanged"
grep -q "$note" "$ERR_LOG" && fail "--no-lane: printed the no-lane note at an operator who opted out"

# CLAUDE_NO_LANE=1 is the same thing by another route.
launch \
    "FAKE_TMUX_WINDOW=openRepoProject-1" \
    "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    "CLAUDE_NO_LANE=1" \
    -- run team002 --resume session-none-env
[[ ! -e "$LANE_START_LOG" ]] || fail "CLAUDE_NO_LANE: lane-start was invoked ('$(lane_start_argv)')"

# ---------------------------------------------------------------------------
# 8. A lane-start from before Amendment 8, which knows neither flag. The
# window's lane still goes to it, bare — that is today's behaviour. The
# record's guess does not: a lane-start that cannot ask must not be handed a
# window to take on a guess.
launch \
    "FAKE_TMUX_WINDOW=openRepoProject-1" \
    "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    "FAKE_LANE_START_HELP=$OLD_HELP" \
    "FAKE_SWAPPED_STATUS=8" \
    -- run team002 --resume session-oldls
grep -Fxq -- "openRepoProject-1 -- $claude_args --resume session-oldls" "$LANE_START_LOG" \
    || fail "old lane-start, window lane: lane-start argv was '$(lane_start_argv)'"

launch \
    "FAKE_TMUX_WINDOW=claude" \
    "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    "FAKE_LANE_START_HELP=$OLD_HELP" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=openRepoProject-1\t2026-09-12T17:04Z\tclaude-a:0\n" \
    -- run team002 --resume session-oldls-record
[[ ! -e "$LANE_START_LOG" ]] \
    || fail "old lane-start, record lane: it was handed a guess it cannot ask about ('$(lane_start_argv)')"
grep -Fxq -- "$claude_args --resume session-oldls-record" "$CLAUDE_LOG" \
    || fail "old lane-start, record lane: Claude did not receive its arguments unchanged"
grep -q -- '--confirm' "$ERR_LOG" || fail "old lane-start, record lane: the reason was not named ($(cat "$ERR_LOG"))"
grep -q "$note" "$ERR_LOG" || fail "old lane-start, record lane: the note was not printed"

# ---------------------------------------------------------------------------
# 9. No lanes-edit.sh to read: nothing can be resolved, and the launcher says
# so once rather than refusing.
launch \
    "FAKE_TMUX_WINDOW=openRepoProject-1" \
    "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    "WORKBENCHES_LANES_EDIT_BIN=$TEST_ROOT/nowhere/lanes-edit.sh" \
    -- run team002 --resume session-nolanesedit
[[ ! -e "$LANE_START_LOG" ]] || fail "no lanes-edit.sh: lane-start was invoked ('$(lane_start_argv)')"
[[ ! -e "$LANES_EDIT_LOG" ]] || fail "no lanes-edit.sh: something answered for it"
grep -Fxq -- "$claude_args --resume session-nolanesedit" "$CLAUDE_LOG" \
    || fail "no lanes-edit.sh: Claude did not receive its arguments unchanged"
grep -q "$note" "$ERR_LOG" || fail "no lanes-edit.sh: the note was not printed"

# A machine with no lane estate at all (no lane-start on PATH) is silent: the
# feature is absent there, and a note on every launch would be noise.
NO_ESTATE_BIN="$TEST_ROOT/bin-no-estate"
mkdir -p "$NO_ESTATE_BIN"
cp "$FAKE_CLAUDE" "$NO_ESTATE_BIN/claude"
cp "$FAKE_BIN/tmux" "$NO_ESTATE_BIN/tmux"
reset_logs
env "${common_env[@]}" "PATH=$NO_ESTATE_BIN:/usr/bin:/bin" "FAKE_TMUX_WINDOW=openRepoProject-1" \
    "$LAUNCHER" run team002 --resume session-noestate >/dev/null 2>"$ERR_LOG"
grep -Fxq -- "$claude_args --resume session-noestate" "$CLAUDE_LOG" \
    || fail "no lane estate: Claude did not receive its arguments unchanged"
[[ ! -s "$ERR_LOG" ]] || fail "no lane estate: the launcher said something ($(cat "$ERR_LOG"))"

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
[[ ! -e "$LANE_START_LOG" ]] || fail "--version: it was handed to lane-start ('$(lane_start_argv)')"
[[ ! -e "$LANES_EDIT_LOG" ]] || fail "--version: the register was read for a launch that is no conversation"
grep -Fxq -- "$claude_args --version" "$CLAUDE_LOG" \
    || fail "--version: Claude did not receive its arguments unchanged ($(cat "$CLAUDE_LOG" 2>/dev/null))"
grep -q "$note" "$ERR_LOG" && fail "--version: the no-lane note was printed at a launch that wanted no lane"

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
grep -Fxq -- "--yes openRepoProject-1 -- $claude_args --resume session-child" "$LANE_START_LOG" \
    || fail "tmux child: the carried window name was not the lane ('$(lane_start_argv)')"
grep -Fxq 'display-message -p #W' "$TMUX_LOG" \
    && fail "tmux child: the launcher asked tmux for the new session's window name"

# With nothing carried across, a child resolves no window lane at all — even
# when the new session's window happens to be named like one.
launch \
    "WORKBENCHES_CLAUDE_TMUX_CHILD=1" \
    "FAKE_TMUX_WINDOW=openRepoProject-1" \
    "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    "FAKE_SWAPPED_STATUS=8" \
    -- run team002 --resume session-child-bare
[[ ! -e "$LANE_START_LOG" ]] \
    || fail "tmux child: a lane was taken from the new session's own window ('$(lane_start_argv)')"
grep -Fq 'argv=register-row' "$LANES_EDIT_LOG" \
    && fail "tmux child: the new session's window name was looked up in the register"

# The parent side: a launch that re-execs into a new tmux session threads the
# lane and the opt-out to the child. It carries no window name, because the
# re-exec happens only when the launch did NOT come from a tmux window at all
# (claude_run_is_interactive requires an empty TMUX) — there is nothing to
# carry, and the child must not invent one.
tty_launch() {
    local -a scenario_env=("$@")
    reset_logs
    local tty_command value
    printf -v tty_command 'env'
    for value in "${common_env[@]}" "${scenario_env[@]}" "$LAUNCHER" run team002 --resume session-tty; do
        printf -v value '%q' "$value"
        tty_command+=" $value"
    done
    script -qefc "$tty_command" "$TEST_ROOT/typescript.log" >/dev/null
}
tty_launch "TMUX=" "FAKE_TMUX_WINDOW=openRepoProject-1" "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    "CLAUDE_LANE=carried-1"
grep -q 'new-session' "$TMUX_LOG" || fail "re-exec: no tmux session was created ($(cat "$TMUX_LOG" 2>/dev/null))"
grep -q 'CLAUDE_LANE=carried-1' "$TMUX_LOG" || fail "re-exec: the lane was not carried into the new session"
grep -q 'WORKBENCHES_CLAUDE_WINDOW=' "$TMUX_LOG" \
    && fail "re-exec: a window name was carried from a launch that came from no window"

tty_launch "TMUX=" "FAKE_TMUX_WINDOW=openRepoProject-1" "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    "CLAUDE_NO_LANE=1"
grep -q 'CLAUDE_NO_LANE=1' "$TMUX_LOG" || fail "re-exec: --no-lane was not carried into the new session"

echo "claude-profile lane default tests passed"
