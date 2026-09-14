#!/usr/bin/env bash
#
# scripts/setup-workspace-repo.sh
#
# The workspace-repository step of the onboarding chain -- lane-collision-protocol
# Amendment 9(e). The chain a new person walks, in the amendment's own order:
#
#   gh repo clone opensoft/workBenches && cd workBenches && ./setup.sh
#   openRepoTools --install                   <- scripts/setup-estate-commands.sh
#   openRepoTools wip init                    <- THIS SCRIPT
#   pclaude run <profile> --lane <repo>-<n>
#   lane-start <repo> <n>
#
# ORDER IS THE POINT, NOT AN ACCIDENT. `wip init` is a subcommand of the
# openRepoTools that `--install` places, so this step is meaningless until that
# one has run. setup.sh therefore calls this script immediately after
# scripts/setup-estate-commands.sh and nowhere else, and this script refuses
# (exit 2) rather than guessing when no openRepoTools is installed -- which is
# what an out-of-order call looks like from in here.
#
# THIS STEP ASKS THE PERSON NOTHING. Brett Heap, 2026-09-12T18:56Z, on the
# onboarding chain: "there are two options in resume. we need to also keep that
# clean so there is the least choices possible to not confuse the user." Every
# input this step needs is derived, none is asked:
#
#   the login   `gh api user -q .login`, lowercased -- Amendment 9(c) step 2,
#               which is also the naming contract's own definition of <user>.
#   the org     the person's home organisation, `opensoft` in this estate --
#               Amendment 9(c) step 3. WORKBENCHES_WORKSPACE_ORG overrides it
#               for an estate that is not this one.
#   the repo    <org>/<login>-wip, from the two above.
#
# There is no prompt in this file, in either path, and none is reachable
# through it: `openRepoTools wip init` is handed no question of ours, and
# where nothing derives (no gh, a gh that is not logged in, or a login that
# cannot form a compliant name) this step prints the one fact that explains why
# and continues or stops as that fact requires -- rather than asking for what
# it could not read, and rather than ever printing a name it made up. R-A9-3,
# ratified: derive or omit, never a placeholder. The one-question budget
# Brett's direction allows is deliberately unspent.
#
# IT DEGRADES RATHER THAN FAILING, AND IT DEGRADES ON `--help`, NOT ON AN EXIT
# CODE. The verb ARRIVED with the 8a36eb3 pin (opensoft/openRepoTools#24, Amendment
# 9's adoption act 3, which sequenced that change after opensoft/brett-wip's
# Amendment 8 PR merged): the openRepoTools this repository vendors today DOES carry
# `wip init`, and the `--help` probe below is what turns this step live rather than
# a Dockerfile or pin-file change on its own -- the probe is what decides, every
# time this script runs, not a fact frozen in this comment. The degradation path
# stays, for an EARLIER or hand-installed openRepoTools that predates act 3: there,
# `openRepoTools wip init` is an unknown argument. An unknown argument makes
# openRepoTools `die`, and `die`'s default exit is 2 -- which is ALSO the exit
# Amendment 9(c) gives `wip init`'s own refusals. One number, two meanings. So
# capability is decided by asking `openRepoTools --help` whether it documents the
# VERB PAIR `wip init`, never by a bare mention of the word `wip` (prose can name
# the workspace repository without shipping the command, and a probe that matched
# the word would call that capable) and never by running the verb and reading what
# comes back: a probe that read the exit code would report a genuine refusal --
# the administrator's `gh repo create` block of Amendment 9(c) step 4, printed and
# then exited 2 -- as "no such subcommand", and would swallow the one piece of
# output the person most needs to see. (The same shape as the launcher's
# `lane-start --help` probe for `--confirm`, opensoft/workBenches#63.)
#
# NOTHING THIS STEP RUNS HAS ITS OUTPUT CAPTURED. `openRepoTools wip init`
# writes straight to this script's stdout and stderr, which are setup.sh's,
# which are the terminal's. The administrator block, the refusals and the next
# step it prints are relayed byte for byte; this script adds no summary that
# could stand in for them and never stores them in a variable it might drop.
# Because that block can still scroll off a screen that runs nine more headers
# after this one, a refusal (exit 1) or a stopped precondition (exit 2, see
# below) also leaves a marker file behind -- $AGENT_PROTOCOL_ROOT/
# .workspace-step-needs-attention -- which setup.sh's own SETUP COMPLETE
# summary checks for and points back at this step's slice of the log. A later
# run that finishes clean (exit 0) removes it.
#
# Set WORKBENCHES_SKIP_WORKSPACE_REPO=1 to skip this step entirely (prints one
# line, exits 0).
#
# AGENT_PROTOCOL_ROOT overrides the directory holding workspace.yaml (default
# "$HOME/.agents"), the estate's own convention for that path and the
# environment override Amendment 9(a) permits for sandbox tests.
# OPENREPOTOOLS_BIN_DIR is honoured as openRepoTools' own installer honours it.
#
# Exit codes when run directly:
#   0  ok -- this host already has a workspace, or `wip init` did the work, or
#      this openRepoTools has no `wip` yet and the step printed what to run
#      instead.
#   1  `openRepoTools wip init` itself ran and refused -- its own output above
#      says why.
#   2  nothing was attempted -- either no openRepoTools is installed
#      (`openRepoTools --install` has not run yet), or this step already knows
#      a precondition `wip init` itself would refuse on (no `gh`, a `gh` that
#      is not logged in, or a login that cannot form `<login>-wip`) and has
#      named it rather than making a doomed call and relaying its refusal.
# setup.sh runs this under `log_header "WORKSPACE REPOSITORY"` and treats any
# non-zero exit here as best-effort, continuing either way, exactly as it
# treats the estate command step above it; this script is also safe to run
# directly, any time, as many times as you like.

set -euo pipefail

DRY_RUN=""
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN="1"; shift ;;
        -h|--help)
            cat <<'USAGE'
setup-workspace-repo.sh [--dry-run]

The workspace-repository step of the onboarding chain (lane-collision-protocol
Amendment 9(e)): runs `openRepoTools wip init` after `openRepoTools --install`
has placed it. Asks nothing -- the login comes from `gh api user -q .login`
lowercased and the organisation from the amendment's own rule. Idempotent: a
host that already has ~/.agents/workspace.yaml naming a repository AND checked
out at its `path:` runs nothing. An openRepoTools with no `wip` subcommand yet
prints what to run and continues.

  --dry-run   rehearse; passed through to `openRepoTools wip init --dry-run`

Environment:
  WORKBENCHES_SKIP_WORKSPACE_REPO=1   skip this step entirely
  WORKBENCHES_WORKSPACE_ORG=<org>     the organisation (default: opensoft)
  AGENT_PROTOCOL_ROOT=<dir>           where workspace.yaml lives (~/.agents)
  OPENREPOTOOLS_BIN_DIR=<dir>         where openRepoTools was installed

Exits: 0 ok or already done; 1 `wip init` refused; 2 nothing attempted --
openRepoTools not installed, or a precondition `wip init` would refuse on (no
`gh`, an unauthenticated `gh`, or a login that cannot form `<login>-wip`) is
already known here.
USAGE
            exit 0
            ;;
        *)
            printf '%s\n' "setup-workspace-repo.sh takes --dry-run or --help and nothing else." >&2
            exit 2
            ;;
    esac
done

AGENTS_DIR="${AGENT_PROTOCOL_ROOT:-$HOME/.agents}"
WORKSPACE_YAML="$AGENTS_DIR/workspace.yaml"
NEEDS_ATTENTION_MARKER="$AGENTS_DIR/.workspace-step-needs-attention"

# A step whose most important output can scroll off screen (the header above
# explains why) leaves one breadcrumb behind for setup.sh's own summary to
# find, and clears it the moment a run finishes clean.
mark_needs_attention() {
    mkdir -p "$AGENTS_DIR" 2>/dev/null || true
    : > "$NEEDS_ATTENTION_MARKER" 2>/dev/null || true
}
clear_needs_attention() {
    rm -f "$NEEDS_ATTENTION_MARKER" 2>/dev/null || true
}

if [ "${WORKBENCHES_SKIP_WORKSPACE_REPO:-}" = "1" ]; then
    printf '%s\n' "Workspace repository step skipped by WORKBENCHES_SKIP_WORKSPACE_REPO=1."
    clear_needs_attention
    exit 0
fi

# --- step 1: detect, the way Amendment 9(c) step 1 detects -------------------
#
# Local checks only, never a network call, and deliberately conservative: a
# `repository:` and a `path:` must both be in the file, that path must be a
# real git checkout, AND its `origin` must resolve to that same `repository:`
# -- A9(a) in its own words: "a `path:` that is not a checkout of the
# `repository:` it names beside it" is a mismatch, not a pass, and "nothing
# validates it today ... so a `path:` pointing at some other repository is
# currently accepted and after this is not." Anything less -- a half-written
# file, a path that is no checkout, a checkout of some OTHER repository, a
# `.git` that is a stray file and not a checkout at all -- falls THROUGH to
# `wip init`, which is idempotent and is the owner of that judgement (its own
# refusal, A9(a), exit 1). Two owners of one judgement is two answers, and
# Amendment 9(a) is explicit that "a second way to find it is a second
# answer".
yaml_value() {
    # `key: value`, with optional quotes, an inline `#` comment and a leading
    # ~ expanded. One key, first occurrence, top level only -- the `orgs:` map
    # Amendment 9(a) puts out of scope is indented, so an anchored match never
    # reaches into it. The comment and trailing whitespace are stripped BEFORE
    # the surrounding quotes: `path: "~/projects/wip" # default checkout` must
    # not leave a trailing quote stuck to the end of the value.
    local key="$1" file="$2" line
    line="$(sed -n "s/^${key}:[[:space:]]*//p" "$file" 2>/dev/null | head -n 1)" || return 0
    line="${line%%[[:space:]]#*}"
    line="${line%"${line##*[![:space:]]}"}"
    line="${line%\"}"; line="${line#\"}"
    line="${line%\'}"; line="${line#\'}"
    case "$line" in
        "~/"*) line="$HOME/${line#\~/}" ;;
        "~") line="$HOME" ;;
    esac
    printf '%s\n' "$line"
}

normalize_github_repo() {
    # Reduce one of the six spellings `git remote get-url origin` can print
    # for the same GitHub repository -- https://github.com/<repo>(.git)?,
    # git@github.com:<repo>(.git)?, and ssh://git@github.com/<repo>(.git)? --
    # to a bare, lowercased "<org>/<name>", so it can be compared against
    # workspace.yaml's own "<org>/<name>" spelling. RV-W1: ssh:// is a real
    # spelling `git remote get-url origin` prints and was missing here, which
    # made the idempotence check below (RV-W2) fall through to `wip init` for
    # a host whose checkout uses it -- silently, and on every re-run.
    local url="$1"
    url="${url%.git}"
    case "$url" in
        https://github.com/*) url="${url#https://github.com/}" ;;
        ssh://git@github.com/*) url="${url#ssh://git@github.com/}" ;;
        git@github.com:*) url="${url#git@github.com:}" ;;
    esac
    printf '%s\n' "$(printf '%s' "$url" | tr '[:upper:]' '[:lower:]')"
}

workspace_repo_matches() {
    # Is $2 (workspace.yaml's `path:`) the ROOT of a checkout of $1 (its
    # `repository:`)? Local only, no network -- same as the rest of step 1.
    # RV-W2: `rev-parse --is-inside-work-tree` and `remote get-url origin`
    # both succeed from ANY subdirectory of a work tree, not just its root --
    # so root-ness is its own check, not implied by the two above. Amendment
    # 9(a) resolves the register at `<path>/lanes/LANES.md`, and a `path:`
    # that names a subdirectory of the real checkout would otherwise be
    # accepted here and silently resolve that file inside the wrong
    # directory. Both sides are realpath-normalised (`pwd -P`, the same idiom
    # this suite's own test harness uses for TEST_DIR/REPO_ROOT) so a symlink
    # in the parent chain cannot produce a false mismatch either.
    local want="$1" path="$2" origin toplevel real_path
    git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
    origin="$(git -C "$path" remote get-url origin 2>/dev/null)" || return 1
    [ "$(normalize_github_repo "$origin")" = "$(normalize_github_repo "$want")" ] || return 1
    toplevel="$(git -C "$path" rev-parse --show-toplevel 2>/dev/null)" || return 1
    real_path="$(cd "$path" 2>/dev/null && pwd -P)" || return 1
    [ "$toplevel" = "$real_path" ]
}

if [ -f "$WORKSPACE_YAML" ]; then
    existing_repo="$(yaml_value repository "$WORKSPACE_YAML")"
    existing_path="$(yaml_value path "$WORKSPACE_YAML")"
    if [ -n "$existing_repo" ] && [ -n "$existing_path" ] \
        && workspace_repo_matches "$existing_repo" "$existing_path"; then
        printf '%s\n' "Workspace repository: $existing_repo already checked out at $existing_path"
        printf '%s\n' "  ($WORKSPACE_YAML names it; nothing to do.)"
        clear_needs_attention
        exit 0
    fi
fi

# --- step 2: find the openRepoTools that `--install` placed ------------------
#
# The installed file first, because that is the one the step above this one
# just wrote and the one whose version this host is meant to be running; then
# $PATH, for a host that installed it somewhere else. Not found is not a
# degradation -- it is this step running before the one it depends on.
tools_bin_dir="${OPENREPOTOOLS_BIN_DIR:-$HOME/.local/bin}"
TOOLS=""
if [ -x "$tools_bin_dir/openRepoTools" ]; then
    TOOLS="$tools_bin_dir/openRepoTools"
elif command -v openRepoTools >/dev/null 2>&1; then
    TOOLS="$(command -v openRepoTools)"
fi

if [ -z "$TOOLS" ]; then
    printf '%s\n' "Workspace repository step refused: no openRepoTools is installed." >&2
    printf '%s\n' "  Looked for: $tools_bin_dir/openRepoTools, then \$PATH." >&2
    printf '%s\n' "  It is installed by the step before this one," >&2
    printf '%s\n' "  scripts/setup-estate-commands.sh (\`openRepoTools --install\`)." >&2
    printf '%s\n' "  Nothing was created." >&2
    mark_needs_attention
    exit 2
fi

# --- step 3: does this openRepoTools know the verb at all? -------------------
#
# `--help`, for the reason the header gives at length: the exit code cannot
# tell "no such subcommand" from "refused", and reading it that way would eat
# the administrator's block. Matched as the verb PAIR, never a bare word --
# prose can name "the wip repository" without ever shipping the command.
tools_help="$("$TOOLS" --help 2>/dev/null || true)"
HAS_WIP=""
if printf '%s' "$tools_help" | grep -Eq '(^|[[:space:]])wip[[:space:]]+init([[:space:]]|$)'; then
    HAS_WIP="1"
fi

# --- the derivations, which are also the whole of this step's input ----------
#
# Run AFTER the capability probe above, not before: on the live path today
# (no `wip` yet) the only consumer of these is a cosmetic name in a message
# that changes nothing, and a network call has no business running ahead of a
# probe that might make it moot. Computed here for what this step PRINTS,
# never handed to `wip init` as an answer: Amendment 9(c) steps 2 and 3 have
# it derive the login and the organisation itself, by these same two rules,
# and a value passed in from here would be a second answer to a question that
# already has one. The exception is an operator who set
# WORKBENCHES_WORKSPACE_ORG, which has no other way in and is therefore passed
# through as `--org`.
derive_login() {
    local login=""
    command -v gh >/dev/null 2>&1 || return 0
    # RV-W3: GNU `timeout` is not on a stock macOS PATH -- the very platform
    # F8's 10s guard against a hung `gh api user` was added for. Used
    # unconditionally, `timeout 10 ...` fails to exec at all there, and
    # `|| true` swallows that "command not found" the same way it swallows a
    # real timeout, so a fully-authenticated `gh` is misread as
    # unauthenticated. Guarded exactly as scripts/ensure-layer3.sh already
    # guards its own `timeout` use (its `run_docker_probe`).
    if command -v timeout >/dev/null 2>&1; then
        login="$(timeout 10 gh api user -q .login 2>/dev/null || true)"
    else
        login="$(gh api user -q .login 2>/dev/null || true)"
    fi
    printf '%s\n' "$(printf '%s' "$login" | tr '[:upper:]' '[:lower:]')"
}

login_is_compliant() {
    # Amendment 9(c) step 2's own naming pattern for the login half of
    # <login>-wip, `^[a-z0-9]+(?:-[a-z0-9]+)*$` -- openRepoShape's naming
    # contract, quoted in full in the messages below. A login that fails it
    # (an underscore, a leading, trailing or doubled hyphen) is exactly as
    # underivable as no login at all: `wip init` would refuse it by the same
    # rule, naming the pattern and never repairing it by guesswork (R-A9-3),
    # so this step treats it the same way rather than forming a name that
    # command would only refuse (F7).
    case "$1" in
        ''|*[![:lower:][:digit:]-]*|-*|*-|*--*) return 1 ;;
        *) return 0 ;;
    esac
}

LOGIN="$(derive_login)"
LOGIN_ISSUE=""
if [ -z "$LOGIN" ]; then
    if command -v gh >/dev/null 2>&1; then
        LOGIN_ISSUE="unauth"
    else
        LOGIN_ISSUE="nogh"
    fi
elif ! login_is_compliant "$LOGIN"; then
    LOGIN_ISSUE="pattern"
    LOGIN=""
fi

ORG="${WORKBENCHES_WORKSPACE_ORG:-opensoft}"
TARGET=""
if [ -n "$LOGIN" ]; then
    TARGET="$ORG/$LOGIN-wip"
fi

if [ -z "$HAS_WIP" ]; then
    printf '%s\n' "Workspace repository: this openRepoTools has no \`wip\` subcommand yet."
    printf '%s\n' "  $TOOLS"
    printf '%s\n' "  Nothing was created and nothing was changed."
    printf '%s\n' ""
    printf '%s\n' "  \`openRepoTools wip init\` arrives with lane protocol Amendment 9's"
    printf '%s\n' "  adoption act 3, which lands in opensoft/openRepoTools after"
    printf '%s\n' "  opensoft/brett-wip's Amendment 8 PR merges. Until then this host has"
    printf '%s\n' "  no way to create a workspace repository and this step does nothing."
    printf '%s\n' ""
    printf '%s\n' "  When it has landed, move workBenches' pin to that commit and re-run"
    printf '%s\n' "  setup.sh -- these two, in this order:"
    printf '%s\n' ""
    printf '%s\n' "    python3 devBenches/base-image/update-upstream.py apply \\"
    printf '%s\n' "        --source openrepotools --at <commit> --yes"
    printf '%s\n' "    ./setup.sh"
    printf '%s\n' ""
    printf '%s\n' "  On a host that tracks openRepoTools without workBenches, the one"
    printf '%s\n' "  command is:"
    printf '%s\n' ""
    printf '%s\n' "    openRepoTools wip init"
    printf '%s\n' ""
    if [ -n "$TARGET" ]; then
        printf '%s\n' "  It will create $TARGET and ask you nothing."
    fi
    case "$LOGIN_ISSUE" in
        nogh)
            printf '%s\n' ""
            printf '%s\n' "  (Your GitHub login could not be read: \`gh\` is not installed. It is not"
            printf '%s\n' "  needed until you run the command above.)"
            ;;
        unauth)
            printf '%s\n' ""
            printf '%s\n' "  (Your GitHub login could not be read from \`gh api user\`. \`gh auth login\`"
            printf '%s\n' "  fills it in; it is not needed until you run the command above.)"
            ;;
        pattern)
            printf '%s\n' ""
            printf '%s\n' "  (Your GitHub login does not fit <login>-wip's own naming pattern,"
            printf '%s\n' "  \`^[a-z0-9]+(-[a-z0-9]+)*\$\` -- openRepoShape's naming contract."
            printf '%s\n' "  \`wip init\` will name that itself; nothing is needed until you run it.)"
            ;;
    esac
    clear_needs_attention
    exit 0
fi

# --- step 4: run it, and relay every byte it prints --------------------------
#
# Before running it at all: `wip init` needs this same login (9(c) step 2) and
# would refuse for exactly the reason this step already knows -- calling it
# anyway would only relay a refusal already known here, and it is the one
# place left this step could still have printed a placeholder instead of the
# name it could not form (F3). So it stops, names the precondition, and exits
# with the same code `wip init` itself uses for a refusal (2) -- nothing was
# attempted, which is also true, rather than 1, which would say `wip init` ran
# and refused when it never got the chance to.
case "$LOGIN_ISSUE" in
    nogh)
        printf '%s\n' "Workspace repository: \`openRepoTools wip init\` needs your GitHub login, and"
        printf '%s\n' "  \`gh\` is not installed to read it."
        printf '%s\n' "  Install \`gh\`, then re-run this step; nothing was created."
        mark_needs_attention
        exit 2
        ;;
    unauth)
        printf '%s\n' "Workspace repository: \`openRepoTools wip init\` needs your GitHub login, and"
        printf '%s\n' "  it could not be read from \`gh api user\`."
        printf '%s\n' "  Run \`gh auth login\`, then re-run this step; nothing was created."
        mark_needs_attention
        exit 2
        ;;
    pattern)
        printf '%s\n' "Workspace repository: your GitHub login does not fit <login>-wip's naming"
        printf '%s\n' "  pattern, \`^[a-z0-9]+(-[a-z0-9]+)*\$\` -- openRepoShape's naming contract."
        printf '%s\n' "  \`openRepoTools wip init\` would refuse it for the same reason; nothing was"
        printf '%s\n' "  created."
        mark_needs_attention
        exit 2
        ;;
esac

# No capture, no summary, no swallowing. Amendment 9(c) step 4 has `wip init`
# print two commands for an administrator where the person cannot create the
# repository themselves, and Addendum 1 to the governing issue adds a third
# act -- excluding the new repository from the organisation's PR-only ruleset,
# without which Rule 9's one-commit-per-write cannot land. That block is the
# most important thing this step ever puts on a terminal, and the only way to
# be sure it is not lost is never to hold it.
printf '%s\n' "Workspace repository: $TOOLS wip init"
printf '%s\n' "  target: $TARGET (derived; you are asked nothing)"

wip_argv=(wip init)
if [ -n "${WORKBENCHES_WORKSPACE_ORG:-}" ]; then
    wip_argv+=(--org "$WORKBENCHES_WORKSPACE_ORG")
fi
if [ -n "$DRY_RUN" ]; then
    wip_argv+=(--dry-run)
fi

wip_status=0
"$TOOLS" "${wip_argv[@]}" || wip_status=$?

if [ "$wip_status" -ne 0 ]; then
    printf '%s\n' "" >&2
    printf '%s\n' "Workspace repository step refused: \`openRepoTools wip init\` exited $wip_status." >&2
    printf '%s\n' "Its own output above says why and names what to do; this step adds" >&2
    printf '%s\n' "nothing to it and has changed nothing itself. Re-run" >&2
    printf '%s\n' "\`openRepoTools wip init\` once that is done -- it is idempotent." >&2
    mark_needs_attention
    exit 1
fi

clear_needs_attention
exit 0
