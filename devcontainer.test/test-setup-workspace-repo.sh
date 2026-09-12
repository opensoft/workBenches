#!/usr/bin/env bash
# Regression tests for scripts/setup-workspace-repo.sh -- the workspace-repository
# step of the onboarding chain, lane-collision-protocol Amendment 9(e):
#
#   ./setup.sh -> openRepoTools --install -> openRepoTools wip init -> pclaude -> lane-start
#                 (setup-estate-commands.sh)  (THIS STEP)
#
# Everything the step shells out to is faked here -- openRepoTools and gh --
# so every assertion below is about the step's own behaviour and nothing else.
# Two scenarios deliberately use the REAL vendored openRepoTools instead, to
# prove the degradation is live against the bytes this repository ships today
# and not only against a fake that agrees with us.
#
# What is guarded, in the order the task named it:
#
#   (a)(i)      the subcommand present: it runs, relays, and adds no question
#   (b)(b2)     idempotence: a host with a workspace runs nothing at all
#   (c)(c2)     the subcommand absent: it prints what to run and continues (0)
#   (c3)        MUTATION: absence is decided by `--help`, NEVER by an exit code
#   (d)(d2)     the missing-gh-rights path: the administrator block is
#               surfaced, not swallowed -- through this step AND through
#               setup.sh's own best-effort caller pattern
#   (e1-e3)     ordering relative to `--install`, behavioural and static
#   (f)         the prompt count, which is zero, proven two ways
#   (g)         the skip switch
#   (h1-h5)     the derivations: nothing derivable is ever asked
#
# Scenario (c3) is the one that matters most and is the least obvious. Today's
# openRepoTools answers an unknown argument by `die`ing, and `die`'s default
# exit is 2 -- the same 2 Amendment 9(c) gives `wip init`'s own refusals. A
# capability probe that read the exit code would therefore read a real refusal,
# with the administrator's `gh repo create` block already on the terminal, as
# "no such subcommand", and would print the degradation text over the top of
# the one thing the person needed. (c3) fails if anyone ever rewrites the probe
# that way.

set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$TEST_DIR/.." && pwd -P)"
SCRIPT_UNDER_TEST="${1:-$REPO_ROOT/scripts/setup-workspace-repo.sh}"
SETUP_SH="$REPO_ROOT/setup.sh"
REAL_TOOLS="$REPO_ROOT/devBenches/base-image/files/openrepotools/openRepoTools"

# Ambient state from the shell running this must not reach the step: a
# workstation that has already run the real chain has a real
# ~/.agents/workspace.yaml, and every scenario below sets the state it means to
# test.
unset AGENT_PROTOCOL_ROOT OPENREPOTOOLS_BIN_DIR WORKBENCHES_SKIP_WORKSPACE_REPO \
    WORKBENCHES_WORKSPACE_ORG 2>/dev/null || true

TMPDIR_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

failures=0
checks=0

pass() { checks=$((checks + 1)); printf 'PASS: %s\n' "$1"; }
fail() { checks=$((checks + 1)); failures=$((failures + 1)); printf 'FAIL: %s\n' "$1"; }

assert_equal() {
    if [ "$1" = "$2" ]; then pass "$3"; else fail "$3: expected [$2], got [$1]"; fi
}

assert_contains() {
    if grep -Fq -- "$2" <<<"$1"; then pass "$3"; else fail "$3: output does not contain: $2"; fi
}

assert_not_contains() {
    if grep -Fq -- "$2" <<<"$1"; then fail "$3: output unexpectedly contains: $2"; else pass "$3"; fi
}

assert_file_absent() {
    if [ ! -e "$1" ]; then pass "$2"; else fail "$2: $1 exists ($(cat "$1" 2>/dev/null))"; fi
}

assert_identical() {
    if cmp -s "$1" "$2"; then pass "$3"; else fail "$3: $1 differs from $2"; fi
}

# ---------------------------------------------------------------------------
# The fakes.
FAKE_BIN="$TMPDIR_ROOT/bin"
mkdir -p "$FAKE_BIN"

# openRepoTools: logs its argv, answers --help with whatever help the scenario
# says it has, and answers `wip ...` with the scenario's stdout/stderr/exit.
# Anything else dies exactly as the real one does -- `die` prints REFUSED and
# exits 2 -- because scenario (c3) turns on those two facts being the truth.
cat > "$FAKE_BIN/openRepoTools" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'argv=%s\n' "$*" >> "${FAKE_TOOLS_LOG:?}"
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    printf '%b\n' "${FAKE_TOOLS_HELP:-}"
    exit 0
fi
if [ "${1:-}" = "wip" ]; then
    if [ -n "${FAKE_WIP_STDOUT:-}" ]; then printf '%b' "${FAKE_WIP_STDOUT}"; fi
    if [ -n "${FAKE_WIP_STDERR:-}" ]; then printf '%b' "${FAKE_WIP_STDERR}" >&2; fi
    exit "${FAKE_WIP_STATUS:-0}"
fi
printf '\nREFUSED: openRepoTools installs the estate commands and does nothing else.\n' >&2
exit 2
EOF

# gh, for the login derivation only. FAKE_GH_LOGIN unset means a gh that is
# installed but not logged in -- `gh api user` fails and prints nothing usable.
cat > "$FAKE_BIN/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'argv=%s\n' "$*" >> "${FAKE_GH_LOG:?}"
if [ "${1:-}" = "api" ] && [ "${2:-}" = "user" ]; then
    if [ -n "${FAKE_GH_LOGIN:-}" ]; then
        printf '%s\n' "$FAKE_GH_LOGIN"
        exit 0
    fi
    printf 'gh: To get started with GitHub CLI, please run: gh auth login\n' >&2
    exit 4
fi
exit 1
EOF

chmod +x "$FAKE_BIN/openRepoTools" "$FAKE_BIN/gh"

TOOLS_LOG="$TMPDIR_ROOT/tools.log"
GH_LOG="$TMPDIR_ROOT/gh.log"

# The help of an openRepoTools that has shipped Amendment 9's adoption act 3,
# and of one that has not. The second is the shape today's really has.
A9_HELP='openRepoTools --install            install (or update) the estate commands
openRepoTools wip init            create this workstation'"'"'s workspace repository
openRepoTools --help | --version'
PRE_A9_HELP='openRepoTools --install            install (or update) park, resume, status and
                                   this command into ~/.local/bin
openRepoTools --help | --version'

ADMIN_BLOCK='This account cannot create repositories in opensoft. Ask an administrator
for these three, then re-run `openRepoTools wip init`:

    gh repo create opensoft/brettheap-wip --private --team estate \\
        --description "brettheap'"'"'s workspace repository"
    gh api --method PUT /orgs/opensoft/teams/estate/repos/opensoft/brettheap-wip -f permission=pull
    exclude opensoft/brettheap-wip from the organisation'"'"'s PR-only ruleset
'

# run <scenario env>... -- [args]   ; leaves OUTPUT and STATUS set.
OUTPUT=""
STATUS=0
run_step() {
    local -a scenario_env=()
    while [ $# -gt 0 ] && [ "$1" != "--" ]; do scenario_env+=("$1"); shift; done
    shift || true
    rm -f "$TOOLS_LOG" "$GH_LOG"
    STATUS=0
    # stdin is /dev/null in every scenario: a step that asked a question would
    # read EOF and could not hang, but it also could not be answered -- and
    # scenario (f) turns that into an assertion rather than a convenience.
    OUTPUT="$(env -i \
        "PATH=$FAKE_BIN:/usr/bin:/bin" \
        "HOME=$TMPDIR_ROOT/home" \
        "FAKE_TOOLS_LOG=$TOOLS_LOG" \
        "FAKE_GH_LOG=$GH_LOG" \
        "${scenario_env[@]}" \
        "$SCRIPT_UNDER_TEST" "$@" 2>&1 </dev/null)" || STATUS=$?
}

tools_argv() { cat "$TOOLS_LOG" 2>/dev/null || true; }

mkdir -p "$TMPDIR_ROOT/home"

# ===========================================================================
printf '%s\n' '--- (a) the subcommand is there: the step runs it, and relays it ---'
AGENTS_A="$TMPDIR_ROOT/agents-a"
mkdir -p "$AGENTS_A"
run_step \
    "AGENT_PROTOCOL_ROOT=$AGENTS_A" \
    "FAKE_TOOLS_HELP=$A9_HELP" \
    "FAKE_GH_LOGIN=brettheap" \
    "FAKE_WIP_STDOUT=created opensoft/brettheap-wip\nnext: pclaude run <profile> --lane <repo>-<n>\n" \
    --
assert_equal "$STATUS" '0' '(a) exit code'
assert_contains "$(tools_argv)" 'argv=wip init' '(a) wip init was invoked'
assert_contains "$OUTPUT" 'created opensoft/brettheap-wip' '(a) wip init stdout is relayed'
assert_contains "$OUTPUT" 'next: pclaude run' '(a) the next step it printed is relayed'
assert_contains "$OUTPUT" 'target: opensoft/brettheap-wip' '(a) the derived target is named before the run'
assert_not_contains "$OUTPUT" 'no `wip` subcommand' '(a) a working openRepoTools is not reported as degraded'
# The mutation that matters here: a second answer. Amendment 9(c) steps 2-3
# have `wip init` derive the login and the org itself; a --login handed in from
# this step would be a second answer to a question that already has one.
assert_not_contains "$(tools_argv)" '--login' '(a) --login is NOT passed (wip init derives it, 9(c) step 2)'
assert_not_contains "$(tools_argv)" '--org' '(a) --org is NOT passed when the estate default applies'
assert_equal "$(grep -c 'argv=wip init' "$TOOLS_LOG")" '1' '(a) wip init was invoked exactly once'

printf '%s\n' '--- (i) --dry-run is passed through ---'
run_step \
    "AGENT_PROTOCOL_ROOT=$AGENTS_A" \
    "FAKE_TOOLS_HELP=$A9_HELP" \
    "FAKE_GH_LOGIN=brettheap" \
    -- --dry-run
assert_equal "$STATUS" '0' '(i) --dry-run exit code'
assert_contains "$(tools_argv)" 'argv=wip init --dry-run' '(i) --dry-run reaches wip init'

# ===========================================================================
printf '%s\n' '--- (b) idempotent re-run: a host that has one runs NOTHING ---'
AGENTS_B="$TMPDIR_ROOT/agents-b"
WS_B="$TMPDIR_ROOT/projects/brettheap-wip"
mkdir -p "$AGENTS_B" "$WS_B/.git"
printf 'repository: opensoft/brettheap-wip\npath: %s\n' "$WS_B" > "$AGENTS_B/workspace.yaml"
cp "$AGENTS_B/workspace.yaml" "$TMPDIR_ROOT/workspace-b.before"

run_step \
    "AGENT_PROTOCOL_ROOT=$AGENTS_B" \
    "FAKE_TOOLS_HELP=$A9_HELP" \
    "FAKE_GH_LOGIN=brettheap" \
    --
assert_equal "$STATUS" '0' '(b) re-run exit code'
assert_contains "$OUTPUT" 'opensoft/brettheap-wip already checked out' '(b) it prints what it found'
assert_contains "$OUTPUT" "$WS_B" '(b) it names the checkout path it found'
assert_file_absent "$TOOLS_LOG" '(b) openRepoTools was not invoked AT ALL -- not even --help'
assert_file_absent "$GH_LOG" '(b) gh was not called either; the detect is a file test, not a network call'
assert_identical "$AGENTS_B/workspace.yaml" "$TMPDIR_ROOT/workspace-b.before" '(b) workspace.yaml is byte-for-byte untouched'

# A third and fourth run change nothing either -- idempotence is not a
# one-shot property.
run_step "AGENT_PROTOCOL_ROOT=$AGENTS_B" "FAKE_TOOLS_HELP=$A9_HELP" "FAKE_GH_LOGIN=brettheap" --
assert_equal "$STATUS" '0' '(b) third run exit code'
assert_file_absent "$TOOLS_LOG" '(b) third run still invokes nothing'

printf '%s\n' '--- (b2) a half-written workspace.yaml falls THROUGH to wip init ---'
AGENTS_B2="$TMPDIR_ROOT/agents-b2"
mkdir -p "$AGENTS_B2"
# names a repository and a path, but the path is no checkout: this step does
# not get to call that "already done", and does not get to repair it either.
printf 'repository: opensoft/brettheap-wip\npath: %s/not-a-checkout\n' "$TMPDIR_ROOT" > "$AGENTS_B2/workspace.yaml"
run_step \
    "AGENT_PROTOCOL_ROOT=$AGENTS_B2" \
    "FAKE_TOOLS_HELP=$A9_HELP" \
    "FAKE_GH_LOGIN=brettheap" \
    --
assert_equal "$STATUS" '0' '(b2) exit code'
assert_contains "$(tools_argv)" 'argv=wip init' '(b2) the judgement is left to wip init, which owns it'

# ===========================================================================
printf '%s\n' '--- (c) the subcommand is absent: print what to run, and continue ---'
AGENTS_C="$TMPDIR_ROOT/agents-c"
mkdir -p "$AGENTS_C"
run_step \
    "AGENT_PROTOCOL_ROOT=$AGENTS_C" \
    "FAKE_TOOLS_HELP=$PRE_A9_HELP" \
    "FAKE_GH_LOGIN=brettheap" \
    --
assert_equal "$STATUS" '0' '(c) absent subcommand exits 0 -- it degrades, it does not fail'
assert_contains "$OUTPUT" 'no `wip` subcommand yet' '(c) it says plainly what is missing'
assert_contains "$OUTPUT" 'Nothing was created and nothing was changed.' '(c) it says it changed nothing'
assert_contains "$OUTPUT" 'openRepoTools wip init' '(c) it prints the command the person would run'
assert_contains "$OUTPUT" 'update-upstream.py apply' '(c) it prints how to get an openRepoTools that has it'
assert_contains "$OUTPUT" './setup.sh' '(c) it prints the re-run that follows the pin move'
assert_contains "$OUTPUT" 'opensoft/brettheap-wip' '(c) it names the repository that command will create'
assert_not_contains "$(tools_argv)" 'argv=wip' '(c) wip init was NOT invoked'
assert_contains "$(tools_argv)" 'argv=--help' '(c) the capability was probed with --help'

printf '%s\n' '--- (c2) the same, against the openRepoTools this repo vendors TODAY ---'
# Not a fake: the real vendored bytes. Adoption act 3 has not landed, so this
# must degrade -- and the day it does land, this scenario is the one that
# notices, because the real --help will then carry the verb.
AGENTS_C2="$TMPDIR_ROOT/agents-c2"
REAL_BIN="$TMPDIR_ROOT/real-bin"
mkdir -p "$AGENTS_C2" "$REAL_BIN"
cp "$REAL_TOOLS" "$REAL_BIN/openRepoTools"
chmod 755 "$REAL_BIN/openRepoTools"
STATUS_C2=0
OUTPUT_C2="$(env -i "PATH=$FAKE_BIN:/usr/bin:/bin" "HOME=$TMPDIR_ROOT/home" \
    "FAKE_TOOLS_LOG=$TMPDIR_ROOT/unused.log" "FAKE_GH_LOG=$TMPDIR_ROOT/unused-gh.log" \
    "FAKE_GH_LOGIN=brettheap" \
    "AGENT_PROTOCOL_ROOT=$AGENTS_C2" "OPENREPOTOOLS_BIN_DIR=$REAL_BIN" \
    "$SCRIPT_UNDER_TEST" 2>&1 </dev/null)" || STATUS_C2=$?
assert_equal "$STATUS_C2" '0' '(c2) the real vendored openRepoTools degrades, exit 0'
assert_contains "$OUTPUT_C2" 'no `wip` subcommand yet' '(c2) the real vendored copy is correctly seen to lack wip'
assert_contains "$OUTPUT_C2" "$REAL_BIN/openRepoTools" '(c2) it names the openRepoTools it asked'

printf '%s\n' '--- (c3) MUTATION: absence is read from --help, never from an exit code ---'
# A `wip init` that REFUSES prints the administrator block and exits 2 -- the
# same 2 today's openRepoTools gives an unknown argument. A probe that read the
# exit code would call this "no such subcommand" and print the degradation text
# over the block. It must not.
AGENTS_C3="$TMPDIR_ROOT/agents-c3"
mkdir -p "$AGENTS_C3"
run_step \
    "AGENT_PROTOCOL_ROOT=$AGENTS_C3" \
    "FAKE_TOOLS_HELP=$A9_HELP" \
    "FAKE_GH_LOGIN=brettheap" \
    "FAKE_WIP_STDOUT=$ADMIN_BLOCK" \
    "FAKE_WIP_STATUS=2" \
    --
assert_not_contains "$OUTPUT" 'no `wip` subcommand yet' '(c3) a refusal is NOT misreported as a missing subcommand'
assert_not_contains "$OUTPUT" 'update-upstream.py apply' '(c3) the degradation recipe is not printed over a real refusal'
assert_contains "$OUTPUT" 'gh repo create opensoft/brettheap-wip' '(c3) the administrator block survives'

# ===========================================================================
printf '%s\n' '--- (d) missing gh rights: the printed block is SURFACED, not swallowed ---'
AGENTS_D="$TMPDIR_ROOT/agents-d"
mkdir -p "$AGENTS_D"
run_step \
    "AGENT_PROTOCOL_ROOT=$AGENTS_D" \
    "FAKE_TOOLS_HELP=$A9_HELP" \
    "FAKE_GH_LOGIN=brettheap" \
    "FAKE_WIP_STDOUT=$ADMIN_BLOCK" \
    "FAKE_WIP_STATUS=2" \
    --
assert_equal "$STATUS" '1' '(d) a refusal from wip init is this step refusing too (exit 1)'
assert_contains "$OUTPUT" 'gh repo create opensoft/brettheap-wip --private --team estate' '(d) the gh repo create line reaches the terminal verbatim'
assert_contains "$OUTPUT" 'gh api --method PUT /orgs/opensoft/teams/estate/repos/opensoft/brettheap-wip -f permission=pull' '(d) the team-permission PUT reaches the terminal verbatim'
assert_contains "$OUTPUT" "PR-only ruleset" '(d) the ruleset exclusion -- the third administrator act -- reaches the terminal'
assert_contains "$OUTPUT" 'exited 2' '(d) the step names the exit it got rather than hiding it'
assert_contains "$OUTPUT" 'idempotent' '(d) it says the re-run is safe'
# The mutation this guards: a step that captured the output to summarise it.
assert_not_contains "$OUTPUT" 'Workspace repository step refused: no openRepoTools' '(d) it is not confused with the ordering refusal'

printf '%s\n' '--- (d2) ... and through setup.sh own best-effort caller pattern ---'
# setup.sh runs this as `script || echo "warning"`. A `||` cannot eat stdout,
# but a future edit to `output=$(script)` silently could -- so assert the block
# survives the real caller shape, and that setup.sh continues past it.
CALLER="$TMPDIR_ROOT/caller.sh"
cat > "$CALLER" <<EOF
#!/usr/bin/env bash
"\$@" || echo "⚠ Workspace repository step skipped or refused; continuing workBenches setup."
echo "SETUP CONTINUED PAST THE STEP"
EOF
chmod +x "$CALLER"
STATUS_D2=0
OUTPUT_D2="$(env -i "PATH=$FAKE_BIN:/usr/bin:/bin" "HOME=$TMPDIR_ROOT/home" \
    "FAKE_TOOLS_LOG=$TMPDIR_ROOT/d2-tools.log" "FAKE_GH_LOG=$TMPDIR_ROOT/d2-gh.log" \
    "AGENT_PROTOCOL_ROOT=$AGENTS_D" "FAKE_TOOLS_HELP=$A9_HELP" "FAKE_GH_LOGIN=brettheap" \
    "FAKE_WIP_STDOUT=$ADMIN_BLOCK" "FAKE_WIP_STATUS=2" \
    "$CALLER" "$SCRIPT_UNDER_TEST" 2>&1 </dev/null)" || STATUS_D2=$?
assert_equal "$STATUS_D2" '0' '(d2) setup.sh own pattern does not fail the setup'
assert_contains "$OUTPUT_D2" 'gh repo create opensoft/brettheap-wip' '(d2) the block survives the caller'
assert_contains "$OUTPUT_D2" 'SETUP CONTINUED PAST THE STEP' '(d2) setup continues past a refused step'
assert_contains "$(grep -c 'continuing workBenches setup' <<<"$OUTPUT_D2")" '1' '(d2) exactly one best-effort warning'

# ===========================================================================
printf '%s\n' '--- (e1) ordering: with no openRepoTools installed, it refuses and names --install ---'
AGENTS_E="$TMPDIR_ROOT/agents-e"
EMPTY_BIN="$TMPDIR_ROOT/empty-bin"
mkdir -p "$AGENTS_E" "$EMPTY_BIN"
STATUS_E1=0
OUTPUT_E1="$(env -i "PATH=$EMPTY_BIN:/usr/bin:/bin" "HOME=$TMPDIR_ROOT/home" \
    "AGENT_PROTOCOL_ROOT=$AGENTS_E" "OPENREPOTOOLS_BIN_DIR=$EMPTY_BIN" \
    "$SCRIPT_UNDER_TEST" 2>&1 </dev/null)" || STATUS_E1=$?
assert_equal "$STATUS_E1" '2' '(e1) no openRepoTools is exit 2 -- tooling missing, the sibling step own code'
assert_contains "$OUTPUT_E1" 'openRepoTools --install' '(e1) the refusal names the step that must run first'
assert_contains "$OUTPUT_E1" 'scripts/setup-estate-commands.sh' '(e1) ... by the name of the script that runs it'
assert_contains "$OUTPUT_E1" 'Nothing was created' '(e1) and says it created nothing'
assert_not_contains "$OUTPUT_E1" 'no `wip` subcommand yet' '(e1) an absent openRepoTools is not a degraded one'

printf '%s\n' '--- (e2) ordering: the file --install just placed wins over $PATH ---'
# OPENREPOTOOLS_BIN_DIR is where `--install` puts it. If some other
# openRepoTools is earlier on $PATH, this step must still ask the one the step
# above it wrote, or "after --install" means nothing.
PLACED_BIN="$TMPDIR_ROOT/placed-bin"
mkdir -p "$PLACED_BIN"
cat > "$PLACED_BIN/openRepoTools" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'argv=%s\n' "$*" >> "${FAKE_TOOLS_LOG:?}"
printf 'THE PLACED ONE\n'
exit 0
EOF
chmod +x "$PLACED_BIN/openRepoTools"
AGENTS_E2="$TMPDIR_ROOT/agents-e2"
mkdir -p "$AGENTS_E2"
run_step \
    "AGENT_PROTOCOL_ROOT=$AGENTS_E2" \
    "OPENREPOTOOLS_BIN_DIR=$PLACED_BIN" \
    "FAKE_TOOLS_HELP=$A9_HELP" \
    "FAKE_GH_LOGIN=brettheap" \
    --
assert_contains "$OUTPUT" "$PLACED_BIN/openRepoTools" '(e2) the installed file is the one consulted, not the one on $PATH'

printf '%s\n' '--- (e3) ordering, statically: setup.sh calls this AFTER the estate commands ---'
# `|| true` on both: a grep that matches nothing exits 1, and under
# `set -o pipefail` that would abort this suite at the assignment instead of
# letting the emptiness be reported as the failure it is.
estate_line="$(grep -n 'scripts/setup-estate-commands.sh" ||' "$SETUP_SH" | head -n 1 | cut -d: -f1 || true)"
workspace_line="$(grep -n 'scripts/setup-workspace-repo.sh" ||' "$SETUP_SH" | head -n 1 | cut -d: -f1 || true)"
# A step setup.sh never calls is not a step. Both line numbers are checked for
# emptiness FIRST and reported as failures, because a missing call must fail
# this suite loudly rather than crash it on the arithmetic below.
if [ -z "$estate_line" ]; then
    fail "(e3) setup.sh does not invoke scripts/setup-estate-commands.sh at all"
elif [ -z "$workspace_line" ]; then
    fail "(e3) setup.sh does not invoke scripts/setup-workspace-repo.sh at all"
elif [ "$estate_line" -lt "$workspace_line" ]; then
    pass "(e3) setup.sh invokes setup-estate-commands.sh (line $estate_line) before setup-workspace-repo.sh (line $workspace_line)"
else
    fail "(e3) setup.sh calls the workspace step (line $workspace_line) BEFORE the estate commands (line $estate_line)"
fi
assert_contains "$(cat "$SETUP_SH")" 'log_header "WORKSPACE REPOSITORY"' '(e3) it has its own log_header block'
if [ -n "$estate_line" ] && [ -n "$workspace_line" ] && [ "$estate_line" -lt "$workspace_line" ]; then
    assert_contains "$(sed -n "${workspace_line}p" "$SETUP_SH")" '||' '(e3) the workspace step is best-effort in setup.sh, like the estate step'
    # And nothing between them: the chain order of Amendment 9(e) is meant to be
    # readable off one screen of setup.sh.
    between="$(sed -n "$((estate_line + 1)),$((workspace_line - 1))p" "$SETUP_SH" \
        | grep 'SCRIPT_DIR}/scripts/' | grep -cv 'setup-workspace-repo.sh' || true)"
    assert_equal "$between" '0' '(e3) no other script runs between --install and wip init'
fi

# ===========================================================================
printf '%s\n' '--- (f) the prompt count is ZERO ---'
# Brett Heap, 2026-09-12T18:56Z: "there are two options in resume. we need to
# also keep that clean so there is the least choices possible to not confuse
# the user." This step spends none of its one-question budget. Proven twice:
# statically, that no prompt exists in the file at all; and behaviourally, that
# the step completes with no stdin to read.
# Comment lines are stripped first, and `read`/`select` must sit where a
# COMMAND sits -- at the start of a statement, or after ;, |, &, then, do or
# else. Prose that merely contains the word ("could not be read from") is not
# a prompt, and a check that counted it would be a check nobody could keep
# green.
prompt_hits="$(sed 's/^[[:space:]]*#.*$//' "$SCRIPT_UNDER_TEST" \
    | grep -cE '(^|;|\||&|\bthen\b|\bdo\b|\belse\b)[[:space:]]*(read|select)[[:space:]]' || true)"
assert_equal "$prompt_hits" '0' '(f) the step contains no read/select prompt of any kind'
assert_equal "$(grep -c 'read -p' "$SCRIPT_UNDER_TEST" || true)" '0' '(f) ... and no read -p in particular'
AGENTS_F="$TMPDIR_ROOT/agents-f"
mkdir -p "$AGENTS_F"
STATUS_F=0
OUTPUT_F="$(env -i "PATH=$FAKE_BIN:/usr/bin:/bin" "HOME=$TMPDIR_ROOT/home" \
    "FAKE_TOOLS_LOG=$TMPDIR_ROOT/f-tools.log" "FAKE_GH_LOG=$TMPDIR_ROOT/f-gh.log" \
    "AGENT_PROTOCOL_ROOT=$AGENTS_F" "FAKE_TOOLS_HELP=$A9_HELP" "FAKE_GH_LOGIN=brettheap" \
    "$SCRIPT_UNDER_TEST" 2>&1 <&-)" || STATUS_F=$?
assert_equal "$STATUS_F" '0' '(f) it completes with stdin CLOSED -- nothing was waiting to be answered'
assert_contains "$OUTPUT_F" 'you are asked nothing' '(f) and it says so, where the person can read it'

# ===========================================================================
printf '%s\n' '--- (g) the skip switch ---'
AGENTS_G="$TMPDIR_ROOT/agents-g"
mkdir -p "$AGENTS_G"
run_step \
    "AGENT_PROTOCOL_ROOT=$AGENTS_G" \
    "WORKBENCHES_SKIP_WORKSPACE_REPO=1" \
    "FAKE_TOOLS_HELP=$A9_HELP" \
    "FAKE_GH_LOGIN=brettheap" \
    --
assert_equal "$STATUS" '0' '(g) the skip switch exits 0'
assert_contains "$OUTPUT" 'WORKBENCHES_SKIP_WORKSPACE_REPO=1' '(g) it names the switch that skipped it'
assert_file_absent "$TOOLS_LOG" '(g) and runs nothing'

# ===========================================================================
printf '%s\n' '--- (h) the derivations: nothing derivable is ever asked ---'
AGENTS_H="$TMPDIR_ROOT/agents-h"
mkdir -p "$AGENTS_H"

# h1: the login is lowercased, per Amendment 9(c) step 2 and the naming contract.
run_step "AGENT_PROTOCOL_ROOT=$AGENTS_H" "FAKE_TOOLS_HELP=$A9_HELP" "FAKE_GH_LOGIN=BrettHeap" --
assert_contains "$OUTPUT" 'target: opensoft/brettheap-wip' '(h1) a mixed-case login is lowercased'
assert_not_contains "$OUTPUT" 'BrettHeap' '(h1) the raw case never reaches the output'
assert_contains "$(cat "$GH_LOG")" 'argv=api user -q .login' '(h1) the login comes from the call Amendment 9(c) step 2 names'

# h2: the org is the estate rule, overridable -- and an override is the one
# value this step does pass through, because it has no other way in.
run_step "AGENT_PROTOCOL_ROOT=$AGENTS_H" "WORKBENCHES_WORKSPACE_ORG=acme" \
    "FAKE_TOOLS_HELP=$A9_HELP" "FAKE_GH_LOGIN=brettheap" --
assert_contains "$OUTPUT" 'target: acme/brettheap-wip' '(h2) WORKBENCHES_WORKSPACE_ORG changes the derived target'
assert_contains "$(tools_argv)" '--org acme' '(h2) an explicit override IS passed through to wip init'

# h3: and with no override, the estate rule applies with no question asked.
run_step "AGENT_PROTOCOL_ROOT=$AGENTS_H" "FAKE_TOOLS_HELP=$A9_HELP" "FAKE_GH_LOGIN=brettheap" --
assert_contains "$OUTPUT" 'target: opensoft/brettheap-wip' '(h3) the default org is the estate own, per 9(c) step 3'

# h4: no gh at all. Nothing derives -- and the answer is still not a question.
# A PATH with NO gh on it at all. /usr/bin has a real gh on most workstations
# (and on this one), so the fake openRepoTools gets a hermetic bin dir carrying
# only the four externals the step actually uses.
NOGH_BIN="$TMPDIR_ROOT/nogh-bin"
mkdir -p "$NOGH_BIN"
cp "$FAKE_BIN/openRepoTools" "$NOGH_BIN/openRepoTools"
for tool in bash sed head tr grep cat; do
    tool_path="$(command -v "$tool")"
    ln -sf "$tool_path" "$NOGH_BIN/$tool"
done
if command -v gh >/dev/null 2>&1 && [ -x "$NOGH_BIN/gh" ]; then
    fail '(h4) setup error: gh is reachable from the no-gh bin dir'
fi
AGENTS_H4="$TMPDIR_ROOT/agents-h4"
mkdir -p "$AGENTS_H4"
STATUS_H4=0
OUTPUT_H4="$(env -i "PATH=$NOGH_BIN" "HOME=$TMPDIR_ROOT/home" \
    "FAKE_TOOLS_LOG=$TMPDIR_ROOT/h4-tools.log" \
    "AGENT_PROTOCOL_ROOT=$AGENTS_H4" "FAKE_TOOLS_HELP=$PRE_A9_HELP" \
    "$SCRIPT_UNDER_TEST" 2>&1 </dev/null)" || STATUS_H4=$?
assert_equal "$STATUS_H4" '0' '(h4) no gh is still not a failure'
assert_contains "$OUTPUT_H4" 'opensoft/<your-login>-wip' '(h4) the undeducible half is shown as a placeholder, not asked for'
assert_contains "$OUTPUT_H4" '`gh` is not installed' '(h4) it names why it could not derive the login'

# h5: a gh that is installed but not logged in names the command that fixes it.
AGENTS_H5="$TMPDIR_ROOT/agents-h5"
mkdir -p "$AGENTS_H5"
run_step "AGENT_PROTOCOL_ROOT=$AGENTS_H5" "FAKE_TOOLS_HELP=$PRE_A9_HELP" --
assert_equal "$STATUS" '0' '(h5) an unauthenticated gh is still not a failure'
assert_contains "$OUTPUT" 'gh auth login' '(h5) it names the one command that makes the login derivable'
assert_contains "$OUTPUT" '<your-login>' '(h5) and asks for nothing in the meantime'

# ===========================================================================
printf '\n%s\n' "=========================================="
printf '%s\n' "test-setup-workspace-repo.sh: $checks checks, $failures failed"
printf '%s\n' "=========================================="
if [ "$failures" -eq 0 ]; then
    printf '%s\n' "workspace repository step tests passed"
    exit 0
fi
exit 1
