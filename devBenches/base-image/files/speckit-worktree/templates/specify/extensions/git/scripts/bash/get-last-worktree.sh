#!/usr/bin/env bash

set -euo pipefail
# speckit-overlay-shape: 1

JSON_MODE=false
ENV_MODE=false
case "${1:-}" in
    --json) JSON_MODE=true ;;
    --env) ENV_MODE=true ;;
esac

# Shape-dependent extras filled in before emit_result runs.
EMIT_REPO_SHAPE=single
EMIT_PROJECT_ROOT=""
EMIT_SPEC_WORKTREE_PATH=""
EMIT_CODE_WORKTREE_PATH=""
EMIT_FEATURE_DIR=""
EMIT_FEATURE_DIR_RELATIVE=""

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
capture_path print_canonical_dir "$SCRIPT_DIR/../../../../.."
SCRIPT_REPO_ROOT="$CAPTURED_PATH"
if [ ! -f "$SCRIPT_DIR/git-common.sh" ]; then
    echo "Error: Could not locate git-common.sh next to get-last-worktree.sh." >&2
    exit 1
fi
source "$SCRIPT_DIR/git-common.sh"

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

read_state_worktree_path() {
    local state_file="$1"
    local output_file

    WORKTREE_PATH=""
    _git_worktree_create_temp_file || return 1
    output_file="$_GIT_WORKTREE_OUTPUT_FILE"
    if command -v jq >/dev/null 2>&1; then
        if ! jq -jr 'if type == "object" and ((.WORKTREE_PATH // "") | type) == "string" then (.WORKTREE_PATH // "") else error("invalid state") end' \
            "$state_file" > "$output_file" 2>/dev/null; then
            _git_worktree_remove_temp_file "$output_file" || true
            return 1
        fi
    elif command -v python3 >/dev/null 2>&1; then
        if ! python3 - "$state_file" > "$output_file" 2>/dev/null <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as stream:
    payload = json.load(stream)
path = payload.get("WORKTREE_PATH", "") if isinstance(payload, dict) else None
if not isinstance(path, str):
    raise ValueError("invalid state")
sys.stdout.buffer.write(path.encode("utf-8"))
PY
        then
            _git_worktree_remove_temp_file "$output_file" || true
            return 1
        fi
    else
        _git_worktree_remove_temp_file "$output_file" || return 1
        return 1
    fi
    if ! printf '\0' >> "$output_file" \
        || ! IFS= read -r -d '' WORKTREE_PATH < "$output_file"; then
        _git_worktree_remove_temp_file "$output_file" || true
        WORKTREE_PATH=""
        return 1
    fi
    _git_worktree_remove_temp_file "$output_file" || return 1
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

canonicalize_if_dir() {
    local candidate="$1"
    if [ -d "$candidate" ]; then
        (cd "$candidate" && pwd -P)
    else
        printf '%s\n' "$candidate"
    fi
}

emit_result() {
    local branch_name="$1"
    local worktree_path="$2"
    local base_branch="$3"
    local repo_root="$4"
    local source="$5"

    if $ENV_MODE; then
        printf 'REPO_SHAPE=%q\n' "$EMIT_REPO_SHAPE"
        printf 'PROJECT_ROOT=%q\n' "${EMIT_PROJECT_ROOT:-$repo_root}"
        printf 'REPO_ROOT=%q\n' "$repo_root"
        printf 'BRANCH_NAME=%q\n' "$branch_name"
        printf 'BASE_BRANCH=%q\n' "$base_branch"
        printf 'WORKTREE_PATH=%q\n' "$worktree_path"
        printf 'SOURCE=%q\n' "$source"
        if [ "$EMIT_REPO_SHAPE" = three-leg ]; then
            printf 'SPEC_WORKTREE_PATH=%q\n' "$EMIT_SPEC_WORKTREE_PATH"
            printf 'CODE_WORKTREE_PATH=%q\n' "$EMIT_CODE_WORKTREE_PATH"
            printf 'FEATURE_DIR=%q\n' "$EMIT_FEATURE_DIR"
            printf 'SPECIFY_FEATURE=%q\n' "$branch_name"
            printf 'SPECIFY_FEATURE_DIRECTORY=%q\n' "$EMIT_FEATURE_DIR_RELATIVE"
        fi
        return 0
    fi

    if $JSON_MODE; then
        if command -v jq >/dev/null 2>&1; then
            jq -cn \
                --arg branch_name "$branch_name" \
                --arg worktree_path "$worktree_path" \
                --arg base_branch "$base_branch" \
                --arg repo_root "$repo_root" \
                --arg source "$source" \
                --arg repo_shape "$EMIT_REPO_SHAPE" \
                --arg project_root "${EMIT_PROJECT_ROOT:-$repo_root}" \
                --arg spec_worktree_path "$EMIT_SPEC_WORKTREE_PATH" \
                --arg code_worktree_path "$EMIT_CODE_WORKTREE_PATH" \
                --arg feature_dir "$EMIT_FEATURE_DIR" \
                '({BRANCH_NAME:$branch_name,WORKTREE_PATH:$worktree_path,BASE_BRANCH:$base_branch,REPO_ROOT:$repo_root,SOURCE:$source,REPO_SHAPE:$repo_shape}
                  + (if $repo_shape == "three-leg" then {PROJECT_ROOT:$project_root,SPEC_WORKTREE_PATH:$spec_worktree_path,CODE_WORKTREE_PATH:$code_worktree_path,FEATURE_DIR:$feature_dir} else {} end))'
        elif command -v python3 >/dev/null 2>&1; then
            python3 - "$branch_name" "$worktree_path" "$base_branch" "$repo_root" "$source" \
                "$EMIT_REPO_SHAPE" "${EMIT_PROJECT_ROOT:-$repo_root}" "$EMIT_SPEC_WORKTREE_PATH" \
                "$EMIT_CODE_WORKTREE_PATH" "$EMIT_FEATURE_DIR" <<'PY'
import json
import sys

payload = {
    "BRANCH_NAME": sys.argv[1],
    "WORKTREE_PATH": sys.argv[2],
    "BASE_BRANCH": sys.argv[3],
    "REPO_ROOT": sys.argv[4],
    "SOURCE": sys.argv[5],
    "REPO_SHAPE": sys.argv[6],
}
if sys.argv[6] == "three-leg":
    payload["PROJECT_ROOT"] = sys.argv[7]
    payload["SPEC_WORKTREE_PATH"] = sys.argv[8]
    payload["CODE_WORKTREE_PATH"] = sys.argv[9]
    payload["FEATURE_DIR"] = sys.argv[10]
print(json.dumps(payload))
PY
        else
            echo "Error: JSON output requires jq or python3." >&2
            return 1
        fi
    else
        printf '%s\n' "$worktree_path"
    fi
}

shape_fill_emit_fields() {
    local project_root="$1"
    local feature_dir="$2"
    local branch="$3"

    shape_feature_paths_for "$project_root" "$feature_dir" "$branch"
    EMIT_REPO_SHAPE=three-leg
    EMIT_PROJECT_ROOT="$project_root"
    EMIT_SPEC_WORKTREE_PATH="$SHAPE_SPEC_WORKTREE_PATH"
    EMIT_CODE_WORKTREE_PATH="$SHAPE_CODE_WORKTREE_PATH"
    EMIT_FEATURE_DIR="${SHAPE_FEATURE_DIR}"
    EMIT_FEATURE_DIR_RELATIVE="$SHAPE_FEATURE_DIR_RELATIVE"
}

if capture_path git rev-parse --show-toplevel 2>/dev/null; then
    REPO_ROOT="$CAPTURED_PATH"
else
    REPO_ROOT=""
fi
if [ -z "$REPO_ROOT" ]; then
    REPO_ROOT="$SCRIPT_REPO_ROOT"
fi
if [ -z "$REPO_ROOT" ] || [ ! -d "$REPO_ROOT/.specify" ]; then
    echo "Error: not inside a Git repository or Speckit checkout." >&2
    exit 1
fi

capture_path resolve_main_repo_root "$REPO_ROOT"
MAIN_REPO_ROOT="$CAPTURED_PATH"
if capture_path git rev-parse --git-common-dir 2>/dev/null; then
    COMMON_DIR="$CAPTURED_PATH"
else
    COMMON_DIR=""
fi
if [ -z "$COMMON_DIR" ]; then
    COMMON_DIR="$MAIN_REPO_ROOT/.git"
fi
if [[ "$COMMON_DIR" != /* ]]; then
    COMMON_DIR="$REPO_ROOT/$COMMON_DIR"
fi

STATE_FILE="$COMMON_DIR/speckit-last-worktree.json"
BASE_BRANCH=$(resolve_config_value "$REPO_ROOT" "base_branch" "main")

load_repo_shape "$MAIN_REPO_ROOT"
if [ "$REPO_SHAPE" = "three-leg" ]; then
    if ! shape_leg_is_checkout "$SPEC_LEG"; then
        echo "Error: the spec leg '$SHAPE_SPEC_PATH' is not an initialised Git checkout at '$SPEC_LEG'." >&2
        echo "Run 'git submodule update --init' (or 'make bootstrap') in the project root first." >&2
        exit 1
    fi
    SHAPE_WORKTREE_ROOT_RAW=$(resolve_config_value "$MAIN_REPO_ROOT" "worktree_root" "worktrees")
    if ! capture_path resolve_path_from_root "$MAIN_REPO_ROOT" "$SHAPE_WORKTREE_ROOT_RAW"; then
        echo "Error: Failed to resolve the Speckit worktree root." >&2
        exit 1
    fi
    SHAPE_WORKTREE_ROOT="$CAPTURED_PATH"
    if ! shape_load_features "$SHAPE_WORKTREE_ROOT"; then
        echo "Error: Failed to list Git worktrees." >&2
        exit 1
    fi

    SHAPE_SELECTED=-1
    SHAPE_SOURCE=worktree_root_fallback
    if [ ! -L "$STATE_FILE" ] && [ -f "$STATE_FILE" ]; then
        WORKTREE_PATH=""
        if read_state_worktree_path "$STATE_FILE" && [ -n "$WORKTREE_PATH" ]; then
            SHAPE_INDEX=0
            while [ "$SHAPE_INDEX" -lt "${#SHAPE_FEATURE_PATHS[@]}" ]; do
                if [ "$WORKTREE_PATH" = "${SHAPE_FEATURE_PATHS[$SHAPE_INDEX]}" ]; then
                    SHAPE_SELECTED=$SHAPE_INDEX
                    SHAPE_SOURCE=state_file
                    break
                fi
                SHAPE_INDEX=$((SHAPE_INDEX + 1))
            done
        fi
    fi
    if [ "$SHAPE_SELECTED" -lt 0 ] && [ "${#SHAPE_FEATURE_PATHS[@]}" -gt 0 ]; then
        SHAPE_SELECTED=0
    fi
    if [ "$SHAPE_SELECTED" -lt 0 ]; then
        echo "Error: no Speckit worktree handoff has been recorded yet." >&2
        exit 1
    fi

    SHAPE_SELECTED_DIR="${SHAPE_FEATURE_PATHS[$SHAPE_SELECTED]}"
    SHAPE_SELECTED_BRANCH="${SHAPE_FEATURE_BRANCHES[$SHAPE_SELECTED]}"
    shape_fill_emit_fields "$MAIN_REPO_ROOT" "$SHAPE_SELECTED_DIR" "$SHAPE_SELECTED_BRANCH"
    emit_result "$SHAPE_SELECTED_BRANCH" "$SHAPE_SELECTED_DIR" "$BASE_BRANCH" \
        "$MAIN_REPO_ROOT" "$SHAPE_SOURCE"
    exit 0
fi

if ! capture_path resolve_worktree_root "$REPO_ROOT"; then
    echo "Error: Failed to list Git worktrees." >&2
    exit 1
fi
WORKTREE_ROOT="$CAPTURED_PATH"
if [ -d "$WORKTREE_ROOT" ]; then
    if ! load_registered_worktrees_by_mtime "$WORKTREE_ROOT" "$MAIN_REPO_ROOT"; then
        echo "Error: Failed to list Git worktrees." >&2
        exit 1
    fi
fi

if [ ! -L "$STATE_FILE" ] && [ -f "$STATE_FILE" ]; then
    WORKTREE_PATH=""
    if read_state_worktree_path "$STATE_FILE" && [ -n "$WORKTREE_PATH" ]; then
        STATE_INDEX=0
        while [ "$STATE_INDEX" -lt "${#REGISTERED_WORKTREE_PATHS[@]}" ]; do
            if [ "$WORKTREE_PATH" = "${REGISTERED_WORKTREE_PATHS[$STATE_INDEX]}" ]; then
                emit_result "${REGISTERED_WORKTREE_BRANCHES[$STATE_INDEX]}" \
                    "${REGISTERED_WORKTREE_PATHS[$STATE_INDEX]}" "$BASE_BRANCH" "$REPO_ROOT" "state_file"
                exit 0
            fi
            STATE_INDEX=$((STATE_INDEX + 1))
        done
    fi
fi

if [ "${#REGISTERED_WORKTREE_PATHS[@]}" -gt 0 ]; then
    LATEST_BRANCH=${REGISTERED_WORKTREE_BRANCHES[0]}
    LATEST_WORKTREE=${REGISTERED_WORKTREE_PATHS[0]}
    emit_result "$LATEST_BRANCH" "$LATEST_WORKTREE" "$BASE_BRANCH" "$REPO_ROOT" "worktree_root_fallback"
    exit 0
fi

echo "Error: no Speckit worktree handoff has been recorded yet." >&2
exit 1
