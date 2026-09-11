#!/usr/bin/env bash
# UserPromptSubmit hook — usage/context guard.
#
# Reads the snapshot published by statusline-command.sh (the only surface that
# receives rate_limits/context_window from the harness) and injects ONE line
# into the model's context when a threshold is newly crossed.
#
# Three properties, by design:
#   GATED   — silent unless .claude/usage-guard.on exists in the session's cwd
#             or ANY ancestor up to $HOME (or ~/.claude/usage-guard.on for all
#             sessions). Off = zero context cost.
#   LATCHED — each (session, metric, threshold) warns ONCE, so a long session
#             costs ~3 short lines instead of one per prompt.
#   FAIL-QUIET — any missing input, stale snapshot, or error prints nothing.
#               A broken guard must never disrupt a session.
set -uo pipefail

SNAP_DIR="$HOME/.claude/usage-snapshots"
LATCH_DIR="$HOME/.claude/usage-latch"
MAX_AGE=600   # seconds; older snapshot is treated as absent, not trusted

input=$(cat 2>/dev/null || true)
cwd=$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null || true)
sid=$(jq -r '.session_id // "nosession"' <<<"$input" 2>/dev/null || echo nosession)

# --- gate ---
# Armed by a flag file, found by walking UP from the session's cwd: arming a
# repo root therefore covers every session whose cwd is inside it (including
# submodules under an armed aggregation root). Sibling worktree containers are
# NOT inside the repo, so they need their own flag. $HOME/.claude/usage-guard.on
# arms everything.
on=0
d="$cwd"
while [ -n "$d" ] && [ "$d" != "/" ] && [ "$d" != "." ]; do
    if [ -f "$d/.claude/usage-guard.on" ]; then on=1; break; fi
    [ "$d" = "$HOME" ] && break
    d=$(dirname "$d")
done
[ -f "$HOME/.claude/usage-guard.on" ] && on=1
[ "$on" -eq 1 ] || exit 0

# Rate limits are account-scoped (profile-keyed, shared by every sibling
# session on that CLAUDE_CONFIG_DIR); context is session-scoped (each
# conversation's own window). Read independently so a stale/missing file on
# one side never hides fresh data on the other.
profile_key=$(printf '%s' "${CLAUDE_CONFIG_DIR:-default}" | sed 's/[^A-Za-z0-9._-]/_/g')
PROFILE_SNAP="$SNAP_DIR/profile.$profile_key.json"
SESSION_SNAP="$SNAP_DIR/session.$sid.json"

# prune snapshots from sessions/profiles that went idle (>1 day), bounded and quiet
find "$SNAP_DIR" -maxdepth 1 -name '*.json' -mtime +1 -delete 2>/dev/null || true

mkdir -p "$LATCH_DIR" 2>/dev/null || exit 0

fresh() {
  local f="$1" now mtime
  [ -r "$f" ] || return 1
  now=$(date +%s)
  mtime=$(stat -c %Y "$f" 2>/dev/null || echo 0)
  [ $((now - mtime)) -le "$MAX_AGE" ]
}

five=null; fivereset=null; fable=null; fablereset=null; ctx=null
if fresh "$PROFILE_SNAP"; then
  read -r five fivereset fable fablereset < <(
    jq -r '[(.five_hour//"null"),(.five_hour_reset//"null"),
            (.fable_weekly//"null"),(.fable_weekly_reset//"null")] | @tsv' "$PROFILE_SNAP" 2>/dev/null \
      || echo "null null null null"
  )
fi
if fresh "$SESSION_SNAP"; then
  ctx=$(jq -r '.context_pct // "null"' "$SESSION_SNAP" 2>/dev/null || echo null)
fi
[ "$five" = null ] && [ "$fable" = null ] && [ "$ctx" = null ] && exit 0

# highest crossed threshold for a value, given a descending list
crossed() {
  local val="$1"; shift
  [ -n "$val" ] && [ "$val" != "null" ] || return 1
  local t
  for t in "$@"; do
    if awk -v v="$val" -v t="$t" 'BEGIN{exit !(v+0 >= t+0)}'; then echo "$t"; return 0; fi
  done
  return 1
}

# emit once per (session, metric, threshold)
latched_warn() {
  local metric="$1" thresh="$2" msg="$3"
  local f="$LATCH_DIR/${sid}.${metric}.${thresh}"
  [ -e "$f" ] && return 0
  : > "$f" 2>/dev/null || return 0
  printf '%s\n' "$msg"
}

hhmm() { [ -n "${1:-}" ] && [ "$1" != "null" ] && date -u -d "@$1" +%H:%MZ 2>/dev/null || echo "unknown"; }

out=""
if t=$(crossed "$five" 95 90 80); then
  case "$t" in
    95) out+="⚠ 5-HOUR WINDOW AT ${five}% (resets $(hhmm "$fivereset")). Per global CLAUDE.md: STOP at a breakpoint, write or refresh the handoff doc, then small tasks only.";;
    90) out+="⚠ 5-hour window at ${five}% (resets $(hhmm "$fivereset")). Approaching the 95% stop line — plan a breakpoint and get the handoff current.";;
    80) out+="Note: 5-hour window at ${five}% (resets $(hhmm "$fivereset")). Delegate writing to Opus/Sonnet subagents; keep judgment in the main loop.";;
  esac
  latched_warn five "$t" "$out"; out=""
fi
if t=$(crossed "$fable" 95 90 80); then
  case "$t" in
    95) out+="⚠ FABLE WEEKLY BUCKET AT ${fable}% (resets $(hhmm "$fablereset")). Per global CLAUDE.md: STOP at a breakpoint, refresh the handoff, small tasks only.";;
    90) out+="⚠ Fable weekly bucket at ${fable}% (resets $(hhmm "$fablereset")). Approaching the 95% stop line.";;
    80) out+="Note: Fable weekly bucket at ${fable}% — this is the scarcest budget. Delegate writing to subagents.";;
  esac
  latched_warn fable "$t" "$out"; out=""
fi
if t=$(crossed "$ctx" 95 85 70); then
  case "$t" in
    95) out+="⚠ CONTEXT AT ${ctx}% — compaction is imminent. Land or record anything unsaved and refresh the handoff NOW.";;
    85) out+="⚠ Context at ${ctx}%. Stop reading whole files into the main loop; send investigation to subagents.";;
    70) out+="Note: context at ${ctx}%. Prefer subagents for file reading and writing from here.";;
  esac
  latched_warn ctx "$t" "$out"
fi
exit 0
