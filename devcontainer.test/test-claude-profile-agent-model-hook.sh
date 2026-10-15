#!/usr/bin/env bash
# Regression tests for the two hook entries that claude-profile ENSURES in each
# profile's settings.json so that the agent-model record exists in every
# profile: a PostToolUse entry on the Agent tool and a SubagentStop entry, both
# calling `~/.local/bin/claude-agent-model-record` (brettheap/new-workstation#59).
# The script records the model each subagent started on and any mid-run swap,
# and the shared protocol's Build Tiers rule "Pin and verify" names that record
# as the documented one. Brett Heap, 2026-10-15, verbatim: "add the posttooluse
# hook that records the resolved model".
#
# Why the launcher owns it: every `pclaude run` execs with
# CLAUDE_CONFIG_DIR=<profile dir>, so the harness reads THAT directory's
# settings, and an entry in ~/.claude/settings.json has never fired for a
# profile session. The launcher rewrites each profile's settings on every run
# anyway, and that rewrite is additive for every hook kind but its own — so
# ensuring the entries here, on every run, is what makes a new profile, a
# restored profile and a hand-edited one all correct without anybody
# remembering an installer. A running session picks up new hook entries only
# after a restart.
#
# What is pinned:
#   - both entries are the canonical ones, byte for byte (command, matcher,
#     `"timeout": 5`, key order), because the command string is the idempotence
#     key; the same entries come out of the program that edits an existing file
#     and the one that creates a new file;
#   - ensuring twice appends once, and a second run leaves the file as it was;
#   - an entry already carrying a command is left exactly as it is, whatever
#     matcher, timeout or note the operator gave it, and wherever it sits;
#   - every other entry under .hooks.PostToolUse and .hooks.SubagentStop, every
#     other hook kind and every other key in the file survives;
#   - nothing is written where the script is not: absent, only on PATH, or not
#     executable; and an entry already in the file is preserved then (unlike
#     the name guard, which is removed);
#   - effortLevel, model and env keep their existing seeding.
#
# Host-run and hermetic: HOME, CLAUDE_PROFILES_HOME and the profile manifest are
# redirected into a private sandbox, and the Claude binary is a stub.

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

EXPECTED_SCENARIOS=23
scenarios=0
assertions=0
scenario() { scenarios=$((scenarios + 1)); }
assertion() { assertions=$((assertions + 1)); }

# The canonical entries, spelled here as the ruling spells them (any whitespace
# is normalised by jq before the comparison; key order and values are not).
# Changing these strings is an amendment rather than an edit, which is exactly
# why the test carries its own copy instead of reading the launcher's.
# The tilde is the harness's to expand, so SC2088's advice does not apply.
# shellcheck disable=SC2088
POST_COMMAND='~/.local/bin/claude-agent-model-record post-tool-use'
# shellcheck disable=SC2088
STOP_COMMAND='~/.local/bin/claude-agent-model-record subagent-stop'
POST_ENTRIES='[{"matcher": "Agent", "hooks": [{"type": "command", "command": "~/.local/bin/claude-agent-model-record post-tool-use", "timeout": 5}]}]'
STOP_ENTRIES='[{"hooks": [{"type": "command", "command": "~/.local/bin/claude-agent-model-record subagent-stop", "timeout": 5}]}]'
POST_ENTRIES_C="$(jq -c . <<<"$POST_ENTRIES")"
STOP_ENTRIES_C="$(jq -c . <<<"$STOP_ENTRIES")"

PROFILE_BASE="$TEST_ROOT/profiles-home"
PROFILE_DIR="$PROFILE_BASE/profiles/opensoft/team/team-002"
SETTINGS="$PROFILE_DIR/settings.json"
MANIFEST="$TEST_ROOT/claude-profiles.json"
FAKE_BIN="$TEST_ROOT/bin"
FAKE_CLAUDE="$FAKE_BIN/claude"
FAKE_HOME="$TEST_ROOT/home"
FAKE_LOCAL_BIN="$FAKE_HOME/.local/bin"
HOOK_SCRIPT="$FAKE_LOCAL_BIN/claude-agent-model-record"
XFACTORY="$FAKE_HOME/projects/xFactory"
mkdir -p "$PROFILE_DIR" "$FAKE_BIN" "$FAKE_LOCAL_BIN" "$XFACTORY" "$PROFILE_BASE/shared"

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

# The usage/context guard is the hook kind the launcher REWRITES on every run
# (UserPromptSubmit). It has to be present for the additivity claims to mean
# anything: the tests are that the new entries survive beside it and it
# survives beside them.
printf '#!/usr/bin/env bash\nexit 0\n' > "$PROFILE_BASE/shared/usage-guard.sh"

# The script as new-workstation's `scripts/link-home` places it. Only its
# presence and its executable bit matter to the launcher; it is never run here.
script_installed() {
    rm -rf "$HOOK_SCRIPT"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$HOOK_SCRIPT"
    chmod +x "$HOOK_SCRIPT"
}
script_absent() { rm -rf "$HOOK_SCRIPT" "$FAKE_BIN/claude-agent-model-record"; }
script_not_executable() {
    script_installed
    chmod -x "$HOOK_SCRIPT"
}
script_on_path_only() {
    script_absent
    printf '#!/usr/bin/env bash\nexit 0\n' > "$FAKE_BIN/claude-agent-model-record"
    chmod +x "$FAKE_BIN/claude-agent-model-record"
}

# `lanes-edit.sh` as the estate installs it, for the scenarios that put the new
# entries beside the SessionStart entry and the name guard.
lanes_edit_with_subcommands() {
    printf '#!/usr/bin/env bash\ncase "$1" in\n  session-start|guard) exit 0 ;;\nesac\nexit 2\n' \
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

post_entries() { jq -c '.hooks.PostToolUse // []' "$SETTINGS"; }
stop_entries() { jq -c '.hooks.SubagentStop // []' "$SETTINGS"; }
post_count() { jq '(.hooks.PostToolUse // []) | length' "$SETTINGS"; }
stop_count() { jq '(.hooks.SubagentStop // []) | length' "$SETTINGS"; }
# How many hook commands, across every entry of a kind, are exactly COMMAND.
carrying() {
    jq --arg k "$1" --arg c "$2" \
        '[(.hooks[$k] // [])[]? | (.hooks // [])[]? | select(.command == $c)] | length' "$SETTINGS"
}
# Overwrite a field of the settings file with a jq program, in place.
edit_settings() {
    jq "$@" "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
}

# expect_jq DESCRIPTION FILTER: the filter must be true for the settings file.
expect_jq() {
    jq -e "$2" "$SETTINGS" >/dev/null \
        || fail "$1 (filter: $2; hooks: $(jq -c '.hooks // null' "$SETTINGS"))"
    assertion
}
# expect_eq DESCRIPTION ACTUAL EXPECTED
expect_eq() {
    [[ "$2" == "$3" ]] || fail "$1: got $2, expected $3"
    assertion
}

# Both canonical entries are in the file, and are the only ones.
expect_canonical() {
    expect_eq "$1: PostToolUse is the canonical entry, byte for byte" "$(post_entries)" "$POST_ENTRIES_C"
    expect_eq "$1: SubagentStop is the canonical entry, byte for byte" "$(stop_entries)" "$STOP_ENTRIES_C"
}

# ---------------------------------------------------------------------------
# 1. No settings.json at all: the entries are in the file the launcher creates,
# not only in the one it edits. (Two jq programs, one behaviour.) The ruling's
# spelling is checked three ways: as parsed JSON (key order and values), as
# the exact text jq writes for the command lines, and as mode 600.
script_installed
rm -f "$SETTINGS"
run_launcher
expect_canonical "created"
expect_eq "created: PostToolUse command" "$(jq -r '.hooks.PostToolUse[0].hooks[0].command' "$SETTINGS")" "$POST_COMMAND"
expect_eq "created: SubagentStop command" "$(jq -r '.hooks.SubagentStop[0].hooks[0].command' "$SETTINGS")" "$STOP_COMMAND"
grep -qF "\"command\": \"$POST_COMMAND\"," "$SETTINGS" \
    || fail "created: the PostToolUse command is not in the file byte for byte ($(cat "$SETTINGS"))"; assertion
grep -qF "\"command\": \"$STOP_COMMAND\"," "$SETTINGS" \
    || fail "created: the SubagentStop command is not in the file byte for byte ($(cat "$SETTINGS"))"; assertion
expect_eq "created: the Agent matcher is on the PostToolUse entry only" \
    "$(jq -c '[.hooks.PostToolUse[0].matcher, (.hooks.SubagentStop[0] | has("matcher"))]' "$SETTINGS")" '["Agent",false]'
expect_eq "created: settings.json is mode 600" "$(stat -c '%a' "$SETTINGS")" 600

# ---------------------------------------------------------------------------
# 2. An existing settings.json gets the same entries from the other program, and
# a key the launcher does not own survives the rewrite.
printf '%s\n' '{"model":"claude-fable-5-1","theme":"dark"}' > "$SETTINGS"
run_launcher
expect_canonical "ensure"
expect_eq "ensure: an unrelated key survives the rewrite" "$(jq -r '.theme' "$SETTINGS")" dark
expect_eq "ensure: settings.json is mode 600" "$(stat -c '%a' "$SETTINGS")" 600
expect_eq "ensure: the usage guard is still in the file beside them" \
    "$(jq '[.hooks.UserPromptSubmit[]?.hooks[]? | select(.command | test("usage-guard"))] | length' "$SETTINGS")" 1

# ---------------------------------------------------------------------------
# 3. Ensuring is idempotent: a second run appends nothing and the file is
# byte-for-byte what the first run left. The match is on the command string and
# on nothing else — an entry compared whole would be re-appended by whatever
# last touched the file.
cp "$SETTINGS" "$TEST_ROOT/settings.first"
run_launcher
expect_eq "idempotent: PostToolUse entries after a second run" "$(post_count)" 1
expect_eq "idempotent: SubagentStop entries after a second run" "$(stop_count)" 1
cmp -s "$TEST_ROOT/settings.first" "$SETTINGS" \
    || fail "idempotent: a second run changed the file ($(diff "$TEST_ROOT/settings.first" "$SETTINGS" || true))"; assertion
run_launcher
expect_canonical "idempotent (third run)"

# ---------------------------------------------------------------------------
# 4. An entry that ALREADY carries a command is left exactly as it is —
# wherever it sits, whatever matcher, timeout or note the operator gave it. The
# match is the command string and nothing else, and each kind is matched on its
# own command: the PostToolUse command in SubagentStop would not count.
printf '%s\n' '{}' > "$SETTINGS"
edit_settings --arg p "$POST_COMMAND" --arg s "$STOP_COMMAND" '
    .hooks.PostToolUse = [{
        matcher: "Task|Agent",
        hooks: [{type: "command", command: $p, timeout: 30}],
        note: "the operator put this here"
    }]
    | .hooks.SubagentStop = [{
        matcher: "worker",
        hooks: [{type: "command", command: $s, timeout: 1}],
        note: "and this"
    }]'
post_mine="$(post_entries)"
stop_mine="$(stop_entries)"
run_launcher
expect_eq "preserved: PostToolUse entries" "$(post_count)" 1
expect_eq "preserved: SubagentStop entries" "$(stop_count)" 1
expect_eq "preserved: the operator's PostToolUse matcher, timeout and note" "$(post_entries)" "$post_mine"
expect_eq "preserved: the operator's SubagentStop matcher, timeout and note" "$(stop_entries)" "$stop_mine"

# 4b. ...even when the operator grouped our command with somebody else's in one
# entry (the shape opensoft/workBenches#89 is about): the entry stays whole and
# nothing is appended beside it.
printf '%s\n' '{}' > "$SETTINGS"
edit_settings --arg p "$POST_COMMAND" --arg s "$STOP_COMMAND" '
    .hooks.PostToolUse = [{
        matcher: "Agent",
        hooks: [
            {type: "command", command: "foreign-post", timeout: 99},
            {type: "command", command: $p, timeout: 9}
        ],
        note: "operator grouped these"
    }]
    | .hooks.SubagentStop = [{
        hooks: [
            {type: "command", command: $s},
            {type: "command", command: "foreign-stop"}
        ]
    }]'
post_mine="$(post_entries)"
stop_mine="$(stop_entries)"
run_launcher
expect_eq "grouped: PostToolUse grouped entry is untouched" "$(post_entries)" "$post_mine"
expect_eq "grouped: SubagentStop grouped entry is untouched" "$(stop_entries)" "$stop_mine"
expect_eq "grouped: our PostToolUse command is there exactly once" "$(carrying PostToolUse "$POST_COMMAND")" 1
expect_eq "grouped: our SubagentStop command is there exactly once" "$(carrying SubagentStop "$STOP_COMMAND")" 1

# 4c. Our command under the OTHER kind is not the entry: each kind is keyed on
# its own command, so the canonical entry still goes in beside it.
printf '%s\n' '{}' > "$SETTINGS"
edit_settings --arg p "$POST_COMMAND" --arg s "$STOP_COMMAND" '
    .hooks.PostToolUse = [{hooks: [{type: "command", command: $s}]}]
    | .hooks.SubagentStop = [{hooks: [{type: "command", command: $p}]}]'
run_launcher
expect_eq "cross-kind: PostToolUse gets its own command beside the stop command" \
    "$(carrying PostToolUse "$POST_COMMAND")/$(carrying PostToolUse "$STOP_COMMAND")" "1/1"
expect_eq "cross-kind: SubagentStop gets its own command beside the post command" \
    "$(carrying SubagentStop "$STOP_COMMAND")/$(carrying SubagentStop "$POST_COMMAND")" "1/1"

# ---------------------------------------------------------------------------
# 5. Other PostToolUse and SubagentStop entries survive, in order, and the
# canonical entry is appended after them — once, however many launches follow.
printf '%s\n' '{}' > "$SETTINGS"
edit_settings '
    .hooks.PostToolUse = [{matcher: "Bash", hooks: [{type: "command", command: "foreign-bash-post", timeout: 10}]}]
    | .hooks.SubagentStop = [{hooks: [{type: "command", command: "foreign-stop", timeout: 20}], note: "keep me"}]'
foreign_post="$(post_entries)"
foreign_stop="$(stop_entries)"
run_launcher
expect_eq "foreign: PostToolUse holds the Bash entry and ours" "$(post_count)" 2
expect_eq "foreign: SubagentStop holds the foreign entry and ours" "$(stop_count)" 2
expect_eq "foreign: the Bash PostToolUse entry is untouched and first" \
    "$(jq -c '.hooks.PostToolUse[0]' "$SETTINGS")" "$(jq -c '.[0]' <<<"$foreign_post")"
expect_eq "foreign: the foreign SubagentStop entry is untouched and first" \
    "$(jq -c '.hooks.SubagentStop[0]' "$SETTINGS")" "$(jq -c '.[0]' <<<"$foreign_stop")"
expect_eq "foreign: ours is appended last in PostToolUse" \
    "$(jq -c '.hooks.PostToolUse[1]' "$SETTINGS")" "$(jq -c '.[0]' <<<"$POST_ENTRIES_C")"
expect_eq "foreign: ours is appended last in SubagentStop" \
    "$(jq -c '.hooks.SubagentStop[1]' "$SETTINGS")" "$(jq -c '.[0]' <<<"$STOP_ENTRIES_C")"
run_launcher
expect_eq "foreign: a second launch leaves PostToolUse at two entries" "$(post_count)" 2
expect_eq "foreign: a second launch leaves SubagentStop at two entries" "$(stop_count)" 2

# ---------------------------------------------------------------------------
# 6. The rewrite is ADDITIVE for every other hook kind and every other key,
# which is the property the whole approach rests on. A foreign hook under each
# of several kinds (UserPromptSubmit, the kind the launcher itself rewrites,
# among them) and top-level keys of several types all come through a launch
# untouched.
printf '%s\n' '{}' > "$SETTINGS"
edit_settings '
    .hooks.PreToolUse = [{matcher: "Bash", hooks: [{type: "command", command: "foreign-pre"}]}]
    | .hooks.Stop = [{hooks: [{type: "command", command: "foreign-stop-kind"}]}]
    | .hooks.SessionStart = [{matcher: "startup", hooks: [{type: "command", command: "foreign-session-start"}]}]
    | .hooks.UserPromptSubmit = [{hooks: [{type: "command", command: "foreign-prompt"}]}]
    | .theme = "dark"
    | .permissions = {allow: ["Bash(ls)"]}
    | .env = {OTHER: "x"}
    | .enabledPlugins = {"some@thing": true}'
run_launcher
expect_canonical "additive"
expect_jq "additive: a foreign PreToolUse hook survived" '.hooks.PreToolUse[0].hooks[0].command == "foreign-pre"'
expect_jq "additive: a foreign Stop hook survived" '.hooks.Stop[0].hooks[0].command == "foreign-stop-kind"'
expect_jq "additive: a foreign SessionStart hook survived" '.hooks.SessionStart[0].hooks[0].command == "foreign-session-start"'
expect_jq "additive: a foreign UserPromptSubmit hook survived beside the usage guard" \
    '[.hooks.UserPromptSubmit[]?.hooks[]? | .command] | (index("foreign-prompt") != null) and any(test("usage-guard"))'
expect_jq "additive: top-level keys of several types survived" \
    '.theme == "dark" and .permissions.allow == ["Bash(ls)"] and .env.OTHER == "x" and .enabledPlugins["some@thing"] == true'
expect_jq "additive: only the hook kinds that were there, plus ours" \
    '.hooks | keys == ["PostToolUse","PreToolUse","SessionStart","Stop","SubagentStop","UserPromptSubmit"]'

# ---------------------------------------------------------------------------
# 7. The estate's other two hooks and these entries sit in one file without
# disturbing each other: with a lanes-edit.sh that answers session-start and
# guard, the SessionStart entry, the name guard and ours all land; and when the
# estate goes away the name guard is stripped by its downgrade branch and ours
# are not, because they are preserved-if-present.
printf '%s\n' '{}' > "$SETTINGS"
lanes_edit_with_subcommands
run_launcher
expect_canonical "estate"
expect_eq "estate: the SessionStart entry landed" "$(jq '(.hooks.SessionStart // []) | length' "$SETTINGS")" 1
expect_eq "estate: the name guard landed" \
    "$(jq '[.hooks.UserPromptSubmit[]?.hooks[]? | select(.command == "~/projects/xFactory/lanes-edit.sh guard")] | length' "$SETTINGS")" 1
lanes_edit_absent
run_launcher
expect_canonical "estate gone"
expect_eq "estate gone: the name guard was removed by its own downgrade branch" \
    "$(jq '[.hooks.UserPromptSubmit[]?.hooks[]? | select(.command == "~/projects/xFactory/lanes-edit.sh guard")] | length' "$SETTINGS")" 0

# ---------------------------------------------------------------------------
# 8. TOLERANCE: no script, no entries. Nothing under PostToolUse or
# SubagentStop is created for a profile that has neither, and no other hook kind
# is disturbed by the absence.
script_absent
printf '%s\n' '{}' > "$SETTINGS"
run_launcher
expect_jq "no script: no PostToolUse key was written" '.hooks | has("PostToolUse") | not'
expect_jq "no script: no SubagentStop key was written" '.hooks | has("SubagentStop") | not'
expect_jq "no script: the launcher's own hook kind is still written" '.hooks.UserPromptSubmit | length == 1'
rm -f "$SETTINGS"
run_launcher
expect_jq "no script, no file: no PostToolUse key was written" '.hooks | has("PostToolUse") | not'
expect_jq "no script, no file: no SubagentStop key was written" '.hooks | has("SubagentStop") | not'
expect_jq "no script, no file: the defaults are still written" '.effortLevel == "xhigh" and .model == "claude-fable-5-1"'

# 8b. ...and an entry already in the file is left ALONE when the script is gone
# (preserved-if-present, like SessionStart; the name guard is the one that is
# removed, and only because an entry left behind there would block prompts).
# Ours and the foreign entries all stay, byte for byte.
printf '%s\n' '{}' > "$SETTINGS"
edit_settings --arg p "$POST_COMMAND" --arg s "$STOP_COMMAND" '
    .hooks.PostToolUse = [
        {matcher: "Bash", hooks: [{type: "command", command: "foreign-bash-post"}]},
        {matcher: "Agent", hooks: [{type: "command", command: $p, timeout: 5}]}
    ]
    | .hooks.SubagentStop = [{hooks: [{type: "command", command: $s, timeout: 5}]}]'
post_mine="$(post_entries)"
stop_mine="$(stop_entries)"
run_launcher
expect_eq "absent, entries present: PostToolUse is left alone" "$(post_entries)" "$post_mine"
expect_eq "absent, entries present: SubagentStop is left alone" "$(stop_entries)" "$stop_mine"
run_launcher
expect_eq "absent, entries present: and on the launch after that" "$(post_entries)$(stop_entries)" "$post_mine$stop_mine"

# ---------------------------------------------------------------------------
# 9. The probe is the path the command names, and an executable one. A script
# that is only on PATH is not what `~/.local/bin/claude-agent-model-record`
# runs, and a file without the executable bit cannot run at all: neither opens
# the gate.
script_on_path_only
printf '%s\n' '{}' > "$SETTINGS"
run_launcher
expect_jq "PATH only: nothing was written for a script that is not under ~/.local/bin" \
    '.hooks | (has("PostToolUse") or has("SubagentStop")) | not'
script_not_executable
printf '%s\n' '{}' > "$SETTINGS"
run_launcher
expect_jq "not executable: nothing was written for a script that cannot run" \
    '.hooks | (has("PostToolUse") or has("SubagentStop")) | not'
rm -rf "$HOOK_SCRIPT"
mkdir -p "$HOOK_SCRIPT"
printf '%s\n' '{}' > "$SETTINGS"
run_launcher
expect_jq "a directory at the path: nothing was written" \
    '.hooks | (has("PostToolUse") or has("SubagentStop")) | not'
rm -rf "$HOOK_SCRIPT"

# 9b. The ensure runs on EVERY launch, so a script installed later is picked up
# by the next one, with no re-install step of its own.
script_installed
run_launcher
expect_canonical "later install"

# ---------------------------------------------------------------------------
# 10. The seeding that was already there is unchanged: effortLevel, model, env
# and the status line on a fresh file, and an explicit value in an existing file
# still wins.
script_installed
rm -f "$SETTINGS"
run_launcher
expect_jq "defaults: a fresh file keeps effortLevel, model, env and the status line" \
    '.effortLevel == "xhigh" and .model == "claude-fable-5-1"
     and .env == {"CLAUDE_CODE_DISABLE_REFUSAL_FALLBACK": "1"}
     and .permissions.defaultMode == "bypassPermissions"
     and .statusLine.type == "command" and .statusLine.refreshInterval == 10'
printf '%s\n' '{"model":"custom-model","effortLevel":"high","env":{"OTHER":"x","CLAUDE_CODE_DISABLE_REFUSAL_FALLBACK":"0"}}' > "$SETTINGS"
run_launcher
expect_jq "explicit values: model, effortLevel and the env opt-out still win" \
    '.model == "custom-model" and .effortLevel == "high"
     and .env == {"OTHER": "x", "CLAUDE_CODE_DISABLE_REFUSAL_FALLBACK": "0"}'
expect_canonical "explicit values"

# ---------------------------------------------------------------------------
# 11. An invalid settings.json is still refused before anything is written —
# the pre-existing guard, checked here because this suite writes that file more
# than most.
printf '%s\n' 'not json' > "$SETTINGS"
scenario
if env "${common_env[@]}" "$LAUNCHER" --no-lane run team002 >/dev/null 2>"$TEST_ROOT/stderr.log"; then
    fail "invalid settings: the launcher ran anyway"
fi; assertion
grep -q 'not valid JSON' "$TEST_ROOT/stderr.log" \
    || fail "invalid settings: the refusal did not say why ($(cat "$TEST_ROOT/stderr.log"))"; assertion
expect_eq "invalid settings: the file was not rewritten" "$(cat "$SETTINGS")" 'not json'

[[ "$scenarios" -eq "$EXPECTED_SCENARIOS" ]] \
    || fail "$scenarios scenarios ran, $EXPECTED_SCENARIOS expected — one was added or lost without saying so"
echo "claude-profile agent-model-record hook: $scenarios scenarios, $assertions assertions passed"
