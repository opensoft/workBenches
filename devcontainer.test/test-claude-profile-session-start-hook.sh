#!/usr/bin/env bash
# Regression tests for the SessionStart hook that claude-profile ENSURES in
# each profile's settings.json — lane-collision-protocol Amendment 8(e), as
# ruled by A8 Addendum 2 R-A8-5(b).
#
# Why the launcher owns it: every `pclaude run` execs with
# CLAUDE_CONFIG_DIR=<profile dir>, so the harness reads THAT directory's
# settings, and an entry in ~/.claude/settings.json has never fired for a lane
# session (F-S2). Measured on Eagle: 418 profile directories, none carrying a
# SessionStart hook. The launcher rewrites each profile's settings on every run
# anyway, and that rewrite is additive for every hook kind but its own — so
# ensuring the entry here, on every run, is what makes a new profile, a
# restored profile and a hand-edited one all correct without anybody
# remembering an installer.
#
# What is pinned:
#   - the command is the canonical string, byte for byte — no `bash -lc` and
#     no `2>/dev/null`, `|| true` by ruling — because that exact string is the
#     idempotence key, and `"timeout": 5` is part of the entry;
#   - ensuring twice appends once;
#   - an entry already carrying that command is left exactly as it is,
#     whatever matcher or timeout the operator gave it;
#   - every other key under .hooks, and every other key in the file, survives;
#   - nothing is written where the estate cannot answer it: no lanes-edit.sh,
#     or a lanes-edit.sh that has no `session-start` subcommand (opensoft/
#     brett-wip `main` today).

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

EXPECTED_SCENARIOS=13
scenarios=0
assertions=0
scenario() { scenarios=$((scenarios + 1)); }
assertion() { assertions=$((assertions + 1)); }

# The canonical entry, spelled here as the ruling spells it. Changing this
# string is an amendment rather than an edit, which is exactly why the test
# carries its own copy instead of reading the launcher's.
SNIPPET='~/projects/xFactory/lanes-edit.sh session-start || true'
MATCHER='startup|resume|clear|fork'

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

# The usage/context guard is the hook kind the launcher REWRITES on every run.
# It has to be present for the additivity claim to mean anything: the test is
# that SessionStart survives beside it.
printf '#!/usr/bin/env bash\nexit 0\n' > "$PROFILE_BASE/shared/usage-guard.sh"

# `lanes-edit.sh` as the estate installs it: the hook's command names the
# Amendment 5 symlink, so the launcher's existence check names the same path.
lanes_edit_with_subcommand() {
    printf '#!/usr/bin/env bash\ncase "$1" in session-start) exit 0 ;; esac\nexit 2\n' \
        > "$XFACTORY/lanes-edit.sh"
    chmod +x "$XFACTORY/lanes-edit.sh"
}
lanes_edit_without_subcommand() {
    printf '#!/usr/bin/env bash\ncase "$1" in who) exit 0 ;; esac\nexit 2\n' \
        > "$XFACTORY/lanes-edit.sh"
    chmod +x "$XFACTORY/lanes-edit.sh"
}
lanes_edit_absent() { rm -f "$XFACTORY/lanes-edit.sh"; }

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

session_start_entries() { jq '.hooks.SessionStart // []' "$SETTINGS"; }
session_start_count() { jq '(.hooks.SessionStart // []) | length' "$SETTINGS"; }
entry_with_snippet() {
    jq --arg c "$SNIPPET" '
        [.hooks.SessionStart[]? | select(any(.hooks[]?; .command == $c))] | .[0] // empty
    ' "$SETTINGS"
}

# ---------------------------------------------------------------------------
# 1. The entry is ensured on a run, and it is clause (e)'s entry: that command,
# that matcher, that timeout, and no decoration.
lanes_edit_with_subcommand
printf '%s\n' '{"model":"claude-fable-5-1"}' > "$SETTINGS"
run_launcher
[[ "$(session_start_count)" -eq 1 ]] \
    || fail "ensure: $(session_start_count) SessionStart entries, expected 1 ($(session_start_entries))"; assertion
[[ "$(entry_with_snippet | jq -r '.matcher')" == "$MATCHER" ]] \
    || fail "ensure: matcher was $(entry_with_snippet | jq -r '.matcher'), expected $MATCHER"; assertion
[[ "$(entry_with_snippet | jq -r '.hooks[0].type')" == command ]] \
    || fail "ensure: the entry is not a command hook ($(entry_with_snippet))"; assertion
[[ "$(entry_with_snippet | jq -r '.hooks[0].timeout')" == 5 ]] \
    || fail "ensure: timeout was $(entry_with_snippet | jq -r '.hooks[0].timeout'), and clause (e)'s 5 is part of the entry"; assertion
[[ "$(entry_with_snippet | jq -r '.hooks[0].command')" == "$SNIPPET" ]] \
    || fail "ensure: the command is not clause (e)'s snippet ($(entry_with_snippet | jq -r '.hooks[0].command'))"; assertion
jq -e --arg c "$SNIPPET" '
    [.hooks.SessionStart[]? | .hooks[]? | .command]
    | all(. == $c)
' "$SETTINGS" >/dev/null \
    || fail "ensure: a SessionStart command other than the snippet was written ($(session_start_entries))"; assertion
[[ "$(stat -c '%a' "$SETTINGS")" == 600 ]] \
    || fail "ensure: settings.json is mode $(stat -c '%a' "$SETTINGS"), not 600"; assertion
[[ "$(jq -r '.model' "$SETTINGS")" == claude-fable-5-1 ]] \
    || fail "ensure: an unrelated key did not survive the rewrite"; assertion

# ---------------------------------------------------------------------------
# 2. Ensuring is idempotent: a second run appends nothing. jq's pretty-printing
# is not byte-stable through a reformat, which is why the match is on the
# command string and on nothing else — an entry compared whole would be
# re-appended by whatever last touched the file.
before="$(session_start_entries)"
run_launcher
[[ "$(session_start_count)" -eq 1 ]] \
    || fail "idempotent: a second run left $(session_start_count) entries"; assertion
[[ "$(session_start_entries)" == "$before" ]] \
    || fail "idempotent: the entry changed on a second run ($(session_start_entries))"; assertion

# ---------------------------------------------------------------------------
# 3. The rewrite is ADDITIVE for every other hook kind, which is the property
# the whole approach rests on (F-W8): the launcher sets .hooks.UserPromptSubmit
# on every run and must leave the rest of .hooks alone, so an entry written
# under SessionStart survives every subsequent launch.
jq '.hooks.PreToolUse = [{matcher: "Bash", hooks: [{type: "command", command: "true"}]}]' \
    "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
run_launcher
[[ "$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$SETTINGS")" == true ]] \
    || fail "additive: an unrelated hook kind was lost ($(jq -c '.hooks' "$SETTINGS"))"; assertion
[[ "$(jq -r '.hooks.UserPromptSubmit | length' "$SETTINGS")" -eq 1 ]] \
    || fail "additive: the launcher's own UserPromptSubmit hook is not there"; assertion
# ...AND ADDITIVE WITHIN THAT KIND TOO, which is where it was not. The guard
# entry was ASSIGNED — `.hooks.UserPromptSubmit = [ours]` — so anybody else's
# UserPromptSubmit hook was dropped on the next launch, in the same function
# that preserves every other kind. Raised by the automated reviewer on
# `setup-claude-profiles.sh:175`, which is the install that makes `guard_ok`
# true; the defect was this write. Now: foreign entries kept, exactly ONE of
# ours, and its timeout refreshed (each `run_launcher` below counts itself).
jq '.hooks.UserPromptSubmit = [{hooks: [{type: "command", command: "foreign-hook"}]}]' \
    "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
run_launcher
[[ "$(jq -r '[.hooks.UserPromptSubmit[]?|.hooks[]?|select(.command == "foreign-hook")]|length' "$SETTINGS")" -eq 1 ]] \
    || fail "additive: a foreign UserPromptSubmit hook was dropped by the guard write ($(jq -c '.hooks.UserPromptSubmit' "$SETTINGS"))"; assertion
[[ "$(jq -r '[.hooks.UserPromptSubmit[]?|.hooks[]?|select(.command|test("usage-guard"))]|length' "$SETTINGS")" -eq 1 ]] \
    || fail "additive: the guard entry is not there exactly once beside it ($(jq -c '.hooks.UserPromptSubmit' "$SETTINGS"))"; assertion
run_launcher
[[ "$(jq -r '.hooks.UserPromptSubmit | length' "$SETTINGS")" -eq 2 ]] \
    || fail "additive: a second launch did not leave exactly the foreign entry and one of ours ($(jq -c '.hooks.UserPromptSubmit' "$SETTINGS"))"; assertion
[[ "$(session_start_count)" -eq 1 ]] \
    || fail "additive: SessionStart did not survive beside them"; assertion

# ---------------------------------------------------------------------------
# 3b. ...AND THE MERGE FILTERS THE NESTED ARRAY, NOT THE OUTER ENTRY
# (opensoft/workBenches#89). Section 3 pins that a foreign ENTRY survives the
# guard write; this pins the shape it did not cover, and the shape the write
# still got wrong: an entry that GROUPS the usage guard's command with somebody
# else's. `select` over the whole entry asked "does this entry carry our command
# anywhere inside it" and dropped the lot — the foreign command with it, and any
# other key on the entry, such as a `note` or a hand-set `timeout` — then
# appended a fresh guard-only entry in its place. The issue's own repro is the
# fixture below, byte for byte in shape: one grouped entry, one foreign command
# with a `timeout` of its own, one `note`.
#
# Nothing this codebase writes produces a grouped entry — every entry this file
# appends carries exactly one command — so the only way one exists is a person's
# hand-edit, which is precisely what an additive merge is for. The second entry
# is the other shape the fix must not break: an entry with NO nested `hooks`
# array at all cannot have carried our command, so it must come through
# untouched rather than be dropped, and must not acquire a `hooks: []` key it
# never had.
printf '%s\n' '{}' > "$SETTINGS"
jq '.hooks.UserPromptSubmit = [
      {
        hooks: [
          {type: "command", command: "bash \"${CLAUDE_CONFIG_DIR}/usage-guard.sh\""},
          {type: "command", command: "some-completely-unrelated-foreign-hook", timeout: 99}
        ],
        note: "operator grouped these"
      },
      {matcher: "Bash", note: "no nested hooks at all"}
    ]' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
run_launcher
[[ "$(jq -r '[.hooks.UserPromptSubmit[]?|.hooks[]?|select(.command|test("usage-guard"))]|length' "$SETTINGS")" -eq 1 ]] \
    || fail "grouped: the guard command is not there exactly once ($(jq -c '.hooks.UserPromptSubmit' "$SETTINGS"))"; assertion
[[ "$(jq -r '[.hooks.UserPromptSubmit[] | select(any(.hooks[]?; .command == "some-completely-unrelated-foreign-hook"))] | length' "$SETTINGS")" -eq 1 ]] \
    || fail "grouped: the foreign hook grouped with ours does not survive exactly once — the entry was dropped or duplicated ($(jq -c '.hooks.UserPromptSubmit' "$SETTINGS"))"; assertion
[[ "$(jq -r '[.hooks.UserPromptSubmit[] | select(any(.hooks[]?; .command == "some-completely-unrelated-foreign-hook"))] | .[0].note' "$SETTINGS")" == "operator grouped these" ]] \
    || fail "grouped: the operator's note on the grouped entry was lost ($(jq -c '.hooks.UserPromptSubmit' "$SETTINGS"))"; assertion
[[ "$(jq -r '[.hooks.UserPromptSubmit[] | select(any(.hooks[]?; .command == "some-completely-unrelated-foreign-hook"))] | .[0].hooks[0].timeout' "$SETTINGS")" == 99 ]] \
    || fail "grouped: the foreign hook's own timeout was rewritten ($(jq -c '.hooks.UserPromptSubmit' "$SETTINGS"))"; assertion
[[ "$(jq -r '[.hooks.UserPromptSubmit[] | select(any(.hooks[]?; .command == "some-completely-unrelated-foreign-hook"))] | .[0].hooks | length' "$SETTINGS")" -eq 1 ]] \
    || fail "grouped: our command was left nested beside the foreign one instead of being filtered out of it ($(jq -c '.hooks.UserPromptSubmit' "$SETTINGS"))"; assertion
[[ "$(jq -r '[.hooks.UserPromptSubmit[] | select(.note == "no nested hooks at all")] | length' "$SETTINGS")" -eq 1 ]] \
    || fail "grouped: an entry with no nested hooks array — which cannot have carried our command — was dropped ($(jq -c '.hooks.UserPromptSubmit' "$SETTINGS"))"; assertion
[[ "$(jq -r '[.hooks.UserPromptSubmit[] | select(.note == "no nested hooks at all")] | .[0] | has("hooks")' "$SETTINGS")" == false ]] \
    || fail "grouped: an entry that had no nested hooks array was given an empty one ($(jq -c '.hooks.UserPromptSubmit' "$SETTINGS"))"; assertion
[[ "$(session_start_count)" -eq 1 ]] \
    || fail "grouped: SessionStart did not survive the grouped-entry merge"; assertion

# ---------------------------------------------------------------------------
# 4. An entry that ALREADY carries the command is left exactly as it is —
# wherever it sits, whatever matcher it shares, whatever else the operator put
# beside it. The match is the command and nothing else.
printf '%s\n' '{}' > "$SETTINGS"
jq --arg c "$SNIPPET" '.hooks.SessionStart = [{
      matcher: "startup",
      hooks: [{type: "command", command: $c, timeout: 30}],
      note: "the operator put this here"
    }]' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
mine="$(session_start_entries)"
run_launcher
[[ "$(session_start_count)" -eq 1 ]] \
    || fail "preserved: the launcher appended beside an entry that already had the command"; assertion
[[ "$(session_start_entries)" == "$mine" ]] \
    || fail "preserved: the operator's matcher, timeout or note was rewritten ($(session_start_entries))"; assertion

# ---------------------------------------------------------------------------
# 5. An entry with a DIFFERENT command is not the entry. This is the shape the
# amendment rejects — `bash -lc` and `2>/dev/null`, which throws the block away
# — and the canonical entry goes in beside it rather than over it, because the
# launcher does not edit what it did not write. Two entries then run, which is
# the documented cost of a hand-installed near-miss and the reason the string
# is fixed.
printf '%s\n' '{}' > "$SETTINGS"
jq '.hooks.SessionStart = [{
      matcher: "startup|resume|clear|fork",
      hooks: [{type: "command", command: "bash -lc \"$HOME/projects/xFactory/lanes-edit.sh session-start 2>/dev/null || true\""}]
    }]' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
run_launcher
[[ "$(session_start_count)" -eq 2 ]] \
    || fail "near-miss: $(session_start_count) entries, expected the old one kept and clause (e)'s added"; assertion
[[ -n "$(entry_with_snippet)" ]] \
    || fail "near-miss: the canonical entry was not added beside the old one"; assertion
jq -e '[.hooks.SessionStart[]? | .hooks[]? | .command] | any(startswith("bash -lc"))' "$SETTINGS" >/dev/null \
    || fail "near-miss: the operator's own entry was removed"; assertion

# ---------------------------------------------------------------------------
# 6. No settings.json at all: the entry is in the file the launcher creates,
# not only in the one it edits. (Two jq programs, one behaviour.)
rm -f "$SETTINGS"
run_launcher
[[ "$(session_start_count)" -eq 1 ]] \
    || fail "created: a fresh settings.json has $(session_start_count) entries"; assertion
[[ "$(entry_with_snippet | jq -r '.hooks[0].command')" == "$SNIPPET" ]] \
    || fail "created: the snippet is not in a freshly created settings.json"; assertion

# ---------------------------------------------------------------------------
# 7. TOLERANCE, and it is the case that is live today: the estate is installed
# but its lanes-edit.sh has no `session-start` subcommand (opensoft/brett-wip
# `main`). Nothing is written, because an entry there would spend a process per
# session start printing a usage block.
lanes_edit_without_subcommand
printf '%s\n' '{}' > "$SETTINGS"
run_launcher
jq -e '.hooks.SessionStart // empty' "$SETTINGS" >/dev/null 2>&1 \
    && fail "no subcommand: an entry was written against a lanes-edit.sh that has none"; assertion

# 7b. And the next run after the estate gains it writes the entry, because the
# ensure runs on EVERY launch rather than once at install time.
lanes_edit_with_subcommand
run_launcher
[[ "$(session_start_count)" -eq 1 ]] \
    || fail "later install: the entry was not picked up by the next run"; assertion

# ---------------------------------------------------------------------------
# 8. No estate at all: no lanes-edit.sh to call, so no hook to call it with.
lanes_edit_absent
printf '%s\n' '{}' > "$SETTINGS"
run_launcher
jq -e '.hooks.SessionStart // empty' "$SETTINGS" >/dev/null 2>&1 \
    && fail "no estate: an entry was written with nothing to call"; assertion

# 9. An invalid settings.json is still refused before anything is written —
# the pre-existing guard, checked here because this suite writes that file more
# than any other.
printf '%s\n' 'not json' > "$SETTINGS"
scenario
if env "${common_env[@]}" "$LAUNCHER" --no-lane run team002 >/dev/null 2>"$TEST_ROOT/stderr.log"; then
    fail "invalid settings: the launcher ran anyway"
fi; assertion
grep -q 'not valid JSON' "$TEST_ROOT/stderr.log" \
    || fail "invalid settings: the refusal did not say why ($(cat "$TEST_ROOT/stderr.log"))"; assertion

[[ "$scenarios" -eq "$EXPECTED_SCENARIOS" ]] \
    || fail "$scenarios scenarios ran, $EXPECTED_SCENARIOS expected — one was added or lost without saying so"
echo "claude-profile SessionStart hook: $scenarios scenarios, $assertions assertions passed"
