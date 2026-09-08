#!/usr/bin/env bash
# Git extension: auto-commit.sh
# Automatically commit changes after a Spec Kit command completes.
# Checks per-command config keys in git-config.yml before committing.
#
# Usage: auto-commit.sh <event_name>
#   e.g.: auto-commit.sh after_specify

set -e
# speckit-overlay-shape: 1

EVENT_NAME="${1:-}"
if [ -z "$EVENT_NAME" ]; then
    echo "Usage: $0 <event_name>" >&2
    exit 1
fi

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_find_project_root() {
    local dir="$1"
    while [ "$dir" != "/" ]; do
        if [ -d "$dir/.specify" ] || [ -d "$dir/.git" ]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

REPO_ROOT=$(_find_project_root "$SCRIPT_DIR") || REPO_ROOT="$(pwd)"
cd "$REPO_ROOT"

# Resolve the repository shape. In a three-leg project the commits belong in
# the feature's two leg worktrees, never in the assembly root.
REPO_SHAPE=single
if [ -f "$SCRIPT_DIR/git-common.sh" ]; then
    # shellcheck source=/dev/null
    . "$SCRIPT_DIR/git-common.sh"
    load_repo_shape "$REPO_ROOT"
fi

# Check if git is available
if ! command -v git >/dev/null 2>&1; then
    echo "[specify] Warning: Git not found; skipped auto-commit" >&2
    exit 0
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "[specify] Warning: Not a Git repository; skipped auto-commit" >&2
    exit 0
fi

# Read per-command config from git-config.yml
_config_file="$REPO_ROOT/.specify/extensions/git/git-config.yml"
_enabled=false
_commit_msg=""

_normalize_yaml_scalar() {
    local value="$1"

    value="${value%%[[:space:]]#*}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
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
    printf '%s\n' "$value"
}

if [ -f "$_config_file" ]; then
    # Parse the auto_commit section for this event.
    # Look for auto_commit.<event_name>.enabled and .message
    # Also check auto_commit.default as fallback.
    _in_auto_commit=false
    _in_event=false
    _default_enabled=false
    _event_seen=false
    _event_indent=0

    while IFS= read -r _line || [ -n "$_line" ]; do
        _trimmed="${_line#"${_line%%[![:space:]]*}"}"
        [ -n "$_trimmed" ] || continue
        case "$_trimmed" in
            \#*) continue ;;
        esac

        _indent="${_line%%[![:space:]]*}"
        _indent_len=${#_indent}
        _key="${_trimmed%%:*}"
        [ "$_trimmed" != "$_key" ] || continue
        _value="${_trimmed#*:}"
        _value="${_value#"${_value%%[![:space:]]*}"}"
        _value="$(_normalize_yaml_scalar "$_value")"

        # Detect auto_commit: section.
        if [ "$_indent_len" -eq 0 ] && [ "$_key" = "auto_commit" ]; then
            _in_auto_commit=true
            _in_event=false
            continue
        fi

        # Exit auto_commit section on any later top-level YAML key.
        if $_in_auto_commit && [ "$_indent_len" -eq 0 ]; then
            break
        fi

        if $_in_auto_commit; then
            if $_in_event && [ "$_indent_len" -le "$_event_indent" ] && [ "$_key" != "$EVENT_NAME" ]; then
                _in_event=false
            fi

            # Check default key.
            if [ "$_key" = "default" ]; then
                _val=$(printf '%s\n' "$_value" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
                [ "$_val" = "true" ] && _default_enabled=true
            fi

            # Detect our event subsection using a literal key comparison.
            if [ "$_key" = "$EVENT_NAME" ]; then
                _in_event=true
                _event_seen=true
                _event_indent=$_indent_len
                continue
            fi

            # Inside our event subsection.
            if $_in_event; then
                if [ "$_key" = "enabled" ]; then
                    _val=$(printf '%s\n' "$_value" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
                    [ "$_val" = "true" ] && _enabled=true
                    [ "$_val" = "false" ] && _enabled=false
                fi
                if [ "$_key" = "message" ]; then
                    _commit_msg="$_value"
                fi
            fi
        fi
    done < "$_config_file"

    # If event-specific key not found, use default
    if [ "$_enabled" = "false" ] && [ "$_default_enabled" = "true" ]; then
        # Only use default if the event wasn't explicitly set to false.
        if ! $_event_seen; then
            _enabled=true
        fi
    fi
else
    # No config file — auto-commit disabled by default
    exit 0
fi

if [ "$_enabled" != "true" ]; then
    exit 0
fi

# Read one scalar from git-config.yml (used for worktree_root in three-leg).
_shape_config_scalar() {
    local key="$1"
    local default_value="$2"
    local line value

    if [ ! -f "$_config_file" ]; then
        printf '%s\n' "$default_value"
        return 0
    fi
    line=$(grep -E "^[[:space:]]*$key:[[:space:]]*" "$_config_file" | tail -n 1 || true)
    if [ -z "$line" ]; then
        printf '%s\n' "$default_value"
        return 0
    fi
    value="${line#*:}"
    value=$(_normalize_yaml_scalar "$value")
    if [ -z "$value" ]; then
        value="$default_value"
    fi
    printf '%s\n' "$value"
}

# Mirror core read_feature_json_feature_directory: jq -> python3 -> grep/sed.
_shape_feature_directory_from_json() {
    local feature_json="$REPO_ROOT/.specify/feature.json"
    local value=""

    [ -f "$feature_json" ] || return 1
    if command -v jq >/dev/null 2>&1; then
        value=$(jq -r '.feature_directory // empty' "$feature_json" 2>/dev/null) || value=""
    fi
    if [ -z "$value" ] && command -v python3 >/dev/null 2>&1; then
        value=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); v=d.get('feature_directory'); print(v if v else '')" \
            "$feature_json" 2>/dev/null) || value=""
    fi
    if [ -z "$value" ]; then
        value=$( { grep -E '"feature_directory"[[:space:]]*:' "$feature_json" 2>/dev/null || true; } \
            | head -n 1 \
            | sed -E 's/^[^:]*:[[:space:]]*"([^"]*)".*$/\1/' )
    fi
    [ -n "$value" ] || return 1
    printf '%s\n' "$value"
}

# Absolute path of the selected feature directory (worktrees/<NNN-feature>).
_shape_resolve_feature_dir() {
    local feature_directory feature_dir worktree_root

    if [ -n "${SPECIFY_FEATURE:-}" ]; then
        worktree_root=$(_shape_config_scalar "worktree_root" "worktrees")
        case "$worktree_root" in
            /*) printf '%s/%s\n' "$worktree_root" "$SPECIFY_FEATURE" ;;
            *) printf '%s/%s/%s\n' "$REPO_ROOT" "$worktree_root" "$SPECIFY_FEATURE" ;;
        esac
        return 0
    fi

    feature_directory=$(_shape_feature_directory_from_json) || return 1
    case "$feature_directory" in
        /*) ;;
        *) feature_directory="$REPO_ROOT/$feature_directory" ;;
    esac
    feature_dir="${feature_directory%/*}"
    case "$feature_dir" in
        */specs) feature_dir="${feature_dir%/specs}" ;;
        *) return 1 ;;
    esac
    case "$feature_dir" in
        */"$SHAPE_SPEC_PATH") feature_dir="${feature_dir%/"$SHAPE_SPEC_PATH"}" ;;
        *) return 1 ;;
    esac
    printf '%s\n' "$feature_dir"
}

_commit_in_tree() {
    local tree="$1"
    local label="$2"
    local out

    if [ ! -d "$tree" ]; then
        echo "[specify] Warning: $label worktree not found; skipped: $tree" >&2
        return 0
    fi
    if git -C "$tree" diff --quiet HEAD 2>/dev/null \
        && git -C "$tree" diff --cached --quiet 2>/dev/null \
        && [ -z "$(git -C "$tree" ls-files --others --exclude-standard 2>/dev/null)" ]; then
        echo "[specify] No changes to commit in the $label worktree after $EVENT_NAME" >&2
        return 0
    fi
    out=$(git -C "$tree" add . 2>&1) || { echo "[specify] Error: git add failed in the $label worktree: $out" >&2; return 1; }
    out=$(git -C "$tree" commit -q -m "$_commit_msg" 2>&1) || { echo "[specify] Error: git commit failed in the $label worktree: $out" >&2; return 1; }
    echo "✓ Changes committed ${_phase} ${_command_name} in the $label worktree" >&2
}

if [ "$REPO_SHAPE" = "three-leg" ]; then
    # Derive a human-readable command name from the event
    # e.g., after_specify -> specify, before_plan -> plan
    _command_name=$(echo "$EVENT_NAME" | sed 's/^after_//' | sed 's/^before_//')
    _phase=$(echo "$EVENT_NAME" | grep -q '^before_' && echo 'before' || echo 'after')
    if [ -z "$_commit_msg" ]; then
        _commit_msg="[Spec Kit] Auto-commit ${_phase} ${_command_name}"
    fi

    if ! _feature_dir=$(_shape_resolve_feature_dir); then
        echo "[specify] No Speckit feature is selected in this three-leg project; skipped auto-commit." >&2
        echo "[specify] Export SPECIFY_FEATURE (and SPECIFY_FEATURE_DIRECTORY) or run /speckit.specify first." >&2
        exit 0
    fi

    _shape_status=0
    _commit_in_tree "$_feature_dir/$SHAPE_SPEC_PATH" spec || _shape_status=1
    _commit_in_tree "$_feature_dir/$SHAPE_CODE_PATH" code || _shape_status=1
    exit "$_shape_status"
fi

# Check if there are changes to commit
if git diff --quiet HEAD 2>/dev/null && git diff --cached --quiet 2>/dev/null && [ -z "$(git ls-files --others --exclude-standard 2>/dev/null)" ]; then
    echo "[specify] No changes to commit after $EVENT_NAME" >&2
    exit 0
fi

# Derive a human-readable command name from the event
# e.g., after_specify -> specify, before_plan -> plan
_command_name=$(echo "$EVENT_NAME" | sed 's/^after_//' | sed 's/^before_//')
_phase=$(echo "$EVENT_NAME" | grep -q '^before_' && echo 'before' || echo 'after')

# Use custom message if configured, otherwise default
if [ -z "$_commit_msg" ]; then
    _commit_msg="[Spec Kit] Auto-commit ${_phase} ${_command_name}"
fi

# Stage and commit
_git_out=$(git add . 2>&1) || { echo "[specify] Error: git add failed: $_git_out" >&2; exit 1; }
_git_out=$(git commit -q -m "$_commit_msg" 2>&1) || { echo "[specify] Error: git commit failed: $_git_out" >&2; exit 1; }

echo "✓ Changes committed ${_phase} ${_command_name}" >&2
