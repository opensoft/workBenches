#!/usr/bin/env bash
# Regression tests for claude-usage-guard.sh's AUTOMATIC SWAP — lane-collision
# -protocol Amendment 11(4), SPEC §9 (brettheap/new-workstation#20).
#
# Before this amendment the guard's top five-hour line was ADVICE: at >=95% it
# told the session to "STOP at a breakpoint, write or refresh the handoff doc,
# then small tasks only" and left the session to work out what that meant.
# SPEC §9 turns that one line into a DIRECTIVE — run /lane-swap (alias
# /swap), now, no question asked — and rules, in the same breath, that the
# guard itself performs none of the swap: "it cannot act, it can only put one
# line into the session's context" (claude-usage-guard.sh:122-131). Four
# properties are pinned here, against the real script and real jq/date/awk:
#
#   DIRECTIVE   at five_hour>=95 the printed line names /lane-swap and /swap,
#               says the operator is asked nothing, and ends with the single
#               restart command (pclaude <profile>) — never the old advice.
#   UNCHANGED   90-94% and 80-89% keep today's advice/note lines and carry
#               neither the directive's language nor the word `pclaude`; a
#               guard that swapped below the breakpoint would pause a lane
#               that is still working, which is the mutation that matters.
#   PRINTS,     the guard never shells out to perform the swap it names —
#   NEVER ACTS  fakes for every binary the swap needs sit at the front of
#               PATH and log their own invocations, so a >=95 run that
#               touches any of them, or writes anywhing under $HOME/projects
#               or any other register, is caught rather than assumed absent.
#   GATED /     the three properties the guard already had (header comment,
#   LATCHED /   claude-usage-guard.sh:8-15) still hold with the directive
#   FAIL-QUIET  wired in: silent with no .claude/usage-guard.on anywhere
#               (SPEC §0.6 measured exactly this miss on the lane Brett
#               cited), one warning per (session, metric, threshold), and
#               silent on any malformed input or stale/missing snapshot.
#
# The Fable weekly bucket's own 95% is left as SPEC §9 leaves it — "Open",
# today's plain warning, deliberately not an automatic swap, because the
# weekly bucket does not refill in hours the way the five-hour window does —
# and the context thresholds (95/85/70) are untouched by this amendment
# entirely, both pinned below.
#
# Snapshot shape mirrors test-claude-statusline-snapshots.sh, which tests the
# writer of these same files: $HOME/.claude/usage-snapshots/profile.<key>.json
# (five_hour, five_hour_reset, fable_weekly, fable_weekly_reset) keyed on
# CLAUDE_CONFIG_DIR (sed 's/[^A-Za-z0-9._-]/_/g', "default" when unset), and
# session.<sid>.json (context_pct).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GUARD="${1:-$REPO_ROOT/base-image/files/claude-usage-guard.sh}"

# This profile session itself exports CLAUDE_CONFIG_DIR, CLAUDE_PROFILE_NAME
# and runs inside TMUX. Forgetting to unset the first of those once already
# made a suite like this one silently vacuous: every scenario below writes its
# snapshot at the key it computes for the CLAUDE_CONFIG_DIR IT sets (usually
# unset, i.e. "default"), and an ambient value leaking through would make the
# guard look for a snapshot at a completely different path, finding nothing,
# forever — see the CLAUDE_CONFIG_DIR MANGLING scenario below, which is the
# one built to fail loudly if this line is ever removed.
unset CLAUDE_CONFIG_DIR CLAUDE_PROFILE_NAME TMUX WORKBENCHES_CLAUDE_LANE 2>/dev/null || true

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

# A scenario is one invocation of the guard (one JSON payload on its stdin);
# an assertion is one check made about the result. EXPECTED_SCENARIOS is
# pinned, as in test-claude-profile-lane-default.sh, so a scenario silently
# dropped (or a run that quietly stopped happening) fails the suite instead of
# just shrinking a number nobody reads.
EXPECTED_SCENARIOS=22
scenarios=0
assertions=0
scenario() { scenarios=$((scenarios + 1)); }
assertion() { assertions=$((assertions + 1)); }

# ---------------------------------------------------------------------------
# Fixture plumbing.

# A fresh $HOME, isolated from every other scenario's. GATED and LATCHED are
# both stateful (a flag file; a per-session latch), so scenarios that must not
# see each other's state each get their own $HOME rather than sharing one and
# resetting parts of it by hand. mktemp's own uniqueness is used rather than a
# counter variable: several callers below invoke this through `< <(...)` or
# `$(...)`, which fork a subshell, and a counter incremented inside a subshell
# never makes it back to the parent — every "fresh" home would silently
# collapse onto the same directory (verified: it did, before this fix).
fresh_home() {
    mktemp -d "$TEST_ROOT/home-XXXXXX"
}

# Mirrors claude-usage-guard.sh's own profile_key derivation (line 61),
# independently rather than by sourcing it, so this test can compute the exact
# path the guard will look at before the guard ever runs.
profile_key() {
    printf '%s' "${1:-default}" | sed 's/[^A-Za-z0-9._-]/_/g'
}

# Arms a directory exactly the way SPEC §9's "Arming" clause has lane-start do
# it: mkdir -p <dir>/.claude, touch <dir>/.claude/usage-guard.on. Every scenario
# below arms the lane's OWN directory rather than $HOME/.claude/usage-guard.on
# (which arms every session) — that is the realistic mechanism, it is the one
# SPEC §9 spells out, and it is what makes the DISARMED scenario's absence of
# any usage-guard.on file meaningful rather than incidental.
arm() {
    mkdir -p "$1/.claude"
    : > "$1/.claude/usage-guard.on"
}

# A fresh, armed lane directory: <home>/projects/openRepoProject, matching the
# SPEC's own worked examples (§5's swap record, §0.6's live measurement).
# Prints "<home> <cwd>" so callers do `read -r H CWD < <(new_lane)`.
new_lane() {
    local home cwd
    home=$(fresh_home)
    cwd="$home/projects/openRepoProject"
    mkdir -p "$cwd"
    arm "$cwd"
    printf '%s %s\n' "$home" "$cwd"
}

# Writes $home/.claude/usage-snapshots/profile.<key(cfgdir)>.json, the file
# statusline-command.sh publishes and this guard reads (fresh() + 600s rule).
# `five`/`fable`/their resets are passed straight to jq --argjson, so "null"
# (the bare JSON token) means absent and a bare integer means present —
# exactly the shape the guard's own `// "null"` jq filters expect.
write_profile_snapshot() {
    local home="$1" cfgdir="$2" five="$3" five_reset="$4" fable="$5" fable_reset="$6"
    local key dir
    key=$(profile_key "$cfgdir")
    dir="$home/.claude/usage-snapshots"
    mkdir -p "$dir"
    jq -n --argjson five "$five" --argjson five_reset "$five_reset" \
        --argjson fable "$fable" --argjson fable_reset "$fable_reset" \
        '{five_hour:$five, five_hour_reset:$five_reset,
          fable_weekly:$fable, fable_weekly_reset:$fable_reset}' \
        > "$dir/profile.$key.json"
    printf '%s' "$dir/profile.$key.json"
}

write_session_snapshot() {
    local home="$1" sid="$2" ctx="$3"
    local dir="$home/.claude/usage-snapshots"
    mkdir -p "$dir"
    jq -n --argjson ctx "$ctx" '{context_pct:$ctx}' > "$dir/session.$sid.json"
}

# claude-usage, lanes-edit.sh, lane-start, tmux and git are every binary
# Amendment 8(a)'s five swap steps touch (SPEC §9's "steps... unchanged").
# Each fake logs its own argv and does nothing else; PATH puts them ahead of
# /usr/bin so a guard that shelled out to any of them would be caught, not
# silently succeed against the real thing.
FAKE_BIN="$TEST_ROOT/bin"
mkdir -p "$FAKE_BIN"
SHELLOUT_CLAUDE_USAGE_LOG="$TEST_ROOT/shellout-claude-usage.log"
SHELLOUT_LANES_EDIT_LOG="$TEST_ROOT/shellout-lanes-edit.log"
SHELLOUT_LANE_START_LOG="$TEST_ROOT/shellout-lane-start.log"
SHELLOUT_TMUX_LOG="$TEST_ROOT/shellout-tmux.log"
SHELLOUT_GIT_LOG="$TEST_ROOT/shellout-git.log"

cat > "$FAKE_BIN/claude-usage" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${SHELLOUT_CLAUDE_USAGE_LOG:?}"
EOF
cat > "$FAKE_BIN/lanes-edit.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${SHELLOUT_LANES_EDIT_LOG:?}"
EOF
cat > "$FAKE_BIN/lane-start" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${SHELLOUT_LANE_START_LOG:?}"
EOF
cat > "$FAKE_BIN/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${SHELLOUT_TMUX_LOG:?}"
EOF
cat > "$FAKE_BIN/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${SHELLOUT_GIT_LOG:?}"
EOF
chmod +x "$FAKE_BIN/claude-usage" "$FAKE_BIN/lanes-edit.sh" "$FAKE_BIN/lane-start" \
    "$FAKE_BIN/tmux" "$FAKE_BIN/git"

# PATH carries the fakes and nothing else that could answer for them (the
# same discipline test-claude-profile-lane-default.sh uses): a real
# lane-start/lanes-edit.sh/tmux/git installed on the workstation running this
# suite must not be reachable from inside a guard invocation.
common_env=(
    "PATH=$FAKE_BIN:/usr/bin:/bin"
    # THE SESSION HOLDS A LANE unless a scenario says otherwise. SPEC §9 (A11
    # Addendum 1 `R-A11-6`, on the review's F14) fences the automatic-swap
    # DIRECTIVE to a session that holds one, and `WORKBENCHES_CLAUDE_LANE` is
    # the fence: claude-profile exports it only after lane-start took the lane
    # and unsets it again where lane-start declined. The directive is the
    # ordinary case for this suite, so it is the default here, and the
    # scenarios about the fence itself override it with an empty value — which
    # is exactly what a bare `claude` in an armed checkout carries.
    "WORKBENCHES_CLAUDE_LANE=swaptest-1"
    "SHELLOUT_CLAUDE_USAGE_LOG=$SHELLOUT_CLAUDE_USAGE_LOG"
    "SHELLOUT_LANES_EDIT_LOG=$SHELLOUT_LANES_EDIT_LOG"
    "SHELLOUT_LANE_START_LOG=$SHELLOUT_LANE_START_LOG"
    "SHELLOUT_TMUX_LOG=$SHELLOUT_TMUX_LOG"
    "SHELLOUT_GIT_LOG=$SHELLOUT_GIT_LOG"
)

GUARD_ERR_FILE="$TEST_ROOT/guard-stderr.log"

# run_guard_raw <home> <stdin-content> [env assignments...]
# Feeds <stdin-content> verbatim to the guard — used directly by the
# fail-quiet scenarios that need to hand it something other than well-formed
# JSON. Sets guard_out/guard_status/guard_err for the caller to assert on.
run_guard_raw() {
    local home="$1" stdin_content="$2"; shift 2
    scenario
    set +e
    guard_out=$(env "${common_env[@]}" HOME="$home" "$@" bash "$GUARD" \
        <<<"$stdin_content" 2>"$GUARD_ERR_FILE")
    guard_status=$?
    set -e
    guard_err=$(cat "$GUARD_ERR_FILE" 2>/dev/null || true)
}

# run_guard <home> <cwd> <sid> [env assignments...]
# The normal path: builds the {"cwd":...,"session_id":...} payload the hook
# actually receives from the harness and hands it to run_guard_raw.
run_guard() {
    local home="$1" cwd="$2" sid="$3"; shift 3
    local payload
    payload=$(jq -nc --arg cwd "$cwd" --arg sid "$sid" '{cwd:$cwd, session_id:$sid}')
    run_guard_raw "$home" "$payload" "$@"
}

# A fixed five-hour reset instant, formatted through the exact command the
# guard's own hhmm() uses (claude-usage-guard.sh:111) rather than a hand-typed
# clock string, so this test can never drift out of sync with a TZ change.
FIVE_RESET_EPOCH=1999999000
FIVE_RESET_HHMM=$(date -u -d "@$FIVE_RESET_EPOCH" +%H:%MZ)
FABLE_RESET_EPOCH=1988888000

# ---------------------------------------------------------------------------
# 0. CLAUDE_CONFIG_DIR MANGLING. A real $CLAUDE_CONFIG_DIR is a filesystem
# path, full of slashes — "default" (what every other scenario below uses)
# has nothing in it that sed's character class would ever touch, so it cannot
# catch a mangling regression, and it would not have caught the ambient-leak
# mistake described at the top of this file either (the ambient value is
# itself slash-shaped and ALSO not "default"). This scenario is: a
# CLAUDE_CONFIG_DIR shaped like the real thing, a snapshot written at this
# test's OWN independent mirror of the guard's sed transform, and an
# assertion that the guard found it there.
read -r CFG_HOME CFG_CWD < <(new_lane)
CFG_VALUE="$CFG_HOME/profiles/opensoft/team/team-mangle"
write_profile_snapshot "$CFG_HOME" "$CFG_VALUE" 96 "$FIVE_RESET_EPOCH" null null >/dev/null
run_guard "$CFG_HOME" "$CFG_CWD" "sid-cfgdir" "CLAUDE_CONFIG_DIR=$CFG_VALUE"
grep -qF '/lane-swap' <<<"$guard_out" \
    || fail "CLAUDE_CONFIG_DIR mangling: no output for profile_key('$CFG_VALUE')=$(profile_key "$CFG_VALUE") — either this test's mirror of sed 's/[^A-Za-z0-9._-]/_/g' and the guard's own have drifted apart, or an ambient CLAUDE_CONFIG_DIR leaked into this run (out=[$guard_out])"; assertion
[[ "$guard_status" -eq 0 ]] \
    || fail "CLAUDE_CONFIG_DIR mangling: exited $guard_status instead of 0"; assertion

# ---------------------------------------------------------------------------
# 1. THE AUTOMATIC SWAP DIRECTIVE — Amendment 11(4)/SPEC §9's whole point. At
# five_hour>=95 the top line names /lane-swap (canonical) and /swap (SPEC §9's
# one-line command-file alias), says outright that the operator is asked
# nothing, and closes with the single restart command — pclaude, with
# CLAUDE_PROFILE_NAME substituted in, never left as the literal placeholder,
# because that command is the operator's entire remaining part in the
# restart. The OLD wording ("STOP at a breakpoint, write or refresh the
# handoff doc, then small tasks only") must be gone: this is a directive now,
# not advice for the session to interpret.
read -r DIR_HOME DIR_CWD < <(new_lane)
write_profile_snapshot "$DIR_HOME" "" 96 "$FIVE_RESET_EPOCH" null null >/dev/null
run_guard "$DIR_HOME" "$DIR_CWD" "sid-directive" "CLAUDE_PROFILE_NAME=team-swaptest"
[[ -n "$guard_out" ]] \
    || fail "directive: a 96% five-hour window with the guard armed printed nothing"; assertion
grep -qF '5-HOUR WINDOW AT 96%' <<<"$guard_out" \
    || fail "directive: the percentage did not appear verbatim (out=[$guard_out])"; assertion
grep -qF "resets ${FIVE_RESET_HHMM}" <<<"$guard_out" \
    || fail "directive: the reset time did not appear as hh:mmZ (out=[$guard_out])"; assertion
grep -qF '/lane-swap' <<<"$guard_out" \
    || fail "directive: /lane-swap was not named (out=[$guard_out])"; assertion
grep -qF '/swap' <<<"$guard_out" \
    || fail "directive: /swap was not named as the alias (out=[$guard_out])"; assertion
grep -qF 'do not ask the operator' <<<"$guard_out" \
    || fail "directive: it did not say the operator is asked nothing (out=[$guard_out])"; assertion
grep -qF 'pclaude team-swaptest' <<<"$guard_out" \
    || fail "directive: CLAUDE_PROFILE_NAME was not substituted into the restart command (out=[$guard_out])"; assertion
grep -qF 'STOP at a breakpoint, write or refresh the handoff doc' <<<"$guard_out" \
    && fail "directive: the OLD advice wording is still there (out=[$guard_out])"; assertion
[[ "$(wc -l <<<"$guard_out")" -eq 1 ]] \
    || fail "directive: printed $(wc -l <<<"$guard_out") lines instead of one (out=[$guard_out])"; assertion
[[ -z "$guard_err" ]] \
    || fail "directive: stderr was not empty (err=[$guard_err])"; assertion
[[ "$guard_status" -eq 0 ]] \
    || fail "directive: exited $guard_status instead of 0"; assertion

# ---------------------------------------------------------------------------
# 2. 90-94% KEEPS TODAY'S ADVICE, NOT THE DIRECTIVE. This is the mutation that
# matters most in the whole suite: a guard that fired the automatic swap
# below the 95% breakpoint would pause a lane that has not earned a swap yet.
read -r ADV_HOME ADV_CWD < <(new_lane)
write_profile_snapshot "$ADV_HOME" "" 92 "$FIVE_RESET_EPOCH" null null >/dev/null
run_guard "$ADV_HOME" "$ADV_CWD" "sid-advice90"
grep -qF 'Approaching the 95% stop line' <<<"$guard_out" \
    || fail "90%: the advice line did not appear (out=[$guard_out])"; assertion
grep -qF '/lane-swap' <<<"$guard_out" \
    && fail "90%: the directive fired BELOW the 95% breakpoint (out=[$guard_out])"; assertion
grep -qF 'AUTOMATIC SWAP' <<<"$guard_out" \
    && fail "90%: the AUTOMATIC SWAP label appeared below the breakpoint (out=[$guard_out])"; assertion
grep -qF 'pclaude' <<<"$guard_out" \
    && fail "90%: a restart command appeared below the breakpoint (out=[$guard_out])"; assertion
[[ "$(wc -l <<<"$guard_out")" -eq 1 ]] \
    || fail "90%: printed $(wc -l <<<"$guard_out") lines instead of one (out=[$guard_out])"; assertion
[[ "$guard_status" -eq 0 ]] \
    || fail "90%: exited $guard_status instead of 0"; assertion

# 2b. 80-89%: the lowest note, same requirement, same reason.
read -r NOTE_HOME NOTE_CWD < <(new_lane)
write_profile_snapshot "$NOTE_HOME" "" 83 "$FIVE_RESET_EPOCH" null null >/dev/null
run_guard "$NOTE_HOME" "$NOTE_CWD" "sid-note80"
grep -qF 'Delegate writing to Opus/Sonnet subagents' <<<"$guard_out" \
    || fail "80%: the note line did not appear (out=[$guard_out])"; assertion
grep -qF '/lane-swap' <<<"$guard_out" \
    && fail "80%: the directive fired at the lowest note threshold (out=[$guard_out])"; assertion
grep -qF 'pclaude' <<<"$guard_out" \
    && fail "80%: a restart command appeared at the lowest note threshold (out=[$guard_out])"; assertion
[[ "$guard_status" -eq 0 ]] \
    || fail "80%: exited $guard_status instead of 0"; assertion

# ---------------------------------------------------------------------------
# 3. MUTATION — SPEC §9: "the guard cannot act, it can only put one line into
# the session's context." Fakes for every binary Amendment 8(a)'s five swap
# steps need stand at the front of PATH; grepping the guard's own source
# confirms it never names tmux, git, lane-start or lanes-edit.sh anywhere and
# mentions claude-usage only in a comment (never invokes it) — this scenario
# is the live proof, not just the static one. Nothing may appear under
# $HOME/projects (where a real swap's dir/register writes would land) or
# anywhere else in $HOME but the guard's own latch file.
read -r MUT_HOME MUT_CWD < <(new_lane)
write_profile_snapshot "$MUT_HOME" "" 97 "$FIVE_RESET_EPOCH" null null >/dev/null
rm -f "$SHELLOUT_CLAUDE_USAGE_LOG" "$SHELLOUT_LANES_EDIT_LOG" "$SHELLOUT_LANE_START_LOG" \
    "$SHELLOUT_TMUX_LOG" "$SHELLOUT_GIT_LOG"
before_projects="$(find "$MUT_HOME/projects" -type f | sort)"
before_home="$(cd "$MUT_HOME" && find . -type f | sort)"
run_guard "$MUT_HOME" "$MUT_CWD" "sid-mutation"
[[ -n "$guard_out" ]] \
    || fail "mutation: the >=95 run this scenario depends on produced no output at all"; assertion
grep -qF '/lane-swap' <<<"$guard_out" \
    || fail "mutation: the run under test was not actually on the directive path (out=[$guard_out])"; assertion
[[ ! -e "$SHELLOUT_CLAUDE_USAGE_LOG" ]] \
    || fail "mutation: the guard shelled out to claude-usage ($(cat "$SHELLOUT_CLAUDE_USAGE_LOG"))"; assertion
[[ ! -e "$SHELLOUT_LANES_EDIT_LOG" ]] \
    || fail "mutation: the guard shelled out to lanes-edit.sh ($(cat "$SHELLOUT_LANES_EDIT_LOG"))"; assertion
[[ ! -e "$SHELLOUT_LANE_START_LOG" ]] \
    || fail "mutation: the guard shelled out to lane-start ($(cat "$SHELLOUT_LANE_START_LOG"))"; assertion
[[ ! -e "$SHELLOUT_TMUX_LOG" ]] \
    || fail "mutation: the guard shelled out to tmux ($(cat "$SHELLOUT_TMUX_LOG"))"; assertion
[[ ! -e "$SHELLOUT_GIT_LOG" ]] \
    || fail "mutation: the guard shelled out to git ($(cat "$SHELLOUT_GIT_LOG"))"; assertion
after_projects="$(find "$MUT_HOME/projects" -type f | sort)"
[[ "$before_projects" == "$after_projects" ]] \
    || fail "mutation: \$HOME/projects changed during the run (before=[$before_projects] after=[$after_projects])"; assertion
after_home="$(cd "$MUT_HOME" && find . -type f | sort)"
new_files="$(comm -13 <(printf '%s\n' "$before_home") <(printf '%s\n' "$after_home"))"
unexpected_new="$(grep -v '^\./\.claude/usage-latch/' <<<"$new_files" || true)"
[[ -z "$unexpected_new" ]] \
    || fail "mutation: unexpected new file(s) under \$HOME outside the latch dir: $unexpected_new"; assertion
[[ -z "$guard_err" ]] \
    || fail "mutation: stderr was not empty (err=[$guard_err])"; assertion

# ---------------------------------------------------------------------------
# 4. GATED STILL HOLDS AT 95% — SPEC §0.6 measured the guard disarmed on the
# very lane Brett cited as the example ("No .claude/usage-guard.on exists...
# while the profile snapshot is live"): a live, crossed threshold with no flag
# file anywhere must still print nothing. This is the live case the amendment
# was reasoned from, not a hypothetical.
GATE_HOME=$(fresh_home)
GATE_CWD="$GATE_HOME/projects/openRepoProject"
mkdir -p "$GATE_CWD"   # deliberately NOT armed: no .claude/usage-guard.on anywhere
write_profile_snapshot "$GATE_HOME" "" 96 "$FIVE_RESET_EPOCH" null null >/dev/null
run_guard "$GATE_HOME" "$GATE_CWD" "sid-gated"
[[ -z "$guard_out" ]] \
    || fail "gated: a 96% snapshot produced output with no usage-guard.on anywhere, SPEC §0.6's exact miss (out=[$guard_out])"; assertion
[[ "$guard_status" -eq 0 ]] \
    || fail "gated: exited $guard_status instead of 0"; assertion
[[ -z "$guard_err" ]] \
    || fail "gated: stderr was not empty (err=[$guard_err])"; assertion

# ---------------------------------------------------------------------------
# 5. LATCHED STILL HOLDS — each (session, metric, threshold) warns once, so a
# long session costs ~3 short lines instead of one per prompt, directive
# included. Same session twice must not repeat the swap directive; a
# different session at the same threshold must still get it.
read -r LATCH_HOME LATCH_CWD < <(new_lane)
write_profile_snapshot "$LATCH_HOME" "" 96 "$FIVE_RESET_EPOCH" null null >/dev/null
run_guard "$LATCH_HOME" "$LATCH_CWD" "sid-latch-A"
grep -qF '/lane-swap' <<<"$guard_out" \
    || fail "latched: the first run for a fresh session printed no directive (out=[$guard_out])"; assertion
[[ "$guard_status" -eq 0 ]] \
    || fail "latched: first run exited $guard_status instead of 0"; assertion
run_guard "$LATCH_HOME" "$LATCH_CWD" "sid-latch-A"
[[ -z "$guard_out" ]] \
    || fail "latched: the SAME session warned twice for the same threshold (out=[$guard_out])"; assertion
[[ "$guard_status" -eq 0 ]] \
    || fail "latched: second (latched) run exited $guard_status instead of 0"; assertion
run_guard "$LATCH_HOME" "$LATCH_CWD" "sid-latch-B"
grep -qF '/lane-swap' <<<"$guard_out" \
    || fail "latched: a DIFFERENT session id was suppressed by another session's latch (out=[$guard_out])"; assertion
[[ "$guard_status" -eq 0 ]] \
    || fail "latched: third run (different session) exited $guard_status instead of 0"; assertion

# ---------------------------------------------------------------------------
# 6. STALE STILL HOLDS — a snapshot older than 600s by mtime is treated as
# absent, not trusted, so a statusline that stopped publishing (harness
# killed, profile idle) cannot leave a directive parroting a number nobody is
# still measuring.
read -r STALE_HOME STALE_CWD < <(new_lane)
snap_path=$(write_profile_snapshot "$STALE_HOME" "" 96 "$FIVE_RESET_EPOCH" null null)
touch -d '20 minutes ago' "$snap_path"
run_guard "$STALE_HOME" "$STALE_CWD" "sid-stale"
[[ -z "$guard_out" ]] \
    || fail "stale: a 20-minute-old 96% snapshot was treated as fresh (out=[$guard_out])"; assertion
[[ "$guard_status" -eq 0 ]] \
    || fail "stale: exited $guard_status instead of 0"; assertion
[[ -z "$guard_err" ]] \
    || fail "stale: stderr was not empty (err=[$guard_err])"; assertion

# ---------------------------------------------------------------------------
# 7. FAIL-QUIET — any missing input, stale snapshot, or error prints nothing
# (claude-usage-guard.sh:14-15): "A broken guard must never disrupt a
# session." Each of these reuses an armed, fresh, 96% setup — the same one
# that fires in scenario 1 — so a printed directive here would prove the bad
# input/snapshot was silently tolerated rather than actually refused.
read -r FQ_HOME FQ_CWD < <(new_lane)
write_profile_snapshot "$FQ_HOME" "" 96 "$FIVE_RESET_EPOCH" null null >/dev/null

# 7a. Garbage on stdin: jq fails to parse it, cwd resolves empty, and with no
# $HOME-level flag file the empty-cwd walk finds nothing to arm against.
run_guard_raw "$FQ_HOME" '{not valid json at all !!!'
[[ -z "$guard_out" ]] \
    || fail "fail-quiet: garbage stdin produced output despite an armed, fresh, 96% snapshot (out=[$guard_out])"; assertion
[[ "$guard_status" -eq 0 ]] \
    || fail "fail-quiet: garbage stdin exited $guard_status instead of 0"; assertion

# 7b. Empty stdin: same shape, the more common real-world case (a hook fired
# with nothing piped to it at all).
run_guard_raw "$FQ_HOME" ''
[[ -z "$guard_out" ]] \
    || fail "fail-quiet: empty stdin produced output (out=[$guard_out])"; assertion
[[ "$guard_status" -eq 0 ]] \
    || fail "fail-quiet: empty stdin exited $guard_status instead of 0"; assertion

# 7c. Valid stdin, but the profile snapshot FILE itself is not JSON — the
# statusline writer crashed mid-write, or something else clobbered it.
read -r NOTJSON_HOME NOTJSON_CWD < <(new_lane)
mkdir -p "$NOTJSON_HOME/.claude/usage-snapshots"
printf 'this is not json\n' > "$NOTJSON_HOME/.claude/usage-snapshots/profile.default.json"
run_guard "$NOTJSON_HOME" "$NOTJSON_CWD" "sid-notjson"
[[ -z "$guard_out" ]] \
    || fail "fail-quiet: a non-JSON snapshot file produced output (out=[$guard_out])"; assertion
[[ "$guard_status" -eq 0 ]] \
    || fail "fail-quiet: non-JSON snapshot exited $guard_status instead of 0"; assertion
[[ -z "$guard_err" ]] \
    || fail "fail-quiet: non-JSON snapshot wrote to stderr (err=[$guard_err])"; assertion

# 7d. Valid stdin, armed, but no snapshot file at all — a lane started before
# the statusline ever ran once.
read -r MISSING_HOME MISSING_CWD < <(new_lane)
run_guard "$MISSING_HOME" "$MISSING_CWD" "sid-missing"
[[ -z "$guard_out" ]] \
    || fail "fail-quiet: no snapshot at all produced output (out=[$guard_out])"; assertion
[[ "$guard_status" -eq 0 ]] \
    || fail "fail-quiet: missing snapshot exited $guard_status instead of 0"; assertion
[[ -z "$guard_err" ]] \
    || fail "fail-quiet: missing snapshot wrote to stderr (err=[$guard_err])"; assertion

# ---------------------------------------------------------------------------
# 8. THE FABLE WEEKLY BUCKET AT >=95% IS DELIBERATELY NOT AN AUTOMATIC SWAP
# (SPEC §9, marked "Open"): the two buckets do not mean the same thing when
# they run out — the five-hour window refills in hours, so a swap parks the
# lane and the operator comes back to it; the weekly bucket does not, and a
# swap firing on it would pause a lane with nothing on the other side of the
# pause. It keeps today's plain warning, unchanged.
read -r FABLE_HOME FABLE_CWD < <(new_lane)
write_profile_snapshot "$FABLE_HOME" "" null null 97 "$FABLE_RESET_EPOCH" >/dev/null
run_guard "$FABLE_HOME" "$FABLE_CWD" "sid-fable95" "CLAUDE_PROFILE_NAME=team-swaptest"
grep -qF 'FABLE WEEKLY BUCKET AT 97%' <<<"$guard_out" \
    || fail "fable 95: today's warning did not appear (out=[$guard_out])"; assertion
grep -qF 'STOP at a breakpoint, refresh the handoff, small tasks only' <<<"$guard_out" \
    || fail "fable 95: the exact standing wording changed without this test noticing (out=[$guard_out])"; assertion
grep -qF '/lane-swap' <<<"$guard_out" \
    && fail "fable 95: the automatic swap fired on the WEEKLY bucket, which SPEC §9 leaves Open (out=[$guard_out])"; assertion
grep -qF 'pclaude' <<<"$guard_out" \
    && fail "fable 95: a restart command was printed for the weekly bucket (out=[$guard_out])"; assertion
[[ "$guard_status" -eq 0 ]] \
    || fail "fable 95: exited $guard_status instead of 0"; assertion

# ---------------------------------------------------------------------------
# 9. CONTEXT THRESHOLDS (95/85/70) ARE UNTOUCHED BY THIS AMENDMENT. The
# context block is its own independent if/latched_warn, entirely separate
# from the five-hour block, so proving both fire together in one run is what
# would catch an edit that accidentally folded them together or gated one
# behind the other.
read -r CTX_HOME CTX_CWD < <(new_lane)
write_profile_snapshot "$CTX_HOME" "" 96 "$FIVE_RESET_EPOCH" null null >/dev/null
write_session_snapshot "$CTX_HOME" "sid-ctx95" 96
run_guard "$CTX_HOME" "$CTX_CWD" "sid-ctx95"
grep -qF '/lane-swap' <<<"$guard_out" \
    || fail "context+five: the five-hour directive did not fire alongside context (out=[$guard_out])"; assertion
grep -qF 'CONTEXT AT 96%' <<<"$guard_out" \
    || fail "context+five: the context-95 line did not appear (out=[$guard_out])"; assertion
grep -qF 'compaction is imminent' <<<"$guard_out" \
    || fail "context+five: the exact context-95 wording changed without this test noticing (out=[$guard_out])"; assertion
[[ "$(wc -l <<<"$guard_out")" -eq 2 ]] \
    || fail "context+five: expected exactly two lines (five + ctx), got $(wc -l <<<"$guard_out") (out=[$guard_out])"; assertion
[[ "$guard_status" -eq 0 ]] \
    || fail "context+five: exited $guard_status instead of 0"; assertion

# ---------------------------------------------------------------------------
# 17. A DIRECTIVE IS ADDRESSED TO A SESSION, and a payload that names none gets
# the ADVICE it got before Amendment 11. `sid` falls back to the literal
# `nosession` when the hook's JSON cannot be parsed, and two things then go
# wrong at once that do not go wrong for advice: the latch key becomes
# `nosession.five.95`, shared by every session whose payload failed the same
# way, so the first to reach it silences the rest — "warn once per session"
# collapsing into "warn once per workstation" — and the line stops being a
# remark and becomes an instruction to perform an act, in a session this hook
# could not identify.
#
# It is reachable only under the GLOBAL arming file, because the per-directory
# gate walks up from a `cwd` such a payload does not carry. That is the one
# path on which FAIL-QUIET does not cover the whole hook: the profile snapshot
# is keyed by CLAUDE_CONFIG_DIR alone, independent of cwd and session_id, so a
# globally-armed workstation still has numbers to report from a payload it
# could not read. SPEC §9 leaves the global file at Open, and this is one more
# reason for that.
NOSESSION_HOME=$(fresh_home)
mkdir -p "$NOSESSION_HOME/.claude"
: > "$NOSESSION_HOME/.claude/usage-guard.on"          # the global arm — "arms everything"
write_profile_snapshot "$NOSESSION_HOME" "" 96 "$FIVE_RESET_EPOCH" null null >/dev/null
run_guard_raw "$NOSESSION_HOME" 'not json at all'
grep -qF 'AUTOMATIC SWAP' <<<"$guard_out" \
    && fail "nosession: a directive to act was addressed to a session this hook could not identify (out=[$guard_out])"; assertion
grep -qF '/lane-swap' <<<"$guard_out" \
    && fail "nosession: the payload named no session and /lane-swap was still ordered (out=[$guard_out])"; assertion
grep -qF 'STOP at a breakpoint' <<<"$guard_out" \
    || fail "nosession: the pre-Amendment-11 advice did not stand in for the directive (out=[$guard_out])"; assertion
grep -qF 'named no session' <<<"$guard_out" \
    || fail "nosession: it does not say WHY the automatic swap is not directed here (out=[$guard_out])"; assertion
[[ "$guard_status" -eq 0 ]] \
    || fail "nosession: exited $guard_status instead of 0"; assertion

# ---------------------------------------------------------------------------
# 18. THE LANE FENCE — SPEC §9, `R-A11-6` on the review's F14. THIS IS THE
# CONTRACT POINT OF THIS ROUND. The guard is a UserPromptSubmit hook wired for
# EVERY profile and armed per DIRECTORY, and clause (g) has lane-start arm the
# lane's own checkout — so a bare `claude`, a second window, or any other
# session started in that checkout is armed too. Telling such a session to "run
# /lane-swap NOW, and do not ask the operator" would have it swap A LANE IT
# DOES NOT HOLD, which is the collision this protocol exists to prevent.
#
# 18a. A session with no lane, armed, at 96%: TODAY'S ADVICE at the same
# threshold, naming nothing. Not silence — the threshold is still crossed and
# the operator still needs to know — and not the directive.
read -r NOLANE_HOME NOLANE_CWD < <(new_lane)
write_profile_snapshot "$NOLANE_HOME" "" 96 "$FIVE_RESET_EPOCH" null null >/dev/null
run_guard "$NOLANE_HOME" "$NOLANE_CWD" "sid-nolane" "WORKBENCHES_CLAUDE_LANE="
[[ -n "$guard_out" ]] \
    || fail "lane fence: a crossed threshold went SILENT for a session with no lane (out=[$guard_out])"; assertion
grep -qF 'AUTOMATIC SWAP' <<<"$guard_out" \
    && fail "lane fence: a session holding no lane was told to swap one (out=[$guard_out])"; assertion
grep -qF '/lane-swap' <<<"$guard_out" \
    && fail "lane fence: /lane-swap was ordered in a session that holds no lane (out=[$guard_out])"; assertion
grep -qF 'STOP at a breakpoint, write or refresh the handoff doc' <<<"$guard_out" \
    || fail "lane fence: today's advice did not stand in for the directive (out=[$guard_out])"; assertion
grep -qF 'holds no lane' <<<"$guard_out" \
    || fail "lane fence: it does not say WHY the automatic swap is not directed here (out=[$guard_out])"; assertion
grep -qF 'pclaude' <<<"$guard_out" \
    && fail "lane fence: a restart command was printed to a session that holds no lane (out=[$guard_out])"; assertion
[[ "$guard_status" -eq 0 ]] \
    || fail "lane fence: exited $guard_status instead of 0"; assertion

# 18b. THE CASE F14 NAMES, END TO END: the very SAME armed checkout, the same
# threshold, two sessions — one that lane-start handed the lane to and one that
# came up beside it. One is directed; the other is advised. A guard that read
# only the directory could not tell them apart, which is the defect.
run_guard "$NOLANE_HOME" "$NOLANE_CWD" "sid-holder" "WORKBENCHES_CLAUDE_LANE=openRepoProject-1"
grep -qF 'AUTOMATIC SWAP' <<<"$guard_out" \
    || fail "lane fence: the session that HOLDS the lane was not directed (out=[$guard_out])"; assertion
grep -qF 'for lane openRepoProject-1' <<<"$guard_out" \
    || fail "lane fence: the directive does not name the lane it is about (out=[$guard_out])"; assertion
[[ "$guard_status" -eq 0 ]] \
    || fail "lane fence: the holder's run exited $guard_status instead of 0"; assertion

# 18c. MUTATION — THE FENCE IS NOT A GATE. The 90 and 80 lines were always
# advice and are not the automatic swap, so a no-lane session gets them
# unchanged: a fence that silenced the whole five-hour block would have taken
# the workstation's usage warnings away from every bare `claude` on it.
read -r NOLANE90_HOME NOLANE90_CWD < <(new_lane)
write_profile_snapshot "$NOLANE90_HOME" "" 92 "$FIVE_RESET_EPOCH" null null >/dev/null
run_guard "$NOLANE90_HOME" "$NOLANE90_CWD" "sid-nolane90" "WORKBENCHES_CLAUDE_LANE="
grep -qF '5-hour window at 92%' <<<"$guard_out" \
    || fail "lane fence: the 90-line was suppressed for a session with no lane (out=[$guard_out])"; assertion
grep -qF 'Approaching the 95% stop line' <<<"$guard_out" \
    || fail "lane fence: the 90-line's standing wording changed (out=[$guard_out])"; assertion

# 18d. ...and neither is the CONTEXT block, which is about this conversation's
# own window and has nothing to do with which lane it holds.
read -r NOLANECTX_HOME NOLANECTX_CWD < <(new_lane)
write_profile_snapshot "$NOLANECTX_HOME" "" 96 "$FIVE_RESET_EPOCH" null null >/dev/null
write_session_snapshot "$NOLANECTX_HOME" "sid-nolanectx" 96
run_guard "$NOLANECTX_HOME" "$NOLANECTX_CWD" "sid-nolanectx" "WORKBENCHES_CLAUDE_LANE="
grep -qF 'CONTEXT AT 96%' <<<"$guard_out" \
    || fail "lane fence: the context line was suppressed for a session with no lane (out=[$guard_out])"; assertion
[[ "$(wc -l <<<"$guard_out")" -eq 2 ]] \
    || fail "lane fence: expected the advice line and the context line, got $(wc -l <<<"$guard_out") (out=[$guard_out])"; assertion

# 18e. MUTATION — AND THE GUARD STILL PERFORMS NO STEP OF THE SWAP (SPEC §9:
# it "performs no step of the swap itself"). The fence added a read of the
# environment and nothing else; the fakes for every binary Amendment 8(a)'s
# five steps need are still untouched on the DIRECTED path.
read -r FENCEMUT_HOME FENCEMUT_CWD < <(new_lane)
write_profile_snapshot "$FENCEMUT_HOME" "" 96 "$FIVE_RESET_EPOCH" null null >/dev/null
rm -f "$SHELLOUT_CLAUDE_USAGE_LOG" "$SHELLOUT_LANES_EDIT_LOG" "$SHELLOUT_LANE_START_LOG" \
    "$SHELLOUT_TMUX_LOG" "$SHELLOUT_GIT_LOG"
run_guard "$FENCEMUT_HOME" "$FENCEMUT_CWD" "sid-fencemut" "WORKBENCHES_CLAUDE_LANE=openRepoProject-1"
grep -qF 'AUTOMATIC SWAP' <<<"$guard_out" \
    || fail "lane fence mutation: the run under test was not on the directive path (out=[$guard_out])"; assertion
for shellout in "$SHELLOUT_CLAUDE_USAGE_LOG" "$SHELLOUT_LANES_EDIT_LOG" \
                "$SHELLOUT_LANE_START_LOG" "$SHELLOUT_TMUX_LOG" "$SHELLOUT_GIT_LOG"; do
    [[ ! -e "$shellout" ]] \
        || fail "lane fence mutation: the guard shelled out to $(basename "$shellout") ($(cat "$shellout"))"; assertion
done

[[ "$scenarios" -eq "$EXPECTED_SCENARIOS" ]] \
    || fail "$scenarios scenarios ran, $EXPECTED_SCENARIOS expected — one was added or lost without saying so"
echo "claude-usage-guard auto-swap: $scenarios scenarios, $assertions assertions passed"
