#!/usr/bin/env bash
# speckit-dash-toggle.sh — show/hide the Spec Kit dashboard pane in the current
# tmux window. cta binds this to  <prefix> D  automatically; or add to
# ~/.tmux.conf:   bind-key D run-shell '~/.claude/speckit-dash-toggle.sh'
set -u

title=speckit-dash

dashboard_script() {
  local script_dir candidate

  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P || pwd)"
  for candidate in \
    "$HOME/.claude/speckit-dashboard.sh" \
    "$script_dir/speckit-dashboard.sh" \
    /usr/local/share/ct/claude/speckit-dashboard.sh; do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  echo "speckit-dash-toggle: dashboard script not found" >&2
  return 1
}

find_dashboard_root() {
  local dir="$1"

  while [ -n "$dir" ] && [ "$dir" != "/" ]; do
    if [ -f "$dir/.claude/dashboard.md" ] || [ -d "$dir/.specify" ]; then
      printf '%s\n' "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done

  return 1
}

# find a pane in the current window whose title is our marker
pane=$(tmux list-panes -F '#{pane_id} #{pane_title}' \
        | awk -v t="$title" '$2 == t { print $1 }')

if [ -n "$pane" ]; then
  # dashboard is open -> close it
  tmux kill-pane -t "$pane"
else
  # dashboard is closed -> open it, title it, return focus to the left pane
  current_pane=$(tmux display-message -p '#{pane_id}')
  cwd="${SPECKIT_DASHBOARD_CWD:-$(tmux display-message -p '#{pane_current_path}')}"
  dashboard_file="${SPECKIT_DASHBOARD_FILE:-}"
  script="$(dashboard_script)" || exit 1

  if [ -z "$dashboard_file" ]; then
    root=$(find_dashboard_root "$cwd" || true)
    if [ -n "$root" ]; then
      cwd="$root"
      dashboard_file="$root/.claude/dashboard.md"
    fi
  fi

  if [ -n "$dashboard_file" ]; then
    command="SPECKIT_DASHBOARD_FILE=$(printf '%q' "$dashboard_file") SPECKIT_DASHBOARD_CWD=$(printf '%q' "$cwd") bash $(printf '%q' "$script") --loop"
  else
    command="bash $(printf '%q' "$script") --loop"
  fi

  tmux split-window -h -l 68 -c "$cwd" \
       "$command"
  tmux select-pane -T "$title"
  tmux select-pane -t "$current_pane"
fi
