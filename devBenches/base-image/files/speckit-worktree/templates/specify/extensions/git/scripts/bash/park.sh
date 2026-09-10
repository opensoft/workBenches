#!/usr/bin/env bash
# speckit-overlay-shape: 1
# Git extension: park.sh
#
# Commit, push and record every open feature of this project, so the work can
# be picked up on another workstation with resume.sh. Implements
# openRepoShape#77 as ruled by Brett Heap on 2026-09-09: Speckit owns the
# mechanics, park refuses by default rather than force-pushing, and the
# feature list is recorded in the private repository the person owns.
#
# Nothing under the worktree root is ever committed at the root: park commits
# only INSIDE the leg worktrees, on the feature branch.

set -e

JSON_MODE=false
DRY_RUN=false
NO_PUSH=false
RETIRE_PARKED_WIP=false
LANE_ARG=""
MESSAGE_ARG=""
WORKSPACE_ARG=""
REQUESTED_BRANCHES=()

usage() {
    echo "Usage: $0 [--json] [--dry-run] [--feature <branch>]... [--lane <name>]"
    echo "          [--message <text>] [--no-push] [--workspace <path>]"
    echo "          [--retire-parked-wip] [-h|--help]"
    echo ""
    echo "Commit, push and record every open feature so another workstation can resume it."
    echo ""
    echo "Options:"
    echo "  --json                 Output in JSON format"
    echo "  --dry-run              Print the plan; commit, push and write nothing"
    echo "  --feature <branch>     Park only this feature; repeatable. Default: every open feature"
    echo "  --lane <name>          Lane recorded in the WIP commit subject and the manifest"
    echo "  --message <text>       Provenance appended after the fixed WIP subject prefix"
    echo "  --no-push              Commit locally and record pushed: false; resume refuses those"
    echo "  --workspace <path>     Workspace checkout to record into, overriding the user config"
    echo "  --retire-parked-wip    Allow the single leased push that retires this workspace's"
    echo "                         own parked WIP commit from the remote (default off)"
    echo "  --help, -h             Show this help message"
    echo ""
    echo "Exit codes:"
    echo "  0  everything asked for was parked, or there was nothing to park"
    echo "  1  usage or environment error"
    echo "  2  a refusal before anything was done, or every feature was refused"
    echo "  3  partial: at least one feature was parked and at least one refused"
    echo ""
    echo "Environment variables:"
    echo "  SPECKIT_WORKSPACE_PATH        Workspace checkout, overriding the user config"
    echo "  SPECKIT_WORKSPACE_REPOSITORY  Workspace repository, for the clone remediation"
    echo "  SPECKIT_LANE, LANE            Lane, when --lane is not given"
    echo "  SPECKIT_WORKSTATION           Workstation name recorded as parked_on"
    echo "  AGENT_PROTOCOL_ROOT           Home of workspace.yaml (default ~/.agents)"
    echo "  SPECKIT_GIT_WORKTREE_ROOT     Override worktree_root"
    echo "  SPECKIT_GIT_BASE_BRANCH       Override base_branch"
    echo ""
    echo "The user config is \${AGENT_PROTOCOL_ROOT:-\$HOME/.agents}/workspace.yaml:"
    echo ""
    echo "  repository: <owner>/<repo>"
    echo "  path: ~/projects/<repo>"
}

i=1
while [ $i -le $# ]; do
    arg="${!i}"
    case "$arg" in
        --json) JSON_MODE=true ;;
        --dry-run) DRY_RUN=true ;;
        --no-push) NO_PUSH=true ;;
        --retire-parked-wip) RETIRE_PARKED_WIP=true ;;
        --feature|--lane|--message|--workspace)
            if [ $((i + 1)) -gt $# ]; then
                echo "Error: $arg requires a value" >&2
                exit 1
            fi
            i=$((i + 1))
            next_arg="${!i}"
            case "$next_arg" in
                --*)
                    echo "Error: $arg requires a value" >&2
                    exit 1
                    ;;
            esac
            case "$arg" in
                --feature) REQUESTED_BRANCHES[${#REQUESTED_BRANCHES[@]}]="$next_arg" ;;
                --lane) LANE_ARG="$next_arg" ;;
                --message) MESSAGE_ARG="$next_arg" ;;
                --workspace) WORKSPACE_ARG="$next_arg" ;;
            esac
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Error: unknown option: $arg" >&2
            usage >&2
            exit 1
            ;;
    esac
    i=$((i + 1))
done

# ---------------------------------------------------------------------------
# Locate the checkout and the helpers, exactly as get-last-worktree.sh does.
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(CDPATH="" cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_REPO_ROOT="$(CDPATH="" cd -- "$SCRIPT_DIR/../../../../.." && pwd 2>/dev/null || true)"
if [ ! -f "$SCRIPT_DIR/git-common.sh" ]; then
    echo "Error: Could not locate git-common.sh next to park.sh." >&2
    exit 1
fi
source "$SCRIPT_DIR/git-common.sh"
if [ ! -f "$SCRIPT_DIR/workspace-common.sh" ]; then
    echo "Error: Could not locate workspace-common.sh next to park.sh." >&2
    exit 1
fi
source "$SCRIPT_DIR/workspace-common.sh"

if REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    :
else
    REPO_ROOT=""
fi
[ -n "$REPO_ROOT" ] || REPO_ROOT="$SCRIPT_REPO_ROOT"
if [ -z "$REPO_ROOT" ] || [ ! -d "$REPO_ROOT/.specify" ]; then
    echo "Error: not inside a Git repository or Speckit checkout." >&2
    exit 1
fi

cd "$REPO_ROOT"
load_repo_shape "$REPO_ROOT"
# get_config_value in git-common.sh reads CONFIG_FILE.
# shellcheck disable=SC2034
CONFIG_FILE="$REPO_ROOT/.specify/extensions/git/git-config.yml"

CHECKOUT_MODE=$(get_config_value "checkout_mode" "branch" "SPECKIT_GIT_CHECKOUT_MODE")
CHECKOUT_MODE=$(printf '%s' "$CHECKOUT_MODE" | tr '[:upper:]' '[:lower:]')
BASE_BRANCH=$(get_config_value "base_branch" "main" "SPECKIT_GIT_BASE_BRANCH")
DEFAULT_WORKTREE_ROOT="../${REPO_ROOT##*/}-worktrees"
if [ "$REPO_SHAPE" = "three-leg" ]; then
    DEFAULT_WORKTREE_ROOT="worktrees"
fi
WORKTREE_ROOT_RAW=$(get_config_value "worktree_root" "$DEFAULT_WORKTREE_ROOT" "SPECKIT_GIT_WORKTREE_ROOT")
WORKTREE_ROOT=$(resolve_path_from_repo_root "$WORKTREE_ROOT_RAW")

if [ "$CHECKOUT_MODE" != "worktree" ]; then
    echo "Error: checkout_mode '$CHECKOUT_MODE' has no worktree to park; nothing was parked." >&2
    echo "park and resume carry linked worktrees between workstations. Set checkout_mode: worktree in .specify/extensions/git/git-config.yml." >&2
    exit 1
fi

if [ "$REPO_SHAPE" = "three-leg" ]; then
    if ! shape_leg_is_checkout "$SPEC_LEG"; then
        echo "Error: the spec leg '$SHAPE_SPEC_PATH' is not an initialised Git checkout at '$SPEC_LEG'." >&2
        echo "Run 'git submodule update --init' (or 'make bootstrap') in the project root first." >&2
        exit 1
    fi
    if ! shape_leg_is_checkout "$CODE_LEG"; then
        echo "Error: the code leg '$SHAPE_CODE_PATH' is not an initialised Git checkout at '$CODE_LEG'." >&2
        echo "Run 'git submodule update --init' (or 'make bootstrap') in the project root first." >&2
        exit 1
    fi
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: park requires Python 3 for safe manifest and state publication." >&2
    exit 1
fi
if [ "$JSON_MODE" = true ] && ! select_json_encoder >/dev/null; then
    echo "Error: JSON output requires jq, a trusted json_escape function, or Python 3; no JSON encoder is available." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# The workspace, and this project's manifest file.
# ---------------------------------------------------------------------------
workspace_project_id "$REPO_ROOT"
PROJECT_ID="$WORKSPACE_PROJECT_ID"
workspace_family_name "$REPO_ROOT" "$PROJECT_ID"
MANIFEST_NAME="$WORKSPACE_FAMILY"
[ -n "$MANIFEST_NAME" ] || MANIFEST_NAME="$PROJECT_ID"
# One private workspace repository tracks work across several orgs, so the
# manifest is filed under the owner of the declared repository: two projects
# that share an id in different orgs never share a file. The same org also
# selects the workspace, when the config gives that org one of its own.
workspace_org_for "$REPO_ROOT" "$WORKSPACE_FAMILY_MANIFEST"
# shellcheck disable=SC2153  # workspace_org_for in workspace-common.sh sets it
MANIFEST_ORG="$WORKSPACE_ORG"
if ! workspace_name_is_safe "$MANIFEST_ORG"; then
    echo "Error: '$MANIFEST_ORG' is not a usable workspace org name; nothing was parked." >&2
    echo "The org is the owner segment of repository: in project.yaml (or in the family's family.yaml) and must match [A-Za-z0-9._-]+." >&2
    echo "Correct that repository: value, then re-run \`make park\`." >&2
    exit 2
fi

WORKSPACE_RESOLVE_STATUS=0
workspace_resolve "$WORKSPACE_ARG" "$MANIFEST_ORG" || WORKSPACE_RESOLVE_STATUS=$?
if [ "$WORKSPACE_RESOLVE_STATUS" -eq 2 ]; then
    workspace_refuse_invalid_config parked park
    exit 2
elif [ "$WORKSPACE_RESOLVE_STATUS" -ne 0 ]; then
    workspace_refuse_no_config parked park
    exit 2
fi
if ! workspace_is_checkout "$WORKSPACE_PATH"; then
    workspace_refuse_not_a_checkout parked
    exit 2
fi

if ! workspace_name_is_safe "$MANIFEST_NAME"; then
    echo "Error: '$MANIFEST_NAME' is not a usable workspace manifest name; nothing was parked." >&2
    echo "A manifest file is named for the family or the project id and must match [A-Za-z0-9._-]+." >&2
    echo "Rename the id: in project.yaml (or in the family's family.yaml), then re-run \`make park\`." >&2
    exit 2
fi
MANIFEST_RELATIVE="workspaces/$MANIFEST_ORG/$MANIFEST_NAME.yaml"
MANIFEST_PATH="$WORKSPACE_PATH/$MANIFEST_RELATIVE"

# What this workspace recorded last time, for the WIP depth and the R8 lease.
workspace_load_project "$MANIFEST_PATH" "$PROJECT_ID" || true

recorded_leg_index() {
    local branch="$1"
    local role="$2"
    local index=0
    local feature

    RECORDED_INDEX=-1
    while [ "$index" -lt "${#MANIFEST_LEG_ROLE[@]}" ]; do
        feature="${MANIFEST_LEG_FEATURE[$index]}"
        if [ "${MANIFEST_LEG_ROLE[$index]}" = "$role" ] \
            && [ "${MANIFEST_FEATURE_BRANCHES[$feature]}" = "$branch" ]; then
            RECORDED_INDEX=$index
            return 0
        fi
        index=$((index + 1))
    done
    return 1
}

recorded_leg_commit() {
    RECORDED_COMMIT=""
    recorded_leg_index "$1" "$2" || return 1
    RECORDED_COMMIT="${MANIFEST_LEG_COMMIT[$RECORDED_INDEX]}"
    [ -n "$RECORDED_COMMIT" ]
}

recorded_leg_depth() {
    RECORDED_DEPTH=0
    recorded_leg_index "$1" "$2" || return 1
    RECORDED_DEPTH="${MANIFEST_LEG_DEPTH[$RECORDED_INDEX]}"
    case "$RECORDED_DEPTH" in
        ''|*[!0-9]*) RECORDED_DEPTH=0 ;;
    esac
    return 0
}

# ---------------------------------------------------------------------------
# Enumerate open features FROM GIT, never from memory and never from
# feature.json.
# ---------------------------------------------------------------------------
FEATURE_DIRS=()
FEATURE_BRANCHES=()

root_relative() {
    local path="$1"

    case "$path" in
        "$REPO_ROOT") printf '%s\n' "." ;;
        "$REPO_ROOT"/*) printf '%s\n' "${path#"$REPO_ROOT/"}" ;;
        *) printf '%s\n' "$path" ;;
    esac
}

if [ "$REPO_SHAPE" = "three-leg" ]; then
    if ! shape_load_features "$WORKTREE_ROOT"; then
        echo "Error: Failed to list Git worktrees." >&2
        exit 1
    fi
    index=0
    while [ "$index" -lt "${#SHAPE_FEATURE_PATHS[@]}" ]; do
        FEATURE_DIRS[${#FEATURE_DIRS[@]}]="${SHAPE_FEATURE_PATHS[$index]}"
        FEATURE_BRANCHES[${#FEATURE_BRANCHES[@]}]="${SHAPE_FEATURE_BRANCHES[$index]}"
        index=$((index + 1))
    done
else
    if ! load_git_worktrees "$REPO_ROOT"; then
        echo "Error: Failed to list Git worktrees." >&2
        exit 1
    fi
    SINGLE_PATHS=()
    SINGLE_BRANCHES=()
    SINGLE_MTIMES=()
    index=0
    while [ "$index" -lt "${#GIT_WORKTREE_PATHS[@]}" ]; do
        candidate="${GIT_WORKTREE_PATHS[$index]}"
        head="${GIT_WORKTREE_HEADS[$index]}"
        branch_ref="${GIT_WORKTREE_BRANCH_REFS[$index]}"
        detached="${GIT_WORKTREE_DETACHED[$index]}"
        index=$((index + 1))
        if verify_git_worktree_candidate "$REPO_ROOT" "$WORKTREE_ROOT" \
            "$candidate" "$head" "$branch_ref" "$detached" \
            && [ -n "$GIT_WORKTREE_VERIFIED_BRANCH_REF" ]; then
            mtime="$(_shape_mtime_for_path "$GIT_WORKTREE_VERIFIED_PATH" 2>/dev/null || true)"
            [ -n "$mtime" ] || continue
            SHAPE_FEATURE_PATHS=("${SINGLE_PATHS[@]}")
            SHAPE_FEATURE_BRANCHES=("${SINGLE_BRANCHES[@]}")
            SHAPE_FEATURE_MTIMES=("${SINGLE_MTIMES[@]}")
            shape_insert_feature "$GIT_WORKTREE_VERIFIED_PATH" \
                "${GIT_WORKTREE_VERIFIED_BRANCH_REF#refs/heads/}" "$mtime"
            SINGLE_PATHS=("${SHAPE_FEATURE_PATHS[@]}")
            SINGLE_BRANCHES=("${SHAPE_FEATURE_BRANCHES[@]}")
            SINGLE_MTIMES=("${SHAPE_FEATURE_MTIMES[@]}")
        fi
    done
    index=0
    while [ "$index" -lt "${#SINGLE_PATHS[@]}" ]; do
        FEATURE_DIRS[${#FEATURE_DIRS[@]}]="${SINGLE_PATHS[$index]}"
        FEATURE_BRANCHES[${#FEATURE_BRANCHES[@]}]="${SINGLE_BRANCHES[$index]}"
        index=$((index + 1))
    done
fi

OPEN_BRANCHES=""
index=0
while [ "$index" -lt "${#FEATURE_BRANCHES[@]}" ]; do
    OPEN_BRANCHES="$OPEN_BRANCHES ${FEATURE_BRANCHES[$index]} "
    index=$((index + 1))
done

# --feature restricts the set; a name that is not open is a usage error.
if [ "${#REQUESTED_BRANCHES[@]}" -gt 0 ]; then
    index=0
    while [ "$index" -lt "${#REQUESTED_BRANCHES[@]}" ]; do
        case "$OPEN_BRANCHES" in
            *" ${REQUESTED_BRANCHES[$index]} "*) ;;
            *)
                echo "Error: '${REQUESTED_BRANCHES[$index]}' is not an open feature under '$(root_relative "$WORKTREE_ROOT")'; nothing was parked." >&2
                echo "  look:  git -C . worktree list" >&2
                exit 1
                ;;
        esac
        index=$((index + 1))
    done
    SELECTED_DIRS=()
    SELECTED_BRANCHES=()
    index=0
    while [ "$index" -lt "${#FEATURE_BRANCHES[@]}" ]; do
        wanted=false
        inner=0
        while [ "$inner" -lt "${#REQUESTED_BRANCHES[@]}" ]; do
            if [ "${REQUESTED_BRANCHES[$inner]}" = "${FEATURE_BRANCHES[$index]}" ]; then
                wanted=true
                break
            fi
            inner=$((inner + 1))
        done
        if [ "$wanted" = true ]; then
            SELECTED_DIRS[${#SELECTED_DIRS[@]}]="${FEATURE_DIRS[$index]}"
            SELECTED_BRANCHES[${#SELECTED_BRANCHES[@]}]="${FEATURE_BRANCHES[$index]}"
        fi
        index=$((index + 1))
    done
    PARK_DIRS=("${SELECTED_DIRS[@]}")
    PARK_BRANCHES=("${SELECTED_BRANCHES[@]}")
else
    PARK_DIRS=("${FEATURE_DIRS[@]}")
    PARK_BRANCHES=("${FEATURE_BRANCHES[@]}")
fi

# ---------------------------------------------------------------------------
# Feature directories that shape_load_features cannot count as open features,
# and that must be refused rather than silently skipped:
#
#   missing   one leg worktree is absent (R7);
#   detached  a leg worktree is on a detached HEAD, which is what an in-flight
#             rebase looks like from `git worktree list` (R4).
# ---------------------------------------------------------------------------
BLOCKED_DIRS=()
BLOCKED_BRANCHES=()
BLOCKED_KINDS=()
BLOCKED_ROLES=()
BLOCKED_MOUNTS=()
BLOCKED_TREES=()

blocked_dir_seen() {
    local wanted="$1"
    local index=0

    while [ "$index" -lt "${#BLOCKED_DIRS[@]}" ]; do
        [ "${BLOCKED_DIRS[$index]}" = "$wanted" ] && return 0
        index=$((index + 1))
    done
    return 1
}

# The branch a detached leg worktree belongs to: the rebase's own record of it,
# else the feature directory's name, which IS the branch by construction.
detached_branch_for() {
    local tree="$1"
    local feature_dir="$2"
    local git_dir head_name

    DETACHED_BRANCH="${feature_dir#"$WORKTREE_ROOT/"}"
    git_dir="$(git -C "$tree" rev-parse --absolute-git-dir 2>/dev/null || true)"
    [ -n "$git_dir" ] || return 0
    for head_name in "$git_dir/rebase-merge/head-name" "$git_dir/rebase-apply/head-name"; do
        if [ -f "$head_name" ]; then
            DETACHED_BRANCH="$(sed -n '1s|^refs/heads/||p' "$head_name")"
            [ -n "$DETACHED_BRANCH" ] || DETACHED_BRANCH="${feature_dir#"$WORKTREE_ROOT/"}"
            return 0
        fi
    done
}

if [ "$REPO_SHAPE" = "three-leg" ] && [ "${#REQUESTED_BRANCHES[@]}" -eq 0 ]; then
    scan_blocked_features() {
        local leg="$1"
        local role="$2"
        local mount="$3"
        local sibling_role="$4"
        local sibling_mount="$5"
        local index=0
        local path branch feature_dir

        load_git_worktrees "$leg" || return 0
        while [ "$index" -lt "${#GIT_WORKTREE_PATHS[@]}" ]; do
            path="${GIT_WORKTREE_PATHS[$index]}"
            branch="${GIT_WORKTREE_BRANCH_REFS[$index]#refs/heads/}"
            index=$((index + 1))
            case "$path" in
                */"$mount") feature_dir="${path%/"$mount"}" ;;
                *) continue ;;
            esac
            case "$feature_dir" in
                "$WORKTREE_ROOT"/*) ;;
                *) continue ;;
            esac
            blocked_dir_seen "$feature_dir" && continue
            if [ -z "$branch" ]; then
                detached_branch_for "$path" "$feature_dir"
                BLOCKED_DIRS[${#BLOCKED_DIRS[@]}]="$feature_dir"
                BLOCKED_BRANCHES[${#BLOCKED_BRANCHES[@]}]="$DETACHED_BRANCH"
                BLOCKED_KINDS[${#BLOCKED_KINDS[@]}]="detached"
                BLOCKED_ROLES[${#BLOCKED_ROLES[@]}]="$role"
                BLOCKED_MOUNTS[${#BLOCKED_MOUNTS[@]}]="$mount"
                BLOCKED_TREES[${#BLOCKED_TREES[@]}]="$path"
                continue
            fi
            [ -d "$feature_dir/$sibling_mount" ] && continue
            BLOCKED_DIRS[${#BLOCKED_DIRS[@]}]="$feature_dir"
            BLOCKED_BRANCHES[${#BLOCKED_BRANCHES[@]}]="$branch"
            BLOCKED_KINDS[${#BLOCKED_KINDS[@]}]="missing"
            BLOCKED_ROLES[${#BLOCKED_ROLES[@]}]="$sibling_role"
            BLOCKED_MOUNTS[${#BLOCKED_MOUNTS[@]}]="$sibling_mount"
            BLOCKED_TREES[${#BLOCKED_TREES[@]}]="$feature_dir/$sibling_mount"
        done
    }
    scan_blocked_features "$SPEC_LEG" spec "$SHAPE_SPEC_PATH" code "$SHAPE_CODE_PATH"
    scan_blocked_features "$CODE_LEG" code "$SHAPE_CODE_PATH" spec "$SHAPE_SPEC_PATH"
fi

# ---------------------------------------------------------------------------
# Per-leg helpers.
# ---------------------------------------------------------------------------
WIP_PREFIX='wip: park '

leg_in_progress_operation() {
    local tree="$1"
    local git_dir

    LEG_OPERATION=""
    git_dir="$(git -C "$tree" rev-parse --absolute-git-dir 2>/dev/null || true)"
    [ -n "$git_dir" ] || return 1
    if [ -e "$git_dir/rebase-merge" ] || [ -e "$git_dir/rebase-apply" ]; then
        LEG_OPERATION="rebase"
        return 0
    fi
    if [ -e "$git_dir/MERGE_HEAD" ]; then
        LEG_OPERATION="merge"
        return 0
    fi
    if [ -e "$git_dir/CHERRY_PICK_HEAD" ]; then
        LEG_OPERATION="cherry-pick"
        return 0
    fi
    return 1
}

leg_has_unmerged_paths() {
    local tree="$1"

    [ -n "$(git -C "$tree" ls-files -u 2>/dev/null || true)" ]
}

leg_is_dirty() {
    local tree="$1"

    [ -n "$(git -C "$tree" status --porcelain 2>/dev/null || true)" ]
}

commit_subject_is_wip() {
    local tree="$1"
    local revision="$2"
    local subject

    subject="$(git -C "$tree" log -1 --format=%s "$revision" 2>/dev/null || true)"
    case "$subject" in
        "$WIP_PREFIX"*) return 0 ;;
        *) return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# Refusal bookkeeping and output.
# ---------------------------------------------------------------------------
REFUSED_BRANCHES=()
REFUSED_REASONS=()
PARKED_COUNT=0

record_refusal() {
    REFUSED_BRANCHES[${#REFUSED_BRANCHES[@]}]="$1"
    REFUSED_REASONS[${#REFUSED_REASONS[@]}]="$2"
    REFUSED_REMEDIATIONS[${#REFUSED_REMEDIATIONS[@]}]="$3"
}
REFUSED_REMEDIATIONS=()

TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "")"
LANE="$(workspace_lane "$LANE_ARG")"
WORKSTATION="$(workspace_workstation)"
WIP_SUBJECT="$WIP_PREFIX$TIMESTAMP — lane $LANE"
if [ -n "$MESSAGE_ARG" ]; then
    WIP_SUBJECT="$WIP_SUBJECT — $MESSAGE_ARG"
fi

_git_worktree_create_temp_file || {
    echo "Error: could not create a temporary file for the workspace record." >&2
    exit 1
}
RECORD_FILE="$_GIT_WORKTREE_OUTPUT_FILE"
# shellcheck disable=SC2329  # an EXIT trap handler
cleanup() {
    workspace_unlock
    [ -n "${RECORD_FILE:-}" ] && rm -f "$RECORD_FILE" 2>/dev/null || true
    return 0
}
trap cleanup EXIT

# A refused feature keeps whatever an earlier park recorded for it: a refusal
# must never erase the entry another workstation would resume from. A feature
# that is simply gone is dropped, which is what leaves `features: []` behind.
emit_recorded_feature() {
    local branch="$1"
    local feature_index=-1
    local index=0

    while [ "$index" -lt "${#MANIFEST_FEATURE_BRANCHES[@]}" ]; do
        if [ "${MANIFEST_FEATURE_BRANCHES[$index]}" = "$branch" ]; then
            feature_index=$index
            break
        fi
        index=$((index + 1))
    done
    [ "$feature_index" -ge 0 ] || return 0

    workspace_record_section "$RECORD_FILE" feature
    workspace_record_put "$RECORD_FILE" branch "$branch"
    if [ -n "${MANIFEST_FEATURE_DIRECTORIES[$feature_index]}" ]; then
        workspace_record_put "$RECORD_FILE" _feature_directory \
            "${MANIFEST_FEATURE_DIRECTORIES[$feature_index]}"
    fi
    index=0
    while [ "$index" -lt "${#MANIFEST_LEG_ROLE[@]}" ]; do
        if [ "${MANIFEST_LEG_FEATURE[$index]}" = "$feature_index" ]; then
            workspace_record_section "$RECORD_FILE" leg
            workspace_record_put "$RECORD_FILE" role "${MANIFEST_LEG_ROLE[$index]}"
            workspace_record_put "$RECORD_FILE" _remote "${MANIFEST_LEG_REMOTE[$index]}"
            workspace_record_put "$RECORD_FILE" parked_commit "${MANIFEST_LEG_COMMIT[$index]}"
            workspace_record_put "$RECORD_FILE" wip "${MANIFEST_LEG_WIP[$index]}"
            workspace_record_put "$RECORD_FILE" wip_depth "${MANIFEST_LEG_DEPTH[$index]}"
            workspace_record_put "$RECORD_FILE" pushed "${MANIFEST_LEG_PUSHED[$index]}"
        fi
        index=$((index + 1))
    done
}

# Lines that describe a parked feature, printed after the refusals so a
# refusal is never buried.
PARK_REPORT=""
append_report() {
    PARK_REPORT="$PARK_REPORT$1
"
}

# ---------------------------------------------------------------------------
# Park each feature.
# ---------------------------------------------------------------------------
LEG_ROLES=()
LEG_REPOS=()
LEG_TREES=()
LEG_MOUNTS=()

# LEG_REPOS is read by the R8 probe and the push, through the loop indices.
# shellcheck disable=SC2034
#
# The role is what the manifest records (spec, code, or repo for a single
# repository); the mount is where the leg checkout sits, which is what a
# copy-pasteable `git -C` command needs.
build_legs() {
    local feature_dir="$1"

    LEG_ROLES=()
    LEG_REPOS=()
    LEG_TREES=()
    LEG_MOUNTS=()
    if [ "$REPO_SHAPE" = "three-leg" ]; then
        LEG_ROLES=("spec" "code")
        LEG_REPOS=("$SPEC_LEG" "$CODE_LEG")
        LEG_TREES=("$feature_dir/$SHAPE_SPEC_PATH" "$feature_dir/$SHAPE_CODE_PATH")
        LEG_MOUNTS=("$SHAPE_SPEC_PATH" "$SHAPE_CODE_PATH")
    else
        LEG_ROLES=("repo")
        LEG_REPOS=("$REPO_ROOT")
        LEG_TREES=("$feature_dir")
        LEG_MOUNTS=(".")
    fi
}

# The blocked directories first: they are refusals about the layout and about
# unresolved state, not about work that could have been committed.
index=0
while [ "$index" -lt "${#BLOCKED_DIRS[@]}" ]; do
    blocked_dir="${BLOCKED_DIRS[$index]}"
    blocked_branch="${BLOCKED_BRANCHES[$index]}"
    blocked_kind="${BLOCKED_KINDS[$index]}"
    blocked_role="${BLOCKED_ROLES[$index]}"
    blocked_mount="${BLOCKED_MOUNTS[$index]}"
    blocked_tree="${BLOCKED_TREES[$index]}"
    index=$((index + 1))
    if [ "$blocked_kind" = "detached" ]; then
        blocked_operation="rebase"
        if leg_in_progress_operation "$blocked_tree"; then
            blocked_operation="$LEG_OPERATION"
        fi
        blocked_tree_print="$(root_relative "$blocked_tree")"
        >&2 echo "Error: $blocked_branch ($blocked_role leg) has a $blocked_operation in progress; that feature was NOT parked."
        >&2 echo "A WIP commit over an unresolved index would park a conflicted tree as if it were work."
        >&2 echo "  finish it:  git -C $blocked_tree_print $blocked_operation --continue"
        >&2 echo "  or drop it: git -C $blocked_tree_print $blocked_operation --abort"
        >&2 echo "Then re-run \`make park\`."
        record_refusal "$blocked_branch" "$blocked_operation in progress" \
            "git -C $blocked_tree_print $blocked_operation --continue"
        emit_recorded_feature "$blocked_branch"
        continue
    fi
    >&2 echo "Error: $(root_relative "$blocked_dir") has no $blocked_role leg worktree; that feature was NOT parked."
    >&2 echo "  recreate it:  git -C $blocked_mount worktree add $(root_relative "$blocked_dir")/$blocked_mount $blocked_branch"
    >&2 echo "  or remove the feature directory and re-run \`make park\`."
    record_refusal "$blocked_branch" "missing $blocked_role leg worktree" \
        "git -C $blocked_mount worktree add $(root_relative "$blocked_dir")/$blocked_mount $blocked_branch"
    emit_recorded_feature "$blocked_branch"
done

feature_index=0
while [ "$feature_index" -lt "${#PARK_BRANCHES[@]}" ]; do
    branch="${PARK_BRANCHES[$feature_index]}"
    feature_dir="${PARK_DIRS[$feature_index]}"
    feature_index=$((feature_index + 1))
    build_legs "$feature_dir"

    # Blockers for EVERY leg before a single commit is made.
    refused=false
    leg=0
    while [ "$leg" -lt "${#LEG_ROLES[@]}" ]; do
        role="${LEG_ROLES[$leg]}"
        tree="${LEG_TREES[$leg]}"
        tree_print="$(root_relative "$tree")"
        leg_print="${LEG_MOUNTS[$leg]}"
        leg=$((leg + 1))
        if [ ! -d "$tree" ]; then
            >&2 echo "Error: $(root_relative "$feature_dir") has no $role leg worktree; that feature was NOT parked."
            >&2 echo "  recreate it:  git -C $leg_print worktree add $(root_relative "$feature_dir")/$leg_print $branch"
            >&2 echo "  or remove the feature directory and re-run \`make park\`."
            record_refusal "$branch" "missing $role leg worktree" \
                "git -C $leg_print worktree add $(root_relative "$feature_dir")/$leg_print $branch"
            refused=true
            break
        fi
        if leg_in_progress_operation "$tree"; then
            >&2 echo "Error: $branch ($role leg) has a $LEG_OPERATION in progress; that feature was NOT parked."
            >&2 echo "A WIP commit over an unresolved index would park a conflicted tree as if it were work."
            >&2 echo "  finish it:  git -C $tree_print $LEG_OPERATION --continue"
            >&2 echo "  or drop it: git -C $tree_print $LEG_OPERATION --abort"
            >&2 echo "Then re-run \`make park\`."
            record_refusal "$branch" "$LEG_OPERATION in progress" \
                "git -C $tree_print $LEG_OPERATION --continue"
            refused=true
            break
        fi
        if leg_has_unmerged_paths "$tree"; then
            >&2 echo "Error: $branch ($role leg) has unmerged paths; that feature was NOT parked."
            >&2 echo "A WIP commit over an unresolved index would park a conflicted tree as if it were work."
            >&2 echo "  look:     git -C $tree_print status"
            >&2 echo "  resolve:  git -C $tree_print add <path>"
            >&2 echo "Then re-run \`make park\`."
            record_refusal "$branch" "unmerged paths" "git -C $tree_print status"
            refused=true
            break
        fi
        if ! git -C "$tree" remote get-url origin >/dev/null 2>&1; then
            >&2 echo "Error: $branch ($role leg) has no 'origin' remote; that feature was NOT parked."
            >&2 echo "resume rebuilds worktrees from pushed branches, so a leg with no remote cannot travel."
            >&2 echo "  git -C $leg_print remote add origin <url>"
            record_refusal "$branch" "no origin remote" "git -C $leg_print remote add origin <url>"
            refused=true
            break
        fi
    done
    [ "$refused" = false ] || { emit_recorded_feature "$branch"; continue; }

    # R8: behind origin by this workspace's own parked WIP commits.
    LEG_RETIRE_LEASE=()
    leg=0
    while [ "$leg" -lt "${#LEG_ROLES[@]}" ]; do
        role="${LEG_ROLES[$leg]}"
        tree="${LEG_TREES[$leg]}"
        tree_print="$(root_relative "$tree")"
        LEG_RETIRE_LEASE[leg]=""
        leg=$((leg + 1))
        [ "$NO_PUSH" = false ] || continue
        [ "$DRY_RUN" = false ] || continue
        # A probe, not a requirement: on a first park the branch is not on
        # origin yet, and an unreachable origin is reported honestly by the
        # push itself (R6) rather than by a warning here.
        GIT_TERMINAL_PROMPT=0 git -C "$tree" fetch -q origin "$branch" >/dev/null 2>&1 || continue
        remote_tip="$(git -C "$tree" rev-parse --verify --quiet FETCH_HEAD 2>/dev/null || true)"
        [ -n "$remote_tip" ] || continue
        local_head="$(git -C "$tree" rev-parse --verify HEAD 2>/dev/null || true)"
        [ -n "$local_head" ] || continue
        [ "$local_head" != "$remote_tip" ] || continue
        git -C "$tree" merge-base --is-ancestor "$local_head" "$remote_tip" 2>/dev/null || continue
        behind="$(git -C "$tree" rev-list --count "$local_head..$remote_tip" 2>/dev/null || echo 0)"
        [ "$behind" -gt 0 ] || continue
        all_wip=true
        step=0
        while [ "$step" -lt "$behind" ]; do
            if ! commit_subject_is_wip "$tree" "$remote_tip~$step"; then
                all_wip=false
                break
            fi
            step=$((step + 1))
        done
        [ "$all_wip" = true ] || continue
        if ! recorded_leg_commit "$branch" "$role" || [ "$RECORDED_COMMIT" != "$remote_tip" ]; then
            continue
        fi
        if [ "$RETIRE_PARKED_WIP" = true ]; then
            LEG_RETIRE_LEASE[leg - 1]="$remote_tip"
            continue
        fi
        >&2 echo "Error: $branch ($role leg) is behind origin by $behind parked WIP commit(s); that feature was NOT parked."
        >&2 echo "The parked commit $remote_tip is still the remote tip and this workspace recorded it, so retiring it"
        >&2 echo "cannot destroy anyone else's work:"
        >&2 echo "  git -C $tree_print push --force-with-lease=$branch:$remote_tip origin $branch"
        >&2 echo "park does not force-push on your behalf. Re-run \`make park\` afterwards, or pass"
        >&2 echo "--retire-parked-wip to let park do exactly that one push."
        record_refusal "$branch" "behind by $behind parked WIP commit(s)" \
            "git -C $tree_print push --force-with-lease=$branch:$remote_tip origin $branch"
        refused=true
        break
    done
    [ "$refused" = false ] || { emit_recorded_feature "$branch"; continue; }

    # Commit, then push, per leg.
    LEG_COMMIT=()
    LEG_WIP=()
    LEG_DEPTH=()
    LEG_PUSHED=()
    leg=0
    while [ "$leg" -lt "${#LEG_ROLES[@]}" ]; do
        role="${LEG_ROLES[$leg]}"
        tree="${LEG_TREES[$leg]}"
        tree_print="$(root_relative "$tree")"
        lease="${LEG_RETIRE_LEASE[$leg]:-}"
        leg=$((leg + 1))

        head_before="$(git -C "$tree" rev-parse --verify HEAD 2>/dev/null || true)"
        wip=false
        depth=0
        parked_commit="$head_before"
        if leg_is_dirty "$tree"; then
            if [ "$DRY_RUN" = true ]; then
                wip=true
                depth=1
                parked_commit="(dry-run)"
            else
                if ! commit_error="$( { git -C "$tree" add -A && git -C "$tree" commit -q -m "$WIP_SUBJECT"; } 2>&1 )"; then
                    >&2 echo "Error: committing $branch ($role leg) failed; that feature was NOT parked."
                    if [ -n "$commit_error" ]; then
                        >&2 printf '  %s\n' "$commit_error"
                    fi
                    >&2 echo "  set your identity:  git -C $tree_print config user.email <you>"
                    record_refusal "$branch" "commit failed" \
                        "git -C $tree_print config user.email <you>"
                    refused=true
                    break
                fi
                wip=true
                depth=1
                if commit_subject_is_wip "$tree" "$head_before" \
                    && recorded_leg_commit "$branch" "$role" \
                    && [ "$RECORDED_COMMIT" = "$head_before" ]; then
                    recorded_leg_depth "$branch" "$role"
                    depth=$((RECORDED_DEPTH + 1))
                fi
                parked_commit="$(git -C "$tree" rev-parse --verify HEAD)"
            fi
        elif recorded_leg_commit "$branch" "$role" \
            && [ "$RECORDED_COMMIT" = "$head_before" ] \
            && commit_subject_is_wip "$tree" HEAD; then
            # Clean, and HEAD is still this workspace's own parked WIP commit:
            # make no commit, and keep the recorded depth. Recording wip: false
            # here would disarm resume's un-commit for work that is still
            # parked, and would make a second park rewrite the manifest for
            # nothing.
            recorded_leg_depth "$branch" "$role"
            if [ "$RECORDED_DEPTH" -gt 0 ]; then
                wip=true
                depth="$RECORDED_DEPTH"
            fi
        fi

        pushed=false
        if [ "$NO_PUSH" = true ]; then
            pushed=false
        elif [ "$DRY_RUN" = true ]; then
            pushed=true
        else
            if [ -n "$lease" ]; then
                push_ok=false
                if push_error="$(GIT_TERMINAL_PROMPT=0 git -C "$tree" push --force-with-lease="$branch:$lease" origin "$branch" 2>&1)"; then
                    push_ok=true
                fi
            else
                push_ok=false
                if push_error="$(GIT_TERMINAL_PROMPT=0 git -C "$tree" push origin "$branch" 2>&1)"; then
                    push_ok=true
                fi
            fi
            if [ "$push_ok" != true ]; then
                >&2 echo "Error: pushing $branch to origin refused in the $role leg; that feature was NOT parked."
                if [ -n "$push_error" ]; then
                    >&2 printf '  %s\n' "$push_error"
                fi
                >&2 echo "Your work is NOT lost: it is committed locally at $parked_commit. park never force-pushes."
                >&2 echo "  look:  git -C $tree_print fetch origin && git -C $tree_print log --oneline $parked_commit..origin/$branch"
                >&2 echo "Then reconcile by hand and re-run \`make park\`."
                record_refusal "$branch" "push refused" \
                    "git -C $tree_print fetch origin && git -C $tree_print log --oneline $parked_commit..origin/$branch"
                refused=true
                break
            fi
            pushed=true
        fi

        LEG_COMMIT[${#LEG_COMMIT[@]}]="$parked_commit"
        LEG_WIP[${#LEG_WIP[@]}]="$wip"
        LEG_DEPTH[${#LEG_DEPTH[@]}]="$depth"
        LEG_PUSHED[${#LEG_PUSHED[@]}]="$pushed"
    done
    [ "$refused" = false ] || { emit_recorded_feature "$branch"; continue; }

    # Recorded, and reported.
    workspace_record_section "$RECORD_FILE" feature
    workspace_record_put "$RECORD_FILE" branch "$branch"
    if [ "$REPO_SHAPE" = "three-leg" ]; then
        shape_feature_paths_for "$REPO_ROOT" "$feature_dir" "$branch"
        workspace_record_put "$RECORD_FILE" _feature_directory "$SHAPE_FEATURE_DIR_RELATIVE"
    fi
    append_report "PARKED: $branch"
    leg=0
    while [ "$leg" -lt "${#LEG_ROLES[@]}" ]; do
        role="${LEG_ROLES[$leg]}"
        workspace_record_section "$RECORD_FILE" leg
        workspace_record_put "$RECORD_FILE" role "$role"
        workspace_record_put "$RECORD_FILE" _remote origin
        workspace_record_put "$RECORD_FILE" parked_commit "${LEG_COMMIT[$leg]}"
        workspace_record_put "$RECORD_FILE" wip "${LEG_WIP[$leg]}"
        workspace_record_put "$RECORD_FILE" wip_depth "${LEG_DEPTH[$leg]}"
        workspace_record_put "$RECORD_FILE" pushed "${LEG_PUSHED[$leg]}"
        if [ "${LEG_PUSHED[$leg]}" = true ]; then
            append_report "  $role  wip ${LEG_DEPTH[$leg]}  ${LEG_COMMIT[$leg]}  pushed origin/$branch"
        else
            append_report "  $role  wip ${LEG_DEPTH[$leg]}  ${LEG_COMMIT[$leg]}  NOT pushed"
        fi
        leg=$((leg + 1))
    done
    PARKED_COUNT=$((PARKED_COUNT + 1))
done

if [ "${#PARK_BRANCHES[@]}" -eq 0 ] && [ "${#BLOCKED_DIRS[@]}" -eq 0 ]; then
    echo "[specify] No open features under '$(root_relative "$WORKTREE_ROOT")'; nothing to park." >&2
fi

# ---------------------------------------------------------------------------
# The active feature: the state file first, the newest open feature second,
# exactly the two steps get-last-worktree.sh already uses, so park and cts
# never disagree.
# ---------------------------------------------------------------------------
ACTIVE_FEATURE=""
ACTIVE_FEATURE_SOURCE="worktree_root_fallback"
STATE_COMMON_DIR="$(resolve_git_common_dir || true)"
STATE_FILE=""
if [ -n "$STATE_COMMON_DIR" ]; then
    STATE_FILE="$STATE_COMMON_DIR/speckit-last-worktree.json"
fi
if [ -n "$STATE_FILE" ] && workspace_read_state_field "$STATE_FILE" BRANCH_NAME; then
    case "$OPEN_BRANCHES" in
        *" $WORKSPACE_STATE_VALUE "*)
            ACTIVE_FEATURE="$WORKSPACE_STATE_VALUE"
            ACTIVE_FEATURE_SOURCE="state_file"
            ;;
    esac
fi
if [ -z "$ACTIVE_FEATURE" ] && [ "${#FEATURE_BRANCHES[@]}" -gt 0 ]; then
    ACTIVE_FEATURE="${FEATURE_BRANCHES[0]}"
    ACTIVE_FEATURE_SOURCE="worktree_root_fallback"
fi

# W1: feature.json disagrees. park enumerates from git, so this is a warning
# and never a refusal.
if [ "$REPO_SHAPE" = "three-leg" ] && [ -f "$REPO_ROOT/.specify/feature.json" ]; then
    recorded_dir="$(python3 - "$REPO_ROOT/.specify/feature.json" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], "r", encoding="utf-8") as stream:
        payload = json.load(stream)
except (OSError, ValueError):
    raise SystemExit(0)
if isinstance(payload, dict):
    value = payload.get("feature_directory", "")
    if isinstance(value, str):
        sys.stdout.write(value)
PY
    )" || recorded_dir=""
    if [ -n "$recorded_dir" ]; then
        known=false
        index=0
        while [ "$index" -lt "${#FEATURE_DIRS[@]}" ]; do
            shape_feature_paths_for "$REPO_ROOT" "${FEATURE_DIRS[$index]}" "${FEATURE_BRANCHES[$index]}"
            if [ "$SHAPE_FEATURE_DIR_RELATIVE" = "$recorded_dir" ]; then
                known=true
                break
            fi
            index=$((index + 1))
        done
        if [ "$known" = false ]; then
            echo "[specify] Warning: .specify/feature.json names '$recorded_dir', which is not an open feature under '$(root_relative "$WORKTREE_ROOT")'." >&2
            echo "[specify] Recorded active_feature_source: stale-feature-json; resume will select '$ACTIVE_FEATURE' instead." >&2
            ACTIVE_FEATURE_SOURCE="stale-feature-json"
        fi
    fi
fi

# ---------------------------------------------------------------------------
# The manifest: written under a mutex, committed with an explicit pathspec,
# pushed with a race retry. Never `git add -A`, never a bare `git commit`,
# never `git stash`, never a force-push in the workspace repository.
# ---------------------------------------------------------------------------
TRACKING_BRANCH="$BASE_BRANCH"
if [ -f "$REPO_ROOT/project.yaml" ] \
    && workspace_read_scalar "$REPO_ROOT/project.yaml" tracking_branch \
    && [ -n "$WORKSPACE_SCALAR" ]; then
    TRACKING_BRANCH="$WORKSPACE_SCALAR"
fi
workspace_project_repository "$REPO_ROOT"
PROJECT_REPOSITORY="$WORKSPACE_PROJECT_REPOSITORY"

HEADER_FILE="$RECORD_FILE.header"
{
    printf 'repo_shape\t%s\n' "$REPO_SHAPE"
    printf 'project_id\t%s\n' "$PROJECT_ID"
    printf 'workspace_path\t%s\n' "$WORKSPACE_PATH"
    printf 'workspace_source\t%s\n' "$WORKSPACE_SOURCE_LABEL"
    printf 'manifest_path\t%s\n' "$MANIFEST_RELATIVE"
    printf 'active_feature\t%s\n' "$ACTIVE_FEATURE"
    printf 'active_feature_source\t%s\n' "$ACTIVE_FEATURE_SOURCE"
    printf '_family\t%s\n' "$WORKSPACE_FAMILY"
    printf '_repository\t%s\n' "$PROJECT_REPOSITORY"
    printf '_shape\t%s\n' "$REPO_SHAPE"
    printf '_root\t%s\n' "$(workspace_manifest_root_value "$REPO_ROOT" "$WORKSPACE_FAMILY_DIR")"
    printf '_tracking_branch\t%s\n' "$TRACKING_BRANCH"
    printf '_worktree_root\t%s\n' "$WORKTREE_ROOT_RAW"
    printf '_parked_at\t%s\n' "$TIMESTAMP"
    printf '_parked_on\t%s\n' "$WORKSTATION"
    printf '_parked_by_lane\t%s\n' "$LANE"
    if [ "$DRY_RUN" = true ]; then
        printf 'dry_run\ttrue\n'
    fi
} > "$HEADER_FILE"
cat "$RECORD_FILE" >> "$HEADER_FILE"
index=0
while [ "$index" -lt "${#REFUSED_BRANCHES[@]}" ]; do
    {
        printf '[refused]\n'
        printf 'branch\t%s\n' "${REFUSED_BRANCHES[$index]}"
        printf 'reason\t%s\n' "${REFUSED_REASONS[$index]}"
        printf 'remediation\t%s\n' "${REFUSED_REMEDIATIONS[$index]}"
    } >> "$HEADER_FILE"
    index=$((index + 1))
done
mv "$HEADER_FILE" "$RECORD_FILE"

MANIFEST_STATE="dry-run"
MANIFEST_COMMIT=""
PUSH_STATE="not-pushed"
if [ "$DRY_RUN" != true ]; then
    if ! workspace_lock "$WORKSPACE_PATH"; then
        >&2 echo "Error: another park or resume holds '$WORKSPACE_PATH/.workspaces.lock'; nothing was recorded."
        >&2 echo "  If no other run is active, remove it:  rmdir $WORKSPACE_PATH/.workspaces.lock"
        exit 3
    fi
    if ! workspace_commit_pre_existing "$WORKSPACE_PATH" "$WORKSTATION"; then
        >&2 echo "Error: could not commit the pre-existing changes under '$WORKSPACE_PATH/workspaces'; nothing was recorded."
        exit 3
    fi
    if ! workspace_sync "$WORKSPACE_PATH"; then
        exit 3
    fi
    if ! MANIFEST_STATE="$(workspace_write_manifest "$MANIFEST_PATH" "$RECORD_FILE")"; then
        >&2 echo "Error: could not write '$MANIFEST_PATH'; nothing was recorded."
        exit 3
    fi
    if [ "$MANIFEST_STATE" = "changed" ]; then
        if ! workspace_only_our_file_changed "$WORKSPACE_PATH" "$MANIFEST_RELATIVE"; then
            >&2 echo "Error: writing '$MANIFEST_RELATIVE' left other changes under '$WORKSPACE_PATH/workspaces'; nothing was committed."
            >&2 echo "  look:  git -C $WORKSPACE_PATH status --porcelain -- workspaces"
            exit 3
        fi
        if ! workspace_commit_manifest "$WORKSPACE_PATH" "$MANIFEST_RELATIVE" \
            "park($PROJECT_ID@$WORKSTATION): $PARKED_COUNT feature(s)"; then
            >&2 echo "Error: could not commit '$MANIFEST_RELATIVE' in '$WORKSPACE_PATH'."
            exit 3
        fi
        MANIFEST_COMMIT="$(git -C "$WORKSPACE_PATH" rev-parse --short HEAD)"
        if workspace_push_manifest "$WORKSPACE_PATH"; then
            PUSH_STATE="$WORKSPACE_PUSH_RESULT"
        else
            PUSH_STATE="$WORKSPACE_PUSH_RESULT"
            workspace_unlock
            exit 3
        fi
    fi
    workspace_unlock
fi

# ---------------------------------------------------------------------------
# Output.
# ---------------------------------------------------------------------------
if [ "$JSON_MODE" = true ]; then
    workspace_emit_json "$RECORD_FILE" PARKED
else
    echo "REPO_SHAPE: $REPO_SHAPE"
    echo "PROJECT_ID: $PROJECT_ID"
    echo "WORKSPACE: $WORKSPACE_PATH ($WORKSPACE_SOURCE_LABEL)"
    echo "MANIFEST: $MANIFEST_RELATIVE"
    if [ -n "$PARK_REPORT" ]; then
        printf '%s' "$PARK_REPORT"
    fi
    if [ -n "$ACTIVE_FEATURE" ]; then
        echo "ACTIVE_FEATURE: $ACTIVE_FEATURE ($ACTIVE_FEATURE_SOURCE)"
    fi
    index=0
    while [ "$index" -lt "${#REFUSED_BRANCHES[@]}" ]; do
        echo "REFUSED: ${REFUSED_BRANCHES[$index]} — ${REFUSED_REASONS[$index]}"
        index=$((index + 1))
    done
    if [ "$DRY_RUN" = true ]; then
        echo "COMMITTED: nothing (--dry-run)"
    elif [ "$MANIFEST_STATE" = "changed" ]; then
        if [ "$PUSH_STATE" = "pushed" ]; then
            echo "COMMITTED: $MANIFEST_RELATIVE @ $MANIFEST_COMMIT (pushed)"
        else
            echo "COMMITTED: $MANIFEST_RELATIVE @ $MANIFEST_COMMIT (not pushed)"
        fi
    else
        echo "COMMITTED: $MANIFEST_RELATIVE unchanged (no commit)"
    fi
fi

if [ "${#REFUSED_BRANCHES[@]}" -eq 0 ]; then
    exit 0
fi
if [ "$PARKED_COUNT" -eq 0 ]; then
    exit 2
fi
exit 3
