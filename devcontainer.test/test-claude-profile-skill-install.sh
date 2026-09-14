#!/usr/bin/env bash
# Regression tests for the /lane-swap skill and its /swap alias command after
# lane-collision-protocol Amendment 9 adoption act 4b: WHO places them, who no
# longer does, and what the files themselves have to say.
#
# WHAT ACT 4B CHANGED HERE. Until act 4b, scripts/setup-claude-profiles.sh
# carried a `for skill in lane-swap` loop that installed SKILL.md into the
# shared skills directory and into ~/.claude, a `for command in swap` loop
# that did the same for the /swap alias command file, and a SessionStart
# ensure that appended Amendment 8(e)'s entry to ~/.claude/settings.json. Act
# 3 gave all three to `openRepoTools --install` (Amendment 9(b) on A8 Addendum
# 2's ratified R-A8-5, and A11 Addendum 4 ruling 9 for the command), and act
# 4b deleted them from that script together with the vendored copies they
# installed from. So this suite is inverted throughout: the assertions that
# used to prove the loops RAN now prove they are GONE, and two scenarios prove
# the install act is what places both artefacts.
#
# NEITHER FILE'S TEXT LEFT THIS REPOSITORY, they changed shelf. They are now
# devBenches/base-image/files/openrepotools/skills/lane-swap/SKILL.md and
# .../commands/swap.md, pinned copies under
# devBenches/base-image/upstream-pin.yaml (commit 8a36eb3, landed as
# opensoft/workBenches#78), vendored so that `--install` can place them with
# no network -- scripts/setup-estate-commands.sh exports
# OPENREPOTOOLS_REPO/_REF to a sentinel that cannot resolve. Every text
# assertion below therefore survives act 4b unchanged, reading the pinned
# copies instead of the deleted ones.
#
# THE ALIAS. Amendment 11 (SPEC §9) adds `/swap` as an alias of `/lane-swap`,
# and rules that the skill is NOT duplicated to get it: the alias is a command
# file whose body invokes the skill. So `commands/swap.md` is vendored beside
# the skill and installed on the same contract, into the same two places and
# for the same reason -- a profile's `commands` is a symlink to the shared
# directory, so that is the write the launcher reads, and the ~/.claude copy
# is for a bare `claude`.
#
# WHAT. The skill's own text carries F-S5-F-S9 and Amendment 11's SPEC §5,
# §7 and §9 additions: it is named /lane-swap in both name and description
# and names /swap as its alias; it never hands ` — ` to `lanes-edit.sh log`,
# which refuses it; it derives the row's leading state word instead of
# guessing it; it probes for the capability instead of asserting the stamps
# are manual; and step 5 prints ONE restart command with no menu and no
# `claude --resume` fallback, because /resume is not a lane surface (R-A8-6).
# The alias command file's own text carries SPEC §9's negative: it does not
# grow a second copy of the skill's steps. Every shell block in the skill is
# parsed here, because a skill is only copy-pasteable if it parses.
#
# This suite runs on the HOST, like test-setup-estate-commands.sh: it needs
# the repository's own scripts/ and base-image/, which are not in the
# container.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SETUP="$REPO_ROOT/scripts/setup-claude-profiles.sh"
VENDOR_DIR="$REPO_ROOT/devBenches/base-image/files/openrepotools"
TOOLS_SHIM="$VENDOR_DIR/openRepoTools"
SKILL_SOURCE="$VENDOR_DIR/skills/lane-swap/SKILL.md"
COMMAND_SOURCE="$VENDOR_DIR/commands/swap.md"
DELETED_SKILL="$REPO_ROOT/base-image/files/claude/skills/lane-swap/SKILL.md"
DELETED_COMMAND="$REPO_ROOT/base-image/files/claude/commands/swap.md"

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
SHARED_COMMAND="$BASE/shared/commands/swap.md"
DEFAULT_COMMAND="$DEFAULT_CLAUDE/commands/swap.md"
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
# 1. THE LOOPS ARE GONE, statically -- both the skills loop and the commands
# loop. The deleted paths are named here rather than only inferred from
# behaviour, because a loop that is merely never reached would pass every
# behavioural check below and still be a second writer the day something
# reaches it.
scenario
[[ ! -e "$DELETED_SKILL" ]] \
    || fail "deletion: $DELETED_SKILL is still vendored here; act 4b deletes the copy the skills loop installed from"; assertion
[[ ! -e "$DELETED_COMMAND" ]] \
    || fail "deletion: $DELETED_COMMAND is still vendored here; act 4b deletes the copy the commands loop installed from"; assertion
# CODE, not comments: the deletion note left behind names both of the things
# it deleted, and a comment is not a writer.
setup_code="$(grep -v '^[[:space:]]*#' "$SETUP")"
grep -q 'for skill in lane-swap' <<<"$setup_code" \
    && fail "deletion: the \`for skill in lane-swap\` loop is still in $SETUP"; assertion
grep -q 'for command in swap' <<<"$setup_code" \
    && fail "deletion: the \`for command in swap\` loop is still in $SETUP"; assertion
grep -q 'default_session_start' <<<"$setup_code" \
    && fail "deletion: the ~/.claude SessionStart ensure is still in $SETUP"; assertion
# ... and the launcher's own ensure is NOT deleted: R-A8-5(b) is ratified and
# `--install` writes no profile's settings.json (Amendment 9(b)).
grep -q 'lane_session_start_command' "$REPO_ROOT/base-image/files/claude-profile" \
    || fail "deletion: the launcher's per-profile SessionStart ensure was removed, and act 4b keeps it"; assertion
# The comment left in place of the loops cites verifiable evidence for the
# claim that `--install` already carries the command file, not just a date --
# so a reader can check it rather than take the comment's word for it.
grep -Fq '8a36eb3' "$SETUP" \
    || fail "deletion: the replacement comment does not cite the pin commit that carries commands/swap.md"; assertion
grep -Fq 'workBenches#78' "$SETUP" \
    || fail "deletion: the replacement comment does not cite the PR that landed the pin"; assertion

# ---------------------------------------------------------------------------
# 2. A setup run places NO skill, NO command, and NO SessionStart entry --
# with a working lane estate present, which is the condition under which the
# deleted ensure would have fired.
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
[[ ! -e "$SHARED_COMMAND" ]] \
    || fail "no-write: setup placed a command at $SHARED_COMMAND, which is --install's path now"; assertion
[[ ! -e "$DEFAULT_COMMAND" ]] \
    || fail "no-write: setup placed a command at $DEFAULT_COMMAND, which is --install's path now"; assertion
jq -e '.hooks.SessionStart // empty' "$DEFAULT_SETTINGS" >/dev/null 2>&1 \
    && fail "no-write: setup wrote a SessionStart entry into $DEFAULT_SETTINGS, which is --install's to merge"; assertion
# What this script still owns is untouched: the shared skills/commands
# directories every profile symlinks to, and its own statusLine write at mode
# 600.
[[ -d "$BASE/shared/skills" ]] \
    || fail "no-write: the shared skills directory is no longer created, and --install writes into it"; assertion
[[ -d "$BASE/shared/commands" ]] \
    || fail "no-write: the shared commands directory is no longer created, and --install writes into it"; assertion
[[ -L "$PROFILE_DIR/skills" ]] \
    || fail "no-write: the profile's skills is not a symlink to the shared directory"; assertion
[[ -L "$PROFILE_DIR/commands" ]] \
    || fail "no-write: the profile's commands is not a symlink to the shared directory"; assertion
[[ "$(jq -r '.statusLine.type' "$DEFAULT_SETTINGS")" == command ]] \
    || fail "no-write: the statusLine write was lost with the hook wiring"; assertion
[[ "$(stat -c '%a' "$DEFAULT_SETTINGS")" == 600 ]] \
    || fail "no-write: $DEFAULT_SETTINGS is mode $(stat -c '%a' "$DEFAULT_SETTINGS"), not 600"; assertion

# ---------------------------------------------------------------------------
# 3. THE INSTALL ACT IS THE WRITER, for both artefacts. The vendored shim, run
# the way setup-estate-commands.sh runs it, places both skill copies, both
# command copies, and merges the hook -- with the no-fetch sentinel exported,
# so this also proves the bytes are vendored rather than fetched. Without the
# pinned skills/lane-swap/SKILL.md and commands/swap.md beside the shim this
# run exits 2 having placed NOTHING: "could not fetch ... from
# pinned-by-workBenches-no-fetch".
run_install
[[ -f "$SHARED_SKILL" ]] \
    || fail "install: --install placed nothing at $SHARED_SKILL ($(cat "$TEST_ROOT/install.out"))"; assertion
cmp -s "$SKILL_SOURCE" "$SHARED_SKILL" \
    || fail "install: the shared skill copy is not the pinned file"; assertion
[[ -f "$DEFAULT_SKILL" ]] \
    || fail "install: --install placed nothing at $DEFAULT_SKILL for a bare claude"; assertion
cmp -s "$SKILL_SOURCE" "$DEFAULT_SKILL" \
    || fail "install: the ~/.claude skill copy is not the pinned file"; assertion
cmp -s "$SKILL_SOURCE" "$PROFILE_DIR/skills/lane-swap/SKILL.md" \
    || fail "install: the skill is not readable through the profile's own skills symlink -- the F-S1 defect"; assertion
[[ -f "$SHARED_COMMAND" ]] \
    || fail "install: --install placed nothing at $SHARED_COMMAND"; assertion
cmp -s "$COMMAND_SOURCE" "$SHARED_COMMAND" \
    || fail "install: the shared command copy is not the pinned file"; assertion
[[ -f "$DEFAULT_COMMAND" ]] \
    || fail "install: --install placed nothing at $DEFAULT_COMMAND for a bare claude"; assertion
cmp -s "$COMMAND_SOURCE" "$DEFAULT_COMMAND" \
    || fail "install: the ~/.claude command copy is not the pinned file"; assertion
cmp -s "$COMMAND_SOURCE" "$PROFILE_DIR/commands/swap.md" \
    || fail "install: /swap is not readable through the profile's own commands symlink -- the F-S1 defect, for commands"; assertion
# The alias is installed BESIDE the skill, not instead of it.
cmp -s "$SKILL_SOURCE" "$PROFILE_DIR/skills/lane-swap/SKILL.md" \
    || fail "install: the command was installed without the skill it invokes"; assertion
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
# an install leaves every one of --install's artefacts byte-for-byte and
# mode-for-mode alone -- both skill copies, both command copies, and the
# merged hook. This is the whole point of act 4b -- the deleted loops stamped
# 0644 over files --install owns, and the deleted ensure appended to a file
# --install merges.
before_shared="$(sha256sum "$SHARED_SKILL" | cut -d' ' -f1)"
before_default="$(sha256sum "$DEFAULT_SKILL" | cut -d' ' -f1)"
before_shared_mode="$(stat -c '%a' "$SHARED_SKILL")"
before_shared_command="$(sha256sum "$SHARED_COMMAND" | cut -d' ' -f1)"
before_default_command="$(sha256sum "$DEFAULT_COMMAND" | cut -d' ' -f1)"
before_shared_command_mode="$(stat -c '%a' "$SHARED_COMMAND")"
before_settings="$(cat "$DEFAULT_SETTINGS")"
touch -d '2001-01-01T00:00:00Z' "$SHARED_SKILL" "$DEFAULT_SKILL" "$SHARED_COMMAND" "$DEFAULT_COMMAND"
before_shared_mtime="$(stat -c '%Y' "$SHARED_SKILL")"
before_default_mtime="$(stat -c '%Y' "$DEFAULT_SKILL")"
before_shared_command_mtime="$(stat -c '%Y' "$SHARED_COMMAND")"
before_default_command_mtime="$(stat -c '%Y' "$DEFAULT_COMMAND")"
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
[[ "$(sha256sum "$SHARED_COMMAND" | cut -d' ' -f1)" == "$before_shared_command" ]] \
    || fail "one writer: setup rewrote the shared command --install placed"; assertion
[[ "$(sha256sum "$DEFAULT_COMMAND" | cut -d' ' -f1)" == "$before_default_command" ]] \
    || fail "one writer: setup rewrote the ~/.claude command --install placed"; assertion
[[ "$(stat -c '%Y' "$SHARED_COMMAND")" == "$before_shared_command_mtime" ]] \
    || fail "one writer: setup touched the shared command's mtime"; assertion
[[ "$(stat -c '%Y' "$DEFAULT_COMMAND")" == "$before_default_command_mtime" ]] \
    || fail "one writer: setup touched the ~/.claude command's mtime"; assertion
[[ "$(stat -c '%a' "$SHARED_COMMAND")" == "$before_shared_command_mode" ]] \
    || fail "one writer: setup changed the shared command's mode from $before_shared_command_mode to $(stat -c '%a' "$SHARED_COMMAND")"; assertion
[[ "$(jq -S . <<<"$before_settings")" == "$(jq -S . "$DEFAULT_SETTINGS")" ]] \
    || fail "one writer: setup changed the settings --install merged"; assertion
[[ "$(jq '(.hooks.SessionStart // []) | length' "$DEFAULT_SETTINGS")" -eq 1 ]] \
    || fail "one writer: setup appended a second SessionStart entry"; assertion

# ---------------------------------------------------------------------------
# 5. THE PINNED COPY IS THE ONLY COPY, for both artefacts. A second SKILL.md
# or swap.md anywhere in this repository is a second source of truth, which is
# what act 4b removed.
scenario
skill_copies="$(find "$REPO_ROOT" -path "$REPO_ROOT/.git" -prune -o \
    -path '*/skills/lane-swap/SKILL.md' -print | sort)"
[[ "$skill_copies" == "$SKILL_SOURCE" ]] \
    || fail "one source: expected only $SKILL_SOURCE, found:
$skill_copies"; assertion
command_copies="$(find "$REPO_ROOT" -path "$REPO_ROOT/.git" -prune -o \
    -path '*/commands/swap.md' -print | sort)"
[[ "$command_copies" == "$COMMAND_SOURCE" ]] \
    || fail "one source: expected only $COMMAND_SOURCE, found:
$command_copies"; assertion
# ... and both are what the pin says they are, checked by the tool that owns
# the pin.
python3 "$REPO_ROOT/devBenches/base-image/update-upstream.py" check --source openrepotools >/dev/null \
    || fail "one source: the vendored copies do not match upstream-pin.yaml"; assertion
grep -q 'path: skills/lane-swap/SKILL.md' "$REPO_ROOT/devBenches/base-image/upstream-pin.yaml" \
    || fail "one source: the skill has no pin row, so nothing vendors it for the offline install"; assertion
grep -q 'path: commands/swap.md' "$REPO_ROOT/devBenches/base-image/upstream-pin.yaml" \
    || fail "one source: the command file has no pin row, so nothing vendors it for the offline install"; assertion

# ---------------------------------------------------------------------------
# 6. The skill's own text (F-S5-F-S9, R-A8-6/7, Amendment 11 SPEC §5/§7/§9).
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
grep -q "win=\"\${win:+\$win }\$wid\"" "$SKILL_SOURCE" \
    || fail "text: the window sub-field does not carry the <@id> beside <session>:<index> (SPEC §5)"; assertion
# ... and the id is VALIDATED before it is recorded: a tmux too old to know the
# format prints the format back, and the object log is append-only.
# The whole guarded line, not just the check: an id is `@<digits>` and nothing
# else, a tmux too old to know the format prints the format back, and the object
# log is append-only, so the append must be the check's own consequent and not a
# separate statement that a later edit could leave behind.
grep -qF -- '[[ "$wid" =~ ^@[0-9]+$ ]] && win="${win:+$win }$wid"' "$SKILL_SOURCE" \
    || fail "text: the window id is appended without being checked for @<digits> (SPEC §5)"; assertion
# SPEC §5: a window or dir value carrying `, ` or ` — ` is REFUSED rather than
# appended, because the parser could not read the line back.
[[ "$(grep -c "refused=\"\$refused" "$SKILL_SOURCE")" -eq 2 ]] \
    || fail "text: the `, `/` — ` refusal does not cover BOTH window and dir (SPEC §5)"; assertion
# SPEC §7's uuid guard and R-A11-14's session-position wording (the previous
# revision of this suite pinned both by exact shape) moved on: A11 Addendum 4
# ruling 11 replaced the per-write uuid guard with a workstation guard
# ($ws_missing, gating writes (a)/(b)/(c) together and naming the gap in the
# handoff instead of a per-field placeholder), and the read that used to be
# inline at each of two call sites is now the one `sread` helper clause (h)
# calls for "one read, three callers". The pinned copy is read for what ruling
# 11 actually requires below (LANES_SESSION still passed explicitly, so
# session_for() is never left to guess); the exact prior mechanics are not
# re-asserted here, because they are not what the current text does.
# THE INSTALLED SKILL ENDS WITH THE `/rename <lane>` ACT (CF-W5, `R-A11-16`) —
# AND ITS PREMISE IS TRUE (CF2-W1). `lane-start` names every session it
# launches, the two RESUME branches included, since adoption act 0 merged as
# `opensoft/brett-wip#5` at `3719d97` (`lanes/lane-start:846`, `:855`, `:866`;
# SPEC rev 5 §13 act 0 item 2). The act stays, because a session that came up
# WITHOUT lane-start — a missing or refusing one, or a bare `claude` — still
# carries the name the harness derived and no API renames a running session from
# inside; what had to move is the reason printed beside it.
# Step 5's SHELL, not the paragraph under it: prose that explains the act is
# not the act, and what the operator reads at the end of a swap is what the
# shell prints.
step5_code="$(awk '/^## 5\./ { inside = 1 } inside && /^```/ { fence = !fence; next } inside && fence' "$SKILL_SOURCE")"
grep -Fq '/rename <lane>' <<<"$step5_code" \
    || fail "CF-W5: step 5 PRINTS the restart command without the act that fixes the derived name the next session comes up with"; assertion
# ...and what it prints beside it is the TRUE premise. The false one is refused
# by its own words in BOTH the printed line and the step's comment, so a revert
# of either fails here.
grep -Fq 'names every session it launches' <<<"$step5_code" \
    || fail "CF2-W1: step 5's printed act does not say lane-start names every branch it launches, which act 0 made true at 3719d97"; assertion
grep -Fq '3719d97' <<<"$step5_code" \
    || fail "CF2-W1: step 5's printed act makes a claim about lane-start and cites no commit for it"; assertion
grep -Fq 'names only the session it CREATES' <<<"$step5_code" \
    && fail "CF2-W1: step 5 still prints that lane-start names only the session it creates, which is false since 3719d97"; assertion
grep -Fq 'with this still open' "$SKILL_SOURCE" \
    && fail "CF2-W1: the skill still says adoption act 0 landed with the --name gap open; it closed it (3719d97)"; assertion
grep -Fq 'SPEC §13.3 gives to the TOOLING PR' "$SKILL_SOURCE" \
    && fail "CF2-W1: the skill still hands the --name fix to the tooling PR, which SPEC rev 5 §13 does not give it"; assertion
# BOTH WINDOW REFS ARE SHAPE-CHECKED (non-blocking 9). The skill's own reason
# for checking the id — "a tmux too old to know the format prints the format
# back … recording that string would put a lie in an append-only log" — reaches
# the `<session>:<index>` exactly as far, and only the id carried the check.
# The ref's own shape check migrated from a `[[ =~ ]]` regex to the `case`
# glob this skill uses for its other shape tests (`*:[0-9]*)`), read twice —
# the live read and the env-var fallback — same as the id's regex form below.
[[ "$(grep -Fc '*:[0-9]*)' "$SKILL_SOURCE")" -ge 2 ]] \
    || fail "the skill records a <session>:<index> without checking its shape, or checks it only once — the env fallback is another process's value and is unread too"; assertion
grep -Fq '=~ ^@[0-9]+$' "$SKILL_SOURCE" \
    || fail "the skill records a window id without checking its shape"; assertion
# The direct `${LANES_WORKSTATION:-}` read moved behind `$L workstation` (the
# helper's own subcommand, tab-field one), so the invariant this pins is
# "never `hostname`" rather than the exact assignment: `hostname` appears only
# in the comment that states the rule, never as a live `$(hostname` read.
grep -Fq 'ws_pair="$("$L" workstation' "$SKILL_SOURCE" \
    || fail "text: the workstation is not read through the shared helper (Evidence 6)"; assertion
[[ "$(grep -v '^[[:space:]]*#' "$SKILL_SOURCE" | grep -Fc '$(hostname')" -eq 0 ]] \
    || fail "text: the skill reads \$(hostname directly outside a comment, which Evidence 6 rules out"; assertion
grep -q 'LANES_SESSION="\$uuid"' "$SKILL_SOURCE" \
    || fail "text: the uuid is not passed to the writer explicitly, so session_for() can still guess (SPEC §7)"; assertion

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
# 9. The alias file's own text. SPEC §9 rules that the canonical name stays
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
echo "lane-swap skill + swap command install (act 4b: --install is the sole writer): $scenarios scenarios, $assertions assertions passed"
