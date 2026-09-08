# speckit-overlay-shape: 1
# Source this file from bash or zsh to enable Speckit worktree helpers.
#
# NOTE: In devBench containers, prefer the globally sourced ct helpers from
# /usr/local/share/ct/ct-functions.zsh.
# This file is kept as a per-repo fallback for environments without the
# container-level helpers.

_speckit_worktree_capture_path() {
  local frame='__SPECKIT_PATH_CAPTURE_FRAME_7D3A9C__'
  local captured capture_status producer_status

  _SPECKIT_WORKTREE_CAPTURED_PATH=""
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
  _SPECKIT_WORKTREE_CAPTURED_PATH="$captured"
}

_speckit_worktree_print_repo_root() {
  local script_path script_dir

  if [ -n "${ZSH_VERSION:-}" ]; then
    CDPATH="" cd "${${(%):-%x}:A:h}/../.." 2>/dev/null && pwd
  else
    script_path="${BASH_SOURCE[0]:-$0}"
    script_dir="${script_path%/*}"
    [ "$script_dir" != "$script_path" ] || script_dir=.
    CDPATH="" cd "$script_dir/../.." 2>/dev/null && pwd
  fi
}

# Auto-detect repo root from this script's own location so the file is
# relocatable and does not embed a host-specific absolute path.
_speckit_worktree_capture_path _speckit_worktree_print_repo_root || return $?
SPECKIT_WORKTREE_REPO_ROOT="$_SPECKIT_WORKTREE_CAPTURED_PATH"
SPECKIT_WORKTREE_LAST_WORKTREE_SCRIPT="$SPECKIT_WORKTREE_REPO_ROOT/.specify/extensions/git/scripts/bash/get-last-worktree.sh"
SPECKIT_WORKTREE_SELECT_WORKTREE_SCRIPT="$SPECKIT_WORKTREE_REPO_ROOT/.specify/shell/select-worktree.sh"

_speckit_worktree_prompt_cli() {
  local selection cli_name cli_command status

  while true; do
    printf '1. Anthropic' >&2
    if command -v claude >/dev/null 2>&1; then
      printf ' [available]\n' >&2
    else
      printf ' [not installed]\n' >&2
    fi

    printf '2. Codex' >&2
    if command -v codex >/dev/null 2>&1; then
      printf ' [available]\n' >&2
    else
      printf ' [not installed]\n' >&2
    fi

    printf '3. Gemini' >&2
    if command -v gemini >/dev/null 2>&1; then
      printf ' [available]\n' >&2
    else
      printf ' [not installed]\n' >&2
    fi

    printf 'Select AI CLI [1] (q to cancel): ' >&2
    if ! IFS= read -r selection; then
      echo >&2
      return 1
    fi

    selection="${selection#"${selection%%[![:space:]]*}"}"
    selection="${selection%"${selection##*[![:space:]]}"}"
    if [ -z "$selection" ]; then
      selection=1
    fi

    case "$selection" in
      q|Q)
        return 1
        ;;
      1)
        cli_name="Anthropic"
        cli_command="claude"
        ;;
      2)
        cli_name="Codex"
        cli_command="codex"
        ;;
      3)
        cli_name="Gemini"
        cli_command="gemini"
        ;;
      *)
        echo "Invalid selection. Enter 1-3 or q." >&2
        continue
        ;;
    esac

    if ! command -v "$cli_command" >/dev/null 2>&1; then
      echo "$cli_name CLI is not installed on PATH." >&2
      continue
    fi

    printf '%s\n' "$cli_command"
    return 0
  done
}

_speckit_worktree_select_worktree() {
  local target _SPECKIT_WORKTREE_CAPTURED_PATH

  if [ ! -f "$SPECKIT_WORKTREE_SELECT_WORKTREE_SCRIPT" ]; then
    echo "worktree selector not found: $SPECKIT_WORKTREE_SELECT_WORKTREE_SCRIPT" >&2
    return 1
  fi

  _speckit_worktree_capture_path bash "$SPECKIT_WORKTREE_SELECT_WORKTREE_SCRIPT" --path || return 1
  target="$_SPECKIT_WORKTREE_CAPTURED_PATH"
  if [ -z "$target" ]; then
    echo "no Speckit worktree selected" >&2
    return 1
  fi

  printf '%s\n' "$target"
}

# Load a handoff into _SPECKIT_WT_* variables. A shape-aware helper answers
# `--env` with `KEY=value` assignments; an older or stubbed helper prints only
# the worktree path, which is still accepted verbatim (byte-exact, including
# any trailing newlines in the path).
_speckit_worktree_load_env() {
  local output _SPECKIT_WORKTREE_CAPTURED_PATH

  _SPECKIT_WT_REPO_SHAPE=single
  _SPECKIT_WT_PROJECT_ROOT=""
  _SPECKIT_WT_BRANCH_NAME=""
  _SPECKIT_WT_WORKTREE_PATH=""
  _SPECKIT_WT_SPEC_WORKTREE_PATH=""
  _SPECKIT_WT_CODE_WORKTREE_PATH=""
  _SPECKIT_WT_FEATURE_DIR=""
  _SPECKIT_WT_SPECIFY_FEATURE=""
  _SPECKIT_WT_SPECIFY_FEATURE_DIRECTORY=""
  _SPECKIT_WT_TARGET=""

  _speckit_worktree_capture_path "$@" || return 1
  output="$_SPECKIT_WORKTREE_CAPTURED_PATH"
  [ -n "$output" ] || return 1

  case "$output" in
    REPO_SHAPE=*)
      eval "$(printf '%s\n' "$output" | sed 's/^/_SPECKIT_WT_/')" || return 1
      ;;
    *)
      _SPECKIT_WT_WORKTREE_PATH="$output"
      ;;
  esac
}

_speckit_worktree_select_env() {
  if [ ! -f "$SPECKIT_WORKTREE_SELECT_WORKTREE_SCRIPT" ]; then
    echo "worktree selector not found: $SPECKIT_WORKTREE_SELECT_WORKTREE_SCRIPT" >&2
    return 1
  fi

  if ! _speckit_worktree_load_env bash "$SPECKIT_WORKTREE_SELECT_WORKTREE_SCRIPT" --env; then
    _speckit_worktree_load_env bash "$SPECKIT_WORKTREE_SELECT_WORKTREE_SCRIPT" --path || return 1
  fi
  if [ -z "$_SPECKIT_WT_WORKTREE_PATH" ]; then
    echo "no Speckit worktree selected" >&2
    return 1
  fi
}

# Where a CLI session should start: the project root in a three-leg project
# (the only place .specify/ exists), the feature worktree otherwise. Assigns
# rather than echoes so paths keep their exact bytes.
_speckit_worktree_set_target() {
  if [ "${_SPECKIT_WT_REPO_SHAPE:-single}" = "three-leg" ]; then
    _SPECKIT_WT_TARGET="$_SPECKIT_WT_PROJECT_ROOT"
  else
    _SPECKIT_WT_TARGET="$_SPECKIT_WT_WORKTREE_PATH"
  fi
}

_speckit_worktree_report_three_leg() {
  local label="$1"

  printf '%s: three-leg project; starting in %s\n' "$label" "$_SPECKIT_WT_PROJECT_ROOT" >&2
  printf '%s: SPECIFY_FEATURE=%s\n' "$label" "$_SPECKIT_WT_SPECIFY_FEATURE" >&2
  printf '%s: SPECIFY_FEATURE_DIRECTORY=%s\n' "$label" "$_SPECKIT_WT_SPECIFY_FEATURE_DIRECTORY" >&2
  printf '%s: spec worktree %s\n' "$label" "$_SPECKIT_WT_SPEC_WORKTREE_PATH" >&2
  printf '%s: code worktree %s\n' "$label" "$_SPECKIT_WT_CODE_WORKTREE_PATH" >&2
}

_speckit_worktree_start_cli() {
  local cli_command="$1"
  local target="$2"
  shift 2 || true

  cd "$target" || return 1
  if [ -n "${_SPECKIT_WT_SPECIFY_FEATURE:-}" ]; then
    env SPECIFY_FEATURE="$_SPECKIT_WT_SPECIFY_FEATURE" \
      SPECIFY_FEATURE_DIRECTORY="$_SPECKIT_WT_SPECIFY_FEATURE_DIRECTORY" \
      "$cli_command" "$@"
    return $?
  fi
  "$cli_command" "$@"
}

_speckit_worktree_start_claude() {
  local target="$1"
  shift || true

  _speckit_worktree_start_cli claude "$target" \
    --model opus \
    --teammate-mode tmux \
    "$@"
}

_speckit_worktree_start_codex() {
  local target="$1"
  shift || true

  _speckit_worktree_start_cli codex "$target" \
    -m gpt-5.4 \
    -c 'model_reasoning_effort="high"' \
    "$@"
}

_speckit_worktree_start_gemini() {
  local target="$1"
  shift || true

  _speckit_worktree_start_cli gemini "$target" \
    --model gemini-2.5-pro \
    "$@"
}

ct() {
  local target

  if [ ! -f "$SPECKIT_WORKTREE_LAST_WORKTREE_SCRIPT" ]; then
    echo "ct: helper script not found: $SPECKIT_WORKTREE_LAST_WORKTREE_SCRIPT" >&2
    return 1
  fi

  if ! _speckit_worktree_load_env bash "$SPECKIT_WORKTREE_LAST_WORKTREE_SCRIPT" --env; then
    _speckit_worktree_load_env bash "$SPECKIT_WORKTREE_LAST_WORKTREE_SCRIPT" || return 1
  fi

  if [ "$_SPECKIT_WT_REPO_SHAPE" = "three-leg" ]; then
    # The project root is the only place .specify/ exists, so Speckit commands
    # run from there with the feature selected; the files live in the worktrees.
    _speckit_worktree_report_three_leg ct
    export SPECIFY_FEATURE="$_SPECKIT_WT_SPECIFY_FEATURE"
    export SPECIFY_FEATURE_DIRECTORY="$_SPECKIT_WT_SPECIFY_FEATURE_DIRECTORY"
  fi

  _speckit_worktree_set_target
  target="$_SPECKIT_WT_TARGET"
  if [ -z "$target" ]; then
    echo "ct: no Speckit worktree path returned" >&2
    return 1
  fi

  cd "$target" || return 1
}

ctp() {
  if [ ! -f "$SPECKIT_WORKTREE_LAST_WORKTREE_SCRIPT" ]; then
    echo "ctp: helper script not found: $SPECKIT_WORKTREE_LAST_WORKTREE_SCRIPT" >&2
    return 1
  fi

  bash "$SPECKIT_WORKTREE_LAST_WORKTREE_SCRIPT" --json
}

cta() {
  local target

  if ! command -v claude >/dev/null 2>&1; then
    echo "cta: Claude CLI not found on PATH" >&2
    return 1
  fi

  _speckit_worktree_select_env || return 1
  if [ "$_SPECKIT_WT_REPO_SHAPE" = "three-leg" ]; then
    _speckit_worktree_report_three_leg cta
  fi
  _speckit_worktree_set_target
  target="$_SPECKIT_WT_TARGET"
  _speckit_worktree_start_claude "$target" "$@"
}

ctc() {
  local target

  if ! command -v codex >/dev/null 2>&1; then
    echo "ctc: Codex CLI not found on PATH" >&2
    return 1
  fi

  _speckit_worktree_select_env || return 1
  if [ "$_SPECKIT_WT_REPO_SHAPE" = "three-leg" ]; then
    _speckit_worktree_report_three_leg ctc
  fi
  _speckit_worktree_set_target
  target="$_SPECKIT_WT_TARGET"
  _speckit_worktree_start_codex "$target" "$@"
}

ctg() {
  local target

  if ! command -v gemini >/dev/null 2>&1; then
    echo "ctg: Gemini CLI not found on PATH" >&2
    return 1
  fi

  _speckit_worktree_select_env || return 1
  if [ "$_SPECKIT_WT_REPO_SHAPE" = "three-leg" ]; then
    _speckit_worktree_report_three_leg ctg
  fi
  _speckit_worktree_set_target
  target="$_SPECKIT_WT_TARGET"
  _speckit_worktree_start_gemini "$target" "$@"
}

cts() {
  local target
  local cli_command

  _speckit_worktree_select_env || return 1
  if [ "$_SPECKIT_WT_REPO_SHAPE" = "three-leg" ]; then
    _speckit_worktree_report_three_leg cts
  fi
  _speckit_worktree_set_target
  target="$_SPECKIT_WT_TARGET"
  cli_command=$(_speckit_worktree_prompt_cli) || return 1
  case "$cli_command" in
    claude)
      _speckit_worktree_start_claude "$target" "$@"
      ;;
    codex)
      _speckit_worktree_start_codex "$target" "$@"
      ;;
    gemini)
      _speckit_worktree_start_gemini "$target" "$@"
      ;;
    *)
      echo "cts: unsupported CLI selection: $cli_command" >&2
      return 1
      ;;
  esac
}

ctlist() {
  if [ ! -f "$SPECKIT_WORKTREE_SELECT_WORKTREE_SCRIPT" ]; then
    echo "ctlist: helper script not found: $SPECKIT_WORKTREE_SELECT_WORKTREE_SCRIPT" >&2
    return 1
  fi

  bash "$SPECKIT_WORKTREE_SELECT_WORKTREE_SCRIPT" --list
}
