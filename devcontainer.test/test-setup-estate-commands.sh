#!/usr/bin/env bash
# Regression test for scripts/setup-estate-commands.sh (opensoft/workBenches#37):
# the host's openRepoShape, openRepoTools, park, resume and status come from
# workBenches' own vendored pin, and the script places them, re-places them
# when they differ from the pin (either direction), and refuses to place
# anything when the vendored copies themselves no longer match the pin.
#
# Scenarios (g)-(m) guard the adversarial review round's D1-D6 findings: a
# symlinked target (D1), a directory target (D2), unpinned bytes reaching
# the shims from the network (D3), a partial install across two independent
# shim transactions (D4), the pin file itself missing, and the placed
# files' mode.

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

assert_mode() {
    local path="$1"
    local expected="$2"
    local label="$3"
    local actual
    actual="$(stat -c '%a' "$path" 2>/dev/null || stat -f '%Lp' "$path" 2>/dev/null)"
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

printf '%s\n' '--- Scenario (a): fresh bin dir installs all five commands from the vendored copies ---'
BIN_A="$TMPDIR_ROOT/bin-a"
mkdir -p "$BIN_A"
STATUS_A=0
OUTPUT_A="$(OPENREPOSHAPE_BIN_DIR="$BIN_A" OPENREPOTOOLS_BIN_DIR="$BIN_A" "$SCRIPT_UNDER_TEST" 2>&1)" || STATUS_A=$?

assert_equal '0' "$STATUS_A" 'fresh install exit code'
assert_file_executable "$BIN_A/openRepoShape" 'fresh install places openRepoShape, executable'
assert_file_executable "$BIN_A/openRepoTools" 'fresh install places openRepoTools, executable'
assert_file_executable "$BIN_A/park" 'fresh install places park, executable'
assert_file_executable "$BIN_A/resume" 'fresh install places resume, executable'
assert_file_executable "$BIN_A/status" 'fresh install places status, executable'
assert_identical "$BIN_A/openRepoShape" "$SHAPE_VENDOR" 'fresh openRepoShape is byte-identical to the vendored copy'
assert_identical "$BIN_A/openRepoTools" "$TOOLS_VENDOR" 'fresh openRepoTools is byte-identical to the vendored copy'
assert_identical "$BIN_A/park" "$PARK_VENDOR" 'fresh park is byte-identical to the vendored copy'
assert_identical "$BIN_A/resume" "$RESUME_VENDOR" 'fresh resume is byte-identical to the vendored copy'
assert_identical "$BIN_A/status" "$STATUS_VENDOR" 'fresh status is byte-identical to the vendored copy'
assert_contains "$OUTPUT_A" "openRepoShape pinned at $SHAPE_COMMIT" 'fresh install prints the openRepoShape pin commit'
assert_contains "$OUTPUT_A" "openRepoTools pinned at $TOOLS_COMMIT" 'fresh install prints the openRepoTools pin commit'
assert_contains "$OUTPUT_A" 'openRepoShape: installed at' 'fresh install reports an installed verb for openRepoShape'
assert_contains "$OUTPUT_A" 'openRepoTools: installed at' 'fresh install reports an installed verb for openRepoTools'
assert_contains "$OUTPUT_A" 'park: installed at' 'fresh install reports an installed verb for park'
assert_contains "$OUTPUT_A" 'resume: installed at' 'fresh install reports an installed verb for resume'
assert_contains "$OUTPUT_A" 'status: installed at' 'fresh install reports an installed verb for status'
assert_contains "$OUTPUT_A" 'Estate commands verified against the vendored pin.' 'fresh install reports success only after post-install verification'
# Scenario (f) folded in here: a brand-new temp dir is never on $PATH. Fix 4
# removed this script's own PATH warning (the shims already print theirs),
# so the substring must appear exactly twice -- once per shim -- not three
# times.
path_warning_count="$(count_occurrences "$OUTPUT_A" 'is not on $PATH')"
assert_equal '2' "$path_warning_count" 'exactly two PATH warnings (one per shim; this script prints no third copy)'

printf '%s\n' '--- Scenario (b): a second run over an already-installed bin dir reports unchanged ---'
STATUS_B=0
OUTPUT_B="$(OPENREPOSHAPE_BIN_DIR="$BIN_A" OPENREPOTOOLS_BIN_DIR="$BIN_A" "$SCRIPT_UNDER_TEST" 2>&1)" || STATUS_B=$?

assert_equal '0' "$STATUS_B" 'second run exit code'
assert_contains "$OUTPUT_B" 'openRepoShape: already installed at' 'second run reports openRepoShape unchanged'
assert_contains "$OUTPUT_B" 'openRepoTools: already installed at' 'second run reports openRepoTools unchanged'
assert_contains "$OUTPUT_B" 'park: already installed at' 'second run reports park unchanged'
assert_contains "$OUTPUT_B" 'resume: already installed at' 'second run reports resume unchanged'
assert_contains "$OUTPUT_B" 'status: already installed at' 'second run reports status unchanged'
assert_identical "$BIN_A/openRepoShape" "$SHAPE_VENDOR" 'openRepoShape still byte-identical after the second run'
assert_identical "$BIN_A/openRepoTools" "$TOOLS_VENDOR" 'openRepoTools still byte-identical after the second run'
assert_identical "$BIN_A/park" "$PARK_VENDOR" 'park still byte-identical after the second run'
assert_identical "$BIN_A/resume" "$RESUME_VENDOR" 'resume still byte-identical after the second run'
assert_identical "$BIN_A/status" "$STATUS_VENDOR" 'status still byte-identical after the second run'

printf '%s\n' '--- Scenario (c): a locally-modified park is replaced and reported updated ---'
printf '%s\n' '# a local edit, not the vendored bytes' >> "$BIN_A/park"
STATUS_C=0
OUTPUT_C="$(OPENREPOSHAPE_BIN_DIR="$BIN_A" OPENREPOTOOLS_BIN_DIR="$BIN_A" "$SCRIPT_UNDER_TEST" 2>&1)" || STATUS_C=$?

assert_equal '0' "$STATUS_C" 'updated-park run exit code'
assert_contains "$OUTPUT_C" 'park: updated at' 'the locally-modified park is reported updated'
assert_identical "$BIN_A/park" "$PARK_VENDOR" 'park is byte-identical to the vendored copy again after being updated'
# The other three were untouched, so this run still reports them unchanged.
assert_contains "$OUTPUT_C" 'openRepoShape: already installed at' 'updated-park run still reports openRepoShape unchanged'
assert_contains "$OUTPUT_C" 'resume: already installed at' 'updated-park run still reports resume unchanged'
assert_contains "$OUTPUT_C" 'status: already installed at' 'updated-park run still reports status unchanged'

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
mkdir -p "$BIN_D"
STATUS_D=0
OUTPUT_D="$(OPENREPOSHAPE_BIN_DIR="$BIN_D" OPENREPOTOOLS_BIN_DIR="$BIN_D" WORKBENCHES_BASE_IMAGE_DIR="$CORRUPT_BASE" "$SCRIPT_UNDER_TEST" 2>&1)" || STATUS_D=$?

assert_equal '1' "$STATUS_D" 'corrupted vendor copy exit code'
assert_contains "$OUTPUT_D" 'REFUSED' "the check's REFUSED finding is in the output"
assert_contains "$OUTPUT_D" 'CHANGED' "the check's CHANGED finding is in the output"
assert_contains "$OUTPUT_D" 'files/openrepotools/resume' 'the finding names the corrupted file'
assert_empty_dir "$BIN_D" 'nothing was installed into the bin dir'

printf '%s\n' '--- Scenario (e): WORKBENCHES_SKIP_ESTATE_COMMANDS=1 skips the step entirely ---'
BIN_E="$TMPDIR_ROOT/bin-e"
mkdir -p "$BIN_E"
STATUS_E=0
OUTPUT_E="$(WORKBENCHES_SKIP_ESTATE_COMMANDS=1 OPENREPOSHAPE_BIN_DIR="$BIN_E" OPENREPOTOOLS_BIN_DIR="$BIN_E" "$SCRIPT_UNDER_TEST" 2>&1)" || STATUS_E=$?

assert_equal '0' "$STATUS_E" 'skip-var run exit code'
assert_contains "$OUTPUT_E" 'skipped' 'skip-var run says skipped'
assert_empty_dir "$BIN_E" 'skip-var run installs nothing'

printf '%s\n' '--- Scenario (g) [D1]: a symlinked target refuses, the link target is untouched ---'
BIN_G="$TMPDIR_ROOT/bin-g"
OTHER_REPO_G="$TMPDIR_ROOT/other-repo-g"
mkdir -p "$BIN_G" "$OTHER_REPO_G"
printf '#!/bin/bash\necho other repo park, not workBenches'"'"'s\n' > "$OTHER_REPO_G/park"
chmod +x "$OTHER_REPO_G/park"
LINK_TARGET_BEFORE="$(cat "$OTHER_REPO_G/park")"
ln -s "$OTHER_REPO_G/park" "$BIN_G/park"
STATUS_G=0
OUTPUT_G="$(OPENREPOSHAPE_BIN_DIR="$BIN_G" OPENREPOTOOLS_BIN_DIR="$BIN_G" "$SCRIPT_UNDER_TEST" 2>&1)" || STATUS_G=$?

assert_equal '1' "$STATUS_G" 'symlinked park target exit code'
assert_contains "$OUTPUT_G" "$BIN_G/park" 'the refusal names the symlinked path'
assert_contains "$OUTPUT_G" 'symlink' 'the refusal says it is a symlink'
assert_equal "$LINK_TARGET_BEFORE" "$(cat "$OTHER_REPO_G/park")" 'the symlink target file is byte-for-byte unchanged'
assert_equal '1' "$(find "$BIN_G" -mindepth 1 | wc -l | tr -d ' ')" 'no other target was placed into the bin dir (only the pre-existing symlink remains)'

printf '%s\n' '--- Scenario (h) [D2]: a directory target refuses, nothing is placed ---'
BIN_H="$TMPDIR_ROOT/bin-h"
mkdir -p "$BIN_H/park"
STATUS_H=0
OUTPUT_H="$(OPENREPOSHAPE_BIN_DIR="$BIN_H" OPENREPOTOOLS_BIN_DIR="$BIN_H" "$SCRIPT_UNDER_TEST" 2>&1)" || STATUS_H=$?

assert_equal '1' "$STATUS_H" 'directory-target park exit code'
assert_contains "$OUTPUT_H" "$BIN_H/park" 'the refusal names the directory path'
assert_contains "$OUTPUT_H" 'not a regular file' 'the refusal says it is not a regular file'
assert_equal '0' "$(find "$BIN_H/park" -mindepth 1 | wc -l | tr -d ' ')" 'nothing was copied into the directory standing in for park'

printf '%s\n' '--- Scenario (i) [D4 regression guard]: a read-only pre-seeded park refuses before ANY placement ---'
BIN_I="$TMPDIR_ROOT/bin-i"
mkdir -p "$BIN_I"
cp "$PARK_VENDOR" "$BIN_I/park"
chmod 0444 "$BIN_I/park"
STATUS_I=0
OUTPUT_I="$(OPENREPOSHAPE_BIN_DIR="$BIN_I" OPENREPOTOOLS_BIN_DIR="$BIN_I" "$SCRIPT_UNDER_TEST" 2>&1)" || STATUS_I=$?

assert_equal '1' "$STATUS_I" 'read-only park exit code'
assert_contains "$OUTPUT_I" 'not writable' 'the refusal says park is not writable'
assert_equal '0' "$([ -e "$BIN_I/openRepoShape" ] && echo 1 || echo 0)" 'openRepoShape was NOT placed (D4 regression guard)'
assert_equal '0' "$([ -e "$BIN_I/openRepoTools" ] && echo 1 || echo 0)" 'openRepoTools was NOT placed (D4 regression guard)'
assert_equal '0' "$([ -e "$BIN_I/resume" ] && echo 1 || echo 0)" 'resume was NOT placed (D4 regression guard)'
chmod 0755 "$BIN_I/park"

printf '%s\n' '--- Scenario (j): a base-image copy with upstream-pin.yaml deleted refuses with exit 2 ---'
NOPIN_BASE="$TMPDIR_ROOT/nopin-base-image"
mkdir -p "$NOPIN_BASE"
cp -r "$BASE_IMAGE_DIR/." "$NOPIN_BASE/"
rm -f "$NOPIN_BASE/upstream-pin.yaml"
BIN_J="$TMPDIR_ROOT/bin-j"
mkdir -p "$BIN_J"
STATUS_J=0
OUTPUT_J="$(OPENREPOSHAPE_BIN_DIR="$BIN_J" OPENREPOTOOLS_BIN_DIR="$BIN_J" WORKBENCHES_BASE_IMAGE_DIR="$NOPIN_BASE" "$SCRIPT_UNDER_TEST" 2>&1)" || STATUS_J=$?

assert_equal '2' "$STATUS_J" 'missing pin file exit code'
assert_contains "$OUTPUT_J" 'missing' 'the refusal says the pin is missing'
assert_empty_dir "$BIN_J" 'missing-pin run installs nothing'

printf '%s\n' '--- Scenario (k) [D3]: resume'"'"'s row AND vendored file both removed the documented way ---'
# Hand-edit the copy directly (drop resume's three-line row, delete its
# file) rather than running `update-upstream.py apply --remove`, which
# needs `gh api` to prove the target commit is reachable from
# opensoft/openRepoTools' default branch -- network and auth this offline
# suite does not assume (and does not have in every CI job). The end state
# is the same one `apply --remove` documents producing: a row-and-file pair
# gone together, `check` none the wiser.
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
mkdir -p "$BIN_K"
STATUS_K=0
OUTPUT_K="$(OPENREPOSHAPE_BIN_DIR="$BIN_K" OPENREPOTOOLS_BIN_DIR="$BIN_K" WORKBENCHES_BASE_IMAGE_DIR="$NOROW_BASE" "$SCRIPT_UNDER_TEST" 2>&1)" || STATUS_K=$?

assert_equal '2' "$STATUS_K" 'row-and-file-removed resume exit code'
assert_contains "$OUTPUT_K" 'resume' 'the pre-flight refusal names resume'
assert_empty_dir "$BIN_K" 'nothing was installed for the row-and-file-removed copy'
assert_not_contains "$OUTPUT_K" 'fetch' 'the output contains no attempted-fetch line'
assert_not_contains "$OUTPUT_K" 'github' 'the output contains no github reference'

printf '%s\n' '--- Scenario (l): every placed file is mode 0755 ---'
assert_mode "$BIN_A/openRepoShape" '755' 'placed openRepoShape is mode 0755'
assert_mode "$BIN_A/openRepoTools" '755' 'placed openRepoTools is mode 0755'
assert_mode "$BIN_A/park" '755' 'placed park is mode 0755'
assert_mode "$BIN_A/resume" '755' 'placed resume is mode 0755'
assert_mode "$BIN_A/status" '755' 'placed status is mode 0755'

printf '%s\n' '--- Scenario (m): the operator'"'"'s own *_REF/*_REPO are overridden by the sentinel, not used ---'
# Dynamically: an operator's environment must not change the happy-path
# outcome (this would also be true without the fix, since neither shim
# fetches when every file is already present -- but it is still a real
# regression guard: it proves the override does not itself break anything).
BIN_M="$TMPDIR_ROOT/bin-m"
mkdir -p "$BIN_M"
STATUS_M=0
OUTPUT_M="$(OPENREPOSHAPE_REF='operator-branch' OPENREPOTOOLS_REF='operator-branch' \
    OPENREPOSHAPE_REPO='operator/fork' OPENREPOTOOLS_REPO='operator/fork' \
    OPENREPOSHAPE_BIN_DIR="$BIN_M" OPENREPOTOOLS_BIN_DIR="$BIN_M" \
    "$SCRIPT_UNDER_TEST" 2>&1)" || STATUS_M=$?
assert_equal '0' "$STATUS_M" 'an operator-set REF/REPO does not change the happy-path exit code'
assert_not_contains "$OUTPUT_M" 'operator-branch' "the operator's REF value never reaches the output"
assert_not_contains "$OUTPUT_M" 'operator/fork' "the operator's REPO value never reaches the output"
assert_identical "$BIN_M/resume" "$RESUME_VENDOR" 'resume is still placed correctly from the vendored copy, not fetched'
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

if (( failures == 0 )); then
    printf '%s\n' 'GREEN: setup-estate-commands regression test passed'
else
    printf 'RED: %d assertion(s) failed\n' "$failures"
    exit 1
fi
