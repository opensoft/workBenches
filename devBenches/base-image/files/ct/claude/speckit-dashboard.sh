#!/usr/bin/env bash
# speckit-dashboard.sh — interactive Spec Kit dashboard for a tmux pane.
#
# Reads .claude/dashboard.md and renders it with color. Sections fold/unfold by
# keypress. In live mode it uses an alternate-screen window with a pinned header,
# internal scrolling, a 5-minute sync timer, Claude-pane watching, and Git
# metadata watching.
#
#   Live pane:      bash speckit-dashboard.sh --loop
#   One-shot dump:  bash speckit-dashboard.sh
#
# Keys (while the pane is focused — click it, tmux mouse is on):
#   1-9  fold / unfold that section      a  expand all
#   c    collapse all                    click section / phase rows to toggle
#   mouse wheel / ↑/↓ / j/k scroll
#   PgUp/PgDn page scroll                q  quit
#
# Override the file:  SPECKIT_DASHBOARD_FILE=<path>   or   --file <path>
set -u

FILE="${SPECKIT_DASHBOARD_FILE:-.claude/dashboard.md}"
[[ "${1:-}" == --file ]] && { FILE="$2"; shift 2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P || pwd)"

dashboard_sync_script() {
  local candidate

  for candidate in \
    "$HOME/.claude/speckit-dashboard-sync.sh" \
    "$SCRIPT_DIR/speckit-dashboard-sync.sh" \
    /usr/local/share/ct/claude/speckit-dashboard-sync.sh; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

esc=$'\033'
c_reset="${esc}[0m";  c_bold="${esc}[1m";   c_dim="${esc}[2m"
c_green="${esc}[38;5;42m";   c_yellow="${esc}[38;5;220m"
c_orange="${esc}[38;5;208m"; c_red="${esc}[38;5;203m"
c_cyan="${esc}[38;5;45m";    c_grey="${esc}[38;5;245m"
c_white="${esc}[38;5;255m";  c_black="${esc}[38;5;16m"
c_bg_cyan="${esc}[48;5;45m"

declare -A folded=()          # folded[N]=1  ->  section N is collapsed
declare -A phase_expanded=()  # phase_expanded[N]=1  ->  phase tasks are shown

sync_dashboard() {
  local reason="${1:-loop}"

  if [[ "${SPECKIT_DASHBOARD_AUTOSYNC:-1}" == 0 ]]; then
    return
  fi

  local sync_script
  sync_script="$(dashboard_sync_script || true)"
  if [[ -n "$sync_script" ]]; then
    SPECKIT_DASHBOARD_FILE="$FILE" \
      SPECKIT_DASHBOARD_SYNC_REASON="$reason" \
      SPECKIT_DASHBOARD_FORCE="${SPECKIT_DASHBOARD_FORCE:-0}" \
      SPECKIT_DASHBOARD_CLAUDE_PANE="${SPECKIT_DASHBOARD_CLAUDE_PANE:-}" \
      bash "$sync_script" >/dev/null 2>&1 || true
  fi
}

find_claude_pane() {
  if [[ -n "${SPECKIT_DASHBOARD_CLAUDE_PANE:-}" ]]; then
    printf '%s\n' "$SPECKIT_DASHBOARD_CLAUDE_PANE"
    return
  fi

  [[ -n "${TMUX:-}" ]] || return 1

  local current="${TMUX_PANE:-}"
  tmux list-panes -F '#{pane_id} #{pane_title} #{pane_current_command}' 2>/dev/null \
    | awk -v current="$current" '
        $1 == current { next }
        $2 == "speckit-dash" { next }
        $3 == "claude" { print $1; found = 1; exit }
        candidate == "" { candidate = $1 }
        END { if (!found && candidate != "") print candidate }
      '
}

pane_signature() {
  local pane="$1"

  [[ -n "$pane" ]] || {
    printf 'no-pane\n'
    return
  }

  if command -v sha256sum >/dev/null 2>&1; then
    tmux capture-pane -p -t "$pane" -S -220 2>/dev/null | sha256sum | awk '{ print $1 }'
  else
    tmux capture-pane -p -t "$pane" -S -220 2>/dev/null | cksum | awk '{ print $1 ":" $2 }'
  fi
}

dashboard_root() {
  if [[ -n "${SPECKIT_DASHBOARD_CWD:-}" ]]; then
    printf '%s\n' "$SPECKIT_DASHBOARD_CWD"
    return
  fi

  if [[ "$FILE" == */.claude/dashboard.md ]]; then
    local dir
    dir="$(cd "$(dirname "$FILE")/.." 2>/dev/null && pwd -P || true)"
    [[ -n "$dir" ]] && {
      printf '%s\n' "$dir"
      return
    }
  fi

  pwd -P 2>/dev/null || pwd
}

git_signature() {
  local root="$1"
  local git_dir common_dir

  git_dir="$(git -C "$root" rev-parse --git-dir 2>/dev/null || true)"
  [[ -n "$git_dir" ]] || {
    printf 'no-git\n'
    return
  }

  if [[ "$git_dir" != /* ]]; then
    git_dir="$root/$git_dir"
  fi

  common_dir="$(git -C "$root" rev-parse --git-common-dir 2>/dev/null || true)"
  if [[ -n "$common_dir" && "$common_dir" != /* ]]; then
    common_dir="$root/$common_dir"
  fi

  {
    git -C "$root" symbolic-ref -q HEAD 2>/dev/null || git -C "$root" rev-parse HEAD 2>/dev/null || true
    for path in \
      "$git_dir/HEAD" \
      "$git_dir/index" \
      "$git_dir/MERGE_HEAD" \
      "$git_dir/CHERRY_PICK_HEAD" \
      "$git_dir/REBASE_HEAD" \
      "$git_dir/rebase-merge" \
      "$git_dir/rebase-apply" \
      "$common_dir/packed-refs" \
      "$common_dir/refs/heads" \
      "$common_dir/refs/remotes"; do
      if [[ -e "$path" ]]; then
        stat -c '%n:%Y:%s' "$path" 2>/dev/null || true
        if [[ -d "$path" ]]; then
          find "$path" -maxdepth 2 -type f -printf '%p:%T@:%s\n' 2>/dev/null | sort || true
        fi
      fi
    done
  } | {
    if command -v sha256sum >/dev/null 2>&1; then
      sha256sum | awk '{ print $1 }'
    else
      cksum | awk '{ print $1 ":" $2 }'
    fi
  }
}

is_rule() {                   # true when the line is a pure horizontal rule
  local l="$1"
  [[ -n "$l" && ! "$l" =~ [A-Za-z0-9] && ( "$l" == *══* || "$l" == *──* ) ]]
}

line_colour() {               # echo an ANSI colour for a body line, else nothing
  local section="$1" line="$2"
  case "$section" in
    "LAST COMMAND"*)
      case "$line" in
        *CRITICAL*|*HIGH*|*🔴*) printf %s "$c_red" ;;
        *MEDIUM*|*🟠*)          printf %s "$c_orange" ;;
        *LOW*|*🟡*)             printf %s "$c_yellow" ;;
        *)                      printf %s "$c_green" ;;
      esac ;;
    "NEXT COMMANDS"*)
      case "$line" in
        *"⭐"*|*"★"*)     printf %s "${c_bold}${c_green}" ;;
        *block*|*BLOCK*) printf %s "$c_red" ;;
      esac ;;
    "RECENT ACTIVITY"*)
      case "$line" in
        *abort*|*ABORT*)     printf %s "$c_red" ;;
        *"just ran"*|*"🔵"*) printf %s "$c_cyan" ;;
        *"↻"*)               printf %s "$c_yellow" ;;
      esac ;;
    "SPEC KIT WORKFLOW"*)
      case "$line" in
        *"just ran ✅"*) printf %s "$c_green" ;;
        *"just ran ❌"*) printf %s "$c_red" ;;
      esac ;;
    "PHASES"*)
      case "$line" in
        *"🎯"*|*"🛡"*) printf %s "${c_bold}${c_white}" ;;
      esac ;;
    "LAST 3 PROMPTS"*) printf %s "$c_dim" ;;
  esac
}

render_title() {
  printf '%s\n' "${c_bold}${c_cyan}Speckit Dashboard${c_reset}"
}

render_body() {
  if [[ ! -f "$FILE" ]]; then
    printf '%s\n' "${c_grey}No dashboard yet. It appears after cta creates .claude/dashboard.md.${c_reset}"
    return
  fi

  local line section="" secnum=0 skip=0 ind col in_banner=1 phase_index=0 phase_skip=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    if (( in_banner )); then
      if [[ "$line" == *"SESSION DASHBOARD"* || "$line" == *"Speckit Dashboard"* ]]; then
        continue
      fi
      if [[ "$line" == *══* ]]; then
        continue
      fi
      in_banner=0
    fi

    if is_rule "$line"; then
      if [[ "$line" == *══* ]]; then printf '%s\n' "${c_cyan}${line}${c_reset}"
      else                           printf '%s\n' "${c_grey}${line}${c_reset}"; fi
      continue
    fi

    if [[ "$line" =~ ^[[:space:]][A-Z] ]]; then            # section header
      secnum=$(( secnum + 1 ))
      section="${line#" "}"
      phase_index=0
      phase_skip=0
      if [[ -n "${folded[$secnum]:-}" ]]; then skip=1; ind="▸"
      else                                     skip=0; ind="▾"; fi
      printf '%s\n' "${c_bold}${c_white}${ind} ${secnum} ${line}${c_reset}"
      continue
    fi
    (( skip )) && continue                                  # folded section body
    if [[ "$section" == PHASES* ]]; then
      if [[ "$line" =~ ^[[:space:]]{6}.+T[0-9]+[A-Za-z]?[[:space:]] ]]; then
        (( phase_skip )) && continue
      elif [[ "$line" == "   🎯 "* || "$line" == "   🛡 "* ]]; then
        phase_skip=0
      elif [[ "$line" =~ ^[[:space:]]{3}([^[:space:]]+|○)[[:space:]]+.+[[:space:]][0-9]+/[0-9]+$ ]]; then
        phase_index=$(( phase_index + 1 ))
        if [[ -n "${phase_expanded[$phase_index]:-}" ]]; then
          ind="▾"
          phase_skip=0
        else
          ind="▸"
          phase_skip=1
        fi
        line="   ${ind} ${line#   }"
      else
        phase_skip=0
      fi
    fi
    col="$(line_colour "$section" "$line")"
    if [[ -n "$col" ]]; then printf '%s\n' "${col}${line}${c_reset}"
    else                     printf '%s\n' "$line"; fi
  done < "$FILE"
}

render() {                    # one-shot dump
  render_title
  render_body
}

section_count() {
  [[ -f "$FILE" ]] && grep -cE '^[[:space:]][A-Z]' "$FILE" || echo 0
}

phase_count() {
  [[ -f "$FILE" ]] || {
    echo 0
    return
  }

  awk '
    /^[[:space:]]PHASES/ { in_phases = 1; next }
    /^[[:space:]][A-Z]/ { if (in_phases) exit }
    in_phases && /^   / && $0 !~ /^      / && $0 !~ /^   🎯/ && $0 !~ /^   🛡/ && $0 ~ /[0-9]+\/[0-9]+$/ { count++ }
    END { print count + 0 }
  ' "$FILE"
}

pane_rows() {
  local rows
  if [[ -n "${TMUX:-}" ]]; then
    rows="$(tmux display-message -p '#{pane_height}' 2>/dev/null || true)"
  fi
  [[ -n "${rows:-}" ]] || rows="$(tput lines 2>/dev/null || true)"
  [[ -n "${rows:-}" ]] || rows=40
  printf '%s\n' "$rows"
}

pane_cols() {
  local cols
  if [[ -n "${TMUX:-}" ]]; then
    cols="$(tmux display-message -p '#{pane_width}' 2>/dev/null || true)"
  fi
  [[ -n "${cols:-}" ]] || cols="$(tput cols 2>/dev/null || true)"
  [[ -n "${cols:-}" ]] || cols=80
  printf '%s\n' "$cols"
}

clear_line() {
  printf '%s' "${esc}[2K"
}

render_window() {
  local rows cols body_height total max_scroll i line
  local -a lines

  rows="$(pane_rows)"
  cols="$(pane_cols)"
  body_height=$(( rows - 4 ))
  (( body_height < 1 )) && body_height=1

  mapfile -t lines < <(render_body)
  total="${#lines[@]}"
  max_scroll=$(( total - body_height ))
  (( max_scroll < 0 )) && max_scroll=0
  (( scroll_offset > max_scroll )) && scroll_offset="$max_scroll"
  (( scroll_offset < 0 )) && scroll_offset=0

  printf '%s' "${esc}[H"
  clear_line
  printf '%s' "${c_bold}${c_bg_cyan}${c_black} Speckit Dashboard ${c_reset}"
  printf ' %s' "${c_grey}${FILE}${c_reset}"
  printf '\n'
  clear_line
  printf '%s\n' "${c_cyan}$(printf '%*s' "$cols" '' | tr ' ' '─')${c_reset}"

  for ((i=0; i<body_height; i++)); do
    clear_line
    line_index=$(( scroll_offset + i ))
    if (( line_index < total )); then
      printf '%s\n' "${lines[$line_index]}"
    else
      printf '\n'
    fi
  done

  clear_line
  if (( max_scroll > 0 )); then
    printf '%s\n' "${c_dim}  click header/phase · wheel/↑↓ · 1-9 fold · a/c · q · ${scroll_offset}/${max_scroll}${c_reset}"
  else
    printf '%s\n' "${c_dim}  click phase · 1-9 fold · a expand · c collapse · q quit${c_reset}"
  fi
}

# ---- one-shot mode ----------------------------------------------------------
if [[ "${1:-}" != --loop ]]; then
  sync_dashboard "oneshot"
  render
  exit 0
fi

# ---- interactive pane mode --------------------------------------------------
cleanup() { printf '%s' "${c_reset}${esc}[?1006l${esc}[?1000l${esc}[?7h${esc}[?25h${esc}[?1049l"; exit 0; }
trap cleanup INT TERM
printf '%s' "${esc}[?1049h${esc}[?25l${esc}[?7l${esc}[?1000h${esc}[?1006h"

read_escape_tail() {
  local seq="" ch timeout="${SPECKIT_DASHBOARD_ESCAPE_TIMEOUT:-0.15}"

  # Mouse and arrow key input arrives as escape sequences. Some benches can
  # deliver those bytes with small gaps under load, so do not assume a tight
  # 30ms packet.
  while IFS= read -rsn1 -t "$timeout" ch; do
    seq+="$ch"
    case "$seq" in
      '[A'|'[B'|'[5~'|'[6~')
        break
        ;;
      '[<'*[Mm])
        break
        ;;
      '[M'???)
        break
        ;;
    esac
  done

  printf '%s' "$seq"
}

mouse_scroll_delta() {
  local seq="$1" code payload first_ord

  case "$seq" in
    '[<'*[Mm])
      payload="${seq#'[<'}"
      code="${payload%%;*}"
      case "$code" in
        64|68|72|76) printf '%s\n' -3; return 0 ;;
        65|69|73|77) printf '%s\n' 3; return 0 ;;
      esac
      ;;
    '[M'???)
      payload="${seq#'[M'}"
      LC_CTYPE=C printf -v first_ord '%d' "'${payload:0:1}"
      code=$(( first_ord - 32 ))
      case "$code" in
        64|68|72|76) printf '%s\n' -3; return 0 ;;
        65|69|73|77) printf '%s\n' 3; return 0 ;;
      esac
      ;;
  esac

  return 1
}

toggle_section() {
  local section="$1"

  [[ "$section" =~ ^[1-9]$ ]] || return 1
  if [[ -n "${folded[$section]:-}" ]]; then
    unset "folded[$section]"
  else
    folded[$section]=1
  fi
}

toggle_phase() {
  local phase="$1"

  [[ "$phase" =~ ^[0-9]+$ && "$phase" -gt 0 ]] || return 1
  if [[ -n "${phase_expanded[$phase]:-}" ]]; then
    unset "phase_expanded[$phase]"
  else
    phase_expanded[$phase]=1
  fi
}

strip_ansi() {
  sed -E $'s/\x1B\\[[0-9;]*[A-Za-z]//g'
}

mouse_click_target() {
  local seq="$1" code payload rest x y first_ord second_ord third_ord
  local line_index line clean i phase=0
  local -a lines

  case "$seq" in
    '[<'*[M])
      payload="${seq#'[<'}"
      code="${payload%%;*}"
      rest="${payload#*;}"
      x="${rest%%;*}"
      rest="${rest#*;}"
      y="${rest%M}"
      [[ "$code" == 0 ]] || return 1
      ;;
    '[M'???)
      payload="${seq#'[M'}"
      LC_CTYPE=C printf -v first_ord '%d' "'${payload:0:1}"
      LC_CTYPE=C printf -v second_ord '%d' "'${payload:1:1}"
      LC_CTYPE=C printf -v third_ord '%d' "'${payload:2:1}"
      code=$(( first_ord - 32 ))
      x=$(( second_ord - 32 ))
      y=$(( third_ord - 32 ))
      (( code == 0 )) || return 1
      ;;
    *)
      return 1
      ;;
  esac

  [[ "$x" =~ ^[0-9]+$ && "$y" =~ ^[0-9]+$ ]] || return 1
  (( y >= 3 )) || return 1
  line_index=$(( scroll_offset + y - 3 ))
  (( line_index >= 0 )) || return 1

  mapfile -t lines < <(render_body)
  (( line_index < ${#lines[@]} )) || return 1

  line="${lines[$line_index]}"
  clean="$(printf '%s\n' "$line" | strip_ansi)"
  if [[ "$clean" =~ ^[^[:space:]]+[[:space:]]*([1-9])([[:space:]]|$) ]]; then
    printf 'section:%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ "$clean" == "   ▸ "* || "$clean" == "   ▾ "* ]]; then
    for ((i=0; i<=line_index; i++)); do
      clean="$(printf '%s\n' "${lines[$i]}" | strip_ansi)"
      if [[ "$clean" == "   ▸ "* || "$clean" == "   ▾ "* ]]; then
        phase=$(( phase + 1 ))
      fi
    done
    if (( phase > 0 )); then
      printf 'phase:%s\n' "$phase"
      return 0
    fi
  fi

  return 1
}

file_signature() {
  if [[ ! -f "$FILE" ]]; then
    printf 'missing\n'
    return
  fi

  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$FILE" 2>/dev/null | awk '{ print $1 }'
  else
    stat -c '%Y:%s' "$FILE" 2>/dev/null || printf 'unreadable\n'
  fi
}

sync_interval="${SPECKIT_DASHBOARD_SYNC_INTERVAL:-300}"
root="$(dashboard_root)"
last_sig=""
last_sync=0
claude_pane="$(find_claude_pane || true)"
last_pane_sig="$(pane_signature "$claude_pane")"
last_git_sig="$(git_signature "$root")"
sync_dashboard "startup"
scroll_offset=0

while true; do
  now="$(date +%s)"
  claude_pane="$(find_claude_pane || true)"
  pane_sig="$(pane_signature "$claude_pane")"
  git_sig="$(git_signature "$root")"

  if [[ "$pane_sig" != "$last_pane_sig" ]]; then
    SPECKIT_DASHBOARD_FORCE=1 \
      SPECKIT_DASHBOARD_CLAUDE_PANE="$claude_pane" \
      sync_dashboard "claude-pane-change"
    last_pane_sig="$pane_sig"
    last_sync="$now"
  elif [[ "$git_sig" != "$last_git_sig" ]]; then
    SPECKIT_DASHBOARD_FORCE=1 \
      SPECKIT_DASHBOARD_CLAUDE_PANE="$claude_pane" \
      sync_dashboard "git-metadata-change"
    last_git_sig="$git_sig"
    last_sync="$now"
  elif (( now - last_sync >= sync_interval )); then
    SPECKIT_DASHBOARD_FORCE=1 \
      SPECKIT_DASHBOARD_CLAUDE_PANE="$claude_pane" \
      sync_dashboard "timer"
    last_sync="$now"
  else
    sync_dashboard "loop"
  fi

  sig="$(file_signature)|${!folded[*]}|${!phase_expanded[*]}|$scroll_offset|$(pane_rows)x$(pane_cols)"
  if [[ "$sig" != "$last_sig" ]]; then                      # redraw only on change
    printf '%s' "${esc}[H${esc}[2J"                         # home + clear visible window
    render_window
    last_sig="$sig"
  fi
  read -rsn1 -t 2 key || continue                           # 2s poll for a keypress
	  case "$key" in
	    [1-9]) toggle_section "$key" ;;
	    a)     folded=(); n="$(phase_count)"; for ((i=1; i<=n; i++)); do phase_expanded[$i]=1; done ;;
	    c)     n="$(section_count)"; for ((i=1; i<=n; i++)); do folded[$i]=1; done; phase_expanded=() ;;
	    j)     scroll_offset=$(( scroll_offset + 1 )) ;;
	    k)     scroll_offset=$(( scroll_offset - 1 )) ;;
	    $'\033')
	           rest="$(read_escape_tail)"
	           if target="$(mouse_click_target "$rest")"; then
	             case "$target" in
	               section:*) toggle_section "${target#section:}" ;;
	               phase:*)   toggle_phase "${target#phase:}" ;;
	             esac
	           elif delta="$(mouse_scroll_delta "$rest")"; then
	             scroll_offset=$(( scroll_offset + delta ))
	           else
	             case "$rest" in
	               '[A') scroll_offset=$(( scroll_offset - 1 )) ;;
	               '[B') scroll_offset=$(( scroll_offset + 1 )) ;;
	               '[5~') scroll_offset=$(( scroll_offset - 10 )) ;;
	               '[6~') scroll_offset=$(( scroll_offset + 10 )) ;;
	             esac
	           fi ;;
	    q)     break ;;
	  esac
  (( scroll_offset < 0 )) && scroll_offset=0
done
cleanup
