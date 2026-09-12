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

EXPECTED_SCENARIOS=4
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
