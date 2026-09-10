#!/usr/bin/env bash
# speckit-overlay-shape: 1
# Git extension: resume.sh
#
# Recreate the worktrees park.sh recorded, restore .specify/feature.json and
# the last-worktree state file, and un-commit the parked WIP so the work comes
# back exactly as it was left. Implements openRepoShape#77 as ruled by Brett
# Heap on 2026-09-09, point 2: resume REFUSES on divergence and never resets
# over commits this workspace did not park.

set -e

JSON_MODE=false
DRY_RUN=false
KEEP_STAGED=false
WORKSPACE_ARG=""
REQUESTED_BRANCHES=()

usage() {
    echo "Usage: $0 [--json] [--dry-run] [--feature <branch>]... [--workspace <path>]"
    echo "          [--keep-staged] [-h|--help]"
    echo ""
    echo "Recreate the worktrees this workspace parked, and un-commit the parked WIP."
    echo ""
    echo "Options:"
    echo "  --json                 Output in JSON format"
    echo "  --dry-run              Print the plan; create, write and reset nothing"
    echo "  --feature <branch>     Resume only this feature; repeatable. Default: every"
    echo "                         manifest entry for this project"
    echo "  --workspace <path>     Workspace checkout to read, overriding the user config"
    echo "  --keep-staged          Stop after the soft reset, leaving the work staged"
    echo "  --help, -h             Show this help message"
    echo ""
    echo "Exit codes:"
    echo "  0  everything asked for was resumed, or there was nothing to resume"
    echo "  1  usage or environment error"
    echo "  2  a refusal before anything was done, or every feature was refused"
    echo "  3  partial: at least one feature was resumed and at least one refused"
    echo ""
    echo "Environment variables:"
    echo "  SPECKIT_WORKSPACE_PATH        Workspace checkout, overriding the user config"
    echo "  SPECKIT_WORKSPACE_REPOSITORY  Workspace repository, for the clone remediation"
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
        --keep-staged) KEEP_STAGED=true ;;
        --feature|--workspace)
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

SCRIPT_DIR="$(CDPATH="" cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_REPO_ROOT="$(CDPATH="" cd -- "$SCRIPT_DIR/../../../../.." && pwd 2>/dev/null || true)"
if [ ! -f "$SCRIPT_DIR/git-common.sh" ]; then
    echo "Error: Could not locate git-common.sh next to resume.sh." >&2
    exit 1
fi
source "$SCRIPT_DIR/git-common.sh"
if [ ! -f "$SCRIPT_DIR/workspace-common.sh" ]; then
    echo "Error: Could not locate workspace-common.sh next to resume.sh." >&2
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
    echo "Error: checkout_mode '$CHECKOUT_MODE' has no worktree to resume; nothing was resumed." >&2
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
    echo "Error: resume requires Python 3 for safe manifest and state publication." >&2
    exit 1
fi
if [ "$JSON_MODE" = true ] && ! select_json_encoder >/dev/null; then
    echo "Error: JSON output requires jq, a trusted json_escape function, or Python 3; no JSON encoder is available." >&2
    exit 1
fi

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
    echo "Error: '$MANIFEST_ORG' is not a usable workspace org name; nothing was resumed." >&2
    echo "The org is the owner segment of repository: in project.yaml (or in the family's family.yaml) and must match [A-Za-z0-9._-]+." >&2
    echo "Correct that repository: value, then re-run \`make resume\`." >&2
    exit 2
fi

WORKSPACE_RESOLVE_STATUS=0
workspace_resolve "$WORKSPACE_ARG" "$MANIFEST_ORG" || WORKSPACE_RESOLVE_STATUS=$?
if [ "$WORKSPACE_RESOLVE_STATUS" -eq 2 ]; then
    workspace_refuse_invalid_config resumed resume
    exit 2
elif [ "$WORKSPACE_RESOLVE_STATUS" -ne 0 ]; then
    workspace_refuse_no_config resumed resume
    exit 2
fi
if ! workspace_is_checkout "$WORKSPACE_PATH"; then
    workspace_refuse_not_a_checkout resumed
    exit 2
fi

if ! workspace_name_is_safe "$MANIFEST_NAME"; then
    echo "Error: '$MANIFEST_NAME' is not a usable workspace manifest name; nothing was resumed." >&2
    echo "A manifest file is named for the family or the project id and must match [A-Za-z0-9._-]+." >&2
    echo "Rename the id: in project.yaml (or in the family's family.yaml), then re-run \`make resume\`." >&2
    exit 2
fi
MANIFEST_RELATIVE="workspaces/$MANIFEST_ORG/$MANIFEST_NAME.yaml"
MANIFEST_PATH="$WORKSPACE_PATH/$MANIFEST_RELATIVE"

# RR7 — no entry for this project.
if ! workspace_load_project "$MANIFEST_PATH" "$PROJECT_ID"; then
    >&2 echo "Error: $WORKSPACE_PATH/workspaces/$MANIFEST_ORG/ has no entry for project '$PROJECT_ID'; nothing was resumed."
    >&2 echo "Either nothing was parked for it, or it was parked into a different file:"
    >&2 echo "  grep -rn \"id: $PROJECT_ID\" $WORKSPACE_PATH/workspaces/$MANIFEST_ORG/"
    exit 2
fi

root_relative() {
    local path="$1"

    case "$path" in
        "$REPO_ROOT") printf '%s\n' "." ;;
        "$REPO_ROOT"/*) printf '%s\n' "${path#"$REPO_ROOT/"}" ;;
        *) printf '%s\n' "$path" ;;
    esac
}

WIP_PREFIX='wip: park '

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

commit_has_one_parent() {
    local tree="$1"
    local revision="$2"
    local parents

    parents="$(git -C "$tree" log -1 --format=%P "$revision" 2>/dev/null || true)"
    case "$parents" in
        '') return 1 ;;
        *' '*) return 1 ;;
        *) return 0 ;;
    esac
}

# True when every commit in <from>..<to> carries the WIP subject prefix and
# there are exactly <depth> of them: the gap a previous resume's soft reset
# leaves behind, as opposed to real work this workspace never parked.
wip_gap_is_ours() {
    local tree="$1"
    local from="$2"
    local to="$3"
    local depth="$4"
    local count step

    [ "$depth" -gt 0 ] || return 1
    git -C "$tree" cat-file -e "$to^{commit}" 2>/dev/null || return 1
    count="$(git -C "$tree" rev-list --count "$from..$to" 2>/dev/null || echo 0)"
    [ "$count" = "$depth" ] || return 1
    step=0
    while [ "$step" -lt "$depth" ]; do
        commit_subject_is_wip "$tree" "$to~$step" || return 1
        step=$((step + 1))
    done
    return 0
}

leg_registered_at() {
    local leg="$1"
    local path="$2"
    local index=0

    LEG_REGISTERED_BRANCH=""
    load_git_worktrees "$leg" || return 2
    while [ "$index" -lt "${#GIT_WORKTREE_PATHS[@]}" ]; do
        if [ "${GIT_WORKTREE_PATHS[$index]}" = "$path" ]; then
            LEG_REGISTERED_BRANCH="${GIT_WORKTREE_BRANCH_REFS[$index]#refs/heads/}"
            return 0
        fi
        index=$((index + 1))
    done
    return 1
}

# The legs of one manifest feature, mapped onto THIS checkout's layout.
LEG_ROLES=()
LEG_REPOS=()
LEG_MOUNTS=()
LEG_TREES=()
LEG_COMMITS=()
LEG_DEPTHS=()
LEG_PUSHEDS=()

collect_legs() {
    local feature_index="$1"
    local branch="$2"
    local index=0
    local role

    LEG_ROLES=()
    LEG_REPOS=()
    LEG_MOUNTS=()
    LEG_TREES=()
    LEG_COMMITS=()
    LEG_DEPTHS=()
    LEG_PUSHEDS=()
    while [ "$index" -lt "${#MANIFEST_LEG_ROLE[@]}" ]; do
        if [ "${MANIFEST_LEG_FEATURE[$index]}" != "$feature_index" ]; then
            index=$((index + 1))
            continue
        fi
        role="${MANIFEST_LEG_ROLE[$index]}"
        case "$role" in
            spec)
                [ "$REPO_SHAPE" = "three-leg" ] || return 1
                LEG_REPOS[${#LEG_REPOS[@]}]="$SPEC_LEG"
                LEG_MOUNTS[${#LEG_MOUNTS[@]}]="$SHAPE_SPEC_PATH"
                LEG_TREES[${#LEG_TREES[@]}]="$WORKTREE_ROOT/$branch/$SHAPE_SPEC_PATH"
                ;;
            code)
                [ "$REPO_SHAPE" = "three-leg" ] || return 1
                LEG_REPOS[${#LEG_REPOS[@]}]="$CODE_LEG"
                LEG_MOUNTS[${#LEG_MOUNTS[@]}]="$SHAPE_CODE_PATH"
                LEG_TREES[${#LEG_TREES[@]}]="$WORKTREE_ROOT/$branch/$SHAPE_CODE_PATH"
                ;;
            repo)
                [ "$REPO_SHAPE" = "single" ] || return 1
                LEG_REPOS[${#LEG_REPOS[@]}]="$REPO_ROOT"
                LEG_MOUNTS[${#LEG_MOUNTS[@]}]="."
                LEG_TREES[${#LEG_TREES[@]}]="$WORKTREE_ROOT/$branch"
                ;;
            *) return 1 ;;
        esac
        LEG_ROLES[${#LEG_ROLES[@]}]="$role"
        LEG_COMMITS[${#LEG_COMMITS[@]}]="${MANIFEST_LEG_COMMIT[$index]}"
        LEG_DEPTHS[${#LEG_DEPTHS[@]}]="${MANIFEST_LEG_DEPTH[$index]}"
        LEG_PUSHEDS[${#LEG_PUSHEDS[@]}]="${MANIFEST_LEG_PUSHED[$index]}"
        index=$((index + 1))
    done
    [ "${#LEG_ROLES[@]}" -gt 0 ]
}

REFUSED_BRANCHES=()
REFUSED_REASONS=()
REFUSED_REMEDIATIONS=()
RESUMED_COUNT=0
RESUMED_BRANCHES=()

record_refusal() {
    REFUSED_BRANCHES[${#REFUSED_BRANCHES[@]}]="$1"
    REFUSED_REASONS[${#REFUSED_REASONS[@]}]="$2"
    REFUSED_REMEDIATIONS[${#REFUSED_REMEDIATIONS[@]}]="$3"
}

_git_worktree_create_temp_file || {
    echo "Error: could not create a temporary file for the resume record." >&2
    exit 1
}
RECORD_FILE="$_GIT_WORKTREE_OUTPUT_FILE"
_git_worktree_create_temp_file || {
    echo "Error: could not create a temporary file for the resume record." >&2
    exit 1
}
HEADER_FILE="$_GIT_WORKTREE_OUTPUT_FILE"
# shellcheck disable=SC2329  # an EXIT trap handler
cleanup() {
    [ -n "${RECORD_FILE:-}" ] && rm -f "$RECORD_FILE" 2>/dev/null || true
    [ -n "${HEADER_FILE:-}" ] && rm -f "$HEADER_FILE" 2>/dev/null || true
    return 0
}
trap cleanup EXIT

RESUME_REPORT=""
append_report() {
    RESUME_REPORT="$RESUME_REPORT$1
"
}

# Which manifest features to work on.
SELECTED_INDEXES=()
index=0
while [ "$index" -lt "${#MANIFEST_FEATURE_BRANCHES[@]}" ]; do
    if [ "${#REQUESTED_BRANCHES[@]}" -eq 0 ]; then
        SELECTED_INDEXES[${#SELECTED_INDEXES[@]}]="$index"
    else
        inner=0
        while [ "$inner" -lt "${#REQUESTED_BRANCHES[@]}" ]; do
            if [ "${REQUESTED_BRANCHES[$inner]}" = "${MANIFEST_FEATURE_BRANCHES[$index]}" ]; then
                SELECTED_INDEXES[${#SELECTED_INDEXES[@]}]="$index"
                break
            fi
            inner=$((inner + 1))
        done
    fi
    index=$((index + 1))
done

if [ "${#REQUESTED_BRANCHES[@]}" -gt 0 ] \
    && [ "${#SELECTED_INDEXES[@]}" -ne "${#REQUESTED_BRANCHES[@]}" ]; then
    >&2 echo "Error: $MANIFEST_PATH has no entry for every --feature named; nothing was resumed."
    >&2 echo "  look:  grep -n 'branch:' $MANIFEST_PATH"
    exit 1
fi

if [ "${#MANIFEST_FEATURE_BRANCHES[@]}" -eq 0 ]; then
    echo "[specify] $MANIFEST_RELATIVE records no open features for '$PROJECT_ID'; nothing to resume." >&2
fi

# ---------------------------------------------------------------------------
# Per feature: check everything, then touch nothing unless every check passed.
# ---------------------------------------------------------------------------
selection=0
while [ "$selection" -lt "${#SELECTED_INDEXES[@]}" ]; do
    feature_index="${SELECTED_INDEXES[$selection]}"
    selection=$((selection + 1))
    branch="${MANIFEST_FEATURE_BRANCHES[$feature_index]}"

    if ! collect_legs "$feature_index" "$branch"; then
        >&2 echo "Error: $branch was parked from a $MANIFEST_SHAPE project and this checkout is $REPO_SHAPE; that feature was NOT recreated."
        >&2 echo "  look:  grep -n 'shape:' $MANIFEST_PATH"
        record_refusal "$branch" "shape mismatch" "grep -n 'shape:' $MANIFEST_PATH"
        continue
    fi

    refused=false
    LEG_ACTION=()
    leg=0
    while [ "$leg" -lt "${#LEG_ROLES[@]}" ]; do
        role="${LEG_ROLES[$leg]}"
        leg_repo="${LEG_REPOS[$leg]}"
        mount="${LEG_MOUNTS[$leg]}"
        tree="${LEG_TREES[$leg]}"
        parked_commit="${LEG_COMMITS[$leg]}"
        pushed="${LEG_PUSHEDS[$leg]}"
        LEG_ACTION[leg]="create"
        leg=$((leg + 1))

        # RR6 — parked with --no-push.
        if [ "$pushed" != true ]; then
            >&2 echo "Error: $branch ($role leg) was parked with --no-push; that feature was NOT recreated."
            >&2 echo "Its parked commit $parked_commit exists only on the workstation that parked it ($MANIFEST_PARKED_ON)."
            >&2 echo "Push it there, re-run \`make park\`, then resume here."
            record_refusal "$branch" "parked with --no-push" "re-run \`make park\` on $MANIFEST_PARKED_ON"
            refused=true
            break
        fi

        # RR4 — already recreated. Not a refusal: resume is idempotent, and
        # after the first resume the local branch is legitimately BEHIND the
        # parked commit, so this must be decided before RR1 and RR5.
        if leg_registered_at "$leg_repo" "$tree"; then
            if [ "$LEG_REGISTERED_BRANCH" = "$branch" ]; then
                LEG_ACTION[leg - 1]="present"
                present_head="$(git -C "$tree" rev-parse --verify HEAD 2>/dev/null || true)"
                present_depth="${LEG_DEPTHS[$((leg - 1))]}"
                case "$present_depth" in
                    ''|*[!0-9]*) present_depth=0 ;;
                esac
                if [ -n "$present_head" ] && [ "$present_head" != "$parked_commit" ] \
                    && git -C "$tree" merge-base --is-ancestor "$present_head" "$parked_commit" 2>/dev/null \
                    && ! wip_gap_is_ours "$tree" "$present_head" "$parked_commit" "$present_depth"; then
                    >&2 echo "Error: the $role leg's local branch '$branch' is BEHIND the parked commit ($present_head is an ancestor of $parked_commit); that feature was NOT recreated."
                    >&2 echo "Fast-forward it, then re-run:"
                    >&2 echo "  git -C $(root_relative "$tree") pull --ff-only origin $branch"
                    >&2 echo "  make resume"
                    record_refusal "$branch" "the local branch is behind the parked commit" \
                        "git -C $(root_relative "$tree") pull --ff-only origin $branch"
                    refused=true
                    break
                fi
                continue
            fi
            >&2 echo "Error: '$(root_relative "$tree")' exists and is not a registered worktree of the $role leg; that feature was NOT recreated."
            >&2 echo "Nothing here overwrites a directory it did not create."
            >&2 echo "  look:  git -C $mount worktree list"
            >&2 echo "Move it aside, then re-run \`make resume\`."
            record_refusal "$branch" "an unrelated worktree is in the way" \
                "git -C $mount worktree list"
            refused=true
            break
        fi

        # RR3 — something else is already at the worktree path.
        if [ -e "$tree" ]; then
            >&2 echo "Error: '$(root_relative "$tree")' exists and is not a registered worktree of the $role leg; that feature was NOT recreated."
            >&2 echo "Nothing here overwrites a directory it did not create."
            >&2 echo "  look:  git -C $mount worktree list"
            >&2 echo "Move it aside, then re-run \`make resume\`."
            record_refusal "$branch" "an unrelated path is in the way" \
                "git -C $mount worktree list"
            refused=true
            break
        fi

        # RR2 — the branch is gone from the remote.
        if [ "$DRY_RUN" != true ]; then
            GIT_TERMINAL_PROMPT=0 git -C "$leg_repo" fetch -q origin \
                "+refs/heads/$branch:refs/remotes/origin/$branch" >/dev/null 2>&1 || true
        fi
        remote_tip="$(git -C "$leg_repo" rev-parse --verify --quiet "refs/remotes/origin/$branch" 2>/dev/null || true)"
        if [ -z "$remote_tip" ]; then
            >&2 echo "Error: $branch is no longer on origin in the $role leg; that feature was NOT recreated."
            >&2 echo "The manifest recorded it at $parked_commit, parked $MANIFEST_PARKED_AT on $MANIFEST_PARKED_ON."
            >&2 echo "If the feature landed, delete its entry:"
            >&2 echo "  $WORKSPACE_PATH/$MANIFEST_RELATIVE  ->  remove the \`- branch: $branch\` block"
            >&2 echo "If it was deleted by mistake, push it again from the workstation that parked it."
            record_refusal "$branch" "gone from origin" \
                "remove the \`- branch: $branch\` block from $MANIFEST_RELATIVE"
            refused=true
            break
        fi

        # RR1 — divergence. The ruling: nothing is ever reset over commits
        # this workspace did not park.
        if [ "$remote_tip" != "$parked_commit" ]; then
            >&2 echo "Error: $branch ($role leg) has moved since it was parked; that feature was NOT recreated."
            >&2 echo "  parked commit  $parked_commit   (parked $MANIFEST_PARKED_AT on $MANIFEST_PARKED_ON)"
            >&2 echo "  current tip    $remote_tip   (origin/$branch)"
            >&2 echo "Nothing is ever reset over commits this workspace did not park. Reconcile by hand:"
            >&2 echo "  git -C $mount fetch origin $branch"
            >&2 echo "  git -C $mount log --oneline $parked_commit..origin/$branch"
            >&2 echo "  git -C $mount worktree add -b $branch $WORKTREE_ROOT_RAW/$branch/$mount origin/$branch"
            >&2 echo "  # then decide: rebase the parked WIP onto the new tip, or discard it"
            record_refusal "$branch" "divergence" \
                "git -C $mount log --oneline $parked_commit..origin/$branch"
            refused=true
            break
        fi

        # RR5 — a local branch that is not the parked commit. Two cases, and
        # they call for opposite remediations: a branch this workstation left
        # BEHIND is fast-forwarded, a branch that DIVERGED carries local
        # commits the parked commit does not contain and nothing here may
        # discard them.
        local_sha="$(git -C "$leg_repo" rev-parse --verify --quiet "refs/heads/$branch" 2>/dev/null || true)"
        if [ -n "$local_sha" ] && [ "$local_sha" != "$parked_commit" ]; then
            if git -C "$leg_repo" merge-base --is-ancestor "$local_sha" "$parked_commit" 2>/dev/null; then
                >&2 echo "Error: the $role leg's local branch '$branch' is BEHIND the parked commit ($local_sha is an ancestor of $parked_commit); that feature was NOT recreated."
                >&2 echo "Fast-forward it, then re-run:"
                >&2 echo "  git -C $mount fetch origin $branch:$branch"
                >&2 echo "  make resume"
                record_refusal "$branch" "the local branch is behind the parked commit" \
                    "git -C $mount fetch origin $branch:$branch"
                refused=true
                break
            fi
            >&2 echo "Error: the $role leg already has a local branch '$branch' at $local_sha, not the parked commit $parked_commit; that feature was NOT recreated."
            >&2 echo "  git -C $mount log --oneline $parked_commit..$branch"
            >&2 echo "Rename or delete that branch, then re-run \`make resume\`."
            record_refusal "$branch" "local branch is not the parked commit" \
                "git -C $mount log --oneline $parked_commit..$branch"
            refused=true
            break
        fi

        if [ -n "$local_sha" ]; then
            LEG_ACTION[leg - 1]="attach"
        else
            LEG_ACTION[leg - 1]="create"
        fi
    done
    [ "$refused" = false ] || continue

    if [ "$DRY_RUN" = true ]; then
        append_report "RESUMED: $branch (--dry-run)"
        workspace_record_section "$RECORD_FILE" feature
        workspace_record_put "$RECORD_FILE" branch "$branch"
        leg=0
        while [ "$leg" -lt "${#LEG_ROLES[@]}" ]; do
            workspace_record_section "$RECORD_FILE" leg
            workspace_record_put "$RECORD_FILE" role "${LEG_ROLES[$leg]}"
            workspace_record_put "$RECORD_FILE" path "$(root_relative "${LEG_TREES[$leg]}")"
            workspace_record_put "$RECORD_FILE" head "${LEG_COMMITS[$leg]}"
            workspace_record_put "$RECORD_FILE" action "${LEG_ACTION[$leg]}"
            append_report "  ${LEG_ROLES[$leg]}  $(root_relative "${LEG_TREES[$leg]}")  ${LEG_COMMITS[$leg]}  would ${LEG_ACTION[$leg]}"
            leg=$((leg + 1))
        done
        RESUMED_COUNT=$((RESUMED_COUNT + 1))
        RESUMED_BRANCHES[${#RESUMED_BRANCHES[@]}]="$branch"
        continue
    fi

    # Create. A failure in a later leg rolls back the earlier ones, exactly as
    # shape_rollback_spec_worktree does for feature creation.
    CREATED_TREES=()
    CREATED_OWNERS=()
    CREATED_BRANCH_NEW=()
    mkdir -p "$WORKTREE_ROOT/$branch" 2>/dev/null || true
    leg=0
    while [ "$leg" -lt "${#LEG_ROLES[@]}" ]; do
        role="${LEG_ROLES[$leg]}"
        leg_repo="${LEG_REPOS[$leg]}"
        tree="${LEG_TREES[$leg]}"
        action="${LEG_ACTION[$leg]}"
        leg=$((leg + 1))
        case "$action" in
            present)
                echo "[specify] $branch ($role): worktree already registered at $(root_relative "$tree"); left as it is." >&2
                continue
                ;;
            attach)
                if ! worktree_error="$(git -C "$leg_repo" worktree add "$tree" "$branch" 2>&1)"; then
                    >&2 echo "Error: could not add the $role leg worktree '$(root_relative "$tree")' for '$branch'; that feature was NOT recreated."
                    >&2 printf '  %s\n' "$worktree_error"
                    record_refusal "$branch" "git worktree add failed" \
                        "git -C ${LEG_MOUNTS[$((leg - 1))]} worktree add $(root_relative "$tree") $branch"
                    refused=true
                    break
                fi
                CREATED_TREES[${#CREATED_TREES[@]}]="$tree"
                CREATED_OWNERS[${#CREATED_OWNERS[@]}]="$leg_repo"
                CREATED_BRANCH_NEW[${#CREATED_BRANCH_NEW[@]}]=false
                ;;
            create)
                if ! worktree_error="$(git -C "$leg_repo" worktree add -b "$branch" "$tree" "origin/$branch" 2>&1)"; then
                    >&2 echo "Error: could not create the $role leg worktree '$(root_relative "$tree")' from 'origin/$branch'; that feature was NOT recreated."
                    >&2 printf '  %s\n' "$worktree_error"
                    record_refusal "$branch" "git worktree add failed" \
                        "git -C ${LEG_MOUNTS[$((leg - 1))]} worktree add -b $branch $(root_relative "$tree") origin/$branch"
                    refused=true
                    break
                fi
                CREATED_TREES[${#CREATED_TREES[@]}]="$tree"
                CREATED_OWNERS[${#CREATED_OWNERS[@]}]="$leg_repo"
                CREATED_BRANCH_NEW[${#CREATED_BRANCH_NEW[@]}]=true
                ;;
        esac
    done
    if [ "$refused" = true ]; then
        >&2 echo "[specify] Rolling back the worktrees this run created for '$branch'."
        undo=0
        while [ "$undo" -lt "${#CREATED_TREES[@]}" ]; do
            undo_tree="${CREATED_TREES[$undo]}"
            # The owner is always the LEG repository that registered the
            # worktree. Naming the assembly root instead makes `worktree
            # remove` fail, the fallback `rm -rf` take the directory, and the
            # leg keep a phantom registration a later resume reads as
            # "already registered" for a path that is not there.
            owner="${CREATED_OWNERS[$undo]}"
            undo_new_branch="${CREATED_BRANCH_NEW[$undo]}"
            undo=$((undo + 1))
            git -C "$owner" worktree remove --force "$undo_tree" >/dev/null 2>&1 \
                || rm -rf "$undo_tree" >/dev/null 2>&1 || true
            git -C "$owner" worktree prune >/dev/null 2>&1 || true
            if [ "$undo_new_branch" = true ]; then
                git -C "$owner" branch -D "$branch" >/dev/null 2>&1 || true
            fi
        done
        rmdir "$WORKTREE_ROOT/$branch" >/dev/null 2>&1 || true
        continue
    fi

    # Un-commit the parked WIP. Three facts, never the prefix alone.
    workspace_record_section "$RECORD_FILE" feature
    workspace_record_put "$RECORD_FILE" branch "$branch"
    append_report "RESUMED: $branch"
    leg=0
    while [ "$leg" -lt "${#LEG_ROLES[@]}" ]; do
        role="${LEG_ROLES[$leg]}"
        tree="${LEG_TREES[$leg]}"
        parked_commit="${LEG_COMMITS[$leg]}"
        depth="${LEG_DEPTHS[$leg]}"
        leg=$((leg + 1))
        case "$depth" in
            ''|*[!0-9]*) depth=0 ;;
        esac
        head_now="$(git -C "$tree" rev-parse --verify HEAD 2>/dev/null || true)"
        short_head="$(git -C "$tree" rev-parse --short HEAD 2>/dev/null || true)"
        note="clean"
        if [ "$depth" -gt 0 ]; then
            if [ "$head_now" != "$parked_commit" ]; then
                echo "[specify] Warning: $branch ($role): HEAD is $head_now, not the parked commit $parked_commit; the parked WIP was NOT un-committed." >&2
                note="left as it is"
            else
                recognised=true
                step=0
                while [ "$step" -lt "$depth" ]; do
                    if ! commit_subject_is_wip "$tree" "HEAD~$step" \
                        || ! commit_has_one_parent "$tree" "HEAD~$step"; then
                        recognised=false
                        break
                    fi
                    step=$((step + 1))
                done
                if [ "$recognised" != true ]; then
                    echo "[specify] Warning: $branch ($role): the $depth tip commit(s) are not this workspace's parked WIP; nothing was reset." >&2
                    note="left as it is"
                else
                    plural="commits"
                    [ "$depth" -eq 1 ] && plural="commit"
                    git -C "$tree" reset --soft "HEAD~$depth"
                    if [ "$KEEP_STAGED" = true ]; then
                        note="un-committed $depth WIP $plural, staged"
                    else
                        git -C "$tree" reset -q
                        note="un-committed $depth WIP $plural"
                    fi
                    short_head="$(git -C "$tree" rev-parse --short HEAD 2>/dev/null || true)"
                fi
            fi
        fi
        workspace_record_section "$RECORD_FILE" leg
        workspace_record_put "$RECORD_FILE" role "$role"
        workspace_record_put "$RECORD_FILE" path "$(root_relative "$tree")"
        workspace_record_put "$RECORD_FILE" head "$(git -C "$tree" rev-parse --verify HEAD 2>/dev/null || true)"
        workspace_record_put "$RECORD_FILE" note "$note"
        append_report "  $role  $(root_relative "$tree")  $short_head  $note"
    done
    RESUMED_COUNT=$((RESUMED_COUNT + 1))
    RESUMED_BRANCHES[${#RESUMED_BRANCHES[@]}]="$branch"
done

# ---------------------------------------------------------------------------
# The active feature: feature.json (three-leg only) and the state file.
# ---------------------------------------------------------------------------
ACTIVE_FEATURE="$MANIFEST_ACTIVE_FEATURE"
if [ -n "$ACTIVE_FEATURE" ]; then
    known=false
    index=0
    while [ "$index" -lt "${#RESUMED_BRANCHES[@]}" ]; do
        if [ "${RESUMED_BRANCHES[$index]}" = "$ACTIVE_FEATURE" ]; then
            known=true
            break
        fi
        index=$((index + 1))
    done
    if [ "$known" = false ]; then
        ACTIVE_FEATURE=""
        if [ "${#RESUMED_BRANCHES[@]}" -gt 0 ]; then
            ACTIVE_FEATURE="${RESUMED_BRANCHES[0]}"
        fi
    fi
fi

FEATURE_JSON_VALUE=""
STATE_FILE_VALUE=""
if [ -n "$ACTIVE_FEATURE" ] && [ "$DRY_RUN" != true ]; then
    if [ "$REPO_SHAPE" = "three-leg" ]; then
        shape_feature_paths_for "$REPO_ROOT" "$WORKTREE_ROOT/$ACTIVE_FEATURE" "$ACTIVE_FEATURE"
        FEATURE_JSON_VALUE="$SHAPE_FEATURE_DIR_RELATIVE"
        previous=""
        if [ -f "$REPO_ROOT/.specify/feature.json" ]; then
            previous="$(python3 - "$REPO_ROOT/.specify/feature.json" <<'PY'
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
            )" || previous=""
        fi
        if [ -n "$previous" ] && [ "$previous" != "$FEATURE_JSON_VALUE" ]; then
            echo "[specify] Warning: .specify/feature.json named '$previous'; rewritten to the parked active feature '$ACTIVE_FEATURE'." >&2
            if [ -d "$REPO_ROOT/$previous" ]; then
                echo "[specify] The manifest wins: '$ACTIVE_FEATURE' is what travelled, and the other feature is recreated but not selected." >&2
            fi
        fi
        mkdir -p "$SHAPE_FEATURE_DIR" 2>/dev/null || true
        shape_persist_feature_json "$FEATURE_JSON_VALUE" || {
            >&2 echo "Error: could not write .specify/feature.json."
            exit 1
        }
    fi

    if STATE_COMMON_DIR="$(resolve_git_common_dir)"; then
        STATE_FILE="$STATE_COMMON_DIR/speckit-last-worktree.json"
        if assert_state_file_safe "$STATE_FILE"; then
            active_worktree="$WORKTREE_ROOT/$ACTIVE_FEATURE"
            if write_last_worktree_state "$ACTIVE_FEATURE" "$active_worktree" "$BASE_BRANCH"; then
                STATE_FILE_VALUE="$(root_relative "$STATE_FILE")"
            else
                >&2 echo "[specify] Warning: could not publish $(root_relative "$STATE_FILE")."
            fi
        fi
    fi
fi

# The recreated worktrees must not show up in the root's `git status`.
if [ "${#RESUMED_BRANCHES[@]}" -gt 0 ] && [ "$REPO_SHAPE" = "three-leg" ]; then
    if ! { [ -f "$REPO_ROOT/.gitignore" ] \
        && grep -Eq "^/?$WORKTREE_ROOT_RAW/?$" "$REPO_ROOT/.gitignore"; }; then
        echo "[specify] Warning: '$REPO_ROOT/.gitignore' does not ignore /$WORKTREE_ROOT_RAW/; the recreated worktrees will show in \`git status\` at the root. Add the line, or re-run setup-openspeckit." >&2
    fi
fi

# ---------------------------------------------------------------------------
# Output.
# ---------------------------------------------------------------------------
{
    printf 'repo_shape\t%s\n' "$REPO_SHAPE"
    printf 'project_id\t%s\n' "$PROJECT_ID"
    printf 'workspace_path\t%s\n' "$WORKSPACE_PATH"
    printf 'workspace_source\t%s\n' "$WORKSPACE_SOURCE_LABEL"
    printf 'manifest_path\t%s\n' "$MANIFEST_PATH"
    if [ -n "$ACTIVE_FEATURE" ]; then
        printf 'active_feature\t%s\n' "$ACTIVE_FEATURE"
    fi
    if [ -n "$FEATURE_JSON_VALUE" ]; then
        printf 'feature_json\t%s\n' "$FEATURE_JSON_VALUE"
    fi
    if [ -n "$STATE_FILE_VALUE" ]; then
        printf 'state_file\t%s\n' "$STATE_FILE_VALUE"
    fi
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

if [ "$JSON_MODE" = true ]; then
    workspace_emit_json "$RECORD_FILE" RESUMED
else
    echo "REPO_SHAPE: $REPO_SHAPE"
    echo "PROJECT_ID: $PROJECT_ID"
    echo "MANIFEST: $MANIFEST_PATH"
    if [ -n "$RESUME_REPORT" ]; then
        printf '%s' "$RESUME_REPORT"
    fi
    if [ -n "$FEATURE_JSON_VALUE" ]; then
        echo "FEATURE_JSON: $FEATURE_JSON_VALUE"
    fi
    if [ -n "$STATE_FILE_VALUE" ]; then
        echo "STATE_FILE: $STATE_FILE_VALUE (BRANCH_NAME=$ACTIVE_FEATURE)"
    fi
    index=0
    while [ "$index" -lt "${#REFUSED_BRANCHES[@]}" ]; do
        echo "REFUSED: ${REFUSED_BRANCHES[$index]} — ${REFUSED_REASONS[$index]}"
        index=$((index + 1))
    done
fi

if [ "${#REFUSED_BRANCHES[@]}" -eq 0 ]; then
    exit 0
fi
if [ "$RESUMED_COUNT" -eq 0 ]; then
    exit 2
fi
exit 3
