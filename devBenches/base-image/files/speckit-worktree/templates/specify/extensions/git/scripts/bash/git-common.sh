#!/usr/bin/env bash
# Git-specific common functions for the git extension.
# Extracted from scripts/bash/common.sh — contains Git-specific branch
# validation, repository detection, and worktree discovery logic.

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
