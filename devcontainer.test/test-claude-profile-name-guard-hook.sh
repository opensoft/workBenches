#!/usr/bin/env bash
# Regression tests for the UserPromptSubmit NAME GUARD that claude-profile
# ENSURES beside the usage guard in each profile's settings.json —
# lane-collision-protocol Amendment 12 adoption act 3: "the launcher
# (`claude-profile` in `opensoft/workBenches`) ensures it per run the way it
# ensures the SessionStart hook today (workBenches#63)". Brett Heap ruled,
# verbatim, "install the hook when 25 lands" (2026-09-15); `opensoft/
# openRepoTools#52` landed Amendment 12 (the name guard and lock) as main
# `2faa883` the same day. This is the profile half — the bare-`claude` half is
# `openRepoTools --install`'s own merge into `~/.claude/settings.json`, which
# this suite does not touch.
#
# What is pinned:
#   - the command is `opensoft/openRepoTools`'s own GUARD_COMMAND, byte for
#     byte, with NO matcher (UserPromptSubmit has no source to match on) and
#     NO `|| true` (exit 2 is the whole mechanism; swallowing it would install
#     a guard that refuses nothing);
#   - ensuring twice appends once — present costs no write, absent appends;
#   - an entry already carrying that command is left exactly as it is,
#     whatever timeout or note the operator gave it;
#   - every other key under .hooks, and every other UserPromptSubmit entry
#     (the usage guard's own, and any foreign hook), survives untouched;
#   - nothing is written where the estate cannot answer it: no
#     lanes-edit.sh, or one that has no `guard` subcommand — and the probe
#     for that must not be fooled by the word "guard" appearing in this
#     estate's own comments, which it does constantly, with and without the
#     subcommand, in a CODE line or a COMMENT line alike (Copilot round 1,
#     PR #88);
#   - a profile that already carries the entry SELF-HEALS the other way too:
#     if the estate is later downgraded to one that cannot answer `guard`,
#     the entry is REMOVED on the profile's next launch rather than left
#     behind to block every prompt with "unknown subcommand" (Copilot round
#     1, PR #88) — SessionStart's `|| true` makes that failure mode
#     impossible for it, which is why this suite tests it and that one does
#     not.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LAUNCHER="${1:-$REPO_ROOT/base-image/files/claude-profile}"

unset TMUX TMUX_PANE WORKBENCHES_CLAUDE_TMUX WORKBENCHES_CLAUDE_TMUX_CHILD \
    WORKBENCHES_CLAUDE_WINDOW CLAUDE_LANE CLAUDE_NO_LANE 2>/dev/null || true

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

EXPECTED_SCENARIOS=16
scenarios=0
assertions=0
scenario() { scenarios=$((scenarios + 1)); }
assertion() { assertions=$((assertions + 1)); }

# The canonical entry, spelled here as opensoft/openRepoTools's own
# GUARD_COMMAND/GUARD_TIMEOUT spell it (`openRepoTools:460-461`,
# `guard_block_text()`) — the test carries its own copy rather than reading
# the launcher's, exactly as the SessionStart suite beside this one does.
SNIPPET='~/projects/xFactory/lanes-edit.sh guard'

PROFILE_BASE="$TEST_ROOT/profiles-home"
PROFILE_DIR="$PROFILE_BASE/profiles/opensoft/team/team-002"
SETTINGS="$PROFILE_DIR/settings.json"
MANIFEST="$TEST_ROOT/claude-profiles.json"
FAKE_BIN="$TEST_ROOT/bin"
FAKE_CLAUDE="$FAKE_BIN/claude"
FAKE_HOME="$TEST_ROOT/home"
XFACTORY="$FAKE_HOME/projects/xFactory"
mkdir -p "$PROFILE_DIR" "$FAKE_BIN" "$XFACTORY" "$PROFILE_BASE/shared"

printf '%s\n' \
    '{"profiles":[{"name":"team-002","email":"test@example.invalid","family":"testing","aliases":["team002"],"profilePath":"opensoft/team/team-002"}]}' \
    > "$MANIFEST"
printf '%s\n' '{"name":"team-002","family":"testing","email":"test@example.invalid","aliases":["team002"]}' \
    > "$PROFILE_DIR/.profile.json"

cat > "$FAKE_CLAUDE" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$FAKE_CLAUDE"

# The usage/context guard is the OTHER hook kind wired into this same array.
# It has to be present for the "beside it" claim to mean anything: the test
# is that the name guard survives beside it and vice versa.
printf '#!/usr/bin/env bash\nexit 0\n' > "$PROFILE_BASE/shared/usage-guard.sh"

# `lanes-edit.sh` AS THE ESTATE INSTALLS IT ACROSS ITS THREE ERAS — the hook's
# command names the Amendment 5 symlink, so the launcher's own probe names the
# same path this fixture writes to.
#
# `lanes_edit_pre_amendment_12` is not a guess: it is shaped exactly like
# `opensoft/workBenches`'s own vendored copy at the pin this PR ships beside
# (`devBenches/base-image/files/openrepotools/lanes-edit.sh`, commit
# `8a36eb3`) — `session-start` in the die's enumeration, no `guard`, and a
# comment mentioning "the dispatcher guard)" that a bare `guard)` probe would
# have mistaken for the case label. That false positive was measured against
# the real file while this suite was written; it is reproduced here so a
# probe that regresses to substring matching fails loudly instead of wiring a
# hook that blocks every prompt on a workstation whose estate has not caught
# up yet.
lanes_edit_pre_amendment_12() {
    cat > "$XFACTORY/lanes-edit.sh" <<'EOF'
#!/usr/bin/env bash
# EXIT CODES: 2 refusal — bad arguments, an unknown alias (the dispatcher
# guard), or a checkout that cannot be rebased.
case "$1" in
  session-start) exit 0 ;;
  *) echo "unknown subcommand '$1' (session-start|who|swapped)" >&2; exit 2 ;;
esac
EOF
    chmod +x "$XFACTORY/lanes-edit.sh"
}
lanes_edit_with_guard() {
    cat > "$XFACTORY/lanes-edit.sh" <<'EOF'
#!/usr/bin/env bash
case "$1" in session-start|guard) : ;; esac
case "$1" in
  session-start) exit 0 ;;
  guard) exit 0 ;;
  *) echo "unknown subcommand '$1' (session-start|guard|who|swapped)" >&2; exit 2 ;;
esac
EOF
    chmod +x "$XFACTORY/lanes-edit.sh"
}
lanes_edit_absent() { rm -f "$XFACTORY/lanes-edit.sh"; }

# THE SECOND FALSE-POSITIVE SHAPE (Copilot round 1, PR #88): no `guard)`
# dispatch arm anywhere, but a COMMENT containing the exact substrings a
# plain `|guard\||\|guard\)|\(guard\|` alternation would have matched —
# `|guard|` mid-list, `|guard)` at the end, `(guard|` at the start — none of
# them on a real dispatch line. A probe that checks raw file text rather than
# a line-anchored, comment-excluded shape wires the hook here; the correct
# one does not, because `guard` never dispatches to anything.
lanes_edit_guard_only_in_prose() {
    cat > "$XFACTORY/lanes-edit.sh" <<'EOF'
#!/usr/bin/env bash
# Related verbs seen in the wild: (guard|shield), a fence|guard|wall, and
# some configs still spell it guard) with the paren glued on.
case "$1" in
  session-start) exit 0 ;;
  *) echo "unknown subcommand '$1' (session-start|who|swapped)" >&2; exit 2 ;;
esac
EOF
    chmod +x "$XFACTORY/lanes-edit.sh"
}

common_env=(
    "PATH=$FAKE_BIN:/usr/bin:/bin"
    "HOME=$FAKE_HOME"
    "CLAUDE_BIN=$FAKE_CLAUDE"
    "CLAUDE_PROFILES_HOME=$PROFILE_BASE"
    "CLAUDE_PROFILES_MANIFEST=$MANIFEST"
    "WORKBENCHES_SHARED_MCP_FAMILIES=disabled"
)

# One run of the launcher. `--no-lane` keeps the lane resolution out of it
# entirely: what is under test here is the settings rewrite every `run` does
# before it ever looks at a lane.
run_launcher() {
    scenario
    env "${common_env[@]}" "$LAUNCHER" --no-lane run team002 --resume session-x \
        >/dev/null 2>"$TEST_ROOT/stderr.log"
}

guard_entries() { jq '[.hooks.UserPromptSubmit[]? | select(any(.hooks[]?; .command == "'"$SNIPPET"'"))]' "$SETTINGS"; }
guard_count() { jq --arg c "$SNIPPET" '[.hooks.UserPromptSubmit[]? | select(any(.hooks[]?; .command == $c))] | length' "$SETTINGS"; }
entry_with_snippet() {
    jq --arg c "$SNIPPET" '
        [.hooks.UserPromptSubmit[]? | select(any(.hooks[]?; .command == $c))] | .[0] // empty
    ' "$SETTINGS"
}

# ---------------------------------------------------------------------------
# 1. The entry is ensured on a run, beside the usage guard the fixture wired
# above: that command, that timeout, NO matcher (UserPromptSubmit has no
# source to match on — the one deliberate shape difference from SessionStart).
lanes_edit_with_guard
printf '%s\n' '{"model":"claude-fable-5-1"}' > "$SETTINGS"
run_launcher
[[ "$(guard_count)" -eq 1 ]] \
    || fail "ensure: $(guard_count) name-guard entries, expected 1 ($(guard_entries))"; assertion
[[ "$(entry_with_snippet | jq -r 'has("matcher")')" == false ]] \
    || fail "ensure: the entry carries a matcher, and UserPromptSubmit has no source to match on ($(entry_with_snippet))"; assertion
[[ "$(entry_with_snippet | jq -r '.hooks[0].type')" == command ]] \
    || fail "ensure: the entry is not a command hook ($(entry_with_snippet))"; assertion
[[ "$(entry_with_snippet | jq -r '.hooks[0].timeout')" == 5 ]] \
    || fail "ensure: timeout was $(entry_with_snippet | jq -r '.hooks[0].timeout'), expected 5"; assertion
[[ "$(entry_with_snippet | jq -r '.hooks[0].command')" == "$SNIPPET" ]] \
    || fail "ensure: the command is not GUARD_COMMAND ($(entry_with_snippet | jq -r '.hooks[0].command'))"; assertion
[[ "$(jq -r '[.hooks.UserPromptSubmit[]?|.hooks[]?|select(.command|test("usage-guard"))]|length' "$SETTINGS")" -eq 1 ]] \
    || fail "ensure: the usage guard entry beside it is missing ($(jq -c '.hooks.UserPromptSubmit' "$SETTINGS"))"; assertion
[[ "$(stat -c '%a' "$SETTINGS")" == 600 ]] \
    || fail "ensure: settings.json is mode $(stat -c '%a' "$SETTINGS"), not 600"; assertion
[[ "$(jq -r '.model' "$SETTINGS")" == claude-fable-5-1 ]] \
    || fail "ensure: an unrelated key did not survive the rewrite"; assertion

# ---------------------------------------------------------------------------
# 2. Present costs no write to OUR entry: a second run leaves it unchanged,
# byte for byte — this is opensoft/openRepoTools --install's own idempotence
# for this exact entry ("present" skips the merge outright), mirrored here.
# Compared as the filtered entry and not the whole array: the usage guard
# beside it is filtered-and-refreshed on every launch by design (its own
# comment: "one of ours, its timeout refreshed"), which reorders the array
# without changing its content, and that pre-existing churn is not this PR's
# to fix or to be tripped up by.
before="$(entry_with_snippet)"
run_launcher
[[ "$(guard_count)" -eq 1 ]] \
    || fail "idempotent: a second run left $(guard_count) name-guard entries"; assertion
[[ "$(entry_with_snippet)" == "$before" ]] \
    || fail "idempotent: the name-guard entry changed on a second run ($(entry_with_snippet))"; assertion

# ---------------------------------------------------------------------------
# 3. NEVER DUPLICATED, and additive within the array: a foreign
# UserPromptSubmit hook and the SessionStart entry both survive every launch
# beside exactly one of ours, and an unrelated hook kind is untouched.
jq '.hooks.PreToolUse = [{matcher: "Bash", hooks: [{type: "command", command: "true"}]}]' \
    "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
jq '.hooks.UserPromptSubmit += [{hooks: [{type: "command", command: "foreign-hook"}]}]' \
    "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
run_launcher
run_launcher
[[ "$(guard_count)" -eq 1 ]] \
    || fail "additive: a second launch left $(guard_count) name-guard entries, never-duplicated failed"; assertion
[[ "$(jq -r '[.hooks.UserPromptSubmit[]?|.hooks[]?|select(.command == "foreign-hook")]|length' "$SETTINGS")" -eq 1 ]] \
    || fail "additive: the foreign UserPromptSubmit hook was dropped ($(jq -c '.hooks.UserPromptSubmit' "$SETTINGS"))"; assertion
[[ "$(jq -r '[.hooks.UserPromptSubmit[]?|.hooks[]?|select(.command|test("usage-guard"))]|length' "$SETTINGS")" -eq 1 ]] \
    || fail "additive: the usage guard entry did not survive beside it"; assertion
[[ "$(jq -r '(.hooks.SessionStart // [])|length' "$SETTINGS")" -eq 1 ]] \
    || fail "additive: the SessionStart entry did not survive beside it"; assertion
[[ "$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$SETTINGS")" == true ]] \
    || fail "additive: an unrelated hook kind was lost ($(jq -c '.hooks' "$SETTINGS"))"; assertion

# ---------------------------------------------------------------------------
# 4. An entry that ALREADY carries the command is left exactly as it is —
# wherever it sits, whatever timeout it carries, whatever else the operator
# put beside it. The match is the command and nothing else.
printf '%s\n' '{}' > "$SETTINGS"
jq --arg c "$SNIPPET" '.hooks.UserPromptSubmit = [{
      hooks: [{type: "command", command: $c, timeout: 30}],
      note: "the operator put this here"
    }]' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
mine="$(jq '.hooks.UserPromptSubmit' "$SETTINGS")"
run_launcher
[[ "$(guard_count)" -eq 1 ]] \
    || fail "preserved: the launcher appended beside an entry that already had the command"; assertion
[[ "$(jq --arg c "$SNIPPET" '[.hooks.UserPromptSubmit[] | select(any(.hooks[]?; .command == $c))]' "$SETTINGS")" == "$mine" ]] \
    || fail "preserved: the operator's timeout or note was rewritten ($(jq -c '.hooks.UserPromptSubmit' "$SETTINGS"))"; assertion

# ---------------------------------------------------------------------------
# 5. An entry with a DIFFERENT command is not the entry: the canonical one
# goes in beside it rather than over it, exactly as SessionStart's near-miss
# case does, because the launcher does not edit what it did not write.
printf '%s\n' '{}' > "$SETTINGS"
jq '.hooks.UserPromptSubmit = [{
      hooks: [{type: "command", command: "bash -lc \"$HOME/projects/xFactory/lanes-edit.sh guard 2>/dev/null || true\""}]
    }]' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
run_launcher
# Three entries after this run, not two: the near-miss kept, the canonical
# one added, AND the usage guard this fixture always wires beside them —
# counted here by what each IS rather than by a fragile total.
[[ "$(guard_count)" -eq 1 ]] \
    || fail "near-miss: $(guard_count) canonical entries, expected exactly 1 added beside the old one ($(jq -c '.hooks.UserPromptSubmit' "$SETTINGS"))"; assertion
[[ -n "$(entry_with_snippet)" ]] \
    || fail "near-miss: the canonical entry was not added beside the old one"; assertion
jq -e '[.hooks.UserPromptSubmit[]? | .hooks[]? | .command] | any(startswith("bash -lc"))' "$SETTINGS" >/dev/null \
    || fail "near-miss: the operator's own entry was removed"; assertion

# ---------------------------------------------------------------------------
# 6. No settings.json at all: the entry is in the file the launcher creates,
# not only in the one it edits.
rm -f "$SETTINGS"
run_launcher
[[ "$(guard_count)" -eq 1 ]] \
    || fail "created: a fresh settings.json has $(guard_count) name-guard entries"; assertion
[[ "$(entry_with_snippet | jq -r '.hooks[0].command')" == "$SNIPPET" ]] \
    || fail "created: the snippet is not in a freshly created settings.json"; assertion

# ---------------------------------------------------------------------------
# 7. TOLERANCE: the estate is installed but its lanes-edit.sh has no `guard`
# subcommand — the case that is live today, since opensoft/workBenches's own
# vendored copy predates opensoft/openRepoTools#52. Nothing is written,
# because an entry there would fall through to lanes-edit.sh's "unknown
# subcommand" die, WHICH EXITS 2 — the one code that BLOCKS a
# UserPromptSubmit prompt.
lanes_edit_pre_amendment_12
printf '%s\n' '{}' > "$SETTINGS"
run_launcher
[[ "$(guard_count)" -eq 0 ]] \
    || fail "no subcommand: a name-guard entry was written against a lanes-edit.sh that has none"; assertion
[[ "$(jq -r '(.hooks.SessionStart // [])|length' "$SETTINGS")" -eq 1 ]] \
    || fail "no subcommand: the SessionStart entry, which this lanes-edit.sh DOES support, was wrongly withheld too"; assertion

# 7b. And the next run after the estate gains it writes the entry, because
# the ensure runs on EVERY launch rather than once at install time.
lanes_edit_with_guard
run_launcher
[[ "$(guard_count)" -eq 1 ]] \
    || fail "later install: the entry was not picked up by the next run"; assertion

# ---------------------------------------------------------------------------
# 8. No estate at all: no lanes-edit.sh to call, so no hook to call it with.
lanes_edit_absent
printf '%s\n' '{}' > "$SETTINGS"
run_launcher
[[ "$(guard_count)" -eq 0 ]] \
    || fail "no estate: a name-guard entry was written with nothing to call"; assertion

# ---------------------------------------------------------------------------
# 9. THE FALSE-POSITIVE REGRESSION. `lanes-edit.sh` predates the `guard`
# subcommand, and the ONLY appearance of the word "guard" in it is a comment
# whose shape — "guard)," mid-sentence — is exactly what a naive substring or
# bare case-label probe mistakes for the dispatch line. This is not a
# hypothetical: it is `opensoft/workBenches`'s own vendored copy, measured
# while this probe was written, and `lanes_edit_pre_amendment_12` above
# reproduces the same shape. A regression here means every profile on a
# workstation whose estate has not yet picked up openRepoTools#52 gets a
# UserPromptSubmit entry that blocks its every prompt with "unknown
# subcommand 'guard'".
lanes_edit_pre_amendment_12
printf '%s\n' '{}' > "$SETTINGS"
run_launcher
[[ "$(guard_count)" -eq 0 ]] \
    || fail "false-positive regression: the comment '(the dispatcher guard)' wired a hook that would block every prompt"; assertion

# ---------------------------------------------------------------------------
# 10. THE SECOND FALSE-POSITIVE SHAPE (Copilot round 1, PR #88): no dispatch
# arm at all, but a COMMENT carrying the exact `|guard|`, `(guard|` and
# `guard)` substrings a plain alternation over raw file text would have
# matched. The probe must exclude comment lines and anchor the shape to where
# a line begins, not merely search for the substring anywhere.
lanes_edit_guard_only_in_prose
printf '%s\n' '{}' > "$SETTINGS"
run_launcher
[[ "$(guard_count)" -eq 0 ]] \
    || fail "false-positive regression (prose): a comment merely containing |guard| shapes wired a hook that would block every prompt"; assertion

# ---------------------------------------------------------------------------
# 11. THE DOWNGRADE FAIL-SAFE (Copilot round 1, PR #88). A profile that
# already carries the entry, on an estate later downgraded to one that
# cannot answer `guard`, must have the entry REMOVED on its next launch —
# not left behind. Left in place, that exact command would fall through the
# downgraded lanes-edit.sh's "unknown subcommand" die, WHICH ALSO EXITS 2,
# blocking every prompt with the very entry meant to protect it.
# SessionStart cannot have this failure mode (its command ends in `|| true`),
# which is why only this suite tests a supported-to-unsupported transition.
lanes_edit_with_guard
printf '%s\n' '{}' > "$SETTINGS"
run_launcher
[[ "$(guard_count)" -eq 1 ]] \
    || fail "downgrade setup: the entry was not ensured while the estate supported it"; assertion
lanes_edit_pre_amendment_12
run_launcher
[[ "$(guard_count)" -eq 0 ]] \
    || fail "downgrade: the entry survived an estate that can no longer answer guard, and would block every prompt"; assertion
[[ "$(jq -r '[.hooks.UserPromptSubmit[]?|.hooks[]?|select(.command|test("usage-guard"))]|length' "$SETTINGS")" -eq 1 ]] \
    || fail "downgrade: the usage guard entry beside it was wrongly touched too"; assertion
[[ "$(jq -r '(.hooks.SessionStart // [])|length' "$SETTINGS")" -eq 1 ]] \
    || fail "downgrade: the SessionStart entry, which this lanes-edit.sh still supports, was wrongly removed too"; assertion
# 11b. And an upgrade after that heals it again on the very next launch —
# the two transitions are symmetric, self-healing in both directions.
lanes_edit_with_guard
run_launcher
[[ "$(guard_count)" -eq 1 ]] \
    || fail "re-upgrade: the entry was not restored on the next launch"; assertion

# ---------------------------------------------------------------------------
# 12. An invalid settings.json is refused before anything is written — the
# pre-existing guard, checked here because a name-guard entry that bypassed it
# would mean two writers disagreeing about when this file may be touched.
lanes_edit_with_guard
printf '%s\n' 'not json' > "$SETTINGS"
scenario
if env "${common_env[@]}" "$LAUNCHER" --no-lane run team002 >/dev/null 2>"$TEST_ROOT/stderr.log"; then
    fail "invalid settings: the launcher ran anyway"
fi; assertion
grep -q 'not valid JSON' "$TEST_ROOT/stderr.log" \
    || fail "invalid settings: the refusal did not say why ($(cat "$TEST_ROOT/stderr.log"))"; assertion

[[ "$scenarios" -eq "$EXPECTED_SCENARIOS" ]] \
    || fail "$scenarios scenarios ran, $EXPECTED_SCENARIOS expected — one was added or lost without saying so"
echo "claude-profile UserPromptSubmit name guard (Amendment 12): $scenarios scenarios, $assertions assertions passed"
