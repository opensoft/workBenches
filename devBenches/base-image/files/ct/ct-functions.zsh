# Project-agnostic Speckit worktree helpers for developer benches.
#
# Defines: ct, ctp, ctlist, cta, ctc, ctg, cts.
#
# Each function resolves the current Git repo at call time via
# `git rev-parse --show-toplevel`, then dispatches to per-repo helper scripts
# under `.specify/`. Errors cleanly if you're not inside a Git repo or the
# repo does not contain a `.specify/` tree.

_ct_repo_root() {
    local root

    root=$(git rev-parse --show-toplevel 2>/dev/null) || {
        echo "ct: not inside a Git repository" >&2
        return 1
    }

    if [ ! -d "$root/.specify" ]; then
        echo "ct: .specify/ not found in repo root: $root" >&2
        return 1
    fi

    printf '%s\n' "$root"
}

_ct_last_worktree_script() {
    local root script

    root=$(_ct_repo_root) || return 1
    script="$root/.specify/extensions/git/scripts/bash/get-last-worktree.sh"

    if [ ! -f "$script" ]; then
        echo "ct: helper script not found: $script" >&2
        return 1
    fi

    printf '%s\n' "$script"
}

_ct_select_worktree_script() {
    local root script

    root=$(_ct_repo_root) || return 1
    script="$root/.specify/shell/select-worktree.sh"

    if [ ! -f "$script" ]; then
        echo "ct: helper script not found: $script" >&2
        return 1
    fi

    printf '%s\n' "$script"
}

_ct_select_worktree() {
    local script target

    script=$(_ct_select_worktree_script) || return 1
    target=$(bash "$script" --path) || return 1

    if [ -z "$target" ]; then
        echo "ct: no Speckit worktree selected" >&2
        return 1
    fi

    printf '%s\n' "$target"
}

_ct_prompt_cli() {
    local selection cli_name cli_command

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
        [ -z "$selection" ] && selection=1

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

_ct_start_cli() {
    local cli_command="$1"
    local target="$2"

    shift 2 || true
    cd "$target" || return 1
    "$cli_command" "$@"
}

_ct_start_claude() {
    local target="$1"

    shift || true
    _ct_start_cli claude "$target" \
        --model opus \
        --dangerously-skip-permissions \
        --permission-mode bypassPermissions \
        --teammate-mode tmux \
        "$@"
}

_ct_shell_quote() {
    local quoted=()
    local arg

    for arg in "$@"; do
        quoted+=("$(printf '%q' "$arg")")
    done

    printf '%s\n' "${quoted[*]}"
}

_ct_enable_tmux_mouse_copy_mode() {
    # Turn on tmux mouse handling so drag/scroll interactions go through tmux
    # copy mode instead of the terminal swallowing them.
    tmux set-option -g mouse on >/dev/null 2>&1
}

_ct_start_claude_in_tmux() {
    local target="$1"
    local session_name command_string

    shift || true

    if [ -n "${TMUX:-}" ]; then
        _ct_enable_tmux_mouse_copy_mode || {
            echo "cta: failed to enable tmux mouse mode" >&2
            return 1
        }
        _ct_start_claude "$target" "$@"
        return $?
    fi

    session_name="cta-$(date +%Y%m%d%H%M%S)-$$"
    command_string=$(_ct_shell_quote \
        claude \
        --model opus \
        --dangerously-skip-permissions \
        --permission-mode bypassPermissions \
        --teammate-mode tmux \
        "$@") || return 1

    tmux new-session -d -s "$session_name" -c "$target" "exec $command_string" || {
        echo "cta: failed to start tmux" >&2
        return 1
    }

    _ct_enable_tmux_mouse_copy_mode || {
        tmux kill-session -t "$session_name" >/dev/null 2>&1 || true
        echo "cta: failed to enable tmux mouse mode" >&2
        return 1
    }

    tmux attach-session -t "$session_name"
}

_ct_start_codex() {
    local target="$1"

    shift || true
    _ct_start_cli codex "$target" \
        --dangerously-bypass-approvals-and-sandbox \
        -m gpt-5.4 \
        -c 'model_reasoning_effort="high"' \
        "$@"
}

_ct_start_gemini() {
    local target="$1"

    shift || true
    _ct_start_cli gemini "$target" \
        --yolo \
        --approval-mode yolo \
        --model gemini-2.5-pro \
        "$@"
}

ct() {
    local script target

    script=$(_ct_last_worktree_script) || return 1
    target=$(bash "$script") || return 1

    if [ -z "$target" ]; then
        echo "ct: no Speckit worktree path returned" >&2
        return 1
    fi

    cd "$target" || return 1
}

ctp() {
    local script

    script=$(_ct_last_worktree_script) || return 1
    bash "$script" --json
}

ctlist() {
    local script

    script=$(_ct_select_worktree_script) || return 1
    bash "$script" --list
}

cta() {
    local target

    if ! command -v claude >/dev/null 2>&1; then
        echo "cta: Claude CLI not found on PATH" >&2
        return 1
    fi

    if ! command -v tmux >/dev/null 2>&1; then
        echo "cta: tmux not found on PATH" >&2
        return 1
    fi

    target=$(_ct_select_worktree) || return 1
    _ct_start_claude_in_tmux "$target" "$@"
}

ctc() {
    local target

    if ! command -v codex >/dev/null 2>&1; then
        echo "ctc: Codex CLI not found on PATH" >&2
        return 1
    fi

    target=$(_ct_select_worktree) || return 1
    _ct_start_codex "$target" "$@"
}

ctg() {
    local target

    if ! command -v gemini >/dev/null 2>&1; then
        echo "ctg: Gemini CLI not found on PATH" >&2
        return 1
    fi

    target=$(_ct_select_worktree) || return 1
    _ct_start_gemini "$target" "$@"
}

cts() {
    local target cli_command

    target=$(_ct_select_worktree) || return 1
    cli_command=$(_ct_prompt_cli) || return 1

    case "$cli_command" in
        claude)
            _ct_start_claude "$target" "$@"
            ;;
        codex)
            _ct_start_codex "$target" "$@"
            ;;
        gemini)
            _ct_start_gemini "$target" "$@"
            ;;
        *)
            echo "cts: unsupported CLI selection: $cli_command" >&2
            return 1
            ;;
    esac
}
