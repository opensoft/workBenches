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
#
# Since lane-collision-protocol Amendment 11(4) the 5-hour window's 95% line is
# also the AUTOMATIC SWAP: it directs the session to run `/lane-swap` there and
# then, with no question to the operator. See auto_swap_directive below — the
# hook still only prints, and all three properties above hold over it.
#
# WHAT IT READS IS WHAT `claude-usage` READS. Both this hook and the
# `claude-usage` command (opensoft/brett-wip, `~/.local/bin/claude-usage`) read
# the same profile-keyed snapshot the status line publishes, with the same
# 600-second freshness rule and the same buckets, so the guard's 95% and
# `claude-usage`'s STOP verdict (its exit 2, "the current profile's max
# available bucket is >= 95") are the same line by construction. The command is
# never invoked here: it would be a second process reading the same file, on
# the path of every prompt, and a guard that depended on a command being
# installed would go silent on a workstation that has not installed it.
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

# THE AUTOMATIC SWAP — lane-collision-protocol Amendment 11(4), SPEC §9.
#
# The 95% line used to end "STOP at a breakpoint, write or refresh the handoff
# doc, then small tasks only" — advice, addressed to a session that then had to
# work out for itself what the estate wanted. It is now a DIRECTIVE, and the
# thing it directs is the act Amendment 8(a) already defines end to end:
# `/lane-swap`. The operator is asked nothing and answers nothing; their whole
# part in the restart is re-running `pclaude <profile>`.
#
# THE GUARD DOES NOT PERFORM THE SWAP, and that is ruled rather than convenient.
# This is a UserPromptSubmit hook: it runs in front of every prompt, it is
# bounded by the entry's 5-second timeout, and its three properties — gated,
# latched, fail-quiet — exist because a hook that disrupts a session is worse
# than no hook. The swap is five steps, two of which (refreshing the handoff's
# prose and telling every running writer to push) need a model, and two of
# which (the object-log PAUSED line, the register's event line and row) fetch,
# commit and push. None of that belongs behind a keystroke. So the hook does
# the one thing a hook can do well — put the right instruction in front of the
# session at the right instant — and the session does the act.
#
# The directive names `/lane-swap` by its canonical name and `/swap` as its
# alias, because the session may have either installed, and it names the one
# fact the skill cannot derive from inside a hook: that nobody is being asked.
auto_swap_directive() {
  local pct="$1" reset="$2"
  printf '%s' "⚠ 5-HOUR WINDOW AT ${pct}% (resets ${reset}). AUTOMATIC SWAP (lane-collision-protocol Amendment 11(4)): run /lane-swap (alias /swap) NOW, every step in order, and do not ask the operator whether to — the 95% breakpoint is the decision. Bound step 3's wait on the writers: name any writer still holding unpushed work in the handoff and proceed, killing nothing and pushing nobody's work. The swap record it writes is what the next launch resolves this lane from, so it is never left unwritten. Then print the one restart command — pclaude ${CLAUDE_PROFILE_NAME:-<profile>} — and stop."
}

out=""
if t=$(crossed "$five" 95 90 80); then
  case "$t" in
    95) out+="$(auto_swap_directive "$five" "$(hhmm "$fivereset")")";;
    90) out+="⚠ 5-hour window at ${five}% (resets $(hhmm "$fivereset")). Approaching the 95% stop line — plan a breakpoint and get the handoff current.";;
    80) out+="Note: 5-hour window at ${five}% (resets $(hhmm "$fivereset")). Delegate writing to Opus/Sonnet subagents; keep judgment in the main loop.";;
  esac
  latched_warn five "$t" "$out"; out=""
fi
# THE FABLE WEEKLY BUCKET'S OWN 95% IS NOT AN AUTOMATIC SWAP, and is left at
# today's warning DELIBERATELY (SPEC §9, marked Open). The two buckets do not
# mean the same thing when they run out: the 5-hour window refills in hours, so
# a swap parks the lane and the operator comes back to it; the weekly bucket
# does not, and a swap that fires on it would pause a lane with nothing on the
# other side of the pause. Until that is ruled, this line says what it always
# said.
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
