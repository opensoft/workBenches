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
    LANES_WORKSTATION PROJECTS_ROOT \
    2>/dev/null || true

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

# THE CWD IS PART OF THE STATE UNDER TEST, so this suite pins it — and keeps
# pinning it now that Amendment 11's directory order has no cwd rung at all.
# An earlier pass of this launcher had one, and a suite run from
# `~/projects/openRepoProject` inferred a directory nobody asked for, handing
# lane-start `--dir /home/brett/projects/...` in scenarios that are not about
# directories: three mutations came back green for the wrong reason. 4f and
# 4f-i now assert the rung's ABSENCE from the cwd it used to fire in, which
# only means anything if the suite's own cwd is pinned. Every scenario below
# either stands in $TEST_ROOT, which is nobody's checkout, or `cd`s into a tree
# it made itself. GIT_CEILING_DIRECTORIES stops `rev-parse --show-toplevel`
# walking out of $TEST_ROOT on a machine whose temp directory sits inside a
# repository.
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
EXPECTED_SCENARIOS=75
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
LANE_START_CWD_LOG="$TEST_ROOT/lane-start-cwd.log"
CLAUDE_CWD_LOG="$TEST_ROOT/claude-cwd.log"
LANES_EDIT_LOG="$TEST_ROOT/lanes-edit.log"
ERR_LOG="$TEST_ROOT/stderr.log"
OUT_LOG="$TEST_ROOT/stdout.log"
FAKE_HOME="$TEST_ROOT/home"
mkdir -p "$PROFILE_DIR" "$RUN_PROFILE_DIR" "$FAKE_BIN" "$FAKE_HOME" "$TEST_ROOT/empty-bin"

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
# WHERE Claude ran, in a log of its own (Evidence 3). Its own argv log is
# compared whole and counted by line elsewhere, so this cannot go in it.
printf '%s\n' "$PWD" >> "${FAKE_CLAUDE_CWD_LOG:-/dev/null}"
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
        # TWO FORMS, and act 1 is why there are two. `-p <fmt>` asks about the
        # window this process is standing in, which is what capture_lane_window
        # reads. `-p -t <ref> <fmt>` asks about a window by ADDRESS, which is
        # act 1's liveness fence: a record whose window is gone must resolve
        # NOTHING, because a `<session>:<index>` is reused the instant a window
        # closes and matching a dead ref is how a lane binds to a stranger's
        # pane. FAKE_TMUX_WINDOWS lists the live windows, one per line, as
        # `<@id>|<session>:<index>|<%pane>|<name>`; UNSET IS THE ESTATE AS
        # MEASURED on 2026-09-13, where 0 of 5 swap records name a window that
        # still exists, so every `-t` probe fails and act 1 falls to step 3.
        if [[ "${2:-}" == -p && "${3:-}" == -t ]]; then
            target="${4:-}"
            while IFS= read -r live; do
                [[ -n "$live" ]] || continue
                if [[ "${live%%|*}" == "$target" \
                    || "$(printf '%s' "$live" | cut -d '|' -f 2)" == "$target" ]]; then
                    printf '%s\n' "$live"
                    exit 0
                fi
            done <<< "${FAKE_TMUX_WINDOWS:-}"
            echo "can't find window: $target" >&2
            exit 1
        fi
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
    respawn-pane)
        # MEASURED ON A PRIVATE SOCKET (SPEC §0.9): `respawn-pane` on a LIVE
        # pane exits 1 with "still active"; `respawn-pane -k` on the same pane
        # exits 0 and leaves the window's name and its automatic-rename off
        # intact. A live pane is the ORDINARY state right after a swap, because
        # /lane-swap kills nothing, so live is this fake's default.
        # A tmux predating 2.6 has no `-c` on respawn-pane and refuses the
        # OPTION rather than the pane, which is a different failure from "the
        # pane is in use" and has a different right answer: retry without it.
        if [[ -n "${FAKE_TMUX_NO_RESPAWN_C:-}" ]]; then
            for argument in "$@"; do
                [[ "$argument" == -c ]] || continue
                echo "unknown option -- c" >&2
                exit 1
            done
        fi
        if [[ "${2:-}" == -k ]]; then
            exit 0
        fi
        [[ "${FAKE_TMUX_PANE_LIVE:-1}" == 1 ]] || exit 0
        echo "respawn pane failed: pane ${3:-} still active" >&2
        exit 1
        ;;
    rename-window)
        [[ -z "${FAKE_TMUX_WINDOW_FILE:-}" ]] || printf '%s\n' "${2:-}" > "$FAKE_TMUX_WINDOW_FILE"
        ;;
    select-window) exit 0 ;;
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
    window-lane)
        # SPEC §11: "the register row whose name is the window's name, else the
        # swap record whose `window` names that id or that `session:index`".
        # FAKE_WINDOW_LANE_MAP is `<ref>=<lane>` per line — the answer the
        # helper gives, never a shape this launcher is allowed to derive for
        # itself. FAKE_WINDOW_LANE_NONE=1 is the helper answering 8 (no lane for
        # this window), FAKE_WINDOW_LANE_STATUS is any other code, and NEITHER
        # set is TODAY'S ESTATE: a helper predating Amendment 11 falls through
        # to the unknown-subcommand line and 2, exactly as a pre-Amendment-8 one
        # did for `swapped`.
        [[ -z "${FAKE_WINDOW_LANE_STATUS:-}" ]] || exit "$FAKE_WINDOW_LANE_STATUS"
        if [[ -n "${FAKE_WINDOW_LANE_MAP:-}" ]]; then
            while IFS= read -r pair; do
                [[ -n "$pair" ]] || continue
                if [[ "${pair%%=*}" == "${2:-}" ]]; then
                    printf '%s\n' "${pair#*=}"
                    exit 0
                fi
            done <<< "$FAKE_WINDOW_LANE_MAP"
            exit 8
        fi
        [[ -z "${FAKE_WINDOW_LANE_NONE:-}" ]] || exit 8
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
# ...and WHERE lane-start was run from, which is the directory the Claude it
# execs inherits and the harness keys the session to (Evidence 3). Logged after
# the --help early exit above, so a capability probe never creates either file.
printf '%s\n' "$PWD" >> "${FAKE_LANE_START_CWD_LOG:-/dev/null}"
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
    "FAKE_LANE_START_CWD_LOG=$LANE_START_CWD_LOG"
    "FAKE_CLAUDE_CWD_LOG=$CLAUDE_CWD_LOG"
    "FAKE_LANES_EDIT_LOG=$LANES_EDIT_LOG"
    "FAKE_LANE_START_HELP=$AMENDMENT_11_HELP"
    "WORKBENCHES_SHARED_MCP_FAMILIES=disabled"
    "LANES_WORKSTATION=Eagle"
    "TMUX=fake-session"
    # lane-start's own default, pointed at a tree of this suite's own: rung 4
    # is "pass no --dir and let lane-start derive it", so nothing here may
    # depend on a real `$HOME/projects`, and 4f's assertion that no fifth rung
    # exists is made with the retired rung's first fence wide open.
    "PROJECTS_ROOT=$TEST_ROOT/projects"
    "GIT_CEILING_DIRECTORIES=$TEST_ROOT"
)

claude_args='--allow-dangerously-skip-permissions --dangerously-skip-permissions --permission-mode bypassPermissions'
note='no lane for this window; run lane-start <repo> <n> inside it'

reset_logs() {
    rm -f "$CLAUDE_LOG" "$TMUX_LOG" "$LANE_START_LOG" "$LANES_EDIT_LOG" "$ERR_LOG" "$OUT_LOG" \
        "$LANE_START_CWD_LOG" "$CLAUDE_CWD_LOG"
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

# ---------------------------------------------------------------------------
# ACT 1 STEPS 1 AND 2 — resolve the lane BEFORE the session is created, and
# REUSE THE RECORDED WINDOW where it still exists (SPEC §3, `R-A11-3`/F3+F4).
# These five are what SPEC §13.2 owed this PR, and the row of §3's own table
# they move is `pclaude <profile>`, fresh terminal outside tmux: 1 question
# today, 0 once a record names a window that is still there.

# 2g. STEP 2 — THE RECORDED WINDOW IS REUSED AND NO SESSION IS CREATED. The
# lane is certain (`--lane`), its record names `claude-y:0 @97`, that window
# still exists, and it CARRIES THE LANE'S OWN NAME — which is lane-start's own
# word that the window is this lane's (A5(f)), and therefore that the pane's
# process is the session this restart replaces. That is the text's condition
# for `-k`, and the ordinary state right after a swap.
tty_launch "TMUX=" "FAKE_TMUX_WINDOW=claude" "FAKE_LANE_WITH_ROW=nothing" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=mine-5\t2026-09-13T03:31:33Z\tclaude-y:0 @97\n" \
    "FAKE_TMUX_WINDOWS=@97|claude-y:0|%12|mine-5" \
    -- --lane mine-5 run team002 --resume session-reuse
grep -q 'new-session' "$TMUX_LOG" \
    && fail "act 1 step 2: a session was created although the recorded window still exists ($(cat "$TMUX_LOG"))"; assertion
grep -q 'respawn-pane -k -t %12' "$TMUX_LOG" \
    || fail "act 1 step 2: the recorded window's pane was not respawned ($(cat "$TMUX_LOG"))"; assertion
grep -q 'attach-session -t claude-y' "$TMUX_LOG" \
    || fail "act 1 step 2: it did not attach to the reused window's session ($(cat "$TMUX_LOG"))"; assertion
grep -q 'WORKBENCHES_CLAUDE_WINDOW=mine-5' "$TMUX_LOG" \
    || fail "act 1 step 2: the REUSED window's name was not threaded to the child ($(cat "$TMUX_LOG"))"; assertion
grep -q 'WORKBENCHES_CLAUDE_WINDOW_ID=@97' "$TMUX_LOG" \
    || fail "act 1 step 2: the reused window's id was not threaded to the child ($(cat "$TMUX_LOG"))"; assertion

# 2h. MUTATION — `-k` ONLY WHERE THE PANE IS THE LANE'S OWN. The same record,
# the same live window, but the window is called `zsh`: the register does not
# know that name, so nothing here can prove the pane is the session this
# restart replaces. Never `-k` then. A plain `respawn-pane` on a live pane
# exits 1 — "still active", measured — which is not an error to report but the
# launcher being told the window is in use, and step 3 makes a session.
tty_launch "TMUX=" "FAKE_TMUX_WINDOW=claude" "FAKE_LANE_WITH_ROW=nothing" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=mine-5\t2026-09-13T03:31:33Z\tclaude-y:0 @97\n" \
    "FAKE_TMUX_WINDOWS=@97|claude-y:0|%12|zsh" \
    -- --lane mine-5 run team002 --resume session-reuse-nokill
grep -q 'respawn-pane -k' "$TMUX_LOG" \
    && fail "act 1 step 2: a pane that is not provably the lane's own was KILLED ($(cat "$TMUX_LOG"))"; assertion
grep -q 'respawn-pane -t %12' "$TMUX_LOG" \
    || fail "act 1 step 2: the plain respawn was not attempted ($(cat "$TMUX_LOG"))"; assertion
grep -q 'new-session' "$TMUX_LOG" \
    || fail "act 1 step 2: a window in use did not fall to step 3 ($(cat "$TMUX_LOG"))"; assertion

# 2h-i. ...and a DEAD pane in that same window IS reused, without `-k`. This is
# the other half of the measurement: `respawn-pane` exits 0 where the pane's own
# process has ended, so the window is taken back without killing anything.
tty_launch "TMUX=" "FAKE_TMUX_WINDOW=claude" "FAKE_LANE_WITH_ROW=nothing" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=mine-5\t2026-09-13T03:31:33Z\tclaude-y:0 @97\n" \
    "FAKE_TMUX_WINDOWS=@97|claude-y:0|%12|zsh" "FAKE_TMUX_PANE_LIVE=0" \
    -- --lane mine-5 run team002 --resume session-reuse-dead
grep -q 'new-session' "$TMUX_LOG" \
    && fail "act 1 step 2: a dead pane's window was not reused ($(cat "$TMUX_LOG"))"; assertion
grep -q 'respawn-pane -k' "$TMUX_LOG" \
    && fail "act 1 step 2: a dead pane was killed, which is one act too many"; assertion

# 2i. MUTATION — A WINDOW THAT IS ANOTHER LANE'S IS NOT TAKEN AT ALL. The
# record still names `@97`, but that window has since been renamed for
# `otherlane-2` and the register has a row for it. Killing somebody else's pane
# to reuse its window is the one act Amendment 8(f) refuses by name, so there is
# no respawn here at all — not even a plain one.
tty_launch "TMUX=" "FAKE_TMUX_WINDOW=claude" "FAKE_LANE_WITH_ROW=otherlane-2" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=mine-5\t2026-09-13T03:31:33Z\tclaude-y:0 @97\n" \
    "FAKE_TMUX_WINDOWS=@97|claude-y:0|%12|otherlane-2" \
    -- --lane mine-5 run team002 --resume session-reuse-other
grep -q 'respawn-pane' "$TMUX_LOG" \
    && fail "act 1 step 2: another lane's window was respawned ($(cat "$TMUX_LOG"))"; assertion
grep -q 'new-session' "$TMUX_LOG" \
    || fail "act 1 step 2: it did not fall to step 3 ($(cat "$TMUX_LOG"))"; assertion

# 2j. TODAY'S ESTATE — A RECORD WHOSE WINDOW IS GONE IS NOT AN ANSWER. Measured
# on Eagle 2026-09-13: 0 of 5 swap records name a window that still exists, and
# not one carries an `<@id>`. So step 2 answers nothing until the cutover has
# run for the lane, and the launch is byte-for-byte today's.
tty_launch "TMUX=" "FAKE_TMUX_WINDOW=claude" "FAKE_LANE_WITH_ROW=nothing" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=mine-5\t2026-09-13T03:31:33Z\tclaude-y:0\n" \
    -- --lane mine-5 run team002 --resume session-reuse-gone
grep -q 'respawn-pane' "$TMUX_LOG" \
    && fail "act 1 step 2: a record naming a window that is GONE was matched ($(cat "$TMUX_LOG"))"; assertion
grep -q 'new-session' "$TMUX_LOG" \
    || fail "act 1 step 2: no session was created for a lane whose window is gone"; assertion

# 2k. STEP 1 — THE LANE IS RESOLVED BEFORE THE SESSION EXISTS, and precedence 3
# answers there. No `--lane` at all. The NEWEST record is `newest-9`, whose
# window is gone; the older one is `mine-5`, whose window still exists. Outside
# tmux precedence 3 has no `<@id>` of its own to compare, so it is tried on the
# RECORDS' own refs and takes the first whose window tmux resolves NOW — which
# is `mine-5`, not the newest row. A launcher that resolved in the child would
# have created a session first and never had the chance.
tty_launch "TMUX=" "FAKE_TMUX_WINDOW=claude" "FAKE_LANE_WITH_ROW=nothing" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=newest-9\t2026-09-13T03:31:56Z\tclaude-x:0 @12\nmine-5\t2026-09-13T03:31:33Z\tclaude-y:0 @97\n" \
    "FAKE_TMUX_WINDOWS=@97|claude-y:0|%12|mine-5" \
    -- run team002 --resume session-step1
grep -q 'new-session' "$TMUX_LOG" \
    && fail "act 1 step 1: a session was created although a record names a live window ($(cat "$TMUX_LOG"))"; assertion
grep -q 'respawn-pane -k -t %12' "$TMUX_LOG" \
    || fail "act 1 step 1: the newest row beat the record whose window still exists ($(cat "$TMUX_LOG"))"; assertion

# 2k-i. ...AND WHAT THE PARENT RESOLVED IS NEVER HANDED DOWN AS THE ANSWER. The
# lane found in the parent decides which window to reuse and nothing else: it is
# not exported as CLAUDE_LANE and not passed as `--lane`, so a lane that was an
# inference still reaches lane-start as `--confirm` in the child and is still
# asked about. Pre-answering that question in the parent is exactly what act 1
# step 3's fence exists to prevent, and it is no better done at step 2.
grep -q 'CLAUDE_LANE=' "$TMUX_LOG" \
    && fail "act 1 step 1: the parent's own resolution was handed to the child as the operator's word ($(cat "$TMUX_LOG"))"; assertion

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
# 3. THE RECORD FOR *THIS* WINDOW — precedence step 3, SPEC §2 row 3 and §11.
#
# READ THROUGH `lanes-edit.sh window-lane`, AND THAT IS THE CONTRACT POINT.
# The helper answers "the register row whose name is the window's name, else
# the swap record whose `window` names that id or that `session:index`" (SPEC
# §11), and it has THREE callers — this launcher, `/restart` step 2(b) and the
# `/lane-swap` skill's step 1. One rule, one implementation: a launcher that
# scanned `swapped` rows for itself would be a second implementation of the one
# rule that exists to stop the three disagreeing about which lane a window is.
# Every scenario below therefore asserts the READ as well as the answer.
# ===========================================================================

# 3a. The record whose `window` field names THIS window's `<@id>`. It is an
# exact match on the window the operator is standing in, so it is taken BARE —
# no `--confirm`, no question — even though the newest swap is another lane's.
launch "FAKE_TMUX_WINDOW=zsh" "FAKE_LANE_WITH_ROW=nothing" \
    "FAKE_TMUX_WINDOW_ID=@97" "FAKE_TMUX_WINDOW_REF=some-session:2" \
    "FAKE_WINDOW_LANE_MAP=@97=mine-5" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=newest-9\t2026-09-13T03:31:56Z\tclaude-x:0 @12\nmine-5\t2026-09-13T03:31:33Z\tclaude-y:0 @97\n" \
    -- run team002 --resume session-byid
grep -Fxq -- "mine-5 -- $claude_args --resume session-byid" "$LANE_START_LOG" \
    || fail "record by @id: lane-start argv was '$(lane_start_argv)'"; assertion
grep -q -- '--confirm' "$LANE_START_LOG" \
    && fail "record by @id: an EXACT match on this window was confirmed ($(lane_start_argv))"; assertion
grep -Fq 'newest-9' "$LANE_START_LOG" \
    && fail "record by @id: the newest row beat the row that names this window"; assertion
grep -Fxq 'argv=window-lane @97' "$LANES_EDIT_LOG" \
    || fail "record by @id: the helper's own read was not made ($(cat "$LANES_EDIT_LOG"))"; assertion

# 3a-i. MUTATION — THE READ IS THE HELPER'S, NEVER THE LAUNCHER'S OWN PARSE.
# `swapped` is holding a row that names this window, and the helper answers
# NOTHING. A launcher that still parsed the rows itself binds `mine-5` bare
# here; one that reads the rule through the helper falls to precedence 4 and is
# CONFIRMED. This is the assertion that fails if the old parse comes back.
launch "FAKE_TMUX_WINDOW=zsh" "FAKE_LANE_WITH_ROW=nothing" \
    "FAKE_TMUX_WINDOW_ID=@97" "FAKE_TMUX_WINDOW_REF=claude-y:0" \
    "FAKE_WINDOW_LANE_NONE=1" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=newest-9\t2026-09-13T03:31:56Z\tclaude-x:0 @12\nmine-5\t2026-09-13T03:31:33Z\tclaude-y:0 @97\n" \
    -- run team002 --resume session-helperonly
grep -Fq 'mine-5' "$LANE_START_LOG" \
    && fail "helper is the read: the launcher parsed the swapped rows itself ('$(lane_start_argv)')"; assertion
grep -Fxq -- "--confirm newest-9 -- $claude_args --resume session-helperonly" "$LANE_START_LOG" \
    || fail "helper is the read: it did not fall to the confirmed guess ('$(lane_start_argv)')"; assertion

# 3b. ...and by `<session>:<index>` where the id answered nothing. The id is
# the better key and is asked about FIRST — a `<session>:<index>` is reused the
# instant a window closes and the next one takes its index, while an id is never
# reissued for the life of the server — but a record written before ids were
# recorded still names its window, and that is still exact.
launch "FAKE_TMUX_WINDOW=zsh" "FAKE_LANE_WITH_ROW=nothing" \
    "FAKE_TMUX_WINDOW_ID=@97" "FAKE_TMUX_WINDOW_REF=claude-y:0" \
    "FAKE_WINDOW_LANE_MAP=claude-y:0=mine-5" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=newest-9\t2026-09-13T03:31:56Z\tclaude-x:0\nmine-5\t2026-09-13T03:31:33Z\tclaude-y:0\n" \
    -- run team002 --resume session-byref
grep -Fxq -- "mine-5 -- $claude_args --resume session-byref" "$LANE_START_LOG" \
    || fail "record by session:index: lane-start argv was '$(lane_start_argv)'"; assertion
grep -q -- '--confirm' "$LANE_START_LOG" \
    && fail "record by session:index: an exact match was confirmed"; assertion

# 3b-i. THE ORDER OF THE TWO REFS, asserted on the log rather than inferred:
# `window-lane <@id>` is asked BEFORE `window-lane <session>:<index>`, and where
# the id answers the ref is never asked at all.
launch "FAKE_TMUX_WINDOW=zsh" "FAKE_LANE_WITH_ROW=nothing" \
    "FAKE_TMUX_WINDOW_ID=@97" "FAKE_TMUX_WINDOW_REF=claude-y:0" \
    "FAKE_WINDOW_LANE_MAP=@97=idmatch-5"$'\n'"claude-y:0=refmatch-9" \
    "FAKE_SWAPPED_STATUS=8" \
    -- run team002 --resume session-idfirst
grep -Fxq -- "idmatch-5 -- $claude_args --resume session-idfirst" "$LANE_START_LOG" \
    || fail "id first: the ref answered before the id ('$(lane_start_argv)')"; assertion
grep -Fxq 'argv=window-lane claude-y:0' "$LANES_EDIT_LOG" \
    && fail "id first: the ref was asked about although the id had answered"; assertion

# 3c. MUTATION — NOTHING NAMES THIS WINDOW, so the newest-first guess of
# precedence 4 applies and IT IS STILL CONFIRMED. The whole value of step 3 is
# that it is not a guess; a launcher that took the newest row bare because step
# 3 had merely been TRIED would have turned Amendment 8(c)'s one question into
# silence, and on 2026-09-13 the two newest records were 23 seconds apart.
launch "FAKE_TMUX_WINDOW=zsh" "FAKE_LANE_WITH_ROW=nothing" \
    "FAKE_TMUX_WINDOW_ID=@55" "FAKE_TMUX_WINDOW_REF=nobody:9" \
    "FAKE_WINDOW_LANE_NONE=1" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=newest-9\t2026-09-13T03:31:56Z\tclaude-x:0 @12\nmine-5\t2026-09-13T03:31:33Z\tclaude-y:0 @97\n" \
    -- run team002 --resume session-noexact
grep -Fxq -- "--confirm newest-9 -- $claude_args --resume session-noexact" "$LANE_START_LOG" \
    || fail "no exact record: lane-start argv was '$(lane_start_argv)'"; assertion

# 3c-i. DEGRADATION — TODAY'S ESTATE. A `lanes-edit.sh` predating Amendment 11
# has no `window-lane` subcommand at all: it prints its unknown-subcommand line
# and exits 2, exactly as a pre-Amendment-8 one did for `swapped`. That 2 is an
# OLD HELPER and is EXPECTED AND SILENT — not a caller's bug, not a notice —
# and the order falls to the NEXT step, which answers today on every
# workstation whose helper is not yet upgraded.
launch "FAKE_TMUX_WINDOW=zsh" "FAKE_LANE_WITH_ROW=nothing" \
    "FAKE_TMUX_WINDOW_ID=@97" "FAKE_TMUX_WINDOW_REF=claude-y:0" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=newest-9\t2026-09-13T03:31:56Z\tclaude-x:0 @12\n" \
    -- run team002 --resume session-oldhelper
grep -Fxq -- "--confirm newest-9 -- $claude_args --resume session-oldhelper" "$LANE_START_LOG" \
    || fail "old helper: it did not fall to precedence 4 ('$(lane_start_argv)')"; assertion
grep -Fq 'window-lane' "$ERR_LOG" \
    && fail "old helper: a helper predating Amendment 11 was reported as a fault ($(cat "$ERR_LOG"))"; assertion

# 3c-ii. MUTATION — A FAILED READ FALLS TO THE NEXT STEP, NOT TO STEP 5, AND
# NAMES ITSELF. SPEC §2: "A failed read falls to the NEXT step, not to step 5 …
# dropping to 5 would skip step 4, which answers today on every workstation
# whose helper is not yet upgraded." 64 is the helper's own usage error and it
# says nothing about unknown subcommands, so it is a caller's bug: one line,
# and still the confirmed guess of precedence 4 below it.
launch "FAKE_TMUX_WINDOW=zsh" "FAKE_LANE_WITH_ROW=nothing" \
    "FAKE_TMUX_WINDOW_ID=@97" "FAKE_TMUX_WINDOW_REF=claude-y:0" \
    "FAKE_WINDOW_LANE_STATUS=64" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=newest-9\t2026-09-13T03:31:56Z\tclaude-x:0 @12\n" \
    -- run team002 --resume session-failedread
grep -Fxq -- "--confirm newest-9 -- $claude_args --resume session-failedread" "$LANE_START_LOG" \
    || fail "failed read: it did not fall to the NEXT step ('$(lane_start_argv)')"; assertion
grep -Fq 'window-lane' "$ERR_LOG" \
    || fail "failed read: it was not named ($(cat "$ERR_LOG"))"; assertion
grep -Fq "$note" "$ERR_LOG" \
    && fail "failed read: it dropped to step 5's no-lane notice instead of to step 4"; assertion

# 3d. The WINDOW NAME still beats the record, and when it answers the record is
# not read at all. Precedence 2 is first for a reason: it is the register's own
# word about a live window, and the record is a copy of an address.
launch "FAKE_TMUX_WINDOW=openRepoProject-1" "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    "FAKE_TMUX_WINDOW_ID=@97" \
    "FAKE_WINDOW_LANE_MAP=@97=mine-5" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=mine-5\t2026-09-13T03:31:33Z\tclaude-y:0 @97\n" \
    -- run team002 --resume session-namewins
grep -Fxq -- "openRepoProject-1 -- $claude_args --resume session-namewins" "$LANE_START_LOG" \
    || fail "name beats record: lane-start argv was '$(lane_start_argv)'"; assertion
grep -Fq 'argv=window-lane' "$LANES_EDIT_LOG" \
    && fail "name beats record: precedence 3 was read even though the window answered"; assertion

# ===========================================================================
# 4. THE LANE'S DIRECTORY — Amendment 11(3), SPEC §4 and §11.
#
# FOUR RUNGS AND NO FIFTH: `--dir`/`CLAUDE_LANE_DIR` → the swap record's `dir`
# → `lanes-edit.sh lane-dir <lane>` → lane-start's own default. The cwd's own
# checkout is ruled OUT BY NAME (A11 Addendum 1, `R-A11-3`), and 4f asserts its
# absence on the very shapes that used to make it fire.
# ===========================================================================

LANE_TREE="$TEST_ROOT/trees/openXfactory"
RECORD_TREE="$TEST_ROOT/trees/from-record"
SPACED_TREE="$TEST_ROOT/trees/my lane tree"
mkdir -p "$LANE_TREE" "$RECORD_TREE" "$SPACED_TREE"

# 4a. RUNG 1 — `--dir` is passed straight through, exactly as typed. It is the
# operator's word, and it is NOT tested for existence here: lane-start's own
# refusal names the path and the flag that fixes it, and a launcher that
# silently dropped what it was told would hide that.
launch "FAKE_TMUX_WINDOW=openRepoProject-1" "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    "FAKE_SWAPPED_STATUS=8" \
    -- --dir "$LANE_TREE" run team002 --resume session-dirflag
grep -Fxq -- "--dir $LANE_TREE openRepoProject-1 -- $claude_args --resume session-dirflag" "$LANE_START_LOG" \
    || fail "--dir: lane-start argv was '$(lane_start_argv)'"; assertion

# ...and `CLAUDE_LANE_DIR` is the SAME RUNG, not a second one: it is how the
# operator's `--dir` survives the re-exec into a new tmux session, exactly as
# `CLAUDE_LANE` carries `--lane` at precedence 1 of the lane order.
launch "FAKE_TMUX_WINDOW=openRepoProject-1" "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    "FAKE_SWAPPED_STATUS=8" "CLAUDE_LANE_DIR=$LANE_TREE" \
    -- run team002 --resume session-direnv
grep -Fxq -- "--dir $LANE_TREE openRepoProject-1 -- $claude_args --resume session-direnv" "$LANE_START_LOG" \
    || fail "CLAUDE_LANE_DIR: lane-start argv was '$(lane_start_argv)'"; assertion

# 4b. RUNG 2 — THE SWAP RECORD's fourth tab-separated field (SPEC §11), for the
# row that names THIS lane.
launch "FAKE_TMUX_WINDOW=zsh" "FAKE_LANE_WITH_ROW=nothing" \
    "FAKE_TMUX_WINDOW_ID=@97" \
    "FAKE_WINDOW_LANE_MAP=@97=mine-5" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=mine-5\t2026-09-13T03:31:33Z\tclaude-y:0 @97\t$RECORD_TREE\n" \
    -- run team002 --resume session-dirrecord
grep -Fxq -- "--dir $RECORD_TREE mine-5 -- $claude_args --resume session-dirrecord" "$LANE_START_LOG" \
    || fail "record dir: lane-start argv was '$(lane_start_argv)'"; assertion

# 4b-i. RUNG 2, READ FOR *THIS* LANE AND NOT FOR THE NEWEST ROW. A record for
# some other lane says nothing about where this one lives, and the lane here
# came from the operator's own `--lane` rather than from any row.
launch "FAKE_TMUX_WINDOW=zsh" "FAKE_LANE_WITH_ROW=nothing" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=someone-9\t2026-09-13T03:31:56Z\tclaude-x:0 @12\t$LANE_TREE\nmine-5\t2026-09-13T03:31:33Z\tclaude-y:0 @97\t$RECORD_TREE\n" \
    -- --lane mine-5 run team002 --resume session-dirmine
grep -Fxq -- "--dir $RECORD_TREE mine-5 -- $claude_args --resume session-dirmine" "$LANE_START_LOG" \
    || fail "record dir for this lane: lane-start argv was '$(lane_start_argv)'"; assertion

# 4b-ii. RUNG 2 WITH A SPACE IN THE PATH, which SPEC §5 makes a QUOTING rule
# rather than a refusal: the space is Amendment 7(b)'s separator between refs
# inside one sub-field, so the writer writes `dir "/home/b/my projects/x"` and
# every reader takes a value opening with `"` as running to its closing `"`,
# stripping both. This launcher is one of those readers.
launch "FAKE_TMUX_WINDOW=zsh" "FAKE_LANE_WITH_ROW=nothing" \
    "FAKE_TMUX_WINDOW_ID=@97" \
    "FAKE_WINDOW_LANE_MAP=@97=mine-5" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=mine-5\t2026-09-13T03:31:33Z\tclaude-y:0 @97; dir \"$SPACED_TREE\"\n" \
    -- run team002 --resume session-dirquoted
grep -Fxq -- "--dir $SPACED_TREE mine-5 -- $claude_args --resume session-dirquoted" "$LANE_START_LOG" \
    || fail "quoted dir: lane-start argv was '$(lane_start_argv)'"; assertion

# 4c. RUNG 3 — `lanes-edit.sh lane-dir <lane>` (SPEC §11), for a lane whose
# record carries no directory.
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
# byte-for-byte what it was before Amendment 11. This is RUNG 4.
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

# 4f. MUTATION — THERE IS NO FIFTH RUNG, ON THE VERY SHAPES THAT USED TO MAKE
# ONE FIRE. This is Evidence 2's own command, run from Evidence 2's own
# checkout: the lane is `openXfactory-5`, `$PROJECTS_ROOT/openXfactory` does not
# exist, and the cwd IS a git checkout named `openxFactory` — the same word in
# a different case. An earlier pass of this launcher inferred the lane's tree
# from it. A11 Addendum 1 `R-A11-3` ruled that out BY NAME, because lane-start
# writes the lane's HOME into its Amendment 7 STARTED line from that
# directory's `origin` and every `#n` the lane afterwards writes inherits it —
# an inference that can silently re-home a lane is not worth the refusal it
# saves, and the refusal names `--dir`. So NO `--dir` is passed, lane-start's
# own default stands, and lane-start refuses with the words that name the flag.
CWD_TREE="$TEST_ROOT/xFactory/openxFactory"
mkdir -p "$CWD_TREE"
git -C "$CWD_TREE" init -q 2>/dev/null || true
reset_logs
scenario
set +e
( cd "$CWD_TREE" && env "${common_env[@]}" \
    "FAKE_TMUX_WINDOW=openXfactory-5" "FAKE_LANE_WITH_ROW=openXfactory-5" \
    "FAKE_SWAPPED_STATUS=8" "PROJECTS_ROOT=$TEST_ROOT/projects" \
    "$LAUNCHER" run team002 --resume session-nocwd >/dev/null 2>"$ERR_LOG" )
launch_status=$?
set -e
grep -q -- '--dir' "$LANE_START_LOG" \
    && fail "no fifth rung: the cwd's own checkout was inferred as the lane's tree ($(lane_start_argv))"; assertion
grep -Fxq -- "openXfactory-5 -- $claude_args --resume session-nocwd" "$LANE_START_LOG" \
    || fail "no fifth rung: lane-start argv was '$(lane_start_argv)'"; assertion

# 4f-i. ...and the rung's own opt-out is gone with it. A switch that turns off
# a rung that does not exist is a switch that says the rung might: nothing may
# read `WORKBENCHES_CLAUDE_LANE_DIR_FROM_CWD` any more, and setting it changes
# nothing at all.
reset_logs
scenario
set +e
( cd "$CWD_TREE" && env "${common_env[@]}" \
    "FAKE_TMUX_WINDOW=openXfactory-5" "FAKE_LANE_WITH_ROW=openXfactory-5" \
    "FAKE_SWAPPED_STATUS=8" "PROJECTS_ROOT=$TEST_ROOT/projects" \
    "WORKBENCHES_CLAUDE_LANE_DIR_FROM_CWD=on" \
    "$LAUNCHER" run team002 --resume session-nocwd-on >/dev/null 2>"$ERR_LOG" )
launch_status=$?
set -e
grep -q -- '--dir' "$LANE_START_LOG" \
    && fail "no fifth rung: the retired opt-out still switches an inference on ($(lane_start_argv))"; assertion
grep -Fq 'WORKBENCHES_CLAUDE_LANE_DIR_FROM_CWD' "$LAUNCHER" \
    && fail "no fifth rung: the launcher still reads the retired opt-out"; assertion

# 4g. MUTATION — AND NOT EVEN WHERE THE DEFAULT EXISTS AND THE CWD IS THE
# LANE'S OWN TREE. The old rung's two fences are not the point; the inference
# is. Standing in the lane's own checkout must change nothing about where the
# lane is started.
mkdir -p "$TEST_ROOT/projects/openXfactory"
reset_logs
scenario
set +e
( cd "$CWD_TREE" && env "${common_env[@]}" \
    "FAKE_TMUX_WINDOW=openXfactory-5" "FAKE_LANE_WITH_ROW=openXfactory-5" \
    "FAKE_SWAPPED_STATUS=8" "PROJECTS_ROOT=$TEST_ROOT/projects" \
    "$LAUNCHER" run team002 --resume session-cwd-default >/dev/null 2>"$ERR_LOG" )
launch_status=$?
set -e
grep -q -- '--dir' "$LANE_START_LOG" \
    && fail "no fifth rung, default present: a directory was derived anyway ($(lane_start_argv))"; assertion
rm -rf "$TEST_ROOT/projects/openXfactory"

# 4j. THE ORDER. The operator's word beats every derived answer, and the record
# beats `lane-dir`. Set all three at once and exactly one may reach lane-start.
launch "FAKE_TMUX_WINDOW=zsh" "FAKE_LANE_WITH_ROW=nothing" \
    "FAKE_TMUX_WINDOW_ID=@97" \
    "FAKE_WINDOW_LANE_MAP=@97=mine-5" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=mine-5\t2026-09-13T03:31:33Z\tclaude-y:0 @97\t$RECORD_TREE\n" \
    "FAKE_LANE_DIR=$LANE_TREE" \
    -- --dir "$TEST_ROOT/trees" run team002 --resume session-dirorder
grep -Fxq -- "--dir $TEST_ROOT/trees mine-5 -- $claude_args --resume session-dirorder" "$LANE_START_LOG" \
    || fail "dir order: the flag did not win ('$(lane_start_argv)')"; assertion

launch "FAKE_TMUX_WINDOW=zsh" "FAKE_LANE_WITH_ROW=nothing" \
    "FAKE_TMUX_WINDOW_ID=@97" \
    "FAKE_WINDOW_LANE_MAP=@97=mine-5" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=mine-5\t2026-09-13T03:31:33Z\tclaude-y:0 @97\t$RECORD_TREE\n" \
    "FAKE_LANE_DIR=$LANE_TREE" \
    -- run team002 --resume session-dirorder2
grep -Fxq -- "--dir $RECORD_TREE mine-5 -- $claude_args --resume session-dirorder2" "$LANE_START_LOG" \
    || fail "dir order: the record did not beat lane-dir ('$(lane_start_argv)')"; assertion
grep -Fq 'argv=lane-dir' "$LANES_EDIT_LOG" \
    && fail "dir order: lane-dir was read although the record had already answered"; assertion
# ---------------------------------------------------------------------------
# 4k-4n. A RECORDED DIRECTORY THAT IS GONE, AND THE DIRECTORY THE LAUNCH RUNS
# IN — RV-W2 and Evidence 3 (A11 Addendum 2 `R-A11-11`).
#
# The rung tests above say which path is CHOSEN. These say what happens to it:
# a recorded one that is not there is a refusal naming it, never a fall to rung
# 4; and the one that is there is ENTERED before anything is launched.
GONE_TREE="$TEST_ROOT/trees/moved-away"

# 4k. RV-W2, AND THE REVIEW'S SURVIVING MUTATION M1. The lane's swap record
# names a directory that no longer exists. Under the `-d` test this launcher
# used to make, that record was SKIPPED and the order fell through rung 3 to
# rung 4 — `$PROJECTS_ROOT/<repo>`, which here EXISTS and is a different tree.
# `lane-start` would start the lane in it and write the lane's HOME from that
# tree's `origin` into its Amendment 7 STARTED line, and every `#n` after it
# inherits that: `R-A11-3`'s own hazard, reached from the record instead of
# from the cwd. So the launcher refuses, names the path, and starts nothing.
mkdir -p "$TEST_ROOT/projects/mine"
launch "FAKE_TMUX_WINDOW=zsh" "FAKE_LANE_WITH_ROW=nothing" \
    "FAKE_TMUX_WINDOW_ID=@97" \
    "FAKE_WINDOW_LANE_MAP=@97=mine-5" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=mine-5\t2026-09-13T03:31:33Z\tclaude-y:0 @97\t$GONE_TREE\n" \
    -- run team002 --resume session-dirgone
[[ "$launch_status" -eq 2 ]] \
    || fail "gone record dir: the launcher exited $launch_status instead of refusing"; assertion
grep -Fq "$GONE_TREE" "$ERR_LOG" \
    || fail "gone record dir: the refusal does not NAME the path ($(cat "$ERR_LOG"))"; assertion
grep -Fq -- '--dir' "$ERR_LOG" \
    || fail "gone record dir: the refusal does not name the one word that fixes it ($(cat "$ERR_LOG"))"; assertion
[[ ! -e "$LANE_START_LOG" ]] \
    || fail "gone record dir: the lane was started anyway ($(lane_start_argv))"; assertion
[[ ! -e "$CLAUDE_LOG" ]] \
    || fail "gone record dir: a Claude was started in a tree nobody named ($(cat "$CLAUDE_LOG"))"; assertion
grep -Fq "$TEST_ROOT/projects/mine" "$ERR_LOG" \
    && fail "gone record dir: the lane was silently RE-HOMED to lane-start's default"; assertion
rm -rf "$TEST_ROOT/projects/mine"

# 4k-i. ...AND IN A CHILD IT DROPS TO BARE CLAUDE INSTEAD, because `R-A11-4`
# outranks the refusal there: this process is the only command of a window the
# launcher itself made, so an exit leaves tmux printing `[exited]` over it. The
# lane is dropped, the path is still named, and the window keeps a Claude.
launch "WORKBENCHES_CLAUDE_TMUX_CHILD=1" \
    "WORKBENCHES_CLAUDE_WINDOW=mine-5" \
    "FAKE_TMUX_WINDOW=mine-5" "FAKE_LANE_WITH_ROW=mine-5" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=mine-5\t2026-09-13T03:31:33Z\tclaude-y:0 @97\t$GONE_TREE\n" \
    -- run team002 --resume session-dirgone-child
grep -Fxq -- "$claude_args --resume session-dirgone-child" "$CLAUDE_LOG" \
    || fail "gone record dir in a child: the pane was left with no Claude in it — [exited] (R-A11-4)"; assertion
[[ "$launch_status" -eq 0 ]] \
    || fail "gone record dir in a child: the launcher exited $launch_status over a Claude that started"; assertion
grep -Fq "$GONE_TREE" "$ERR_LOG" \
    || fail "gone record dir in a child: the path was not named ($(cat "$ERR_LOG"))"; assertion
[[ ! -e "$LANE_START_LOG" ]] \
    || fail "gone record dir in a child: the lane was started in a tree that is not there ($(lane_start_argv))"; assertion

# 4k-ii. THE SAME FOR RUNG 3, the lane's own recorded directory. One rule for
# both records; the mutation that survived was on rung 2's line alone.
launch "FAKE_TMUX_WINDOW=openXfactory-5" "FAKE_LANE_WITH_ROW=openXfactory-5" \
    "FAKE_SWAPPED_STATUS=8" "FAKE_LANE_DIR=$GONE_TREE" \
    -- run team002 --resume session-lanedirgone
[[ "$launch_status" -eq 2 ]] \
    || fail "gone lane-dir: the launcher exited $launch_status instead of refusing"; assertion
grep -Fq "$GONE_TREE" "$ERR_LOG" \
    || fail "gone lane-dir: the refusal does not name the path ($(cat "$ERR_LOG"))"; assertion
[[ ! -e "$LANE_START_LOG" ]] \
    || fail "gone lane-dir: the lane was started anyway ($(lane_start_argv))"; assertion

# 4k-iii. AND RUNG 1 IS NOT TOUCHED BY ANY OF IT. SPEC §4 says of the
# operator's own word, and only of it, that it is "not tested for existence —
# lane-start's refusal names the path and the flag". Two refusals for one typo
# would be two; the launcher passes it on and lane-start says it once.
launch "FAKE_TMUX_WINDOW=openRepoProject-1" "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    "FAKE_SWAPPED_STATUS=8" "FAKE_LANE_START_STATUS=1" \
    -- --dir "$GONE_TREE" run team002 --resume session-dirflag-gone
grep -Fxq -- "--dir $GONE_TREE openRepoProject-1 -- $claude_args --resume session-dirflag-gone" "$LANE_START_LOG" \
    || fail "gone --dir: the operator's own word was not passed through ($(lane_start_argv))"; assertion
grep -Fq 'the directory recorded for' "$ERR_LOG" \
    && fail "gone --dir: the launcher refused a path SPEC §4 says lane-start refuses"; assertion

# 4m. EVIDENCE 3 — THE LAUNCH RUNS IN THE LANE'S DIRECTORY. The second restart
# of this lane today was typed from `/workspace`: the launcher made its session
# there, the harness keyed the session to that directory, and the repository's
# CLAUDE.md and the lane's memory did not load, while `--resume <uuid>` still
# continued the transcript. Nothing refused and nothing warned. So the resolved
# directory is ENTERED before lane-start is run, and the Claude lane-start
# execs inherits it.
launch "FAKE_TMUX_WINDOW=zsh" "FAKE_LANE_WITH_ROW=nothing" \
    "FAKE_TMUX_WINDOW_ID=@97" \
    "FAKE_WINDOW_LANE_MAP=@97=mine-5" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=mine-5\t2026-09-13T03:31:33Z\tclaude-y:0 @97\t$RECORD_TREE\n" \
    -- run team002 --resume session-dircd
grep -Fxq "$RECORD_TREE" "$LANE_START_CWD_LOG" \
    || fail "evidence 3: lane-start was run from '$(cat "$LANE_START_CWD_LOG" 2>/dev/null)', not the lane's own directory"; assertion

# 4m-i. ...AND SO DOES THE BARE CLAUDE BEHIND A REFUSAL. The drop exists so that
# no window is left empty (R-A11-4); a drop that lands in the terminal's own
# directory is Evidence 3 again, one door along, with the lane's instructions
# and memory missing from the session that replaces it.
launch "WORKBENCHES_CLAUDE_TMUX_CHILD=1" \
    "WORKBENCHES_CLAUDE_WINDOW=mine-5" \
    "FAKE_TMUX_WINDOW=mine-5" "FAKE_LANE_WITH_ROW=mine-5" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=mine-5\t2026-09-13T03:31:33Z\tclaude-y:0 @97\t$RECORD_TREE\n" \
    "FAKE_LANE_START_STATUS=1" \
    -- run team002 --resume session-dircd-bare
grep -Fxq -- "$claude_args --resume session-dircd-bare" "$CLAUDE_LOG" \
    || fail "evidence 3, bare drop: no Claude started at all"; assertion
grep -Fxq "$RECORD_TREE" "$CLAUDE_CWD_LOG" \
    || fail "evidence 3, bare drop: Claude ran in '$(cat "$CLAUDE_CWD_LOG" 2>/dev/null)' instead of the lane's directory"; assertion

# 4m-ii. AND RUNG 4 ENTERS NOTHING. Where no directory was learnt there is
# nothing to enter, and the launch is byte-for-byte what it was before
# Amendment 11: lane-start derives its own default from where it stands.
launch "FAKE_TMUX_WINDOW=openRepoProject-1" "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    "FAKE_SWAPPED_STATUS=8" \
    -- run team002 --resume session-nodircd
grep -Fxq "$TEST_ROOT" "$LANE_START_CWD_LOG" \
    || fail "rung 4: the launcher moved to '$(cat "$LANE_START_CWD_LOG" 2>/dev/null)' although it learnt no directory"; assertion

# 4n. ACT 1 CREATES THE SESSION WITH `-c` THE LANE'S DIRECTORY (Evidence 3).
# The evidence's own shape: no window to reuse, a session made, and the pane it
# is made in decides what the harness keys the session to.
tty_launch "TMUX=" "FAKE_TMUX_WINDOW=claude" "FAKE_LANE_WITH_ROW=nothing" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=mine-5\t2026-09-13T03:31:33Z\tclaude-y:0 @97\t$RECORD_TREE\n" \
    -- --lane mine-5 run team002 --resume session-newsession-dir
grep -q 'new-session' "$TMUX_LOG" || fail "act 1 step 3 -c: no session was created"; assertion
grep -Fq -- "-c $RECORD_TREE" "$TMUX_LOG" \
    || fail "act 1 step 3: the session was created outside the lane's directory ($(cat "$TMUX_LOG"))"; assertion

# 4n-i. ...BUT NEVER FROM A GUESS. The newest-first row of precedence 4 is an
# inference the CHILD hands to lane-start as `--confirm`; act 1 already refuses
# to name the window from it, and the directory is the same rule. Standing
# somewhere else and starting a session in a lane nobody confirmed is how a
# restart lands in the wrong tree with the right name.
tty_launch "TMUX=" "FAKE_TMUX_WINDOW=claude" "FAKE_LANE_WITH_ROW=nothing" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=mine-5\t2026-09-13T03:31:33Z\tclaude-y:0\t$RECORD_TREE\n" \
    -- run team002 --resume session-newsession-guess
grep -Fq -- "-c $RECORD_TREE" "$TMUX_LOG" \
    && fail "act 1 step 3: the session was created in a directory taken from a lane nobody confirmed ($(cat "$TMUX_LOG"))"; assertion
grep -Fq -- "-c $TEST_ROOT" "$TMUX_LOG" \
    || fail "act 1 step 3: the session was created with no start directory at all ($(cat "$TMUX_LOG"))"; assertion

# 4n-ii. AND THE REUSED PANE IS RESPAWNED WITH `-c` TOO. A window the lane
# already had keeps whatever start directory it was BORN with, which is the
# lane's tree only if it was made for the lane — and Evidence 3 is a window
# that was not.
tty_launch "TMUX=" "FAKE_TMUX_WINDOW=claude" "FAKE_LANE_WITH_ROW=nothing" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=mine-5\t2026-09-13T03:31:33Z\tclaude-y:0 @97\t$RECORD_TREE\n" \
    "FAKE_TMUX_WINDOWS=@97|claude-y:0|%12|mine-5" \
    -- --lane mine-5 run team002 --resume session-respawn-dir
grep -q 'new-session' "$TMUX_LOG" \
    && fail "act 1 step 2 -c: a session was created although the recorded window still exists ($(cat "$TMUX_LOG"))"; assertion
grep -Fq -- "respawn-pane -k -c $RECORD_TREE -t %12" "$TMUX_LOG" \
    || fail "act 1 step 2: the pane was respawned outside the lane's directory ($(cat "$TMUX_LOG"))"; assertion

# 4n-iii. DEGRADATION — a tmux predating 2.6 has no `-c` on respawn-pane and
# refuses the OPTION, not the pane. That is a different failure from "the pane
# is in use" and has a different right answer: one retry without it, so the
# REUSE survives — act 1 step 2 is the whole of what a restart in the lane's
# own window is for — and the child's own `cd` covers the difference.
tty_launch "TMUX=" "FAKE_TMUX_WINDOW=claude" "FAKE_LANE_WITH_ROW=nothing" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=mine-5\t2026-09-13T03:31:33Z\tclaude-y:0 @97\t$RECORD_TREE\n" \
    "FAKE_TMUX_WINDOWS=@97|claude-y:0|%12|mine-5" "FAKE_TMUX_NO_RESPAWN_C=1" \
    -- --lane mine-5 run team002 --resume session-respawn-old-tmux
grep -Fq 'respawn-pane -k -t %12' "$TMUX_LOG" \
    || fail "old tmux: the respawn was not retried without -c ($(cat "$TMUX_LOG"))"; assertion
grep -q 'new-session' "$TMUX_LOG" \
    && fail "old tmux: the reuse was lost over an option this tmux does not have ($(cat "$TMUX_LOG"))"; assertion

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

# 5g. THE DOOR ACT 1 OPENED, AND R-A11-4's "NO PATH EXITS THE PANE". A child of
# the re-exec whose window ALREADY CARRIES THE LANE'S NAME — which is now the
# ordinary case, because act 1 step 3 names the new window for a certain lane at
# birth and step 2 reuses a window that already has the name — met a lane-start
# that REFUSED. The window read cannot tell that refusal from a Claude's own
# exit 1 there, because the rename lane-start would have made is a no-op; and
# handing the status back in a child is not "returning the operator to a
# prompt", because the child IS the only command of a window the launcher made
# a moment ago. tmux would print `[exited]` over a window with no Claude in it,
# which is Evidence 2 exactly, through a third door. So in a child the launcher
# drops to bare Claude with one line.
launch "WORKBENCHES_CLAUDE_TMUX_CHILD=1" \
    "WORKBENCHES_CLAUDE_WINDOW=openXfactory-5" \
    "FAKE_TMUX_WINDOW=openXfactory-5" "FAKE_LANE_WITH_ROW=openXfactory-5" \
    "FAKE_SWAPPED_STATUS=8" "FAKE_LANE_START_STATUS=1" \
    -- run team002 --resume session-child-refused
grep -Fxq -- "openXfactory-5 -- $claude_args --resume session-child-refused" "$LANE_START_LOG" \
    || fail "child, window already the lane's: lane-start argv was '$(lane_start_argv)'"; assertion
grep -Fxq -- "$claude_args --resume session-child-refused" "$CLAUDE_LOG" \
    || fail "child, window already the lane's: the pane was left with no Claude in it — [exited] (R-A11-4)"; assertion
[[ "$launch_status" -eq 0 ]] \
    || fail "child, window already the lane's: the launcher exited $launch_status over a Claude that started"; assertion
grep -q 'did not take openXfactory-5 (exit 1)' "$ERR_LOG" \
    || fail "child, window already the lane's: the notice was '$(cat "$ERR_LOG")'"; assertion

# 5g-i. ...and OUTSIDE a child the same shape still hands the status back. There
# the launcher is a command in an existing window's shell: a refusal returns the
# operator to their prompt under lane-start's own words, and there is no pane to
# exit. Starting a bare Claude behind a session that may still be the lane's
# would mint a second transcript in the lane's own window, which is the lineage
# fault the protocol exists to prevent — and that objection is exactly what does
# NOT reach a window the launcher itself just made.
launch "FAKE_TMUX_WINDOW=openXfactory-5" "FAKE_LANE_WITH_ROW=openXfactory-5" \
    "FAKE_SWAPPED_STATUS=8" "FAKE_LANE_START_STATUS=1" \
    -- run team002 --resume session-shell-refused
[[ ! -e "$CLAUDE_LOG" ]] \
    || fail "shell, window already the lane's: a bare Claude was started behind a session that may still be the lane's ($(cat "$CLAUDE_LOG"))"; assertion
[[ "$launch_status" -eq 1 ]] \
    || fail "shell, window already the lane's: the launcher exited $launch_status instead of handing back 1"; assertion

# 5h. THE WHOLE MATRIX, ASSERTED RATHER THAN ARGUED. Every lane source this
# launcher has crossed with both of lane-start's documented refusals, IN A
# CHILD — which is every path on which this process is the only command of a
# tmux window and therefore every path that could print `[exited]`. Each cell
# must end with a Claude running and the launcher exiting 0. This is the
# scenario SPEC §2's "a launcher never refuses to start Claude" owes, and it is
# one loop rather than eight paragraphs because the claim is about ALL of them.
for lane_case in flag window window-record record; do
    for refusal in 1 2; do
        case "$lane_case" in
            flag)          lane_env=(--lane matrix-1) ; scen=(
                               "FAKE_TMUX_WINDOW=matrix-1" "FAKE_LANE_WITH_ROW=nothing"
                               "FAKE_SWAPPED_STATUS=8") ;;
            window)        lane_env=() ; scen=(
                               "FAKE_TMUX_WINDOW=matrix-1" "FAKE_LANE_WITH_ROW=matrix-1"
                               "FAKE_SWAPPED_STATUS=8") ;;
            window-record) lane_env=() ; scen=(
                               "FAKE_TMUX_WINDOW=matrix-1" "FAKE_LANE_WITH_ROW=nothing"
                               "WORKBENCHES_CLAUDE_WINDOW_ID=@97"
                               "FAKE_WINDOW_LANE_MAP=@97=matrix-1"
                               "FAKE_SWAPPED_STATUS=8") ;;
            record)        lane_env=() ; scen=(
                               "FAKE_TMUX_WINDOW=matrix-1" "FAKE_LANE_WITH_ROW=nothing"
                               "FAKE_SWAPPED_STATUS=0"
                               "FAKE_SWAPPED_ROWS=matrix-1\t2026-09-13T03:31:33Z\tclaude-m:0\n") ;;
        esac
        launch "WORKBENCHES_CLAUDE_TMUX_CHILD=1" \
            "WORKBENCHES_CLAUDE_WINDOW=matrix-1" \
            "${scen[@]}" "FAKE_LANE_START_STATUS=$refusal" \
            -- ${lane_env[@]+"${lane_env[@]}"} run team002 --resume "session-$lane_case-$refusal"
        grep -Fxq -- "$claude_args --resume session-$lane_case-$refusal" "$CLAUDE_LOG" \
            || fail "no [exited] pane: lane source $lane_case, lane-start exit $refusal, left the pane with no Claude ($(cat "$CLAUDE_LOG" 2>/dev/null))"; assertion
        [[ "$launch_status" -eq 0 ]] \
            || fail "no [exited] pane: lane source $lane_case, lane-start exit $refusal, the launcher exited $launch_status"; assertion
        [[ -e "$LANE_START_LOG" ]] \
            || fail "no [exited] pane: lane source $lane_case, lane-start was never invoked at all"; assertion
    done
done

# 5h-i. ...and the same matrix with a lane-start that is not there AT ALL, which
# is the other way an `exec`ed one used to die (`lane-start:337`'s sibling: a
# helper that is not on PATH). The launcher refuses the launch only where the
# operator NAMED a lane and it cannot be taken; with no lane named, the whole
# feature is simply absent and Claude starts.
reset_logs
scenario
set +e
env "PATH=$TEST_ROOT/empty-bin:/usr/bin:/bin" \
    "HOME=$FAKE_HOME" "CLAUDE_BIN=$FAKE_CLAUDE" \
    "CLAUDE_PROFILES_HOME=$PROFILE_BASE" "CLAUDE_PROFILES_MANIFEST=$MANIFEST" \
    "FAKE_CLAUDE_LOG=$CLAUDE_LOG" "WORKBENCHES_SHARED_MCP_FAMILIES=disabled" \
    "WORKBENCHES_CLAUDE_TMUX_CHILD=1" "WORKBENCHES_CLAUDE_WINDOW=matrix-1" \
    "$LAUNCHER" run team002 --resume session-no-lane-start >"$OUT_LOG" 2>"$ERR_LOG"
launch_status=$?
set -e
grep -Fxq -- "$claude_args --resume session-no-lane-start" "$CLAUDE_LOG" \
    || fail "no lane-start on PATH: the pane was left with no Claude in it ($(cat "$CLAUDE_LOG" 2>/dev/null))"; assertion
[[ "$launch_status" -eq 0 ]] \
    || fail "no lane-start on PATH: the launcher exited $launch_status"; assertion

# ===========================================================================
# 6. EVERY FIELD NAME IS THE SPEC'S, BYTE FOR BYTE — SPEC §4, §5 and §11.
#
# A field name is a contract between writers and readers that nothing else
# enforces: a launcher that reads `dir:` where the writer writes `dir `, or a
# skill that writes `win` where the reader looks for `window`, fails silently
# and only at a restart. The four artefacts this PR ships are audited against
# the SPEC's own spellings here, statically, because the failure they have is
# not one a scenario can provoke — it is one that simply never matches.
# ===========================================================================

scenario
SKILL_MD="$REPO_ROOT/base-image/files/claude/skills/lane-swap/SKILL.md"
SWAP_MD="$REPO_ROOT/base-image/files/claude/commands/swap.md"
GUARD_SH="$REPO_ROOT/base-image/files/claude-usage-guard.sh"

# SPEC §5 — the swap record's payload, in the SPEC's own order and spelling:
# `swap; window <session>:<index> <@id>; dir <path>; workstation <ws>`.
grep -Fq 'payload="swap"' "$SKILL_MD" \
    || fail "§5: the PAUSED payload does not open with the verb-less swap token"; assertion
grep -Fq 'payload="$payload; window $win"' "$SKILL_MD" \
    || fail "§5: the window sub-field is not written as 'window <refs>'"; assertion
grep -Fq 'payload="$payload; dir $dir"' "$SKILL_MD" \
    || fail "§5: the directory sub-field is not written as 'dir <path>'"; assertion
grep -Fq 'payload="$payload; workstation ' "$SKILL_MD" \
    || fail "§5: the workstation sub-field is not written as 'workstation <ws>'"; assertion
# ...and the window sub-field's two refs are SPACE-separated within it, which is
# Amendment 7(b)'s rule for several refs in one sub-field.
grep -Fq 'win="${win:+$win }$win_id"' "$SKILL_MD" \
    || fail "§5: the window sub-field's two refs are not space-separated"; assertion
# ...and a space in a path is QUOTED, while `, `, ` — ` and a `"` are refused.
grep -Fq 'case "$dir" in *'"'"' '"'"'*) dir=' "$SKILL_MD" \
    || fail "§5/R-A11-6: a dir sub-field containing a space is not quoted"; assertion
grep -q 'case "\$dir" in .*'"'"', '"'"'.*'"'"' — '"'"'.*refused' "$SKILL_MD" \
    || fail "§5: a dir sub-field containing ', ' or ' -- ' is not refused"; assertion

# SPEC §7 — the uuid is SUPPLIED, not left for session_for() to substitute.
grep -Fq 'LANES_SESSION="$uuid"' "$SKILL_MD" \
    || fail "§7/R-A11-5: the skill does not pass the uuid it has in hand"; assertion

# SPEC §11 — the helper's reads, by their own names, in all three callers this
# PR ships. `window-lane` has THREE (R-A11-6 on F17): the launcher's precedence
# 3, /restart step 2(b) — the tooling PR's — and the skill's step 1.
grep -Fq 'window-lane' "$LAUNCHER" \
    || fail "§11: the launcher does not read precedence 3 through window-lane"; assertion
grep -Fq 'window-lane' "$SKILL_MD" \
    || fail "§11/R-A11-6: the skill's step 1 does not take the new precedence step"; assertion
grep -Fq 'lane-dir' "$LAUNCHER" \
    || fail "§11: the launcher does not read the lane's directory through lane-dir"; assertion

# SPEC §4 — the operator's word, in both of its spellings, and nothing else.
grep -Fq -- '--dir' "$LAUNCHER" || fail "§4: --dir is not an option of the launcher"; assertion
grep -Fq 'CLAUDE_LANE_DIR' "$LAUNCHER" || fail "§4: CLAUDE_LANE_DIR does not carry --dir across the re-exec"; assertion
grep -Fq 'dir[:=]' "$LAUNCHER" \
    && fail "§4/§5: the launcher still reads dir: / dir= spellings the SPEC does not name"; assertion

# SPEC §3 — the window's name and its address across the re-exec.
for var in WORKBENCHES_CLAUDE_WINDOW WORKBENCHES_CLAUDE_WINDOW_ID WORKBENCHES_CLAUDE_WINDOW_REF; do
    grep -Fq "$var" "$LAUNCHER" || fail "§3: $var is not threaded across the re-exec"; assertion
done

# SPEC §9 — `/swap` is a one-line command file that INVOKES the skill, and the
# 176-line skill is not duplicated into it. Two texts that must stay byte-equal
# with nothing making them so is the rejected alternative.
grep -Fq 'lane-swap' "$SWAP_MD" \
    || fail "§9: commands/swap.md does not invoke the lane-swap skill"; assertion
[[ "$(wc -l < "$SWAP_MD")" -lt 30 ]] \
    || fail "§9: commands/swap.md is $(wc -l < "$SWAP_MD") lines — it is restating the skill, not aliasing it"; assertion
grep -Fq 'append-row-status' "$SWAP_MD" \
    && fail "§9: commands/swap.md restates the skill's own steps, which is the rejected second copy"; assertion

# SPEC §9 — the guard's fence is the launcher's own exported lane, and the
# restart command it prints is the one-word form of SPEC §1.
grep -Fq 'WORKBENCHES_CLAUDE_LANE' "$GUARD_SH" \
    || fail "§9/R-A11-6: the guard's directive is not fenced on the session's lane"; assertion
grep -Fq 'pclaude ${CLAUDE_PROFILE_NAME:-<profile>}' "$GUARD_SH" \
    || fail "§9/§1: the guard does not print the one-word restart command"; assertion
grep -Fq 'pclaude run ' "$GUARD_SH" \
    && fail "§1: the guard still prints the long form of the restart command"; assertion
grep -Fq 'restart_cmd="pclaude ${CLAUDE_PROFILE_NAME:-<profile>}"' "$SKILL_MD" \
    || fail "§9/§1: the skill does not print the one-word restart command"; assertion

# ===========================================================================
# 6b. THE SWAP RECORD'S WRITER — RV-W1, RV-W6 and R-A11-10 (A11 Addendum 2).
#
# Three rules about ONE act, and all three fail the way §6's do: not by
# misbehaving in a scenario, but by never matching, never firing, or firing in
# the one case the clause exists for. A scenario cannot provoke any of them,
# because the act runs inside a Claude session and its inputs are that session's
# own record.
# ===========================================================================

scenario

# RV-W1 (BLOCKING) — THE REGISTER'S FILE-LEVEL `PAUSED` LINE IS WRITTEN OUTSIDE
# THE UUID GUARD. SPEC §7 and clause (e) both say, in the same words, that a
# lane with no uuid recorded reaches the refusal "where the swap writes the
# register's file-level PAUSED line and the row's state cell and names the gap
# in the handoff" — it is the whole of how A8(a) step 4's "never left unwritten"
# is preserved. Write (a), the object-log line, is refused there because that log
# is append-only; write (b) is not. The guard's own text is extracted and (b)
# must not be in it.
guard_start="$(grep -Fn 'if [[ -z "${uuid:-}" ]]; then' "$SKILL_MD" | head -n 1 | cut -d : -f 1)"
[[ -n "$guard_start" ]] \
    || fail "RV-W1: the uuid guard is gone from the skill entirely, so SPEC §7's refusal is not made at all"; assertion
guard_end="$(awk -v start="$guard_start" 'NR >= start && $0 == "fi" { print NR; exit }' "$SKILL_MD")"
[[ -n "$guard_end" && "$guard_end" -gt "$guard_start" ]] \
    || fail "RV-W1: the uuid guard opened at line $guard_start never closes, so nothing can be said about what is inside it"; assertion
guard_block="$(sed -n "${guard_start},${guard_end}p" "$SKILL_MD")"
# (a), the OBJECT-LOG write, must still be INSIDE it: that log is append-only and
# an `unknown` there is wrong for ever, so moving the guard off it is the same
# defect from the other side.
printf '%s\n' "$guard_block" | grep -Fq 'log PAUSED' \
    || fail "SPEC §7: the object-log write is not inside the uuid guard, so an unknown session id can still reach an append-only log"; assertion
printf '%s\n' "$guard_block" | grep -Fq 'append-line' \
    && fail "RV-W1/R-A11-11: the register's file-level PAUSED line is inside the uuid guard (lines $guard_start-$guard_end), so a lane with no uuid gets neither write and A8(a) step 4's 'never left unwritten' is lost"; assertion
# ...and it is still written, with the gap in the SESSION position rather than a
# uuid. Deleting the line altogether would satisfy the assertion above.
grep -Fq '"$L" append-line "PAUSED — lane $lane, session $session_field' "$SKILL_MD" \
    || fail "RV-W1: the file-level PAUSED line is not written from a session field that can carry the gap"; assertion
grep -Fq 'session_field="none recorded@$(hostname -s)"' "$SKILL_MD" \
    || fail "RV-W1: a lane with no recorded session does not NAME the gap in the line's session position"; assertion
# ...and write (c), the row's state cell, is outside the guard too — SPEC §7 names
# the two together, and a state cell flipped only where a uuid exists is the same
# defect one write along.
printf '%s\n' "$guard_block" | grep -Fq 'replace-in-row' \
    && fail "RV-W1/R-A11-11: the row's state cell is flipped only where a uuid exists, and SPEC §7 says it survives the refusal beside the file-level line"; assertion

# RV-W6 / R-A11-11 — THE `dir` THE SKILL RECORDS IS THE LANE'S CHECKOUT, NEVER A
# WORKTREE. SPEC §4 and clause (c) name the writer's source as the live session's
# own record — the harness's `"cwd"` beside its `"tmux"` — and the launcher's
# exported word before it. `git rev-parse --show-toplevel` and `$PWD` are the two
# derivations that record a subagent's scratchpad worktree on rung 4, which is
# every lane on the estate until a record carries a `dir`.
grep -Fq 'dir="${WORKBENCHES_CLAUDE_LANE_DIR:-}"' "$SKILL_MD" \
    || fail "RV-W6: the skill does not take the launcher's own word for the lane's directory first"; assertion
grep -Fq 'CLAUDE_CONFIG_DIR"/sessions/*.json' "$SKILL_MD" \
    || fail "RV-W6/R-A11-11: the skill does not read the live session's own record for the directory (SPEC §4)"; assertion
grep -Fq 'select((.sessionId // "") == $id) | .cwd // empty' "$SKILL_MD" \
    || fail "RV-W6: the session record is not matched on THIS session's id, so it could take another session's cwd"; assertion
# The two derivations are judged on the skill's own SHELL and not on its prose:
# the comment above the assignment names them as retired, and a rule that
# grepped the whole file could never be stated at all.
skill_code="$(grep -v '^[[:space:]]*#' "$SKILL_MD")"
printf '%s\n' "$skill_code" | grep -Fq 'git rev-parse --show-toplevel' \
    && fail "RV-W6/R-A11-11: the skill's shell still derives a directory from the git toplevel of wherever it stands, which in a subagent's scratchpad is a worktree"; assertion
printf '%s\n' "$skill_code" | grep -Fq '"$PWD"' \
    && fail "RV-W6/R-A11-11: the skill's shell still falls back to \$PWD for the lane's dir"; assertion
# ...and where neither source answers, the sub-field is OMITTED and the omission
# is SAID. A record with no `dir` is complete the way SPEC §5 says a record with
# no `@id` is; a record with the wrong one is not.
grep -Fq 'NO dir sub-field' "$SKILL_MD" \
    || fail "RV-W6: a record written with no dir says nothing about the gap"; assertion

# R-A11-10 (decision 7, drafted now) — `profile <name>` IS IN THE RECORD. A lane's
# name says nothing about the account it runs under, and `restart <lane>` has to
# build `pclaude --lane <lane> <profile>` out of the record alone.
grep -Fq 'payload="$payload; profile $profile_name"' "$SKILL_MD" \
    || fail "R-A11-10: the swap record does not carry the 'profile <name>' sub-field"; assertion
grep -Fq 'profile_name="${CLAUDE_PROFILE_NAME:-}"' "$SKILL_MD" \
    || fail "R-A11-10: the profile sub-field is not taken from the launcher's exported CLAUDE_PROFILE_NAME"; assertion
# ...and the launcher is the one that exports it, so the two halves agree.
grep -Fq 'export CLAUDE_PROFILE_NAME="$profile"' "$LAUNCHER" \
    || fail "R-A11-10: the launcher does not export CLAUDE_PROFILE_NAME, so the skill's profile sub-field is empty on every launch"; assertion

[[ "$scenarios" -eq "$EXPECTED_SCENARIOS" ]] \
    || fail "$scenarios scenarios ran, $EXPECTED_SCENARIOS expected — one was added or lost without saying so"
echo "claude-profile Amendment 11: $scenarios scenarios, $assertions assertions passed"
