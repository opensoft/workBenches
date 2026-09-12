#!/usr/bin/env bash
#
# scripts/setup-workspace-repo.sh
#
# The workspace-repository step of the onboarding chain -- lane-collision-protocol
# Amendment 9(e). The chain a new person walks, in the amendment's own order:
#
#   gh repo clone opensoft/workBenches && ./setup.sh
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
# where nothing derives (no gh, or a gh that is not logged in) this step prints
# the one command that fixes that and continues rather than asking for what it
# could not read. The one-question budget Brett's direction allows is
# deliberately unspent.
#
# IT DEGRADES RATHER THAN FAILING, AND IT DEGRADES ON `--help`, NOT ON AN EXIT
# CODE. The openRepoTools this repository vendors today has no `wip` subcommand
# at all: Amendment 9's adoption act 3 sequences that change after
# opensoft/brett-wip's Amendment 8 PR merges, so for now `openRepoTools wip
# init` is an unknown argument. An unknown argument makes openRepoTools `die`,
# and `die`'s default exit is 2 -- which is ALSO the exit Amendment 9(c) gives
# `wip init`'s own refusals. One number, two meanings. So capability is decided
# by asking `openRepoTools --help` whether it documents the verb, never by
# running the verb and reading what comes back: a probe that read the exit code
# would report a genuine refusal -- the administrator's `gh repo create` block
# of Amendment 9(c) step 4, printed and then exited 2 -- as "no such
# subcommand", and would swallow the one piece of output the person most needs
# to see. (The same shape as the launcher's `lane-start --help` probe for
# `--confirm`, opensoft/workBenches#63.)
#
# NOTHING THIS STEP RUNS HAS ITS OUTPUT CAPTURED. `openRepoTools wip init`
# writes straight to this script's stdout and stderr, which are setup.sh's,
# which are the terminal's. The administrator block, the refusals and the next
# step it prints are relayed byte for byte; this script adds no summary that
# could stand in for them and never stores them in a variable it might drop.
#
# Set WORKBENCHES_SKIP_WORKSPACE_REPO=1 to skip this step entirely (prints one
# line, exits 0).
#
# AGENT_PROTOCOL_ROOT overrides the directory holding workspace.yaml (default
# "$HOME/.agents"), the estate's own convention for that path and the
# environment override Amendment 9(a) permits for sandbox tests.
# OPENREPOTOOLS_BIN_DIR is honoured as openRepoTools' own installer honours it.
#
# Exit codes when run directly: 0 ok (this host already has a workspace, or
# `wip init` did the work, or this openRepoTools has no `wip` yet and the step
# printed what to run instead); 1 refused (`openRepoTools wip init` itself
# refused or failed -- its own output above says why); 2 tooling missing (no
# openRepoTools is installed, so `openRepoTools --install` has not run yet).
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
host that already has ~/.agents/workspace.yaml pointing at a checkout runs
nothing. An openRepoTools with no `wip` subcommand yet prints what to run and
continues.

  --dry-run   rehearse; passed through to `openRepoTools wip init --dry-run`

Environment:
  WORKBENCHES_SKIP_WORKSPACE_REPO=1   skip this step entirely
  WORKBENCHES_WORKSPACE_ORG=<org>     the organisation (default: opensoft)
  AGENT_PROTOCOL_ROOT=<dir>           where workspace.yaml lives (~/.agents)
  OPENREPOTOOLS_BIN_DIR=<dir>         where openRepoTools was installed

Exits: 0 ok or already done; 1 `wip init` refused; 2 openRepoTools not
installed (the `--install` step has not run).
USAGE
            exit 0
            ;;
        *)
            printf '%s\n' "setup-workspace-repo.sh takes --dry-run or --help and nothing else." >&2
            exit 2
            ;;
    esac
done

if [ "${WORKBENCHES_SKIP_WORKSPACE_REPO:-}" = "1" ]; then
    printf '%s\n' "Workspace repository step skipped by WORKBENCHES_SKIP_WORKSPACE_REPO=1."
    exit 0
fi

AGENTS_DIR="${AGENT_PROTOCOL_ROOT:-$HOME/.agents}"
WORKSPACE_YAML="$AGENTS_DIR/workspace.yaml"

# --- step 1: detect, the way Amendment 9(c) step 1 detects -------------------
#
# A file test, not a network call, and deliberately conservative: all four of
# these must hold before this step decides the host already has a workspace and
# runs nothing at all. Anything less -- a half-written file, a path that is no
# checkout -- falls THROUGH to `wip init`, which is idempotent and is the owner
# of that judgement. Two owners of one judgement is two answers, and Amendment
# 9(a) is explicit that "a second way to find it is a second answer".
yaml_value() {
    # `key: value`, with optional quotes and a leading ~ expanded. One key,
    # first occurrence, top level only -- the `orgs:` map Amendment 9(a) puts
    # out of scope is indented, so an anchored match never reaches into it.
    local key="$1" file="$2" line
    line="$(sed -n "s/^${key}:[[:space:]]*//p" "$file" 2>/dev/null | head -n 1)" || return 0
    line="${line%\"}"; line="${line#\"}"
    line="${line%\'}"; line="${line#\'}"
    line="${line%%[[:space:]]#*}"
    line="${line%"${line##*[![:space:]]}"}"
    case "$line" in
        "~/"*) line="$HOME/${line#\~/}" ;;
        "~") line="$HOME" ;;
    esac
    printf '%s\n' "$line"
}

if [ -f "$WORKSPACE_YAML" ]; then
    existing_repo="$(yaml_value repository "$WORKSPACE_YAML")"
    existing_path="$(yaml_value path "$WORKSPACE_YAML")"
    if [ -n "$existing_repo" ] && [ -n "$existing_path" ] && [ -e "$existing_path/.git" ]; then
        printf '%s\n' "Workspace repository: $existing_repo already checked out at $existing_path"
        printf '%s\n' "  ($WORKSPACE_YAML names it; nothing to do.)"
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
    exit 2
fi

# --- the derivations, which are also the whole of this step's input ----------
#
# Computed here for what this step PRINTS, never handed to `wip init` as an
# answer: Amendment 9(c) steps 2 and 3 have it derive the login and the
# organisation itself, by these same two rules, and a value passed in from here
# would be a second answer to a question that already has one. The exception is
# an operator who set WORKBENCHES_WORKSPACE_ORG, which has no other way in and
# is therefore passed through as `--org`.
derive_login() {
    local login=""
    command -v gh >/dev/null 2>&1 || return 0
    login="$(gh api user -q .login 2>/dev/null || true)"
    printf '%s\n' "$(printf '%s' "$login" | tr '[:upper:]' '[:lower:]')"
}

LOGIN="$(derive_login)"
ORG="${WORKBENCHES_WORKSPACE_ORG:-opensoft}"
if [ -n "$LOGIN" ]; then
    TARGET="$ORG/$LOGIN-wip"
else
    TARGET="$ORG/<your-login>-wip"
fi

# --- step 3: does this openRepoTools know the verb at all? -------------------
#
# `--help`, for the reason the header gives at length: the exit code cannot
# tell "no such subcommand" from "refused", and reading it that way would eat
# the administrator's block.
tools_help="$("$TOOLS" --help 2>/dev/null || true)"
if ! printf '%s' "$tools_help" | grep -Eq '(^|[^[:alnum:]-])wip([^[:alnum:]-]|$)'; then
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
    printf '%s\n' "  It will create $TARGET and ask you nothing."
    if [ -z "$LOGIN" ]; then
        printf '%s\n' ""
        if command -v gh >/dev/null 2>&1; then
            printf '%s\n' "  (The login above could not be read from \`gh api user\`. \`gh auth login\`"
            printf '%s\n' "  fills it in; it is not needed until you run the command.)"
        else
            printf '%s\n' "  (The login above could not be read: \`gh\` is not installed. It is not"
            printf '%s\n' "  needed until you run the command.)"
        fi
    fi
    exit 0
fi

# --- step 4: run it, and relay every byte it prints --------------------------
#
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
    exit 1
fi

exit 0
