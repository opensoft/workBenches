#!/usr/bin/env bash
# speckit-dashboard-sync.sh — repo-state fallback writer for the tmux dashboard.
#
# Claude updates .claude/dashboard.md when a command allows file writes. Some
# Spec Kit commands, notably /speckit-analyze, are explicitly read-only. This
# script lets the dashboard pane keep itself useful by regenerating the dashboard
# from tasks.md, phase headings, and the latest Claude slash command transcript.
set -u

ROOT="${SPECKIT_DASHBOARD_CWD:-}"
OUT="${SPECKIT_DASHBOARD_FILE:-}"
FORCE="${SPECKIT_DASHBOARD_FORCE:-0}"
SYNC_REASON="${SPECKIT_DASHBOARD_SYNC_REASON:-loop}"
CLAUDE_PANE="${SPECKIT_DASHBOARD_CLAUDE_PANE:-}"

if [ -z "$ROOT" ] && [ -n "$OUT" ]; then
  ROOT="$(cd "$(dirname "$OUT")/.." 2>/dev/null && pwd -P || true)"
fi

if [ -z "$ROOT" ]; then
  ROOT="$(pwd -P 2>/dev/null || pwd)"
fi

if [ -z "$OUT" ]; then
  OUT="$ROOT/.claude/dashboard.md"
fi

mkdir -p "$ROOT/.claude" || exit 0

feature_dir_for_root() {
  local branch specs feature_json feature_path

  specs="$ROOT/specs"
  [ -d "$specs" ] || return 1

  feature_json="$ROOT/.specify/feature.json"
  if [ -r "$feature_json" ]; then
    if command -v jq >/dev/null 2>&1; then
      feature_path="$(jq -r '.feature_directory // empty' "$feature_json" 2>/dev/null || true)"
    elif command -v python3 >/dev/null 2>&1; then
      feature_path="$(python3 - "$feature_json" <<'PY' 2>/dev/null || true
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as fh:
    print(json.load(fh).get("feature_directory", ""))
PY
)"
    else
      feature_path="$(sed -nE 's/.*"feature_directory"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$feature_json" | head -1)"
    fi

    if [ -n "$feature_path" ]; then
      case "$feature_path" in
        /*) ;;
        *) feature_path="$ROOT/$feature_path" ;;
      esac
      if [ -d "$feature_path" ]; then
        printf '%s\n' "$feature_path"
        return 0
      fi
    fi
  fi

  branch="$(git -C "$ROOT" branch --show-current 2>/dev/null || true)"
  if [ -n "$branch" ] && [ -d "$specs/$branch" ]; then
    printf '%s\n' "$specs/$branch"
    return 0
  fi

  find "$specs" -maxdepth 1 -mindepth 1 -type d -name '[0-9][0-9][0-9]-*' \
    -printf '%T@ %p\n' 2>/dev/null | sort -nr | awk 'NR == 1 { $1=""; sub(/^ /, ""); print }'
}

encoded_project_dir() {
  local path="$1"
  local encoded

  encoded="-${path#/}"
  encoded="${encoded//\//-}"
  encoded="${encoded//./-}"
  printf '%s/.claude/projects/%s\n' "$HOME" "$encoded"
}

latest_transcript() {
  local project_dir

  project_dir="$(encoded_project_dir "$ROOT")"
  [ -d "$project_dir" ] || return 1
  find "$project_dir" -maxdepth 1 -type f -name '*.jsonl' -printf '%T@ %p\n' 2>/dev/null \
    | sort -nr | awk 'NR == 1 { $1=""; sub(/^ /, ""); print }'
}

pane_snapshot() {
  [ -n "$CLAUDE_PANE" ] || return 1
  tmux capture-pane -p -t "$CLAUDE_PANE" -S -260 2>/dev/null || return 1
}

pane_command() {
  local snapshot

  snapshot="$(pane_snapshot || true)"
  [ -n "$snapshot" ] || return 1

  if printf '%s\n' "$snapshot" | grep -q 'Specification Analysis Report'; then
    printf '/speckit.analyze\n'
    return 0
  fi

  if printf '%s\n' "$snapshot" | grep -qiE 'implement|What landed|tasks complete|Phase .*batch'; then
    printf '/speckit.implement\n'
    return 0
  fi

  return 1
}

latest_command() {
  local log="$1"
  local command

  [ -n "$log" ] && [ -r "$log" ] || return 1
  command="$(tail -c 800000 "$log" \
    | grep -ao '<command-name>[^<]*</command-name>' \
    | tail -1 \
    | sed -E 's#</?command-name>##g' || true)"

  [ -n "$command" ] || return 1
  command="${command/#\/speckit-/\/speckit.}"
  printf '%s\n' "$command"
}

git_status_summary() {
  local branch changed ahead behind ab

  branch="$(git -C "$ROOT" branch --show-current 2>/dev/null || true)"
  if [ -z "$branch" ]; then
    branch="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || true)"
  fi
  [ -n "$branch" ] || {
    printf 'no git status'
    return
  }

  changed="$(git -C "$ROOT" status --porcelain=v1 2>/dev/null | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')"
  [ -n "$changed" ] || changed=0

  ab="$(git -C "$ROOT" status --porcelain=v2 --branch 2>/dev/null | awk '/^# branch.ab / { print $3 " " $4; exit }')"
  ahead=""
  behind=""
  if [ -n "$ab" ]; then
    ahead="$(printf '%s\n' "$ab" | awk '{ print $1 }' | sed 's/^+//')"
    behind="$(printf '%s\n' "$ab" | awk '{ print $2 }' | sed 's/^-//')"
  fi

  if [ "$changed" -eq 0 ]; then
    printf '%s clean' "$branch"
  else
    printf '%s %s changed' "$branch" "$changed"
  fi

  if [ "${ahead:-0}" -ne 0 ] || [ "${behind:-0}" -ne 0 ]; then
    printf ' (%s ahead, %s behind)' "${ahead:-0}" "${behind:-0}"
  fi
}

pull_request_workflow_row() {
  local pr_data pr_number pr_state review_count fix_count marker gh_timeout

  if [ "${SPECKIT_DASHBOARD_PR:-1}" = "0" ] || ! command -v gh >/dev/null 2>&1; then
    printf '   ○  Pull Request             PR -- rev 0 fix 0\n'
    return
  fi

  gh_timeout="${SPECKIT_DASHBOARD_GH_TIMEOUT:-6}"
  case "$gh_timeout" in
    ''|*[!0-9]*) gh_timeout=6 ;;
  esac

  if command -v timeout >/dev/null 2>&1; then
    pr_data="$(GH_PROMPT_DISABLED=1 timeout "$gh_timeout" gh pr view \
      --json number,state,reviews,commits \
      --jq '([.reviews[].submittedAt] | map(select(. != null)) | sort | .[0] // "") as $first_review | "\(.number)\t\(.state)\t\(.reviews|length)\t\(if $first_review == "" then 0 else ([.commits[].committedDate] | map(select(. > $first_review)) | length) end)"' \
      2>/dev/null || true)"
  else
    pr_data="$(GH_PROMPT_DISABLED=1 gh pr view \
      --json number,state,reviews,commits \
      --jq '([.reviews[].submittedAt] | map(select(. != null)) | sort | .[0] // "") as $first_review | "\(.number)\t\(.state)\t\(.reviews|length)\t\(if $first_review == "" then 0 else ([.commits[].committedDate] | map(select(. > $first_review)) | length) end)"' \
      2>/dev/null || true)"
  fi

  if [ -z "$pr_data" ]; then
    printf '   ○  Pull Request             PR -- rev 0 fix 0\n'
    return
  fi

  IFS=$'\t' read -r pr_number pr_state review_count fix_count <<EOF
$pr_data
EOF

  case "$pr_state" in
    MERGED) marker='🟢' ;;
    CLOSED) marker='🔴' ;;
    *) marker='🔵' ;;
  esac

  printf '   %s Pull Request             PR #%s rev %s fix %s\n' \
    "$marker" "${pr_number:---}" "${review_count:-0}" "${fix_count:-0}"
}

prompt_summaries() {
  local log="$1"
  local count="${2:-5}"
  local width="${3:-54}"
  local snapshot

  case "$count" in ''|*[!0-9]*) count=5 ;; esac
  case "$width" in ''|*[!0-9]*) width=54 ;; esac

  if [ -n "$log" ] && [ -r "$log" ] && command -v python3 >/dev/null 2>&1; then
    python3 - "$log" "$count" "$width" <<'PY' 2>/dev/null && return 0
import json
import re
import sys

path, count, width = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
items = []
by_prompt_id = {}
seen_text = set()

def clean(text):
    if not text:
        return ""
    text = str(text)
    command = re.search(r"<command-name>(.*?)</command-name>", text, re.S)
    if command:
        return command.group(1).strip()
    text = re.sub(r"<command-message>.*?</command-message>", " ", text, flags=re.S)
    text = re.sub(r"<[^>]+>", " ", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text

def add_prompt(prompt_id, summary):
    summary = clean(summary)
    if not summary or summary == "Structured output provided successfully":
        return
    if prompt_id in by_prompt_id:
        idx = by_prompt_id[prompt_id]
        if not items[idx].startswith("/") and summary.startswith("/"):
            seen_text.discard(items[idx])
            items[idx] = summary
            seen_text.add(summary)
        return
    if summary in seen_text:
        return
    by_prompt_id[prompt_id] = len(items)
    seen_text.add(summary)
    items.append(summary)

with open(path, "r", encoding="utf-8", errors="replace") as fh:
    for line in fh:
        try:
            obj = json.loads(line)
        except Exception:
            continue
        if obj.get("type") != "user":
            continue
        msg = obj.get("message") or {}
        if msg.get("role") != "user":
            continue
        content = msg.get("content")
        prompt_id = obj.get("promptId") or obj.get("uuid")
        if isinstance(content, str):
            add_prompt(prompt_id, content)
        elif isinstance(content, list):
            parts = []
            for part in content:
                if not isinstance(part, dict):
                    continue
                if part.get("type") == "tool_result" or "tool_use_id" in part:
                    continue
                if part.get("type") == "text":
                    parts.append(part.get("text", ""))
            add_prompt(prompt_id, "\n".join(parts))

recent = list(reversed(items[-count:]))
if not recent:
    sys.exit(1)
for idx, item in enumerate(recent, 1):
    if len(item) > width:
        item = item[: max(width - 1, 1)] + "…"
    print(f"{idx}. {item}")
PY
  fi

  snapshot="$(pane_snapshot || true)"
  if [ -n "$snapshot" ]; then
    printf '1. %.54s\n' "$(printf '%s\n' "$snapshot" | grep -v '^[[:space:]]*$' | tail -1)"
  fi
}

current_prompt_summary() {
  local log="$1"
  local width="${2:-29}"
  local first

  first="$(prompt_summaries "$log" 1 "$width" | sed -E 's/^[0-9]+\. //' | head -1)"
  [ -n "$first" ] || first="none yet"
  printf '%s\n' "$first"
}

should_sync() {
  local log="$1"
  local command="$2"
  local out_mtime log_mtime

  [ "$FORCE" = "1" ] && return 0
  [ -f "$OUT" ] || return 0
  grep -q 'waiting for active feature\|cta started' "$OUT" 2>/dev/null && return 0

  [ -n "$log" ] && [ -n "$command" ] || return 1
  log_mtime="$(stat -c %Y "$log" 2>/dev/null || echo 0)"
  out_mtime="$(stat -c %Y "$OUT" 2>/dev/null || echo 0)"

  [ "$log_mtime" -gt "$out_mtime" ] || return 1
}

percent() {
  local done="$1"
  local total="$2"

  if [ "$total" -le 0 ]; then
    printf '0'
  else
    printf '%s' $(( done * 100 / total ))
  fi
}

bar_fixed() {
  local done="$1"
  local total="$2"
  local width="${3:-10}"
  local filled empty

  if [ "$total" -le 0 ]; then
    filled=0
  else
    filled=$(( (done * width + total / 2) / total ))
  fi
  [ "$filled" -gt "$width" ] && filled="$width"
  empty=$(( width - filled ))
  while [ "$filled" -gt 0 ]; do
    printf '▰'
    filled=$(( filled - 1 ))
  done
  while [ "$empty" -gt 0 ]; do
    printf '▱'
    empty=$(( empty - 1 ))
  done
}

task_title() {
  local width="${1:-56}"

  sed -E \
    -e 's/^- \[[ xX]\][[:space:]]*(T[0-9]+[A-Za-z]?)[[:space:]]*/\1 /' \
    -e 's/[[:space:]]*\[P\][[:space:]]*/ /g' \
    -e 's/`//g; s/[*#]//g; s/  +/ /g; s/[[:space:]]+$//' \
    | awk -v width="$width" '{ if (length($0) > width) print substr($0, 1, width); else print }'
}

append_history() {
  local history="$ROOT/.claude/speckit-history.md"
  local command="$1"
  local note="$2"
  local next compact_line

  [ -n "$command" ] || return 0
  mkdir -p "$(dirname "$history")" || return 0

  if [ ! -f "$history" ]; then
    {
      printf '# Speckit invocation history\n\n'
      printf 'One line per `/speckit.*` invocation or significant action.\n\n'
      printf '```\n'
    } > "$history" || return 0
  fi

  compact_line="$command $note"
  tail -20 "$history" 2>/dev/null \
    | grep -E '^[0-9]+[[:space:]]+' \
    | sed -E 's/^[0-9]+[[:space:]]+//; s/[[:space:]]+/ /g; s/[[:space:]]+$//' \
    | grep -qxF "$compact_line" && return 2
  next="$(grep -E '^[0-9]+[[:space:]]+' "$history" 2>/dev/null | tail -1 | awk '{ print $1 + 1 }')"
  [ -n "$next" ] || next=1

  if tail -1 "$history" 2>/dev/null | grep -qx '```'; then
    tmp="$(mktemp)"
    sed '$d' "$history" > "$tmp" && mv "$tmp" "$history"
  fi

  printf '%02d  %-18s %s\n' "$next" "$command" "$note" >> "$history"
  printf '```\n' >> "$history"
  return 0
}

feature_dir="$(feature_dir_for_root || true)"
[ -n "$feature_dir" ] || exit 0

tasks_file="$feature_dir/tasks.md"
[ -f "$tasks_file" ] || exit 0

log_file="$(latest_transcript || true)"
if [ "$SYNC_REASON" = "git-metadata-change" ]; then
  command="git status"
else
  command=""
  if [ "$SYNC_REASON" != "timer" ]; then
    command="$(latest_command "$log_file" || true)"
  fi
  if [ -z "$command" ]; then
    command="$(pane_command || true)"
  fi
fi
prompt_summary="$(current_prompt_summary "$log_file" 29)"
prompt_lines="$(prompt_summaries "$log_file" 5 54)"
git_summary="$(git_status_summary)"

should_sync "$log_file" "$command" || exit 0

feature_name="$(basename "$feature_dir")"
task_total="$(grep -cE '^- \[[ xX]\][[:space:]]+T[0-9]+[A-Za-z]?' "$tasks_file" || true)"
task_done="$(grep -cE '^- \[[xX]\][[:space:]]+T[0-9]+[A-Za-z]?' "$tasks_file" || true)"
task_pct="$(percent "$task_done" "$task_total")"
task_bar="$(bar_fixed "$task_done" "$task_total" 10)"

last_command="${command:-repo scan}"
history_just_ran=0
history_note="auto dashboard sync"
if [ "$SYNC_REASON" = "timer" ]; then
  history_note="timer refresh"
elif [ "$SYNC_REASON" = "claude-pane-change" ]; then
  history_note="Claude pane changed"
elif [ "$SYNC_REASON" = "git-metadata-change" ]; then
  history_note="$git_summary"
elif [ "$last_command" = "/speckit.analyze" ] || [ "$last_command" = "/speckit-analyze" ]; then
  history_note="read-only analyze detected"
fi
if [ "$SYNC_REASON" != "timer" ] && [ "$SYNC_REASON" != "loop" ] && [ "$SYNC_REASON" != "claude-pane-change" ]; then
  if append_history "$last_command" "$history_note"; then
    history_just_ran=1
  fi
fi

tmp_open="$(mktemp)"
grep -E '^- \[ \][[:space:]]+T[0-9]+[A-Za-z]?' "$tasks_file" | head -5 > "$tmp_open" || true
open_more=$(( task_total - task_done ))
[ "$open_more" -lt 0 ] && open_more=0

# Set of completed task IDs (sentinel-wrapped: " T001 T002 ... ") used by
# mark_open() to decide whether an open task's declared dependencies are met.
DONE_IDS=" $(grep -oE '^- \[[xX]\][[:space:]]+T[0-9]+[A-Za-z]?' "$tasks_file" 2>/dev/null | grep -oE 'T[0-9]+[A-Za-z]?' | tr '\n' ' ')"

# Marker for an OPEN task. 🔴 (blocked) only when the task explicitly depends on
# a task that is not yet done, or carries a manual ⛔ / BLOCKED: tag. Otherwise
# ○ (not started). Avoid substring matches against task descriptions.
mark_open() {
  local task="$1"
  local deps dep

  case "$task" in
    *'⛔'*|*'BLOCKED:'*) printf '🔴'; return ;;
  esac

  deps="$(printf '%s\n' "$task" | grep -oiE 'depends on[^.]*' | grep -oE 'T[0-9]+[A-Za-z]?')"
  [ -n "$deps" ] || { printf '○ '; return; }

  for dep in $deps; do
    case "$DONE_IDS" in
      *" $dep "*) ;;
      *) printf '🔴'; return ;;
    esac
  done

  printf '○ '
}

phase_file="$(mktemp)"
phase_tasks_file="$(mktemp)"
awk -v summary="$phase_file" -v details="$phase_tasks_file" '
function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
function emit() {
  if (phase != "" && total > 0) {
    print group "\t" phase "\t" done "\t" total >> summary
  }
}
/^## Phase [0-9]+:/ {
  emit()
  raw=$0
  phase=raw
  sub(/^## Phase [0-9]+:[[:space:]]*/, "", phase)
  sub(/[[:space:]]*\(.*/, "", phase)
  phase=trim(phase)
  group="POST"
  if (phase ~ /Setup/) { phase="Setup"; group="MVP" }
  else if (phase ~ /Foundational/) { phase="Foundational"; group="MVP" }
  else if (phase ~ /User Story/) {
    us=phase
    sub(/^.*User Story[[:space:]]*/, "US", us)
    sub(/[[:space:]]*[-—].*$/, "", us)
    pr="P?"
    if (raw ~ /Priority:[[:space:]]*P1/) { pr="P1"; group="MVP" }
    else if (raw ~ /Priority:[[:space:]]*P2/) { pr="P2"; group="POST" }
    else if (raw ~ /Priority:[[:space:]]*P3/) { pr="P3"; group="POST" }
    phase=us " (" pr ")"
  } else if (phase ~ /Polish|Verification|Cross/) {
    phase="Polish"
  }
  done=0
  total=0
  next
}
/^- \[[ xX]\][[:space:]]+T[0-9]+[A-Za-z]?/ {
  if (phase != "") {
    task=$0
    task_label=task
    sub(/^- \[[ xX]\][[:space:]]*/, "", task_label)
    gsub(/`/, "", task_label)
    gsub(/[*#]/, "", task_label)
    gsub(/[[:space:]]+/, " ", task_label)
    task_label=trim(task_label)
    task_marker="○ "
    if (task ~ /^- \[[xX]\]/) task_marker="🟢"
    # Open-task blocked status is resolved in the shell consumer via
    # mark_open() (dependency-aware), not by a substring match here.
    print phase "\t" task_marker "\t" task_label >> details
    total++
    if ($0 ~ /^- \[[xX]\]/) done++
  }
}
END { emit() }
' "$tasks_file"

mvp_done="$(awk -F '\t' '$1=="MVP"{d+=$3} END{print d+0}' "$phase_file")"
mvp_total="$(awk -F '\t' '$1=="MVP"{t+=$4} END{print t+0}' "$phase_file")"
post_done="$(awk -F '\t' '$1=="POST"{d+=$3} END{print d+0}' "$phase_file")"
post_total="$(awk -F '\t' '$1=="POST"{t+=$4} END{print t+0}' "$phase_file")"
phase_total=$(( mvp_total + post_total ))
phase_done=$(( mvp_done + post_done ))
phase_pct="$(percent "$phase_done" "$phase_total")"

latest_label="${last_command}"
[ "$latest_label" = "repo scan" ] && latest_label="$prompt_summary"
if [ "$last_command" = "git status" ]; then
  latest_label="$git_summary"
  workflow_gate="repo status"
elif [ "$last_command" = "repo scan" ]; then
  workflow_gate="repo scan"
else
  workflow_gate="${last_command#/}"
  workflow_gate="${workflow_gate#speckit.}"
  [ -n "$workflow_gate" ] || workflow_gate="implement"
fi

{
  printf '══════════════════════════════════════════════════════════════\n'
  printf ' Opensoft Speckit Dashboard\n'
  printf '══════════════════════════════════════════════════════════════\n'
  printf ' RECENT ACTIVITY             latest: %s\n' "$latest_label"
  if [ "$history_just_ran" = "1" ]; then
    tail -8 "$ROOT/.claude/speckit-history.md" 2>/dev/null | grep -E '^[0-9]+' | tail -3 \
      | sed '$s/$/ 🔵 just ran/; s/^/   /' || true
  else
    tail -8 "$ROOT/.claude/speckit-history.md" 2>/dev/null | grep -E '^[0-9]+' | tail -3 \
      | sed 's/^/   /' || true
  fi
  printf '──────────────────────────────────────────────────────────────\n'
  printf ' SPEC KIT WORKFLOW           ▶ %s %s%%\n' "$workflow_gate" "$task_pct"
  printf '      command                %%done  runs\n'
  printf '   🟢 /speckit.constitution    100%%   1\n'
  printf '   🟢 /speckit.specify         100%%   1\n'
  printf '   🟢 /speckit.clarify         100%%   1\n'
  printf '   🟢 /speckit.checklist       100%%   1   (pre-plan)\n'
  printf '   🟢 /speckit.plan            100%%   1\n'
  printf '   🟢 /speckit.checklist       100%%   1   (post-plan)\n'
  printf '   🟢 /speckit.tasks           100%%   1\n'
  printf '   🟢 /speckit.checklist       100%%   1   (post-tasks)\n'
  if [ "$last_command" = "/speckit.analyze" ]; then
    printf '   🔵 /speckit.analyze         100%%   ?   ◀ just ran ✅\n'
  else
    printf '   🟢 /speckit.analyze         100%%   ?\n'
  fi
  printf '   ○  /speckit.checklist         0%%   0   (post-analyze)\n'
  if [ "$task_total" -gt 0 ] && [ "$task_done" -eq "$task_total" ]; then
    impl_dot='🟢'
  else
    impl_dot='🔵'
  fi
  if [ "$last_command" = "/speckit.implement" ]; then
    printf '   %s /speckit.implement       %3s%%   ?   ◀ just ran ✅\n' "$impl_dot" "$task_pct"
  else
    printf '   %s /speckit.implement       %3s%%   ?\n' "$impl_dot" "$task_pct"
  fi
  pull_request_workflow_row
  printf '──────────────────────────────────────────────────────────────\n'
  printf ' TASKS                                        %s/%s done · %s%%\n' "$task_done" "$task_total" "$task_pct"
  printf '   %s\n' "$task_bar"
  while IFS= read -r line; do
    marker="$(mark_open "$line")"
    printf '   %s %s\n' "$marker" "$(printf '%s\n' "$line" | task_title)"
  done < "$tmp_open"
  if [ "$open_more" -gt 5 ]; then
    printf '   … +%s more open\n' $(( open_more - 5 ))
  fi
  printf '   🟢 done:  %s tasks complete\n' "$task_done"
  printf '──────────────────────────────────────────────────────────────\n'
  printf ' PHASES — %s         %s/%s · %s%%\n' "$feature_name" "$phase_done" "$phase_total" "$phase_pct"
  if [ "$mvp_total" -gt 0 ]; then
    printf '   🎯 MVP ─────────────────────────────────────  %s/%s\n' "$mvp_done" "$mvp_total"
    awk -F '\t' '$1=="MVP"{print $2 "\t" $3 "\t" $4}' "$phase_file" | while IFS=$'\t' read -r name done total; do
      if [ "$done" -eq "$total" ]; then marker='🟢'; else marker='🔵'; fi
      printf '   %s %-13s %s  %s/%s\n' "$marker" "$name" "$(bar_fixed "$done" "$total" 24)" "$done" "$total"
      awk -F '\t' -v phase="$name" '$1==phase{print $2 "\t" $3}' "$phase_tasks_file" \
        | while IFS=$'\t' read -r task_marker task_name; do
            [ "$task_marker" = "🟢" ] || task_marker="$(mark_open "$task_name")"
            printf '      %s %s\n' "$task_marker" "$(printf '%s\n' "$task_name" | task_title 48)"
          done
    done
  fi
  if [ "$post_total" -gt 0 ]; then
    printf '   🛡 Post-MVP ────────────────────────────────  %s/%s\n' "$post_done" "$post_total"
    awk -F '\t' '$1=="POST"{print $2 "\t" $3 "\t" $4}' "$phase_file" | while IFS=$'\t' read -r name done total; do
      if [ "$done" -eq "$total" ]; then marker='🟢'; elif [ "$done" -gt 0 ]; then marker='🔵'; else marker='○ '; fi
      printf '   %s %-13s %s  %s/%s\n' "$marker" "$name" "$(bar_fixed "$done" "$total" 24)" "$done" "$total"
      awk -F '\t' -v phase="$name" '$1==phase{print $2 "\t" $3}' "$phase_tasks_file" \
        | while IFS=$'\t' read -r task_marker task_name; do
            [ "$task_marker" = "🟢" ] || task_marker="$(mark_open "$task_name")"
            printf '      %s %s\n' "$task_marker" "$(printf '%s\n' "$task_name" | task_title 48)"
          done
    done
  fi
  printf '──────────────────────────────────────────────────────────────\n'
  printf ' PROMPTS                     %s\n' "$prompt_summary"
  if [ -n "$prompt_lines" ]; then
    printf '%s\n' "$prompt_lines" | sed 's/^/   /'
  else
    printf '   (none yet this cta session)\n'
  fi
  printf '──────────────────────────────────────────────────────────────\n'
  printf ' NEXT COMMANDS               ⭐ next open task / remediation\n'
  first_open="$(head -1 "$tmp_open" | task_title 32)"
  if [ -n "$first_open" ]; then
    printf '   ⭐ /speckit.implement %s\n' "$first_open"
  else
    printf '   ⭐ git status              verify clean feature state\n'
  fi
  printf '      /speckit.analyze         rerun after edits land\n'
  printf '══════════════════════════════════════════════════════════════\n'
} > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"

rm -f "$tmp_open" "$phase_file" "$phase_tasks_file"
