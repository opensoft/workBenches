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
#       window name and the picker. A row whose `window` sub-field names this
#       window's `<@id>` or `<session>:<index>` is an exact match on the window
#       the operator is standing in, so it goes to lane-start BARE. Only where
#       nothing names this window does precedence 4 apply — and since
#       lane-collision-protocol Amendment 18 Addendum 1 (clause (i-5),
#       opensoft/workBenches#79) that is no longer this launcher confirming a
#       swap-record guess with `--confirm`: it hands the pane to `lane`, on
#       PATH, given a terminal to ask on, and STOPS — `lane` exit 0 (acted on)
#       or 8 (quit, or nothing to pick) leaves nothing for this launcher to
#       start, and only exit 2, A REFUSAL, falls through to nothing exactly as
#       no `lane` on PATH or no terminal does.
#
# Everything the launcher shells out to is faked — tmux, lanes-edit.sh,
# lane-start, lane and claude — so the assertions are about the launcher's own
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
EXPECTED_SCENARIOS=111
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
LANE_START_ENV_LOG="$TEST_ROOT/lane-start-env.log"
CLAUDE_CWD_LOG="$TEST_ROOT/claude-cwd.log"
# THE LANE MARKERS THE SESSION COMES UP WITH (clause (g), non-blocking 3). The
# guard's automatic swap reads WORKBENCHES_CLAUDE_LANE and nothing else, and
# CLAUDE_LANE is what a NESTED pclaude reads at precedence 1 — so what the
# started process INHERITS is the whole of the fence, observed from the only
# place it can be observed.
CLAUDE_ENV_LOG="$TEST_ROOT/claude-env.log"
LANES_EDIT_LOG="$TEST_ROOT/lanes-edit.log"
ERR_LOG="$TEST_ROOT/stderr.log"
OUT_LOG="$TEST_ROOT/stdout.log"
FAKE_HOME="$TEST_ROOT/home"
# The four artefacts this suite audits, named once. `GUARD_SH` and the two
# markdown files are read by the static sections below; `GUARD_SH` is also
# under section 0's syntax gate, so it is defined here rather than there.
GUARD_SH="$REPO_ROOT/base-image/files/claude-usage-guard.sh"
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
# ...and WHAT LANE THIS SESSION COMES UP HOLDING. `${x-<unset>}` and not
# `${x:-<unset>}`: an EMPTY export and an absent variable are different answers
# and the fence is about the second, so the two must not be flattened here.
{
    printf 'WORKBENCHES_CLAUDE_LANE=%s\n' "${WORKBENCHES_CLAUDE_LANE-<unset>}"
    printf 'WORKBENCHES_CLAUDE_LANE_SOURCE=%s\n' "${WORKBENCHES_CLAUDE_LANE_SOURCE-<unset>}"
    printf 'WORKBENCHES_CLAUDE_LANE_DIR=%s\n' "${WORKBENCHES_CLAUDE_LANE_DIR-<unset>}"
    printf 'CLAUDE_LANE=%s\n' "${CLAUDE_LANE-<unset>}"
    printf 'CLAUDE_LANE_DIR=%s\n' "${CLAUDE_LANE_DIR-<unset>}"
} >> "${FAKE_CLAUDE_ENV_LOG:-/dev/null}"
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
            # THE PANE'S ROOT PROCESS (`R-A11-16`). `lane_is_pane_root` asks
            # for it by pane, and UNSET IS THE DEFAULT everywhere else: an
            # answer that is not a number is "not the root", which is the answer
            # that changes nothing, so every scenario that is not about this
            # fence behaves exactly as it did before it existed.
            if [[ "${5:-}" == '#{pane_pid}' ]]; then
                printf '%s\n' "${FAKE_TMUX_PANE_PID:-}"
                exit 0
            fi
            target="${4:-}"
            while IFS= read -r live; do
                [[ -n "$live" ]] || continue
                if [[ "${live%%|*}" == "$target" \
                    || "$(cut -d '|' -f 2 <<<"$live")" == "$target" ]]; then
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
# ...and the one ENVIRONMENT value the session it starts is judged on: since
# `R-A11-14` the launcher resolves the workstation on the host and exports it,
# and everything downstream — this fake stands for the real lane-start, and the
# /lane-swap skill stands behind that — reads it or refuses.
printf 'LANES_WORKSTATION=%s\n' "${LANES_WORKSTATION:-}" >> "${FAKE_LANE_START_ENV_LOG:-/dev/null}"
# ...and the lane marker, because the Claude a DECLINED `--confirm` starts is
# started by lane-start and inherits exactly this environment.
printf 'WORKBENCHES_CLAUDE_LANE=%s\n' "${WORKBENCHES_CLAUDE_LANE-<unset>}" >> "${FAKE_LANE_START_ENV_LOG:-/dev/null}"
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

# `ps`, IN A DIRECTORY OF ITS OWN — the second half of the pane-level fence
# (`R-A11-16`). It answers the two reads `lane_is_pane_root` makes and nothing
# else: `-o args= -p <pid>` and `-o ppid= -p <pid>`, out of `<pid>=<value>` maps
# with `*` as the catch-all, first match winning so a scenario can give one pid
# an answer of its own. It is NOT on the common PATH: every other scenario keeps
# the real `ps`, which knows nothing of this suite's pids and therefore answers
# the way the fence's failure path does — unchanged from before it existed.
PS_BIN="$TEST_ROOT/ps-bin"
mkdir -p "$PS_BIN"
cat > "$PS_BIN/ps" <<'EOF'
#!/usr/bin/env bash
field=""; pid=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) field="${2:-}"; shift 2 ;;
        -p) pid="${2:-}"; shift 2 ;;
        *)  shift ;;
    esac
done
map=""
case "$field" in
    args=) map="${FAKE_PS_ARGS:-}" ;;
    ppid=) map="${FAKE_PS_PPID:-}" ;;
esac
while IFS= read -r pair; do
    [[ -n "$pair" ]] || continue
    key="${pair%%=*}"
    [[ "$key" == "$pid" || "$key" == '*' ]] || continue
    printf '%s\n' "${pair#*=}"
    exit 0
done <<< "$map"
exit 1
EOF
chmod +x "$PS_BIN/ps"

# THE PICKER (lane-collision-protocol Amendment 18 Addendum 1, clause (i-5)),
# precedence 4's replacement for the swap record's `--confirm`. `lane` does not
# exist yet on any real machine (opensoft/openRepoTools#43 builds it in
# parallel), so this fake stands in for its whole contract: it logs the argv it
# was run with — bare, always, per clause (i-5) — and exits with whatever this
# scenario says its pick came to. Exit 0 is a pick ACTED ON, exit 8 is a QUIT
# or nothing to pick, exit 2 is A REFUSAL; this launcher hands it neither
# `--dir`, `--confirm`, `--resume` nor anything else.
LANE_PICKER_LOG="$TEST_ROOT/lane-picker.log"
cat > "$FAKE_BIN/lane" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${FAKE_LANE_LOG:?}"
exit "${FAKE_LANE_EXIT:-8}"
EOF

chmod +x "$FAKE_CLAUDE" "$FAKE_BIN/tmux" "$FAKE_BIN/lanes-edit.sh" "$FAKE_BIN/lane-start" "$FAKE_BIN/lane"

# THE WORKSTATION'S WORKSPACE MANIFEST — `R-A11-13`. `~/.agents/workspace.yaml`
# is where a person names their own workspace repository (this repo's README
# gives it as the whole of that setup step's idempotence), and since A11
# Addendum 3 it is where the launcher reads the repository whose
# `scripts/link-estates` places the lane tools. $FAKE_HOME is this suite's HOME,
# so the file below is the one every scenario here reads — and it names a
# repository that is NOT the one the launcher used to hard-code.
mkdir -p "$FAKE_HOME/.agents"
WORKSPACE_YAML="$FAKE_HOME/.agents/workspace.yaml"
printf 'repository: opensoft/estate-wip\npath: %s/estate-wip\n' "$TEST_ROOT" > "$WORKSPACE_YAML"

# `openRepoTools`, whose own `--help` is the capability probe's only source.
# TWO texts, and the difference between them is the whole of `R-A11-13`: the
# copy installed on this workstation today places park, resume, status and
# itself — measured, `--help` says "does nothing else" — and the copy Amendment
# 9 act 3 ships lists the lane tools beside them.
ORT_BIN="$TEST_ROOT/openrepotools-bin"
mkdir -p "$ORT_BIN"
cat > "$ORT_BIN/openRepoTools" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${FAKE_OPENREPOTOOLS_HELP:-}"
EOF
chmod +x "$ORT_BIN/openRepoTools"
OPENREPOTOOLS_HELP_TODAY='openRepoTools --install            install (or update) park, resume, status and
                                   this command into ~/.local/bin

This command installs the estate commands and does nothing else.'
OPENREPOTOOLS_HELP_ACT3='openRepoTools --install            install (or update) park, resume, status,
                                   lane-start, lanes-edit.sh and this command
                                   into ~/.local/bin'

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
    "FAKE_LANE_START_ENV_LOG=$LANE_START_ENV_LOG"
    "FAKE_CLAUDE_CWD_LOG=$CLAUDE_CWD_LOG"
    "FAKE_CLAUDE_ENV_LOG=$CLAUDE_ENV_LOG"
    "FAKE_LANES_EDIT_LOG=$LANES_EDIT_LOG"
    "FAKE_LANE_LOG=$LANE_PICKER_LOG"
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
    # opensoft/workBenches#95: the lane defect capture is kept, and its tail
    # printed, on a run that exits FAST — every fake here always does, having
    # no interactive session to hold open — so 0 tells the launcher that
    # merely being instant is not "fast" for this suite's purposes. A
    # scenario that means to test the keep-and-print behaviour overrides this
    # back up per-launch instead of relying on real elapsed time.
    "WORKBENCHES_CLAUDE_LANE_DEFECT_SECONDS=0"
    # Copilot round 1 on opensoft/workBenches#96: the 0 override above stops
    # an INSTANT status-0 run from being mistaken for a fast exit, but
    # several scenarios in this suite (5c, 5g and others) exercise the
    # genuinely ambiguous status-1/2-in-the-lane's-own-window case on
    # purpose, and the launcher KEEPS that capture by design. A test-local
    # TMPDIR means every one of those still lands under $TEST_ROOT — cleaned
    # by this file's own EXIT trap — rather than the real host /tmp.
    "TMPDIR=$TEST_ROOT"
)

claude_args='--allow-dangerously-skip-permissions --dangerously-skip-permissions --permission-mode bypassPermissions'
note='no lane for this window; run lane-start <repo> <n> inside it'

reset_logs() {
    rm -f "$CLAUDE_LOG" "$TMUX_LOG" "$LANE_START_LOG" "$LANES_EDIT_LOG" "$LANE_PICKER_LOG" "$ERR_LOG" "$OUT_LOG" \
        "$LANE_START_CWD_LOG" "$CLAUDE_CWD_LOG" "$LANE_START_ENV_LOG" "$CLAUDE_ENV_LOG"
}

# launch <scenario env>... -- <launcher args>...
#
# STDIN IS ALWAYS /dev/null HERE — never a terminal — so THE PICKER (step 3 of
# the lane order's Amendment 8(c) numbering, precedence 4 of the launcher's
# own; Amendment 18 Addendum 1) never fires by accident in a scenario that is
# not testing it: every scenario below that reaches precedence 4 with nothing
# to offer is thereby testing "no terminal on stdin", the same fall-through no
# `lane` on PATH gets. Scenarios that must prove the picker DOES fire use
# `tty_launch` below instead, which gives it a real one.
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
        </dev/null >"$OUT_LOG" 2>"$ERR_LOG"
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
lane_picker_argv() { cat "$LANE_PICKER_LOG" 2>/dev/null || true; }

# ===========================================================================
# 0. THE FILE PARSES, AND THE LINTER AGREES — CF-W4, under `R-A11-16` (A11
#    Addendum 3, ratified by Brett Heap 2026-09-13 "a11 addendum 3 yes").
#
# This PR adds ~1,400 lines to `base-image/files/claude-profile` and NOTHING
# ran a syntax check over it: the only `bash -n` calls in devcontainer.test/
# were on `codex-profile` and `wave-container-shell.sh`. The hazard is not
# hypothetical — one apostrophe inside a `${x:-word}` default swallows the rest
# of the file, and every function below it is simply missing at run time while
# the file still READS like bash.
#
# AND THE TWO HALVES OF THIS GATE ARE NOT THE SAME CHECK. Measured on this
# workstation (GNU bash 5.2.21, shellcheck 0.9.0) by putting one apostrophe into
# the launcher's own `lane_read_note` default: `bash -n` on the launcher exits
# 0 and says nothing, while `shellcheck -S error` refuses it with SC1073/SC1072
# naming the line. `bash -n` sees the error only where the stray quote is still
# open at END OF FILE, and any apostrophe below it closes it again. The
# confirmation review measured a three-line file, where the quote does reach EOF
# unbalanced and `bash -n` does exit 2 — both are true, and what differs is what
# follows the trap. The launcher's comment is corrected to say that, and this
# gate is what makes the correction load-bearing: the mutations for this round
# put both shapes into the launcher and it is the LINTER that catches each.
#
# Every scenario below runs the launcher, so a syntax error fails them all
# anyway — but it fails them as a hundred unrelated failures with no line
# number. This runs first and says the one thing that is wrong.
# `shellcheck` is run WHERE IT IS PRESENT and is not a dependency of this
# suite: `-S error` is what the launcher is clean at today (three warnings at
# `-S warning`, none of them this class), so the gate refuses a NEW error and
# does not demand a cleanup nobody asked for.
# ===========================================================================

scenario

bash -n "$LAUNCHER" \
    || fail "bash -n: the launcher does not parse — one apostrophe in a \${x:-word} default swallows every function below it (CF-W4)"; assertion
bash -n "$GUARD_SH" \
    || fail "bash -n: the usage guard does not parse"; assertion
if command -v shellcheck >/dev/null 2>&1; then
    shellcheck -S error "$LAUNCHER" \
        || fail "shellcheck -S error: the launcher has an error-level finding (CF-W4)"; assertion
    shellcheck -S error "$GUARD_SH" \
        || fail "shellcheck -S error: the usage guard has an error-level finding"; assertion
else
    echo "note: shellcheck is not on PATH, so the linter half of the CF-W4 gate did not run" >&2
fi

# CITATIONS OF THE AMENDMENT TEXT NAME A HEAD — round 4's own finding, and the
# reason it is a gate rather than one corrected comment.
#
# `brettheap/new-workstation#21` is a DRAFT that is still being written, and a
# bare line number into it is a citation that rots silently. Measured: the
# launcher's `act1_compose_child_command` cited `#21 :630-635` for the rule that
# the `window` sub-field is a fact about the writer's own window. That was TRUE
# at `2fc8db4`, the head the round-3 confirmation read; the same paragraph is
# `:642` at `1f88a12` and `:663` at `e7b639e`, the text having grown from 2,171
# to 2,402 lines across two rounds. Nothing in this repository noticed, because
# nothing here reads that file.
#
# So the rule: cite the CLAUSE — clause letters do not move — and where a line
# number is given as well, name the head it was read at in the same breath. This
# refuses the shape rather than the string, so the next writer cannot reintroduce
# it in a new file.
#
# ITS SCOPE IS EVERY ARTEFACT THIS PR SHIPS, and the list below is that list
# (round-4 non-blocking 6). It used to name four files while claiming every
# document, leaving `README.md` and the `/swap` command file outside a gate whose
# whole point is the file nobody thought of; neither cites the text today, so
# nothing was wrong — the CLAIM was wider than the read, which is the shape of
# defect this PR keeps finding one file along. All eight installed artefacts are
# read now, and the list is checked for paths this checkout does not have, so a
# renamed file cannot make the gate pass by going unread.
#
# THE SUITES ARE DELIBERATELY OUTSIDE IT, and that is stated rather than left to
# be noticed: this file quotes `#21 :630-635` at `:568` on purpose — it is the
# record of the citation that rotted, and the defect a gate reading its own
# explanation would report is the explanation. What ships to a host is what is
# read; what explains the gate is not.
#
# It is deliberately narrow in the other direction too. It fires only on a `#21`
# citation that carries a line number and no `at <sha>` beside it; a citation
# naming only a clause is the preferred form and is not touched.
#
# EIGHT DROPPED TO SIX: lane-collision-protocol Amendment 9 adoption act 4b
# (`opensoft/workBenches#74`) deleted this repository's own copies of the
# `/lane-swap` skill and the `/swap` command file — `base-image/files/claude/
# skills/lane-swap/SKILL.md` and `base-image/files/claude/commands/swap.md` —
# together with the loops that installed from them, once `openRepoTools
# --install` took over both paths (A9 act 3, A11 Addendum 4 ruling 9) and the
# pin (`devBenches/base-image/upstream-pin.yaml`, commit `8a36eb3`,
# `opensoft/workBenches#78`) started vendoring them. What ships at
# `devBenches/base-image/files/openrepotools/skills/lane-swap/SKILL.md` and
# `.../commands/swap.md` is `opensoft/openRepoTools`' own prose now, copied
# in byte for byte and read by ITS repository's own citation convention, not
# this one's `#21` numbering — so the two drop out of this gate's remit
# rather than move within it.
cite_files=(
    "$LAUNCHER"
    "$REPO_ROOT/base-image/files/claude-usage-guard.sh"
    "$REPO_ROOT/docs/claude-multi-account-profiles.md"
    "$REPO_ROOT/README.md"
    "$REPO_ROOT/scripts/setup-claude-profiles.sh"
    "$REPO_ROOT/scripts/wave-container-shell.sh"
)
cite_missing=""
for cite_file in "${cite_files[@]}"; do
    [[ -f "$cite_file" ]] || cite_missing="$cite_missing $cite_file"
done
[[ -z "$cite_missing" ]] \
    || fail "citation: the gate's list names file(s) this checkout does not have ($cite_missing), so it would pass by not reading them"; assertion
cite_bare=0
cite_qualified=0
while IFS= read -r cite_line; do
    # Only a citation that GIVES a line number is in scope. A `#21` naming a
    # clause alone is the preferred form and is passed over.
    [[ "$cite_line" =~ :[0-9] ]] || continue
    case "$cite_line" in
        *'at `'*) cite_qualified=$((cite_qualified + 1)) ;;
        *) cite_bare=$((cite_bare + 1))
           echo "note: unqualified #21 citation: $cite_line" >&2 ;;
    esac
done < <(grep -hE '#21' "${cite_files[@]}" 2>/dev/null || true)
[[ "$cite_bare" -eq 0 ]] \
    || fail "citation: $cite_bare citation(s) of the #21 DRAFT give a line number with no head to read it at — that paragraph moved :630 -> :642 -> :663 across three heads, so the number alone points a reader at the wrong sentence"; assertion
[[ "$cite_qualified" -ge 1 ]] \
    || fail "citation: the gate found no head-qualified #21 line citation at all, so it is passing on an empty set rather than on the corrected one"; assertion

# A TEXT AUDIT READS A STRING. IT DOES NOT GO THROUGH A PIPE — this file's own
# defect, found while confirming round 5, and the reason it is a gate rather
# than forty corrected lines.
#
# MEASURED: this suite was NON-DETERMINISTIC. On `d5d252a`, before any round-5
# commit, twelve sequential runs from a pristine `git archive` of that head
# produced ONE failure — `FAIL: R-A11-14: the launcher resolves a workstation
# and never exports it` — a STATIC STRING AUDIT over a variable, which cannot be
# false while the launcher carries the line it looks for. A second sample gave
# one in eight, on a different assertion of the same shape.
#
# THE CAUSE is the shape, not any one assertion: a payload written into a reader
# that STOPS EARLY, under `set -o pipefail` (line 45). `grep -q` exits at its
# first match and closes the read end; the writer is a `printf` of a multi-
# kilobyte variable, which bash flushes in stdio-sized chunks and so takes more
# than one `write(2)`; the write after the close raises SIGPIPE and the writer
# exits 141; `pipefail` makes 141 the PIPELINE's status; `|| fail` fires on an
# assertion that MATCHED. It is a race between two processes and it is won
# either way on different runs. Measured on the real payloads at `cfc9254`:
# `$ws_launcher_code` is 37,796 bytes and the three needles §7d looks for in it
# returned a spurious 141 in 2, 3 and 6 runs of 300; a 1.3 MB payload returns one
# in 400 of 400.
#
# AND IT CUTS BOTH WAYS, which is worse than a flake. A NEGATIVE audit is
# `<payload> | grep -Fq FORBIDDEN && fail`, and on a 141 the `&&` does not fire:
# the suite goes GREEN while the artefact carries the string the assertion
# exists to refuse. `R-A11-27`'s own negative — the skill must not print
# "(c) below still runs" — is one of those, so the gate this PR built for a
# ratified ruling could have passed on a file that broke it.
#
# THE FIX IS TO STOP MAKING A PIPELINE. A here-string feeds the reader from
# bash itself: there is no second process to kill, no exit status to poison, and
# `grep`'s flags, patterns and `-c` counts are unchanged, so every assertion
# means exactly what it meant before. `<<<"$x"` appends one newline exactly as
# `printf '%s\n' "$x"` did. Re-measured after the change: 0 spurious failures in
# 300 on each of the three needles, and 0 in 400 on the 1.3 MB payload.
#
# THE GATE, and WHAT IT DOES NOT COVER, said rather than left to be noticed.
# It refuses the shape that was MEASURED to fail: a shell VARIABLE written into
# a reader that can stop early. Seventeen pipelines remain in these two suites
# whose writer is a command rather than a variable — `head -n 1 "$ERR_LOG"`,
# `lane_start_argv`, `grep -F '<one string>' "$SKILL_MD"` — and they are out of
# scope on a measured bound, not on a hope: the race needs the writer to still
# be writing after the reader has gone, which needs MORE THAN ONE `write(2)`,
# which needs an output above one stdio flush. The largest of them is 680 bytes
# (`grep -F 'REFUSED: no workstation for this lane' "$SKILL_MD"`, 678; the wave
# launcher's `--help`, 680), every other one is a single line, and one `write`
# into a 64 KiB pipe buffer completes before a reader can have read anything at
# all. If one of those writers ever grows past a few kilobytes this gate will
# not catch it, and that sentence is here so the next writer knows.
#
# Comments are stripped first — the paragraph you are reading names the shape it
# refuses, and a gate that read its own explanation would report the
# explanation, which is the trap the citation gate above had to be told about as
# well. The pattern is assembled from two fragments for the same reason: the
# line that builds it must not be an instance of what it looks for.
scenario
audit_writer="print""f '%s"
audit_suites=(
    "$REPO_ROOT/devcontainer.test/test-claude-profile-amendment-11.sh"
    "$REPO_ROOT/devcontainer.test/test-claude-profile-skill-install.sh"
)
audit_missing=""
for audit_file in "${audit_suites[@]}"; do
    [[ -f "$audit_file" ]] || audit_missing="$audit_missing $audit_file"
done
[[ -z "$audit_missing" ]] \
    || fail "text audit: the gate names suite(s) this checkout does not have ($audit_missing), so it would pass by not reading them"; assertion
audit_pipes="$(grep -hv '^[[:space:]]*#' "${audit_suites[@]}" \
    | grep -cE "$audit_writer.*\| *(grep|head|sed)" || true)"
[[ "$audit_pipes" -eq 0 ]] \
    || fail "text audit: $audit_pipes line(s) still write a variable into a reader that can stop early, so under pipefail a matched assertion can fail on SIGPIPE and a refused string can pass — feed the reader from a here-string instead"; assertion

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

# 1f-i. RV-W4 — THE SAME REFUSAL ON THE LONG FORM, and it is a DIFFERENT LINE
# of the launcher. 1f exercises the one-word arm, which refuses before the
# action is decided; `pclaude run <typo>` reaches the `login|status|run` arm,
# which refuses after the profile is looked up. SPEC §1 fixes the wording and
# the code for both, and the re-verification's mutation M6 — that arm's `exit 2`
# turned into `exit 1` — SURVIVED ten suites, because only one of the two was
# held. The verb being optional means the two forms are one command, so a
# reviewer reading either line must find the other pinned.
launch "FAKE_TMUX_WINDOW=claude" "FAKE_SWAPPED_STATUS=8" -- run teamOO2
[[ "$launch_status" -eq 2 ]] \
    || fail "typo, long form: exited $launch_status, and SPEC §1 says 2 (this is mutation M6)"; assertion
grep -q 'Unknown Claude profile: teamOO2' "$ERR_LOG" \
    || fail "typo, long form: the message was '$(cat "$ERR_LOG")'"; assertion
[[ ! -e "$CLAUDE_LOG" ]] || fail "typo, long form: it became a launch anyway"; assertion
[[ ! -e "$LANE_START_LOG" ]] || fail "typo, long form: it reached lane-start"; assertion

# 1f-ii. ...and on `status`, which shares that arm's one line. A profile that
# does not exist cannot be logged into, asked about or run, and all three say so
# in the same words with the same status.
launch "FAKE_TMUX_WINDOW=claude" "FAKE_SWAPPED_STATUS=8" -- status teamOO2
[[ "$launch_status" -eq 2 ]] \
    || fail "typo, status: exited $launch_status, and SPEC §1 says 2"; assertion
grep -q 'Unknown Claude profile: teamOO2' "$ERR_LOG" \
    || fail "typo, status: the message was '$(cat "$ERR_LOG")'"; assertion

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

# 1i-i. RV-W5 — `--help` IS THE DOCUMENT AN OPERATOR MEETS FIRST, so it says
# what this launcher does NOW and not what an earlier pass of it did. Every
# claim below is one Amendment 11 moved, and a help text that lags the code is
# how an operator learns a rule that is no longer true.
grep -q 'STEP 3 IS NEW IN AMENDMENT 11' "$TEST_ROOT/help.out" \
    || fail "RV-W5: --help does not document precedence step 3, the one zero-question rule Amendment 11 adds to this path"; assertion
grep -Fq 'the swap record whose `window` sub-field NAMES THIS WINDOW' "$TEST_ROOT/help.out" \
    || fail "RV-W5: --help's lane order does not carry step 3 at all"; assertion
grep -Fq 'WORKBENCHES_CLAUDE_LANE_DIR_FROM_CWD' "$TEST_ROOT/help.out" \
    && fail "RV-W5: --help still documents the cwd rung's opt-out, which c712c5b removed"; assertion
grep -Fq "The cwd's own checkout is NOT a rung" "$TEST_ROOT/help.out" \
    || fail "RV-W5: --help does not rule the cwd's own checkout out by name (R-A11-3)"; assertion
grep -Fq 'WORKBENCHES_CLAUDE_WINDOW_REUSE' "$TEST_ROOT/help.out" \
    || fail "RV-W5: the reuse opt-out is a switch nobody can find — the review's third declared addition, kept only if documented"; assertion
grep -Fq 'AND THE LAUNCH RUNS IN IT' "$TEST_ROOT/help.out" \
    || fail "RV-W5/Evidence 3: --help does not say the launcher enters the lane's directory"; assertion
grep -Fq 'refusal that names the path, never a quiet fall to the default' "$TEST_ROOT/help.out" \
    || fail "RV-W2: --help does not say what happens to a recorded directory that is gone"; assertion
grep -Fq 'NEVER DEGRADES IN SILENCE' "$TEST_ROOT/help.out" \
    || fail "Evidence 5: --help does not say what happens when lane-start is absent, which is the case a rebuilt machine meets"; assertion

# 1i-ii. RV-W3 — AND THE SCOPE OF "NO PATH EXITS THE PANE" IS STATED, now that
# `R-A11-16` has CLOSED the case that used to fall outside it rather than
# documenting it. The invariant is held wherever this process is the only
# command of its pane: every window act 1 made (WORKBENCHES_CLAUDE_TMUX_CHILD,
# the fast path) and, since the fence became a pane-level one, a window whose
# only command is `pclaude` and which the launcher did not create. What --help
# must still say is where the promise STOPS — the shell you typed `pclaude`
# into — because that arm is the one that hands a refusal back.
grep -q 'NO PATH THE LAUNCHER OPENED EXITS THE PANE' "$TEST_ROOT/help.out" \
    || fail "RV-W3: --help claims an invariant wider than the one this launcher proves"; assertion
grep -Fq 'THE CASE THAT IS NOT COVERED' "$TEST_ROOT/help.out" \
    && fail "RV-W3/R-A11-16: --help still documents as uncovered the case the pane-level fence closes"; assertion
grep -Fq 'RV-W3, closed by' "$TEST_ROOT/help.out" \
    || fail "RV-W3/R-A11-16: --help does not say that the third door is closed, or by what"; assertion
grep -Fq 'the only command of its pane' "$TEST_ROOT/help.out" \
    || fail "R-A11-16: --help states the promise in terms of the marker rather than the pane"; assertion
grep -Fq 'stops' "$TEST_ROOT/help.out" \
    || fail "R-A11-16: --help does not say where the walk stops, which is the arm that hands a refusal back"; assertion

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
# record's newest-first row is an INFERENCE that Amendment 8(c) used to hand
# over as `--confirm` and that lane-collision-protocol Amendment 18 Addendum 1
# now hands to the picker instead, so something asks before taking a window.
# Naming the window for it here would answer that question in advance and in
# the wrong place: the child would then find a window named for the lane and
# bind by NAME, silently, from a guess nobody confirmed.
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
# ...AND THE CHILD IN THAT NEW SESSION IS NOT HANDED THE WINDOW THE RESPAWN
# FAILED TO REUSE (non-blocking 6). `act1_find_window` copies the recorded
# window's name and address into `lane_window*` the moment it succeeds, and the
# command string was built from them BEFORE the respawn was attempted — so the
# child created here carried `WORKBENCHES_CLAUDE_WINDOW`/`_REF`/`_ID` for
# `claude-y:0 @97`, a window it is not in. It would bind by precedence 2 or 3 to
# that window and write it into its own swap record, where the amendment makes
# the `window` sub-field a fact about the WRITER's own window. The command is
# now composed again after the fall-through, with the three cleared. Asserted on
# the `new-session` line alone: the failed `respawn-pane` line carries the old
# command string on purpose, and a grep of the whole log could not tell them
# apart.
tmux_new_session_line="$(grep 'new-session' "$TMUX_LOG" | head -n 1)"
grep -Fq 'WORKBENCHES_CLAUDE_WINDOW_ID' <<<"$tmux_new_session_line" \
    && fail "act 1 fall-through: the child of the NEW session was handed the id of the window the respawn failed to reuse ($tmux_new_session_line)"; assertion
grep -Fq 'WORKBENCHES_CLAUDE_WINDOW_REF' <<<"$tmux_new_session_line" \
    && fail "act 1 fall-through: the child of the NEW session was handed the ref of the window the respawn failed to reuse ($tmux_new_session_line)"; assertion
grep -Fq 'WORKBENCHES_CLAUDE_WINDOW=' <<<"$tmux_new_session_line" \
    && fail "act 1 fall-through: the child of the NEW session was handed the NAME of the window the respawn failed to reuse ($tmux_new_session_line)"; assertion
# ...and the respawn that failed DID carry them, so this is a difference the
# fall-through makes and not a value that was never threaded at all.
grep 'respawn-pane' "$TMUX_LOG" | grep -Fq 'WORKBENCHES_CLAUDE_WINDOW_ID=@97' \
    || fail "act 1 fall-through: the reuse attempt itself did not carry the recorded window, so the assertions above prove nothing ($(cat "$TMUX_LOG"))"; assertion

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
# inference still reaches only the picker in the child (lane-collision-protocol
# Amendment 18 Addendum 1) and is still asked about there. Pre-answering that
# question in the parent is exactly what act 1 step 3's fence exists to
# prevent, and it is no better done at step 2.
grep -q 'CLAUDE_LANE=' "$TMUX_LOG" \
    && fail "act 1 step 1: the parent's own resolution was handed to the child as the operator's word ($(cat "$TMUX_LOG"))"; assertion

# 2c-i. ...AND SO DOES `CLAUDE_LANE_DIR`, THE OTHER SPELLING OF `--dir`.
# `--help` advertises the two as the same thing, and `tmux new-session` hands
# its command the SERVER's environment rather than this client's — which is why
# every other value is written into the command string — so an operator who
# exported `CLAUDE_LANE_DIR` and launched from OUTSIDE tmux lost it at the
# re-exec while `--dir` survived. (Raised by the round-3 pass as the residue
# behind its fifth "not real" item, as a doc-side nit; it is one line either
# way, and threading it is the half that keeps `--help` honest.)
tty_launch "TMUX=" "FAKE_TMUX_WINDOW=claude" "FAKE_SWAPPED_STATUS=8" \
    "CLAUDE_LANE_DIR=$TEST_ROOT/projects/openRepoProject" \
    -- --lane mine-5 run team002 --resume session-envdir-reexec
grep -Fq "CLAUDE_LANE_DIR=$TEST_ROOT/projects/openRepoProject" "$TMUX_LOG" \
    || fail "re-exec: CLAUDE_LANE_DIR did not cross into the session, so --help's 'also settable as' is false outside tmux ($(cat "$TMUX_LOG"))"; assertion

# 2c-ii. ...and `--dir` still WINS where both are given, which is the directory
# order's rung 1 read in its own order.
tty_launch "TMUX=" "FAKE_TMUX_WINDOW=claude" "FAKE_SWAPPED_STATUS=8" \
    "CLAUDE_LANE_DIR=$TEST_ROOT/projects/from-env" \
    -- --dir "$TEST_ROOT/projects/openRepoProject" --lane mine-5 run team002 --resume session-envdir-loses
grep -Fq "CLAUDE_LANE_DIR=$TEST_ROOT/projects/openRepoProject" "$TMUX_LOG" \
    || fail "re-exec: --dir did not beat CLAUDE_LANE_DIR across the re-exec ($(cat "$TMUX_LOG"))"; assertion
grep -Fq 'from-env' "$TMUX_LOG" \
    && fail "re-exec: the environment's directory beat the operator's own --dir ($(cat "$TMUX_LOG"))"; assertion

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
# here; one that reads the rule through the helper finds no exact match and
# falls all the way to THE PICKER (Amendment 18 Addendum 1) — proven on a real
# terminal with a refusing `lane`, so the picker's own log and the bare Claude
# behind its refusal are the assertions that fail if the old parse comes back.
tty_launch "FAKE_TMUX_WINDOW=zsh" "FAKE_LANE_WITH_ROW=nothing" \
    "FAKE_TMUX_WINDOW_ID=@97" "FAKE_TMUX_WINDOW_REF=claude-y:0" \
    "FAKE_WINDOW_LANE_NONE=1" "FAKE_LANE_EXIT=2" \
    -- run team002 --resume session-helperonly
grep -Fq 'mine-5' "$LANE_START_LOG" \
    && fail "helper is the read: the launcher parsed the swapped rows itself ('$(lane_start_argv)')"; assertion
[[ -e "$LANE_PICKER_LOG" ]] \
    || fail "helper is the read: it did not fall all the way to the picker"; assertion
[[ ! -e "$LANE_START_LOG" ]] \
    || fail "helper is the read: lane-start was invoked ('$(lane_start_argv)')"; assertion
grep -Fxq -- "$claude_args --resume session-helperonly" "$CLAUDE_LOG" \
    || fail "helper is the read: Claude did not receive its arguments unchanged"; assertion

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

# 3c. MUTATION — NOTHING NAMES THIS WINDOW, so THE PICKER (Amendment 18
# Addendum 1) is reached — not skipped, not silently answered bare. The whole
# value of step 3 is that a lane it cannot confirm is not taken on its own
# say-so; a launcher that took ANY guess bare because step 3 had merely been
# TRIED would have turned the picker's own question into silence.
tty_launch "FAKE_TMUX_WINDOW=zsh" "FAKE_LANE_WITH_ROW=nothing" \
    "FAKE_TMUX_WINDOW_ID=@55" "FAKE_TMUX_WINDOW_REF=nobody:9" \
    "FAKE_WINDOW_LANE_NONE=1" "FAKE_LANE_EXIT=0" \
    -- run team002 --resume session-noexact
[[ -e "$LANE_PICKER_LOG" ]] || fail "no exact record: the picker was never reached"; assertion
[[ -z "$(lane_picker_argv)" ]] \
    || fail "no exact record: lane argv was '$(lane_picker_argv)', not bare"; assertion
[[ "$launch_status" -eq 0 ]] \
    || fail "no exact record: the launcher exited $launch_status instead of lane's own 0"; assertion
[[ ! -e "$LANE_START_LOG" ]] \
    || fail "no exact record: this launcher also ran lane-start ('$(lane_start_argv)')"; assertion

# 3c-i. DEGRADATION — TODAY'S ESTATE. A `lanes-edit.sh` predating Amendment 11
# has no `window-lane` subcommand at all: it prints its unknown-subcommand line
# and exits 2, exactly as a pre-Amendment-8 one did for `swapped`. That 2 is an
# OLD HELPER and is EXPECTED AND SILENT — not a caller's bug, not a notice —
# and the order falls to THE PICKER, which answers today on every workstation
# whose helper is not yet upgraded.
tty_launch "FAKE_TMUX_WINDOW=zsh" "FAKE_LANE_WITH_ROW=nothing" \
    "FAKE_TMUX_WINDOW_ID=@97" "FAKE_TMUX_WINDOW_REF=claude-y:0" \
    "FAKE_LANE_EXIT=8" \
    -- run team002 --resume session-oldhelper
[[ -e "$LANE_PICKER_LOG" ]] || fail "old helper: it did not fall to the picker"; assertion
[[ "$launch_status" -eq 8 ]] \
    || fail "old helper: the launcher exited $launch_status instead of lane's own 8"; assertion
grep -Fq 'window-lane' "$TEST_ROOT/typescript.log" \
    && fail "old helper: a helper predating Amendment 11 was reported as a fault ($(cat "$TEST_ROOT/typescript.log"))"; assertion

# 3c-ii. MUTATION — A FAILED READ FALLS TO THE NEXT STEP, NOT TO STEP 5, AND
# NAMES ITSELF, EVEN WHEN THAT NEXT STEP GOES ON TO SUCCEED. SPEC §2: "A failed
# read falls to the NEXT step, not to step 5 … dropping to 5 would skip step 4,
# which answers today on every workstation whose helper is not yet upgraded."
# 64 is the helper's own usage error and it says nothing about unknown
# subcommands, so it is a caller's bug: one line, named on the way to the
# picker below it — and not swallowed by the picker's own exit 8, which never
# reaches precedence 5's own flush of the same note.
tty_launch "FAKE_TMUX_WINDOW=zsh" "FAKE_LANE_WITH_ROW=nothing" \
    "FAKE_TMUX_WINDOW_ID=@97" "FAKE_TMUX_WINDOW_REF=claude-y:0" \
    "FAKE_WINDOW_LANE_STATUS=64" "FAKE_LANE_EXIT=8" \
    -- run team002 --resume session-failedread
[[ -e "$LANE_PICKER_LOG" ]] || fail "failed read: it did not fall to the picker"; assertion
[[ "$launch_status" -eq 8 ]] \
    || fail "failed read: the launcher exited $launch_status instead of lane's own 8"; assertion
grep -Fq 'window-lane' "$TEST_ROOT/typescript.log" \
    || fail "failed read: it was not named ($(cat "$TEST_ROOT/typescript.log"))"; assertion
grep -Fq "$note" "$TEST_ROOT/typescript.log" \
    && fail "failed read: it printed step 5's no-lane notice instead of naming itself alone"; assertion

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

# 4b-iii. RUNG 2 READ OUT OF THE RECORD SPEC rev 3 ACTUALLY WRITES — the
# "tolerant reader beside `lane_dir_field`" SPEC §13.2 owes this PR. The payload
# gained `profile <name>` (`R-A11-10`) between `dir` and `workstation`, so the
# dir reader now has a sub-field on BOTH sides of it; a reader that ran to the
# end of the line instead of stopping at the `;` would hand `lane-start` a
# directory with two more sub-fields glued to it, and every scenario above would
# still pass because none of them writes a record with anything after the `dir`.
launch "FAKE_TMUX_WINDOW=zsh" "FAKE_LANE_WITH_ROW=nothing" \
    "FAKE_TMUX_WINDOW_ID=@97" \
    "FAKE_WINDOW_LANE_MAP=@97=mine-5" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=mine-5\t2026-09-13T03:31:33Z\tswap; window claude-y:0 @97; dir $RECORD_TREE; profile team-002; workstation Eagle\n" \
    -- run team002 --resume session-dirfullpayload
grep -Fxq -- "--dir $RECORD_TREE mine-5 -- $claude_args --resume session-dirfullpayload" "$LANE_START_LOG" \
    || fail "§5 payload: the dir reader did not stop at the sub-field that follows it ('$(lane_start_argv)')"; assertion
grep -Fq 'profile' "$LANE_START_LOG" \
    && fail "§5 payload: a sub-field beside the directory was read as part of it ('$(lane_start_argv)')"; assertion

# 4b-iv. ...and the TAB form of the same record. SPEC rev 3 §11 gives `swapped`
# a fourth `<dir>` field and a FIFTH `<profile>`; the dir is the fourth and a
# fifth column must not move it.
launch "FAKE_TMUX_WINDOW=zsh" "FAKE_LANE_WITH_ROW=nothing" \
    "FAKE_TMUX_WINDOW_ID=@97" \
    "FAKE_WINDOW_LANE_MAP=@97=mine-5" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=mine-5\t2026-09-13T03:31:33Z\tclaude-y:0 @97\t$RECORD_TREE\tteam-002\n" \
    -- run team002 --resume session-dirfifthfield
grep -Fxq -- "--dir $RECORD_TREE mine-5 -- $claude_args --resume session-dirfifthfield" "$LANE_START_LOG" \
    || fail "§11: a fifth <profile> column moved the fourth <dir> one ('$(lane_start_argv)')"; assertion

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
# whatever the launcher learnt. The probe is the same `--help` read every
# capability check in this launcher shares, and a probe nothing tests is a
# probe that lies.
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
# ...and the line it printed does not claim a gap it does not have. The rung-4
# notice (4m-iii) is a fact about THIS launch, so a launch that entered a
# directory must not carry it: a notice that fires everywhere is read nowhere.
grep -Fq 'no directory is recorded' "$ERR_LOG" \
    && fail "evidence 3, bare drop: the drop's line claims no directory is recorded although $RECORD_TREE was entered ('$(cat "$ERR_LOG")')"; assertion

# 4m-ii. AND RUNG 4 ENTERS NOTHING. Where no directory was learnt there is
# nothing to enter, and the launch is byte-for-byte what it was before
# Amendment 11: lane-start derives its own default from where it stands.
launch "FAKE_TMUX_WINDOW=openRepoProject-1" "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    "FAKE_SWAPPED_STATUS=8" \
    -- run team002 --resume session-nodircd
grep -Fxq "$TEST_ROOT" "$LANE_START_CWD_LOG" \
    || fail "rung 4: the launcher moved to '$(cat "$LANE_START_CWD_LOG" 2>/dev/null)' although it learnt no directory"; assertion

# 4m-iii. ...AND IT SAYS SO, IN THE ONE LINE IT ALREADY PRINTS. The other half
# of Evidence 3: where `lane-start` TAKES the lane it cds for its own launch and
# there is nothing to report, but where it refuses, the bare Claude of SPEC §2's
# run-not-exec drop starts wherever this was typed — and that session loads
# neither the repository's CLAUDE.md nor the lane's memory while `--resume`
# still continues the transcript, which is exactly why nobody noticed for an
# afternoon. So the launcher names the gap and names `--dir`, and it does it
# INSIDE the drop's own line: one situation, ONE line (F-W3, `R-A8-7`).
launch "FAKE_TMUX_WINDOW=zsh" "FAKE_LANE_WITH_ROW=nothing" "FAKE_SWAPPED_STATUS=8" \
    "FAKE_LANE_START_STATUS=1" \
    -- --lane mine-5 run team002 --resume session-nodir-note
grep -q -- '--dir' "$LANE_START_LOG" \
    && fail "rung 4: a directory was invented ($(lane_start_argv))"; assertion
grep -Fq 'no directory is recorded for mine-5' "$ERR_LOG" \
    || fail "Evidence 3: the launcher does not say it could not learn the lane's directory ('$(cat "$ERR_LOG")')"; assertion
grep -Fq -- '--dir <path>' "$ERR_LOG" \
    || fail "Evidence 3: the notice does not name the one word that fixes it ('$(cat "$ERR_LOG")')"; assertion
# opensoft/workBenches#95 adds ONE line ahead of both of these — the capture
# path, printed before every lane-start invocation regardless of how it
# turns out — so "beside lane-start's own" is now 3, not 2: the breadcrumb,
# lane-start's own refusal (tee'd through), and this launcher's one note.
[[ "$(wc -l < "$ERR_LOG")" -eq 3 ]] \
    || fail "Evidence 3: one situation printed $(wc -l < "$ERR_LOG") lines beside lane-start's own and the capture breadcrumb ($(cat "$ERR_LOG"))"; assertion
grep -Fxq -- "$claude_args --resume session-nodir-note" "$CLAUDE_LOG" \
    || fail "Evidence 3: the pane was left with no Claude in it"; assertion

# 4m-iv. ...and where `lane-start` TAKES the lane, nothing is said at all: it
# cds for its own launch, so the session is keyed to the directory it chose and
# a line here would be a warning about a thing that did not happen.
launch "FAKE_TMUX_WINDOW=zsh" "FAKE_LANE_WITH_ROW=nothing" "FAKE_SWAPPED_STATUS=8" \
    "FAKE_LANE_START_DECLINE=took" \
    -- --lane mine-5 run team002 --resume session-nodir-took
grep -Fq 'no directory is recorded' "$ERR_LOG" \
    && fail "rung 4: a launch lane-start took was warned about a directory nothing needed ('$(cat "$ERR_LOG")')"; assertion

# 4m-v. AND A LAUNCH THAT TAKES NO LANE MOVES NOTHING AND IS TOLD NOTHING.
# `--no-lane` is byte-for-byte today's behaviour, which is the test that this
# act added no fifth rung by the back door: a record for some lane is right
# there and neither its directory nor its name is used.
launch "FAKE_TMUX_WINDOW=zsh" "FAKE_LANE_WITH_ROW=nothing" "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=mine-5\t2026-09-13T03:31:33Z\tclaude-y:0 @97\t$RECORD_TREE\n" \
    -- --no-lane run team002 --resume session-nolane-dir
grep -Fxq "$TEST_ROOT" "$CLAUDE_CWD_LOG" \
    || fail "--no-lane: the launcher entered a directory for a launch that took no lane ('$(cat "$CLAUDE_CWD_LOG" 2>/dev/null)')"; assertion
grep -Fq 'directory' "$ERR_LOG" \
    && fail "--no-lane: a launch that took no lane was told about some lane's directory ($(cat "$ERR_LOG"))"; assertion

# 4m-vi. `restart <lane>`'s OWN CALL SHAPE (decision 7, `R-A11-10`): the
# launcher accepts being called as `pclaude --lane <lane> <profile>`, takes the
# lane from the operator's word with NO question, learns the directory from that
# lane's own record, enters it, and says nothing OF ITS OWN beyond the one
# capture-path breadcrumb opensoft/workBenches#95 now prints ahead of every
# lane launch, clean or not. That is the whole of what the tooling PR's
# `restart` needs from this half.
launch "FAKE_TMUX_WINDOW=zsh" "FAKE_LANE_WITH_ROW=nothing" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=mine-5\t2026-09-13T03:31:33Z\tclaude-y:0 @97\t$RECORD_TREE\n" \
    -- --lane mine-5 run team002 --resume session-restart-shape
grep -Fxq -- "--dir $RECORD_TREE mine-5 -- $claude_args --resume session-restart-shape" "$LANE_START_LOG" \
    || fail "restart's call shape: lane-start argv was '$(lane_start_argv)'"; assertion
grep -q -- '--confirm' "$LANE_START_LOG" \
    && fail "restart's call shape: the operator's own --lane was handed over as a guess to confirm ($(lane_start_argv))"; assertion
grep -Fxq "$RECORD_TREE" "$LANE_START_CWD_LOG" \
    || fail "restart's call shape: lane-start ran in '$(cat "$LANE_START_CWD_LOG" 2>/dev/null)' and not in the lane's own tree"; assertion
[[ "$(grep -c '^pclaude:' "$ERR_LOG")" -eq 1 ]] \
    || fail "restart's call shape: this launcher had $(grep -c '^pclaude:' "$ERR_LOG" 2>/dev/null) things of its own to say, not just the capture breadcrumb ('$(cat "$ERR_LOG")')"; assertion
grep -Fq 'lane defect capture:' "$ERR_LOG" \
    || fail "restart's call shape: the capture-path breadcrumb itself is missing ('$(cat "$ERR_LOG")')"; assertion

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
# inference the CHILD now hands to the picker (lane-collision-protocol
# Amendment 18 Addendum 1) rather than to lane-start; act 1 already refuses to
# name the window from it, and the directory is the same rule. Standing
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
# opensoft/workBenches#95 adds the capture-path breadcrumb ahead of both of
# these, so 3 lines is now the whole of "one situation" here, not 2.
[[ "$(wc -l < "$ERR_LOG")" -eq 3 ]] \
    || fail "evidence 2: one situation printed $(wc -l < "$ERR_LOG") lines beside lane-start's own and the capture breadcrumb ($(cat "$ERR_LOG"))"; assertion

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
# (The lane is the operator's own `--lane`, not a record: this property is
# about the exit-status passthrough once ANY lane is taken, and precedence 4 —
# THE PICKER since Amendment 18 Addendum 1 — no longer reaches lane-start at
# all, so it is no longer a vehicle for reaching this arm.)
WINDOW_FILE="$TEST_ROOT/tmux-window.name"
printf 'zsh\n' > "$WINDOW_FILE"
launch "FAKE_TMUX_WINDOW_FILE=$WINDOW_FILE" "FAKE_LANE_WITH_ROW=nothing" \
    "FAKE_LANE_START_DECLINE=took" "FAKE_LANE_START_STATUS=1" \
    -- --lane mine-5 run team002 --resume session-claude-exited-1
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
# lane this window never took. The RAW `CLAUDE_LANE`/`CLAUDE_LANE_DIR` go with
# it — they are read at precedence 1 and at the directory order's rung 1, so a
# nested `pclaude` inside that Claude would otherwise re-select the very lane
# lane-start just refused (clause (g), non-blocking 3).
# The lane is given as `CLAUDE_LANE`/`CLAUDE_LANE_DIR` rather than as `--lane`
# BECAUSE THAT IS THE SHAPE THE RESIDUE HAS: `--lane` leaves nothing in the
# environment to inherit, so a suite that only ever typed the flag could not
# see the raw inputs survive. `--help` documents the two spellings as the same
# thing, and they resolve to the same `lane`.
launch "FAKE_TMUX_WINDOW=claude" "FAKE_LANE_WITH_ROW=nothing" "FAKE_SWAPPED_STATUS=8" \
    "FAKE_LANE_START_STATUS=1" \
    "CLAUDE_LANE=openXfactory-5" "CLAUDE_LANE_DIR=$TEST_ROOT/projects/openXfactory" \
    -- run team002 --print env-check
grep -Fxq -- "$claude_args --print env-check" "$CLAUDE_LOG" \
    || fail "identity after a refusal: Claude did not start"; assertion
lane_start_argv | grep -Fq 'openXfactory-5' \
    || fail "identity after a refusal: CLAUDE_LANE did not reach lane-start as the lane ($(lane_start_argv))"; assertion
grep -Fxq 'WORKBENCHES_CLAUDE_LANE=<unset>' "$CLAUDE_ENV_LOG" \
    || fail "clause (g): the Claude behind a lane-start refusal came up holding the lane it refused ($(cat "$CLAUDE_ENV_LOG"))"; assertion
grep -Fxq 'CLAUDE_LANE=<unset>' "$CLAUDE_ENV_LOG" \
    || fail "clause (g): the raw CLAUDE_LANE survived the refusal, so a nested pclaude re-selects it at precedence 1 ($(cat "$CLAUDE_ENV_LOG"))"; assertion
grep -Fxq 'CLAUDE_LANE_DIR=<unset>' "$CLAUDE_ENV_LOG" \
    || fail "clause (g): the raw CLAUDE_LANE_DIR survived the refusal, so a nested pclaude takes the refused lane's directory at rung 1 ($(cat "$CLAUDE_ENV_LOG"))"; assertion

# 5f-i. `--no-lane` DOES NOT INHERIT A LANE. The operator's own word takes no
# lane, and until this round `export_lane_identity` only ever ADDED: a
# `[[ -z $lane ]] || export` leaves an inherited marker exactly where it was, so
# a nested `pclaude --no-lane <profile>` came up carrying the OUTER session's
# lane and the automatic swap would have swapped it. The guard states the
# contract itself (`claude-usage-guard.sh:146-148`): "exported by claude-profile
# only after lane-start took the lane and UNSET again where lane-start declined
# it".
launch "FAKE_TMUX_WINDOW=claude" "FAKE_SWAPPED_STATUS=8" \
    "WORKBENCHES_CLAUDE_LANE=openRepoProject-1" \
    "WORKBENCHES_CLAUDE_LANE_SOURCE=window" \
    "WORKBENCHES_CLAUDE_LANE_DIR=$TEST_ROOT/projects/openRepoProject" \
    "CLAUDE_LANE=openRepoProject-1" \
    -- --no-lane run team002 --resume session-nolane-inherit
grep -Fxq -- "$claude_args --resume session-nolane-inherit" "$CLAUDE_LOG" \
    || fail "--no-lane: Claude did not start"; assertion
grep -Fxq 'WORKBENCHES_CLAUDE_LANE=<unset>' "$CLAUDE_ENV_LOG" \
    || fail "clause (g): --no-lane came up holding the outer session's lane ($(cat "$CLAUDE_ENV_LOG"))"; assertion
grep -Fxq 'WORKBENCHES_CLAUDE_LANE_SOURCE=<unset>' "$CLAUDE_ENV_LOG" \
    || fail "clause (g): --no-lane kept an inherited lane SOURCE ($(cat "$CLAUDE_ENV_LOG"))"; assertion
grep -Fxq 'WORKBENCHES_CLAUDE_LANE_DIR=<unset>' "$CLAUDE_ENV_LOG" \
    || fail "clause (g): --no-lane kept an inherited lane directory ($(cat "$CLAUDE_ENV_LOG"))"; assertion
grep -Fxq 'CLAUDE_LANE=<unset>' "$CLAUDE_ENV_LOG" \
    || fail "clause (g): --no-lane left the raw CLAUDE_LANE for a nested pclaude to read at precedence 1 ($(cat "$CLAUDE_ENV_LOG"))"; assertion

# 5f-ii is RETIRED (lane-collision-protocol Amendment 18 Addendum 1, clause
# (i-5)): it pinned that a `--confirm` lane — precedence 4's swap-record guess,
# published to `WORKBENCHES_CLAUDE_LANE` only once lane-start's answer was
# known to be a take rather than a decline (clause (g)'s "the lane the launcher
# ALREADY KNOWS it handed over") — was withheld from the environment until
# then. Precedence 4 no longer produces a lane THIS launcher hands to
# lane-start at all: it hands the pane to `lane` and exits with `lane`'s own
# status before `export_lane_identity` ever runs, or falls through with `lane`
# empty. There is no longer a `--confirm` lane for this function to gate on,
# which is exactly what `export_lane_identity`'s own comment says now — so the
# scenario that pinned the gate is retired with the code path it pinned, rather
# than kept pointed at a branch that can no longer be reached.

# 5f-iii. ...AND THE FENCE IS NOT A GATE. The three CERTAIN sources — the
# operator's `--lane`, the window's own name and the record naming THIS window
# — all reach lane-start BARE, with no question for anybody to decline, so all
# three publish the marker. A fence that withheld it from them would take the
# automatic swap away from every lane on the estate, which is the mutation that
# matters here.
launch "FAKE_TMUX_WINDOW=openRepoProject-1" "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    "FAKE_SWAPPED_STATUS=8" "FAKE_LANE_START_DECLINE=took" \
    -- run team002 --resume session-window-certain
lane_start_argv | grep -Fq -- '--confirm' \
    && fail "confirm: a window-name lane was handed over as a question ($(lane_start_argv))"; assertion
grep -Fxq 'WORKBENCHES_CLAUDE_LANE=openRepoProject-1' "$LANE_START_ENV_LOG" \
    || fail "clause (g): a CERTAIN lane was not published, so the automatic swap is fenced off from the lanes it is for ($(cat "$LANE_START_ENV_LOG"))"; assertion

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

# 5g-ii. RV-W3 IS CLOSED, NOT DOCUMENTED — `R-A11-16` (A11 Addendum 3, ratified
# by Brett Heap 2026-09-13 "a11 addendum 3 yes"). THE THIRD DOOR: a window whose
# only command is `pclaude` and which this launcher did NOT create — `tmux
# new-window -n <lane> 'pclaude <profile>'`, a tmux config line, a pane
# respawned by hand. There is no WORKBENCHES_CLAUDE_TMUX_CHILD, so the old fence
# could not tell that window from a shell's and handed the refusal back, leaving
# tmux to print `[exited]` over a window with no Claude in it. The pane itself
# now answers: `#{pane_pid}` is the process tmux started for it, and this
# process's ancestry reaches it through nothing but this launcher.
ps_launcher_args="*=/bin/bash $LAUNCHER run team002"
launch "TMUX=fake-session" "TMUX_PANE=%9" "PATH=$PS_BIN:$FAKE_BIN:/usr/bin:/bin" \
    "FAKE_TMUX_PANE_PID=4242" "FAKE_PS_ARGS=$ps_launcher_args" "FAKE_PS_PPID=*=4242" \
    "FAKE_TMUX_WINDOW=openXfactory-5" "FAKE_LANE_WITH_ROW=openXfactory-5" \
    "FAKE_SWAPPED_STATUS=8" "FAKE_LANE_START_STATUS=1" \
    -- run team002 --resume session-third-door
grep -Fxq -- "openXfactory-5 -- $claude_args --resume session-third-door" "$LANE_START_LOG" \
    || fail "third door: lane-start argv was '$(lane_start_argv)'"; assertion
grep -Fxq -- "$claude_args --resume session-third-door" "$CLAUDE_LOG" \
    || fail "RV-W3/R-A11-16: the pane whose only command is pclaude was left with no Claude in it — [exited] ($(cat "$CLAUDE_LOG" 2>/dev/null))"; assertion
[[ "$launch_status" -eq 0 ]] \
    || fail "RV-W3/R-A11-16: the launcher exited $launch_status in a pane it is the only command of"; assertion
grep -q 'did not take openXfactory-5 (exit 1)' "$ERR_LOG" \
    || fail "third door: the notice was '$(cat "$ERR_LOG")'"; assertion

# 5g-iii. ...AND THE WALK STOPS AT A COMMAND OF ITS OWN, which is what keeps
# 5g-i true. The same pane, the same lane, the same refusal — but the process
# tmux started for the pane is a SHELL, so there is a prompt behind this
# process, the status is handed back under lane-start's own words, and no bare
# Claude is minted behind a session that may still be the lane's.
launch "TMUX=fake-session" "TMUX_PANE=%9" "PATH=$PS_BIN:$FAKE_BIN:/usr/bin:/bin" \
    "FAKE_TMUX_PANE_PID=4242" "FAKE_PS_ARGS=$(printf '4242=-zsh\n%s' "$ps_launcher_args")" \
    "FAKE_PS_PPID=*=4242" \
    "FAKE_TMUX_WINDOW=openXfactory-5" "FAKE_LANE_WITH_ROW=openXfactory-5" \
    "FAKE_SWAPPED_STATUS=8" "FAKE_LANE_START_STATUS=1" \
    -- run team002 --resume session-shell-behind
[[ ! -e "$CLAUDE_LOG" ]] \
    || fail "R-A11-16: a bare Claude was started behind a shell's own prompt ($(cat "$CLAUDE_LOG"))"; assertion
[[ "$launch_status" -eq 1 ]] \
    || fail "R-A11-16: the launcher exited $launch_status instead of handing 1 back to the prompt behind it"; assertion

# 5g-iv. EVIDENCE 7 — THE AUTO-SELECTED LANE WHOSE CHECKOUT IS NESTED
# (2026-09-13T23:01:02Z, `brettheap/new-workstation#20` issuecomment-5656793094).
# Reported by Brett Heap from another session, on the LIVE Amendment 8 launcher:
# `pclaude team03m` in a window that is not a lane, the swap record named
# `opsXfactory-5`, and `lane-start:336` — `DIR="$PROJECTS_ROOT/$repo"` where no
# `--dir` was passed — derived `/home/brett/projects/opsXfactory`, which does not
# exist. The lane's real checkout is nested: `~/projects/xFactory/xFactories/
# OpsxFactory`. lane-start exited 1, the A8 launcher had EXEC'd it, and tmux
# printed `[exited]` over a window with no Claude in it. The operator saw NO
# WORDS AT ALL and had to guess at `--no-lane`.
#
# It is Evidence 2's defect through the RECORD door, and the record's own `dir`
# is absent because no Amendment 11 writer has written one for that lane yet:
# its PAUSED line carries `window …; workstation docker-desktop` and no `dir`.
# So the composition is what matters and no existing scenario has it — an
# AUTO-SELECTED lane the operator never typed, RUNG 4 of the directory order
# (no `dir` in the row and a helper with no `lane-dir`), and lane-start's
# environment refusal. Three halves each covered elsewhere; the report is the
# three at once.
#
# THE DOOR IT WALKED THROUGH IS RETIRED, THE SHAPE IS NOT (lane-collision-
# protocol Amendment 18 Addendum 1, clause (i-5)). `opsXfactory-5` reached
# lane-start unconfirmed here because it was the workstation's newest SWAP
# record — a guess this launcher made silently and handed to `lane-start
# --confirm`. That door is gone: precedence 4 is `lane`, asked of a person, and
# a person asked is not an operator surprised by a lane they never typed. The
# nearest door an auto-selected, UNCONFIRMED lane still reaches lane-start
# through is precedence 3 — the record whose `window` field names THIS window
# exactly, certain enough that it goes bare — and the fix Evidence 7 forced
# does not care which door the lane came through: SPEC §2's run-not-exec, the
# one-line notice, and RUNG 4's silence where the record carries no `dir` are
# general to every lane this launcher hands to lane-start.
#
# WHAT THIS HEAD OWES, and it is not "print `--no-lane`": `--no-lane` was the
# interim because the exec left nothing running. Here the launch is RUN, not
# exec'd (SPEC §2), so the window keeps a Claude and the operator needs no
# escape at all. What they need is to be TOLD, in one line, which lane was
# taken, that lane-start refused it, and the one word that fixes it for good —
# `--dir`, which is also what writes the record's field on the next swap.
launch "FAKE_TMUX_WINDOW=zsh" "FAKE_LANE_WITH_ROW=nothing" \
    "FAKE_TMUX_WINDOW_ID=@97" "FAKE_WINDOW_LANE_MAP=@97=opsXfactory-5" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=opsXfactory-5\t2026-09-13T22:31:00Z\tclaude-y:0 @97; workstation docker-desktop\n" \
    "FAKE_LANE_START_STATUS=1" \
    -- run team002 --resume session-evidence7
lane_start_argv | grep -Fq -- '--confirm' \
    && fail "Evidence 7: an exact window match was handed over as a question ($(lane_start_argv))"; assertion
lane_start_argv | grep -Fq -- '--dir' \
    && fail "Evidence 7: a record carrying no dir produced one anyway ($(lane_start_argv))"; assertion
grep -Fxq -- "opsXfactory-5 -- $claude_args --resume session-evidence7" "$LANE_START_LOG" \
    || fail "Evidence 7: lane-start argv was '$(lane_start_argv)'"; assertion
grep -Fxq -- "$claude_args --resume session-evidence7" "$CLAUDE_LOG" \
    || fail "Evidence 7: the window was left with no Claude in it — [exited], which is the whole report ($(cat "$CLAUDE_LOG" 2>/dev/null))"; assertion
[[ "$launch_status" -eq 0 ]] \
    || fail "Evidence 7: the launcher exited $launch_status over a Claude that started"; assertion
grep -q 'did not take opsXfactory-5 (exit 1)' "$ERR_LOG" \
    || fail "Evidence 7: the operator was not told which lane was refused ('$(cat "$ERR_LOG")')"; assertion
grep -Fq -- '--dir' "$ERR_LOG" \
    || fail "Evidence 7: the notice named no way to fix the lane's directory ('$(cat "$ERR_LOG")')"; assertion
grep -Fq 'lane-start: refused (fake)' "$ERR_LOG" \
    || fail "Evidence 7: lane-start's own refusal was swallowed, so the derived path it names never reached the operator"; assertion

# 5g-v. ...AND WITH THE FIELD PRESENT THE DERIVATION NEVER HAPPENS. The same
# auto-selected, unconfirmed lane, but the row carries the `dir` Amendment 11
# adds — which is what `#26`'s writer will put there the first time this lane
# is swapped from a `lane-start --dir` launch. `lane-start:336`'s
# `$PROJECTS_ROOT/$repo` branch is not reached at all, so the nested checkout is
# not a special case: it is just the path in the record.
launch "FAKE_TMUX_WINDOW=zsh" "FAKE_LANE_WITH_ROW=nothing" \
    "FAKE_TMUX_WINDOW_ID=@97" "FAKE_WINDOW_LANE_MAP=@97=opsXfactory-5" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=opsXfactory-5\t2026-09-13T22:31:00Z\tswap; window claude-y:0 @97; dir $RECORD_TREE; workstation docker-desktop\n" \
    -- run team002 --resume session-evidence7-dir
grep -Fxq -- "--dir $RECORD_TREE opsXfactory-5 -- $claude_args --resume session-evidence7-dir" "$LANE_START_LOG" \
    || fail "Evidence 7: the record's dir did not reach lane-start on the exact-match path ($(lane_start_argv))"; assertion
grep -Fxq "$RECORD_TREE" "$LANE_START_CWD_LOG" \
    || fail "Evidence 7: the launcher did not enter the recorded checkout before launching ($(cat "$LANE_START_CWD_LOG"))"; assertion

# 5i. EVIDENCE 4 — THE BARE DROP CARRIES NO NAME, AND NO `--resume`. Measured
# on this lane today: the transcript's `customTitle` is the lane, but every
# process that resumed it through a bare `claude --resume <uuid>` has a DERIVED
# record name (`openrepoproject-b9`, `-1e`, `-27`, `-45`), and that derived name
# is what the statusline and `ListAgents` show. `lane-start` passes `--name
# <lane>` on every launch it makes, so the third leg of the identity triple is
# set whenever the restart goes THROUGH lane-start and lost whenever it does
# not. The launcher's answer is in two halves, and this is the second: the drop
# behind a refusal is a session with NO LANE, so it must not be named for one —
# a Claude named `<lane>` that lane-start declined to take would put the lane's
# own messaging address (Amendment 2) on a session the register does not know.
# The first half is that every lane path runs lane-start; that is section 5's
# matrix, and §6c audits that nothing here ever spells the bare resume itself.
launch "WORKBENCHES_CLAUDE_TMUX_CHILD=1" \
    "WORKBENCHES_CLAUDE_WINDOW=matrix-1" \
    "FAKE_TMUX_WINDOW=matrix-1" "FAKE_LANE_WITH_ROW=matrix-1" \
    "FAKE_SWAPPED_STATUS=8" "FAKE_LANE_START_STATUS=2" \
    -- run team002
[[ "$(cat "$CLAUDE_LOG")" == "$claude_args" ]] \
    || fail "evidence 4: the bare drop's argv was '$(cat "$CLAUDE_LOG")', not the flags and nothing else"; assertion
grep -Fq -- '--name' "$CLAUDE_LOG" \
    && fail "evidence 4: the drop named a session for a lane lane-start refused to take"; assertion
grep -Fq -- '--resume' "$CLAUDE_LOG" \
    && fail "evidence 4: the launcher resumed a transcript of its own choosing"; assertion

# 5h. THE WHOLE MATRIX, ASSERTED RATHER THAN ARGUED. Every lane source this
# launcher itself still hands to lane-start, crossed with both of lane-start's
# documented refusals, IN A CHILD — which is every path on which this process
# is the only command of a tmux window and therefore every path that could
# print `[exited]`. Each cell must end with a Claude running and the launcher
# exiting 0. This is the scenario SPEC §2's "a launcher never refuses to start
# Claude" owes, and it is one loop rather than six paragraphs because the claim
# is about ALL of them. `record` — precedence 4's old swap-record guess — is
# gone from the list (lane-collision-protocol Amendment 18 Addendum 1, clause
# (i-5)): this launcher no longer hands lane-start a lane from that door at
# all, so it is no longer one of the sources this matrix is about.
for lane_case in flag window window-record; do
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
# feature is absent, Claude starts — AND THE LAUNCHER SAYS SO (Evidence 5).
#
# An estate that is not on PATH at all: no lane-start, no lanes-edit.sh, nothing
# this feature can read.
# `without_estate_env` is spliced in AFTER the fixed values, so a scenario that
# sets it wins: `env` applies its assignments left to right. It is what the
# install-act scenarios use to put an `openRepoTools` on PATH or to take the
# workspace manifest away, and it is reset by each caller that sets it.
without_estate_env=()
launch_without_estate() {
    reset_logs
    scenario
    set +e
    env "PATH=$TEST_ROOT/empty-bin:/usr/bin:/bin" \
        "HOME=$FAKE_HOME" "CLAUDE_BIN=$FAKE_CLAUDE" \
        "CLAUDE_PROFILES_HOME=$PROFILE_BASE" "CLAUDE_PROFILES_MANIFEST=$MANIFEST" \
        "FAKE_CLAUDE_LOG=$CLAUDE_LOG" "FAKE_CLAUDE_ENV_LOG=$CLAUDE_ENV_LOG" \
        "WORKBENCHES_SHARED_MCP_FAMILIES=disabled" \
        "WORKBENCHES_CLAUDE_TMUX_CHILD=1" "WORKBENCHES_CLAUDE_WINDOW=matrix-1" \
        ${without_estate_env[@]+"${without_estate_env[@]}"} \
        "$LAUNCHER" "$@" >"$OUT_LOG" 2>"$ERR_LOG"
    launch_status=$?
    set -e
}

launch_without_estate run team002 --resume session-no-lane-start
grep -Fxq -- "$claude_args --resume session-no-lane-start" "$CLAUDE_LOG" \
    || fail "no lane-start on PATH: the pane was left with no Claude in it ($(cat "$CLAUDE_LOG" 2>/dev/null))"; assertion
[[ "$launch_status" -eq 0 ]] \
    || fail "no lane-start on PATH: the launcher exited $launch_status"; assertion
# EVIDENCE 5 — AND IT IS SAID, ON THE FIRST LINE, WITH THE INSTALL ACT NAMED.
# Measured 2026-09-13T17:29:58Z: after this workstation was rebuilt the
# `~/.local/bin` links `scripts/link-estates` places were gone while
# `/usr/local/bin/claude-profile` was still there, so every restart took this
# branch — no stamp, a derived record name, a window left as `claude` — and
# said nothing three times in one afternoon, because `--resume <uuid>` went on
# continuing the right transcript. A launcher that cannot tell "never
# installed" from "the links vanished this morning" must state the fact rather
# than choose between them.
head -n 1 "$ERR_LOG" | grep -Fq 'lane-start is not on PATH' \
    || fail "Evidence 5: the missing tool is not named on the FIRST line ('$(cat "$ERR_LOG")')"; assertion
head -n 1 "$ERR_LOG" | grep -Fq 'NO LANE' \
    || fail "Evidence 5: the first line does not say what the launch degraded TO ('$(cat "$ERR_LOG")')"; assertion
grep -Fq 'scripts/link-estates' "$ERR_LOG" \
    || fail "Evidence 5: the install act is not named ('$(cat "$ERR_LOG")')"; assertion
# ...AND IT IS THIS MACHINE'S OWN WORKSPACE REPOSITORY, READ OUT OF
# `~/.agents/workspace.yaml` — `R-A11-13`. No openRepoTools is on this PATH, so
# the capability probe cannot answer and the act is the manifest's repository
# and its checkout. The hard-coded `git clone git@github.com:opensoft/brett-wip`
# this line used to print is one operator's estate printed at everybody else's.
grep -Fq "$TEST_ROOT/estate-wip/scripts/link-estates" "$ERR_LOG" \
    || fail "R-A11-13: the install act does not name the workspace repository ~/.agents/workspace.yaml names ('$(cat "$ERR_LOG")')"; assertion
grep -Fq 'brett-wip' "$ERR_LOG" \
    && fail "R-A11-13: the install act still names a repository this machine never chose ('$(cat "$ERR_LOG")')"; assertion
grep -Fq "$note" "$ERR_LOG" \
    && fail "Evidence 5: the standing no-lane note told the operator to run a command this machine does not have ('$(cat "$ERR_LOG")')"; assertion
# ONE SITUATION, ONE LINE — SPEC rev 5 §16(a) and the amendment text's rule (a)
# ("A8 gives the one-notice shape `pclaude: <reason>; <note>` … One situation,
# one line"). The reason and the act were on two lines; the act now rides on the
# reason's own line, which is also the FIRST line, so both halves of the ruling
# are on one read.
[[ "$(wc -l < "$ERR_LOG")" -eq 1 ]] \
    || fail "Evidence 5/§16(a): one situation printed $(wc -l < "$ERR_LOG") lines ($(cat "$ERR_LOG"))"; assertion
head -n 1 "$ERR_LOG" | grep -Fq 'fix:' \
    || fail "§16(a): the install act is not on the same line as the reason ('$(cat "$ERR_LOG")')"; assertion

# 5h-ii. ...AND `--no-lane` IS TOLD NOTHING. The operator said no lane, so there
# is no degradation to report: a notice that fires where nothing was lost is a
# notice that gets filtered out before the one that matters.
launch_without_estate --no-lane run team002 --resume session-no-estate-nolane
grep -Fxq -- "$claude_args --resume session-no-estate-nolane" "$CLAUDE_LOG" \
    || fail "no lane-start, --no-lane: Claude did not start"; assertion
[[ ! -s "$ERR_LOG" ]] \
    || fail "Evidence 5: a launch that asked for no lane was told the lane tool is missing ('$(cat "$ERR_LOG")')"; assertion

# 5h-iii. ...and neither is a launch that starts no conversation. `--print` is
# one of the forms `claude_args_start_session` excludes, and a one-shot takes no
# lane on a machine that HAS the estate either, so nothing here degraded.
launch_without_estate run team002 --print env-check
grep -Fxq -- "$claude_args --print env-check" "$CLAUDE_LOG" \
    || fail "no lane-start, --print: Claude did not start"; assertion
[[ ! -s "$ERR_LOG" ]] \
    || fail "Evidence 5: a one-shot that takes no lane anywhere was told the lane tool is missing ('$(cat "$ERR_LOG")')"; assertion

# 5h-iv. THE ACT IS NAMED BY CAPABILITY, AND THE CAPABILITY IS THE INSTALLED
# TOOL'S OWN `--help` — `R-A11-13` (A11 Addendum 3, ratified by Brett Heap
# 2026-09-13 "a11 addendum 3 yes"). An `openRepoTools` that LISTS the lane tools
# is their placer, and Amendment 9(b)'s act is the one to print: workBenches'
# setup.sh already runs `openRepoTools --install`, so the fix is a step this
# estate has rather than a second installer.
without_estate_env=(
    "PATH=$ORT_BIN:$TEST_ROOT/empty-bin:/usr/bin:/bin"
    "FAKE_OPENREPOTOOLS_HELP=$OPENREPOTOOLS_HELP_ACT3"
)
launch_without_estate run team002 --resume session-act3-openrepotools
without_estate_env=()
grep -Fq 'openRepoTools --install' "$ERR_LOG" \
    || fail "R-A11-13: an openRepoTools that places the lane tools is not the act named ('$(cat "$ERR_LOG")')"; assertion
grep -Fq 'link-estates' "$ERR_LOG" \
    && fail "R-A11-13: the superseded mechanism is named beside the one that works, so the operator has to decide which is current ('$(cat "$ERR_LOG")')"; assertion
[[ "$(wc -l < "$ERR_LOG")" -eq 1 ]] \
    || fail "R-A11-13/§16(a): one situation printed $(wc -l < "$ERR_LOG") lines ($(cat "$ERR_LOG"))"; assertion

# 5h-v. ...AND THE COPY INSTALLED TODAY IS NOT THAT PLACER. `/usr/local/bin/
# openRepoTools` on this workstation places park, resume, status and itself —
# its `--help` says "does nothing else", measured 2026-09-13 — so naming
# `--install` to an operator whose lane-start is missing hands them a command
# that cannot fix their machine. The interval act is the workspace repository's.
without_estate_env=(
    "PATH=$ORT_BIN:$TEST_ROOT/empty-bin:/usr/bin:/bin"
    "FAKE_OPENREPOTOOLS_HELP=$OPENREPOTOOLS_HELP_TODAY"
)
launch_without_estate run team002 --resume session-today-openrepotools
without_estate_env=()
grep -Fq "$TEST_ROOT/estate-wip/scripts/link-estates" "$ERR_LOG" \
    || fail "R-A11-13: an openRepoTools that cannot place the lane tools was named as the act anyway ('$(cat "$ERR_LOG")')"; assertion
grep -Fq 'openRepoTools --install' "$ERR_LOG" \
    && fail "R-A11-13: the act named cannot place lane-start on this machine ('$(cat "$ERR_LOG")')"; assertion
# ...AND THIS SCENARIO SAYS WHICH BRANCH IT IS ON. The checkout does not exist
# here (5h-vii creates it and removes it again), so the act is the CLONE form —
# and the substring above matches the clone form's tail just as well as the
# script-alone branch, which is exactly why the assertion above could not tell
# `:915` from `:917` and why `CF2-W11`'s cases below are separate scenarios.
grep -Fq "git clone git@github.com:opensoft/estate-wip.git" "$ERR_LOG" \
    || fail "R-A11-13: a checkout that is not there was not offered a clone ('$(cat "$ERR_LOG")')"; assertion
[[ ! -d "$TEST_ROOT/estate-wip" ]] \
    || fail "R-A11-13: this scenario is meant to run with the checkout ABSENT, and it is present"; assertion

# 5h-vi. ...AND A MACHINE THAT NAMES NO WORKSPACE REPOSITORY IS TOLD WHERE TO
# NAME ONE. `link-estates` on its own is a script inside a repository and not an
# act anybody can run, so the line names the FILE that decides which repository
# it is — never the bare word.
without_estate_env=("HOME=$TEST_ROOT/no-manifest-home")
launch_without_estate run team002 --resume session-no-manifest
without_estate_env=()
grep -Fq "$TEST_ROOT/no-manifest-home/.agents/workspace.yaml" "$ERR_LOG" \
    || fail "R-A11-13: with no workspace manifest the operator is not told where to name their repository ('$(cat "$ERR_LOG")')"; assertion
grep -Eq '(^|[^/])link-estates' "$ERR_LOG" \
    && fail "R-A11-13: the act is named as bare link-estates, with no repository in front of it ('$(cat "$ERR_LOG")')"; assertion

# 5h-vii. ...and where the workspace repository is ALREADY CLONED the act is the
# script alone: an operator whose links a rebuild removed does not need to be
# told to clone a checkout they are standing next to.
mkdir -p "$TEST_ROOT/estate-wip/scripts"
printf '#!/bin/sh\n' > "$TEST_ROOT/estate-wip/scripts/link-estates"
launch_without_estate run team002 --resume session-manifest-cloned
grep -Fq "fix: $TEST_ROOT/estate-wip/scripts/link-estates" "$ERR_LOG" \
    || fail "R-A11-13: the act is not the workspace repository's own script ('$(cat "$ERR_LOG")')"; assertion
grep -Fq 'git clone' "$ERR_LOG" \
    && fail "R-A11-13: an operator with the repository already cloned is told to clone it ('$(cat "$ERR_LOG")')"; assertion
rm -rf "$TEST_ROOT/estate-wip"

# 5h-viii. `CF2-W11` — THE CHECKOUT IS THERE AND THE SCRIPT IS NOT, which is
# what `opensoft/brett-wip#6` @`1483d55` (Amendment 9 act 5, "the workspace
# repository keeps data only") does: it DELETES `scripts/link-estates`. The `-e`
# test on the script is what makes act 5 bite rather than what saves it — with
# the script gone it goes false, and the resolver's second branch then printed a
# `git clone` FOR A PATH THAT IS ALREADY THERE: a clone that fails with
# "destination path already exists", followed by a script that is not in the
# repository any more. Two failures in the one act rule (a) exists to name.
#
# The interval act no longer exists on this machine, so the line names the one
# act that can ever place the lane tools — `openRepoTools --install`, the
# capability branch's own — with the reason beside it, and NEVER a path that is
# not there. This is the mirror of 5h-vii and the scenario the addendum asked
# for: it is the only one of the six that can tell the third branch from the
# second.
mkdir -p "$TEST_ROOT/estate-wip"
[[ ! -e "$TEST_ROOT/estate-wip/scripts/link-estates" ]] \
    || fail "CF2-W11: this scenario needs the checkout WITHOUT the script, and the script is there"; assertion
launch_without_estate run team002 --resume session-act5-script-gone
grep -Fq 'git clone' "$ERR_LOG" \
    && fail "CF2-W11: the checkout is already there and the operator is told to clone it — the clone fails with 'destination path already exists' ('$(cat "$ERR_LOG")')"; assertion
grep -Fq "$TEST_ROOT/estate-wip/scripts/link-estates" "$ERR_LOG" \
    && fail "CF2-W11: the act names a path that is not there (Amendment 9 act 5 deletes it) ('$(cat "$ERR_LOG")')"; assertion
grep -Fq 'openRepoTools --install' "$ERR_LOG" \
    || fail "CF2-W11: with the interval act gone the line names no act at all ('$(cat "$ERR_LOG")')"; assertion
grep -Fq 'act 5' "$ERR_LOG" \
    || fail "CF2-W11: the line names the act without the reason it changed, so an operator cannot tell it from a plain --install ('$(cat "$ERR_LOG")')"; assertion
[[ "$(wc -l < "$ERR_LOG")" -eq 1 ]] \
    || fail "CF2-W11/§16(a): one situation printed $(wc -l < "$ERR_LOG") lines ($(cat "$ERR_LOG"))"; assertion
rm -rf "$TEST_ROOT/estate-wip"

# 5h-ix. THE MANIFEST'S INLINE COMMENT DOES NOT REACH THE PRINTED ACT (the
# automated reviewer's YAML item, judged real). `path: "<checkout>" # default
# checkout` is the exact form `scripts/setup-workspace-repo.sh:171-177`
# documents as supported, and the launcher's own reader kept everything after
# the `#`: the printed act became `git clone … "<path>" # default checkout &&
# "<path>" # default checkout/scripts/link-estates`, where everything after the
# `#` is COMMENTED OUT and what an operator would actually run is a bare clone
# into a quoted path. Both halves are now the repo's own `yaml_value` rule.
mkdir -p "$TEST_ROOT/comment-home/.agents"
printf 'repository: opensoft/estate-wip   # the workspace repo\npath: "%s/commented-wip" # default checkout\n' \
    "$TEST_ROOT" > "$TEST_ROOT/comment-home/.agents/workspace.yaml"
without_estate_env=("HOME=$TEST_ROOT/comment-home")
launch_without_estate run team002 --resume session-yaml-comment
without_estate_env=()
grep -Fq 'default checkout' "$ERR_LOG" \
    && fail "YAML: the manifest's inline comment reached the printed act, where everything after the # is commented out ('$(cat "$ERR_LOG")')"; assertion
grep -Fq "$TEST_ROOT/commented-wip" "$ERR_LOG" \
    || fail "YAML: the quoted path was not read back at all ('$(cat "$ERR_LOG")')"; assertion
grep -Fq '"' "$ERR_LOG" \
    && fail "YAML: the manifest's own quotes reached the printed act ('$(cat "$ERR_LOG")')"; assertion
grep -Fq 'git clone git@github.com:opensoft/estate-wip.git' "$ERR_LOG" \
    || fail "YAML: the repository's own inline comment broke the clone URL ('$(cat "$ERR_LOG")')"; assertion

# 5h-x. AND AN INDENTED KEY IS NOT A TOP-LEVEL ONE. Amendment 9(a) puts the
# `orgs:` map out of scope and `yaml_value` anchors to column 0 for exactly that
# reason; the launcher's copy allowed leading whitespace, so a `path:` nested
# under `orgs:` could answer for the workspace's own.
mkdir -p "$TEST_ROOT/indent-home/.agents"
printf 'orgs:\n  opensoft:\n    path: %s/WRONG-nested\n    repository: opensoft/WRONG\n' \
    "$TEST_ROOT" > "$TEST_ROOT/indent-home/.agents/workspace.yaml"
without_estate_env=("HOME=$TEST_ROOT/indent-home")
launch_without_estate run team002 --resume session-yaml-indent
without_estate_env=()
grep -Fq 'WRONG' "$ERR_LOG" \
    && fail "YAML: an INDENTED key under orgs: answered for the top-level workspace path ('$(cat "$ERR_LOG")')"; assertion
grep -Fq "$TEST_ROOT/indent-home/.agents/workspace.yaml" "$ERR_LOG" \
    || fail "YAML: with no top-level key the operator is not told where to name their repository ('$(cat "$ERR_LOG")')"; assertion

# 5h-xi. A WORKSPACE PATH WITH A SPACE PRINTS A COMMAND THAT RUNS (the automated
# reviewer's other half, judged HALF real: the act is printed and never
# executed, so "can execute unintended commands" does not arise, but a command
# that will not run does). The clone target is checked by word-splitting it the
# way a shell would: one word is right, two is the bug.
mkdir -p "$TEST_ROOT/space-home/.agents"
printf 'repository: opensoft/estate-wip\npath: %s/my estate\n' "$TEST_ROOT" \
    > "$TEST_ROOT/space-home/.agents/workspace.yaml"
without_estate_env=("HOME=$TEST_ROOT/space-home")
launch_without_estate run team002 --resume session-yaml-space
without_estate_env=()
space_act="$(sed -n 's/.*; fix: //p' "$ERR_LOG" | head -n 1)"
[[ -n "$space_act" ]] \
    || fail "space path: no install act was printed ('$(cat "$ERR_LOG")')"; assertion
space_target="$(sed -n 's/^git clone [^ ]* \(.*\) && .*$/\1/p' <<<"$space_act")"
[[ -n "$space_target" ]] \
    || fail "space path: the printed act is not the clone form, so this scenario proves nothing ('$space_act')"; assertion
eval "set -- $space_target"
[[ "$#" -eq 1 ]] \
    || fail "space path: the clone target word-splits into $# words, so the printed command clones into the wrong place ('$space_target')"; assertion
[[ "$1" == "$TEST_ROOT/my estate" ]] \
    || fail "space path: the clone target reads back as '$1', not '$TEST_ROOT/my estate'"; assertion

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
# Amendment 9 adoption act 4b (`opensoft/workBenches#74`) deleted this
# repository's own copies of these two files along with the loops that
# installed from them; `openRepoTools --install` places both now, from the
# pin (`devBenches/base-image/upstream-pin.yaml`, commit `f98d734`, moved
# there from `8a36eb3` by `opensoft/workBenches#91`, the pin `opensoft/
# workBenches#78` first vendored). The SPEC spellings audited below are a
# property of the shipped bytes, not of which repository's checkout holds
# them, so this scenario reads the vendored copy the pin carries.
#
# opensoft/workBenches#93's ACCOUNTING (superseding opensoft/workBenches#91's
# note, which is history now): this suite IS wired into CI as of #93 (beside
# test-claude-profile-skill-install.sh, in .github/workflows/speckit-git-bash.
# yml) and is GREEN against the real vendored content the pin carries today.
# It was not always: several assertions below failed the identical way against
# `git show 8a36eb3:skills/lane-swap/SKILL.md`, independent of any pin move —
# some were this suite's OWN rot (a citation checked for a commit sha that was
# never the shipped citation convention; a hostname-reading shape that
# describes the launcher and was mistakenly duplicated onto the skill; two
# guard-variable names — `ws_write_refused`, `session_field` — that were never
# the shipped spelling), retargeted in place and marked `RETARGETED
# (opensoft/workBenches#93)` where they are, each citing the amendment clause
# that settles it. Others were real gaps against the vendored bytes — a missing
# preemptive uuid/session guard, a stale uncorrected comment, a hard-coded
# helper path — filed upstream (opensoft/openRepoTools#98, #99, #100, siblings
# of #79 and #80) and marked `KNOWN GAP, NOT THIS PR'S` where they are, same as
# #79's own marker below. #93's PR description carries the full per-assertion
# table.
SKILL_MD="$REPO_ROOT/devBenches/base-image/files/openrepotools/skills/lane-swap/SKILL.md"
SWAP_MD="$REPO_ROOT/devBenches/base-image/files/openrepotools/commands/swap.md"
HANDOFF_MD="$REPO_ROOT/devBenches/base-image/files/openrepotools/skills/handoff/SKILL.md"  # Amendment 17(a): the mechanics below moved here

# SPEC §5 (rev 3) — the swap record's payload, in the SPEC's own ORDER and
# spelling: `swap; window <session>:<index> <@id>; dir <path>; profile <name>;
# workstation <ws>`. Five sub-fields now: `profile` was added by `R-A11-10` and
# sits between `dir` and `workstation`, which is the order the SPEC's own three
# example lines carry and the order a reader of the log will meet.
grep -Fq 'payload="swap"' "$HANDOFF_MD" \
    || fail "§5: the PAUSED payload does not open with the verb-less swap token"; assertion
grep -Fq 'payload="$payload; window $win"' "$HANDOFF_MD" \
    || fail "§5: the window sub-field is not written as 'window <refs>'"; assertion
grep -Fq 'payload="$payload; dir $dir"' "$HANDOFF_MD" \
    || fail "§5: the directory sub-field is not written as 'dir <path>'"; assertion
grep -Fq 'payload="$payload; workstation ' "$HANDOFF_MD" \
    || fail "§5: the workstation sub-field is not written as 'workstation <ws>'"; assertion
# ...and they are appended in the SPEC's order, which is a property of the
# lines TOGETHER and cannot be read off any one of them. Amendment 17(b)
# appended `agent` and `transcript` after `workstation`, and Amendment 17
# Addendum 1 appended `kind` after that (`kind respawn` for a `/ctx` that
# killed the process every writer was a child of, `kind in-process` for a
# clear that keeps it) -- six fields now, not four. `transcript` does not
# appear in $payload_order below: it shares ONE assignment with `agent`
# (`payload="$payload; agent $agent_name; transcript $transcript_id"`), and
# this regex, unchanged from before, only ever sees the field that opens a
# `payload="$payload; ` assignment -- a pre-existing limit of the detection,
# not a new gap this rename introduces.
payload_order="$(grep -o 'payload="$payload; [a-z]*' "$HANDOFF_MD" | sed 's/.*; //' | tr '\n' ' ')"
[[ "$payload_order" == "window dir profile workstation agent kind " ]] \
    || fail "§5: the payload is built as '$payload_order', and the current order is 'window dir profile workstation agent kind'"; assertion
# ...and the window sub-field's two refs are SPACE-separated within it, which is
# Amendment 7(b)'s rule for several refs in one sub-field.
grep -Fq 'win="${win:+$win }$wid"' "$HANDOFF_MD" \
    || fail "§5: the window sub-field's two refs are not space-separated"; assertion
# ...and a space in a path is QUOTED, while `, `, ` — ` and a `"` are refused.
grep -Fq 'case "$dir" in *'"'"' '"'"'*) dir=' "$HANDOFF_MD" \
    || fail "§5/R-A11-6: a dir sub-field containing a space is not quoted"; assertion
grep -q 'case "\$dir" in .*'"'"', '"'"'.*'"'"' — '"'"'.*refused' "$HANDOFF_MD" \
    || fail "§5: a dir sub-field containing ', ' or ' -- ' is not refused"; assertion
# ...and `; ` joins that list for `dir`, SPEC rev 6 §5: it is the separator
# BETWEEN payload sub-fields, so `dir /a; b` reads back as a dir of `/a`
# followed by a sub-field no reader knows.
grep -Fq "case \"\$dir\" in *', '*|*' — '*|*'; '*" "$HANDOFF_MD" \
    || fail "§5 (rev 6): a dir sub-field containing '; ' is not refused, so it splits the payload one level down"; assertion
# ...and `window` is NOT widened. Narrowing it would be a SEVENTH edit to
# in-force text where the ratified count is six (R-A11-15), spent on a case the
# estate cannot produce: a window value is a launcher-built session name, an
# index and an <@id>. Pinned so a later pass does not "fix" it for symmetry.
grep -Fq "case \"\$win\" in *', '*|*' — '*|*'; '*" "$HANDOFF_MD" \
    && fail "§5 (rev 6): the window refusal was widened to '; ', which is A8(b)'s list and a seventh in-force edit"; assertion
# ...and `profile` needs no token, because its shape check already admits
# neither `;` nor a space.
grep -Fq 'profile_name" =~ ^[A-Za-z0-9._-]+$' "$HANDOFF_MD" \
    || fail "§5 (rev 6): the profile sub-field is not shape-checked, so '; ' can reach the payload through it"; assertion

# SPEC §7 — the uuid is SUPPLIED, not left for session_for() to substitute.
grep -Fq 'LANES_SESSION="$uuid"' "$HANDOFF_MD" \
    || fail "§7/R-A11-5: the skill does not pass the uuid it has in hand"; assertion

# SPEC §11 — the helper's reads, by their own names, in all three callers this
# PR ships. `window-lane` has THREE (R-A11-6 on F17): the launcher's precedence
# 3, /restart step 2(b) — the tooling PR's — and the skill's step 1.
grep -Fq 'window-lane' "$LAUNCHER" \
    || fail "§11: the launcher does not read precedence 3 through window-lane"; assertion
grep -Fq 'window-lane' "$HANDOFF_MD" \
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

# RV-W5 — AND THE DOCUMENT BESIDE `--help` SAYS THE SAME. A switch that occurs
# once in the code and nowhere a person reads is a switch nobody can use in the
# emergency it exists for; the review's judgement on the third declared addition
# was "keep and document it in one line, or drop it".
DOCS_MD="$REPO_ROOT/docs/claude-multi-account-profiles.md"
grep -Fq 'WORKBENCHES_CLAUDE_WINDOW_REUSE' "$DOCS_MD" \
    || fail "RV-W5: the window-reuse opt-out is in the code and in no document a person reads"; assertion
grep -Fq 'WORKBENCHES_CLAUDE_LANE_DIR_FROM_CWD' "$DOCS_MD" \
    && fail "RV-W5: the docs still carry the cwd rung's opt-out, which c712c5b removed"; assertion
grep -Fq 'the only command of its pane' "$DOCS_MD" \
    || fail "RV-W3/R-A11-16: the docs state the pane invariant in terms of the marker rather than the pane"; assertion
grep -Fq 'closed by' "$DOCS_MD" \
    || fail "RV-W3/R-A11-16: the docs do not say the third door is closed, or by what"; assertion
grep -Fq 'entered' "$DOCS_MD" \
    || fail "RV-W5/Evidence 3: the docs do not say the launcher enters the lane's directory"; assertion
grep -Fq 'A missing `lane-start` is said, not passed over' "$DOCS_MD" \
    || fail "Evidence 5: the docs still describe the silent degradation this launcher no longer performs"; assertion

# THE `; ` REFUSAL IN THE DOCUMENT A PERSON READS (round-4 non-blocking 3). The
# rule is pinned in the skill's CODE above and in the `--help` below; until now
# `grep -c '; ' docs/…md` was 0, so a reader following the documented contract —
# "`, `, ` — ` or a `\"`" — could build a `dir` the writer drops without ever
# being told it would be dropped. A contract stated in three places and refused
# in a fourth is the defect this round keeps finding, one file along. BOTH halves
# are pinned, because the interesting half is the asymmetry: `window` is
# deliberately NOT widened (SPEC rev 6 §5), and a document listing `; ` for all
# three would send the reader back the other way.
grep -Fq '`, `, ` — `, `; `' "$DOCS_MD" \
    || fail "non-blocking 3: the '; ' refusal is in the code, the skill and the --help, and is missing from the LIST the docs give a reader"; assertion
grep -Fq 'deliberately not for' "$DOCS_MD" \
    || fail "non-blocking 3: the docs list the '; ' refusal without saying that window is deliberately outside it, which is the ruling and not an oversight"; assertion

# EVIDENCE 4 IN THE DOCUMENT A PERSON READS. §6c pins what the CODE does about
# the session's name — nothing, which is the rule. This pins what the docs SAY,
# because "the way back is `pclaude <profile>`" is an instruction to a person,
# and a person who reaches for `claude --resume <uuid>` instead gets a session
# that resumes correctly, reports a derived name and never goes through
# lane-start at all: the failure Evidence 4 measured.
grep -Fq 'openrepoproject-b9' "$DOCS_MD" \
    || fail "Evidence 4: the docs claim a derived name without the one that was measured"; assertion
grep -Fq '`/rename <lane>` is what fixes it' "$DOCS_MD" \
    || fail "Evidence 4(b): the docs do not name the act that fixes a derived name from inside a session"; assertion

# ...AND SINCE AMENDMENT 12 THAT ACT HAS TWO PERFORMERS, so no document here may
# call it the only one. A11 is IN FORCE (ratified 2026-09-13T19:41:04Z, verbatim
# "ratify 21 and 71 when ready", landed `0e40d6e` with ratification commit
# `f12f96b`), and the section its ratification commit added — "Amendments 12 and
# 13, which went in force while this text was in confirmation", `:2164-2177` at
# `0e40d6e` — rules the first bullet in these words: "A RUNNING session's name:
# AMENDMENT 12 GOVERNS THE ACT; this text keeps the fallback." A12's
# `UserPromptSubmit` guard and `SessionStart` hook TYPE `/rename <lane>` into the
# session's own tmux pane with `tmux send-keys`, "which is a keystroke rather
# than an API". So the NO-API half of every sentence here stays exactly true and
# the "nothing else can" half is superseded, and this PR's printed line is "what
# a person still has wherever it is not" installed — every workstation until
# A12's adoption act 3 lands.
#
# BOTH HALVES ARE PINNED, in the three documents that print the act: the
# performer must be named, and the retired claim must be gone. The retired
# string was asserted POSITIVELY by this suite until this round, which is why it
# is inverted here rather than merely deleted — a suite that only stopped
# requiring it would let the next writer put it back.
for rename_file in "$DOCS_MD" "$HANDOFF_MD" "$LAUNCHER"; do
    grep -Fq 'tmux send-keys' "$rename_file" \
        || fail "A12 reconciliation: $(basename "$rename_file") prints the /rename act and never names Amendment 12's guard, which types it"; assertion
    grep -Fq 'is the only act that fixes it' "$rename_file" \
        && fail "A12 reconciliation: $(basename "$rename_file") still calls /rename the ONLY act; A12 governs it and this text is the fallback"; assertion
    # QUOTING ANOTHER FILE'S SENTENCE IS NOT ASSERTING IT, and the head is what
    # tells the two apart: a line carrying `63a74af` is reporting what the
    # LANDED successor still says — ruling 10's item-5 gap, recorded in the
    # file being handed over — while the same words with no head on the line
    # are this estate's own claim, which A12 superseded. Counted rather than
    # matched, the way this suite counts every other corrected sentence.
    rename_claims="$(grep -F 'the only act there is' "$rename_file" | grep -cv '63a74af' || true)"
    if [[ "$rename_claims" -eq 0 ]]; then
        :
    elif [[ "$rename_file" == "$HANDOFF_MD" ]] && [[ "$rename_claims" -eq 1 ]] \
        && grep -Fq "operator's \`/rename <lane>\` is the only act there is." "$rename_file"; then
        # KNOWN, PRE-EXISTING, and NOT from this pin move: this exact uncited
        # sentence was already in skills/lane-swap/SKILL.md at 8a36eb3 (the pin
        # workBenches#78 vendored, verified with `git show 8a36eb3:skills/
        # lane-swap/SKILL.md | grep -c 'the only act there is'` = 1, same
        # line), unreconciled with Amendment 12 since before this suite's own
        # reconciliation round landed. Amendment 17(a) moved it, byte for
        # byte, into skills/handoff/SKILL.md, where retargeting this scenario
        # onto the file that now carries the mechanics (see this suite's
        # header note) surfaces it for the first time -- it was never
        # reachable against the emptied-out lane-swap alias, and until
        # opensoft/workBenches#93 wired this suite into CI (see this suite's
        # header note) nothing had run this check against real content since
        # 8a36eb3 landed. Against the VENDORED BYTES, copied byte-for-byte, so
        # filed upstream rather than
        # fixed here (opensoft/openRepoTools#79) and not this PR's regression.
        echo "KNOWN (opensoft/openRepoTools#79, pre-existing since 8a36eb3, not fixed here -- vendored byte-for-byte): $(basename "$rename_file") still says /rename is the only act there is" >&2
    else
        fail "A12 reconciliation: $(basename "$rename_file") still says /rename is the only act there is, on $rename_claims line(s) that name no head"
    fi
    assertion
done
# ...and the no-API half is NOT dropped with it: it is the half A12's own note
# calls "still exactly true", and a document that lost it would read as if an
# API had appeared. The sentence wraps across two `#` comment lines in the
# vendored file (unchanged from the 8a36eb3 wrapping this check was written
# against), so it is matched against the comment prose JOINED, not against
# one raw line -- a single-line `grep -F` on wrapped prose is a fragile
# assertion of line-wrap width, not of the sentence's presence.
handoff_prose="$(sed -n 's/^# \{0,1\}//p' "$HANDOFF_MD" | tr '\n' ' ')"
grep -Fq 'no API to rename a running session' <<<"$handoff_prose" \
    || fail "A12 reconciliation: the skill dropped the half that is still true — there is no API, and the keystroke is not one"; assertion

# THE AMENDMENT IS IN FORCE, AND ITS CITATIONS NAME THE LANDED FILE. Until this
# round the text was a DRAFT on a PR and every citation here was qualified by a
# draft head. It landed as `0e40d6e`, and the ratification commit MOVED THE
# LINES ONE LAST TIME — clause (c)'s window paragraph `:663` -> `:687`, the
# `R-A11-27` paragraph `:2025` -> `:2035` — which is the citation gate's own
# rule proving itself a third time. Two things are required of this PR: the
# landed path is named where a reader would go looking, and NOTHING here claims
# the word ratified this PR, because the amendment's own list says the launcher
# half lands under it when its own confirmation says READY.
grep -Fq 'home/.agents/protocols/lane-collision-protocol-amendment-11.md' "$LAUNCHER" \
    || fail "in force: the launcher cites the amendment and never names the file it landed as, so a reader is sent to a PR diff"; assertion
# RETARGETED (opensoft/workBenches#93): `0e40d6e` names no line of the amendment
# TEXT (it cannot cite its own landing commit) and never has, in either the
# vendored copy this checkout carries or the pre-move `8a36eb3` one — this
# assertion was stale from before any pin move, not a casualty of one. The
# skill's own citation convention for "ratified, not draft" is the ruling's
# addendum number plus its verbatim ratifying words, and R-A11-27's own is
# right there in the shipped bytes (`skills/handoff/SKILL.md:97-98`): "A11
# Addendum 4 ruling 11, ratified \"a11 addendum 4 yes\"". That is what a reader
# actually meets, so that is what this checks for.
#
# SCOPED TO THE CITATION ITSELF (round 7, joined round 8): `ruling 11` appears
# four times in this file (`:98`, `:265`, `:474`, `:501`) and the ratification
# quote could have drifted onto an unrelated one of them while THIS citation
# regressed to draft wording, so round 7 required both on one LINE — but the
# citation itself wraps: "A11 Addendum 4" closes `:97`'s parenthetical and
# "ruling 11, ratified …" opens `:98`, two lines for one phrase. Joined on the
# comment prose already built above (`$handoff_prose`, the same technique the
# no-API sentence a few lines up needed for the same reason), so the addendum
# number, the ruling number and the ratification quote are all required
# together rather than "ruling 11" alone standing in for the whole citation.
grep -Fq 'A11 Addendum 4 ruling 11, ratified "a11 addendum 4 yes"' <<<"$handoff_prose" \
    || fail "in force: the skill's 'A11 Addendum 4 ruling 11' citation does not carry the ratification quote ('ratified \"a11 addendum 4 yes\"'), so the R-A11-27 citation may read as a draft again"; assertion
grep -Fq 'in force' "$HANDOFF_MD" \
    || fail "in force: the skill quotes a ruling from a text it still presents as unratified"; assertion
grep -Fq 'still a DRAFT' "$LAUNCHER" \
    && fail "in force: the launcher still calls the amendment text a DRAFT; it was ratified 2026-09-13T19:41:04Z and landed at 0e40d6e"; assertion
grep -Fq 'when its own confirmation says READY' "$LAUNCHER" \
    || fail "in force: nothing says the ratifying word did NOT ratify this PR, so a reader could take this file as ratified too"; assertion

# THE GUARD'S WIRING SCOPE, said rather than assumed (the automated reviewer's
# `setup-claude-profiles.sh:175`). ARMED is the per-directory walk and reaches
# anything started under the tree; WIRED is the `hooks.UserPromptSubmit` entry,
# which `configure_profile_runtime` writes into a PROFILE's settings.json and
# nowhere else. A `claude` typed by hand reads `~/.claude`, whose settings.json
# `setup-claude-profiles.sh` gives the status line and the SessionStart entry and
# no UserPromptSubmit entry — so the guard never runs there, and a sentence
# opening its list with "a bare `claude`" reads as a claim to cover it.
[[ "$(grep -c 'UserPromptSubmit' "$REPO_ROOT/scripts/setup-claude-profiles.sh")" -eq 1 ]] \
    || fail "guard scope: setup-claude-profiles.sh now mentions UserPromptSubmit more than once — if it WIRES the guard for bare claude, the scope sentences below are wrong"; assertion
grep -Fq 'WIRED AND ARMED ARE NOT THE SAME WORD' "$GUARD_SH" \
    || fail "guard scope: the guard's lane fence does not distinguish armed from wired, so a reader takes a hand-typed claude as covered"; assertion
grep -Fq 'launcher-managed profile' "$DOCS_MD" \
    || fail "guard scope: the docs claim the fence without saying the automatic swap is a profile behaviour"; assertion
# ...and they state WHAT IS TRUE AT THE HEAD, with the commit that made it so —
# CF2-W1. SPEC rev 3 §0.9 measured `--name` on the new-session branch alone and
# this document said so; adoption act 0 then merged as `opensoft/brett-wip#5` at
# `3719d97` and put it on all three branches, which SPEC rev 5 §13 act 0 item 2
# assigns to act 0 and not to the tooling round. Both halves are pinned: the
# corrected claim must be there WITH its commit, and the superseded one must not.
grep -Fq 'names EVERY session it launches' "$DOCS_MD" \
    || fail "CF2-W1: the docs still say lane-start names only the session it creates, which is false since 3719d97"; assertion
grep -Fq '3719d97' "$DOCS_MD" \
    || fail "CF2-W1: the docs make a claim about lane-start's branches and cite no commit for it, so a reader cannot read it back"; assertion
grep -Fq 'carry no `--name` at all' "$DOCS_MD" \
    && fail "CF2-W1: the docs still say lane-start's resume branches carry no --name; they have carried it since 3719d97"; assertion
grep -Fq 'closing that is the tooling PR' "$DOCS_MD" \
    && fail "CF2-W1: the docs still hand the --name fix to the tooling PR, which SPEC rev 5 §13 does not give it"; assertion
# ...AND A THIRD PHRASING, which is `CF3-W2`. The two negatives above refuse the
# two spellings that were corrected in round 4; a THIRD survived fifty lines
# below the corrected paragraph, in the `lane-start` description — "`--name
# <lane>` where it creates a session, `--resume` where it continues one (see
# Evidence 4 above for which branch carries which)" — and used neither string, so
# this audit passed it. That sentence is the pre-`CF2-W1` framing entire: it
# sends the reader to work out a distinction act 0 abolished at `3719d97`. Both
# halves are refused, the claim and the pointer, because either one alone would
# leave the reader expecting a derived name after a normal restart.
grep -Fq 'where it creates a session' "$DOCS_MD" \
    && fail "CF3-W2: the docs still split lane-start's branches into one that names and one that resumes, which act 0 abolished at 3719d97"; assertion
grep -Fq 'which branch carries' "$DOCS_MD" \
    && fail "CF3-W2: the docs still send the reader to work out which branch carries --name, and since 3719d97 all three do"; assertion

# RV-W7 — DIVERGENCE 9's RESIDUE IS NAMED, with the finding ids the two reviews
# actually gave it. A rule this PR withdrew and nobody had implemented is a hole
# with no owner; rev 3 §5 gave it to `window-lane` and §13.3 to the tooling PR,
# and the next reader of this launcher meets it warned or not at all.
grep -Fq 'RV-W7' "$DOCS_MD" \
    || fail "RV-W7: divergence 9's residue is named in no document"; assertion
grep -Fq 'reissued from `@0`' "$DOCS_MD" \
    || fail "RV-W7/SPEC §0.7: the docs do not say that a replaced tmux server empties precedence step 3, which is exactly when a restart happens"; assertion
grep -Fq 'only where the window now holding' "$DOCS_MD" \
    || fail "RV-W7: the residue is named without the rule that closes it"; assertion
grep -Fq 'RV-T6' "$DOCS_MD" \
    || fail "RV-W7: the text half of this finding is cited by the wrong id, and RV-T6 is the one that carries the agreement rule"; assertion
grep -Fq 'neither asked nor told anything' "$DOCS_MD" \
    && fail "Evidence 5: the docs still carry the sentence Evidence 5 overturned"; assertion

# EVIDENCE 5 / `R-A11-13` — ONE INSTALL ACT, RESOLVED IN ONE FUNCTION. Two
# places name it: the `--lane` refusal and the notice above. An operator handed
# two different commands for one missing tool has to decide which is current,
# and the one that is wrong is the one they will try first. Since A11 Addendum 3
# the act is CHOSEN rather than written down, so what is pinned is that the
# choice lives in one function and that both callers print what it returns.
[[ "$(grep -Fc '$(lane_start_install_act)' "$LAUNCHER")" -eq 2 ]] \
    || fail "R-A11-13: the install act has $(grep -Fc '$(lane_start_install_act)' "$LAUNCHER") callers, and it has two — the --lane refusal and the missing-tool notice"; assertion
# COMMENTS STRIPPED ON BOTH SIDES OF THE COUNT BELOW. The property is "all of
# the act is inside one function", and it is measured by comparing how many
# times each spelling occurs in the function against how many times it occurs
# in the whole executable file. `launcher_exec_code` already drops comments, so
# this side has to as well — otherwise the function ARGUING about `link-estates`
# (which it must, since `CF2-W11` is a rule about when not to name it) counts as
# spelling it, and the two sides can never agree.
install_act_code="$(awk '/^lane_start_install_act\(\) \{$/ { inside = 1 } inside { print } inside && $0 == "}" { exit }' "$LAUNCHER" \
    | grep -v '^[[:space:]]*#')"
[[ -n "$install_act_code" ]] \
    || fail "R-A11-13: there is no lane_start_install_act function, so the act is not resolved in one place"; assertion
grep -Fq 'openRepoTools --help' <<<"$install_act_code" \
    || fail "R-A11-13: the act is not chosen by asking the INSTALLED openRepoTools what it can do"; assertion
grep -Fq '*lane-start*' <<<"$install_act_code" \
    || fail "R-A11-13: the capability probe does not test for the LANE tools, so any openRepoTools at all would answer it"; assertion
grep -Fq "lane_start_install_act_answer='openRepoTools --install'" <<<"$install_act_code" \
    || fail "R-A11-13: the act Amendment 9(b) names is never printed at all"; assertion
grep -Fq 'workspace.yaml' <<<"$install_act_code" \
    || fail "R-A11-13: the interval act names no workspace repository, so it names link-estates alone"; assertion
# ...and ALL of it lives in that function. A second spelling anywhere in the
# launcher's executable text is exactly the drift the one-spelling rule is for,
# so the counts are compared rather than the sites listed.
#
# EXCEPT ONE LINE, NAMED RATHER THAN LEFT TO DRIFT THIS ASSERTION SILENT
# (opensoft/workBenches#93, on opensoft/workBenches#99/#90's merge): the name
# guard's downgrade notice — "Restore the estate (openRepoTools --install,
# then link-estates) and the next launch of this profile puts it back." — says
# both words too, but as ADVICE to a person reading a log, not as a SECOND
# CALLER of the install act; it never calls `lane_start_install_act` and prints
# no answer this rule is about two callers agreeing on. Excluded by the one
# sentence that names it, so a real second caller elsewhere still trips this.
launcher_exec_code="$(awk '/^      cat <<.EOF.$/ { skip = 1 } !skip { print } skip && $0 == "EOF" { skip = 0 }' "$LAUNCHER" \
    | grep -v '^[[:space:]]*#' \
    | grep -Fv 'Restore the estate (openRepoTools --install, then link-estates)')"
[[ "$(grep -Fc 'link-estates' <<<"$launcher_exec_code")" \
    -eq "$(grep -Fc 'link-estates' <<<"$install_act_code")" ]] \
    || fail "R-A11-13: link-estates is spelled outside lane_start_install_act, so two callers can drift apart"; assertion
[[ "$(grep -Fc 'openRepoTools' <<<"$launcher_exec_code")" \
    -eq "$(grep -Fc 'openRepoTools' <<<"$install_act_code")" ]] \
    || fail "R-A11-13: openRepoTools is named outside lane_start_install_act"; assertion
grep -Fq 'github.com:opensoft/brett-wip.git' <<<"$launcher_exec_code" \
    && fail "R-A11-13: the launcher still hard-codes one operator's workspace repository as the install act"; assertion

# ONE RULE FOR READING `workspace.yaml`, AND TWO NECESSARY COPIES OF IT — the
# automated reviewer's YAML item, judged real. `scripts/setup-workspace-repo.sh`
# has this repository's own reader (`yaml_value`, :171-189) and states the two
# things a looser one gets wrong in its own comment: TOP LEVEL ONLY, and the
# inline comment stripped BEFORE the quotes. The launcher cannot call it — the
# launcher is copied into the base image and that script stays in the checkout,
# so inside a container there is nothing to source — so the rule is copied, and
# what keeps a copy from becoming a second rule is this: both functions are
# extracted verbatim and run over the same table, and every answer must agree.
# A drift in either file fails here rather than at a restart on somebody's
# machine.
YAML_READERS="$TEST_ROOT/yaml-readers.sh"
{
    printf '#!/usr/bin/env bash\n'
    awk '/^lane_workspace_field\(\) \{$/ { inside = 1 } inside { print } inside && $0 == "}" { exit }' "$LAUNCHER"
    awk '/^yaml_value\(\) \{$/ { inside = 1 } inside { print } inside && $0 == "}" { exit }' \
        "$REPO_ROOT/scripts/setup-workspace-repo.sh"
} > "$YAML_READERS"
grep -Fq 'lane_workspace_field()' "$YAML_READERS" \
    || fail "YAML: the launcher's reader could not be extracted, so the comparison below proves nothing"; assertion
grep -Fq 'yaml_value()' "$YAML_READERS" \
    || fail "YAML: setup-workspace-repo.sh's reader could not be extracted, so the comparison below proves nothing"; assertion
# shellcheck disable=SC1090
. "$YAML_READERS"
yaml_probe="$TEST_ROOT/yaml-probe.yaml"
yaml_mismatch=""
while IFS= read -r yaml_case; do
    [[ -n "$yaml_case" ]] || continue
    printf '%s\n' "$yaml_case" > "$yaml_probe"
    for yaml_key in path repository; do
        mine="$(lane_workspace_field "$yaml_probe" "$yaml_key")"
        theirs="$(yaml_value "$yaml_key" "$yaml_probe")"
        [[ "$mine" == "$theirs" ]] \
            || yaml_mismatch="$yaml_mismatch|$yaml_key on <$yaml_case>: launcher='$mine' setup-workspace-repo='$theirs'"
    done
done <<'YAMLCASES'
path: /plain/checkout
path: "/quoted/checkout"
path: '/single/quoted'
path: "/with/comment" # default checkout
path: /bare/comment # a trailing note
path: /trailing/space
path: ~/tilde/checkout
path: ~
path: /has#hash/inside
  path: /indented/under/orgs
repository: opensoft/estate-wip   # the workspace repo
repository: "opensoft/quoted-wip"
YAMLCASES
[[ -z "$yaml_mismatch" ]] \
    || fail "YAML: the launcher's reader and this repo's own yaml_value disagree — two implementations of one rule${yaml_mismatch}"; assertion

# SPEC §9 — `/swap` is a one-line command file that INVOKES the skill, and the
# skill is not duplicated into it. Two texts that must stay byte-equal with
# nothing making them so is the rejected alternative. Amendment 17(a) renamed
# the invoked skill to `handoff` (lane-swap is now the same shape of alias),
# so the invocation check follows the rename; /swap still names /lane-swap
# as a fellow door onto the same act, which is the substance the old wording
# was really after.
grep -Fqi 'invoke the `handoff` skill' "$SWAP_MD" \
    || fail "§9: commands/swap.md does not invoke the handoff skill (Amendment 17(a))"; assertion
grep -Fq 'lane-swap' "$SWAP_MD" \
    || fail "§9: commands/swap.md no longer names /lane-swap as a fellow door onto this act"; assertion
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
grep -Fq 'restart_cmd="pclaude ${CLAUDE_PROFILE_NAME:-<profile>}"' "$HANDOFF_MD" \
    || fail "§9/§1: the skill does not print the one-word restart command"; assertion
# ...AND THE LAUNCHER DOES NOT TELL A MAINTAINER THE GUARD PERFORMS THE SWAP.
# SPEC §9 and the amendment text (clause (g)) rule the opposite in terms: the
# hook "cannot act", it composes one line and printf's it, and the SESSION
# performs the act. A comment that says otherwise sends the next person
# debugging a missing PAUSED record into the wrong file. Both artefacts are
# audited: the guard already says it (`:122`), and now so does the launcher.
grep -Fq 'performs the swap itself' "$LAUNCHER" \
    && fail "§9: the launcher tells a maintainer the guard performs the swap; it is a UserPromptSubmit hook that prints one line (claude-usage-guard.sh:167-179)"; assertion
grep -Fq 'THE GUARD ITSELF PERFORMS NO STEP OF IT' "$LAUNCHER" \
    || fail "§9: the launcher does not say what the guard actually does at the breakpoint"; assertion
grep -Fq 'THE GUARD DOES NOT PERFORM THE SWAP' "$GUARD_SH" \
    || fail "§9: the guard itself no longer says it performs no step of the swap"; assertion

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
# is append-only; write (b) is not.
#
# KNOWN GAP, NOT THIS PR'S (opensoft/workBenches#93, filed upstream as
# opensoft/openRepoTools#98): the skill supplies the uuid it has in hand
# (`LANES_SESSION="$uuid"`, `R-A11-5`) but has no preemptive guard at all for a
# lane that has never had a session recorded — no `[[ -z "$uuid" ]]` of any
# spelling, no `session_field`, no message naming the gap, anywhere in the
# file. `:507` and `:514` run unconditionally on `$uuid`, so an empty uuid
# reaches the writer un-warned instead of the skill refusing first the way
# `R-A11-5`'s "two guards rather than one" requires and the way `R-A11-14`'s
# `ws_missing` flag already does for the analogous missing-workstation case.
# Confirmed pre-existing against `git show 8a36eb3:skills/lane-swap/SKILL.md`'s
# equivalent step too, independent of any pin move — this is a real shipped-code
# gap against vendored bytes, not a test-methodology one, so it is skipped
# pending opensoft/openRepoTools#98 rather than retargeted.
#
# FAIL-CLOSED (Copilot round 4 on opensoft/workBenches#93): the skip above was
# unconditional -- it never checked that the gap it waives is still the gap
# that is there. Gated on the exact known shape (no uuid-emptiness construct of
# any spelling anywhere in the skill's shell); the moment one appears, #98 may
# be fixed or may have changed shape, and this fails rather than keep waiving
# silently, so a human restores or extends the five checks that stood here.
#
# WIDENED, NOT PROVEN (round 5, operator fixed round 6): a `grep` cannot
# enumerate every bash spelling of "the uuid is empty" — round 4 covered
# `-z`/`-n` on a quoted `$uuid`; this adds `-v uuid` and `"$uuid" =`/`==`/`!=`
# `""`, the other common forms, and an unquoted `$uuid` after `-z`/`-n`.
# `[=!]=` (round 5's own pattern) requires TWO operator characters and so
# never matched bash's single-`=` string test despite the comment claiming to
# — `[=!]?=` makes the first character optional, matching `=`, `==` and `!=`
# alike. It still cannot see one split across a line break or an exotic
# predicate this suite has never needed elsewhere, so the claim is bounded to
# what is checked, not to every conceivable rewrite.
uuid_guard_probe="$(grep -v '^[[:space:]]*#' "$HANDOFF_MD" \
    | grep -E -- '-z "?\$\{?uuid|-n "?\$\{?uuid|-v uuid\b|"\$\{?uuid:?-?[^}]*\}?" *[=!]?= *""' || true)"
if [[ -z "$uuid_guard_probe" ]]; then
    echo "KNOWN (opensoft/openRepoTools#98, pre-existing since 8a36eb3, not fixed here -- vendored byte-for-byte): skills/handoff/SKILL.md has no preemptive uuid/session guard" >&2
else
    fail "RV-W1/R-A11-5: a uuid-emptiness construct now exists in the skill ($uuid_guard_probe) — opensoft/openRepoTools#98 may be fixed or may have changed shape; re-examine by hand and restore or extend the checks this skip replaced"
fi
assertion
# The audit is made on the skill's SHELL — its fenced code blocks with their
# comments stripped — and not on its prose, which ARGUES about both words at
# length and would answer for the code if it were read.
skill_write_code="$(awk '/^```/ { fence = !fence; next } fence' "$HANDOFF_MD" | grep -v '^[[:space:]]*#')"
grep -Fq 'none recorded' <<<"$skill_write_code" \
    && fail "R-A11-14: the skill still writes 'none recorded' — two tokens with a space, in a field Amendment 7(b) gives one uuid"; assertion
# ...and `unknown` is counted as a VALUE and not as the word, exactly as the
# `$(hostname` read is counted above and for the same reason. Since the step-1
# reader takes `window-lane`'s status apart (clause (k), the launcher's
# `window_lane_read` matched string for string), the skill's shell now contains
# the helper's own `unknown subcommand` line as a COMPARISON. That is naming the
# helper's message, not writing a placeholder into a record, so it is removed
# before the word is looked for — a count that could not tell the two apart
# would force the skill to misspell the one string it must match exactly.
# RETARGETED (opensoft/workBenches#93, narrowed round 2/3 on Copilot's review):
# the exclusion above pre-dates Amendment 17 Addendum 1's `kind="${kind:-
# unknown}"` and its `$kind == unknown` branch — a legitimate, ratified THIRD
# use of the bare word `unknown`, for the swap's `kind` sub-field, not a
# placeholder workstation. Stripping only `unknown subcommand` left these two
# literal `unknown` values as a false positive the day the `kind` field landed.
# Dropping every `kind`-bearing LINE (the first cut at this) was too wide —
# `payload="$payload; kind $kind"` is a different line from either legitimate
# `unknown`, but a REGRESSION that leaked a placeholder workstation onto a line
# that also happened to mention `kind` would then go uncaught. Only the four
# exact substrings that carry the ratified `unknown` (the assignment, its
# trailing comment, the comparison, and the `why_text` concatenation) are
# removed, by name, so anything else stays visible to the check.
grep -Fq 'unknown' <<<"$(sed -e 's/unknown subcommand//g' -e 's/kind="${kind:-unknown}"//g' -e 's/# in-process | respawn | unknown//g' -e 's/"$kind" == unknown//g' -e 's/kind unknown//g' <<<"$skill_write_code")" \
    && fail "R-A11-14: the skill still writes a placeholder workstation into a position 'swapped <ws>' keys on, which append-line does not validate"; assertion
# ...and write (c), the row's state cell, must be outside any uuid guard too —
# SPEC §7 names the two together. Moot on the shipped bytes (opensoft/
# openRepoTools#98, above): there is no uuid guard at all for `replace-in-row`
# to be inside or outside of, so nothing here can be asserted about its
# position relative to one.

# RV-W6 / R-A11-11 — THE `dir` THE SKILL RECORDS IS THE LANE'S CHECKOUT, NEVER A
# WORKTREE. SPEC §4 and clause (c) name the writer's source as the live session's
# own record — the harness's `"cwd"` beside its `"tmux"` — and the launcher's
# exported word before it. `git rev-parse --show-toplevel` and `$PWD` are the two
# derivations that record a subagent's scratchpad worktree on rung 4, which is
# every lane on the estate until a record carries a `dir`.
grep -Fq 'dir="${WORKBENCHES_CLAUDE_LANE_DIR:-}"' "$HANDOFF_MD" \
    || fail "RV-W6: the skill does not take the launcher's own word for the lane's directory first"; assertion
grep -Fq 'CLAUDE_CONFIG_DIR"/sessions/*.json' "$HANDOFF_MD" \
    || fail "RV-W6/R-A11-11: the skill does not read the live session's own record for the directory (SPEC §4)"; assertion
grep -Fq 'select((.sessionId // "") == $id) | .cwd // empty' "$HANDOFF_MD" \
    || fail "RV-W6: the session record is not matched on THIS session's id, so it could take another session's cwd"; assertion
# The two derivations are judged on the skill's own SHELL and not on its prose:
# the comment above the assignment names them as retired, and a rule that
# grepped the whole file could never be stated at all.
skill_code="$(grep -v '^[[:space:]]*#' "$HANDOFF_MD")"
grep -Fq 'git rev-parse --show-toplevel' <<<"$skill_code" \
    && fail "RV-W6/R-A11-11: the skill's shell still derives a directory from the git toplevel of wherever it stands, which in a subagent's scratchpad is a worktree"; assertion
grep -Fq '"$PWD"' <<<"$skill_code" \
    && fail "RV-W6/R-A11-11: the skill's shell still falls back to \$PWD for the lane's dir"; assertion
# ...and where neither source answers, the sub-field is OMITTED and the omission
# is SAID. A record with no `dir` is complete the way SPEC §5 says a record with
# no `@id` is; a record with the wrong one is not.
grep -Fq 'NO dir sub-field' "$HANDOFF_MD" \
    || fail "RV-W6: a record written with no dir says nothing about the gap"; assertion

# R-A11-10 (decision 7, drafted now) — `profile <name>` IS IN THE RECORD. A lane's
# name says nothing about the account it runs under, and `restart <lane>` has to
# build `pclaude --lane <lane> <profile>` out of the record alone.
grep -Fq 'payload="$payload; profile $profile_name"' "$HANDOFF_MD" \
    || fail "R-A11-10: the swap record does not carry the 'profile <name>' sub-field"; assertion
grep -Fq 'profile_name="${CLAUDE_PROFILE_NAME:-}"' "$HANDOFF_MD" \
    || fail "R-A11-10: the profile sub-field is not taken from the launcher's exported CLAUDE_PROFILE_NAME"; assertion
# ...and the launcher is the one that exports it, so the two halves agree.
grep -Fq 'export CLAUDE_PROFILE_NAME="$profile"' "$LAUNCHER" \
    || fail "R-A11-10: the launcher does not export CLAUDE_PROFILE_NAME, so the skill's profile sub-field is empty on every launch"; assertion

# ===========================================================================
# 6c. EVIDENCE 4 — NO SURFACE HERE PRINTS OR EXECS A BARE `claude --resume`.
#
# A bare `claude --resume <uuid>` continues the transcript and leaves the
# session's RECORD NAME derived (`openrepoproject-b9`), which is what the
# statusline and `ListAgents` display.
#
# WHAT `lane-start` ACTUALLY DOES ABOUT IT, read back at the commit that decided
# it: `--name "$LANE"` is on ALL THREE launch branches — `claude --resume
# "$row_sid"` (`lanes/lane-start:846`), `claude --resume "$LANE"` (`:855`) and
# the new session (`:866`) — since adoption act 0 merged as
# `opensoft/brett-wip#5` at `3719d97` on 2026-09-13, which SPEC rev 5 §13 act 0
# item 2 assigns to act 0 rather than to the tooling round. This comment has now
# been wrong in BOTH directions: an early pass said lane-start named every launch
# it made (the overclaim SPEC rev 3 §0.9 measured), and the pass after it said
# the resume branches carried none and handed the fix to the tooling PR (CF2-W1,
# false at the very commit it cited). What is true here is the negative rule owed
# to THIS PR — the launcher, the guard and the skill never offer a bare
# `claude --resume` as the lane's act, and never name a session themselves — and
# a negative rule is audited, not scenario'd.
#
# The launcher's own `--help` DESCRIBES lane-start's `--resume/--name <lane>`,
# which is the correct thing to describe, so the audit is made against the
# launcher's EXECUTABLE text with the help heredoc removed. A rule that grepped
# the whole file could not be stated at all.
# ===========================================================================

scenario

# The help heredoc first, then the comments: this file ARGUES about `--resume`
# at length — Evidence 3's own paragraph quotes it — and a rule about what the
# launcher DOES cannot be read off text that only says why.
launcher_code="$(awk '/^      cat <<.EOF.$/ { skip = 1 } !skip { print } skip && $0 == "EOF" { skip = 0 }' "$LAUNCHER" \
    | grep -v '^[[:space:]]*#')"
[[ -n "$launcher_code" ]] \
    || fail "evidence 4: the launcher's executable text could not be separated from its --help"; assertion
grep -Fq 'show this help' <<<"$launcher_code" \
    && fail "evidence 4: the --help heredoc was not removed, so this audit reads prose and proves nothing"; assertion
grep -q '^[[:space:]]*#' <<<"$launcher_code" \
    && fail "evidence 4: the comments were not removed, so this audit reads the argument rather than the code"; assertion
grep -Fq -- '--resume' <<<"$launcher_code" \
    && fail "evidence 4: the launcher spells --resume itself; a bare resume is never the lane's act (the operator's own --resume is passed through in \"\$@\")"; assertion
grep -Fq -- '--name' <<<"$launcher_code" \
    && fail "evidence 4: the launcher names a Claude session itself; --name <lane> is lane-start's act alone"; assertion
# ...and the exec that starts the bare Claude carries the flags and the
# operator's own argv, and nothing this launcher added.
grep -Fq 'CLAUDE_CONFIG_DIR="$config_dir" exec "$claude_bin" "${claude_flags[@]}" "$@"' "$LAUNCHER" \
    || fail "evidence 4: the bare Claude is not exec'd with the flags and the operator's argv alone"; assertion
# The guard's one printed command is the restart, and it is `pclaude`.
grep -Fq 'claude --resume' "$GUARD_SH" \
    && fail "evidence 4: the usage guard prints a bare claude --resume as the way back"; assertion
# The skill prints `pclaude <profile>`, refuses `claude --resume <title>` as a
# lane surface by name, and ends the identity triple with the one act that can
# fix a derived record name from inside a session.
grep -Fq 'are not lane surfaces' "$HANDOFF_MD" \
    || fail "evidence 4: the skill no longer refuses /resume and claude --resume as lane surfaces (A8 Addendum 2 R-A8-6)"; assertion
grep -Fq '/rename <lane>' "$HANDOFF_MD" \
    || fail "evidence 4(b): the skill's identity triple does not name /rename <lane>, the act that fixes a derived session name from inside"; assertion
# ...AND IT ENDS WITH THE SAME ACT, for the session that comes NEXT (CF-W5,
# `R-A11-16`). Step 1's `/rename` is the incoming one, for the session running
# the skill. The restart step 5 prints RESUMES, and `lane-start` passes
# `--name <lane>` only where it CREATES a session — its two resume branches
# carry none — so the session the operator lands in after every swap has the
# name the harness derived, and until adoption act 0 lands nothing else in
# flight tells them.
# The audit is of step 5's SHELL — the lines it actually prints — and not of
# the paragraph under it: prose that explains the act is not the act, and an
# operator reading the swap's output is reading the shell's words.
skill_step5_code="$(awk '/^## 5\./ { inside = 1 } inside && /^## 6\./ { exit } inside && /^```/ { fence = !fence; next } inside && fence' "$HANDOFF_MD")"
[[ -n "$skill_step5_code" ]] \
    || fail "CF-W5: step 5 of the skill has no shell at all, so nothing it prints can be audited"; assertion
grep -Fq '/rename <lane>' <<<"$skill_step5_code" \
    || fail "CF-W5/R-A11-16: step 5 PRINTS the restart command and says nothing about the derived name the session it starts comes up with"; assertion

# ===========================================================================
# 7. THE WORKSTATION THE RECORDS ARE KEYED TO — Evidence 6 (new-workstation#20,
#    2026-09-13T17:57:45Z).
#
# `swapped <ws>` answers with the rows THAT WORKSTATION wrote, and this lane's
# records say `Eagle`. Inside a bench container `hostname -s` is the container's
# id — `0e7d1a79a07e`, measured — so a launcher that passes it asks about a
# machine that has existed for an hour: the read answers nothing, precedence 4
# falls through, and nothing says why. That is Evidence 5's silence one function
# along. A WRITER that passes it is worse, and is what the forked orchestrator
# of Evidence 6 did: the id went into an append-only log.
#
# This suite runs INSIDE such a container, so the two branches are forced by the
# `container=` marker rather than left to the host: `container=docker` is a
# container everywhere, which makes both scenarios below say the same thing on
# any machine they are run on.
# ===========================================================================

# 7a. CONFIGURATION WINS, AND IT WINS INSIDE A CONTAINER. LANES_WORKSTATION is
# the estate's own word; the container marker does not override it, because the
# rule is "configured, not guessed" and not "never inside a container". Read
# here through the directory order's rung 2 (Amendment 11(3)): precedence 4 no
# longer reads `swapped` at all (lane-collision-protocol Amendment 18 Addendum
# 1 hands that step to `lane`), so rung 2 is the nearest remaining door onto
# the same `swapped <ws>` read Evidence 6 is about.
launch "FAKE_TMUX_WINDOW=zsh" "FAKE_LANE_WITH_ROW=nothing" "container=docker" \
    "FAKE_TMUX_WINDOW_ID=@97" "FAKE_WINDOW_LANE_MAP=@97=mine-5" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=mine-5\t2026-09-13T03:31:33Z\tclaude-y:0 @97\t$RECORD_TREE\n" \
    -- run team002 --resume session-ws-configured
grep -Fxq 'argv=swapped Eagle' "$LANES_EDIT_LOG" \
    || fail "Evidence 6: the configured workstation was not the one asked about ($(cat "$LANES_EDIT_LOG"))"; assertion
grep -Fxq -- "--dir $RECORD_TREE mine-5 -- $claude_args --resume session-ws-configured" "$LANE_START_LOG" \
    || fail "Evidence 6: the configured workstation's own swap record did not answer ('$(lane_start_argv)')"; assertion

# 7b. A CONTAINER THAT NAMES NO WORKSTATION READS NOTHING. Passing the
# container id would ask about the wrong machine; passing nothing would let the
# helper derive the same id one process later. So the read is not made at all
# — here again through rung 2, precedence 4 having no read of its own left to
# make. THE NOTICE THIS SCENARIO USED TO PIN IS RETIRED WITH THAT READ:
# precedence 4's own `swapped_ws_unknown` check — the one place that spelled
# "Evidence 6" and named `LANES_WORKSTATION` — went with the `swapped` call it
# guarded, and rung 2 has never had a notice of its own for the same gap; it
# silently falls through to rung 3/4 exactly as an ordinary "no dir recorded"
# does. What survives, and what this scenario now pins, is the SAFETY property
# Evidence 6 exists for: a container with no configured workstation never asks
# `swapped` for one, so it can never read a stranger's rows back as its own.
launch "FAKE_TMUX_WINDOW=openRepoProject-1" "FAKE_LANE_WITH_ROW=openRepoProject-1" \
    "LANES_WORKSTATION=" "container=docker" \
    "FAKE_SWAPPED_STATUS=0" \
    "FAKE_SWAPPED_ROWS=openRepoProject-1\t2026-09-13T03:31:33Z\tclaude-y:0 @97\t$RECORD_TREE\n" \
    -- run team002 --resume session-ws-unknown
grep -q '^argv=swapped' "$LANES_EDIT_LOG" \
    && fail "Evidence 6: the swap records were read for a workstation this container cannot name ($(cat "$LANES_EDIT_LOG"))"; assertion
grep -Fxq -- "openRepoProject-1 -- $claude_args --resume session-ws-unknown" "$LANE_START_LOG" \
    || fail "Evidence 6: lane-start argv was '$(lane_start_argv)'"; assertion
grep -q -- '--dir' "$LANE_START_LOG" \
    && fail "Evidence 6: a directory was derived from a workstation this container cannot name ($(lane_start_argv))"; assertion
[[ "$launch_status" -eq 0 ]] \
    || fail "Evidence 6: the launcher exited $launch_status over a Claude that started"; assertion

# 7c. ...AND THE STEPS THAT DO NOT NEED A WORKSTATION ARE UNTOUCHED. Precedence
# 3 asks the helper about THIS window, which is a fact about this process and
# not about the machine's name: the lane binds bare, nothing is read for a
# workstation nobody named, and this launcher has nothing OF ITS OWN to
# report — beyond the one capture-path breadcrumb opensoft/workBenches#95
# prints ahead of every lane launch regardless of workstation.
launch "FAKE_TMUX_WINDOW=zsh" "FAKE_LANE_WITH_ROW=nothing" \
    "LANES_WORKSTATION=" "container=docker" \
    "FAKE_TMUX_WINDOW_ID=@97" "FAKE_TMUX_WINDOW_REF=claude-y:0" \
    "FAKE_WINDOW_LANE_MAP=@97=mine-5" \
    -- run team002 --resume session-ws-unknown-window
grep -Fxq -- "mine-5 -- $claude_args --resume session-ws-unknown-window" "$LANE_START_LOG" \
    || fail "Evidence 6: the window's own record stopped answering because the machine has no name ('$(lane_start_argv)')"; assertion
[[ "$(grep -c '^pclaude:' "$ERR_LOG")" -eq 1 ]] \
    || fail "Evidence 6: a launch that never needed the workstation was told $(grep -c '^pclaude:' "$ERR_LOG" 2>/dev/null) things of this launcher's own, not just the capture breadcrumb ('$(cat "$ERR_LOG")')"; assertion
grep -Fq 'lane defect capture:' "$ERR_LOG" \
    || fail "Evidence 6: the capture-path breadcrumb itself is missing ('$(cat "$ERR_LOG")')"; assertion

# 7e. THE LAUNCHER OWNS THE VALUE AND EXPORTS IT — `R-A11-14` (A11 Addendum 3,
# ratified by Brett Heap 2026-09-13 "a11 addendum 3 yes"). Before this, the
# reader honoured LANES_WORKSTATION and the writer refused without it and
# NOTHING ON THE ESTATE SET IT — a contract with no owner, which inside a bench
# container means every lane write stops. The owner is this launcher, because it
# is the one process that runs on the HOST: it resolves the name once and
# exports it, so the session it starts, the /lane-swap skill in that session and
# every other writer read the host's word instead of asking a container for one.
launch "FAKE_TMUX_WINDOW=mine-5" "FAKE_LANE_WITH_ROW=mine-5" "LANES_WORKSTATION=Eagle" \
    -- run team002 --resume session-ws-exported
grep -Fxq 'LANES_WORKSTATION=Eagle' "$LANE_START_ENV_LOG" \
    || fail "R-A11-14: the workstation was not exported into the session the launcher started ('$(cat "$LANE_START_ENV_LOG" 2>/dev/null)')"; assertion

# ...and THREADED ACROSS THE RE-EXEC, where inheritance is not reliable: tmux
# does not reliably hand a freshly-exported variable to a new session on an
# already-running server, which is why every other value act 1 needs is put on
# the command string explicitly.
tty_launch "TMUX=" "FAKE_TMUX_WINDOW=claude" "FAKE_SWAPPED_STATUS=8" "CLAUDE_LANE=ws-carried-2" \
    "LANES_WORKSTATION=Eagle" -- run team002 --resume session-ws-threaded
grep -q 'LANES_WORKSTATION=Eagle' "$TMUX_LOG" \
    || fail "R-A11-14: the workstation was not threaded into the tmux session act 1 created ($(cat "$TMUX_LOG"))"; assertion

# 7f. ...AND A CONTAINER THAT NAMES NONE EXPORTS NOTHING. The launcher invents
# no value where it has none — that is the whole of Evidence 6 — so the session
# comes up with the variable still unset and the writers in it refuse and say
# which variable is missing, rather than writing a container id into an
# append-only log or a placeholder that reads back as a hostname.
launch "FAKE_TMUX_WINDOW=mine-5" "FAKE_LANE_WITH_ROW=mine-5" \
    "LANES_WORKSTATION=" "container=docker" \
    -- run team002 --resume session-ws-not-invented
grep -Fxq 'LANES_WORKSTATION=' "$LANE_START_ENV_LOG" \
    || fail "R-A11-14: a container that names no workstation handed the session one anyway ('$(cat "$LANE_START_ENV_LOG" 2>/dev/null)')"; assertion

# 7d. THE RULE IS IN ONE PLACE IN EACH ARTEFACT, AND IT IS FENCED. A static
# audit, because the failure is the one a scenario cannot reach: a second
# `hostname` read somewhere else in the file, which fires only on the machine
# the suite is not running on.
scenario
ws_launcher_code="$(awk '/^      cat <<.EOF.$/ { skip = 1 } !skip { print } skip && $0 == "EOF" { skip = 0 }' "$LAUNCHER" \
    | grep -v '^[[:space:]]*#')"
# TWO READS SINCE lane-collision-protocol AMENDMENT 18 CLAUSE (a)
# (opensoft/workBenches#98): `lane_workstation`'s, and `lane_host`'s beside it —
# the machine's own short name, which the amendment's record line carries next
# to the workstation's. The count is kept because it is what catches a THIRD
# read appearing somewhere this suite cannot reach, and the fence is now audited
# structurally as well, because a count alone says nothing about which of the
# two an edit moved out from under `lane_in_container`.
[[ "$(grep -c 'hostname' <<<"$ws_launcher_code")" -eq 2 ]] \
    || fail "Evidence 6 / Amendment 18(a): the launcher's shell reads hostname $(grep -c 'hostname' <<<"$ws_launcher_code") times, and the two it may have are lane_workstation's and lane_host's"; assertion
ws_unfenced_hostname="$(awk '
    /\$\(hostname/ { if (prev !~ /! lane_in_container/) unfenced = unfenced " " NR }
    { prev = $0 }
    END { print unfenced }' <<<"$ws_launcher_code")"
[[ -z "$ws_unfenced_hostname" ]] \
    || fail "Evidence 6 / Amendment 18(a): a hostname read at line(s)$ws_unfenced_hostname of the launcher's shell is not under '! lane_in_container', so a bench container would export its own id as a machine name"; assertion
grep -Fq 'if [[ -z "$name" ]] && ! lane_in_container; then' <<<"$ws_launcher_code" \
    || fail "Evidence 6: the launcher's hostname read is not fenced on lane_in_container"; assertion
grep -Fq 'name="${LANES_WORKSTATION:-}"' <<<"$ws_launcher_code" \
    || fail "Evidence 6: the launcher does not take the configured workstation first"; assertion
grep -Fq '[[ -e /.dockerenv || -e /run/.containerenv || -n "${container:-}" ]]' <<<"$ws_launcher_code" \
    || fail "Evidence 6: the container fence does not test the three markers a container leaves"; assertion
# ...and the skill, which is the WRITER, and the half of Evidence 6 that cannot
# be taken back: the id the fork wrote is in an append-only log for ever.
ws_skill_code="$(grep -v '^[[:space:]]*#' "$HANDOFF_MD")"
# RETARGETED, THE WHOLE SUB-CLUSTER (opensoft/workBenches#93): the checks below
# used to expect the skill to duplicate the LAUNCHER's own hostname-plus-fence
# code (the shape asserted at :3169-3176 above, against $ws_launcher_code, which
# still passes). The shipped skill takes a DIFFERENT and, per the ruling, more
# correct road: `R-A11-14` gives the workstation value ONE owner, the launcher —
# "the workBenches launcher owns it … The helper and the skill READ it and never
# write a placeholder" — so the skill never reads `hostname` itself at all. It
# reads the value back through the helper's own `workstation` subcommand
# (`"$L" workstation`, `:90`), which is Amendment 11's uniform read (clause (k):
# "one read, three callers" — the same `sread`/fence convention every other
# step-1 read in this file goes through, `:38-45`), rather than re-deriving the
# host id inline the way the launcher (which IS the one owner) still does. The
# four checks here now audit THAT design, which is what R-A11-14 and Evidence 6
# actually require of the skill — that it never invents a hostname of its own —
# rather than a hostname-reading shape the amendment assigns elsewhere.
[[ "$(grep -Fc '$(hostname' <<<"$ws_skill_code")" -eq 0 ]] \
    || fail "R-A11-14: the skill reads hostname directly — the ruling makes the launcher the one owner of that read, and the skill only reads back what it exported"; assertion
grep -Fq '"$L" workstation' <<<"$ws_skill_code" \
    || fail "Evidence 6/R-A11-14: the skill does not take the configured workstation through the helper the launcher and the ruling both make its one owner"; assertion
grep -Fq 'ws_pair="$("$L" workstation 2>/dev/null)" || ws_rc=$?' <<<"$ws_skill_code" \
    || fail "R-A11-14: the workstation read does not capture its own exit code, so the skill cannot tell a stale helper (exit 2, R-A11-8) from a read that failed"; assertion
grep -Fq 'sread rows "'"'"'this workstation has no swap record'"'"'" swapped "$ws"' <<<"$ws_skill_code" \
    || fail "Evidence 6: the skill's step 1 does not read the records for the configured workstation through the uniform read fence"; assertion
grep -Fq '[[ -z "$ws" ]] || payload="$payload; workstation $ws"' <<<"$ws_skill_code" \
    || fail "Evidence 6: the record's workstation sub-field is not written from \$ws, or is written even where none is known"; assertion
# ...and the writer REFUSES where it has none, rather than writing a third thing
# nobody declared (`R-A11-14`; the register line's session position used to read
# `<uuid>@unknown-workstation`, which `append-line` does not validate, so it
# would have landed and no reader would ever have caught it).
#
# RETARGETED, THE WHOLE SUB-CLUSTER (opensoft/workBenches#93): the checks below
# used to expect one guard variable (`ws_write_refused`) and one literal line
# ("REFUSED: no workstation for this lane"). The shipped skill's guard variable
# is `ws_missing`, and it prints TWO distinct messages, not one — `R-A11-8`'s own
# refinement of this exact ruling, read alongside it: exit code 2 from
# `$L workstation` is "a lanes-edit.sh predating Amendment 11 — expected", a
# different situation with a different fix (`openRepoTools --install`) than a
# container that genuinely has no `$LANES_WORKSTATION` exported (fix: `export
# LANES_WORKSTATION=<host>`), so one ruling now reads as two named cases rather
# than one interchangeable line. Both stop the same two writes; both name the
# variable; the container case also names the launcher that sets it.
grep -Fq 'ws_missing=1' <<<"$ws_skill_code" \
    || fail "R-A11-14: the skill does not refuse where no workstation is configured"; assertion
[[ "$(grep -Fc 'ws_missing=1' <<<"$ws_skill_code")" -eq 2 ]] \
    || fail "R-A11-8/R-A11-14: $(grep -Fc 'ws_missing=1' <<<"$ws_skill_code") case(s) set the refusal flag, and the ruling names two — a stale helper (exit 2) and a container with no \$LANES_WORKSTATION"; assertion
grep -Fq 'if [[ -z "$ws_missing" ]]; then' <<<"$ws_skill_code" \
    || fail "R-A11-14: the skill's workstation refusal does not stop the two writes that carry it"; assertion
# PROVES THE GUARD, NOT JUST ITS EXISTENCE (round 9): the check above only
# found the string "if [[ -z ..." somewhere in the file — a regression could
# move (a) and (b) below the guard's `fi` while leaving that dead condition
# in place and still pass. Extracted the guard's own body (a single, unnested
# if/fi, unlike write (c)'s two-command nest below) and require both writes
# inside it, the same standard the (c) check already holds itself to.
ab_guard_block="$(awk '/^if \[\[ -z "\$ws_missing" \]\]; then$/ { inside = 1; next } inside && /^fi$/ { exit } inside { print }' "$HANDOFF_MD" \
    | grep -v '^[[:space:]]*#')"
grep -Fq 'log PAUSED' <<<"$ab_guard_block" \
    || fail "R-A11-14: write (a), the object-log line, is not inside the ws_missing guard"; assertion
grep -Fq 'append-line' <<<"$ab_guard_block" \
    || fail "R-A11-14: write (b), the file-level PAUSED line, is not inside the ws_missing guard"; assertion
grep -Fq 'NO WORKSTATION READ:' "$HANDOFF_MD" \
    || fail "R-A11-8: the stale-helper case (exit 2 predates Amendment 11) is not named as its own situation"; assertion
grep -Fq 'NO WORKSTATION: this is a container and \$LANES_WORKSTATION is not set' "$HANDOFF_MD" \
    || fail "R-A11-14: the refusal is not stated in one line of its own"; assertion
grep -F 'NO WORKSTATION: this is a container' "$HANDOFF_MD" | grep -Fq 'LANES_WORKSTATION' \
    || fail "R-A11-14: the refusal does not name the variable that fixes it"; assertion
grep -F 'NO WORKSTATION: this is a container' "$HANDOFF_MD" | grep -Fq 'workBenches launcher' \
    || fail "R-A11-14: the refusal does not name the launcher that sets the variable"; assertion
# ...AND (c) IS REFUSED WITH THEM — `R-A11-27` (A11 Addendum 4 ruling 11,
# RATIFIED by Brett Heap 2026-09-13T21:08:26Z, verbatim "a11 addendum 4 yes";
# the encoding is `brettheap/new-workstation#21` :2025-2048 at `613452f`).
#
# THIS ASSERTION SAID THE OPPOSITE until round 5, and its comment gave the
# pre-ruling reason: that keeping the flip is how A8(a) step 4's "never left
# unwritten" keeps its substance. The ruling settles it the other way and the
# text quotes this PR's own shipped string — "(c) below still runs, so the row is
# still flipped to PAUSED" — back at it. The row-status flip IS a register write:
# `replace-in-row` and `append-row-status` each file a commit the helper
# subject-keys `LANES(<lane>@<ws>)`, so the one write left running is the one that
# lands the container id in the register's history. Nor does it fail safely on
# this estate — `opensoft/brett-wip`'s `lanes-edit.sh` has no dispatcher guard at
# all and its `:233` is the `${LANES_WORKSTATION:-$(hostname -s)}` default, so
# from a container (c) SUCCEEDS. What survives the refusal is step 2's handoff, a
# commit in the lane's own repository. Inverted here so the next writer who
# restores the write is told by the suite rather than by a review.
c_section="$(awk '/^# \(c\) the row: flip its leading state word/{inside=1} inside{print} inside && /^```$/{exit}' "$HANDOFF_MD")"
[[ -n "$c_section" ]] \
    || fail "R-A11-27: write (c) is not in the skill at all, so nothing can be said about what fences it"; assertion
# ...on the section's SHELL, comments stripped, because the comment above the
# fence ARGUES about `replace-in-row` at length and would answer for the code.
#
# RETARGETED (opensoft/workBenches#93): the guard variable the shipped skill
# tests is `ws_missing`, not `ws_write_refused` — the same rename as the R-A11-14
# cluster above, applied here to the same flag. The shape asked for is
# unchanged: `row_write_refused=1` set inside the guarded branch, `replace-in-row`
# only in the else.
#
# TRACKS BOTH REGISTER WRITES (round 7): write (c) is TWO commands in the
# shipped code, `replace-in-row` AND `append-row-status` (`:542-545`), both
# needed for the row to actually land as PAUSED — a regression moving only one
# of them out from under `ws_missing` used to still read `fenced=1 loose=0`
# from `replace-in-row` alone and pass. `fenced`/`loose` are now true only when
# BOTH commands agree on which side of the guard they are on.
#
# CLOSES THE OUTER `fi` (round 9): `phase` used to stay "written" for the rest
# of the section once `else` opened it, so a write moved past the outer `if`'s
# own closing `fi` — no longer inside the guard at all — still read as
# "written" and passed. The shipped body nests a SECOND if/fi inside the else
# (`append-row-status`'s own `if [[ -z "$row_write_refused" ]]; then … fi`), so
# a bare depth counter is tracked: every line ending `then` opens one, every
# bare `fi` closes one, and hitting depth 0 again closes the OUTER guard and
# moves to a fourth phase, "closed", counted the same as never having entered
# it at all.
c_fence="$(grep -v '^[[:space:]]*#' <<<"$c_section" | awk '
    index($0, "if [[ -n \"$ws_missing\" ]]; then") { phase = "refused"; depth = 1; next }
    phase == "refused" && $0 == "else" { phase = "written"; next }
    phase == "refused" && index($0, "row_write_refused=1") { set = 1 }
    phase == "written" {
        if ($0 ~ /then$/) { depth++ }
        else if ($0 == "fi") {
            depth--
            if (depth == 0) { phase = "closed"; next }
        }
    }
    phase == "written" && index($0, "replace-in-row") { fenced_replace = 1 }
    phase == "written" && index($0, "append-row-status") { fenced_status = 1 }
    (phase == "" || phase == "closed") && index($0, "replace-in-row") { loose_replace = 1 }
    (phase == "" || phase == "closed") && index($0, "append-row-status") { loose_status = 1 }
    END { printf "set=%d fenced=%d loose=%d", set, (fenced_replace && fenced_status), (loose_replace || loose_status) }')"
[[ "$c_fence" == "set=1 fenced=1 loose=0" ]] \
    || fail "R-A11-27: write (c) is not refused with (a) and (b) where no workstation is configured ($c_fence), so a swap from a container still flips the row and files a commit keyed on the container id"; assertion
# RETARGETED (opensoft/workBenches#93): the shipped message is worded
# differently from the draft string this checked for, but names the same thing
# — the row's state cell is not written, and why (the same `clause (k) rule (d)`
# every other register-write refusal in this cluster cites) — so this checks
# for the shipped wording rather than the one no revision of the file has ever
# carried (confirmed also absent from `git show 8a36eb3:skills/lane-swap/
# SKILL.md`).
grep -Fq "NOT WRITTEN: the row's state cell stays as it is" "$HANDOFF_MD" \
    || fail "R-A11-27: (c) is skipped without saying so — a swap that writes nothing has to name which writes it refused"; assertion
grep -F "NOT WRITTEN: the row's state cell stays as it is" "$HANDOFF_MD" | grep -Fq 'clause (k) rule (d)' \
    || fail "R-A11-27: the row-status refusal does not cite the same rule the two writes beside it do"; assertion
# ...and the retired promise is QUOTED, never meant — counted the way the
# `$(hostname` read above is counted rather than the word, because a comment that
# records a corrected sentence must not be indistinguishable from one that still
# asserts it. Two halves: the string is in no SHELL line at all, and every line
# that carries it calls itself somebody ELSE's past claim.
#
# RETARGETED (opensoft/workBenches#93, round 1 of Copilot's review of this PR):
# `revision` was never the shipped marker even on the legitimate quote —
# `SKILL.md:535` says "`#71`'s copy PROMISED …", never the word "revision" —
# so the original check could never go green even after `:474` is fixed
# upstream (opensoft/openRepoTools#99), and would keep reporting a closed gap
# as open forever. `promised` is the word the shipped quote actually uses to
# attribute the claim to another PR rather than assert it; once #99 lands
# (only `:535`'s properly-attributed occurrence remains), `still_runs_total`
# and `still_runs_quoted` become equal and this assertion goes green on its
# own, with nothing here to update.
grep -Fq '(c) below still runs' <<<"$skill_write_code" \
    && fail "R-A11-27: the skill's shell still prints '(c) below still runs' — the exact string the amendment text quotes back at this PR"; assertion
still_runs_total="$(grep -Fc '(c) below still runs' "$HANDOFF_MD" || true)"
still_runs_quoted="$(grep -F '(c) below still runs' "$HANDOFF_MD" | grep -Fc 'promised' || true)"
# round 7: the unqualified occurrence must be the KNOWN one, not merely
# outnumbered by an attributed one — a hypothetical unrelated unqualified
# regression elsewhere would satisfy total=2/quoted=1 too. `:474`'s own
# context cites `ruling 11` (the R-A11-27 ruling number this whole gap is
# about) right beside it; nothing else that could say "(c) below still runs"
# unqualified has a reason to.
still_runs_unqualified_is_known="$(grep -F '(c) below still runs' "$HANDOFF_MD" | grep -Fv 'promised' | grep -Fc 'ruling 11' || true)"
# KNOWN GAP, NOT THIS PR'S (opensoft/workBenches#93, filed upstream as
# opensoft/openRepoTools#99): `:474`'s "(c) below still runs" is a real,
# unqualified leftover — the exact promise R-A11-27 refuses, asserted as
# current fact three sentences after the ruling number that refutes it, and
# contradicted by the code 53 lines further down in the same file (`:527-541`,
# which correctly gates write (c) behind `ws_missing`). Confirmed pre-existing
# against `git show 8a36eb3:skills/lane-swap/SKILL.md`'s equivalent comment too
# — a real shipped-bytes gap, not a test-methodology one.
#
# FAIL-CLOSED (Copilot round 2/3, tightened rounds 4/6, on
# opensoft/workBenches#93): the known shape TODAY is exactly two occurrences,
# one of them properly attributed — anything else, including a WORSE
# regression (a third unqualified line, or the attributed one losing its
# attribution), must still fail rather than fall through this skip silently.
# `-gt 0 && equal` (round 4's fix for the `0 == 0` case) was still too loose —
# a THIRD attributed occurrence (`total=3, quoted=3`) or any other equal-and-
# positive pair would also pass, none of which is the one fixed state this
# file actually has room for. The fixed state is the ONE legitimate historical
# quote at `:535` and nothing else, so the passing shape is now the EXACT
# count (1, 1), not merely "equal and positive".
if [[ "$still_runs_total" -eq 1 && "$still_runs_quoted" -eq 1 ]]; then
    :
elif [[ "$still_runs_total" -eq 2 && "$still_runs_quoted" -eq 1 && "$still_runs_unqualified_is_known" -eq 1 ]]; then
    echo "KNOWN (opensoft/openRepoTools#99, pre-existing since 8a36eb3, not fixed here -- vendored byte-for-byte): skills/handoff/SKILL.md:474 still asserts '(c) below still runs' unqualified ($still_runs_total total, $still_runs_quoted quoted as superseded)" >&2
else
    fail "R-A11-27: $still_runs_total line(s) say '(c) below still runs', $still_runs_quoted attributed, $still_runs_unqualified_is_known of the unqualified one(s) citing 'ruling 11' — neither the known gap (2 total, 1 attributed, 1 citing ruling 11) nor the one fixed state (1 total, 1 attributed); something else changed and needs a human read"
fi
assertion

# THE LAUNCHER IS THE OWNER, IN BOTH OF THE PLACES IT STARTS SOMETHING.
grep -Fq 'name="$(lane_workstation)"' <<<"$ws_launcher_code" \
    || fail "R-A11-14: the exported workstation is not the one lane_workstation resolves, so the reader and the writers could disagree"; assertion
grep -Fq 'export LANES_WORKSTATION="$name"' <<<"$ws_launcher_code" \
    || fail "R-A11-14: the launcher resolves a workstation and never exports it, which is the contract with no owner Evidence 6 left"; assertion
grep -Fq 'env_prefix+=("LANES_WORKSTATION=$LANES_WORKSTATION")' <<<"$ws_launcher_code" \
    || fail "R-A11-14: the workstation is not threaded across the re-exec, where a fresh export is not reliably inherited"; assertion
grep -Fq 'lane_export_workstation' <<<"$ws_launcher_code" \
    || fail "R-A11-14: nothing calls the export, so the session comes up without the value anyway"; assertion
# ...and the container half, which is the case Evidence 6 was measured in: a
# bench container cannot name itself, so the host names it on the way in.
WAVE_SHELL="$REPO_ROOT/scripts/wave-container-shell.sh"
grep -Fq 'lanes_workstation_env=(--env "LANES_WORKSTATION=$lanes_workstation")' "$WAVE_SHELL" \
    || fail "R-A11-14: the bench container is opened without the workstation, so every lane write inside it refuses"; assertion
grep -Fq '${lanes_workstation_env[@]+"${lanes_workstation_env[@]}"}' "$WAVE_SHELL" \
    || fail "R-A11-14: the workstation is resolved for the container and never passed to docker exec"; assertion
grep -Fq 'lanes_workstation="${LANES_WORKSTATION:-}"' "$WAVE_SHELL" \
    || fail "R-A11-14: the container launcher does not take an already-configured workstation first"; assertion
# ...resolved BEFORE this script assigns `container` for its own purposes. The
# systemd container marker is an environment variable of exactly that name, and
# after `container="py-bench"` has run it cannot be read at all: a host that is
# itself a container would then guess a hostname that is a container id.
ws_resolve_line="$(grep -n 'lanes_workstation="${LANES_WORKSTATION:-}"' "$WAVE_SHELL" | head -n 1 | cut -d : -f 1)"
ws_container_line="$(grep -n '^container="py-bench"' "$WAVE_SHELL" | head -n 1 | cut -d : -f 1)"
[[ -n "$ws_resolve_line" && -n "$ws_container_line" && "$ws_resolve_line" -lt "$ws_container_line" ]] \
    || fail "R-A11-14: the container marker is read at line $ws_resolve_line, after this script overwrites \$container at line $ws_container_line"; assertion
# ...and the two documents say it.
grep -Fq 'AND THE WORKSTATION THE SWAP RECORDS ARE KEYED ON IS CONFIGURED' "$TEST_ROOT/help.out" \
    || fail "Evidence 6: --help does not say where the workstation comes from"; assertion
# CF2-W1 — WHAT `lane-start` NAMES, AND WHO CLOSED THE GAP. Adoption act 0
# merged as `opensoft/brett-wip#5` at `3719d97` on 2026-09-13 and put
# `--name "$LANE"` on ALL THREE launch branches (`lanes/lane-start:846`, `:855`,
# `:866`) — the two that RESUME included — which is what SPEC rev 5 §13 act 0
# item 2 assigns it. Four surfaces of this PR said the opposite and handed the
# fix to the tooling PR; this pair pins the corrected claim and refuses the old
# one by its own words, so a revert of the prose fails here rather than shipping.
grep -Fq 'passes `--name <lane>` on EVERY launch branch' "$TEST_ROOT/help.out" \
    || fail "CF2-W1: --help does not say lane-start names every branch it launches, which act 0 made true at 3719d97"; assertion
grep -Fq 'its two resume branches carry' "$TEST_ROOT/help.out" \
    && fail "CF2-W1: --help still tells the reader lane-start's resume branches carry no --name, which is false since 3719d97"; assertion
grep -Fq '3719d97' "$TEST_ROOT/help.out" \
    || fail "CF2-W1: --help names no commit for the claim it makes about lane-start, so a reader cannot read it back"; assertion
grep -Fq '/rename <lane>' "$TEST_ROOT/help.out" \
    || fail "Evidence 4(b): --help does not name the one act that fixes a derived session name from inside"; assertion
# ...and the docs' half of the same fact is pinned in the doc audit above.
grep -Fq 'never taken from' "$DOCS_MD" \
    || fail "Evidence 6: the docs do not carry the rule at all"; assertion

# ---------------------------------------------------------------------------
# THE HELPER HALF HAS LANDED, AND EVERY SENTENCE ABOUT IT IS RE-MEASURED — the
# takeover round's own finding, and the reason it is a pair of audits rather
# than four corrected comments.
#
# This PR was written against a helper that did not exist yet: `opensoft/
# openRepoTools#26`, Amendment 9's adoption act 3, has since MERGED as
# `63a74af`, and with it `lanes-edit.sh window-lane`, `lane-dir`, `swapped`'s
# fourth and fifth fields, the `session-start` subcommand, and the dispatcher
# guard that refuses nine writers from a container with no `LANES_WORKSTATION`.
# Nothing in the launcher changed — every one of those reads was written
# tolerantly for the day it would answer, and the day came — but four sentences
# said "today's helper has none of this", and a sentence about another program
# that the other program no longer supports is `CF2-W1`'s defect one repository
# along.
#
# MEASURED AGAINST THE INSTALLED COPIES, with the launcher's own resolvers
# extracted and run against them: `lanes-edit.sh` resolves on PATH to
# `~/.local/bin/lanes-edit.sh`; `swapped <ws>` exits 0 with FIVE tab-separated
# fields and an empty fourth on this workstation's pre-cutover rows; `lane-dir
# openRepoProject-1` exits 0 with `/workspace/projects/openRepoProject` and
# `lane-dir openRepoTools-3` exits 8; `window-lane @999999` exits 8 and the
# launcher's reader answers nothing WITHOUT a note, which is the contract's
# silent "none"; an unknown subcommand still exits 2; and the resolver answers
# `openRepoTools --install` from the capability branch.
#
# The audits are on the SUBSTANCE and in both directions: the corrected claim
# must be there WITH the head it was measured at, and the superseded one must
# not, so a later pass cannot restore the old premise by tidying the new one
# away. Rung 3 is the one that moved from "finds nothing" to "answers", so it
# is the one named in the failure text.
scenario
grep -Fq '63a74af' "$LAUNCHER" \
    || fail "landed tooling: the launcher makes claims about what lanes-edit.sh answers and names no head to read them at, so a reader cannot check one"; assertion
grep -Fq 'RUNG 3 NOW ANSWERS' "$LAUNCHER" \
    || fail "landed tooling: the launcher does not say that lane-dir now answers, which is the whole of what act 3 changed for the directory order"; assertion
grep -Fq "today's \`lanes-edit.sh swapped\` prints" "$LAUNCHER" \
    && fail "landed tooling: the launcher still says today's swapped prints no fourth field; at 63a74af it prints five and the fourth is empty, which is not the same fact"; assertion
grep -Fq '\`lane-dir\` subcommand at all' "$LAUNCHER" \
    && fail "landed tooling: the launcher still says the helper has no lane-dir subcommand, which it has had since 63a74af"; assertion
grep -Fq "is the tooling PR's" "$LAUNCHER" \
    && fail "landed tooling: the launcher still hands a live behaviour to an unlanded PR; act 3 merged as 63a74af"; assertion
# ...and the tolerance STAYS, with the population it is for named rather than
# assumed. A host that has not re-run `openRepoTools --install` still answers
# the old way, and an audit that only refused the old sentences would invite the
# next writer to delete the fallback with them.
grep -Fq 'predates' "$LAUNCHER" \
    || fail "landed tooling: the launcher no longer names the host its tolerant reads are for — one whose lanes-edit.sh predates that merge"; assertion
grep -Fq 'unknown subcommand' "$LAUNCHER" \
    || fail "landed tooling: the launcher stopped naming the line an older helper prints, which is the one thing rung 3 must never read as a path"; assertion
# THE DOCUMENT SAYS IT TOO, both halves. The docs are what an operator reads
# before the comments, and a document that still says the rung finds nothing
# sends them to fix a launcher that is working.
grep -Fq 'That helper has landed' "$DOCS_MD" \
    || fail "landed tooling: the docs still describe the helper as unlanded"; assertion
grep -Fq 'degrade silently against today' "$DOCS_MD" \
    && fail "landed tooling: the docs still say rungs 2 and 3 degrade against today's helpers, which is false on any host that has re-run --install"; assertion
grep -Fq 'the gate has since opened' "$DOCS_MD" \
    || fail "landed tooling: the docs' live-state paragraph does not record that the SessionStart gate now opens"; assertion
grep -Fq 'does not exist yet — so today, correctly' "$DOCS_MD" \
    && fail "landed tooling: the docs still say the session-start subcommand does not exist; ~/projects/xFactory/lanes-edit.sh links the installed helper, which has it"; assertion
# ...and the launcher's own probe comment says which file it is really reading,
# because `~/projects/xFactory/lanes-edit.sh` is a symlink and a reader who
# takes it for a second estate will conclude the gate can never open.
grep -Fq 'link-estates' "$LAUNCHER" \
    || fail "landed tooling: nothing in the launcher says who keeps ~/projects/xFactory/lanes-edit.sh pointed at the installed helper"; assertion
# AND THE ONE PER-HOST ACT IS WRITTEN DOWN — clause (k) rule (d) gives the value
# an OWNER and no file, which leaves exactly one thing a person may have to do
# on a host whose `hostname -s` is not the name its rows are keyed to. Until
# this round no document said what it was, and "the launcher exports it" is not
# an instruction to anybody standing on such a host. The rejected alternative is
# named with it, because the obvious fix — a key in `workspace.yaml` — is the
# one the amendment refuses by name.
grep -Fq 'export LANES_WORKSTATION=Eagle' "$DOCS_MD" \
    || fail "R-A11-14: no document gives the one per-host act for a workstation whose hostname is not its name"; assertion
grep -Fq 'SECOND PLACE FOR THE TRUTH TO BE WRONG' "$DOCS_MD" \
    || fail "R-A11-14: the docs give the act without the alternative the amendment refuses, so the next reader adds a workstation: key to workspace.yaml"; assertion
grep -Fq 'lanes-edit.sh workstation' "$DOCS_MD" \
    || fail "R-A11-14: the docs tell a person to set the variable and not how to read back what it resolved to"; assertion
# THE GUARD CARRIED A FIFTH COPY OF THE PROMISE `R-A11-27` REFUSES, and the
# automated reviewer found it where four rounds of this PR had not: the
# directive told the session the swap record "is never left unwritten", which
# is the sentence the ruling corrects — in a container with no
# `LANES_WORKSTATION` every register and object-log write is refused and the
# restart the skill prints carries `--lane`. Both halves pinned.
grep -Fq 'it is never left unwritten' "$GUARD_SH" \
    && fail "R-A11-27: the guard's directive still promises the swap record is never left unwritten, which a container with no LANES_WORKSTATION refuses"; assertion
grep -Fq 'R-A11-27' "$GUARD_SH" \
    || fail "R-A11-27: the guard directs an act whose writes can be refused and never names the ruling that refuses them"; assertion
# AND THE SKILL RESOLVES ITS HELPER instead of spelling one path. `link-estates`
# adds the `~/projects/xFactory` symlink ONLY where that directory exists, so on
# a host with the tools and no such directory a hard-coded `$L` names nothing
# and every write in the skill fails with no helper to blame. PATH first, the
# symlink second — `claude-profile`'s own rule, and the line openRepoTools'
# `/restart` skill already uses.
#
# KNOWN GAP, NOT THIS PR'S (opensoft/workBenches#93, filed upstream as
# opensoft/openRepoTools#100): `skills/handoff/SKILL.md:39` still hard-codes
# `L=~/projects/xFactory/lanes-edit.sh`. Every sibling artifact in the same
# vendored tree resolves it PATH-first — `lanes`, `lane`, `lane-end`,
# `lane-start`, `lane-handoff` all call `command -v lanes-edit.sh` first, and
# `skills/restart/SKILL.md:39` (this skill's own sibling, same line, same job)
# already reads `L="$(command -v lanes-edit.sh || printf '%s' ~/projects/
# xFactory/lanes-edit.sh)"`. Confirmed pre-existing against `git show
# 8a36eb3:skills/lane-swap/SKILL.md:39` too (the pre-Amendment-17(a) home of
# this same line) — a real shipped-bytes gap, not a test-methodology one.
#
# FAIL-CLOSED (Copilot round 2/3, tightened rounds 4-6, on
# opensoft/workBenches#93): the known gap is specifically TODAY's exact
# hard-coded line, not "anything that isn't the fixed form" — a third,
# differently-broken `L=` would otherwise also fall through this skip
# unnoticed, and matching the raw Markdown (rather than the extracted,
# comment-stripped `skill_write_code`) meant a PROSE mention of the fixed form,
# with no code changed at all, could make this pass too. Round 5: a mere
# PREFIX match also passed a syntactically-valid but semantically broken
# fallback (`L="$(command -v lanes-edit.sh || false)"` names no helper on a
# host without one, same failure as today's hard-coded line, dressed as
# fixed — this required the WHOLE line to equal the complete form
# `skills/restart/SKILL.md:39` already ships, `printf` fallback included.
# Round 6, two more: `grep -qx` (no `-F`) on the hard-coded pattern left the
# `.` in `lanes-edit.sh` a wildcard, so `lanes-editXsh` would have counted as
# today's exact gap; and neither branch checked that the OTHER assignment was
# ABSENT, so a file carrying both somehow would have taken whichever branch
# came first and missed that the wrong one might still be the effective `$L`.
# Both are counted, `-F` and `-x` together, and each branch now requires the
# other to be exactly zero. Round 7: neither branch checked the TOTAL — a
# third, differently-spelled `L=` assignment sitting beside either of the
# other two would have left both specific counts exactly as expected while a
# stray extra assignment silently decided the effective `$L`. `total_l_count`
# catches any `^L=` this file has that is neither counted pattern.
fixed_l_count="$(grep -Fxc 'L="$(command -v lanes-edit.sh || printf '"'"'%s'"'"' ~/projects/xFactory/lanes-edit.sh)"' <<<"$skill_write_code" || true)"
hardcoded_l_count="$(grep -Fxc 'L=~/projects/xFactory/lanes-edit.sh' <<<"$skill_write_code" || true)"
total_l_count="$(grep -Ec '^L=' <<<"$skill_write_code" || true)"
if [[ "$total_l_count" -eq 1 && "$fixed_l_count" -eq 1 && "$hardcoded_l_count" -eq 0 ]]; then
    :
elif [[ "$total_l_count" -eq 1 && "$fixed_l_count" -eq 0 && "$hardcoded_l_count" -eq 1 ]]; then
    echo "KNOWN (opensoft/openRepoTools#100, pre-existing since 8a36eb3, not fixed here -- vendored byte-for-byte): skills/handoff/SKILL.md:39 hard-codes lanes-edit.sh's path instead of resolving it" >&2
else
    fail "helper: \$L assignment is ambiguous or unexpected (total x$total_l_count, fixed form x$fixed_l_count, hard-coded form x$hardcoded_l_count) — neither the known gap nor the exact fixed form alone; something else changed here and needs a human read"
fi
assertion

[[ "$scenarios" -eq "$EXPECTED_SCENARIOS" ]] \
    || fail "$scenarios scenarios ran, $EXPECTED_SCENARIOS expected — one was added or lost without saying so"
echo "claude-profile Amendment 11: $scenarios scenarios, $assertions assertions passed"
