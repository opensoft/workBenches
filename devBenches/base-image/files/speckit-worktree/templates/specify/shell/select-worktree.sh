#!/usr/bin/env bash

set -euo pipefail

capture_path() {
    local frame='__SPECKIT_PATH_CAPTURE_FRAME_7D3A9C__'
    local captured capture_status producer_status

    CAPTURED_PATH=""
    if captured="$(
        if "$@"; then
            producer_status=0
        else
            producer_status=$?
        fi
        printf '%s' "$frame"
        exit "$producer_status"
    )"; then
        capture_status=0
    else
        capture_status=$?
    fi

    case "$captured" in
        *"$frame") captured="${captured%"$frame"}" ;;
        *) [ "$capture_status" -ne 0 ] && return "$capture_status"; return 1 ;;
    esac
    [ "$capture_status" -eq 0 ] || return "$capture_status"
    case "$captured" in
        *$'\n') captured="${captured%$'\n'}" ;;
    esac
    CAPTURED_PATH="$captured"
}

print_script_dir() {
    local script_path="${BASH_SOURCE[0]}"
    local script_dir="${script_path%/*}"

    [ "$script_dir" != "$script_path" ] || script_dir=.
    CDPATH="" cd "$script_dir" && pwd
}

print_canonical_dir() {
    CDPATH="" cd "$1" && pwd -P
}

capture_path print_script_dir
SCRIPT_DIR="$CAPTURED_PATH"
capture_path print_canonical_dir "$SCRIPT_DIR/../.."
REPO_ROOT="$CAPTURED_PATH"
GIT_COMMON_SCRIPT="$SCRIPT_DIR/../extensions/git/scripts/bash/git-common.sh"
if [ ! -f "$GIT_COMMON_SCRIPT" ]; then
    echo "Error: Could not locate the Git extension git-common.sh." >&2
    exit 1
fi
source "$GIT_COMMON_SCRIPT"

trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

normalize_config_value() {
    local value="$1"

    value="${value%%[[:space:]]#*}"
    value="$(trim "$value")"
    case "$value" in
        \"*\")
            value="${value#\"}"
            value="${value%\"}"
            ;;
        \'*\')
            value="${value#\'}"
            value="${value%\'}"
            ;;
    esac
    printf '%s' "$value"
}

resolve_config_value() {
    local repo_root="$1"
    local key="$2"
    local default_value="$3"
    local config_file="$repo_root/.specify/extensions/git/git-config.yml"

    if [ ! -f "$config_file" ]; then
        printf '%s\n' "$default_value"
        return 0
    fi

    local raw_value
    raw_value=$(awk -F':' -v key="$key" '$1 == key {sub(/^[^:]*:[[:space:]]*/, "", $0); print $0; exit}' "$config_file")
    raw_value=$(normalize_config_value "${raw_value:-}")
    if [ -z "$raw_value" ]; then
        printf '%s\n' "$default_value"
    else
        printf '%s\n' "$raw_value"
    fi
}

mtime_for_path() {
    if stat -c %Y "$1" >/dev/null 2>&1; then
        stat -c %Y "$1"
    else
        stat -f %m "$1"
    fi
}

REGISTERED_WORKTREE_PATHS=()
REGISTERED_WORKTREE_BRANCHES=()
REGISTERED_WORKTREE_MTIMES=()

insert_registered_worktree() {
    local root="$1"
    local main_root="$2"
    local path="$3"
    local branch="$4"
    local head="$5"
    local detached="$6"
    local canonical_path mtime
    local candidate_count insert_at index previous_index

    verify_git_worktree_candidate "$main_root" "$root" "$path" "$head" "$branch" "$detached" || return 0
    canonical_path="$GIT_WORKTREE_VERIFIED_PATH"
    branch="$GIT_WORKTREE_VERIFIED_BRANCH_REF"
    mtime="$(mtime_for_path "$canonical_path" 2>/dev/null || true)"
    [ -n "$mtime" ] || return 0
    branch="${branch#refs/heads/}"
    [ -n "$branch" ] || branch="(detached)"

    candidate_count=${#REGISTERED_WORKTREE_PATHS[@]}
    insert_at=$candidate_count
    index=0
    while [ "$index" -lt "$candidate_count" ]; do
        if [ "$mtime" -gt "${REGISTERED_WORKTREE_MTIMES[$index]}" ]; then
            insert_at=$index
            break
        fi
        index=$((index + 1))
    done

    REGISTERED_WORKTREE_PATHS+=("")
    REGISTERED_WORKTREE_BRANCHES+=("")
    REGISTERED_WORKTREE_MTIMES+=("")
    index=$candidate_count
    while [ "$index" -gt "$insert_at" ]; do
        previous_index=$((index - 1))
        REGISTERED_WORKTREE_PATHS[$index]="${REGISTERED_WORKTREE_PATHS[$previous_index]}"
        REGISTERED_WORKTREE_BRANCHES[$index]="${REGISTERED_WORKTREE_BRANCHES[$previous_index]}"
        REGISTERED_WORKTREE_MTIMES[$index]="${REGISTERED_WORKTREE_MTIMES[$previous_index]}"
        index=$previous_index
    done
    REGISTERED_WORKTREE_PATHS[$insert_at]="$canonical_path"
    REGISTERED_WORKTREE_BRANCHES[$insert_at]="$branch"
    REGISTERED_WORKTREE_MTIMES[$insert_at]="$mtime"
}

load_registered_worktrees_by_mtime() {
    local root="$1"
    local main_root="$2"
    local index

    REGISTERED_WORKTREE_PATHS=()
    REGISTERED_WORKTREE_BRANCHES=()
    REGISTERED_WORKTREE_MTIMES=()
    load_git_worktrees "$main_root" || return 1
    index=0
    while [ "$index" -lt "${#GIT_WORKTREE_PATHS[@]}" ]; do
        insert_registered_worktree "$root" "$main_root" \
            "${GIT_WORKTREE_PATHS[$index]}" "${GIT_WORKTREE_BRANCH_REFS[$index]}" \
            "${GIT_WORKTREE_HEADS[$index]}" "${GIT_WORKTREE_DETACHED[$index]}"
        index=$((index + 1))
    done
}

resolve_path_from_root() {
    local repo_root="$1"
    local raw_path="$2"
    local combined parent_dir leaf_name canonical_parent CAPTURED_PATH

    if [[ "$raw_path" = /* ]]; then
        combined="$raw_path"
    else
        combined="$repo_root/$raw_path"
    fi

    capture_path dirname "$combined" || return 1
    parent_dir="$CAPTURED_PATH"
    capture_path basename "$combined" || return 1
    leaf_name="$CAPTURED_PATH"
    if [ -d "$parent_dir" ]; then
        capture_path print_canonical_dir "$parent_dir" || return 1
        canonical_parent="$CAPTURED_PATH"
        printf '%s/%s\n' "$canonical_parent" "$leaf_name"
    else
        printf '%s\n' "$combined"
    fi
}

resolve_main_repo_root() {
    local repo_root="$1"

    local inferred_root worktree_parent worktree_parent_name common_dir common_name main_root CAPTURED_PATH
    case "$repo_root" in
        */.worktrees/*)
            inferred_root="${repo_root%%/.worktrees/*}"
            if [ -d "$inferred_root/.specify" ]; then
                (cd "$inferred_root" && pwd -P)
                return 0
            fi
            ;;
        */worktrees/*)
            inferred_root="${repo_root%%/worktrees/*}"
            if [ -d "$inferred_root/.specify" ]; then
                (cd "$inferred_root" && pwd -P)
                return 0
            fi
            ;;
    esac

    capture_path dirname "$repo_root" || return 1
    worktree_parent="$CAPTURED_PATH"
    capture_path basename "$worktree_parent" || return 1
    worktree_parent_name="$CAPTURED_PATH"
    if [[ "$worktree_parent_name" == *-worktrees ]]; then
        capture_path dirname "$worktree_parent" || return 1
        inferred_root="$CAPTURED_PATH/${worktree_parent_name%-worktrees}"
        if [ -d "$inferred_root/.specify" ]; then
            (cd "$inferred_root" && pwd -P)
            return 0
        fi
    fi

    if capture_path git -C "$repo_root" rev-parse --git-common-dir 2>/dev/null; then
        common_dir="$CAPTURED_PATH"
    else
        common_dir=""
    fi

    if [ -z "$common_dir" ]; then
        printf '%s\n' "$repo_root"
        return 0
    fi

    if [[ "$common_dir" != /* ]]; then
        common_dir="$repo_root/$common_dir"
    fi

    capture_path basename "$common_dir" || return 1
    common_name="$CAPTURED_PATH"
    if [ "$common_name" = ".git" ]; then
        capture_path dirname "$common_dir" || return 1
        main_root="$CAPTURED_PATH"
        if [ -d "$main_root" ]; then
            (cd "$main_root" && pwd -P)
            return 0
        fi
    fi

    printf '%s\n' "$repo_root"
}

worktree_root_has_registered_worktrees() {
    local candidate="$1"
    local main_root="$2"

    [ -d "$candidate" ] || return 1
    load_registered_worktrees_by_mtime "$candidate" "$main_root" || return 2
    [ "${#REGISTERED_WORKTREE_PATHS[@]}" -gt 0 ]
}

resolve_worktree_root() {
    local repo_root="$1"
    local main_root main_root_name raw_root candidate
    local legacy_worktrees_candidate legacy_hidden_candidate CAPTURED_PATH
    capture_path resolve_main_repo_root "$repo_root" || return 1
    main_root="$CAPTURED_PATH"

    capture_path basename "$main_root" || return 1
    main_root_name="$CAPTURED_PATH"
    local default_root="../$main_root_name-worktrees"
    capture_path resolve_config_value "$main_root" "worktree_root" "$default_root" || return 1
    raw_root="$CAPTURED_PATH"

    capture_path resolve_path_from_root "$main_root" "$raw_root" || return 1
    candidate="$CAPTURED_PATH"
    if [ -d "$candidate" ]; then
        if [ "$raw_root" != "$default_root" ]; then
            (cd "$candidate" && pwd -P)
            return 0
        elif worktree_root_has_registered_worktrees "$candidate" "$main_root"; then
            (cd "$candidate" && pwd -P)
            return 0
        elif [ "$?" -eq 2 ]; then
            return 1
        fi
    fi

    if [ "$raw_root" != "$default_root" ]; then
        printf '%s\n' "$candidate"
        return 0
    fi

    capture_path resolve_path_from_root "$main_root" "worktrees" || return 1
    legacy_worktrees_candidate="$CAPTURED_PATH"
    capture_path resolve_path_from_root "$main_root" ".worktrees" || return 1
    legacy_hidden_candidate="$CAPTURED_PATH"
    for candidate in "$legacy_worktrees_candidate" "$legacy_hidden_candidate"; do
        if worktree_root_has_registered_worktrees "$candidate" "$main_root"; then
            (cd "$candidate" && pwd -P)
            return 0
        elif [ "$?" -eq 2 ]; then
            return 1
        fi
    done

    capture_path resolve_path_from_root "$main_root" "$default_root" || return 1
    printf '%s\n' "$CAPTURED_PATH"
}

MODE="prompt"
if [ "${1:-}" = "--path" ]; then
    MODE="path"
elif [ "${1:-}" = "--list" ]; then
    MODE="list"
elif [ $# -gt 0 ]; then
    echo "Usage: $0 [--path|--list]" >&2
    exit 1
fi

capture_path resolve_main_repo_root "$REPO_ROOT"
MAIN_REPO_ROOT="$CAPTURED_PATH"
if ! capture_path resolve_worktree_root "$REPO_ROOT"; then
    echo "Error: Failed to list Git worktrees." >&2
    exit 1
fi
WORKTREE_ROOT="$CAPTURED_PATH"
if [ ! -d "$WORKTREE_ROOT" ]; then
    echo "No Speckit worktree root found at: $WORKTREE_ROOT" >&2
    exit 1
fi

PATHS=()
BRANCHES=()
if ! load_registered_worktrees_by_mtime "$WORKTREE_ROOT" "$MAIN_REPO_ROOT"; then
    echo "Error: Failed to list Git worktrees." >&2
    exit 1
fi
if [ "${#REGISTERED_WORKTREE_PATHS[@]}" -eq 0 ]; then
    echo "No Speckit worktrees found under: $WORKTREE_ROOT" >&2
    exit 1
fi
PATHS=("${REGISTERED_WORKTREE_PATHS[@]}")
BRANCHES=("${REGISTERED_WORKTREE_BRANCHES[@]}")

if [ "${#PATHS[@]}" -eq 0 ]; then
    echo "No usable Speckit worktrees found under: $WORKTREE_ROOT" >&2
    exit 1
fi

if [ "$MODE" = "list" ]; then
    for i in "${!PATHS[@]}"; do
        index=$((i + 1))
        marker=""
        if [ "$i" -eq 0 ]; then
            marker=" [default]"
        fi
        printf '%d. %s%s\n' "$index" "${BRANCHES[$i]}" "$marker"
        printf '   %s\n' "${PATHS[$i]}"
    done
    exit 0
fi

if [ "$MODE" = "path" ] && ! [ -t 0 ]; then
    printf '%s\n' "${PATHS[0]}"
    exit 0
fi

for i in "${!PATHS[@]}"; do
    index=$((i + 1))
    marker=""
    if [ "$i" -eq 0 ]; then
        marker=" [default]"
    fi
    printf '%d. %s%s\n' "$index" "${BRANCHES[$i]}" "$marker" >&2
    printf '   %s\n' "${PATHS[$i]}" >&2
done

while true; do
    printf 'Select worktree [1] (q to cancel): ' >&2
    if ! IFS= read -r selection; then
        echo >&2
        exit 1
    fi

    selection=$(trim "$selection")
    if [ -z "$selection" ]; then
        selection=1
    fi

    case "$selection" in
        q|Q)
            exit 1
            ;;
    esac

    if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "${#PATHS[@]}" ]; then
        printf '%s\n' "${PATHS[$((selection - 1))]}"
        exit 0
    fi

    echo "Invalid selection. Enter 1-${#PATHS[@]} or q." >&2
done
