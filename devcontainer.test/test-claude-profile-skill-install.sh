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
# THE ALIAS. Amendment 11 (SPEC §9) adds `/swap` as an alias of `/lane-swap`,
# and rules that the 176-line skill is NOT duplicated to get it: the alias is a
# command file whose body invokes the skill. So `commands/swap.md` is vendored
# beside the skill and installed by a second loop on the same contract, into the
# same two places and for the same reason — a profile's `commands` is a symlink
# to the shared directory, so that is the write the launcher reads, and the
# ~/.claude copy is for a bare `claude`. Sections 10-14 pin all of it, including
# the negative: that the command file does not grow a second copy of the steps,
# which is the failure mode §9 rejects by name.
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
COMMAND_SOURCE="$REPO_ROOT/base-image/files/claude/commands/swap.md"

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

EXPECTED_SCENARIOS=14
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
SHARED_COMMAND="$BASE/shared/commands/swap.md"
DEFAULT_COMMAND="$DEFAULT_CLAUDE/commands/swap.md"
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
# Amendment 11, SPEC §9: A8(a)'s "every surface names it /lane-swap" is amended,
# not reversed — the NAME stays lane-swap and the description still OPENS with
# the canonical /lane-swap (the F-S5 assertions above still stand, unchanged),
# and /swap is now named in it as the alias. Without this the alias command file
# installed beside the skill would name a surface the skill itself never does.
grep -q '^description: "/lane-swap (alias /swap) ' "$SKILL_SOURCE" \
    || fail "text: the description does not name /swap as the alias (Amendment 11, SPEC §9)"; assertion
# SPEC §5: the swap record's `window` sub-field is TWO space-separated refs and
# `dir` is a new sub-field. Grepping the assignments, not the prose, because the
# prose can say it while the shell writes the old payload.
grep -q 'payload="\$payload; window \$win"' "$SKILL_SOURCE" \
    || fail "text: step 4 does not write the window sub-field from a derived ref (SPEC §5)"; assertion
grep -q 'payload="\$payload; dir \$dir"' "$SKILL_SOURCE" \
    || fail "text: step 4 does not write the new dir sub-field (SPEC §5)"; assertion
grep -q "win=\"\${win:+\$win }\$win_id\"" "$SKILL_SOURCE" \
    || fail "text: the window sub-field does not carry the <@id> beside <session>:<index> (SPEC §5)"; assertion
# ... and the id is VALIDATED before it is recorded: a tmux too old to know the
# format prints the format back, and the object log is append-only.
# The whole guarded line, not just the check: an id is `@<digits>` and nothing
# else, a tmux too old to know the format prints the format back, and the object
# log is append-only, so the append must be the check's own consequent and not a
# separate statement that a later edit could leave behind.
grep -qF -- '[[ "$win_id" =~ ^@[0-9]+$ ]] && win="${win:+$win }$win_id"' "$SKILL_SOURCE" \
    || fail "text: the window id is appended without being checked for @<digits> (SPEC §5)"; assertion
# SPEC §5: a window or dir value carrying `, ` or ` — ` is REFUSED rather than
# appended, because the parser could not read the line back.
[[ "$(grep -c "refused=\"\$refused" "$SKILL_SOURCE")" -eq 2 ]] \
    || fail "text: the `, `/` — ` refusal does not cover BOTH window and dir (SPEC §5)"; assertion
# SPEC §7: `unknown` is not a transcript uuid and the object log is append-only,
# so the skill refuses on its own `log PAUSED` path BEFORE it writes, and names
# the act that supplies the uuid.
grep -q 'if \[\[ -z "\${uuid:-}" \]\]; then' "$SKILL_SOURCE" \
    || fail "text: step 4 writes the PAUSED line without first checking it has a uuid (SPEC §7)"; assertion
grep -q "REFUSED: no transcript uuid" "$SKILL_SOURCE" \
    || fail "text: the missing-uuid path does not refuse in as many words (SPEC §7)"; assertion
# ...AND THE REFUSAL IS (a)'s ALONE (SPEC §7, A11 Addendum 2 `R-A11-11`). The
# clause says the lane that has never had a session recorded reaches the refusal
# "where the swap writes the register's file-level PAUSED line and the row's
# state cell", so (b) and (c) sit OUTSIDE the uuid guard and the gap is named in
# the session position. A skill that drops them leaves a paused lane with no
# record at all, which is the one state a restart cannot resolve from. The line
# says which of the three writes it refuses, so a reader is not left to infer it.
grep -q "so nothing is written to the object log — (b) and (c) below still run" "$SKILL_SOURCE" \
    || fail "text: the refusal does not say WHICH of the three writes it refuses (SPEC §7/R-A11-11)"; assertion
uuid_guard="$(awk 'index($0,"if [[ -z \"${uuid:-}\" ]]; then"){inside=1} inside{print} inside && $0=="fi"{exit}' "$SKILL_SOURCE")"
printf '%s\n' "$uuid_guard" | grep -Fq 'append-line' \
    && fail "text: the register's file-level PAUSED line is inside the uuid guard, so a lane with no uuid gets neither half (SPEC §7/R-A11-11)"; assertion
printf '%s\n' "$uuid_guard" | grep -Fq 'replace-in-row' \
    && fail "text: the row's state cell is flipped only where a uuid exists, which is the same defect one write along (SPEC §7/R-A11-11)"; assertion
# THE SESSION POSITION IS `session <uuid>@<workstation>` AND NOTHING ELSE —
# `R-A11-14` (A11 Addendum 3, ratified by Brett Heap 2026-09-13 "a11 addendum 3
# yes"). Where there is no uuid the FIELD IS LEFT OUT and the line's own free
# text names the gap: `none recorded` was two tokens with a space inside a field
# Amendment 7(b):137 gives one uuid, which its :140 has REPORTED as
# `unreadable`, so the skill was writing a line its own parser cannot read back.
# And where there is no WORKSTATION the write is refused outright rather than
# filled with `unknown-workstation`: `append-line` validates neither half, so a
# placeholder lands in the register and no reader on the estate ever notices.
grep -Fq 'session_field="session $uuid@$ws, "' "$SKILL_SOURCE" \
    || fail "R-A11-14: the session position is not built from the uuid and the workstation alone"; assertion
grep -Fq 'NO session recorded for this lane' "$SKILL_SOURCE" \
    || fail "text: the file-level PAUSED line does not NAME the gap where no session is recorded (SPEC §7/R-A11-11)"; assertion
# The skill's SHELL — its fenced code blocks, comments stripped — because the
# prose argues about both words at length and would answer for the code.
skill_code_only="$(awk '/^```/ { fence = !fence; next } fence' "$SKILL_SOURCE" | grep -v '^[[:space:]]*#')"
printf '%s\n' "$skill_code_only" | grep -Fq 'none recorded' \
    && fail "R-A11-14: the skill still writes 'none recorded' into a field that takes one uuid"; assertion
printf '%s\n' "$skill_code_only" | grep -Fq 'unknown' \
    && fail "R-A11-14: the skill still writes a placeholder workstation into the register"; assertion
grep -Fq 'REFUSED: no workstation for this lane' "$SKILL_SOURCE" \
    || fail "R-A11-14: a writer with no configured workstation does not refuse"; assertion
grep -F 'REFUSED: no workstation for this lane' "$SKILL_SOURCE" | grep -Fq 'pclaude' \
    || fail "R-A11-14: the refusal does not name the launcher that sets LANES_WORKSTATION"; assertion
grep -Fq 'ws="${LANES_WORKSTATION:-}"' "$SKILL_SOURCE" \
    || fail "text: the workstation is not taken from configuration first (Evidence 6)"; assertion
# ONE hostname READ — the read, `$(hostname`, and not the word: the `R-A11-14`
# refusal names the hazard in its own message, and a count of the word would
# make saying it indistinguishable from doing it.
[[ "$(grep -v '^[[:space:]]*#' "$SKILL_SOURCE" | grep -Fc '$(hostname')" -eq 1 ]] \
    || fail "text: the skill reads hostname more than once, so one read is outside the container fence (Evidence 6)"; assertion
grep -q "Amendment 6(c)'s session-cell append that supplies one" "$SKILL_SOURCE" \
    || fail "text: the refusal does not name which act supplies the uuid (SPEC §7)"; assertion
grep -q 'LANES_SESSION="\$uuid"' "$SKILL_SOURCE" \
    || fail "text: the uuid is not passed to the writer explicitly, so session_for() can still guess (SPEC §7)"; assertion
# SPEC §9: under the automatic swap there is no operator to ask, so step 3's one
# question becomes a BOUNDED wait, and a writer still holding unpushed work when
# it elapses is named in the handoff. It still kills nothing and pushes nobody's
# work, so the manual branch's single question has to survive beside it.
grep -q 'Under the AUTOMATIC swap there is no operator to ask' "$SKILL_SOURCE" \
    || fail "text: step 3 has no automatic-swap branch (SPEC §9)"; assertion
grep -q 'named in the handoff' "$SKILL_SOURCE" \
    || fail "text: the bounded wait does not say what happens to a writer that outlasts it (SPEC §9)"; assertion
grep -q 'Ask the operator exactly one question' "$SKILL_SOURCE" \
    || fail "text: the manual branch's single question was lost when the automatic one was added (SPEC §9)"; assertion

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
# 9. RV-S2 regression: step 5 must print --lane as a LEADING option, before the
# profile — claude-profile accepts --lane only as a leading option (before the
# action), so a trailing one would be handed to Claude itself, not to the
# launcher. Executes the shipped branch itself, both ways.
#
# Amendment 11(1) drops the `run` verb from both branches: `pclaude <profile>`
# and `pclaude run <profile>` build the same argv, and the short form is what
# every surface now prints — the usage guard's automatic-swap directive
# included, so the skill and the hook cannot disagree about what the operator
# re-runs. The LEADING-option property is unchanged by that and is what this
# scenario exists for: with `run` gone there is no verb left between the option
# and the profile to hide a trailing one behind.
scenario
step5_snippet="$(sed -n '/if \[\[ -n "\${row_write_refused:-}" \]\]; then/,/^fi$/p' "$SKILL_SOURCE")"
[[ -n "$step5_snippet" ]] \
    || fail "RV-S2: could not find step 5's restart-command branch to execute it"; assertion
lane=openRepoProject-1
CLAUDE_PROFILE_NAME=work
row_write_refused=""
eval "$step5_snippet"
[[ "$restart_cmd" == "pclaude work" ]] \
    || fail "RV-S2: normal-path restart_cmd='$restart_cmd', expected the unqualified one-word command (Amendment 11(1))"; assertion
row_write_refused=1
eval "$step5_snippet"
[[ "$restart_cmd" == "pclaude --lane openRepoProject-1 work" ]] \
    || fail "RV-S2: refused-write restart_cmd='$restart_cmd', expected --lane as a LEADING option before the profile"; assertion
# A `run` left anywhere in either branch is the regression: the two surfaces
# would then print different commands for the same act.
[[ "$step5_snippet" != *' run '* ]] \
    || fail "RV-S2: step 5 still prints the 'run' verb, which Amendment 11(1) drops: $step5_snippet"; assertion

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

# ---------------------------------------------------------------------------
# 10. The `/swap` ALIAS is installed on the skills loop's contract (Amendment
# 11, SPEC §9): into the shared commands directory, which is what the launcher
# reads because every profile's `commands` is a symlink to it, and into
# ~/.claude/commands for a bare `claude`. The symlink assertion is the one that
# matters — installing only into ~/.claude is precisely the F-S1 defect that
# left the skill unlisted on 418 profiles, and `commands` is linked by the same
# `for item in skills agents commands rules` loop that linked `skills`.
run_setup
[[ -f "$SHARED_COMMAND" ]] \
    || fail "alias install: nothing at $SHARED_COMMAND"; assertion
cmp -s "$COMMAND_SOURCE" "$SHARED_COMMAND" \
    || fail "alias install: the shared copy is not the vendored file"; assertion
[[ "$(stat -c '%a' "$SHARED_COMMAND")" == 644 ]] \
    || fail "alias install: the shared copy is mode $(stat -c '%a' "$SHARED_COMMAND"), not 644"; assertion
[[ -f "$DEFAULT_COMMAND" ]] \
    || fail "alias install: nothing at $DEFAULT_COMMAND for a bare claude"; assertion
cmp -s "$COMMAND_SOURCE" "$DEFAULT_COMMAND" \
    || fail "alias install: the ~/.claude copy is not the vendored file"; assertion
[[ -L "$PROFILE_DIR/commands" ]] \
    || fail "alias install: the profile's commands is not a symlink ($(ls -ld "$PROFILE_DIR/commands" 2>&1))"; assertion
cmp -s "$COMMAND_SOURCE" "$PROFILE_DIR/commands/swap.md" \
    || fail "alias install: /swap is not readable through the profile's own commands symlink — the F-S1 defect, for commands"; assertion
# The alias is installed BESIDE the skill, not instead of it: /swap invokes
# `lane-swap`, so a profile that has the command and not the skill has a slash
# command that resolves to nothing.
cmp -s "$SKILL_SOURCE" "$PROFILE_DIR/skills/lane-swap/SKILL.md" \
    || fail "alias install: the command was installed without the skill it invokes"; assertion

# ---------------------------------------------------------------------------
# 11. Idempotent by CONTENT, exactly as section 2 pins for the skill: a second
# run leaves an identical destination untouched, mtime and all, so Amendment 9's
# act 3 handover to `openRepoTools --install` is not clobbered by the next setup
# run (workBenches#68 F5). Two writers of one file is the thing A9(b) rules
# against, and content-idempotence is what makes the overlap survivable.
touch -d '2001-01-01T00:00:00Z' "$SHARED_COMMAND" "$DEFAULT_COMMAND"
before_shared_command="$(stat -c '%Y' "$SHARED_COMMAND")"
before_default_command="$(stat -c '%Y' "$DEFAULT_COMMAND")"
run_setup
[[ "$(stat -c '%Y' "$SHARED_COMMAND")" == "$before_shared_command" ]] \
    || fail "alias idempotent: the shared copy was rewritten although its content already matched"; assertion
[[ "$(stat -c '%Y' "$DEFAULT_COMMAND")" == "$before_default_command" ]] \
    || fail "alias idempotent: the ~/.claude copy was rewritten although its content already matched"; assertion
cmp -s "$COMMAND_SOURCE" "$SHARED_COMMAND" \
    || fail "alias idempotent: the shared copy changed"; assertion

# ---------------------------------------------------------------------------
# 12. And a hand-edited destination IS repaired: until A9's act 3 this loop is
# the writer, so drift is corrected rather than preserved. This is the other
# half of section 11 — content-idempotence must not degrade into "never write".
printf 'not the alias\n' > "$SHARED_COMMAND"
printf 'not the alias either\n' > "$DEFAULT_COMMAND"
run_setup
cmp -s "$COMMAND_SOURCE" "$SHARED_COMMAND" \
    || fail "alias drift: a shared copy that differed was not put back"; assertion
cmp -s "$COMMAND_SOURCE" "$DEFAULT_COMMAND" \
    || fail "alias drift: a ~/.claude copy that differed was not put back"; assertion
[[ "$(stat -c '%a' "$SHARED_COMMAND")" == 644 ]] \
    || fail "alias drift: the restored copy is mode $(stat -c '%a' "$SHARED_COMMAND"), not 644"; assertion

# ---------------------------------------------------------------------------
# 13. A vendored source that is NOT there is skipped, not fatal — the skills
# loop's `[[ -f ]] || continue`, carried over. This file runs on checkouts that
# predate the command, and `set -euo pipefail` at the top of it turns any
# unguarded read of a missing source into a failed setup for every profile on
# the machine. Proved against a MIRROR repo (symlinks to the real scripts/ and
# skills/, and no commands/ at all) rather than by moving the real source
# aside, so the checkout under test is never mutated.
MIRROR="$TEST_ROOT/repo-without-commands"
MIRROR_HOME="$TEST_ROOT/home-mirror"
MIRROR_BASE="$MIRROR_HOME/.claude-profiles"
MIRROR_DEFAULT_CLAUDE="$MIRROR_HOME/.claude"
mkdir -p "$MIRROR/scripts" "$MIRROR/base-image/files/claude" "$MIRROR_HOME"
ln -s "$SETUP" "$MIRROR/scripts/setup-claude-profiles.sh"
ln -s "$REPO_ROOT/base-image/files/claude-statusline-command.sh" \
      "$MIRROR/base-image/files/claude-statusline-command.sh"
ln -s "$REPO_ROOT/base-image/files/claude/skills" "$MIRROR/base-image/files/claude/skills"
scenario
mirror_status=0
env HOME="$MIRROR_HOME" \
    XDG_CONFIG_HOME="$MIRROR_HOME/.config" \
    CLAUDE_PROFILES_HOME="$MIRROR_BASE" \
    WORKBENCHES_DEFAULT_CLAUDE_HOME="$MIRROR_DEFAULT_CLAUDE" \
    "$MIRROR/scripts/setup-claude-profiles.sh" --manifest "$MANIFEST" \
    >/dev/null 2>"$TEST_ROOT/mirror.err" || mirror_status=$?
[[ "$mirror_status" -eq 0 ]] \
    || fail "missing source: setup exited $mirror_status instead of skipping an absent command — $(cat "$TEST_ROOT/mirror.err")"; assertion
[[ ! -e "$MIRROR_BASE/shared/commands/swap.md" ]] \
    || fail "missing source: something was installed from a source that does not exist"; assertion
[[ ! -e "$MIRROR_DEFAULT_CLAUDE/commands/swap.md" ]] \
    || fail "missing source: something was installed into ~/.claude from a source that does not exist"; assertion
# ... and the run really did the REST of its work, so the pass above is a skip
# and not an early exit that happened to return 0.
cmp -s "$SKILL_SOURCE" "$MIRROR_BASE/shared/skills/lane-swap/SKILL.md" \
    || fail "missing source: the run did not get as far as the skill, so the 'skip' proves nothing"; assertion

# ---------------------------------------------------------------------------
# 14. The alias file's own text. SPEC §9 rules that the canonical name stays
# `lane-swap` and the skill is NOT duplicated: "two copies of one skill that
# must stay byte-equal is the rejected alternative", for the reason A9(b) gives
# about two writers of one file. So the assertions that matter here are the
# NEGATIVE ones — a command file that grew a second copy of the five steps is
# the failure, and it would pass every assertion above.
scenario
head -n 1 "$COMMAND_SOURCE" | grep -q '^---$' \
    || fail "alias text: no frontmatter fence, so it does not match the repo's command-file convention"; assertion
grep -q '^name: ' "$COMMAND_SOURCE" \
    || fail "alias text: no name: field (the convention the opsx/ command files set)"; assertion
grep -q '^description: ' "$COMMAND_SOURCE" \
    || fail "alias text: no description: field"; assertion
grep -q 'lane-swap' "$COMMAND_SOURCE" \
    || fail "alias text: the body never names the skill it is an alias of"; assertion
grep -qi 'invoke the `lane-swap` skill' "$COMMAND_SOURCE" \
    || fail "alias text: the body does not tell the session to invoke the skill"; assertion
command_lines="$(wc -l < "$COMMAND_SOURCE")"
[[ "$command_lines" -le 20 ]] \
    || fail "alias text: $command_lines lines; §9 rules the alias is a command file that invokes the skill, not a copy of it"; assertion
for duplicated in 'READY TO SWAP' 'replace-in-row' 'append-row-status' 'lanes-edit.sh' 'log PAUSED'; do
    grep -qF -- "$duplicated" "$COMMAND_SOURCE" \
        && fail "alias text: the command file restates the skill's own machinery ('$duplicated') — §9's rejected alternative"; assertion
done

[[ "$scenarios" -eq "$EXPECTED_SCENARIOS" ]] \
    || fail "$scenarios scenarios ran, $EXPECTED_SCENARIOS expected — one was added or lost without saying so"
echo "lane-swap skill install: $scenarios scenarios, $assertions assertions passed"
