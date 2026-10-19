#!/usr/bin/env bash
# Regression test for scripts/setup-estate-commands.sh (opensoft/workBenches#37,
# grown for opensoft/openRepoTools#26 and re-grown for opensoft/openRepoTools
# #45): the host's openRepoShape, and openRepoTools's own TWENTY-NINE
# artifacts -- the FIFTEEN files `openRepoTools --install` places on $PATH
# (itself, park, resume, status, lane, lanes, lane-handoff, lane-rename, the
# four lane helpers `lanes-edit.sh`, `lane-start`, `lane-end` and
# `link-estates` with the alias table `repos.tsv` they read, and the two
# Claude Code launch commands `claude-current` and `claude-restart-check`,
# opensoft/workBenches#119), the `handoff`, `lane-swap`
# and `restart` skills, the `handoff`, `ctx` and `swap` command files, and
# the merged `SessionStart` and `UserPromptSubmit` entries in
# `~/.claude/settings.json` -- all come from workBenches' own vendored pin
# (TWENTY-ONE pinned openrepotools paths, plus openRepoShape's own two), and
# the script places them, re-places them when they differ from the pin
# (either direction), and refuses to place anything when the vendored
# copies themselves no longer match the pin. Every scenario runs with $HOME
# sandboxed under a throwaway directory, AND CLAUDE_PROFILES_HOME/
# CLAUDE_USER_DIR pinned explicitly to that same directory's
# .claude-profiles/.claude -- `skills_home`/`claude_home` read those two
# variables first and only fall back to $HOME when either is unset, so
# sandboxing $HOME alone is not enough if the invoking shell (a developer's,
# or CI's) happens to export one of them for its own purposes. The skills, the
# command files and the hook are written under there
# (~/.claude-profiles/... and ~/.claude/...), not just under the bin dir the
# *_BIN_DIR overrides reach -- so a run of this suite never touches the real
# machine's profiles, skills or settings.json, nor any other profile's.
#
# Scenarios (g)-(m) guard the adversarial review round's D1-D6 findings: a
# symlinked target (D1), a directory target (D2), unpinned bytes reaching
# the shims from the network (D3), a partial install across two independent
# shim transactions (D4), the pin file itself missing, and the placed
# files' mode. D3 now has two parts, both inside scenario (k): the first
# proves scripts/setup-estate-commands.sh's OWN pre-flight (`require_pin_row`,
# now checking all twenty-one openrepotools paths) refuses a documented
# row-and-file removal before either shim runs, so no fetch is ever
# reachable through this script's front door -- exactly the guarantee this
# scenario always proved, just extended past the original five names. The
# second part proves the defense-in-depth layer that pre-flight exists to
# backstop actually works when reached: called directly, with a file missing
# beside it, `openRepoTools --install` itself tries to fetch that file under
# openRepoTools#26's all-or-nothing rule, and the sentinel this script
# exports refuses it by name. Neither path ever reaches a real network.
#
# Scenarios (n) and (o) guard opensoft/openRepoTools#45's `RETIRED=(restart)`
# (Copilot's review of opensoft/workBenches#91, `openRepoTools:277`, "not
# exercised... a future change could therefore leave the retired executable
# on PATH -- or delete the wrong one -- while the reported checks still
# pass"): the two ownership branches `retire_commands` decides between, an
# installer-owned stale copy (removed) and a person's own file of the same
# name (named and left, byte for byte).
#
# Scenarios (ab)-(ah), at the END of this file (they test the host step, and sit
# after the others only to keep the other letters where they were), guard
# opensoft/workBenches#159: the host's openRepoShape is held on the pin's
# commit by the record `openRepoShape --install` writes beside it, fetching
# nothing (hazard 1: it used to record nothing and remove a record, so the
# host followed main), and the caller's own $OPENREPOSHAPE_RECORD_REF never
# reaches that install (hazard 2: with it set to 1 the install recorded the
# no-fetch sentinel as the command's ref).

set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$TEST_DIR/.." && pwd -P)"
SCRIPT_UNDER_TEST="$REPO_ROOT/scripts/setup-estate-commands.sh"
BASE_IMAGE_DIR="$REPO_ROOT/devBenches/base-image"
PIN_FILE="$BASE_IMAGE_DIR/upstream-pin.yaml"

SHAPE_VENDOR="$BASE_IMAGE_DIR/files/openreposhape/openRepoShape"
TOOLS_VENDOR="$BASE_IMAGE_DIR/files/openrepotools/openRepoTools"
PARK_VENDOR="$BASE_IMAGE_DIR/files/openrepotools/park"
RESUME_VENDOR="$BASE_IMAGE_DIR/files/openrepotools/resume"
STATUS_VENDOR="$BASE_IMAGE_DIR/files/openrepotools/status"

# THE FIFTEEN FILES `openRepoTools --install` places on $PATH (openRepoTools#26
# and #45, and opensoft/workBenches#119's two launch commands at the END). One
# list, so scenarios (a), (b) and (l) cannot disagree about what a complete
# bin-directory install is.
TOOLS_FILES=(openRepoTools park resume status lane lanes lane-handoff lane-rename lanes-edit.sh lane-start lane-end link-estates repos.tsv claude-current claude-restart-check lanes-index lane-worktrees)
tools_vendor_path() { printf '%s/files/openrepotools/%s\n' "$BASE_IMAGE_DIR" "$1"; }

SKILL_NAMES=(handoff lane-swap restart)
COMMAND_NAMES=(handoff ctx swap)

TMPDIR_ROOT="$(mktemp -d)"
# Each scenario supplies its own HOME. Host XDG/receipt overrides must not send
# fixture installation records into the real user's data directory.
unset XDG_DATA_HOME OPENREPOTOOLS_DATA_DIR
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

failures=0

pass() {
    printf 'PASS: %s\n' "$1"
}

fail() {
    printf 'FAIL: %s\n' "$1"
    failures=$((failures + 1))
}

assert_equal() {
    local actual="$1"
    local expected="$2"
    local label="$3"
    if [ "$actual" = "$expected" ]; then
        pass "$label"
    else
        fail "$label: expected [$expected], got [$actual]"
    fi
}

assert_matches() {
    local actual="$1"
    local pattern="$2"
    local label="$3"
    if [[ "$actual" =~ $pattern ]]; then
        pass "$label"
    else
        fail "$label: [$actual] does not match /$pattern/"
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local label="$3"
    if grep -Fq -- "$needle" <<<"$haystack"; then
        pass "$label"
    else
        fail "$label: output does not contain: $needle"
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local label="$3"
    if grep -Fq -- "$needle" <<<"$haystack"; then
        fail "$label: output unexpectedly contains: $needle"
    else
        pass "$label"
    fi
}

count_occurrences() {
    # A bare `grep -c` with zero matches exits 1, which would abort this
    # test script under `set -e` if not for the `|| true` guard here.
    grep -Fc -- "$2" <<<"$1" || true
}

assert_file_executable() {
    local path="$1"
    local label="$2"
    if [ -f "$path" ] && [ -x "$path" ]; then
        pass "$label"
    else
        fail "$label: $path missing or not executable"
    fi
}

assert_identical() {
    local a="$1"
    local b="$2"
    local label="$3"
    if cmp -s "$a" "$b"; then
        pass "$label"
    else
        fail "$label: $a differs from $b"
    fi
}

assert_empty_dir() {
    local dir="$1"
    local label="$2"
    if [ -z "$(find "$dir" -mindepth 1 2>/dev/null)" ]; then
        pass "$label"
    else
        fail "$label: $dir is not empty"
    fi
}

assert_absent() {
    # For a path that must not even have been CREATED (unlike
    # assert_empty_dir, which needs the directory to already exist) --
    # `find` on a missing path is not something the two assert_mode/
    # assert_empty_dir helpers should have to guard against, so this one
    # never shells out to `find` at all.
    local path="$1"
    local label="$2"
    if [ -e "$path" ] || [ -L "$path" ]; then
        fail "$label: $path unexpectedly exists"
    else
        pass "$label"
    fi
}

assert_mode() {
    local path="$1"
    local expected="$2"
    local label="$3"
    local actual
    # A path that does not exist at all must FAIL the assertion, not kill
    # this whole test script: `stat` on a missing path fails on both the
    # GNU and BSD branches below, and a bare `actual="$(A || B)"` with both
    # A and B failing is a nonzero-exit assignment, which `set -e` treats as
    # this script's own failure -- exactly the crash this suite hit when
    # Scenario (l) asked for the mode of a bin file the old four/five-file
    # contract never placed. Checking existence first, before ever calling
    # `stat`, turns that crash into an ordinary FAIL line.
    if [ ! -e "$path" ]; then
        fail "$label: $path does not exist"
        return
    fi
    actual="$(stat -c '%a' "$path" 2>/dev/null || stat -f '%Lp' "$path" 2>/dev/null || true)"
    assert_equal "$actual" "$expected" "$label"
}

# Independent of the script under test: read the two pinned commits straight
# out of the YAML, the same file the script itself must agree with.
pin_commit_for() {
    local id="$1"
    awk -v id="$id" '
        $0 ~ "^  - id: " id "$" { found=1; next }
        found && /^  - id:/ { found=0 }
        found && /^    commit:/ {
            line = $0
            gsub(/^    commit: *"?/, "", line)
            gsub(/"$/, "", line)
            print line
            exit
        }
    ' "$PIN_FILE"
}

SHAPE_COMMIT="$(pin_commit_for openreposhape)"
TOOLS_COMMIT="$(pin_commit_for openrepotools)"
assert_matches "$SHAPE_COMMIT" '^[0-9a-f]{40}$' 'pin file yields a 40-hex openreposhape commit'
assert_matches "$TOOLS_COMMIT" '^[0-9a-f]{40}$' 'pin file yields a 40-hex openrepotools commit'

# Asserts both destinations a skill or the command file is placed at
# (Amendment 9(b): the shared profiles copy and the bare ~/.claude copy),
# byte-identical to the vendored source and mode 0644 -- a document a
# session reads, not a command.
assert_skill_pair() {
    local home="$1" name="$2" label="$3"
    local vendor="$BASE_IMAGE_DIR/files/openrepotools/skills/$name/SKILL.md"
    assert_identical "$home/.claude-profiles/shared/skills/$name/SKILL.md" "$vendor" "$label: shared copy matches the vendored SKILL.md"
    assert_identical "$home/.claude/skills/$name/SKILL.md" "$vendor" "$label: bare copy matches the vendored SKILL.md"
    assert_mode "$home/.claude-profiles/shared/skills/$name/SKILL.md" '644' "$label: shared copy is mode 0644"
    assert_mode "$home/.claude/skills/$name/SKILL.md" '644' "$label: bare copy is mode 0644"
}

assert_command_pair() {
    local home="$1" name="$2" label="$3"
    local vendor="$BASE_IMAGE_DIR/files/openrepotools/commands/$name.md"
    assert_identical "$home/.claude-profiles/shared/commands/$name.md" "$vendor" "$label: shared copy matches the vendored command file"
    assert_identical "$home/.claude/commands/$name.md" "$vendor" "$label: bare copy matches the vendored command file"
    assert_mode "$home/.claude-profiles/shared/commands/$name.md" '644' "$label: shared copy is mode 0644"
    assert_mode "$home/.claude/commands/$name.md" '644' "$label: bare copy is mode 0644"
}

assert_hook_present() {
    local home="$1" label="$2"
    local settings="$home/.claude/settings.json"
    if [ ! -f "$settings" ]; then
        fail "$label: $settings does not exist"
        return
    fi
    assert_contains "$(cat "$settings")" 'lanes-edit.sh session-start' "$label: settings.json carries the SessionStart command"
    assert_mode "$settings" '600' "$label: settings.json is mode 0600"
}

# lane-collision-protocol Amendment 12's UserPromptSubmit name guard, merged
# into the same file as the SessionStart entry above -- one write for the
# pair, so this is a second assertion on the same settings.json rather than
# a second file.
assert_guard_hook_present() {
    local home="$1" label="$2"
    local settings="$home/.claude/settings.json"
    if [ ! -f "$settings" ]; then
        fail "$label: $settings does not exist"
        return
    fi
    assert_contains "$(cat "$settings")" 'lanes-edit.sh guard' "$label: settings.json carries the UserPromptSubmit guard command"
    assert_mode "$settings" '600' "$label: settings.json is mode 0600"
}

assert_hooks_deferred() {
    local settings="$1/.claude/settings.json" label="$2"
    if [ ! -e "$settings" ]; then
        pass "$label: no settings file calling an absent target"
    elif jq -e '[.hooks.SessionStart[]?.hooks[]?.command,
                  .hooks.UserPromptSubmit[]?.hooks[]?.command]
                 | all(. != "~/projects/xFactory/lanes-edit.sh guard"
                       and . != "~/projects/xFactory/lanes-edit.sh session-start || true")' "$settings" >/dev/null; then
        pass "$label: neither hook calls an absent target"
    else
        fail "$label: an unready hook was installed"
    fi
}

printf '%s\n' '--- Scenario (a): fresh bin dir + fresh $HOME installs all TWENTY-NINE openRepoTools artifacts, plus openRepoShape ---'
BIN_A="$TMPDIR_ROOT/bin-a"
HOME_A="$TMPDIR_ROOT/home-a"
mkdir -p "$BIN_A" "$HOME_A"
STATUS_A=0
OUTPUT_A="$(HOME="$HOME_A" \
    CLAUDE_PROFILES_HOME="$HOME_A/.claude-profiles" CLAUDE_USER_DIR="$HOME_A/.claude" \
    OPENREPOSHAPE_BIN_DIR="$BIN_A" OPENREPOTOOLS_BIN_DIR="$BIN_A" \
    "$SCRIPT_UNDER_TEST" 2>&1)" || STATUS_A=$?

assert_equal '0' "$STATUS_A" 'fresh install exit code'
assert_file_executable "$BIN_A/openRepoShape" 'fresh install places openRepoShape, executable'
assert_identical "$BIN_A/openRepoShape" "$SHAPE_VENDOR" 'fresh openRepoShape is byte-identical to the vendored copy'
assert_contains "$OUTPUT_A" 'openRepoShape: installed at' 'fresh install reports an installed verb for openRepoShape'
for name in "${TOOLS_FILES[@]}"; do
    assert_file_executable "$BIN_A/$name" "fresh install places $name, executable"
    assert_identical "$BIN_A/$name" "$(tools_vendor_path "$name")" "fresh $name is byte-identical to the vendored copy"
    assert_contains "$OUTPUT_A" "$name: installed at" "fresh install reports an installed verb for $name"
done
assert_contains "$OUTPUT_A" 'openRepoTools: 17 of 17 placed in' 'fresh install reports all fifteen openRepoTools bin files placed'
for name in "${SKILL_NAMES[@]}"; do
    assert_skill_pair "$HOME_A" "$name" "fresh install places the $name skill"
    assert_contains "$OUTPUT_A" "$name: installed at" "fresh install reports an installed verb for the $name skill"
done
for name in "${COMMAND_NAMES[@]}"; do
    assert_command_pair "$HOME_A" "$name" "fresh install places the /$name command file"
    assert_contains "$OUTPUT_A" "/$name: installed at" "fresh install reports an installed verb for /$name"
done
assert_hooks_deferred "$HOME_A" 'fresh install defers the pair until workspace linking'
assert_contains "$OUTPUT_A" 'SessionStart hook: deferred' 'fresh install reports SessionStart deferred'
assert_hooks_deferred "$HOME_A" 'fresh install has no broken prompt hook'
assert_contains "$OUTPUT_A" 'UserPromptSubmit guard: deferred' 'fresh install reports the prompt guard deferred'
assert_contains "$OUTPUT_A" "openRepoShape pinned at $SHAPE_COMMIT" 'fresh install prints the openRepoShape pin commit'
assert_contains "$OUTPUT_A" "openRepoTools pinned at $TOOLS_COMMIT" 'fresh install prints the openRepoTools pin commit'
assert_contains "$OUTPUT_A" 'Estate commands verified against the vendored pin.' 'fresh install reports success only after post-install verification'
# Scenario (f) folded in here: a brand-new temp dir is never on $PATH. Fix 4
# removed this script's own PATH warning (the shims already print theirs),
# so the substring must appear exactly twice -- once per shim -- not three
# times. Twenty-eight more report lines from the skills, the command files and
# the two hook entries do not add a third: none of them mentions $PATH at all.
path_warning_count="$(count_occurrences "$OUTPUT_A" 'is not on $PATH')"
assert_equal '2' "$path_warning_count" 'exactly two PATH warnings (one per shim; this script prints no third copy)'

printf '%s\n' '--- Scenario (b): a second run over an already-installed bin dir and $HOME reports unchanged ---'
STATUS_B=0
OUTPUT_B="$(HOME="$HOME_A" \
    CLAUDE_PROFILES_HOME="$HOME_A/.claude-profiles" CLAUDE_USER_DIR="$HOME_A/.claude" \
    OPENREPOSHAPE_BIN_DIR="$BIN_A" OPENREPOTOOLS_BIN_DIR="$BIN_A" \
    "$SCRIPT_UNDER_TEST" 2>&1)" || STATUS_B=$?

assert_equal '0' "$STATUS_B" 'second run exit code'
assert_contains "$OUTPUT_B" 'openRepoShape: already installed at' 'second run reports openRepoShape unchanged'
assert_identical "$BIN_A/openRepoShape" "$SHAPE_VENDOR" 'openRepoShape still byte-identical after the second run'
for name in "${TOOLS_FILES[@]}"; do
    assert_contains "$OUTPUT_B" "$name: already installed at" "second run reports $name unchanged"
    assert_identical "$BIN_A/$name" "$(tools_vendor_path "$name")" "$name still byte-identical after the second run"
done
for name in "${SKILL_NAMES[@]}"; do
    assert_contains "$OUTPUT_B" "$name: already installed at" "second run reports the $name skill unchanged"
    assert_skill_pair "$HOME_A" "$name" "second run still has the $name skill"
done
for name in "${COMMAND_NAMES[@]}"; do
    assert_contains "$OUTPUT_B" "/$name: already installed at" "second run reports /$name unchanged"
    assert_command_pair "$HOME_A" "$name" "second run still has the /$name command file"
done
assert_contains "$OUTPUT_B" 'SessionStart hook: deferred' 'second run still reports SessionStart deferred'
assert_hooks_deferred "$HOME_A" 'second run still defers the unready hook'
assert_contains "$OUTPUT_B" 'UserPromptSubmit guard: deferred' 'second run reports the guard hook unchanged'
assert_hooks_deferred "$HOME_A" 'second run still defers the unready guard'

printf '%s\n' '--- Scenario (c): a locally-modified park is replaced and reported updated ---'
printf '%s\n' '# a local edit, not the vendored bytes' >> "$BIN_A/park"
STATUS_C=0
OUTPUT_C="$(HOME="$HOME_A" \
    CLAUDE_PROFILES_HOME="$HOME_A/.claude-profiles" CLAUDE_USER_DIR="$HOME_A/.claude" \
    OPENREPOSHAPE_BIN_DIR="$BIN_A" OPENREPOTOOLS_BIN_DIR="$BIN_A" \
    "$SCRIPT_UNDER_TEST" 2>&1)" || STATUS_C=$?

assert_equal '0' "$STATUS_C" 'updated-park run exit code'
assert_contains "$OUTPUT_C" 'park: updated at' 'the locally-modified park is reported updated'
assert_identical "$BIN_A/park" "$PARK_VENDOR" 'park is byte-identical to the vendored copy again after being updated'
# The rest were untouched, so this run still reports them unchanged -- a
# representative few from each of the four kinds of artifact, not all
# twenty-nine again.
assert_contains "$OUTPUT_C" 'openRepoShape: already installed at' 'updated-park run still reports openRepoShape unchanged'
assert_contains "$OUTPUT_C" 'resume: already installed at' 'updated-park run still reports resume unchanged'
assert_contains "$OUTPUT_C" 'status: already installed at' 'updated-park run still reports status unchanged'
assert_contains "$OUTPUT_C" 'repos.tsv: already installed at' 'updated-park run still reports repos.tsv unchanged'
assert_contains "$OUTPUT_C" 'lane-swap: already installed at' 'updated-park run still reports the lane-swap skill unchanged'
assert_contains "$OUTPUT_C" '/swap: already installed at' 'updated-park run still reports /swap unchanged'
assert_contains "$OUTPUT_C" 'SessionStart hook: deferred' 'updated-park run still defers the unready hook'

printf '%s\n' '--- Scenario (d): a corrupted vendor copy refuses to install anything ---'
CORRUPT_BASE="$TMPDIR_ROOT/corrupt-base-image"
mkdir -p "$CORRUPT_BASE"
cp -r "$BASE_IMAGE_DIR/." "$CORRUPT_BASE/"
python3 - "$CORRUPT_BASE/files/openrepotools/resume" <<'PYEOF'
import sys
path = sys.argv[1]
data = bytearray(open(path, "rb").read())
idx = len(data) // 2
data[idx] ^= 0x01
open(path, "wb").write(data)
PYEOF
BIN_D="$TMPDIR_ROOT/bin-d"
HOME_D="$TMPDIR_ROOT/home-d"
mkdir -p "$BIN_D" "$HOME_D"
STATUS_D=0
OUTPUT_D="$(HOME="$HOME_D" \
    CLAUDE_PROFILES_HOME="$HOME_D/.claude-profiles" CLAUDE_USER_DIR="$HOME_D/.claude" \
    OPENREPOSHAPE_BIN_DIR="$BIN_D" OPENREPOTOOLS_BIN_DIR="$BIN_D" \
    WORKBENCHES_BASE_IMAGE_DIR="$CORRUPT_BASE" \
    "$SCRIPT_UNDER_TEST" 2>&1)" || STATUS_D=$?

assert_equal '1' "$STATUS_D" 'corrupted vendor copy exit code'
assert_contains "$OUTPUT_D" 'REFUSED' "the check's REFUSED finding is in the output"
assert_contains "$OUTPUT_D" 'CHANGED' "the check's CHANGED finding is in the output"
assert_contains "$OUTPUT_D" 'files/openrepotools/resume' 'the finding names the corrupted file'
assert_empty_dir "$BIN_D" 'nothing was installed into the bin dir'
assert_absent "$HOME_D/.claude" 'nothing was written under $HOME/.claude either (neither shim ran)'
assert_absent "$HOME_D/.claude-profiles" 'nothing was written under $HOME/.claude-profiles either (neither shim ran)'

printf '%s\n' '--- Scenario (e): WORKBENCHES_SKIP_ESTATE_COMMANDS=1 skips the step entirely ---'
BIN_E="$TMPDIR_ROOT/bin-e"
HOME_E="$TMPDIR_ROOT/home-e"
mkdir -p "$BIN_E" "$HOME_E"
STATUS_E=0
OUTPUT_E="$(HOME="$HOME_E" \
    CLAUDE_PROFILES_HOME="$HOME_E/.claude-profiles" CLAUDE_USER_DIR="$HOME_E/.claude" \
    WORKBENCHES_SKIP_ESTATE_COMMANDS=1 \
    OPENREPOSHAPE_BIN_DIR="$BIN_E" OPENREPOTOOLS_BIN_DIR="$BIN_E" \
    "$SCRIPT_UNDER_TEST" 2>&1)" || STATUS_E=$?

assert_equal '0' "$STATUS_E" 'skip-var run exit code'
assert_contains "$OUTPUT_E" 'skipped' 'skip-var run says skipped'
assert_empty_dir "$BIN_E" 'skip-var run installs nothing'

printf '%s\n' '--- Scenario (g) [D1]: a symlinked target refuses, the link target is untouched ---'
BIN_G="$TMPDIR_ROOT/bin-g"
HOME_G="$TMPDIR_ROOT/home-g"
OTHER_REPO_G="$TMPDIR_ROOT/other-repo-g"
mkdir -p "$BIN_G" "$HOME_G" "$OTHER_REPO_G"
printf '#!/bin/bash\necho other repo park, not workBenches'"'"'s\n' > "$OTHER_REPO_G/park"
chmod +x "$OTHER_REPO_G/park"
LINK_TARGET_BEFORE="$(cat "$OTHER_REPO_G/park")"
ln -s "$OTHER_REPO_G/park" "$BIN_G/park"
STATUS_G=0
OUTPUT_G="$(HOME="$HOME_G" \
    CLAUDE_PROFILES_HOME="$HOME_G/.claude-profiles" CLAUDE_USER_DIR="$HOME_G/.claude" \
    OPENREPOSHAPE_BIN_DIR="$BIN_G" OPENREPOTOOLS_BIN_DIR="$BIN_G" \
    "$SCRIPT_UNDER_TEST" 2>&1)" || STATUS_G=$?

assert_equal '1' "$STATUS_G" 'symlinked park target exit code'
assert_contains "$OUTPUT_G" "$BIN_G/park" 'the refusal names the symlinked path'
assert_contains "$OUTPUT_G" 'symlink' 'the refusal says it is a symlink'
assert_equal "$LINK_TARGET_BEFORE" "$(cat "$OTHER_REPO_G/park")" 'the symlink target file is byte-for-byte unchanged'
assert_equal '1' "$(find "$BIN_G" -mindepth 1 | wc -l | tr -d ' ')" 'no other target was placed into the bin dir (only the pre-existing symlink remains)'

printf '%s\n' '--- Scenario (h) [D2]: a directory target refuses, nothing is placed ---'
BIN_H="$TMPDIR_ROOT/bin-h"
HOME_H="$TMPDIR_ROOT/home-h"
mkdir -p "$BIN_H/park" "$HOME_H"
STATUS_H=0
OUTPUT_H="$(HOME="$HOME_H" \
    CLAUDE_PROFILES_HOME="$HOME_H/.claude-profiles" CLAUDE_USER_DIR="$HOME_H/.claude" \
    OPENREPOSHAPE_BIN_DIR="$BIN_H" OPENREPOTOOLS_BIN_DIR="$BIN_H" \
    "$SCRIPT_UNDER_TEST" 2>&1)" || STATUS_H=$?

assert_equal '1' "$STATUS_H" 'directory-target park exit code'
assert_contains "$OUTPUT_H" "$BIN_H/park" 'the refusal names the directory path'
assert_contains "$OUTPUT_H" 'not a regular file' 'the refusal says it is not a regular file'
assert_equal '0' "$(find "$BIN_H/park" -mindepth 1 | wc -l | tr -d ' ')" 'nothing was copied into the directory standing in for park'

printf '%s\n' '--- Scenario (i) [D4 regression guard]: a read-only pre-seeded park refuses before ANY placement ---'
BIN_I="$TMPDIR_ROOT/bin-i"
HOME_I="$TMPDIR_ROOT/home-i"
mkdir -p "$BIN_I" "$HOME_I"
cp "$PARK_VENDOR" "$BIN_I/park"
chmod 0444 "$BIN_I/park"
STATUS_I=0
OUTPUT_I="$(HOME="$HOME_I" \
    CLAUDE_PROFILES_HOME="$HOME_I/.claude-profiles" CLAUDE_USER_DIR="$HOME_I/.claude" \
    OPENREPOSHAPE_BIN_DIR="$BIN_I" OPENREPOTOOLS_BIN_DIR="$BIN_I" \
    "$SCRIPT_UNDER_TEST" 2>&1)" || STATUS_I=$?

assert_equal '1' "$STATUS_I" 'read-only park exit code'
assert_contains "$OUTPUT_I" 'not writable' 'the refusal says park is not writable'
assert_equal '0' "$([ -e "$BIN_I/openRepoShape" ] && echo 1 || echo 0)" 'openRepoShape was NOT placed (D4 regression guard)'
assert_equal '0' "$([ -e "$BIN_I/openRepoTools" ] && echo 1 || echo 0)" 'openRepoTools was NOT placed (D4 regression guard)'
assert_equal '0' "$([ -e "$BIN_I/resume" ] && echo 1 || echo 0)" 'resume was NOT placed (D4 regression guard)'
assert_equal '0' "$([ -e "$BIN_I/repos.tsv" ] && echo 1 || echo 0)" 'repos.tsv (thirteenth of the fifteen) was NOT placed (D4 regression guard)'
assert_equal '0' "$([ -e "$BIN_I/claude-current" ] && echo 1 || echo 0)" 'claude-current (fourteenth of the fifteen) was NOT placed (D4 regression guard)'
assert_equal '0' "$([ -e "$BIN_I/claude-restart-check" ] && echo 1 || echo 0)" 'claude-restart-check (last of the fifteen) was NOT placed (D4 regression guard)'
assert_absent "$HOME_I/.claude" 'nothing was written under $HOME/.claude either (D4 regression guard)'
chmod 0755 "$BIN_I/park"

printf '%s\n' '--- Scenario (j): a base-image copy with upstream-pin.yaml deleted refuses with exit 2 ---'
NOPIN_BASE="$TMPDIR_ROOT/nopin-base-image"
mkdir -p "$NOPIN_BASE"
cp -r "$BASE_IMAGE_DIR/." "$NOPIN_BASE/"
rm -f "$NOPIN_BASE/upstream-pin.yaml"
BIN_J="$TMPDIR_ROOT/bin-j"
HOME_J="$TMPDIR_ROOT/home-j"
mkdir -p "$BIN_J" "$HOME_J"
STATUS_J=0
OUTPUT_J="$(HOME="$HOME_J" \
    CLAUDE_PROFILES_HOME="$HOME_J/.claude-profiles" CLAUDE_USER_DIR="$HOME_J/.claude" \
    OPENREPOSHAPE_BIN_DIR="$BIN_J" OPENREPOTOOLS_BIN_DIR="$BIN_J" \
    WORKBENCHES_BASE_IMAGE_DIR="$NOPIN_BASE" \
    "$SCRIPT_UNDER_TEST" 2>&1)" || STATUS_J=$?

assert_equal '2' "$STATUS_J" 'missing pin file exit code'
assert_contains "$OUTPUT_J" 'missing' 'the refusal says the pin is missing'
assert_empty_dir "$BIN_J" 'missing-pin run installs nothing'

printf '%s\n' '--- Scenario (k) [D3, part one]: resume'"'"'s row AND vendored file both removed the documented way -- this script'"'"'s OWN pre-flight refuses first ---'
# Hand-edit the copy directly (drop resume's three-line row, delete its
# file) rather than running `update-upstream.py apply --remove`, which
# needs `gh api` to prove the target commit is reachable from
# opensoft/openRepoTools' default branch -- network and auth this offline
# suite does not assume (and does not have in every CI job). The end state
# is the same one `apply --remove` documents producing: a row-and-file pair
# gone together, `check` none the wiser.
#
# UNCHANGED FROM BEFORE opensoft/openRepoTools#26, deliberately: this script's
# own `require_pin_row`, now checking all TWENTY-ONE openrepotools paths
# instead of four, still catches "resume" missing a row before either shim
# runs, for the same reason it always did -- a file the shims would install
# with no row in the pin is refused here, explicitly, rather than ever
# reaching a shim that could fall back to fetching it. The all-or-nothing
# rule does not change this half of D3 at all: it only raises the stakes of
# the OTHER half, proved directly in part two below, because now the same
# missing file would cost the whole twenty-nine-artifact install, not one
# file among five.
NOROW_BASE="$TMPDIR_ROOT/norow-base-image"
mkdir -p "$NOROW_BASE"
cp -r "$BASE_IMAGE_DIR/." "$NOROW_BASE/"
python3 - "$NOROW_BASE/upstream-pin.yaml" <<'PYEOF'
import sys
path = sys.argv[1]
lines = open(path).readlines()
out = []
i = 0
dropped = 0
while i < len(lines):
    if lines[i].strip() == "- path: resume":
        i += 3  # this line, its sha256: line, its mode: line
        dropped += 1
        continue
    out.append(lines[i])
    i += 1
if dropped != 1:
    raise SystemExit(f"expected to drop exactly one 'resume' row, dropped {dropped}")
open(path, "w").writelines(out)
PYEOF
rm -f "$NOROW_BASE/files/openrepotools/resume"
NOROW_CHECK_STATUS=0
python3 "$NOROW_BASE/update-upstream.py" check >"$TMPDIR_ROOT/norow-check.log" 2>&1 || NOROW_CHECK_STATUS=$?
assert_equal '0' "$NOROW_CHECK_STATUS" "scenario (k) setup: 'check' passes on the row-and-file-removed copy (this is the D3 precondition)"

BIN_K="$TMPDIR_ROOT/bin-k"
HOME_K="$TMPDIR_ROOT/home-k"
mkdir -p "$BIN_K" "$HOME_K"
STATUS_K=0
OUTPUT_K="$(HOME="$HOME_K" \
    CLAUDE_PROFILES_HOME="$HOME_K/.claude-profiles" CLAUDE_USER_DIR="$HOME_K/.claude" \
    OPENREPOSHAPE_BIN_DIR="$BIN_K" OPENREPOTOOLS_BIN_DIR="$BIN_K" \
    WORKBENCHES_BASE_IMAGE_DIR="$NOROW_BASE" \
    "$SCRIPT_UNDER_TEST" 2>&1)" || STATUS_K=$?

assert_equal '2' "$STATUS_K" 'row-and-file-removed resume exit code'
assert_contains "$OUTPUT_K" 'resume' 'the pre-flight refusal names resume'
assert_empty_dir "$BIN_K" 'nothing was installed for the row-and-file-removed copy'
assert_absent "$HOME_K/.claude" 'nothing under $HOME/.claude either, for the row-and-file-removed copy'
assert_not_contains "$OUTPUT_K" 'fetch' 'the output contains no attempted-fetch line'
assert_not_contains "$OUTPUT_K" 'github' 'the output contains no github reference'

printf '%s\n' '--- Scenario (k) [D3, part two]: called directly with a file missing beside it, the shim'"'"'s OWN all-or-nothing fetch refuses and names the sentinel ---'
# Part one proves this script's front door never lets a fetch happen. This
# half proves the BACKSTOP behind that door -- the four *_REPO/*_REF sentinel
# exports -- actually does what its own comment in the script claims, which
# no version of this suite has exercised directly before: it was previously
# provable only by the ABSENCE of "fetch" or "github" in output that a
# pre-flight refusal produced before the shim ever ran. Here the shim runs
# on purpose, invoked exactly as scripts/setup-estate-commands.sh invokes
# it (as a FILE, with the same four sentinel exports; the point is that
# EVEN THEN, missing one of its own siblings, it must refuse loudly rather
# than reach out for real -- so the read-only-mount installs this base
# image's Dockerfile does with `docker run --volume ...:ro` are provably
# safe, network or none.
SHIM_ONLY_DIR="$TMPDIR_ROOT/shim-only-k2"
mkdir -p "$SHIM_ONLY_DIR"
cp -r "$BASE_IMAGE_DIR/files/openrepotools/." "$SHIM_ONLY_DIR/"
rm -f "$SHIM_ONLY_DIR/resume"
BIN_K2="$TMPDIR_ROOT/bin-k2"
HOME_K2="$TMPDIR_ROOT/home-k2"
mkdir -p "$BIN_K2" "$HOME_K2"
# Read the sentinel value out of the script under test rather than
# hand-typing it a second time here: if it ever changes there, this
# assertion must not go on trusting a stale copy of it.
ESTATE_SENTINEL_VALUE="$(sed -n 's/^ESTATE_SENTINEL="\(.*\)"$/\1/p' "$SCRIPT_UNDER_TEST")"
assert_matches "$ESTATE_SENTINEL_VALUE" '.' "scenario (k) part two setup: the sentinel value was read from $SCRIPT_UNDER_TEST"
STATUS_K2=0
OUTPUT_K2="$(HOME="$HOME_K2" \
    CLAUDE_PROFILES_HOME="$HOME_K2/.claude-profiles" CLAUDE_USER_DIR="$HOME_K2/.claude" \
    OPENREPOTOOLS_BIN_DIR="$BIN_K2" \
    OPENREPOTOOLS_REPO="$ESTATE_SENTINEL_VALUE" OPENREPOTOOLS_REF="$ESTATE_SENTINEL_VALUE" \
    "$SHIM_ONLY_DIR/openRepoTools" --install 2>&1)" || STATUS_K2=$?

assert_equal '2' "$STATUS_K2" "the shim's own fetch refusal exits 2 (die's default)"
assert_contains "$OUTPUT_K2" 'REFUSED' "the shim's own refusal says REFUSED"
assert_contains "$OUTPUT_K2" 'could not fetch resume' "the shim's own refusal names resume as the file it could not fetch"
assert_contains "$OUTPUT_K2" "$ESTATE_SENTINEL_VALUE" "the shim's own refusal names the sentinel it tried to fetch from"
assert_empty_dir "$BIN_K2" "nothing was installed by the shim's own refusal either"
assert_absent "$HOME_K2/.claude" "nothing under \$HOME/.claude either, from the shim's own refusal"

printf '%s\n' '--- Scenario (l): every one of the FIFTEEN placed openRepoTools bin files is mode 0755, and so is openRepoShape ---'
assert_mode "$BIN_A/openRepoShape" '755' 'placed openRepoShape is mode 0755'
for name in "${TOOLS_FILES[@]}"; do
    assert_mode "$BIN_A/$name" '755' "placed $name is mode 0755"
done

printf '%s\n' '--- Scenario (m): the operator'"'"'s own *_REF/*_REPO are overridden by the sentinel, not used ---'
# Dynamically: an operator's environment must not change the happy-path
# outcome (this would also be true without the fix, since neither shim
# fetches when every file is already present -- but it is still a real
# regression guard: it proves the override does not itself break anything).
BIN_M="$TMPDIR_ROOT/bin-m"
HOME_M="$TMPDIR_ROOT/home-m"
mkdir -p "$BIN_M" "$HOME_M"
STATUS_M=0
OUTPUT_M="$(HOME="$HOME_M" \
    CLAUDE_PROFILES_HOME="$HOME_M/.claude-profiles" CLAUDE_USER_DIR="$HOME_M/.claude" \
    OPENREPOSHAPE_REF='operator-branch' OPENREPOTOOLS_REF='operator-branch' \
    OPENREPOSHAPE_REPO='operator/fork' OPENREPOTOOLS_REPO='operator/fork' \
    OPENREPOSHAPE_BIN_DIR="$BIN_M" OPENREPOTOOLS_BIN_DIR="$BIN_M" \
    "$SCRIPT_UNDER_TEST" 2>&1)" || STATUS_M=$?
assert_equal '0' "$STATUS_M" 'an operator-set REF/REPO does not change the happy-path exit code'
assert_not_contains "$OUTPUT_M" 'operator-branch' "the operator's REF value never reaches the output"
assert_not_contains "$OUTPUT_M" 'operator/fork' "the operator's REPO value never reaches the output"
assert_identical "$BIN_M/resume" "$RESUME_VENDOR" 'resume is still placed correctly from the vendored copy, not fetched'
assert_skill_pair "$HOME_M" 'lane-swap' 'the lane-swap skill is still placed correctly from the vendored copy, not fetched'
# Statically: neither shim echoes REPO/REF on the happy path at all (only on
# --version, or inside a fetch-failure message -- and this script's own
# pre-flight makes a fetch unreachable through its front door once every
# file is proven present and pinned, which is exactly what scenario (k)
# proves for the one file that COULD have gone missing). So the only way to
# show the override itself -- not just its harmlessness -- is to read the
# source for the four fixed exports, which is what the reviewer's own
# fallback clause invited ("assert instead by a method you can justify, or
# drop (m) and say so"): this is that method.
SCRIPT_SOURCE="$(cat "$SCRIPT_UNDER_TEST")"
for var in OPENREPOSHAPE_REPO OPENREPOSHAPE_REF OPENREPOTOOLS_REPO OPENREPOTOOLS_REF; do
    assert_contains "$SCRIPT_SOURCE" "export $var=\"\$ESTATE_SENTINEL\"" "the script source exports $var to the fixed sentinel before installing"
done

printf '%s\n' '--- Scenario (n) [Copilot round on #91, openRepoTools:277]: a stale INSTALLER-OWNED restart is retired -- removed, and named ---'
# `restart` left INSTALLABLES at this pin (Amendment 18 Addendum 2); the shim
# does not merely stop copying it, it retires a copy IT PLACED. The test for
# "this installer's own copy" is the header line every file this installer
# owns carries -- `Installed on PATH by \`openRepoTools --install\`` -- which
# is why the fixture below is not an empty file: `retire_commands` reads that
# exact string out of the target, not out of anything this script asserts.
BIN_N="$TMPDIR_ROOT/bin-n"
HOME_N="$TMPDIR_ROOT/home-n"
mkdir -p "$BIN_N" "$HOME_N"
cat > "$BIN_N/restart" <<'RESTARTEOF'
#!/usr/bin/env bash
# Installed on PATH by `openRepoTools --install`. lane-collision-protocol
echo "a stale restart this installer placed on an earlier run"
RESTARTEOF
chmod +x "$BIN_N/restart"
STATUS_N=0
OUTPUT_N="$(HOME="$HOME_N" \
    CLAUDE_PROFILES_HOME="$HOME_N/.claude-profiles" CLAUDE_USER_DIR="$HOME_N/.claude" \
    OPENREPOSHAPE_BIN_DIR="$BIN_N" OPENREPOTOOLS_BIN_DIR="$BIN_N" \
    "$SCRIPT_UNDER_TEST" 2>&1)" || STATUS_N=$?

assert_equal '0' "$STATUS_N" 'retiring an installer-owned restart still exits 0'
assert_absent "$BIN_N/restart" 'the installer-owned restart was removed'
assert_contains "$OUTPUT_N" 'restart: RETIRED, removed from' 'the output names the removal, not a silent delete'
assert_contains "$OUTPUT_N" "$BIN_N/restart" 'the removal line names the exact path removed'

printf '%s\n' '--- Scenario (o) [Copilot round on #91, openRepoTools:277]: a stale USER-OWNED restart is named and left exactly as it is ---'
# The other ownership branch: a file at the same path with no installer
# header -- a person's own script happening to be called `restart` -- is
# never this installer's to delete (`unplaceable_kind`'s own reasoning,
# ported to retirement rather than to placement).
BIN_O="$TMPDIR_ROOT/bin-o"
HOME_O="$TMPDIR_ROOT/home-o"
mkdir -p "$BIN_O" "$HOME_O"
cat > "$BIN_O/restart" <<'RESTARTEOF'
#!/usr/bin/env bash
echo "a person's own restart script, unrelated to openRepoTools"
RESTARTEOF
chmod +x "$BIN_O/restart"
USER_RESTART_BEFORE="$(sha256sum "$BIN_O/restart" | cut -d' ' -f1)"
STATUS_O=0
OUTPUT_O="$(HOME="$HOME_O" \
    CLAUDE_PROFILES_HOME="$HOME_O/.claude-profiles" CLAUDE_USER_DIR="$HOME_O/.claude" \
    OPENREPOSHAPE_BIN_DIR="$BIN_O" OPENREPOTOOLS_BIN_DIR="$BIN_O" \
    "$SCRIPT_UNDER_TEST" 2>&1)" || STATUS_O=$?

assert_equal '0' "$STATUS_O" 'a user-owned restart in the way still exits 0'
assert_file_executable "$BIN_O/restart" 'the user-owned restart is still there, still executable'
assert_equal "$USER_RESTART_BEFORE" "$(sha256sum "$BIN_O/restart" | cut -d' ' -f1)" 'the user-owned restart is byte-for-byte untouched'
assert_contains "$OUTPUT_O" "RETIRED by lane-collision-protocol Amendment 18 Addendum 2" 'the output names the retirement, even though nothing was removed'
assert_contains "$OUTPUT_O" 'left exactly as it is' 'the output says the file was left alone'
assert_contains "$OUTPUT_O" "rm -f -- \"$BIN_O/restart\"" 'the output prints the exact command that would remove it, for the person to run'

printf '%s\n' '--- Scenario (p) [Copilot round on #91, README.md:108]: this script'"'"'s TOOLS_FILES refuses to run against a shim whose own INSTALLABLES disagrees ---'
# The safeguard README.md:108 claims and Copilot found missing: TOOLS_FILES
# is still a hand-kept literal array (there is no `--list-installables` to
# generate it from), but from here it is CHECKED against the shim's own
# INSTALLABLES, not merely assumed to agree with it forever. Proven by
# editing a throwaway copy's shim to grow a file this script does not know
# about, and hand-patching that ONE vendored copy's pin row so `check` still
# passes -- exactly `update-upstream.py apply`'s own effect, without the
# network call recomputing a real upstream commit's digest would need.
MISMATCH_BASE="$TMPDIR_ROOT/mismatch-base-image"
mkdir -p "$MISMATCH_BASE"
cp -r "$BASE_IMAGE_DIR/." "$MISMATCH_BASE/"
python3 - "$MISMATCH_BASE" <<'PYEOF'
import hashlib
import re
import sys

base = sys.argv[1]
shim_path = f"{base}/files/openrepotools/openRepoTools"
pin_path = f"{base}/upstream-pin.yaml"

with open(shim_path, "r", encoding="utf-8") as f:
    text = f.read()
new_text, count = re.subn(
    r"^INSTALLABLES=\(([^)]*)\)$",
    r"INSTALLABLES=(\1 a-new-tool-this-script-does-not-list)",
    text,
    count=1,
    flags=re.MULTILINE,
)
if count != 1:
    raise SystemExit("could not find INSTALLABLES=(...) to widen")
with open(shim_path, "w", encoding="utf-8") as f:
    f.write(new_text)

new_digest = hashlib.sha256(new_text.encode("utf-8")).hexdigest()

with open(pin_path, "r", encoding="utf-8") as f:
    lines = f.readlines()
out = []
i = 0
patched = False
while i < len(lines):
    out.append(lines[i])
    if lines[i].strip() == "- path: openRepoTools":
        out.append(lines[i + 1].split(":")[0] + f': "{new_digest}"\n')
        out.append(lines[i + 2])
        i += 3
        patched = True
        continue
    i += 1
if not patched:
    raise SystemExit("could not find the openRepoTools pin row to patch")
with open(pin_path, "w", encoding="utf-8") as f:
    f.writelines(out)
PYEOF
BIN_P="$TMPDIR_ROOT/bin-p"
HOME_P="$TMPDIR_ROOT/home-p"
mkdir -p "$BIN_P" "$HOME_P"
MISMATCH_CHECK_STATUS=0
python3 "$MISMATCH_BASE/update-upstream.py" check >"$TMPDIR_ROOT/mismatch-check.log" 2>&1 || MISMATCH_CHECK_STATUS=$?
assert_equal '0' "$MISMATCH_CHECK_STATUS" "scenario (p) setup: 'check' passes on the widened-and-repinned copy (this is the precondition -- the two files agree with each other, and disagree with this script)"

STATUS_P=0
OUTPUT_P="$(HOME="$HOME_P" \
    CLAUDE_PROFILES_HOME="$HOME_P/.claude-profiles" CLAUDE_USER_DIR="$HOME_P/.claude" \
    OPENREPOSHAPE_BIN_DIR="$BIN_P" OPENREPOTOOLS_BIN_DIR="$BIN_P" \
    WORKBENCHES_BASE_IMAGE_DIR="$MISMATCH_BASE" \
    "$SCRIPT_UNDER_TEST" 2>&1)" || STATUS_P=$?

assert_equal '2' "$STATUS_P" 'a widened shim INSTALLABLES refuses (tooling/configuration, not a placement failure)'
assert_contains "$OUTPUT_P" 'TOOLS_FILES list' 'the refusal names this script'"'"'s own list'
assert_contains "$OUTPUT_P" 'a-new-tool-this-script-does-not-list' 'the refusal shows the file this script does not know about'
assert_empty_dir "$BIN_P" 'nothing was installed once the two lists disagree'
assert_absent "$HOME_P/.claude" 'nothing was written under $HOME/.claude either, for the widened shim'

# ===========================================================================
# THE CONTAINER-START STEP (opensoft/workBenches#90)
#
# `devBenches/base-image/files/estate/estate-commands-start` is the same two
# actions this script's subject takes -- the vendored `openRepoTools --install`
# and then `link-estates` -- taken at CONTAINER START instead of at `setup.sh`
# time, because `~/.local/bin` is not one of the paths the benches bind-mount
# and a bench recreate therefore resets it to whatever the image baked. It is
# tested here, beside the host step it mirrors, so the two cannot drift apart
# about what a complete estate install is.
#
# It cannot live in scripts/ and be reached from a container: Layer 1a's build
# context is devBenches/base-image/, so the repository's own scripts/ is not
# COPY-able into the image. What it shares with the script above is the
# vendored tree and the no-fetch sentinel, not code -- and, like that script,
# it adds no install logic of its own.
#
# Scenarios (q)-(v) pin the properties an entrypoint step must have and a
# `setup.sh` step need not: it installs when the bin dir is empty, writes
# NOTHING when it is already current, and NEVER exits nonzero -- not when the
# workspace file a fresh workstation has not written yet is missing, not when
# the switch turns it off, and not when the image predates the vendored tree
# it installs from. A nonzero exit there is a container that will not start.
START_STEP="$REPO_ROOT/devBenches/base-image/files/estate/estate-commands-start"
VENDOR_DIR="$BASE_IMAGE_DIR/files/openrepotools"

# Every run is sandboxed the way the scenarios above are, plus the two the
# linking half reads: AGENT_PROTOCOL_ROOT (where workspace.yaml is looked for)
# and PROJECTS_ROOT (where the estate folders are), so `link-estates` can never
# reach the real ~/.agents or ~/projects of whoever runs this suite.
run_start_step() {   # <home> <bin dir> [extra env assignments...]
    local home="$1" bin="$2"
    shift 2
    env HOME="$home" \
        CLAUDE_PROFILES_HOME="$home/.claude-profiles" CLAUDE_USER_DIR="$home/.claude" \
        AGENT_PROTOCOL_ROOT="$home/.agents" PROJECTS_ROOT="$home/projects" \
        OPENREPOTOOLS_BIN_DIR="$bin" \
        WORKBENCHES_ESTATE_VENDOR_DIR="$VENDOR_DIR" \
        "$@" bash "$START_STEP" 2>&1
}

# A manifest of everything the step could have written, by path, size and
# modification time -- the only way to prove "already current" cost no write
# rather than merely leaving the same bytes behind. `stat` is called on both
# the GNU and the BSD spelling, the same way assert_mode above does it, rather
# than with `find -printf`, which is GNU-only: this suite is host-run (see
# devcontainer.test/README.md) and a developer's host is not always Linux.
#
# THE INSTALL RECEIPT IS LEFT OUT, and is checked on its own terms in scenario
# (r) instead. `openRepoTools --install` (openRepoTools#57, #103) writes
# `$XDG_DATA_HOME/openRepoTools/installed.tsv` -- under `~/.local/share` here --
# one row per file it placed, `<name> <destination> <sha256> <UTC>`, and
# REPLACES the row of every destination it placed on every run, "already
# installed" ones included, so the UTC column and the file's mtime move on a
# run that placed nothing new. That is a RECORD of the placement, "not an
# artifact of the count" in the shim's own words, and not one of the things a
# no-op start must leave untouched.
state_manifest() {   # <dir>...
    find "$@" -type f ! -path '*/.local/share/openRepoTools/installed.tsv' 2>/dev/null | LC_ALL=C sort | while IFS= read -r manifest_file; do
        printf '%s %s\n' "$manifest_file" \
            "$(stat -c '%s %Y' "$manifest_file" 2>/dev/null || stat -f '%z %m' "$manifest_file" 2>/dev/null || true)"
    done
}

printf '%s\n' '--- Scenario (q): the container-start step installs into an empty bin dir, as a recreate leaves it ---'
BIN_Q="$TMPDIR_ROOT/bin-q"
HOME_Q="$TMPDIR_ROOT/home-q"
mkdir -p "$BIN_Q" "$HOME_Q"
STATUS_Q=0
OUTPUT_Q="$(run_start_step "$HOME_Q" "$BIN_Q")" || STATUS_Q=$?

assert_equal '0' "$STATUS_Q" 'the start step exits 0 on a fresh container'
for name in "${TOOLS_FILES[@]}"; do
    assert_file_executable "$BIN_Q/$name" "the start step places $name, executable"
    assert_identical "$BIN_Q/$name" "$(tools_vendor_path "$name")" "the start step's $name is byte-identical to the vendored copy"
done
assert_contains "$OUTPUT_Q" 'openRepoTools: 17 of 17 placed in' 'the start step relays the installer'"'"'s own count line, not a summary of its own'
for name in "${SKILL_NAMES[@]}"; do
    assert_skill_pair "$HOME_Q" "$name" "the start step places the $name skill"
done
for name in "${COMMAND_NAMES[@]}"; do
    assert_command_pair "$HOME_Q" "$name" "the start step places the /$name command file"
done
assert_hooks_deferred "$HOME_Q" 'the start step defers SessionStart without a workspace'
assert_hooks_deferred "$HOME_Q" 'the start step defers the prompt guard without a workspace'
# The six per-user artifacts and the two hook entries are the half the image's
# own COPY into /usr/local/bin can never restore -- a build has no user's $HOME
# -- which is why the step runs `--install` rather than trusting those copies.

printf '%s\n' '--- Scenario (r): a second start is a no-op — every artifact reported unchanged, and not one byte written ---'
# The receipt rows without their UTC stamp: name, destination and digest.
RECEIPT_Q="$HOME_Q/.local/share/openRepoTools/installed.tsv"
receipt_rows() {   # <receipt> -- columns 1-3, sorted
    cut -f1-3 "$1" 2>/dev/null | LC_ALL=C sort
}
BEFORE_R="$(state_manifest "$BIN_Q" "$HOME_Q")"
RECEIPT_BEFORE_R="$(receipt_rows "$RECEIPT_Q")"
STATUS_R=0
OUTPUT_R="$(run_start_step "$HOME_Q" "$BIN_Q")" || STATUS_R=$?
AFTER_R="$(state_manifest "$BIN_Q" "$HOME_Q")"
RECEIPT_AFTER_R="$(receipt_rows "$RECEIPT_Q")"

assert_equal '0' "$STATUS_R" 'a second start exits 0'
assert_equal "$BEFORE_R" "$AFTER_R" 'a second start writes nothing at all (same files, sizes and mtimes), the install receipt aside'
assert_contains "$RECEIPT_BEFORE_R" 'claude-restart-check' 'the install receipt names the last of the fifteen bin files'
assert_equal "$RECEIPT_BEFORE_R" "$RECEIPT_AFTER_R" 'a second start leaves every receipt row'"'"'s name, destination and digest as it was (only the UTC stamp may move)'
assert_not_contains "$OUTPUT_R" ': installed at' 'a second start installs nothing'
for name in "${TOOLS_FILES[@]}"; do
    assert_contains "$OUTPUT_R" "$name: already installed at" "a second start reports $name unchanged"
done
assert_contains "$OUTPUT_R" 'SessionStart hook: deferred' 'a second start still defers SessionStart without a workspace'
assert_contains "$OUTPUT_R" 'UserPromptSubmit guard: deferred' 'a second start still defers the prompt guard without a workspace'

# Exercise the INSTALLED payload after repeat startup, not only the source
# guard: a correct launcher and source tree did not prevent an old image from
# restoring a guard that ignored the profile-only marker.
mkdir -p "$HOME_Q/projects"
PROFILE_GUARD_INPUT="$(printf '{"session_id":"profile-only","cwd":"%s/projects","prompt":"status","hook_event_name":"UserPromptSubmit"}' "$HOME_Q")"
PROFILE_GUARD_RC=0
PROFILE_GUARD_OUTPUT="$(env HOME="$HOME_Q" AGENT_PROTOCOL_ROOT="$HOME_Q/missing-agents" \
    CLAUDE_NO_LANE=1 bash "$BIN_Q/lanes-edit.sh" guard <<< "$PROFILE_GUARD_INPUT" 2>&1)" || PROFILE_GUARD_RC=$?
assert_equal '0' "$PROFILE_GUARD_RC" 'after repeat startup, installed guard permits profile-only sessions without lane infrastructure'
assert_equal '' "$PROFILE_GUARD_OUTPUT" 'profile-only installed hook is silent'
LANE_GUARD_RC=0
LANE_GUARD_OUTPUT="$(env HOME="$HOME_Q" AGENT_PROTOCOL_ROOT="$HOME_Q/missing-agents" \
    CLAUDE_NO_LANE=0 bash "$BIN_Q/lanes-edit.sh" guard <<< "$PROFILE_GUARD_INPUT" 2>&1)" || LANE_GUARD_RC=$?
assert_equal '2' "$LANE_GUARD_RC" 'after repeat startup, installed guard still refuses an unverifiable lane session'
assert_contains "$LANE_GUARD_OUTPUT" 'THE NAME GUARD REFUSES' 'lane enforcement survives the profile-only exemption'

printf '%s\n' '--- Scenario (s): no ~/.agents/workspace.yaml (a fresh workstation before `openRepoTools wip init`) does not fail container start ---'
assert_absent "$HOME_Q/.agents/workspace.yaml" 'scenario (s) precondition: the sandbox has no workspace.yaml'
assert_contains "$OUTPUT_Q" 'openRepoTools wip init' 'the linking half relays link-estates'"'"' own refusal, which names the one command that ends it'
assert_contains "$OUTPUT_Q" 'Container start continues' 'the step says out loud that the refusal did not stop the container'
# Asserted against scenario (q)'s own output, not a fresh run: (q) already ran
# with no workspace.yaml, and its exit code -- asserted 0 above -- IS this
# scenario's claim. link-estates exits 1 there; the step swallows it.

printf '%s\n' '--- Scenario (t): with a workspace.yaml, the links land and the SessionStart hook path resolves again ---'
BIN_T="$TMPDIR_ROOT/bin-t"
HOME_T="$TMPDIR_ROOT/home-t"
WIP_T="$HOME_T/brett-wip"
mkdir -p "$BIN_T" "$HOME_T/.agents" "$HOME_T/projects/xFactory" "$WIP_T/handoffs/xFactory" "$WIP_T/lanes"
git init -q "$WIP_T"
git -C "$WIP_T" remote add origin git@github.com:acme/acme-wip.git
: > "$WIP_T/lanes/LANES.md"
printf 'repository: acme/acme-wip\npath: %s\n' "$WIP_T" > "$HOME_T/.agents/workspace.yaml"
STATUS_T=0
OUTPUT_T="$(run_start_step "$HOME_T" "$BIN_T")" || STATUS_T=$?

assert_equal '0' "$STATUS_T" 'the start step exits 0 with a workspace repository present'
# THE POINT OF THE WHOLE STEP, in one assertion: `~/projects/xFactory/
# lanes-edit.sh` is the command string Amendment 8(e)'s SessionStart hook
# names, and a recreate left it a symlink to a file that no longer existed.
# `-e` follows the link, so this fails on a dangling one.
if [ -L "$HOME_T/projects/xFactory/lanes-edit.sh" ] && [ -e "$HOME_T/projects/xFactory/lanes-edit.sh" ]; then
    pass 'the SessionStart hook path ~/projects/xFactory/lanes-edit.sh is a link that resolves'
else
    fail 'the SessionStart hook path ~/projects/xFactory/lanes-edit.sh is missing or dangling after the start step'
fi
assert_identical "$HOME_T/projects/xFactory/lanes-edit.sh" "$BIN_T/lanes-edit.sh" 'that link resolves to the lanes-edit.sh this start step installed'
assert_equal "$(readlink "$HOME_T/projects/xFactory/LANES.md")" "$WIP_T/lanes/LANES.md" 'the register link points into the workspace repository'
assert_equal "$(readlink "$HOME_T/projects/xFactory/handoffs")" "$WIP_T/handoffs/xFactory" 'the handoffs link points into the workspace repository'
assert_hook_present "$HOME_T" 'the first start reconciles SessionStart after successful linking'
assert_guard_hook_present "$HOME_T" 'the first start reconciles the prompt guard after successful linking'

printf '%s\n' '--- Scenario (u): WORKBENCHES_SKIP_ESTATE_COMMANDS=1 turns the step off from a bench'"'"'s own environment ---'
BIN_U="$TMPDIR_ROOT/bin-u"
HOME_U="$TMPDIR_ROOT/home-u"
mkdir -p "$BIN_U" "$HOME_U"
STATUS_U=0
OUTPUT_U="$(run_start_step "$HOME_U" "$BIN_U" WORKBENCHES_SKIP_ESTATE_COMMANDS=1)" || STATUS_U=$?

assert_equal '0' "$STATUS_U" 'the skip switch exits 0'
assert_contains "$OUTPUT_U" 'WORKBENCHES_SKIP_ESTATE_COMMANDS=1' 'the skip switch says which switch turned it off'
assert_empty_dir "$BIN_U" 'the skip switch installs nothing'
assert_absent "$HOME_U/.claude" 'the skip switch writes nothing under $HOME either'

printf '%s\n' '--- Scenario (v): an image built before #90 has no vendored tree, and still must not fail container start ---'
BIN_V="$TMPDIR_ROOT/bin-v"
HOME_V="$TMPDIR_ROOT/home-v"
mkdir -p "$BIN_V" "$HOME_V"
STATUS_V=0
OUTPUT_V="$(env HOME="$HOME_V" \
    CLAUDE_PROFILES_HOME="$HOME_V/.claude-profiles" CLAUDE_USER_DIR="$HOME_V/.claude" \
    AGENT_PROTOCOL_ROOT="$HOME_V/.agents" PROJECTS_ROOT="$HOME_V/projects" \
    OPENREPOTOOLS_BIN_DIR="$BIN_V" \
    WORKBENCHES_ESTATE_VENDOR_DIR="$TMPDIR_ROOT/no-such-vendor-dir" \
    bash "$START_STEP" 2>&1)" || STATUS_V=$?

assert_equal '0' "$STATUS_V" 'a missing vendored tree exits 0 rather than refusing to start the container'
assert_contains "$OUTPUT_V" 'no vendored openRepoTools at' 'a missing vendored tree says what is missing'
assert_contains "$OUTPUT_V" 'build.sh' 'a missing vendored tree names the rebuild that ends it'
assert_empty_dir "$BIN_V" 'a missing vendored tree installs nothing'

printf '%s\n' '--- Scenario (w): an incomplete vendored tree installs NOTHING, rather than sending --install to the network at container start ---'
# Copilot's review of opensoft/workBenches#99: the no-fetch sentinel only makes
# a fetch FAIL -- a DNS and TLS round trip in front of every container start --
# so the guarantee has to be a preflight, not a sentinel. The set it checks is
# read from the shim's own INSTALLABLES/SKILLS/COMMANDS, so this scenario also
# covers the case that motivates it: an image whose Layer 1a was not rebuilt
# after the shim grew an artifact.
BIN_W="$TMPDIR_ROOT/bin-w"
HOME_W="$TMPDIR_ROOT/home-w"
VENDOR_W="$TMPDIR_ROOT/vendor-w"
mkdir -p "$BIN_W" "$HOME_W"
cp -R "$VENDOR_DIR" "$VENDOR_W"
rm -f "$VENDOR_W/lane-handoff" "$VENDOR_W/skills/restart/SKILL.md" "$VENDOR_W/commands/swap.md"
STATUS_W=0
OUTPUT_W="$(env HOME="$HOME_W" \
    CLAUDE_PROFILES_HOME="$HOME_W/.claude-profiles" CLAUDE_USER_DIR="$HOME_W/.claude" \
    AGENT_PROTOCOL_ROOT="$HOME_W/.agents" PROJECTS_ROOT="$HOME_W/projects" \
    OPENREPOTOOLS_BIN_DIR="$BIN_W" WORKBENCHES_ESTATE_VENDOR_DIR="$VENDOR_W" \
    bash "$START_STEP" 2>&1)" || STATUS_W=$?

assert_equal '0' "$STATUS_W" 'an incomplete vendored tree still exits 0 — a container start is not a place to refuse'
assert_empty_dir "$BIN_W" 'an incomplete vendored tree installs NOTHING, so no fetch is ever reachable'
assert_absent "$HOME_W/.claude" 'an incomplete vendored tree writes nothing under $HOME either'
assert_contains "$OUTPUT_W" 'lane-handoff' 'the refusal names the missing bin file'
assert_contains "$OUTPUT_W" 'skills/restart/SKILL.md' 'the refusal names the missing skill, derived from the shim'"'"'s own SKILLS list'
assert_contains "$OUTPUT_W" 'commands/swap.md' 'the refusal names the missing command file, derived from the shim'"'"'s own COMMANDS list'
assert_contains "$OUTPUT_W" 'build.sh' 'the refusal names the rebuild that ends it'

printf '%s\n' '--- Scenario (x): the ENTRYPOINT runs the step and then execs the container'"'"'s own command, argument for argument ---'
# Also Copilot's review of #99: "it never executes this ENTRYPOINT with a real
# command... a bad image build, lost inherited CMD, or broken `exec` argument
# forwarding could therefore pass". A `docker build` is still out of reach in
# here (this suite runs INSIDE a bench), but everything below the image layer
# is not: WORKBENCHES_ENTRYPOINT_STEP points the entrypoint at a recorder, and
# the argv it forwards is compared byte for byte -- including an argument with
# a space in it, which is what an `exec $@` without quotes would split.
ENTRYPOINT_FILE="$REPO_ROOT/devBenches/base-image/files/estate/workbench-entrypoint"
X_DIR="$TMPDIR_ROOT/entrypoint-x"
mkdir -p "$X_DIR/bin"
cat > "$X_DIR/step" <<EOF
#!/bin/sh
printf 'step ran\n' >> "$X_DIR/step.log"
exit 0
EOF
cat > "$X_DIR/bin/recorder" <<EOF
#!/bin/sh
: > "$X_DIR/argv.log"
for a in "\$@"; do printf '%s\n' "\$a" >> "$X_DIR/argv.log"; done
exit 0
EOF
# The image's own CMD is `sleep infinity`; a stub of that name earlier on PATH
# is how the no-argument fallback is asserted without hanging this suite.
cat > "$X_DIR/bin/sleep" <<EOF
#!/bin/sh
printf '%s\n' "\$@" > "$X_DIR/sleep.log"
exit 0
EOF
chmod 0755 "$X_DIR/step" "$X_DIR/bin/recorder" "$X_DIR/bin/sleep"

: > "$X_DIR/step.log"
STATUS_X=0
env PATH="$X_DIR/bin:$PATH" WORKBENCHES_ENTRYPOINT_STEP="$X_DIR/step" \
    sh "$ENTRYPOINT_FILE" recorder --flag "two words" -- trailing >/dev/null 2>&1 || STATUS_X=$?
assert_equal '0' "$STATUS_X" 'the entrypoint exits with the status of the command it exec-ed'
assert_equal "$(cat "$X_DIR/step.log" 2>/dev/null)" 'step ran' 'the entrypoint ran the start-up step exactly once before exec'
assert_equal "$(cat "$X_DIR/argv.log" 2>/dev/null)" "$(printf '%s\n' --flag 'two words' -- trailing)" 'the entrypoint forwarded every argument unchanged, the one with a space included'

# A step that FAILS must not stop the container: the exec is unconditional.
printf '#!/bin/sh\nexit 3\n' > "$X_DIR/step"
chmod 0755 "$X_DIR/step"
rm -f "$X_DIR/argv.log"
STATUS_XF=0
env PATH="$X_DIR/bin:$PATH" WORKBENCHES_ENTRYPOINT_STEP="$X_DIR/step" \
    sh "$ENTRYPOINT_FILE" recorder still-runs >/dev/null 2>&1 || STATUS_XF=$?
assert_equal '0' "$STATUS_XF" 'a start-up step that fails does not fail the container'
assert_equal "$(cat "$X_DIR/argv.log" 2>/dev/null)" 'still-runs' 'the command is exec-ed even when the start-up step failed'

# A step that is not there at all (an image that predates this) likewise.
rm -f "$X_DIR/argv.log"
STATUS_XM=0
env PATH="$X_DIR/bin:$PATH" WORKBENCHES_ENTRYPOINT_STEP="$X_DIR/no-such-step" \
    sh "$ENTRYPOINT_FILE" recorder no-step >/dev/null 2>&1 || STATUS_XM=$?
assert_equal '0' "$STATUS_XM" 'a missing start-up step does not fail the container'
assert_equal "$(cat "$X_DIR/argv.log" 2>/dev/null)" 'no-step' 'the command is exec-ed even when the start-up step is not in the image'

# NO arguments at all falls back to the image's own default command, so an
# `--entrypoint` override that passes none still leaves PID 1 with something
# to be.
printf '#!/bin/sh\nexit 0\n' > "$X_DIR/step"
chmod 0755 "$X_DIR/step"
STATUS_XN=0
env PATH="$X_DIR/bin:$PATH" WORKBENCHES_ENTRYPOINT_STEP="$X_DIR/step" \
    sh "$ENTRYPOINT_FILE" >/dev/null 2>&1 || STATUS_XN=$?
assert_equal '0' "$STATUS_XN" 'the no-argument fallback exits cleanly'
assert_equal "$(cat "$X_DIR/sleep.log" 2>/dev/null)" 'infinity' 'with no arguments the entrypoint execs the image'"'"'s own default command, `sleep infinity`'

# END TO END, minus Docker: the REAL start step under the REAL entrypoint,
# against a sandboxed $HOME, then the recorder. This is the whole instruction
# chain except `docker build` and the kernel's exec of PID 1.
BIN_XE="$TMPDIR_ROOT/bin-xe"
HOME_XE="$TMPDIR_ROOT/home-xe"
mkdir -p "$BIN_XE" "$HOME_XE"
rm -f "$X_DIR/argv.log"
STATUS_XE=0
env PATH="$X_DIR/bin:$PATH" WORKBENCHES_ENTRYPOINT_STEP="$START_STEP" \
    HOME="$HOME_XE" CLAUDE_PROFILES_HOME="$HOME_XE/.claude-profiles" CLAUDE_USER_DIR="$HOME_XE/.claude" \
    AGENT_PROTOCOL_ROOT="$HOME_XE/.agents" PROJECTS_ROOT="$HOME_XE/projects" \
    OPENREPOTOOLS_BIN_DIR="$BIN_XE" WORKBENCHES_ESTATE_VENDOR_DIR="$VENDOR_DIR" \
    sh "$ENTRYPOINT_FILE" recorder end-to-end >/dev/null 2>&1 || STATUS_XE=$?
assert_equal '0' "$STATUS_XE" 'entrypoint + real start step + command exits 0'
assert_equal "$(cat "$X_DIR/argv.log" 2>/dev/null)" 'end-to-end' 'the command still runs after the real start step did its work'
for name in "${TOOLS_FILES[@]}"; do
    assert_identical "$BIN_XE/$name" "$(tools_vendor_path "$name")" "end to end through the entrypoint, $name is installed and byte-identical"
done

printf '%s\n' '--- Scenario (y): two benches sharing one host home do not install over each other ---'
# Copilot round 2 of opensoft/workBenches#99: `~/.claude` and `~/.claude-profiles`
# are bind-mounted from the SAME host home into every bench, so running the
# install at container start is what makes a race between two bench starts
# reachable -- two read-modify-writes of one settings.json. The step takes an
# flock in the shared home. It WAITS rather than standing down, because
# `~/.local/bin` is the one thing here that is not shared, and a timeout goes
# ahead anyway: a slower race beats a bench with no lane commands.
#
# SKIPPED, NOT FAILED, WHERE THERE IS NO `flock`. This suite is host-run (see
# devcontainer.test/README.md) and a developer's host is not always Linux;
# `flock(1)` is util-linux and macOS does not ship it. The step under test has
# a DEFINED fallback for exactly that — it says the start is not serialized and
# carries on — so a host without flock is a supported configuration, and
# failing the whole regression suite there would punish a valid run for the
# absence of an optional utility. CI (ubuntu-24.04) always has it, so the
# scenario is never quietly lost on the run that gates merges.
if ! command -v flock >/dev/null 2>&1; then
    printf 'SKIP: scenario (y) needs flock(1), which this host does not have; the step'"'"'s own no-flock fallback is what runs here. CI on ubuntu-24.04 exercises it.\n'
else
    BIN_Y="$TMPDIR_ROOT/bin-y"
    HOME_Y="$TMPDIR_ROOT/home-y"
    mkdir -p "$BIN_Y" "$HOME_Y/.claude"
    LOCK_Y="$HOME_Y/.claude/.workbenches-estate-start.lock"
    : > "$LOCK_Y"

    # A holder in another process stands in for the other bench. Confirmed held
    # before the step runs, in a bounded loop, so this is a fact rather than a
    # sleep and a hope.
    flock "$LOCK_Y" -c 'sleep 10' &
    LOCK_HOLDER=$!
    held=0
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        if flock -n "$LOCK_Y" -c true >/dev/null 2>&1; then
            sleep 0.3
        else
            held=1
            break
        fi
    done
    assert_equal '1' "$held" 'scenario (y) precondition: another process holds the estate lock'

    STATUS_Y=0
    OUTPUT_Y="$(env HOME="$HOME_Y" \
        CLAUDE_PROFILES_HOME="$HOME_Y/.claude-profiles" CLAUDE_USER_DIR="$HOME_Y/.claude" \
        AGENT_PROTOCOL_ROOT="$HOME_Y/.agents" PROJECTS_ROOT="$HOME_Y/projects" \
        OPENREPOTOOLS_BIN_DIR="$BIN_Y" WORKBENCHES_ESTATE_VENDOR_DIR="$VENDOR_DIR" \
        WORKBENCHES_ESTATE_LOCK_WAIT=1 \
        bash "$START_STEP" 2>&1)" || STATUS_Y=$?
    kill "$LOCK_HOLDER" 2>/dev/null || true
    wait "$LOCK_HOLDER" 2>/dev/null || true

    assert_equal '0' "$STATUS_Y" 'a contended lock still exits 0 — a bench start is never blocked on another bench'
    assert_contains "$OUTPUT_Y" 'still holds' 'the step says it went ahead without the lock rather than doing it silently'
    for name in "${TOOLS_FILES[@]}"; do
        assert_identical "$BIN_Y/$name" "$(tools_vendor_path "$name")" "a contended lock still installs $name — the bin dir is per-container and nobody else fills it"
    done

    # THE LOCK MUST NOT MUTE THE STEP. `exec 9>"$lock" 2>/dev/null` is ONE
    # redirection list applied to the shell: it opens the lock AND sends every
    # later line -- every notice, and everything `--install` and `link-estates`
    # write to stderr -- to /dev/null. That was the first cut here, measured
    # mute while this scenario was written. Scenario (q)'s own output is the
    # other half of this guard (its link-estates refusal is asserted in (s));
    # this asserts it on the contended path too, where the lock code does the
    # most work.
    assert_contains "$OUTPUT_Y" 'Container start continues' 'the lock did not swallow the rest of the step'"'"'s output'

    # And with the lock free there is no such line: a lock that always reports
    # a timeout is not a working lock.
    BIN_Y2="$TMPDIR_ROOT/bin-y2"
    HOME_Y2="$TMPDIR_ROOT/home-y2"
    mkdir -p "$BIN_Y2" "$HOME_Y2"
    STATUS_Y2=0
    OUTPUT_Y2="$(env HOME="$HOME_Y2" \
        CLAUDE_PROFILES_HOME="$HOME_Y2/.claude-profiles" CLAUDE_USER_DIR="$HOME_Y2/.claude" \
        AGENT_PROTOCOL_ROOT="$HOME_Y2/.agents" PROJECTS_ROOT="$HOME_Y2/projects" \
        OPENREPOTOOLS_BIN_DIR="$BIN_Y2" WORKBENCHES_ESTATE_VENDOR_DIR="$VENDOR_DIR" \
        WORKBENCHES_ESTATE_LOCK_WAIT=1 \
        bash "$START_STEP" 2>&1)" || STATUS_Y2=$?
    assert_equal '0' "$STATUS_Y2" 'an uncontended lock exits 0'
    assert_not_contains "$OUTPUT_Y2" 'still holds' 'an uncontended lock is taken, not timed out'
    if [ -f "$HOME_Y2/.claude/.workbenches-estate-start.lock" ]; then
        pass 'the lock file is created beside the settings.json it protects, in the shared home'
    else
        fail 'the step took no lock at all: no lock file under the shared ~/.claude'
    fi
fi

printf '%s\n' '--- Scenario (z): a bench that shares the workstation'"'"'s own home installs nothing into it ---'
# Copilot round 3 of opensoft/workBenches#99. The step runs from the image, so
# it runs in EVERY dev bench -- and devBenches/.devcontainer/docker-compose.yml
# mounts the WHOLE host home (`~:/home/${USER}`). There `$HOME/.local/bin` is
# the workstation's, not a container overlay, and installing would put the
# image's pin over whatever the host has: a silent downgrade at container start
# on any workstation whose openRepoTools is newer than the image's, which is
# #90 arriving from the other direction. A whole-home mount makes `$HOME`
# itself a mount point; the per-path mounts every other bench uses make its
# CHILDREN mount points and leave `$HOME` an ordinary directory. Field 5 of
# /proc/self/mountinfo is the mount point, and WORKBENCHES_MOUNTINFO is the
# seam that lets both shapes be exercised on one host.
#
# Every other scenario here runs against the REAL /proc/self/mountinfo with no
# seam set, so "the guard does not fire in an ordinary bench" is already
# asserted twenty-four times over; this scenario is the other half.
BIN_Z="$TMPDIR_ROOT/bin-z"
HOME_Z="$TMPDIR_ROOT/home-z"
mkdir -p "$BIN_Z" "$HOME_Z"
MOUNTINFO_WHOLE_HOME="$TMPDIR_ROOT/mountinfo-whole-home"
printf '26 25 0:24 / %s rw,relatime shared:4 - ext4 /dev/sdd rw\n' "$HOME_Z" > "$MOUNTINFO_WHOLE_HOME"

run_start_step_with_mountinfo() {   # <home> <bin dir> <mountinfo> [extra env...]
    local home="$1" bin="$2" mountinfo="$3"
    shift 3
    env HOME="$home" \
        CLAUDE_PROFILES_HOME="$home/.claude-profiles" CLAUDE_USER_DIR="$home/.claude" \
        AGENT_PROTOCOL_ROOT="$home/.agents" PROJECTS_ROOT="$home/projects" \
        OPENREPOTOOLS_BIN_DIR="$bin" WORKBENCHES_ESTATE_VENDOR_DIR="$VENDOR_DIR" \
        WORKBENCHES_MOUNTINFO="$mountinfo" \
        "$@" bash "$START_STEP" 2>&1
}

STATUS_Z=0
OUTPUT_Z="$(run_start_step_with_mountinfo "$HOME_Z" "$BIN_Z" "$MOUNTINFO_WHOLE_HOME")" || STATUS_Z=$?
assert_equal '0' "$STATUS_Z" 'a shared host home exits 0 rather than failing the container'
assert_empty_dir "$BIN_Z" 'a shared host home has nothing installed into it — the image pin never lands on the workstation'
assert_absent "$HOME_Z/.claude" 'a shared host home has nothing written under it either'
assert_contains "$OUTPUT_Z" 'is itself a bind mount' 'the stand-down says what it detected'
assert_contains "$OUTPUT_Z" 'WORKBENCHES_ESTATE_FORCE=1' 'the stand-down names the override for an operator who means it'

# The other shape, the one every real lane bench has: children mounted, $HOME
# its own. This must install, or the fix for #90 never runs anywhere.
BIN_Z2="$TMPDIR_ROOT/bin-z2"
HOME_Z2="$TMPDIR_ROOT/home-z2"
mkdir -p "$BIN_Z2" "$HOME_Z2"
# The rows name CHILDREN OF THE HOME THIS RUN IS GIVEN, and that is the whole
# discrimination under test: a prefix match rather than an equality on the
# mount point would fire here and strand every real bench with no lane
# commands. Mutation-tested as exactly that.
MOUNTINFO_CHILDREN="$TMPDIR_ROOT/mountinfo-children"
{
    printf '26 25 0:24 / %s rw,relatime shared:4 - ext4 /dev/sdd rw\n' "$HOME_Z2/.claude"
    printf '27 25 0:24 / %s rw,relatime shared:5 - ext4 /dev/sdd rw\n' "$HOME_Z2/.claude-profiles"
    printf '28 25 0:24 / %s rw,relatime shared:6 - ext4 /dev/sdd rw\n' "$HOME_Z2/.agents"
} > "$MOUNTINFO_CHILDREN"
STATUS_Z2=0
OUTPUT_Z2="$(run_start_step_with_mountinfo "$HOME_Z2" "$BIN_Z2" "$MOUNTINFO_CHILDREN")" || STATUS_Z2=$?
assert_equal '0' "$STATUS_Z2" 'a container home with per-path mounts exits 0'
assert_not_contains "$OUTPUT_Z2" 'is itself a bind mount' 'a mounted ~/.claude is not mistaken for a mounted home'
for name in "${TOOLS_FILES[@]}"; do
    assert_identical "$BIN_Z2/$name" "$(tools_vendor_path "$name")" "a container home still gets $name — the guard did not over-fire"
done

# And the override does what it says.
BIN_Z3="$TMPDIR_ROOT/bin-z3"
HOME_Z3="$TMPDIR_ROOT/home-z3"
mkdir -p "$BIN_Z3" "$HOME_Z3"
MOUNTINFO_WHOLE_HOME3="$TMPDIR_ROOT/mountinfo-whole-home-3"
printf '26 25 0:24 / %s rw,relatime shared:4 - ext4 /dev/sdd rw\n' "$HOME_Z3" > "$MOUNTINFO_WHOLE_HOME3"
STATUS_Z3=0
run_start_step_with_mountinfo "$HOME_Z3" "$BIN_Z3" "$MOUNTINFO_WHOLE_HOME3" WORKBENCHES_ESTATE_FORCE=1 >/dev/null 2>&1 || STATUS_Z3=$?
assert_equal '0' "$STATUS_Z3" 'WORKBENCHES_ESTATE_FORCE=1 exits 0'
assert_identical "$BIN_Z3/lanes-edit.sh" "$(tools_vendor_path lanes-edit.sh)" 'WORKBENCHES_ESTATE_FORCE=1 installs into a shared host home anyway'

printf '%s\n' '--- Scenario (aa) [opensoft/workBenches#132]: every file the vendored shim installs has its own COPY line and chmod in the Layer 1a Dockerfile ---'
# The Dockerfile COPYs each bin file into /usr/local/bin by name, one line
# apiece, and NOTHING compared that list with the shim's own INSTALLABLES: the
# image went on baking thirteen files while the vendored shim grew to fifteen,
# which is how a bench start came to reinstall an old copy over a newer one
# (opensoft/workBenches#132). The whole-tree COPY under /usr/local/share needs
# no per-file line, so it never noticed either. The list is read from the
# vendored shim itself -- one-line array, stripped to words, never executed,
# the way estate-commands-start reads it -- and compared with this suite's own
# TOOLS_FILES first, so a shim that grows fails here by NAME before it fails
# anywhere else. Whole-line and whole-word matches, not substrings: `lane` is
# a prefix of `lane-end`, `lane-handoff` and `lane-start`.
DEV_DOCKERFILE="$BASE_IMAGE_DIR/Dockerfile"
DEV_DOCKERFILE_TEXT="$(cat "$DEV_DOCKERFILE")"
SHIM_INSTALLABLES_WORDS="$(sed -n 's/^INSTALLABLES=(\(.*\))$/\1/p' "$TOOLS_VENDOR" | head -n 1)"
read -r -a SHIM_INSTALLABLES <<<"$SHIM_INSTALLABLES_WORDS"
assert_equal "$(IFS=,; echo "${SHIM_INSTALLABLES[*]}")" "$(IFS=,; echo "${TOOLS_FILES[*]}")" "this suite's TOOLS_FILES is the vendored shim's own INSTALLABLES, in order"
# The `RUN chmod 0755 /usr/local/bin/openRepoShape ...` block with its
# continuations, one word per line, so a word is compared whole.
DEV_CHMOD_WORDS="$(awk '/^RUN chmod 0755 \/usr\/local\/bin\/openRepoShape /{p=1} p{for (i = 1; i <= NF; i++) if ($i != "\\") print $i; if ($0 !~ /\\$/) exit}' "$DEV_DOCKERFILE")"
assert_has_line() {
    local haystack="$1" line="$2" label="$3"
    if grep -Fxq -- "$line" <<<"$haystack"; then
        pass "$label"
    else
        fail "$label: no line equal to: $line"
    fi
}
for name in "${SHIM_INSTALLABLES[@]}"; do
    assert_has_line "$DEV_DOCKERFILE_TEXT" "COPY files/openrepotools/$name /usr/local/bin/$name" "the Dockerfile COPYs $name into /usr/local/bin"
    assert_has_line "$DEV_CHMOD_WORDS" "/usr/local/bin/$name" "the Dockerfile's chmod 0755 block lists /usr/local/bin/$name"
done

# ===========================================================================
# THE HOST'S openRepoShape RECORD (opensoft/workBenches#159, the host half of
# #153)
#
# Scenarios (ab)-(ah) belong with the host step above and sit down here only
# so that the letters of the scenarios in between stay as they were.
#
# The vendored openRepoShape launcher reads the ref it runs at from
# `openRepoShape.ref` beside the installed command, and its `--install` writes
# that record only when $OPENREPOSHAPE_RECORD_REF is 1, from
# $OPENREPOSHAPE_REF. The script used to set neither on purpose and exported
# the no-fetch sentinel as $OPENREPOSHAPE_REF, so two things went wrong on a
# host:
#   1. nothing was recorded, and a record already there was REMOVED, so the
#      host's command followed openRepoShape's main while the image's command
#      stayed on the release (hazard 1); and
#   2. the caller's own $OPENREPOSHAPE_RECORD_REF=1 reached the install, which
#      then recorded the SENTINEL as the host command's ref (hazard 2).
# Every scenario here runs with a fetch trap first on $PATH: `gh` and `curl`
# stubs that log what they were asked and fail, so no scenario can reach the
# real network or the real gh, and the log shows whether an install fetched.
TRAP_159="$TMPDIR_ROOT/fetch-trap-159"
mkdir -p "$TRAP_159"
for tool in gh curl; do
    cat > "$TRAP_159/$tool" <<EOF
#!/bin/sh
printf '%s %s\n' "$tool" "\$*" >> "$TRAP_159/calls.log"
exit 97
EOF
    chmod 0755 "$TRAP_159/$tool"
done
: > "$TRAP_159/calls.log"

run_record_install() {   # <home> <bin dir> [env args...] -- the script under test, the fetch trap first on PATH
    local home="$1" bin="$2"
    shift 2
    env "$@" HOME="$home" \
        CLAUDE_PROFILES_HOME="$home/.claude-profiles" CLAUDE_USER_DIR="$home/.claude" \
        OPENREPOSHAPE_BIN_DIR="$bin" OPENREPOTOOLS_BIN_DIR="$bin" \
        PATH="$TRAP_159:$PATH" "$SCRIPT_UNDER_TEST" 2>&1
}

# The text of a record, or nothing at all when there is none: a missing file
# must be a failed assertion below, never a stray `cat` error or an abort.
record_text() {
    cat -- "$1" 2>/dev/null || true
}

printf '%s\n' '--- Scenario (ab) [#159, hazard 1]: a fresh host install records the pin'"'"'s commit beside the command, and fetches nothing to do it ---'
BIN_AB="$TMPDIR_ROOT/bin-ab"
HOME_AB="$TMPDIR_ROOT/home-ab"
mkdir -p "$BIN_AB" "$HOME_AB"
: > "$TRAP_159/calls.log"
STATUS_AB=0
OUTPUT_AB="$(run_record_install "$HOME_AB" "$BIN_AB" -u OPENREPOSHAPE_RECORD_REF)" || STATUS_AB=$?
CALLS_AB="$(cat "$TRAP_159/calls.log")"

assert_equal '0' "$STATUS_AB" 'fresh install with no OPENREPOSHAPE_RECORD_REF in the caller'"'"'s shell: exit code'
assert_equal "$(record_text "$BIN_AB/openRepoShape.ref")" "$SHAPE_COMMIT" "the record beside the host's openRepoShape holds the pin's openreposhape commit"
assert_equal "$(wc -c < "$BIN_AB/openRepoShape.ref" 2>/dev/null | tr -d ' ')" '41' 'the record is the 40-hex commit and one newline, nothing else'
assert_contains "$OUTPUT_AB" "openRepoShape: pinned to $SHAPE_COMMIT, recorded in $BIN_AB/openRepoShape.ref" "the launcher's own line says it recorded the pin"
assert_not_contains "$OUTPUT_AB" 'follows main' 'the install does not say it removed a record and follows main'
# What the command says it runs at, read from the installed copy itself, with the
# two variables that would override the record taken out of its environment.
VERSION_AB="$(env -u OPENREPOSHAPE_REF -u OPENREPOSHAPE_REPO PATH="$TRAP_159:$PATH" "$BIN_AB/openRepoShape" --version 2>&1)" || true
assert_equal "$VERSION_AB" "openRepoShape (opensoft/openRepoShape @ $SHAPE_COMMIT)" "the installed command's --version names the pin's commit, the ref the image's command runs at"
assert_not_contains "$VERSION_AB" "$ESTATE_SENTINEL_VALUE" 'the installed command does not report the sentinel as its ref'
# Recording needs no fetch: the launcher run as a file installs the bytes beside
# it. `gh auth status` is its own machine report, not a fetch.
assert_not_contains "$CALLS_AB" 'gh api' 'recording the pin fetched nothing through gh api'
assert_not_contains "$CALLS_AB" 'curl' 'recording the pin fetched nothing through curl'

printf '%s\n' '--- Scenario (ac) [#159, hazard 1]: an older or damaged record is replaced by the pin'"'"'s commit, and a second run leaves it ---'
BIN_AC="$TMPDIR_ROOT/bin-ac"
HOME_AC="$TMPDIR_ROOT/home-ac"
mkdir -p "$BIN_AC" "$HOME_AC"
# What the one-line installer (install.sh) leaves: the release TAG.
printf 'v1.0.0\n' > "$BIN_AC/openRepoShape.ref"
STATUS_AC=0
OUTPUT_AC="$(run_record_install "$HOME_AC" "$BIN_AC" -u OPENREPOSHAPE_RECORD_REF)" || STATUS_AC=$?
assert_equal '0' "$STATUS_AC" 'an install over a v1.0.0 record: exit code'
assert_equal "$(record_text "$BIN_AC/openRepoShape.ref")" "$SHAPE_COMMIT" 'the v1.0.0 record is replaced by the pin'"'"'s commit, not removed'
assert_contains "$OUTPUT_AC" "pinned to $SHAPE_COMMIT (was v1.0.0), recorded in" 'the launcher says what the record held before'
assert_not_contains "$OUTPUT_AC" 'no longer pinned' 'the install does not say it un-pinned the host'

STATUS_AC2=0
OUTPUT_AC2="$(run_record_install "$HOME_AC" "$BIN_AC" -u OPENREPOSHAPE_RECORD_REF)" || STATUS_AC2=$?
assert_equal '0' "$STATUS_AC2" 'a second run over the pin'"'"'s record: exit code'
assert_contains "$OUTPUT_AC2" "already pinned to $SHAPE_COMMIT in $BIN_AC/openRepoShape.ref (unchanged)" 'a second run reports the record unchanged'
assert_equal "$(record_text "$BIN_AC/openRepoShape.ref")" "$SHAPE_COMMIT" 'a second run leaves the record as it was'

# A host that hazard 2 had already damaged: the sentinel recorded as its ref.
printf '%s\n' "$ESTATE_SENTINEL_VALUE" > "$BIN_AC/openRepoShape.ref"
STATUS_AC3=0
OUTPUT_AC3="$(run_record_install "$HOME_AC" "$BIN_AC" -u OPENREPOSHAPE_RECORD_REF)" || STATUS_AC3=$?
assert_equal '0' "$STATUS_AC3" 'an install over a record that holds the sentinel: exit code'
assert_equal "$(record_text "$BIN_AC/openRepoShape.ref")" "$SHAPE_COMMIT" 'a record that holds the sentinel is repaired to the pin'"'"'s commit'
assert_contains "$OUTPUT_AC3" "(was $ESTATE_SENTINEL_VALUE)" 'the launcher names the sentinel record it replaced'

printf '%s\n' '--- Scenario (ad) [#159, hazard 2]: the caller'"'"'s own OPENREPOSHAPE_RECORD_REF (and REF) never reaches the install, and the sentinel is never recorded ---'
# `1` is the hazard: the install recorded $OPENREPOSHAPE_REF, which this script
# had exported as the sentinel. `0` and `yes` are the other things a shell may
# hold: the install used to record nothing for them (and remove a record), and
# now records the pin whatever the caller's shell says. The last row is an
# operator who names a branch of their own AND asks for it to be recorded.
ad_run=0
for ad_spec in '1|' '0|' 'yes|' '1|operator-branch'; do
    ad_run=$((ad_run + 1))
    ad_record_ref="${ad_spec%%|*}"
    ad_ref="${ad_spec#*|}"
    HOME_AD="$TMPDIR_ROOT/home-ad$ad_run"
    BIN_AD="$TMPDIR_ROOT/bin-ad$ad_run"
    mkdir -p "$HOME_AD" "$BIN_AD"
    ad_env=(OPENREPOSHAPE_RECORD_REF="$ad_record_ref")
    [ -z "$ad_ref" ] || ad_env+=(OPENREPOSHAPE_REF="$ad_ref")
    ad_label="OPENREPOSHAPE_RECORD_REF=$ad_record_ref${ad_ref:+ OPENREPOSHAPE_REF=$ad_ref} in the caller's shell"
    STATUS_AD=0
    OUTPUT_AD="$(run_record_install "$HOME_AD" "$BIN_AD" "${ad_env[@]}")" || STATUS_AD=$?
    assert_equal '0' "$STATUS_AD" "$ad_label: exit code"
    assert_equal "$(record_text "$BIN_AD/openRepoShape.ref")" "$SHAPE_COMMIT" "$ad_label: the record holds the pin's commit"
    assert_not_contains "$(record_text "$BIN_AD/openRepoShape.ref")" "$ESTATE_SENTINEL_VALUE" "$ad_label: the sentinel is not what was recorded"
    assert_not_contains "$OUTPUT_AD" "pinned to $ESTATE_SENTINEL_VALUE" "$ad_label: the launcher does not say it pinned the sentinel"
    assert_not_contains "$OUTPUT_AD" 'pinned to operator-branch' "$ad_label: the operator's own ref is not what was recorded"
done
# The reproduction RV154 gave on #159, read back through the installed command.
BIN_AD1="$TMPDIR_ROOT/bin-ad1"
VERSION_AD1="$(env -u OPENREPOSHAPE_REF -u OPENREPOSHAPE_REPO PATH="$TRAP_159:$PATH" "$BIN_AD1/openRepoShape" --version 2>&1)" || true
assert_equal "$VERSION_AD1" "openRepoShape (opensoft/openRepoShape @ $SHAPE_COMMIT)" 'after an install with OPENREPOSHAPE_RECORD_REF=1 in the caller'"'"'s shell, the command reports the pin, not "@ pinned-by-workBenches-no-fetch"'

printf '%s\n' '--- Scenario (ae) [#159]: a symlinked or non-regular record refuses before anything is placed, like every other target ---'
BIN_AE="$TMPDIR_ROOT/bin-ae"
HOME_AE="$TMPDIR_ROOT/home-ae"
OTHER_AE="$TMPDIR_ROOT/other-ae"
mkdir -p "$BIN_AE" "$HOME_AE" "$OTHER_AE"
printf 'somebody else'"'"'s ref\n' > "$OTHER_AE/record"
ln -s "$OTHER_AE/record" "$BIN_AE/openRepoShape.ref"
STATUS_AE=0
OUTPUT_AE="$(run_record_install "$HOME_AE" "$BIN_AE" -u OPENREPOSHAPE_RECORD_REF)" || STATUS_AE=$?
assert_equal '1' "$STATUS_AE" 'a symlinked record: exit code'
assert_contains "$OUTPUT_AE" "$BIN_AE/openRepoShape.ref" 'the refusal names the symlinked record'
assert_contains "$OUTPUT_AE" 'symlink' 'the refusal says it is a symlink'
assert_equal "somebody else's ref" "$(cat "$OTHER_AE/record")" 'what the symlink points at is byte for byte unchanged'
assert_equal '1' "$(find "$BIN_AE" -mindepth 1 | wc -l | tr -d ' ')" 'nothing was placed into the bin dir (only the symlink remains)'
assert_absent "$HOME_AE/.claude" 'nothing was written under $HOME/.claude either (neither shim ran)'

BIN_AE2="$TMPDIR_ROOT/bin-ae2"
HOME_AE2="$TMPDIR_ROOT/home-ae2"
mkdir -p "$BIN_AE2/openRepoShape.ref" "$HOME_AE2"
STATUS_AE2=0
OUTPUT_AE2="$(run_record_install "$HOME_AE2" "$BIN_AE2" -u OPENREPOSHAPE_RECORD_REF)" || STATUS_AE2=$?
assert_equal '1' "$STATUS_AE2" 'a directory standing in for the record: exit code'
assert_contains "$OUTPUT_AE2" 'not a regular file' 'the refusal says the record is not a regular file'
assert_equal '0' "$([ -e "$BIN_AE2/openRepoShape" ] && echo 1 || echo 0)" 'openRepoShape was NOT placed beside a record that cannot be written'
assert_absent "$HOME_AE2/.claude" 'nothing was written under $HOME/.claude either (neither shim ran)'

# A record this user cannot READ: the launcher reads the ref it holds before it
# replaces it, and does that only after placing openRepoShape. Mode 0200 is
# unreadable to a non-root user and readable to root, which no chmod changes;
# like scenario (i) this assumes a non-root runner, and where the file is still
# readable after the chmod it is SKIPPED, not failed, as scenario (y) is for want
# of flock.
BIN_AE3="$TMPDIR_ROOT/bin-ae3"
HOME_AE3="$TMPDIR_ROOT/home-ae3"
mkdir -p "$BIN_AE3" "$HOME_AE3"
printf '%s\n' "$SHAPE_COMMIT" > "$BIN_AE3/openRepoShape.ref"
chmod 0200 "$BIN_AE3/openRepoShape.ref"
if [ -r "$BIN_AE3/openRepoShape.ref" ]; then
    printf 'SKIP: scenario (ae) unreadable record needs a user that mode 0200 locks out; this one (root?) can still read it.\n'
else
    STATUS_AE3=0
    OUTPUT_AE3="$(run_record_install "$HOME_AE3" "$BIN_AE3" -u OPENREPOSHAPE_RECORD_REF)" || STATUS_AE3=$?
    assert_equal '1' "$STATUS_AE3" 'an unreadable record: exit code'
    assert_contains "$OUTPUT_AE3" "$BIN_AE3/openRepoShape.ref exists and is not readable" 'the refusal names the unreadable record'
    assert_contains "$OUTPUT_AE3" 'Nothing was installed.' 'the refusal is a preflight one: nothing was installed'
    assert_equal '0' "$([ -e "$BIN_AE3/openRepoShape" ] && echo 1 || echo 0)" 'openRepoShape was NOT placed beside a record the launcher could not read'
    assert_absent "$HOME_AE3/.claude" 'nothing was written under $HOME/.claude either (neither shim ran)'
    assert_not_contains "$OUTPUT_AE3" 'Permission denied' 'the refusal is ours, not a bare Permission denied from the launcher'
fi
chmod 0644 "$BIN_AE3/openRepoShape.ref"

printf '%s\n' '--- Scenario (af) [#159]: a launcher that leaves no record, or the wrong one, is caught by the post-install check ---'
# The vendored launcher is the one that records. If a re-pin ever took one that
# did not (or that recorded something else), every file above would still
# verify while the host command followed main, so the record is read back and
# compared with the pin. Proved on throwaway copies of base-image with the ONE
# launcher line changed and that one pin row re-digested by hand, which is what
# `update-upstream.py apply` would have done, so `check` still passes.
patch_shape_launcher() {   # <base dir> <old text> <new text>
    python3 - "$1" "$2" "$3" <<'PYEOF'
import hashlib
import sys

base, old, new = sys.argv[1:4]
launcher = f"{base}/files/openreposhape/openRepoShape"
pin_path = f"{base}/upstream-pin.yaml"

with open(launcher, "r", encoding="utf-8") as f:
    text = f.read()
if text.count(old) != 1:
    raise SystemExit(f"expected exactly one occurrence of {old!r}, found {text.count(old)}")
text = text.replace(old, new)
with open(launcher, "w", encoding="utf-8") as f:
    f.write(text)
digest = hashlib.sha256(text.encode("utf-8")).hexdigest()

with open(pin_path, "r", encoding="utf-8") as f:
    lines = f.readlines()
out = []
i = 0
patched = False
while i < len(lines):
    out.append(lines[i])
    if lines[i].strip() == "- path: openRepoShape":
        out.append(lines[i + 1].split(":")[0] + f': "{digest}"\n')
        out.append(lines[i + 2])
        i += 3
        patched = True
        continue
    i += 1
if not patched:
    raise SystemExit("could not find the openRepoShape pin row to patch")
with open(pin_path, "w", encoding="utf-8") as f:
    f.writelines(out)
PYEOF
}

# What a refusal over the record says (SHOULD 1 of RV161's review of #161): its
# OWN text, not `refuse_postverify`'s, which names the fifteen openRepoTools
# commands (not re-checked yet at that point) and tells the person to re-run
# (which cannot change a record the vendored launcher writes). It must say that
# openRepoShape is placed and NOT held on the pin, and name the two places the
# fix is: the pin and the vendored launcher, here in the base-image copy under test.
assert_record_refusal_text() {   # <output> <base dir> <label>
    assert_contains "$1" 'openRepoShape is placed but is NOT held on the pin' "$3: the refusal says openRepoShape is placed and not held on the pin"
    assert_contains "$1" "The fix is the pin" "$3: the refusal says the fix is the pin ..."
    assert_contains "$1" "$2/upstream-pin.yaml" "$3: ... and names the pin file"
    assert_contains "$1" "$2/files/openreposhape/openRepoShape" "$3: ... and the vendored launcher"
    assert_not_contains "$1" 'fifteen openRepoTools commands' "$3: the refusal does not blame the openRepoTools commands"
    assert_not_contains "$1" 're-run this script' "$3: the refusal does not tell the person to re-run, which cannot help"
}

NORECORD_BASE="$TMPDIR_ROOT/norecord-base-image"
mkdir -p "$NORECORD_BASE"
cp -r "$BASE_IMAGE_DIR/." "$NORECORD_BASE/"
patch_shape_launcher "$NORECORD_BASE" '	record_ref "$record" "$recording"
' '	true
'
NORECORD_CHECK_STATUS=0
python3 "$NORECORD_BASE/update-upstream.py" check >"$TMPDIR_ROOT/norecord-check.log" 2>&1 || NORECORD_CHECK_STATUS=$?
assert_equal '0' "$NORECORD_CHECK_STATUS" "scenario (af) setup: 'check' passes on the copy whose launcher writes no record"
BIN_AF="$TMPDIR_ROOT/bin-af"
HOME_AF="$TMPDIR_ROOT/home-af"
mkdir -p "$BIN_AF" "$HOME_AF"
STATUS_AF=0
OUTPUT_AF="$(run_record_install "$HOME_AF" "$BIN_AF" -u OPENREPOSHAPE_RECORD_REF WORKBENCHES_BASE_IMAGE_DIR="$NORECORD_BASE")" || STATUS_AF=$?
assert_equal '1' "$STATUS_AF" 'a launcher that writes no record: exit code'
assert_contains "$OUTPUT_AF" "$BIN_AF/openRepoShape.ref is not a regular file after install" 'the refusal names the missing record'
assert_contains "$OUTPUT_AF" "$SHAPE_COMMIT" 'the refusal names the commit the host is not held on'
assert_record_refusal_text "$OUTPUT_AF" "$NORECORD_BASE" 'a launcher that writes no record'
assert_not_contains "$OUTPUT_AF" 'Estate commands verified against the vendored pin.' 'a host that follows main is not reported as verified against the pin'

WRONGREF_BASE="$TMPDIR_ROOT/wrongref-base-image"
mkdir -p "$WRONGREF_BASE"
cp -r "$BASE_IMAGE_DIR/." "$WRONGREF_BASE/"
patch_shape_launcher "$WRONGREF_BASE" 'printf '"'"'%s\n'"'"' "$REF" >"$record"' 'printf '"'"'%s\n'"'"' main >"$record"'
WRONGREF_CHECK_STATUS=0
python3 "$WRONGREF_BASE/update-upstream.py" check >"$TMPDIR_ROOT/wrongref-check.log" 2>&1 || WRONGREF_CHECK_STATUS=$?
assert_equal '0' "$WRONGREF_CHECK_STATUS" "scenario (af) setup: 'check' passes on the copy whose launcher records main"
BIN_AF2="$TMPDIR_ROOT/bin-af2"
HOME_AF2="$TMPDIR_ROOT/home-af2"
mkdir -p "$BIN_AF2" "$HOME_AF2"
STATUS_AF2=0
OUTPUT_AF2="$(run_record_install "$HOME_AF2" "$BIN_AF2" -u OPENREPOSHAPE_RECORD_REF WORKBENCHES_BASE_IMAGE_DIR="$WRONGREF_BASE")" || STATUS_AF2=$?
assert_equal '1' "$STATUS_AF2" 'a launcher that records a ref other than the pin: exit code'
assert_contains "$OUTPUT_AF2" "$BIN_AF2/openRepoShape.ref holds 'main' after install" 'the refusal names what the record holds'
assert_not_contains "$OUTPUT_AF2" 'Estate commands verified against the vendored pin.' 'a record that is not the pin is not reported as verified'
assert_record_refusal_text "$OUTPUT_AF2" "$WRONGREF_BASE" 'a launcher that records main'

# A record that is a COMMIT, but not THE commit: "forty hex digits" is not "the
# pin". This row is what tells a check of `held = pin` from a check of `held
# looks like a commit` (mutation m5 of RV161's review of #161).
OTHER_COMMIT="ffffffffffffffffffffffffffffffffffffffff"
assert_matches "$OTHER_COMMIT" '^[0-9a-f]{40}$' 'scenario (af) setup: the stand-in commit is 40 lowercase hex'
if [ "$OTHER_COMMIT" = "$SHAPE_COMMIT" ]; then fail 'scenario (af) setup: the stand-in commit must differ from the pin'; fi
OTHERCOMMIT_BASE="$TMPDIR_ROOT/othercommit-base-image"
mkdir -p "$OTHERCOMMIT_BASE"
cp -r "$BASE_IMAGE_DIR/." "$OTHERCOMMIT_BASE/"
patch_shape_launcher "$OTHERCOMMIT_BASE" 'printf '"'"'%s\n'"'"' "$REF" >"$record"' "printf '%s\\n' $OTHER_COMMIT >\"\$record\""
OTHERCOMMIT_CHECK_STATUS=0
python3 "$OTHERCOMMIT_BASE/update-upstream.py" check >"$TMPDIR_ROOT/othercommit-check.log" 2>&1 || OTHERCOMMIT_CHECK_STATUS=$?
assert_equal '0' "$OTHERCOMMIT_CHECK_STATUS" "scenario (af) setup: 'check' passes on the copy whose launcher records a different commit"
BIN_AF3="$TMPDIR_ROOT/bin-af3"
HOME_AF3="$TMPDIR_ROOT/home-af3"
mkdir -p "$BIN_AF3" "$HOME_AF3"
STATUS_AF3=0
OUTPUT_AF3="$(run_record_install "$HOME_AF3" "$BIN_AF3" -u OPENREPOSHAPE_RECORD_REF WORKBENCHES_BASE_IMAGE_DIR="$OTHERCOMMIT_BASE")" || STATUS_AF3=$?
assert_equal '1' "$STATUS_AF3" 'a launcher that records a DIFFERENT commit than the pin: exit code'
assert_equal "$(record_text "$BIN_AF3/openRepoShape.ref")" "$OTHER_COMMIT" 'scenario (af) setup: that launcher really did record the other commit'
assert_contains "$OUTPUT_AF3" "$BIN_AF3/openRepoShape.ref holds '$OTHER_COMMIT' after install" 'the refusal names the other commit the record holds'
assert_contains "$OUTPUT_AF3" "expected the pinned openRepoShape commit $SHAPE_COMMIT" 'the refusal names the pin'"'"'s commit it expected'
assert_not_contains "$OUTPUT_AF3" 'Estate commands verified against the vendored pin.' 'a record holding some other commit is not reported as verified'
assert_record_refusal_text "$OUTPUT_AF3" "$OTHERCOMMIT_BASE" 'a launcher that records a different commit'

printf '%s\n' '--- Scenario (ag) [#159]: the record sits beside openRepoShape, wherever OPENREPOSHAPE_BIN_DIR puts it, and not beside openRepoTools ---'
SHAPE_BIN_AG="$TMPDIR_ROOT/shape-bin-ag"
TOOLS_BIN_AG="$TMPDIR_ROOT/tools-bin-ag"
HOME_AG="$TMPDIR_ROOT/home-ag"
mkdir -p "$SHAPE_BIN_AG" "$TOOLS_BIN_AG" "$HOME_AG"
STATUS_AG=0
OUTPUT_AG="$(env -u OPENREPOSHAPE_RECORD_REF HOME="$HOME_AG" \
    CLAUDE_PROFILES_HOME="$HOME_AG/.claude-profiles" CLAUDE_USER_DIR="$HOME_AG/.claude" \
    OPENREPOSHAPE_BIN_DIR="$SHAPE_BIN_AG" OPENREPOTOOLS_BIN_DIR="$TOOLS_BIN_AG" \
    PATH="$TRAP_159:$PATH" "$SCRIPT_UNDER_TEST" 2>&1)" || STATUS_AG=$?
assert_equal '0' "$STATUS_AG" 'separate bin directories for the two commands: exit code'
assert_equal "$(record_text "$SHAPE_BIN_AG/openRepoShape.ref")" "$SHAPE_COMMIT" 'the record is beside openRepoShape'
assert_contains "$OUTPUT_AG" "recorded in $SHAPE_BIN_AG/openRepoShape.ref" 'the launcher says where it recorded the pin'
assert_absent "$TOOLS_BIN_AG/openRepoShape.ref" 'no record is placed beside the openRepoTools files'
assert_absent "$TOOLS_BIN_AG/openRepoShape" 'openRepoShape itself is not placed in the openRepoTools bin directory either'

printf '%s\n' '--- Scenario (ah) [#159, RV161 m3 and m10]: the install call carries both variables inline, and the repo on it is still the sentinel ---'
# Two properties no run can show, because the mutations that break them change
# nothing a run can see today, so, as scenario (m) does for the four exports, the
# source is read for them:
#   - m3: the two variables EXPORTED instead of prefixed to the one call. They
#     would then reach the openRepoTools install too, and any later call the
#     script grows; a prefix is in force for that one command only.
#   - m10: the real repository named on that call instead of the sentinel. A
#     fetch reached there would then succeed against the network, not fail by
#     name, and the record would still read the same.
# Comment lines are dropped first, so a sentence in a comment can neither satisfy
# nor break one of them.
SCRIPT_CODE_159="$(grep -v '^[[:space:]]*#' "$SCRIPT_UNDER_TEST")"
assert_has_line "$SCRIPT_CODE_159" 'if ! OPENREPOSHAPE_REF="$shape_commit" OPENREPOSHAPE_RECORD_REF=1 "$SHAPE_SHIM" --install; then' 'the openRepoShape install call carries both variables inline: the pin'"'"'s commit as the ref, and the record asked for, nothing else on it (no repo)'
assert_equal '1' "$(count_occurrences "$SCRIPT_CODE_159" 'OPENREPOSHAPE_RECORD_REF')" 'OPENREPOSHAPE_RECORD_REF appears once in the script'"'"'s code: on that call, never exported'
assert_not_contains "$SCRIPT_CODE_159" 'export OPENREPOSHAPE_RECORD_REF' 'OPENREPOSHAPE_RECORD_REF is not exported'
assert_not_contains "$SCRIPT_CODE_159" 'export OPENREPOSHAPE_REF="$shape_commit"' 'the pin'"'"'s commit is not exported as OPENREPOSHAPE_REF'
assert_equal '2' "$(count_occurrences "$SCRIPT_CODE_159" 'OPENREPOSHAPE_REF=')" 'OPENREPOSHAPE_REF is assigned twice in the code: the exported sentinel, and the one call'
assert_equal '1' "$(count_occurrences "$SCRIPT_CODE_159" 'OPENREPOSHAPE_REPO=')" 'OPENREPOSHAPE_REPO is assigned once in the code: the exported sentinel, so the call'"'"'s repo is the sentinel'
assert_has_line "$SCRIPT_CODE_159" 'export OPENREPOSHAPE_REPO="$ESTATE_SENTINEL"' 'and that one assignment is the sentinel'

# #237 integration cases stay in this already-triggered CI suite. All homes,
# receipt/config roots and repositories are disposable; no GitHub is contacted.
python3 - "$REPO_ROOT" <<'HOOK_GATE_TESTS'
#!/usr/bin/env python3
"""Vendored #237 integration: disposable homes, local git only, no real accounts."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(sys.argv.pop(1)).resolve()
SESSION = '~/projects/xFactory/lanes-edit.sh session-start || true'
GUARD = '~/projects/xFactory/lanes-edit.sh guard'


class EstateHookGateTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(); self.addCleanup(temporary.cleanup)
        self.home = Path(temporary.name) / 'home'; self.home.mkdir()
        self.bin = self.home / '.local/bin'
        self.env = {key: value for key, value in os.environ.items()
                    if not key.startswith(('LANES_', 'TMUX', 'CLAUDE_', 'WORKBENCHES_', 'OPENREPOTOOLS_', 'OPENREPOSHAPE_', 'GH_', 'GITHUB_', 'XDG_'))}
        self.env.update(HOME=str(self.home), PATH=str(self.bin) + os.pathsep + os.environ['PATH'],
            XDG_DATA_HOME=str(self.home / '.local/share'), XDG_CACHE_HOME=str(self.home / '.cache'),
            XDG_CONFIG_HOME=str(self.home / '.config'), AGENT_PROTOCOL_ROOT=str(self.home / '.agents'),
            PROJECTS_ROOT=str(self.home / 'projects'), OPENREPOTOOLS_BIN_DIR=str(self.bin),
            OPENREPOSHAPE_BIN_DIR=str(self.bin), CLAUDE_USER_DIR=str(self.home / '.claude'),
            CLAUDE_PROFILES_HOME=str(self.home / '.claude-profiles'))
        self.settings = self.home / '.claude/settings.json'

    def run_command(self, *argv, **kwargs):
        result = subprocess.run(argv, env=self.env, cwd=ROOT, capture_output=True, text=True, timeout=40, **kwargs)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def install(self):
        return self.run_command('bash', str(ROOT / 'scripts/setup-estate-commands.sh'))

    def hooks(self, event):
        data = json.loads(self.settings.read_text()) if self.settings.exists() else {}
        return [hook.get('command') for item in data.get('hooks', {}).get(event, []) for hook in item.get('hooks', [])]

    def workspace(self):
        checkout = self.home / 'example-wip'; checkout.mkdir()
        self.run_command('git', 'init', '-q', str(checkout))
        self.run_command('git', '-C', str(checkout), 'remote', 'add', 'origin', 'https://github.com/example/example-wip.git')
        (checkout / 'lanes').mkdir(); (checkout / 'lanes/LANES.md').write_text('')
        (checkout / 'handoffs/xFactory').mkdir(parents=True)
        (self.home / 'projects/xFactory').mkdir(parents=True)
        (self.home / '.agents').mkdir()
        (self.home / '.agents/workspace.yaml').write_text('repository: example/example-wip\npath: ' + str(checkout) + '\n')

    def assert_pair(self):
        self.assertEqual(self.hooks('SessionStart').count(SESSION), 1)
        self.assertEqual(self.hooks('UserPromptSubmit').count(GUARD), 1)
        self.assertEqual(self.settings.stat().st_mode & 0o777, 0o600)

    def test_fresh_and_interrupted_install_never_places_missing_prompt_target(self):
        for _ in range(2):
            result = self.install()
            self.assertIn('UserPromptSubmit guard: deferred', result.stdout)
            self.assertNotIn(GUARD, self.hooks('UserPromptSubmit'))
            self.assertNotIn(SESSION, self.hooks('SessionStart'))
        for name in ('openRepoTools', 'lanes-index', 'lane-worktrees'):
            self.assertTrue(os.access(self.bin / name, os.X_OK))

    def test_migration_removes_only_our_broken_guard_and_preserves_foreign_hooks(self):
        self.settings.parent.mkdir()
        self.settings.write_text(json.dumps({'custom': 'preserved', 'hooks': {
            'SessionStart': [{'hooks': [{'type': 'command', 'command': SESSION}]}],
            'UserPromptSubmit': [{'hooks': [{'type': 'command', 'command': GUARD},
                                          {'type': 'command', 'command': 'echo personal-hook'}]}]}}))
        self.settings.chmod(0o644)
        self.install()
        self.assertEqual(self.hooks('SessionStart'), [SESSION])
        self.assertEqual(self.hooks('UserPromptSubmit'), ['echo personal-hook'])
        self.assertEqual(json.loads(self.settings.read_text())['custom'], 'preserved')
        self.assertEqual(self.settings.stat().st_mode & 0o777, 0o600)

    def test_wip_init_rerun_heals_interruption_and_keeps_real_guard_refusal(self):
        self.install(); self.workspace()
        for _ in range(2):
            self.run_command(str(self.bin / 'openRepoTools'), 'wip', 'init')
            self.assert_pair()
        result = subprocess.run(['bash', str(self.bin / 'lanes-edit.sh'), 'guard'], env=self.env,
            input=json.dumps({'session_id': 'fixture', 'cwd': str(self.home), 'prompt': 'hello'}),
            capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)

    def test_container_start_completes_hooks_after_linking_on_the_first_run(self):
        self.workspace()
        self.env['WORKBENCHES_ESTATE_VENDOR_DIR'] = str(ROOT / 'devBenches/base-image/files/openrepotools')
        self.run_command('bash', str(ROOT / 'devBenches/base-image/files/estate/estate-commands-start'))
        self.assert_pair()
        self.assertTrue((self.home / 'projects/xFactory/lanes-edit.sh').is_symlink())


if __name__ == '__main__': unittest.main()
HOOK_GATE_TESTS

if (( failures == 0 )); then
    printf '%s\n' 'GREEN: setup-estate-commands regression test passed'
else
    printf 'RED: %d assertion(s) failed\n' "$failures"
    exit 1
fi
