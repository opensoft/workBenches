# Project-agnostic Speckit worktree helpers for developer benches.
#
# Defines: ct, ctp, ctlist, cta, ctc, ctg, cts.
#
# Each function resolves the current Git repo at call time, then dispatches to
# per-repo helper scripts under `.specify/`. When a worktree's Git metadata is
# container-relative, it falls back to the nearest `.specify/` checkout.

_ct_find_specify_root_from_pwd() {
    local dir

    dir=$(pwd -P 2>/dev/null || pwd)
    while [ -n "$dir" ] && [ "$dir" != "/" ]; do
        if [ -d "$dir/.specify" ]; then
            printf '%s\n' "$dir"
            return 0
        fi
        dir=$(dirname "$dir")
    done

    return 1
}

_ct_repo_root() {
    local root

    root=$(git rev-parse --show-toplevel 2>/dev/null || true)
    if [ -z "$root" ]; then
        root=$(_ct_find_specify_root_from_pwd) || {
            echo "ct: not inside a Git repository or Speckit checkout" >&2
            return 1
        }
    fi

    if [ ! -d "$root/.specify" ]; then
        root=$(_ct_find_specify_root_from_pwd) || {
            echo "ct: .specify/ not found in repo root: $root" >&2
            return 1
        }
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

_ct_dashboard_prompt_file() {
    local prompt_file

    for prompt_file in \
        "$HOME/.claude/prompts/speckit-dashboard-full.md" \
        "/usr/local/share/ct/claude/prompts/speckit-dashboard-full.md"; do
        if [ -r "$prompt_file" ]; then
            printf '%s\n' "$prompt_file"
            return 0
        fi
    done

    echo "cta: required dashboard prompt not found in ~/.claude or /usr/local/share/ct/claude" >&2
    return 1
}

_ct_dashboard_script() {
    local script

    for script in \
        "$HOME/.claude/speckit-dashboard.sh" \
        "/usr/local/share/ct/claude/speckit-dashboard.sh"; do
        if [ -x "$script" ]; then
            printf '%s\n' "$script"
            return 0
        fi
    done

    echo "cta: required dashboard script not found in ~/.claude or /usr/local/share/ct/claude" >&2
    return 1
}

_ct_dashboard_toggle_script() {
    local script

    for script in \
        "$HOME/.claude/speckit-dash-toggle.sh" \
        "/usr/local/share/ct/claude/speckit-dash-toggle.sh"; do
        if [ -x "$script" ]; then
            printf '%s\n' "$script"
            return 0
        fi
    done

    echo "cta: required dashboard toggle script not found in ~/.claude or /usr/local/share/ct/claude" >&2
    return 1
}

_ct_start_claude_with_dashboard() {
    local target="$1"
    local prompt_file

    shift || true
    prompt_file=$(_ct_dashboard_prompt_file) || return 1

    _ct_start_cli claude "$target" \
        --model opus \
        --dangerously-skip-permissions \
        --permission-mode bypassPermissions \
        --teammate-mode tmux \
        --append-system-prompt-file "$prompt_file" \
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

_ct_dashboard_command() {
    local target="$1"
    local dashboard_file="$target/.claude/dashboard.md"
    local dashboard_script

    dashboard_script=$(_ct_dashboard_script) || return 1

    printf 'SPECKIT_DASHBOARD_FILE=%s SPECKIT_DASHBOARD_CWD=%s bash %s --loop\n' \
        "$(_ct_shell_quote "$dashboard_file")" \
        "$(_ct_shell_quote "$target")" \
        "$(_ct_shell_quote "$dashboard_script")"
}

_ct_bind_dashboard_toggle() {
    local toggle_script

    toggle_script=$(_ct_dashboard_toggle_script) || return 1
    tmux bind-key D run-shell "bash $(_ct_shell_quote "$toggle_script")" >/dev/null 2>&1
}

_ct_append_gitignore_entry() {
    local gitignore="$1"
    local entry="$2"

    if grep -qxF "$entry" "$gitignore" 2>/dev/null; then
        return 0
    fi

    if [ -s "$gitignore" ] && [ -n "$(tail -c 1 "$gitignore" 2>/dev/null)" ]; then
        printf '\n' >> "$gitignore" || return 1
    fi

    printf '%s\n' "$entry" >> "$gitignore"
}

_ct_ensure_dashboard_gitignore() {
    local target="$1"
    local gitignore="$target/.gitignore"

    if [ -e "$gitignore" ] && [ ! -f "$gitignore" ]; then
        echo "cta: .gitignore exists but is not a file: $gitignore" >&2
        return 1
    fi

    touch "$gitignore" || {
        echo "cta: failed to update gitignore: $gitignore" >&2
        return 1
    }

    _ct_append_gitignore_entry "$gitignore" ".claude/dashboard.md" || return 1
    _ct_append_gitignore_entry "$gitignore" ".claude/speckit-history.md" || return 1
}

_ct_write_initial_dashboard() {
    local target="$1"
    local dashboard_dir="$target/.claude"
    local dashboard_file="$dashboard_dir/dashboard.md"

    _ct_ensure_dashboard_gitignore "$target" || return 1

    mkdir -p "$dashboard_dir" || {
        echo "cta: failed to create dashboard directory: $dashboard_dir" >&2
        return 1
    }

    cat > "$dashboard_file" <<'EOF'
══════════════════════════════════════════════════════════════
 Speckit Dashboard
══════════════════════════════════════════════════════════════
 RECENT ACTIVITY             latest: cta started
   cta  dashboard pane started
──────────────────────────────────────────────────────────────
 SPEC KIT WORKFLOW           ▶ starting 0%
      command                %done  runs
   ○  /speckit.constitution      0%   0
   ○  /speckit.specify           0%   0
   ○  /speckit.clarify           0%   0
   ○  /speckit.checklist         0%   0   (pre-plan)
   ○  /speckit.plan              0%   0
   ○  /speckit.checklist         0%   0   (post-plan)
   ○  /speckit.tasks             0%   0
   ○  /speckit.checklist         0%   0   (post-tasks)
   ○  /speckit.analyze           0%   0
   ○  /speckit.checklist         0%   0   (post-analyze)
   ○  /speckit.implement         0%   0
──────────────────────────────────────────────────────────────
 TASKS                       waiting for feature
   Waiting for active feature detection.
──────────────────────────────────────────────────────────────
 PHASES                      waiting for phases
   Waiting for phase / user-story detection.
──────────────────────────────────────────────────────────────
 LAST COMMAND                cta started
   cta started Claude with dashboard-only output mode.
──────────────────────────────────────────────────────────────
 NEXT COMMANDS               ⭐ constitution/specify
   ⭐ Start with /speckit.constitution or /speckit.specify as needed.
──────────────────────────────────────────────────────────────
 LAST 3 PROMPTS              none yet
   (none yet this cta session)
══════════════════════════════════════════════════════════════
EOF
}

_ct_open_dashboard_pane() {
    local target="$1"
    local tmux_target="$2"
    local focus_pane="$3"
    local dashboard_command dashboard_pane existing_pane

    dashboard_command=$(_ct_dashboard_command "$target") || return 1
    existing_pane=$(tmux list-panes -t "$tmux_target" -F '#{pane_id} #{pane_title}' \
        | awk '$2 == "speckit-dash" { print $1; exit }')
    if [ -n "$existing_pane" ]; then
        tmux kill-pane -t "$existing_pane" >/dev/null 2>&1 || true
    fi

    dashboard_pane=$(tmux split-window -P -F '#{pane_id}' -h -l 68 -t "$tmux_target" -c "$target" "$dashboard_command") || {
        echo "cta: failed to open dashboard pane" >&2
        return 1
    }

    tmux select-pane -t "$dashboard_pane" -T speckit-dash >/dev/null 2>&1 || true
    tmux select-pane -t "$focus_pane" >/dev/null 2>&1 || true
}

_ct_claude_dashboard_command_string() {
    local prompt_file command_string extra_args

    prompt_file=$(_ct_dashboard_prompt_file) || return 1
    command_string=$(_ct_shell_quote \
        claude \
        --model opus \
        --dangerously-skip-permissions \
        --permission-mode bypassPermissions \
        --teammate-mode tmux \
        --append-system-prompt-file "$prompt_file") || return 1

    if [ "$#" -gt 0 ]; then
        extra_args=$(_ct_shell_quote "$@") || return 1
        command_string="$command_string $extra_args"
    fi

    printf '%s\n' "$command_string"
}

_ct_start_claude_in_tmux() {
    local target="$1"
    local session_name command_string current_pane

    shift || true
    _ct_write_initial_dashboard "$target" || return 1
    command_string=$(_ct_claude_dashboard_command_string "$@") || return 1

    if [ -n "${TMUX:-}" ]; then
        _ct_enable_tmux_mouse_copy_mode || {
            echo "cta: failed to enable tmux mouse mode" >&2
            return 1
        }

        current_pane=$(tmux display-message -p '#{pane_id}') || {
            echo "cta: failed to resolve current tmux pane" >&2
            return 1
        }
        _ct_bind_dashboard_toggle || return 1
        _ct_open_dashboard_pane "$target" "$current_pane" "$current_pane" || return 1
        _ct_start_claude_with_dashboard "$target" "$@"
        return $?
    fi

    session_name="cta-$(date +%Y%m%d%H%M%S)-$$"

    tmux new-session -d -s "$session_name" -c "$target" || {
        echo "cta: failed to start tmux" >&2
        return 1
    }

    _ct_enable_tmux_mouse_copy_mode || {
        tmux kill-session -t "$session_name" >/dev/null 2>&1 || true
        echo "cta: failed to enable tmux mouse mode" >&2
        return 1
    }

    _ct_bind_dashboard_toggle || {
        tmux kill-session -t "$session_name" >/dev/null 2>&1 || true
        return 1
    }

    _ct_open_dashboard_pane "$target" "$session_name:0.0" "$session_name:0.0" || {
        tmux kill-session -t "$session_name" >/dev/null 2>&1 || true
        return 1
    }

    tmux send-keys -t "$session_name:0.0" "exec $command_string" C-m || {
        tmux kill-session -t "$session_name" >/dev/null 2>&1 || true
        echo "cta: failed to start Claude in tmux" >&2
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
