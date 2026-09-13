#!/usr/bin/env bash
# Regression tests for the /lane-swap skill after lane-collision-protocol
# Amendment 9 adoption act 4b: WHO places it, who no longer does, and what the
# file itself has to say.
#
# WHAT ACT 4B CHANGED HERE. Until act 4b, scripts/setup-claude-profiles.sh
# carried a `for skill in lane-swap` loop that installed SKILL.md into the
# shared skills directory and into ~/.claude, and a SessionStart ensure that
# appended Amendment 8(e)'s entry to ~/.claude/settings.json. Act 3 gave both
# to `openRepoTools --install` (Amendment 9(b), on A8 Addendum 2's ratified
# R-A8-5), and act 4b deleted them from that script "together with the
# vendored copy it installs from". So this suite is inverted: the assertions
# that used to prove the loop RAN now prove it is GONE, and one new scenario
# proves the install act is what places the skill.
#
# THE SKILL'S TEXT DID NOT LEAVE THIS REPOSITORY, it changed shelf. It is now
# devBenches/base-image/files/openrepotools/skills/lane-swap/SKILL.md, a pinned
# copy under devBenches/base-image/upstream-pin.yaml, vendored so that
# `--install` can place it with no network -- scripts/setup-estate-commands.sh
# exports OPENREPOTOOLS_REPO/_REF to a sentinel that cannot resolve. Every
# text assertion below therefore survives act 4b unchanged, reading the pinned
# copy instead of the deleted one.
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
VENDOR_DIR="$REPO_ROOT/devBenches/base-image/files/openrepotools"
TOOLS_SHIM="$VENDOR_DIR/openRepoTools"
SKILL_SOURCE="$VENDOR_DIR/skills/lane-swap/SKILL.md"
DELETED_SKILL="$REPO_ROOT/base-image/files/claude/skills/lane-swap/SKILL.md"

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

EXPECTED_SCENARIOS=8
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
DEFAULT_SETTINGS="$DEFAULT_CLAUDE/settings.json"
SESSION_START_SNIPPET='~/projects/xFactory/lanes-edit.sh session-start || true'
SESSION_START_MATCHER='startup|resume|clear|fork'
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

# `openRepoTools --install` exactly as scripts/setup-estate-commands.sh runs
# it: the vendored shim invoked as a FILE, with the no-fetch sentinel exported,
# so a fetch that should never happen fails loudly instead of quietly
# succeeding against the network.
run_install() {
    scenario
    env HOME="$FAKE_HOME" \
        OPENREPOTOOLS_BIN_DIR="$TEST_ROOT/bin" \
        CLAUDE_PROFILES_HOME="$BASE" \
        CLAUDE_USER_DIR="$DEFAULT_CLAUDE" \
        OPENREPOTOOLS_REPO=pinned-by-workBenches-no-fetch \
        OPENREPOTOOLS_REF=pinned-by-workBenches-no-fetch \
        "$TOOLS_SHIM" --install >"$TEST_ROOT/install.out" 2>&1
}

# ---------------------------------------------------------------------------
# 1. THE LOOP IS GONE, statically. The deleted paths are named here rather
# than only inferred from behaviour, because a loop that is merely never
# reached would pass every behavioural check below and still be a second
# writer the day something reaches it.
scenario
[[ ! -e "$DELETED_SKILL" ]] \
    || fail "deletion: $DELETED_SKILL is still vendored here; act 4b deletes the copy the loop installed from"; assertion
# CODE, not comments: the deletion note left behind names both of the things
# it deleted, and a comment is not a writer.
setup_code="$(grep -v '^[[:space:]]*#' "$SETUP")"
grep -q 'for skill in lane-swap' <<<"$setup_code" \
    && fail "deletion: the \`for skill in lane-swap\` loop is still in $SETUP"; assertion
grep -q 'default_session_start' <<<"$setup_code" \
    && fail "deletion: the ~/.claude SessionStart ensure is still in $SETUP"; assertion
# ... and the launcher's own ensure is NOT deleted: R-A8-5(b) is ratified and
# `--install` writes no profile's settings.json (Amendment 9(b)).
grep -q 'lane_session_start_command' "$REPO_ROOT/base-image/files/claude-profile" \
    || fail "deletion: the launcher's per-profile SessionStart ensure was removed, and act 4b keeps it"; assertion

# ---------------------------------------------------------------------------
# 2. A setup run places NO skill and NO SessionStart entry -- with a working
# lane estate present, which is the condition under which the deleted ensure
# would have fired.
XFACTORY="$FAKE_HOME/projects/xFactory"
mkdir -p "$XFACTORY"
printf '#!/usr/bin/env bash\ncase "$1" in session-start) exit 0 ;; esac\nexit 2\n' \
    > "$XFACTORY/lanes-edit.sh"
chmod +x "$XFACTORY/lanes-edit.sh"
run_setup
[[ ! -e "$SHARED_SKILL" ]] \
    || fail "no-write: setup placed a skill at $SHARED_SKILL, which is --install's path now"; assertion
[[ ! -e "$DEFAULT_SKILL" ]] \
    || fail "no-write: setup placed a skill at $DEFAULT_SKILL, which is --install's path now"; assertion
jq -e '.hooks.SessionStart // empty' "$DEFAULT_SETTINGS" >/dev/null 2>&1 \
    && fail "no-write: setup wrote a SessionStart entry into $DEFAULT_SETTINGS, which is --install's to merge"; assertion
# What this script still owns is untouched: the shared skills directory every
# profile symlinks to, and its own statusLine write at mode 600.
[[ -d "$BASE/shared/skills" ]] \
    || fail "no-write: the shared skills directory is no longer created, and --install writes into it"; assertion
[[ -L "$PROFILE_DIR/skills" ]] \
    || fail "no-write: the profile's skills is not a symlink to the shared directory"; assertion
[[ "$(jq -r '.statusLine.type' "$DEFAULT_SETTINGS")" == command ]] \
    || fail "no-write: the statusLine write was lost with the hook wiring"; assertion
[[ "$(stat -c '%a' "$DEFAULT_SETTINGS")" == 600 ]] \
    || fail "no-write: $DEFAULT_SETTINGS is mode $(stat -c '%a' "$DEFAULT_SETTINGS"), not 600"; assertion

# ---------------------------------------------------------------------------
# 3. THE INSTALL ACT IS THE WRITER. The vendored shim, run the way
# setup-estate-commands.sh runs it, places both skill copies and merges the
# hook -- with the no-fetch sentinel exported, so this also proves the skill's
# bytes are vendored rather than fetched. Without the pinned
# skills/lane-swap/SKILL.md beside the shim this run exits 2 having placed
# NOTHING: "could not fetch skills/lane-swap/SKILL.md from
# pinned-by-workBenches-no-fetch".
run_install
[[ -f "$SHARED_SKILL" ]] \
    || fail "install: --install placed nothing at $SHARED_SKILL ($(cat "$TEST_ROOT/install.out"))"; assertion
cmp -s "$SKILL_SOURCE" "$SHARED_SKILL" \
    || fail "install: the shared copy is not the pinned file"; assertion
[[ -f "$DEFAULT_SKILL" ]] \
    || fail "install: --install placed nothing at $DEFAULT_SKILL for a bare claude"; assertion
cmp -s "$SKILL_SOURCE" "$DEFAULT_SKILL" \
    || fail "install: the ~/.claude copy is not the pinned file"; assertion
cmp -s "$SKILL_SOURCE" "$PROFILE_DIR/skills/lane-swap/SKILL.md" \
    || fail "install: the skill is not readable through the profile's own skills symlink -- the F-S1 defect"; assertion
grep -q 'no-fetch' "$TEST_ROOT/install.out" \
    && fail "install: the sentinel was reached, so a fetch was attempted for a file that is pinned"; assertion
[[ "$(jq '(.hooks.SessionStart // []) | length' "$DEFAULT_SETTINGS")" -eq 1 ]] \
    || fail "install: $(jq '(.hooks.SessionStart // []) | length' "$DEFAULT_SETTINGS") SessionStart entries, expected 1"; assertion
[[ "$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$DEFAULT_SETTINGS")" == "$SESSION_START_SNIPPET" ]] \
    || fail "install: the merged command is not Amendment 8(e)'s canonical string"; assertion
[[ "$(jq -r '.hooks.SessionStart[0].matcher' "$DEFAULT_SETTINGS")" == "$SESSION_START_MATCHER" ]] \
    || fail "install: the merged matcher is not Amendment 8(e)'s"; assertion
[[ "$(jq -r '.hooks.SessionStart[0].hooks[0].timeout' "$DEFAULT_SETTINGS")" == 5 ]] \
    || fail "install: the merged timeout is not 5"; assertion
# The merge is additive: this script's statusLine survived it.
[[ "$(jq -r '.statusLine.type' "$DEFAULT_SETTINGS")" == command ]] \
    || fail "install: the merge replaced the file and lost the statusLine this script wrote"; assertion

# ---------------------------------------------------------------------------
# 4. EXACTLY ONE WRITER, proved the only way that matters: a setup run AFTER
# an install leaves every one of --install's three artifacts byte-for-byte and
# mode-for-mode alone. This is the whole point of act 4b -- the deleted loop
# stamped 0644 over a file --install owns, and the deleted ensure appended to
# a file --install merges.
before_shared="$(sha256sum "$SHARED_SKILL" | cut -d' ' -f1)"
before_default="$(sha256sum "$DEFAULT_SKILL" | cut -d' ' -f1)"
before_shared_mode="$(stat -c '%a' "$SHARED_SKILL")"
before_settings="$(cat "$DEFAULT_SETTINGS")"
touch -d '2001-01-01T00:00:00Z' "$SHARED_SKILL" "$DEFAULT_SKILL"
before_shared_mtime="$(stat -c '%Y' "$SHARED_SKILL")"
before_default_mtime="$(stat -c '%Y' "$DEFAULT_SKILL")"
run_setup
[[ "$(sha256sum "$SHARED_SKILL" | cut -d' ' -f1)" == "$before_shared" ]] \
    || fail "one writer: setup rewrote the shared skill --install placed"; assertion
[[ "$(sha256sum "$DEFAULT_SKILL" | cut -d' ' -f1)" == "$before_default" ]] \
    || fail "one writer: setup rewrote the ~/.claude skill --install placed"; assertion
[[ "$(stat -c '%Y' "$SHARED_SKILL")" == "$before_shared_mtime" ]] \
    || fail "one writer: setup touched the shared skill's mtime"; assertion
[[ "$(stat -c '%Y' "$DEFAULT_SKILL")" == "$before_default_mtime" ]] \
    || fail "one writer: setup touched the ~/.claude skill's mtime"; assertion
[[ "$(stat -c '%a' "$SHARED_SKILL")" == "$before_shared_mode" ]] \
    || fail "one writer: setup changed the shared skill's mode from $before_shared_mode to $(stat -c '%a' "$SHARED_SKILL") -- the exact defect act 4b closes"; assertion
[[ "$(jq -S . <<<"$before_settings")" == "$(jq -S . "$DEFAULT_SETTINGS")" ]] \
    || fail "one writer: setup changed the settings --install merged"; assertion
[[ "$(jq '(.hooks.SessionStart // []) | length' "$DEFAULT_SETTINGS")" -eq 1 ]] \
    || fail "one writer: setup appended a second SessionStart entry"; assertion

# ---------------------------------------------------------------------------
# 5. THE PINNED COPY IS THE ONLY COPY. A second SKILL.md anywhere in this
# repository is a second source of truth, which is what act 4b removed.
scenario
copies="$(find "$REPO_ROOT" -path "$REPO_ROOT/.git" -prune -o \
    -path '*/skills/lane-swap/SKILL.md' -print | sort)"
[[ "$copies" == "$SKILL_SOURCE" ]] \
    || fail "one source: expected only $SKILL_SOURCE, found:
$copies"; assertion
# ... and it is what the pin says it is, checked by the tool that owns the pin.
python3 "$REPO_ROOT/devBenches/base-image/update-upstream.py" check --source openrepotools >/dev/null \
    || fail "one source: the vendored copies do not match upstream-pin.yaml"; assertion
grep -q 'path: skills/lane-swap/SKILL.md' "$REPO_ROOT/devBenches/base-image/upstream-pin.yaml" \
    || fail "one source: the skill has no pin row, so nothing vendors it for the offline install"; assertion

# ---------------------------------------------------------------------------
# 6. The skill's own text (F-S5-F-S9, R-A8-6, R-A8-7).
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
# 7. RV-S1 regression (BLOCKING, opensoft/workBenches#63 re-verification): the
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
# 8. RV-S2 regression: step 5 must print --lane as a LEADING option, before
# the profile — claude-profile accepts --lane only as a leading option (before
# the action), so a trailing one would be handed to Claude itself, not to the
# launcher. Executes the shipped branch itself, both ways.
#
# THE VERB MOVED WITH THE PIN, AND THE INVARIANT DID NOT. Until adoption act
# 4b re-pinned this skill onto openRepoTools' Amendment 11 tooling commit the
# shipped branch built `pclaude run <profile>`; A11 drops the verb — it was
# always optional, and `pclaude <profile>` and `pclaude run <profile>` build
# the same argv — so the branch now builds `pclaude <profile>`. The exact-match
# assertions follow the PINNED text, because the pinned text is what every host
# runs. The two assertions after them do not mention the verb at all: `--lane`
# leads and the profile is last is the thing this scenario exists for, and it
# is asserted separately so the next wording change cannot quietly take it too.
scenario
step5_snippet="$(sed -n '/if \[\[ -n "\${row_write_refused:-}" \]\]; then/,/^fi$/p' "$SKILL_SOURCE")"
[[ -n "$step5_snippet" ]] \
    || fail "RV-S2: could not find step 5's restart-command branch to execute it"; assertion
lane=openRepoProject-1
CLAUDE_PROFILE_NAME=work
row_write_refused=""
eval "$step5_snippet"
restart_cmd_plain="$restart_cmd"
[[ "$restart_cmd_plain" == "pclaude work" ]] \
    || fail "RV-S2: normal-path restart_cmd='$restart_cmd_plain', expected the unqualified command"; assertion
row_write_refused=1
eval "$step5_snippet"
restart_cmd_lane="$restart_cmd"
[[ "$restart_cmd_lane" == "pclaude --lane openRepoProject-1 work" ]] \
    || fail "RV-S2: refused-write restart_cmd='$restart_cmd_lane', expected --lane as a LEADING option before the profile"; assertion
[[ "$restart_cmd_lane" == 'pclaude --lane openRepoProject-1 '* ]] \
    || fail "RV-S2: refused-write restart_cmd='$restart_cmd_lane' does not LEAD with --lane, so claude-profile would hand it to Claude instead of reading it"; assertion
[[ "$restart_cmd_lane" == *' work' ]] \
    || fail "RV-S2: refused-write restart_cmd='$restart_cmd_lane' does not END in the profile"; assertion

# AND THE PROSE HAS TO NAME THE COMMAND THE BRANCH ACTUALLY BUILDS. A skill
# whose executed snippet hands the reader `pclaude <profile>` while the
# sentence under it tells them to run `pclaude run <profile>` gives one answer
# and explains another, and both halves are copied into a terminal by hand.
#
# This is not hypothetical and not a style check: openRepoTools#26 round 1
# changed the snippet and left the sentence, which is how this assertion came
# to exist (reported at opensoft/openRepoTools#26, for its round 2 absorb).
#
# The expected wording is DERIVED from the branch that just ran, never
# hardcoded, so it holds across the verb change in both directions — it is
# green on the pre-A11 text (`run` in both halves) and green on A11's
# (`run` in neither) — and it does not fire on A11's deliberate equivalence
# sentence elsewhere in the file, which names both forms on purpose.
restart_bare_form="${restart_cmd_plain/% work/ <profile>}"
restart_prose="$(grep -F 'That one command is the whole restart: bare' "$SKILL_SOURCE" || true)"
[[ -n "$restart_prose" ]] \
    || fail "RV-S2: could not find the sentence that explains step 5's restart command"; assertion
[[ "$restart_prose" == *"\`$restart_bare_form\`"* ]] \
    || fail "RV-S2: the branch builds '$restart_cmd_plain', so the sentence explaining it should name \`$restart_bare_form\`, but it reads: $restart_prose"; assertion

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
echo "lane-swap skill install (act 4b: --install is the writer): $scenarios scenarios, $assertions assertions passed"
