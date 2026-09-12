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
#   (b3)(b4)    a checkout of a DIFFERENT repository, and a `.git` that is a
#               plain file, are both mismatches, not "done" (F2)
#   (b5)        a `path:` that is a SUBDIRECTORY of the real checkout is a
#               mismatch too, not "done" (RV-W2)
#   (l)         normalize_github_repo matches every GitHub remote URL
#               spelling, https/git@/ssh://, with and without `.git` (RV-W1)
#   (m)         the onboarding clone example is runnable as printed, in this
#               script's own header and in README.md (RV-W4)
#   (c)(c2)     the subcommand absent: it prints what to run and continues (0)
#   (c3)        MUTATION: absence is decided by `--help`, NEVER by an exit code
#   (c4)        MUTATION: a bare `wip` in --help PROSE is not capability (F1)
#   (c5)        the degraded path never repairs a noncompliant login (F7)
#   (d)(d2)     the missing-gh-rights path: the administrator block is
#               surfaced, not swallowed -- through this step AND through
#               setup.sh's own best-effort caller pattern
#   (e1-e3)     ordering relative to `--install`, behavioural and static
#   (f)         the prompt count, which is zero, proven two ways
#   (g)         the skip switch
#   (h1-h5)     the derivations: nothing derivable is ever asked
#   (h6)        the login still derives with no `timeout` binary on PATH at
#               all -- stock macOS has none (RV-W3)
#   (j1-j3)     the RUN path never calls a `wip init` this step already knows
#               would refuse -- no gh, an unauthenticated gh, or a
#               noncompliant login all stop here instead (F3, F7)
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

# A mutant left at mode 644 (or any non-executable mode) must fail loudly and
# distinctly, not read as "every scenario caught it" -- `"$SCRIPT_UNDER_TEST"`
# would exit 126 on every single invocation below, which looks exactly like a
# suite that caught a mutation instead of a harness that forgot to `chmod +x`
# the copy it was pointed at.
[ -x "$SCRIPT_UNDER_TEST" ] || {
    printf 'not executable: %s\n' "$SCRIPT_UNDER_TEST" >&2
    exit 2
}

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

assert_file_present() {
    if [ -e "$1" ]; then pass "$2"; else fail "$2: $1 does not exist"; fi
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
# F1: an identity line that names the workspace repository in PROSE, before
# ever shipping the verb. A bare-word probe would call this capable; the
# verb-pair probe must not.
PROSE_ONLY_HELP='openRepoTools --install            install (or update) the estate commands

This command installs the estate commands and does nothing else besides
--install: the helpers read your workspace repository, the wip repository
your register lives in.
openRepoTools --help | --version'

ADMIN_BLOCK='This account cannot create repositories in opensoft. Ask an administrator
for these three, then re-run `openRepoTools wip init`:

    gh repo create opensoft/brettheap-wip --private --team estate \\
        --description "brettheap'"'"'s workspace repository"
    gh api --method PUT /orgs/opensoft/teams/estate/repos/opensoft/brettheap-wip -f permission=pull
    exclude opensoft/brettheap-wip from the organisation'"'"'s PR-only ruleset
'

# A9(a)'s own words for the mismatch this step must never call "done": a
# `path:` that is not a checkout of the `repository:` beside it. This is
# `wip init`'s refusal to give (exit 1 in its own numbering), never this
# step's -- this step's only job is not to short-circuit past it.
MISMATCH_REFUSAL='Error: opensoft/brettheap-wip is not configured here; nothing was created.
A `path:` that is not a checkout of the `repository:` it names beside it is a
mismatch, not a workspace. Fix `path:` in workspace.yaml, or remove it and
re-run to create opensoft/brettheap-wip fresh.
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
assert_file_absent "$AGENTS_A/.workspace-step-needs-attention" '(a) a clean run leaves no needs-attention marker'

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
mkdir -p "$AGENTS_B" "$WS_B"
# A REAL checkout, not a fabricated `.git` directory: the production check is
# `git rev-parse --is-inside-work-tree` plus `remote get-url origin`, so the
# fixture must be one or it only proves the fixture, not the step.
git -C "$WS_B" init -q
git -C "$WS_B" remote add origin "https://github.com/opensoft/brettheap-wip.git"
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

printf '%s\n' '--- (b3) a path: that is a checkout of a DIFFERENT repository is a mismatch, not "done" (F2) ---'
# A9(a): "a `path:` that is not a checkout of the `repository:` it names
# beside it" is the new refusal, and it is `wip init`'s to give -- this step's
# only job is to not call a foreign checkout "already done".
AGENTS_B3="$TMPDIR_ROOT/agents-b3"
WS_B3="$TMPDIR_ROOT/projects/foreign-checkout"
mkdir -p "$AGENTS_B3" "$WS_B3"
git -C "$WS_B3" init -q
git -C "$WS_B3" remote add origin "git@github.com:opensoft/workBenches.git"
printf 'repository: opensoft/brettheap-wip\npath: %s\n' "$WS_B3" > "$AGENTS_B3/workspace.yaml"
run_step \
    "AGENT_PROTOCOL_ROOT=$AGENTS_B3" \
    "FAKE_TOOLS_HELP=$A9_HELP" \
    "FAKE_GH_LOGIN=brettheap" \
    "FAKE_WIP_STDERR=$MISMATCH_REFUSAL" \
    "FAKE_WIP_STATUS=2" \
    --
assert_equal "$STATUS" '1' '(b3) a checkout of a DIFFERENT repository is NOT treated as done'
assert_contains "$(tools_argv)" 'argv=wip init' '(b3) wip init is consulted -- the mismatch judgement is not made here'
assert_contains "$OUTPUT" 'is not a checkout of the' '(b3) the A9(a) mismatch wording is relayed, not summarised or replaced'

printf '%s\n' '--- (b4) a `.git` that is a plain FILE (no git metadata at all) also falls through (F2) ---'
AGENTS_B4="$TMPDIR_ROOT/agents-b4"
WS_B4="$TMPDIR_ROOT/projects/git-is-a-file"
mkdir -p "$AGENTS_B4" "$WS_B4"
: > "$WS_B4/.git"
printf 'repository: opensoft/brettheap-wip\npath: %s\n' "$WS_B4" > "$AGENTS_B4/workspace.yaml"
run_step \
    "AGENT_PROTOCOL_ROOT=$AGENTS_B4" \
    "FAKE_TOOLS_HELP=$A9_HELP" \
    "FAKE_GH_LOGIN=brettheap" \
    --
assert_equal "$STATUS" '0' '(b4) exit code'
assert_contains "$(tools_argv)" 'argv=wip init' '(b4) a `.git` FILE is not a checkout either -- wip init is consulted'

# ===========================================================================
printf '%s\n' '--- (b5) a path: that is a SUBDIRECTORY of the real checkout is a mismatch too, not "done" (RV-W2) ---'
# `git -C "$path" rev-parse --is-inside-work-tree` and `remote get-url origin`
# both succeed from inside ANY subdirectory of a work tree -- not just its
# root -- so `path:` pointing one level too deep must not read as "already
# checked out" either. Reproduced exactly as the review found it: `path:`
# names a real subdirectory of a checkout whose origin DOES match.
AGENTS_B5="$TMPDIR_ROOT/agents-b5"
WS_B5="$TMPDIR_ROOT/projects/brettheap-wip-nested"
mkdir -p "$AGENTS_B5" "$WS_B5/nested"
git -C "$WS_B5" init -q
git -C "$WS_B5" remote add origin "https://github.com/opensoft/brettheap-wip.git"
printf 'repository: opensoft/brettheap-wip\npath: %s/nested\n' "$WS_B5" > "$AGENTS_B5/workspace.yaml"
run_step \
    "AGENT_PROTOCOL_ROOT=$AGENTS_B5" \
    "FAKE_TOOLS_HELP=$A9_HELP" \
    "FAKE_GH_LOGIN=brettheap" \
    --
assert_equal "$STATUS" '0' '(b5) exit code'
assert_not_contains "$OUTPUT" 'already checked out' '(b5) a subdirectory path: is never reported as already checked out'
assert_contains "$(tools_argv)" 'argv=wip init' '(b5) a path: pointing at a SUBDIRECTORY of the real checkout is not "already done" -- wip init is consulted'

printf '%s\n' '--- (l) RV-W1: normalize_github_repo matches every GitHub remote URL spelling ---'
# One idempotence check per spelling `git remote get-url origin` can print for
# the same repository, reproduced end-to-end through workspace_repo_matches --
# the path production actually takes -- rather than as a unit test of the
# private function. ssh:// is the spelling the review found missing; the
# other five are run alongside it so a future regression in ANY spelling is
# caught the same way.
check_url_form() {
    local label="$1" remote_url="$2"
    local agents_dir="$TMPDIR_ROOT/agents-l-$label"
    local ws_dir="$TMPDIR_ROOT/projects/wip-l-$label"
    mkdir -p "$agents_dir" "$ws_dir"
    git -C "$ws_dir" init -q
    git -C "$ws_dir" remote add origin "$remote_url"
    printf 'repository: opensoft/brettheap-wip\npath: %s\n' "$ws_dir" > "$agents_dir/workspace.yaml"
    run_step "AGENT_PROTOCOL_ROOT=$agents_dir" "FAKE_TOOLS_HELP=$A9_HELP" "FAKE_GH_LOGIN=brettheap" --
    assert_equal "$STATUS" '0' "(l) $label exit code"
    assert_contains "$OUTPUT" 'already checked out' "(l) $label ($remote_url) is recognised as the same repository"
    assert_file_absent "$TOOLS_LOG" "(l) $label: openRepoTools was not invoked -- the URL form matched"
}
check_url_form 'https'            'https://github.com/opensoft/brettheap-wip'
check_url_form 'https-dotgit'     'https://github.com/opensoft/brettheap-wip.git'
check_url_form 'scp-like'         'git@github.com:opensoft/brettheap-wip'
check_url_form 'scp-like-dotgit'  'git@github.com:opensoft/brettheap-wip.git'
check_url_form 'ssh'              'ssh://git@github.com/opensoft/brettheap-wip'
check_url_form 'ssh-dotgit'       'ssh://git@github.com/opensoft/brettheap-wip.git'

printf '%s\n' '--- (m) RV-W4: the onboarding clone example is runnable as printed ---'
assert_contains "$(sed -n '1,20p' "$SCRIPT_UNDER_TEST")" \
    'gh repo clone opensoft/workBenches && cd workBenches && ./setup.sh' \
    '(m) this script own header cd'"'"'s into the clone before ./setup.sh'
assert_contains "$(cat "$REPO_ROOT/README.md" 2>/dev/null || true)" \
    'gh repo clone opensoft/workBenches && cd workBenches && ./setup.sh' \
    '(m) README.md prints the same runnable clone example'

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
# notices, because the real --help will then carry the verb. THAT DAY, the
# act-3 pin-move PR must update this scenario (and (c)'s siblings that assert
# "no `wip` subcommand yet") in the same commit, or CI (F4) lands red on this
# suite rather than green on a stale assumption.
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

printf '%s\n' '--- (c4) MUTATION: a bare `wip` in --help PROSE is not capability (F1) ---'
# Amendment 9(b) rewrites the identity line to describe the workspace
# repository in prose before the verb ever ships. A probe that matched a bare
# word would call this capable and invoke `wip init`; this fake's `wip` arm is
# made to die exactly as a real "no such subcommand" would, so a regression
# here is loud and unmistakable rather than silently swallowed.
AGENTS_C4="$TMPDIR_ROOT/agents-c4"
mkdir -p "$AGENTS_C4"
run_step \
    "AGENT_PROTOCOL_ROOT=$AGENTS_C4" \
    "FAKE_TOOLS_HELP=$PROSE_ONLY_HELP" \
    "FAKE_GH_LOGIN=brettheap" \
    "FAKE_WIP_STDERR=\nREFUSED: openRepoTools installs the estate commands and does nothing else.\n" \
    "FAKE_WIP_STATUS=2" \
    --
assert_equal "$STATUS" '0' '(c4) help that only mentions "wip" in prose still degrades (exit 0)'
assert_contains "$OUTPUT" 'no `wip` subcommand yet' '(c4) it is reported as absent, not as a refusal'
assert_not_contains "$OUTPUT" 'REFUSED' "(c4) the fake's die text never reaches the person -- the verb was never invoked"
assert_not_contains "$(tools_argv)" 'argv=wip' '(c4) `wip init` was NEVER invoked against prose-only help'

printf '%s\n' '--- (c5) the degraded path never repairs a noncompliant login either (F7) ---'
AGENTS_C5="$TMPDIR_ROOT/agents-c5"
mkdir -p "$AGENTS_C5"
run_step \
    "AGENT_PROTOCOL_ROOT=$AGENTS_C5" \
    "FAKE_TOOLS_HELP=$PRE_A9_HELP" \
    "FAKE_GH_LOGIN=Brett_Heap" \
    --
assert_equal "$STATUS" '0' '(c5) degraded path is still not a failure'
assert_not_contains "$OUTPUT" 'brett_heap-wip' '(c5) the noncompliant name is never repaired or printed as a target'
assert_not_contains "$OUTPUT" '<your-login>' '(c5) and no placeholder either (R-A9-3)'
assert_contains "$OUTPUT" 'naming pattern' '(c5) it names the pattern instead, per F7'

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
assert_file_present "$AGENTS_D/.workspace-step-needs-attention" '(d) a refusal leaves the needs-attention marker for setup.sh to find (F9)'

printf '%s\n' '--- (d3) ... and a later CLEAN run removes that marker (F9) ---'
run_step \
    "AGENT_PROTOCOL_ROOT=$AGENTS_D" \
    "FAKE_TOOLS_HELP=$A9_HELP" \
    "FAKE_GH_LOGIN=brettheap" \
    "FAKE_WIP_STDOUT=created opensoft/brettheap-wip\n" \
    --
assert_equal "$STATUS" '0' '(d3) the re-run succeeds'
assert_file_absent "$AGENTS_D/.workspace-step-needs-attention" '(d3) ... and the marker left by (d) is gone'

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
AGENTS_D2="$TMPDIR_ROOT/agents-d2"
mkdir -p "$AGENTS_D2"
STATUS_D2=0
OUTPUT_D2="$(env -i "PATH=$FAKE_BIN:/usr/bin:/bin" "HOME=$TMPDIR_ROOT/home" \
    "FAKE_TOOLS_LOG=$TMPDIR_ROOT/d2-tools.log" "FAKE_GH_LOG=$TMPDIR_ROOT/d2-gh.log" \
    "AGENT_PROTOCOL_ROOT=$AGENTS_D2" "FAKE_TOOLS_HELP=$A9_HELP" "FAKE_GH_LOGIN=brettheap" \
    "FAKE_WIP_STDOUT=$ADMIN_BLOCK" "FAKE_WIP_STATUS=2" \
    "$CALLER" "$SCRIPT_UNDER_TEST" 2>&1 </dev/null)" || STATUS_D2=$?
assert_equal "$STATUS_D2" '0' '(d2) setup.sh own pattern does not fail the setup'
assert_contains "$OUTPUT_D2" 'gh repo create opensoft/brettheap-wip' '(d2) the block survives the caller'
assert_contains "$OUTPUT_D2" 'SETUP CONTINUED PAST THE STEP' '(d2) setup continues past a refused step'
assert_equal "$(grep -c 'continuing workBenches setup' <<<"$OUTPUT_D2")" '1' '(d2) exactly one best-effort warning'

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
assert_file_present "$AGENTS_E/.workspace-step-needs-attention" '(e1) a precondition refusal also leaves the marker (F9)'

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
# only the externals the step actually uses when gh is absent.
NOGH_BIN="$TMPDIR_ROOT/nogh-bin"
mkdir -p "$NOGH_BIN"
cp "$FAKE_BIN/openRepoTools" "$NOGH_BIN/openRepoTools"
for tool in bash sed head tr grep cat mkdir rm; do
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
assert_not_contains "$OUTPUT_H4" '<your-login>' '(h4) the undeducible half is OMITTED, never shown as a placeholder (R-A9-3)'
assert_contains "$OUTPUT_H4" '`gh` is not installed' '(h4) it names why it could not derive the login'

# h5: a gh that is installed but not logged in names the command that fixes it.
AGENTS_H5="$TMPDIR_ROOT/agents-h5"
mkdir -p "$AGENTS_H5"
run_step "AGENT_PROTOCOL_ROOT=$AGENTS_H5" "FAKE_TOOLS_HELP=$PRE_A9_HELP" --
assert_equal "$STATUS" '0' '(h5) an unauthenticated gh is still not a failure'
assert_contains "$OUTPUT" 'gh auth login' '(h5) it names the one command that makes the login derivable'
assert_not_contains "$OUTPUT" '<your-login>' '(h5) and no placeholder either, in the meantime (R-A9-3)'

# h6 (RV-W3): GNU `timeout` is not on a stock macOS PATH -- the very platform
# F8's 10s guard was added for. A PATH with `gh` reachable but NO `timeout`
# binary at all must still derive the login, not silently misreport a
# fully-authenticated `gh` as unauthenticated (which `timeout ... || true`
# would do if `timeout` failed to exec and that were swallowed).
printf '%s\n' '--- (h6) RV-W3: the login still derives with no `timeout` binary on PATH ---'
NOTIMEOUT_BIN="$TMPDIR_ROOT/notimeout-bin"
mkdir -p "$NOTIMEOUT_BIN"
cp "$FAKE_BIN/openRepoTools" "$NOTIMEOUT_BIN/openRepoTools"
cp "$FAKE_BIN/gh" "$NOTIMEOUT_BIN/gh"
for tool in bash sed head tr grep cat mkdir rm; do
    tool_path="$(command -v "$tool")"
    ln -sf "$tool_path" "$NOTIMEOUT_BIN/$tool"
done
assert_file_absent "$NOTIMEOUT_BIN/timeout" '(h6) setup: the hermetic PATH has no timeout binary'
AGENTS_H6="$TMPDIR_ROOT/agents-h6"
mkdir -p "$AGENTS_H6"
H6_TOOLS_LOG="$TMPDIR_ROOT/h6-tools.log"
H6_GH_LOG="$TMPDIR_ROOT/h6-gh.log"
STATUS_H6=0
OUTPUT_H6="$(env -i "PATH=$NOTIMEOUT_BIN" "HOME=$TMPDIR_ROOT/home" \
    "FAKE_TOOLS_LOG=$H6_TOOLS_LOG" "FAKE_GH_LOG=$H6_GH_LOG" \
    "AGENT_PROTOCOL_ROOT=$AGENTS_H6" "FAKE_TOOLS_HELP=$A9_HELP" "FAKE_GH_LOGIN=brettheap" \
    "$SCRIPT_UNDER_TEST" 2>&1 </dev/null)" || STATUS_H6=$?
assert_equal "$STATUS_H6" '0' '(h6) exit code with no `timeout` binary present'
assert_contains "$OUTPUT_H6" 'target: opensoft/brettheap-wip' '(h6) the login still derives with no `timeout` present'
assert_contains "$(cat "$H6_GH_LOG" 2>/dev/null || true)" 'argv=api user -q .login' '(h6) gh was still called directly, without a timeout wrapper'

# ===========================================================================
printf '%s\n' '--- (j) the RUN path never calls a `wip init` this step already knows would refuse ---'
# F3 + F7: `wip init` needs this same login (9(c) step 2) and would refuse for
# exactly the reason this step already knows -- so calling it anyway would
# only relay a refusal already known here, and it is the one place a
# placeholder could still have leaked (F3's worst case). All three stop
# BEFORE invoking wip init, name the precondition, and exit 2 -- the same code
# `wip init` uses for its own refusals -- never 1, which would claim it ran.

printf '%s\n' '--- (j1) wip IS capable, but no gh at all: stop before calling it ---'
AGENTS_J1="$TMPDIR_ROOT/agents-j1"
mkdir -p "$AGENTS_J1"
J1_TOOLS_LOG="$TMPDIR_ROOT/j1-tools.log"
STATUS_J1=0
OUTPUT_J1="$(env -i "PATH=$NOGH_BIN" "HOME=$TMPDIR_ROOT/home" \
    "FAKE_TOOLS_LOG=$J1_TOOLS_LOG" \
    "AGENT_PROTOCOL_ROOT=$AGENTS_J1" "FAKE_TOOLS_HELP=$A9_HELP" \
    "$SCRIPT_UNDER_TEST" 2>&1 </dev/null)" || STATUS_J1=$?
assert_equal "$STATUS_J1" '2' '(j1) stops rather than calling a wip init that would only refuse the same way'
assert_contains "$OUTPUT_J1" 'gh' '(j1) it names gh as the precondition'
assert_not_contains "$OUTPUT_J1" 'target:' '(j1) no target: line -- nothing was derived to show'
assert_not_contains "$OUTPUT_J1" '<your-login>' '(j1) and no placeholder either (R-A9-3)'
assert_not_contains "$(cat "$J1_TOOLS_LOG" 2>/dev/null || true)" 'argv=wip' '(j1) `wip init` itself was never invoked'
assert_file_present "$AGENTS_J1/.workspace-step-needs-attention" '(j1) the stop leaves the needs-attention marker too (F9)'

printf '%s\n' '--- (j2) wip IS capable, gh installed but not authenticated: stop, name gh auth login ---'
AGENTS_J2="$TMPDIR_ROOT/agents-j2"
mkdir -p "$AGENTS_J2"
run_step \
    "AGENT_PROTOCOL_ROOT=$AGENTS_J2" \
    "FAKE_TOOLS_HELP=$A9_HELP" \
    --
assert_equal "$STATUS" '2' '(j2) stops rather than calling a wip init that would only refuse the same way'
assert_contains "$OUTPUT" 'gh auth login' '(j2) it names the one command that fixes it'
assert_not_contains "$OUTPUT" 'target:' '(j2) no target: line -- nothing was derived to show'
assert_not_contains "$OUTPUT" '<your-login>' '(j2) and no placeholder either (R-A9-3)'
assert_not_contains "$(tools_argv)" 'argv=wip' '(j2) `wip init` itself was never invoked'

printf '%s\n' '--- (j3) wip IS capable, login derived but not compliant with <login>-wip (F7): stop, name the pattern ---'
AGENTS_J3="$TMPDIR_ROOT/agents-j3"
mkdir -p "$AGENTS_J3"
run_step \
    "AGENT_PROTOCOL_ROOT=$AGENTS_J3" \
    "FAKE_TOOLS_HELP=$A9_HELP" \
    "FAKE_GH_LOGIN=Brett_Heap" \
    --
assert_equal "$STATUS" '2' '(j3) stops rather than calling a wip init that would refuse the same login'
assert_contains "$OUTPUT" '[a-z0-9]' '(j3) it names the naming pattern, not a repaired or placeholder name'
assert_not_contains "$OUTPUT" 'brett_heap-wip' '(j3) the noncompliant name never reaches a target: line'
assert_not_contains "$OUTPUT" 'target:' '(j3) no target: line -- nothing was derived to show'
assert_not_contains "$(tools_argv)" 'argv=wip' '(j3) `wip init` itself was never invoked'

# ===========================================================================
printf '\n%s\n' "=========================================="
printf '%s\n' "test-setup-workspace-repo.sh: $checks checks, $failures failed"
printf '%s\n' "=========================================="
if [ "$failures" -eq 0 ]; then
    printf '%s\n' "workspace repository step tests passed"
    exit 0
fi
exit 1
