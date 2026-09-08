#!/usr/bin/env bash
# speckit-overlay-shape: 1
# Git-specific common functions for the git extension.
# Extracted from scripts/bash/common.sh — contains Git-specific branch
# validation, repository detection, and worktree discovery logic.

# ---------------------------------------------------------------------------
# Repository shape detection (single repository vs openRepoShape three-leg).
#
# load_repo_shape <root> sets, for its callers:
#   REPO_SHAPE        single | three-leg
#   PROJECT_ROOT      absolute path of the directory holding .specify/
#   SHAPE_SPEC_PATH   relative mount path of the spec leg (empty when single)
#   SHAPE_CODE_PATH   relative mount path of the code leg (empty when single)
#   SPEC_LEG          absolute path of the spec leg checkout (root when single)
#   CODE_LEG          absolute path of the code leg checkout (root when single)
#   SHAPE_FAMILY      1 when a family holder was detected, else 0
#
# The manifest is read line by line with parameter expansion only: no YAML
# library, no Python, no forks per line.
# ---------------------------------------------------------------------------

_shape_set_trimmed() {
    _SHAPE_TRIMMED="$1"
    _SHAPE_TRIMMED="${_SHAPE_TRIMMED#"${_SHAPE_TRIMMED%%[![:space:]]*}"}"
    _SHAPE_TRIMMED="${_SHAPE_TRIMMED%"${_SHAPE_TRIMMED##*[![:space:]]}"}"
}

_shape_set_scalar() {
    _shape_set_trimmed "$1"
    _SHAPE_SCALAR="$_SHAPE_TRIMMED"
    case "$_SHAPE_SCALAR" in
        \"*\")
            _SHAPE_SCALAR="${_SHAPE_SCALAR#\"}"
            _SHAPE_SCALAR="${_SHAPE_SCALAR%\"}"
            ;;
        \'*\')
            _SHAPE_SCALAR="${_SHAPE_SCALAR#\'}"
            _SHAPE_SCALAR="${_SHAPE_SCALAR%\'}"
            ;;
    esac
}

_shape_record_leg() {
    local role="$1"
    local path="$2"

    case "$role" in
        spec) _SHAPE_LEG_SPEC_PATH="${path:-spec}" ;;
        code) _SHAPE_LEG_CODE_PATH="${path:-code}" ;;
    esac
}

_shape_is_family_holder() {
    local family_manifest="$1"

    [ -f "$family_manifest" ] || return 1
    grep -Eq "^[[:space:]]*kind:[[:space:]]*[\"']?family-manifest[\"']?[[:space:]]*$" \
        "$family_manifest"
}

# shellcheck disable=SC2034  # the shape variables are consumed by the callers
load_repo_shape() {
    local root="$1"
    local manifest="$root/project.yaml"
    local family_manifest="$root/family.yaml"
    local raw content trimmed indent_ws indent key value rest
    local manifest_kind="" manifest_schema=""
    local in_legs=false key_col=-1
    local cur_role="" cur_path=""

    REPO_SHAPE="single"
    PROJECT_ROOT="$root"
    SHAPE_SPEC_PATH=""
    SHAPE_CODE_PATH=""
    SPEC_LEG="$root"
    CODE_LEG="$root"
    SHAPE_FAMILY=0
    _SHAPE_LEG_SPEC_PATH=""
    _SHAPE_LEG_CODE_PATH=""

    if [ ! -f "$manifest" ]; then
        if _shape_is_family_holder "$family_manifest"; then
            SHAPE_FAMILY=1
            echo "[specify] Family holder detected ($family_manifest); using the single-repository layout." >&2
        fi
        return 0
    fi

    while IFS= read -r raw || [ -n "$raw" ]; do
        content="${raw%%#*}"
        _shape_set_trimmed "$content"
        trimmed="$_SHAPE_TRIMMED"
        [ -n "$trimmed" ] || continue
        indent_ws="${content%%[![:space:]]*}"
        indent=${#indent_ws}

        if [ "$in_legs" = true ]; then
            if [ "$indent" -eq 0 ]; then
                _shape_record_leg "$cur_role" "$cur_path"
                cur_role=""
                cur_path=""
                in_legs=false
            elif [ "${trimmed:0:2}" = "- " ] || [ "$trimmed" = "-" ]; then
                _shape_record_leg "$cur_role" "$cur_path"
                cur_role=""
                cur_path=""
                key_col=$((indent + 2))
                _shape_set_trimmed "${trimmed#-}"
                rest="$_SHAPE_TRIMMED"
                key="${rest%%:*}"
                if [ -n "$rest" ] && [ "$key" != "$rest" ]; then
                    _shape_set_scalar "${rest#*:}"
                    value="$_SHAPE_SCALAR"
                    case "$key" in
                        role) cur_role="$value" ;;
                        path) cur_path="$value" ;;
                    esac
                fi
                continue
            elif [ "$indent" -eq "$key_col" ]; then
                key="${trimmed%%:*}"
                if [ "$key" != "$trimmed" ]; then
                    _shape_set_scalar "${trimmed#*:}"
                    value="$_SHAPE_SCALAR"
                    case "$key" in
                        role) cur_role="$value" ;;
                        path) cur_path="$value" ;;
                    esac
                fi
                continue
            else
                continue
            fi
        fi

        if [ "$indent" -eq 0 ]; then
            key="${trimmed%%:*}"
            [ "$key" != "$trimmed" ] || continue
            _shape_set_scalar "${trimmed#*:}"
            value="$_SHAPE_SCALAR"
            case "$key" in
                kind) manifest_kind="$value" ;;
                schema) manifest_schema="$value" ;;
                legs)
                    in_legs=true
                    key_col=-1
                    ;;
            esac
        fi
    done < "$manifest"
    _shape_record_leg "$cur_role" "$cur_path"

    if [ "$manifest_kind" = "project-manifest" ] \
        && [ "$manifest_schema" = "project-repo-schema" ] \
        && [ -n "$_SHAPE_LEG_SPEC_PATH" ] \
        && [ -n "$_SHAPE_LEG_CODE_PATH" ]; then
        REPO_SHAPE="three-leg"
        SHAPE_SPEC_PATH="$_SHAPE_LEG_SPEC_PATH"
        SHAPE_CODE_PATH="$_SHAPE_LEG_CODE_PATH"
        SPEC_LEG="$root/$SHAPE_SPEC_PATH"
        CODE_LEG="$root/$SHAPE_CODE_PATH"
    fi

    return 0
}

# True when the leg mount point holds an initialised Git checkout. A submodule
# that was never fetched is an empty directory, which is the case this guards.
shape_leg_is_checkout() {
    local leg="$1"

    [ -d "$leg" ] || return 1
    { [ -d "$leg/.git" ] || [ -f "$leg/.git" ]; } || return 1
    command -v git >/dev/null 2>&1 || return 1
    git -C "$leg" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Three-leg feature discovery.
#
# shape_load_features <worktree_root> enumerates the spec leg's linked
# worktrees and keeps the ones that sit at <worktree_root>/<feature>/<spec>/
# with a sibling <code>/ worktree. The feature directory is the parent of the
# spec worktree. Results are ordered newest first by feature directory mtime:
#
#   SHAPE_FEATURE_PATHS     feature directories
#   SHAPE_FEATURE_BRANCHES  branch names, same index
#   SHAPE_FEATURE_MTIMES    mtimes, same index
#
# Requires load_repo_shape to have run (SPEC_LEG / SHAPE_SPEC_PATH /
# SHAPE_CODE_PATH) and load_git_worktrees from this file.
# ---------------------------------------------------------------------------
SHAPE_FEATURE_PATHS=()
SHAPE_FEATURE_BRANCHES=()
SHAPE_FEATURE_MTIMES=()

_shape_mtime_for_path() {
    if stat -c %Y "$1" >/dev/null 2>&1; then
        stat -c %Y "$1"
    else
        stat -f %m "$1"
    fi
}

shape_insert_feature() {
    local path="$1"
    local branch="$2"
    local mtime="$3"
    local count insert_at index previous_index

    count=${#SHAPE_FEATURE_PATHS[@]}
    insert_at=$count
    index=0
    while [ "$index" -lt "$count" ]; do
        if [ "$mtime" -gt "${SHAPE_FEATURE_MTIMES[$index]}" ]; then
            insert_at=$index
            break
        fi
        index=$((index + 1))
    done

    SHAPE_FEATURE_PATHS+=("")
    SHAPE_FEATURE_BRANCHES+=("")
    SHAPE_FEATURE_MTIMES+=("")
    index=$count
    while [ "$index" -gt "$insert_at" ]; do
        previous_index=$((index - 1))
        SHAPE_FEATURE_PATHS[index]="${SHAPE_FEATURE_PATHS[previous_index]}"
        SHAPE_FEATURE_BRANCHES[index]="${SHAPE_FEATURE_BRANCHES[previous_index]}"
        SHAPE_FEATURE_MTIMES[index]="${SHAPE_FEATURE_MTIMES[previous_index]}"
        index=$previous_index
    done
    SHAPE_FEATURE_PATHS[insert_at]="$path"
    SHAPE_FEATURE_BRANCHES[insert_at]="$branch"
    SHAPE_FEATURE_MTIMES[insert_at]="$mtime"
}

shape_load_features() {
    local worktree_root="$1"
    local index path branch feature_dir code_dir mtime

    SHAPE_FEATURE_PATHS=()
    SHAPE_FEATURE_BRANCHES=()
    SHAPE_FEATURE_MTIMES=()
    load_git_worktrees "$SPEC_LEG" || return 1
    index=0
    while [ "$index" -lt "${#GIT_WORKTREE_PATHS[@]}" ]; do
        path="${GIT_WORKTREE_PATHS[$index]}"
        branch="${GIT_WORKTREE_BRANCH_REFS[$index]}"
        index=$((index + 1))
        [ -n "$branch" ] || continue
        [ -d "$path" ] || continue
        case "$path" in
            */"$SHAPE_SPEC_PATH") feature_dir="${path%/"$SHAPE_SPEC_PATH"}" ;;
            *) continue ;;
        esac
        feature_dir="${feature_dir%/}"
        case "$feature_dir" in
            "$worktree_root"/*) ;;
            *) continue ;;
        esac
        code_dir="$feature_dir/$SHAPE_CODE_PATH"
        [ -d "$code_dir" ] || continue
        mtime="$(_shape_mtime_for_path "$feature_dir" 2>/dev/null || true)"
        [ -n "$mtime" ] || continue
        shape_insert_feature "$feature_dir" "${branch#refs/heads/}" "$mtime"
    done
}

# Derive the per-feature paths of a three-leg feature directory:
#   SHAPE_SPEC_WORKTREE_PATH, SHAPE_CODE_WORKTREE_PATH,
#   SHAPE_FEATURE_DIR, SHAPE_FEATURE_DIR_RELATIVE (relative to the root).
# shellcheck disable=SC2034  # consumed by the scripts that source this file
shape_feature_paths_for() {
    local project_root="$1"
    local feature_dir="$2"
    local branch="$3"

    SHAPE_SPEC_WORKTREE_PATH="$feature_dir/$SHAPE_SPEC_PATH"
    SHAPE_CODE_WORKTREE_PATH="$feature_dir/$SHAPE_CODE_PATH"
    SHAPE_FEATURE_DIR="$SHAPE_SPEC_WORKTREE_PATH/specs/$branch"
    SHAPE_FEATURE_DIR_RELATIVE="$SHAPE_FEATURE_DIR"
    case "$SHAPE_FEATURE_DIR" in
        "$project_root"/*) SHAPE_FEATURE_DIR_RELATIVE="${SHAPE_FEATURE_DIR#"$project_root/"}" ;;
    esac
}

# Check if we have git available at the repo root
has_git() {
    local repo_root="${1:-$(pwd)}"
    { [ -d "$repo_root/.git" ] || [ -f "$repo_root/.git" ]; } && \
        command -v git >/dev/null 2>&1 && \
        git -C "$repo_root" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

# Validate that a branch name matches the expected feature branch pattern.
# Accepts sequential (###-* with >=3 digits) or timestamp (YYYYMMDD-HHMMSS-*) formats.
check_feature_branch() {
    local branch="$1"
    local has_git_repo="$2"
    local feature_segment="${branch##*/}"

    # For non-git repos, we can't enforce branch naming but still provide output
    if [[ "$has_git_repo" != "true" ]]; then
        echo "[specify] Warning: Git repository not detected; skipped branch validation" >&2
        return 0
    fi

    # Reject malformed timestamps (7-digit date, 8-digit date without trailing slug, or 7-digit with slug)
    if [[ "$feature_segment" =~ ^[0-9]{7}-[0-9]{6}- ]] || [[ "$feature_segment" =~ ^[0-9]{7,8}-[0-9]{6}$ ]]; then
        echo "ERROR: Not on a feature branch. Current branch: $branch" >&2
        echo "Feature branches should be named like: 001-feature-name, 20260319-143022-feature-name, or <namespace>/001-feature-name" >&2
        return 1
    fi

    # Accept sequential (>=3 digits followed by hyphen) or timestamp (YYYYMMDD-HHMMSS-*)
    if { [[ "$feature_segment" =~ ^[0-9]{3,}-.+ ]] && [[ ! "$feature_segment" =~ ^[0-9]{8}-[0-9]{6}- ]]; } \
        || [[ "$feature_segment" =~ ^[0-9]{8}-[0-9]{6}-.+ ]]; then
        return 0
    fi

    echo "ERROR: Not on a feature branch. Current branch: $branch" >&2
    echo "Feature branches should be named like: 001-feature-name, 20260319-143022-feature-name, or <namespace>/001-feature-name" >&2
    return 1
}

GIT_WORKTREE_PATHS=()
GIT_WORKTREE_BRANCH_REFS=()
GIT_WORKTREE_HEADS=()
GIT_WORKTREE_DETACHED=()

_git_worktree_reset_record() {
    _GIT_WORKTREE_RECORD_FIELDS=()
}

_git_worktree_decode_line_path() {
    local payload="$1"
    local remaining character escape octal decoded="" decoded_escape

    _GIT_WORKTREE_DECODED_PATH=""
    case "$payload" in
        \"*) ;;
        *) _GIT_WORKTREE_DECODED_PATH="$payload"; return 0 ;;
    esac
    [ "${#payload}" -ge 2 ] && [ "${payload: -1}" = '"' ] || return 1
    remaining="${payload#\"}"
    remaining="${remaining%\"}"

    while [ -n "$remaining" ]; do
        character="${remaining:0:1}"
        remaining="${remaining:1}"
        case "$character" in
            '"') return 1 ;;
            '\')
                [ -n "$remaining" ] || return 1
                escape="${remaining:0:1}"
                remaining="${remaining:1}"
                case "$escape" in
                    a) decoded_escape=$'\a' ;;
                    b) decoded_escape=$'\b' ;;
                    t) decoded_escape=$'\t' ;;
                    n) decoded_escape=$'\n' ;;
                    v) decoded_escape=$'\v' ;;
                    f) decoded_escape=$'\f' ;;
                    r) decoded_escape=$'\r' ;;
                    '"') decoded_escape='"' ;;
                    '\') decoded_escape='\' ;;
                    [0-3])
                        [ "${#remaining}" -ge 2 ] || return 1
                        octal="$escape${remaining:0:2}"
                        case "$octal" in [0-3][0-7][0-7]) ;; *) return 1 ;; esac
                        [ "$octal" != 000 ] || return 1
                        remaining="${remaining:2}"
                        printf -v decoded_escape '%b' "\\$octal" || return 1
                        ;;
                    *) return 1 ;;
                esac
                printf -v decoded '%s%s' "$decoded" "$decoded_escape" || return 1
                ;;
            *) printf -v decoded '%s%s' "$decoded" "$character" || return 1 ;;
        esac
    done
    _GIT_WORKTREE_DECODED_PATH="$decoded"
}

_git_worktree_finalize_record() {
    local mode="$1"
    local field index head_index=-1 head_count=0 state_count=0
    local path="" head="" branch_ref="" detached=false prunable=false

    [ "${#_GIT_WORKTREE_RECORD_FIELDS[@]}" -gt 0 ] || return 0
    case "${_GIT_WORKTREE_RECORD_FIELDS[0]}" in
        worktree\ *) path="${_GIT_WORKTREE_RECORD_FIELDS[0]#worktree }" ;;
        *) return 1 ;;
    esac
    if [ "$mode" = lines ]; then
        _git_worktree_decode_line_path "$path" || return 1
        path="$_GIT_WORKTREE_DECODED_PATH"
    fi

    index=1
    while [ "$index" -lt "${#_GIT_WORKTREE_RECORD_FIELDS[@]}" ]; do
        field="${_GIT_WORKTREE_RECORD_FIELDS[$index]}"
        if [[ "$field" =~ ^HEAD\ ([0-9a-f]{40}|[0-9a-f]{64})$ ]]; then
            head_count=$((head_count + 1))
            head_index=$index
            head="${field#HEAD }"
        fi
        index=$((index + 1))
    done
    [ "$head_count" -eq 1 ] || return 1

    if [ "$mode" = lines ]; then
        index=1
        while [ "$index" -lt "$head_index" ]; do
            path="$path"$'\n'"${_GIT_WORKTREE_RECORD_FIELDS[$index]}"
            index=$((index + 1))
        done
    elif [ "$head_index" -ne 1 ]; then
        return 1
    fi

    index=$((head_index + 1))
    while [ "$index" -lt "${#_GIT_WORKTREE_RECORD_FIELDS[@]}" ]; do
        field="${_GIT_WORKTREE_RECORD_FIELDS[$index]}"
        case "$field" in
            branch\ *)
                state_count=$((state_count + 1))
                branch_ref="${field#branch }"
                detached=false
                ;;
            detached)
                state_count=$((state_count + 1))
                branch_ref=""
                detached=true
                ;;
            prunable|prunable\ *) prunable=true ;;
            worktree\ *|HEAD\ *) return 1 ;;
        esac
        index=$((index + 1))
    done
    [ "$state_count" -eq 1 ] || return 1

    if [ "$prunable" = false ]; then
        _GIT_WORKTREE_STAGED_PATHS+=("$path")
        _GIT_WORKTREE_STAGED_BRANCH_REFS+=("$branch_ref")
        _GIT_WORKTREE_STAGED_HEADS+=("$head")
        _GIT_WORKTREE_STAGED_DETACHED+=("$detached")
    fi
}

_git_worktree_parse_z() {
    local input_file="$1"
    local field

    _git_worktree_reset_record
    while IFS= read -r -d '' field; do
        if [ -z "$field" ]; then
            _git_worktree_finalize_record z || return 1
            _git_worktree_reset_record
            continue
        fi
        _GIT_WORKTREE_RECORD_FIELDS+=("$field")
    done < "$input_file"
    [ "${#_GIT_WORKTREE_RECORD_FIELDS[@]}" -eq 0 ]
}

_git_worktree_parse_lines() {
    local input_file="$1"
    local line head_count=0 pending_blank=false

    _git_worktree_reset_record
    while IFS= read -r line || [ -n "$line" ]; do
        if [ -z "$line" ]; then
            if [ "$head_count" -eq 0 ]; then
                _GIT_WORKTREE_RECORD_FIELDS+=("")
                pending_blank=true
                continue
            fi
            _git_worktree_finalize_record lines || return 1
            _git_worktree_reset_record
            head_count=0
            pending_blank=false
            continue
        fi
        if [ "$pending_blank" = true ]; then
            case "$line" in worktree\ *) return 1 ;; esac
        fi
        pending_blank=false
        if [[ "$line" =~ ^HEAD\ ([0-9a-f]{40}|[0-9a-f]{64})$ ]]; then
            head_count=$((head_count + 1))
        fi
        _GIT_WORKTREE_RECORD_FIELDS+=("$line")
    done < "$input_file"
    [ "$pending_blank" = false ] && [ "${#_GIT_WORKTREE_RECORD_FIELDS[@]}" -eq 0 ]
}

_git_worktree_create_temp_file() {
    local attempt=0
    local candidate

    _GIT_WORKTREE_OUTPUT_FILE=""
    while [ "$attempt" -lt 100 ]; do
        candidate="${TMPDIR:-/tmp}/speckit-git-worktrees.$$.$RANDOM.$attempt"
        if (umask 077; set -o noclobber; : > "$candidate") 2>/dev/null; then
            _GIT_WORKTREE_OUTPUT_FILE="$candidate"
            return 0
        fi
        attempt=$((attempt + 1))
    done
    return 1
}

_git_worktree_remove_temp_file() {
    if command -v rm >/dev/null 2>&1; then
        rm -f "$1"
    elif [ -x /bin/rm ]; then
        /bin/rm -f "$1"
    else
        return 1
    fi
}

_git_worktree_query() {
    local repo_root="$1"
    local output_file
    shift

    _GIT_WORKTREE_QUERY_RESULT=""
    _git_worktree_create_temp_file || return 1
    output_file="$_GIT_WORKTREE_OUTPUT_FILE"
    if ! git -C "$repo_root" "$@" > "$output_file" 2>/dev/null \
        || ! printf '\0' >> "$output_file" \
        || ! IFS= read -r -d '' _GIT_WORKTREE_QUERY_RESULT < "$output_file"; then
        _git_worktree_remove_temp_file "$output_file" || true
        return 1
    fi
    _git_worktree_remove_temp_file "$output_file" || return 1
    _GIT_WORKTREE_QUERY_RESULT="${_GIT_WORKTREE_QUERY_RESULT%$'\n'}"
}

_git_worktree_canonicalize_dir() {
    local path="$1"

    _GIT_WORKTREE_CANONICAL_RESULT=""
    [ -d "$path" ] || return 1
    _GIT_WORKTREE_CANONICAL_RESULT=$(CDPATH="" cd -- "$path" && pwd -P && printf '.') || return 1
    _GIT_WORKTREE_CANONICAL_RESULT="${_GIT_WORKTREE_CANONICAL_RESULT%.}"
    _GIT_WORKTREE_CANONICAL_RESULT="${_GIT_WORKTREE_CANONICAL_RESULT%$'\n'}"
}

_git_worktree_resolve_git_dir() {
    local repo_root="$1"
    local query="$2"
    local raw_path

    _git_worktree_query "$repo_root" rev-parse "$query" || return 1
    raw_path="$_GIT_WORKTREE_QUERY_RESULT"
    case "$raw_path" in
        /*) ;;
        *) raw_path="$repo_root/$raw_path" ;;
    esac
    _git_worktree_canonicalize_dir "$raw_path" || return 1
    _GIT_WORKTREE_GIT_DIR_RESULT="$_GIT_WORKTREE_CANONICAL_RESULT"
}

verify_git_worktree_candidate() {
    local main_root="$1"
    local configured_root="$2"
    local candidate="$3"
    local parsed_head="$4"
    local parsed_branch_ref="$5"
    local parsed_detached="$6"
    local canonical_main canonical_root canonical_candidate canonical_top
    local main_common candidate_common candidate_git_dir actual_head actual_branch_ref

    GIT_WORKTREE_VERIFIED_PATH=""
    GIT_WORKTREE_VERIFIED_HEAD=""
    GIT_WORKTREE_VERIFIED_BRANCH_REF=""
    GIT_WORKTREE_VERIFIED_DETACHED=""

    _git_worktree_canonicalize_dir "$main_root" || return 1
    canonical_main="$_GIT_WORKTREE_CANONICAL_RESULT"
    _git_worktree_canonicalize_dir "$configured_root" || return 1
    canonical_root="$_GIT_WORKTREE_CANONICAL_RESULT"
    _git_worktree_canonicalize_dir "$candidate" || return 1
    canonical_candidate="$_GIT_WORKTREE_CANONICAL_RESULT"
    [ "$canonical_candidate" != "$canonical_main" ] || return 1
    [ "$canonical_candidate" != "$canonical_root" ] || return 1
    if [ "$canonical_root" = / ]; then
        case "$canonical_candidate" in /*) ;; *) return 1 ;; esac
    else
        case "$canonical_candidate" in "$canonical_root"/*) ;; *) return 1 ;; esac
    fi

    _git_worktree_query "$canonical_candidate" rev-parse --show-toplevel || return 1
    _git_worktree_canonicalize_dir "$_GIT_WORKTREE_QUERY_RESULT" || return 1
    canonical_top="$_GIT_WORKTREE_CANONICAL_RESULT"
    [ "$canonical_top" = "$canonical_candidate" ] || return 1

    _git_worktree_resolve_git_dir "$canonical_main" --git-common-dir || return 1
    main_common="$_GIT_WORKTREE_GIT_DIR_RESULT"
    _git_worktree_resolve_git_dir "$canonical_candidate" --git-common-dir || return 1
    candidate_common="$_GIT_WORKTREE_GIT_DIR_RESULT"
    [ "$candidate_common" = "$main_common" ] || return 1
    _git_worktree_resolve_git_dir "$canonical_candidate" --git-dir || return 1
    candidate_git_dir="$_GIT_WORKTREE_GIT_DIR_RESULT"
    [ "$candidate_git_dir" != "$main_common" ] || return 1
    case "$candidate_git_dir" in "$main_common"/worktrees/*) ;; *) return 1 ;; esac

    _git_worktree_query "$canonical_candidate" rev-parse --verify HEAD || return 1
    actual_head="$_GIT_WORKTREE_QUERY_RESULT"
    [ "$actual_head" = "$parsed_head" ] || return 1

    if [ "$parsed_detached" = true ]; then
        if _git_worktree_query "$canonical_candidate" symbolic-ref -q HEAD; then
            return 1
        fi
        actual_branch_ref=""
    else
        [ -n "$parsed_branch_ref" ] || return 1
        _git_worktree_query "$canonical_candidate" symbolic-ref -q HEAD || return 1
        actual_branch_ref="$_GIT_WORKTREE_QUERY_RESULT"
        [ "$actual_branch_ref" = "$parsed_branch_ref" ] || return 1
    fi

    GIT_WORKTREE_VERIFIED_PATH="$canonical_candidate"
    GIT_WORKTREE_VERIFIED_HEAD="$actual_head"
    GIT_WORKTREE_VERIFIED_BRANCH_REF="$actual_branch_ref"
    GIT_WORKTREE_VERIFIED_DETACHED="$parsed_detached"
}

load_git_worktrees() {
    local repo_root="$1"
    local output_file

    GIT_WORKTREE_PATHS=()
    GIT_WORKTREE_BRANCH_REFS=()
    GIT_WORKTREE_HEADS=()
    GIT_WORKTREE_DETACHED=()
    _GIT_WORKTREE_STAGED_PATHS=()
    _GIT_WORKTREE_STAGED_BRANCH_REFS=()
    _GIT_WORKTREE_STAGED_HEADS=()
    _GIT_WORKTREE_STAGED_DETACHED=()
    _git_worktree_create_temp_file || return 1
    output_file="$_GIT_WORKTREE_OUTPUT_FILE"

    if git -C "$repo_root" worktree list --porcelain -z > "$output_file" 2>/dev/null; then
        if _git_worktree_parse_z "$output_file"; then
            GIT_WORKTREE_PATHS=("${_GIT_WORKTREE_STAGED_PATHS[@]}")
            GIT_WORKTREE_BRANCH_REFS=("${_GIT_WORKTREE_STAGED_BRANCH_REFS[@]}")
            GIT_WORKTREE_HEADS=("${_GIT_WORKTREE_STAGED_HEADS[@]}")
            GIT_WORKTREE_DETACHED=("${_GIT_WORKTREE_STAGED_DETACHED[@]}")
            _git_worktree_remove_temp_file "$output_file" || return 1
            return 0
        fi
        _git_worktree_remove_temp_file "$output_file" || return 1
        return 1
    fi
    if git -C "$repo_root" worktree list --porcelain > "$output_file" 2>/dev/null; then
        if _git_worktree_parse_lines "$output_file"; then
            GIT_WORKTREE_PATHS=("${_GIT_WORKTREE_STAGED_PATHS[@]}")
            GIT_WORKTREE_BRANCH_REFS=("${_GIT_WORKTREE_STAGED_BRANCH_REFS[@]}")
            GIT_WORKTREE_HEADS=("${_GIT_WORKTREE_STAGED_HEADS[@]}")
            GIT_WORKTREE_DETACHED=("${_GIT_WORKTREE_STAGED_DETACHED[@]}")
            _git_worktree_remove_temp_file "$output_file" || return 1
            return 0
        fi
        _git_worktree_remove_temp_file "$output_file" || return 1
        return 1
    fi

    _git_worktree_remove_temp_file "$output_file" || return 1
    return 1
}
