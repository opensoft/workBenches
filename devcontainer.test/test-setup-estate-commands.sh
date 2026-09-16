#!/usr/bin/env bash
# Regression test for scripts/setup-estate-commands.sh (opensoft/workBenches#37,
# grown for opensoft/openRepoTools#26 and re-grown for opensoft/openRepoTools
# #45): the host's openRepoShape, and openRepoTools's own TWENTY-SIX
# artifacts -- the TWELVE files `openRepoTools --install` places on $PATH
# (itself, park, resume, status, lane, lanes, lane-handoff, and the four
# lane helpers `lanes-edit.sh`, `lane-start`, `lane-end` and `link-estates`
# with the alias table `repos.tsv` they read), the `handoff`, `lane-swap`
# and `restart` skills, the `handoff`, `ctx` and `swap` command files, and
# the merged `SessionStart` and `UserPromptSubmit` entries in
# `~/.claude/settings.json` -- all come from workBenches' own vendored pin
# (EIGHTEEN pinned openrepotools paths, plus openRepoShape's own two), and
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
# now checking all eighteen openrepotools paths) refuses a documented
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

# THE TWELVE FILES `openRepoTools --install` places on $PATH (openRepoTools#26
# and #45). One list, so scenarios (a), (b) and (l) cannot disagree about
# what a complete bin-directory install is.
TOOLS_FILES=(openRepoTools park resume status lane lanes lane-handoff lanes-edit.sh lane-start lane-end link-estates repos.tsv)
tools_vendor_path() { printf '%s/files/openrepotools/%s\n' "$BASE_IMAGE_DIR" "$1"; }

SKILL_NAMES=(handoff lane-swap restart)
COMMAND_NAMES=(handoff ctx swap)

TMPDIR_ROOT="$(mktemp -d)"
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

printf '%s\n' '--- Scenario (a): fresh bin dir + fresh $HOME installs all TWENTY-SIX openRepoTools artifacts, plus openRepoShape ---'
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
assert_contains "$OUTPUT_A" 'openRepoTools: 12 of 12 placed in' 'fresh install reports all twelve openRepoTools bin files placed'
for name in "${SKILL_NAMES[@]}"; do
    assert_skill_pair "$HOME_A" "$name" "fresh install places the $name skill"
    assert_contains "$OUTPUT_A" "$name: installed at" "fresh install reports an installed verb for the $name skill"
done
for name in "${COMMAND_NAMES[@]}"; do
    assert_command_pair "$HOME_A" "$name" "fresh install places the /$name command file"
    assert_contains "$OUTPUT_A" "/$name: installed at" "fresh install reports an installed verb for /$name"
done
assert_hook_present "$HOME_A" 'fresh install merges the SessionStart hook'
assert_contains "$OUTPUT_A" 'SessionStart hook: installed in' 'fresh install reports the hook as installed (new file)'
assert_guard_hook_present "$HOME_A" 'fresh install merges the UserPromptSubmit guard hook'
assert_contains "$OUTPUT_A" 'UserPromptSubmit guard: installed in' 'fresh install reports the guard hook as installed (new file)'
assert_contains "$OUTPUT_A" "openRepoShape pinned at $SHAPE_COMMIT" 'fresh install prints the openRepoShape pin commit'
assert_contains "$OUTPUT_A" "openRepoTools pinned at $TOOLS_COMMIT" 'fresh install prints the openRepoTools pin commit'
assert_contains "$OUTPUT_A" 'Estate commands verified against the vendored pin.' 'fresh install reports success only after post-install verification'
# Scenario (f) folded in here: a brand-new temp dir is never on $PATH. Fix 4
# removed this script's own PATH warning (the shims already print theirs),
# so the substring must appear exactly twice -- once per shim -- not three
# times. Twenty-six more report lines from the skills, the command files and
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
assert_contains "$OUTPUT_B" 'SessionStart hook: already installed in' 'second run reports the hook unchanged'
assert_hook_present "$HOME_A" 'second run still has the hook'
assert_contains "$OUTPUT_B" 'UserPromptSubmit guard: already installed in' 'second run reports the guard hook unchanged'
assert_guard_hook_present "$HOME_A" 'second run still has the guard hook'

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
# twenty-six again.
assert_contains "$OUTPUT_C" 'openRepoShape: already installed at' 'updated-park run still reports openRepoShape unchanged'
assert_contains "$OUTPUT_C" 'resume: already installed at' 'updated-park run still reports resume unchanged'
assert_contains "$OUTPUT_C" 'status: already installed at' 'updated-park run still reports status unchanged'
assert_contains "$OUTPUT_C" 'repos.tsv: already installed at' 'updated-park run still reports repos.tsv unchanged'
assert_contains "$OUTPUT_C" 'lane-swap: already installed at' 'updated-park run still reports the lane-swap skill unchanged'
assert_contains "$OUTPUT_C" '/swap: already installed at' 'updated-park run still reports /swap unchanged'
assert_contains "$OUTPUT_C" 'SessionStart hook: already installed in' 'updated-park run still reports the hook unchanged'

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
assert_equal '0' "$([ -e "$BIN_I/repos.tsv" ] && echo 1 || echo 0)" 'repos.tsv (last of the twelve) was NOT placed (D4 regression guard)'
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
# own `require_pin_row`, now checking all EIGHTEEN openrepotools paths
# instead of four, still catches "resume" missing a row before either shim
# runs, for the same reason it always did -- a file the shims would install
# with no row in the pin is refused here, explicitly, rather than ever
# reaching a shim that could fall back to fetching it. The all-or-nothing
# rule does not change this half of D3 at all: it only raises the stakes of
# the OTHER half, proved directly in part two below, because now the same
# missing file would cost the whole twenty-six-artifact install, not one
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

printf '%s\n' '--- Scenario (l): every one of the TWELVE placed openRepoTools bin files is mode 0755, and so is openRepoShape ---'
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
# It cannot live in scripts/ and be reached from a container: Layer 2's build
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
state_manifest() {   # <dir>...
    find "$@" -type f 2>/dev/null | LC_ALL=C sort | while IFS= read -r manifest_file; do
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
assert_contains "$OUTPUT_Q" 'openRepoTools: 12 of 12 placed in' 'the start step relays the installer'"'"'s own count line, not a summary of its own'
for name in "${SKILL_NAMES[@]}"; do
    assert_skill_pair "$HOME_Q" "$name" "the start step places the $name skill"
done
for name in "${COMMAND_NAMES[@]}"; do
    assert_command_pair "$HOME_Q" "$name" "the start step places the /$name command file"
done
assert_hook_present "$HOME_Q" 'the start step merges the SessionStart hook'
assert_guard_hook_present "$HOME_Q" 'the start step merges the UserPromptSubmit guard hook'
# The six per-user artifacts and the two hook entries are the half the image's
# own COPY into /usr/local/bin can never restore -- a build has no user's $HOME
# -- which is why the step runs `--install` rather than trusting those copies.

printf '%s\n' '--- Scenario (r): a second start is a no-op — every artifact reported unchanged, and not one byte written ---'
BEFORE_R="$(state_manifest "$BIN_Q" "$HOME_Q")"
STATUS_R=0
OUTPUT_R="$(run_start_step "$HOME_Q" "$BIN_Q")" || STATUS_R=$?
AFTER_R="$(state_manifest "$BIN_Q" "$HOME_Q")"

assert_equal '0' "$STATUS_R" 'a second start exits 0'
assert_equal "$BEFORE_R" "$AFTER_R" 'a second start writes nothing at all (same files, sizes and mtimes)'
assert_not_contains "$OUTPUT_R" ': installed at' 'a second start installs nothing'
for name in "${TOOLS_FILES[@]}"; do
    assert_contains "$OUTPUT_R" "$name: already installed at" "a second start reports $name unchanged"
done
assert_contains "$OUTPUT_R" 'SessionStart hook: already installed in' 'a second start reports the SessionStart hook unchanged'
assert_contains "$OUTPUT_R" 'UserPromptSubmit guard: already installed in' 'a second start reports the guard hook unchanged'

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
assert_not_contains "$OUTPUT_T" 'openRepoTools wip init' 'nothing refuses for want of a workspace repository once there is one'

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
# covers the case that motivates it: an image whose Layer 2 was not rebuilt
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

if (( failures == 0 )); then
    printf '%s\n' 'GREEN: setup-estate-commands regression test passed'
else
    printf 'RED: %d assertion(s) failed\n' "$failures"
    exit 1
fi
