#!/usr/bin/env bash
# Regression tests for the /lane-swap skill: where setup-claude-profiles.sh
# puts it, and what the file itself has to say — lane-collision-protocol
# Amendment 8(a), as ruled by A8 Addendum 2 R-A8-5(a) and R-A8-7.
#
# WHERE. `claude-profile` execs every `run` with CLAUDE_CONFIG_DIR=<profile
# dir>, so the harness reads THAT directory's `skills/`, never ~/.claude's.
# Every profile's `skills` is a symlink to one shared directory, so a single
# write into it reaches all of them — 418 on Eagle, where the skill had been
# installed in ~/.claude/skills and had therefore never been listed at all
# (F-S1). The ~/.claude copy stays for a bare `claude` outside the launcher.
#
# The copy is idempotent BY CONTENT: a destination already holding the vendored
# bytes is left alone, mtime and all, so a later `openRepoTools --install`
# write of the same bytes is not clobbered by the next setup run (ruled on
# opensoft/workBenches#68, F5 — this loop is their sole writer until Amendment
# 9's adoption act 3 lands, and A9's act 4 deletes it).
#
# WHAT. The skill's own text carries F-S5-F-S9: it is named /lane-swap in both
# name and description; it never hands ` — ` to `lanes-edit.sh log`, which
# refuses it; it derives the row's leading state word instead of guessing it;
# it probes for the capability instead of asserting the stamps are manual; and
# step 5 prints ONE restart command with no menu and no `claude --resume`
# fallback, because /resume is not a lane surface (R-A8-6). Every shell block
# in it is parsed here, because a skill is only copy-pasteable if it parses.
#
# This suite runs on the HOST, like test-setup-estate-commands.sh: it needs the
# repository's own scripts/ and base-image/, which are not in the container.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SETUP="$REPO_ROOT/scripts/setup-claude-profiles.sh"
SKILL_SOURCE="$REPO_ROOT/base-image/files/claude/skills/lane-swap/SKILL.md"

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

EXPECTED_SCENARIOS=9
scenarios=0
assertions=0
scenario() { scenarios=$((scenarios + 1)); }
assertion() { assertions=$((assertions + 1)); }

FAKE_HOME="$TEST_ROOT/home"
BASE="$FAKE_HOME/.claude-profiles"
DEFAULT_CLAUDE="$FAKE_HOME/.claude"
MANIFEST="$TEST_ROOT/claude-profiles.json"
PROFILE_DIR="$BASE/profiles/opensoft/team/team-002"
SHARED_SKILL="$BASE/shared/skills/lane-swap/SKILL.md"
DEFAULT_SKILL="$DEFAULT_CLAUDE/skills/lane-swap/SKILL.md"
mkdir -p "$FAKE_HOME"

cat > "$MANIFEST" <<'EOF'
{"version": 1, "families": ["opensoft"], "profiles": [
  {"name": "team-002", "profilePath": "opensoft/team/team-002", "family": "opensoft",
   "email": "test@example.invalid", "aliases": ["team002"]}
]}
EOF

run_setup() {
    scenario
    env HOME="$FAKE_HOME" \
        XDG_CONFIG_HOME="$FAKE_HOME/.config" \
        CLAUDE_PROFILES_HOME="$BASE" \
        WORKBENCHES_DEFAULT_CLAUDE_HOME="$DEFAULT_CLAUDE" \
        "$SETUP" --manifest "$MANIFEST" >/dev/null
}

# ---------------------------------------------------------------------------
# 1. One run installs the skill into the shared directory and into ~/.claude,
# byte-for-byte and world-readable, and it is visible THROUGH the profile's
# own `skills` symlink — which is the whole point of the shared directory.
run_setup
[[ -f "$SHARED_SKILL" ]] \
    || fail "install: nothing at $SHARED_SKILL"; assertion
cmp -s "$SKILL_SOURCE" "$SHARED_SKILL" \
    || fail "install: the shared copy is not the vendored file"; assertion
[[ "$(stat -c '%a' "$SHARED_SKILL")" == 644 ]] \
    || fail "install: the shared copy is mode $(stat -c '%a' "$SHARED_SKILL"), not 644"; assertion
[[ -f "$DEFAULT_SKILL" ]] \
    || fail "install: nothing at $DEFAULT_SKILL for a bare claude"; assertion
cmp -s "$SKILL_SOURCE" "$DEFAULT_SKILL" \
    || fail "install: the ~/.claude copy is not the vendored file"; assertion
# RV-W2 (workBenches#63 re-verification): with no lane estate on this machine
# at all, the bare-claude SessionStart hook is gated exactly like the
# per-profile one, so nothing is written yet.
DEFAULT_SETTINGS="$DEFAULT_CLAUDE/settings.json"
jq -e '.hooks.SessionStart // empty' "$DEFAULT_SETTINGS" >/dev/null 2>&1 \
    && fail "install: a SessionStart hook was written with no lanes-edit.sh estate at all"; assertion
[[ -L "$PROFILE_DIR/skills" ]] \
    || fail "install: the profile's skills is not a symlink ($(ls -ld "$PROFILE_DIR/skills" 2>&1))"; assertion
cmp -s "$SKILL_SOURCE" "$PROFILE_DIR/skills/lane-swap/SKILL.md" \
    || fail "install: the skill is not readable through the profile's own skills symlink — the F-S1 defect"; assertion

# ---------------------------------------------------------------------------
# 2. Idempotent by CONTENT: a second run leaves an identical destination
# untouched, mtime and all, so a later `openRepoTools --install` write of the
# same bytes is not clobbered (workBenches#68 F5).
touch -d '2001-01-01T00:00:00Z' "$SHARED_SKILL" "$DEFAULT_SKILL"
before_shared="$(stat -c '%Y' "$SHARED_SKILL")"
before_default="$(stat -c '%Y' "$DEFAULT_SKILL")"
run_setup
[[ "$(stat -c '%Y' "$SHARED_SKILL")" == "$before_shared" ]] \
    || fail "idempotent: the shared copy was rewritten although its content already matched"; assertion
[[ "$(stat -c '%Y' "$DEFAULT_SKILL")" == "$before_default" ]] \
    || fail "idempotent: the ~/.claude copy was rewritten although its content already matched"; assertion
cmp -s "$SKILL_SOURCE" "$SHARED_SKILL" \
    || fail "idempotent: the shared copy changed"; assertion

# ---------------------------------------------------------------------------
# 3. And a destination that does NOT match is put back: until A9's act 3 this
# loop is the writer, so drift is corrected rather than preserved.
printf 'something else\n' > "$SHARED_SKILL"
run_setup
cmp -s "$SKILL_SOURCE" "$SHARED_SKILL" \
    || fail "drift: a shared copy that differed was not put back"; assertion
[[ "$(stat -c '%a' "$SHARED_SKILL")" == 644 ]] \
    || fail "drift: the restored copy is mode $(stat -c '%a' "$SHARED_SKILL"), not 644"; assertion

# ---------------------------------------------------------------------------
# 4. The skill's own text (F-S5-F-S9, R-A8-6, R-A8-7).
scenario
grep -q '^name: lane-swap$' "$SKILL_SOURCE" \
    || fail "text: the skill is not named lane-swap"; assertion
grep -q '^description: "/lane-swap ' "$SKILL_SOURCE" \
    || fail "text: the description does not open with the invocable name /lane-swap (F-S5)"; assertion
grep -q '"/swap' "$SKILL_SOURCE" \
    && fail "text: the description still calls it /swap (F-S5)"; assertion
grep -q 'PROMPTS TO THE PERSON: 1' "$SKILL_SOURCE" \
    || fail "text: the header does not state the prompt count (R-A8-7)"; assertion
grep -q 'replace every ` — ` with `; `' "$SKILL_SOURCE" \
    || fail "text: nothing sanitises the separator Amendment 7(b)/R26 refuses (F-S6)"; assertion
grep -q 'replace-in-row "\$lane" "\$state"' "$SKILL_SOURCE" \
    || fail "text: the row's state word is not derived from the row (F-S7)"; assertion
grep -q "lane-start --help" "$SKILL_SOURCE" \
    || fail "text: there is no capability probe, so the restart stamps are asserted from memory (F-S8)"; assertion
grep -q 'Until the brett-wip' "$SKILL_SOURCE" \
    && fail "text: the closing note still dates itself to an unlanded PR (F-S8)"; assertion
[[ "$(grep -c 'READY TO SWAP' "$SKILL_SOURCE")" -eq 1 ]] \
    || fail "text: step 5 prints $(grep -c 'READY TO SWAP' "$SKILL_SOURCE") restart lines, and the ruling is ONE (F-S9)"; assertion
# grep -c counts LINES; a second mention on the same line is exactly how a
# fallback would be slipped back in, so count OCCURRENCES.
resume_mentions="$(grep -o 'claude --resume' "$SKILL_SOURCE" | wc -l)"
[[ "$resume_mentions" -eq 1 ]] \
    || fail "text: 'claude --resume' appears $resume_mentions times; it belongs only where it is ruled out (R-A8-6)"; assertion
# ... and every one of them has to be on the line that rules it out. (The word
# "fallback" itself stays: the skill's last line is "Do not offer either as a
# fallback".)
[[ "$(grep -c 'claude --resume' "$SKILL_SOURCE")" -eq "$(grep 'claude --resume' "$SKILL_SOURCE" | grep -c 'not lane surfaces')" ]] \
    || fail "text: 'claude --resume' appears somewhere other than the line that rules it out (R-A8-6)"; assertion
grep -q 'are not lane surfaces' "$SKILL_SOURCE" \
    || fail "text: /resume is not ruled out as a lane surface (R-A8-6)"; assertion
grep -q -- '--no-launch <repo> <n>' "$SKILL_SOURCE" \
    && fail "text: a copy-pasteable command still carries literal <repo> <n>, which the shell reads as redirections"; assertion
# RV-S2 (opensoft/workBenches#63 re-verification): step 4's row write must
# have a refused-write branch.
grep -q 'row_write_refused=1' "$SKILL_SOURCE" \
    || fail "text: step 4's row write has no refused-write branch (RV-S2)"; assertion

# ---------------------------------------------------------------------------
# 5. RV-W2 (workBenches#63 re-verification; new-workstation#16 adoption act 6
# owns this). A bare `claude` run reads $DEFAULT_CLAUDE/settings.json, never a
# profile's, so the SessionStart hook has to be ensured HERE too, not only by
# claude-profile — the same canonical string, matcher and timeout, gated the
# same way on the estate's lanes-edit.sh actually having the subcommand.
SESSION_START_SNIPPET='~/projects/xFactory/lanes-edit.sh session-start || true'
SESSION_START_MATCHER='startup|resume|clear|fork'
XFACTORY="$FAKE_HOME/projects/xFactory"
mkdir -p "$XFACTORY"
printf '#!/usr/bin/env bash\ncase "$1" in session-start) exit 0 ;; esac\nexit 2\n' \
    > "$XFACTORY/lanes-edit.sh"
chmod +x "$XFACTORY/lanes-edit.sh"
default_session_start_entries() { jq '.hooks.SessionStart // []' "$DEFAULT_SETTINGS"; }
default_session_start_count() { jq '(.hooks.SessionStart // []) | length' "$DEFAULT_SETTINGS"; }
default_entry_with_snippet() {
    jq --arg c "$SESSION_START_SNIPPET" '
        [.hooks.SessionStart[]? | select(any(.hooks[]?; .command == $c))] | .[0] // empty
    ' "$DEFAULT_SETTINGS"
}
run_setup
[[ "$(default_session_start_count)" -eq 1 ]] \
    || fail "default hook: $(default_session_start_count) SessionStart entries, expected 1 ($(default_session_start_entries))"; assertion
[[ "$(default_entry_with_snippet | jq -r '.matcher')" == "$SESSION_START_MATCHER" ]] \
    || fail "default hook: matcher was $(default_entry_with_snippet | jq -r '.matcher')"; assertion
[[ "$(default_entry_with_snippet | jq -r '.hooks[0].timeout')" == 5 ]] \
    || fail "default hook: timeout was $(default_entry_with_snippet | jq -r '.hooks[0].timeout'), expected 5"; assertion
[[ "$(default_entry_with_snippet | jq -r '.hooks[0].command')" == "$SESSION_START_SNIPPET" ]] \
    || fail "default hook: the command is not claude-profile's own canonical snippet"; assertion

# ---------------------------------------------------------------------------
# 6. Idempotent: a second run against the same estate appends nothing.
before_default_entries="$(default_session_start_entries)"
run_setup
[[ "$(default_session_start_count)" -eq 1 ]] \
    || fail "default hook idempotent: a second run left $(default_session_start_count) entries"; assertion
[[ "$(default_session_start_entries)" == "$before_default_entries" ]] \
    || fail "default hook idempotent: the entry changed on a second run"; assertion

# ---------------------------------------------------------------------------
# 7. Additive: an unrelated hook kind set by hand survives the next run
# alongside the ensured SessionStart entry, exactly like the per-profile
# rewrite (F-W8's property, carried to this second writer of the same kind).
jq '.hooks.PreToolUse = [{matcher: "Bash", hooks: [{type: "command", command: "true"}]}]' \
    "$DEFAULT_SETTINGS" > "$DEFAULT_SETTINGS.tmp" && mv "$DEFAULT_SETTINGS.tmp" "$DEFAULT_SETTINGS"
run_setup
[[ "$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$DEFAULT_SETTINGS")" == true ]] \
    || fail "default hook additive: an unrelated hook kind was lost"; assertion
[[ "$(default_session_start_count)" -eq 1 ]] \
    || fail "default hook additive: SessionStart did not survive beside it"; assertion

# ---------------------------------------------------------------------------
# 8. RV-S1 regression (BLOCKING, opensoft/workBenches#63 re-verification): the
# handoff column has to be read by a fixed LEFT field index, never counted
# back from NF. A right split returns the wrong cell — the empty string, on
# this lane's own real register row — the moment any earlier or later column
# carries a literal '|', which the live register has more than one of. This
# executes the shipped derivation line itself against two fixture rows (a
# plain one and one shaped like this lane's real row, extra '|' characters
# and all), so a future edit to the expression is re-tested, not a hand-copied
# stand-in that could silently diverge from the file.
scenario
handoff_line="$(grep -m1 '^handoff="\$(printf' "$SKILL_SOURCE")"
[[ -n "$handoff_line" ]] \
    || fail "RV-S1: could not find the handoff derivation line to execute it"; assertion
[[ "$handoff_line" != *'NF-2'* && "$handoff_line" != *'NF -'* ]] \
    || fail "RV-S1: the handoff derivation itself still counts back from NF: $handoff_line"; assertion
plain_row='| `openxfactory-13` | `abc12345` | Eagle / WSL2 / brett | 2026-09-05 | none | handoffs/xFactory/session-handoff-2026-09-05.md | LIVE · note |'
multi_pipe_row='| `openRepoProject-1` | harness abc-123 | Eagle / team / brett | 2026-09-11T19:08Z | https://example/issues/1, CLAIMED | handoffs/openRepoProject/session-handoff-2026-09-11-lane-openRepoProject-1.md | LIVE · event one · event with a | literal pipe inside it · event three |'
row="$plain_row"; eval "$handoff_line"
[[ "$handoff" == "handoffs/xFactory/session-handoff-2026-09-05.md" ]] \
    || fail "RV-S1: plain row derived handoff='$handoff'"; assertion
row="$multi_pipe_row"; eval "$handoff_line"
[[ "$handoff" == "handoffs/openRepoProject/session-handoff-2026-09-11-lane-openRepoProject-1.md" ]] \
    || fail "RV-S1: a row with extra '|' characters (this lane's own shape) derived handoff='$handoff', expected the real handoff column"; assertion
old_buggy_result="$(printf '%s' "$multi_pipe_row" | awk -F'|' '{print $(NF-2)}')"
[[ "$old_buggy_result" != "$handoff" ]] \
    || fail "RV-S1: the fixture does not actually distinguish a right split from a left split"; assertion

# ---------------------------------------------------------------------------
# 9. RV-S2 regression: step 5 must print --lane as a LEADING option, before
# `run` — claude-profile accepts --lane only as a leading option (before the
# action), so a trailing one would be handed to Claude itself, not to the
# launcher. Executes the shipped branch itself, both ways.
scenario
step5_snippet="$(sed -n '/if \[\[ -n "\${row_write_refused:-}" \]\]; then/,/^fi$/p' "$SKILL_SOURCE")"
[[ -n "$step5_snippet" ]] \
    || fail "RV-S2: could not find step 5's restart-command branch to execute it"; assertion
lane=openRepoProject-1
CLAUDE_PROFILE_NAME=work
row_write_refused=""
eval "$step5_snippet"
[[ "$restart_cmd" == "pclaude run work" ]] \
    || fail "RV-S2: normal-path restart_cmd='$restart_cmd', expected the unqualified command"; assertion
row_write_refused=1
eval "$step5_snippet"
[[ "$restart_cmd" == "pclaude --lane openRepoProject-1 run work" ]] \
    || fail "RV-S2: refused-write restart_cmd='$restart_cmd', expected --lane as a LEADING option before run"; assertion

# Every fenced shell block has to parse, or the skill is not copy-pasteable.
block_count=0
while IFS= read -r block_file; do
    block_count=$((block_count + 1))
    bash -n "$block_file" \
        || fail "text: shell block $block_count does not parse: $(cat "$block_file")"; assertion
done < <(
    awk -v dir="$TEST_ROOT" '
        /^```(bash|sh)$/ { inblock = 1; n += 1; file = sprintf("%s/block-%02d.sh", dir, n); next }
        /^```$/ { if (inblock) { close(file); print file } inblock = 0; next }
        inblock { print > file }
    ' "$SKILL_SOURCE"
)
[[ "$block_count" -ge 6 ]] \
    || fail "text: only $block_count shell blocks were found, so the parse check is not covering the skill"; assertion

[[ "$scenarios" -eq "$EXPECTED_SCENARIOS" ]] \
    || fail "$scenarios scenarios ran, $EXPECTED_SCENARIOS expected — one was added or lost without saying so"
echo "lane-swap skill install: $scenarios scenarios, $assertions assertions passed"
