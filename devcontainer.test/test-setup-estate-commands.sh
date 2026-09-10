#!/usr/bin/env bash
# Regression test for scripts/setup-estate-commands.sh (opensoft/workBenches#37):
# the host's openRepoShape, openRepoTools, park and resume come from
# workBenches' own vendored pin, and the script places them, re-places them
# when they differ from the pin (either direction), and refuses to place
# anything when the vendored copies themselves no longer match the pin.

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

printf '%s\n' '--- Scenario (a): fresh bin dir installs all four commands from the vendored copies ---'
BIN_A="$TMPDIR_ROOT/bin-a"
mkdir -p "$BIN_A"
STATUS_A=0
OUTPUT_A="$(OPENREPOSHAPE_BIN_DIR="$BIN_A" OPENREPOTOOLS_BIN_DIR="$BIN_A" "$SCRIPT_UNDER_TEST" 2>&1)" || STATUS_A=$?

assert_equal '0' "$STATUS_A" 'fresh install exit code'
assert_file_executable "$BIN_A/openRepoShape" 'fresh install places openRepoShape, executable'
assert_file_executable "$BIN_A/openRepoTools" 'fresh install places openRepoTools, executable'
assert_file_executable "$BIN_A/park" 'fresh install places park, executable'
assert_file_executable "$BIN_A/resume" 'fresh install places resume, executable'
assert_identical "$BIN_A/openRepoShape" "$SHAPE_VENDOR" 'fresh openRepoShape is byte-identical to the vendored copy'
assert_identical "$BIN_A/openRepoTools" "$TOOLS_VENDOR" 'fresh openRepoTools is byte-identical to the vendored copy'
assert_identical "$BIN_A/park" "$PARK_VENDOR" 'fresh park is byte-identical to the vendored copy'
assert_identical "$BIN_A/resume" "$RESUME_VENDOR" 'fresh resume is byte-identical to the vendored copy'
assert_contains "$OUTPUT_A" "openRepoShape pinned at $SHAPE_COMMIT" 'fresh install prints the openRepoShape pin commit'
assert_contains "$OUTPUT_A" "openRepoTools pinned at $TOOLS_COMMIT" 'fresh install prints the openRepoTools pin commit'
assert_contains "$OUTPUT_A" 'openRepoShape: installed at' 'fresh install reports an installed verb for openRepoShape'
assert_contains "$OUTPUT_A" 'openRepoTools: installed at' 'fresh install reports an installed verb for openRepoTools'
assert_contains "$OUTPUT_A" 'park: installed at' 'fresh install reports an installed verb for park'
assert_contains "$OUTPUT_A" 'resume: installed at' 'fresh install reports an installed verb for resume'
# Scenario (f) folded in here: a brand-new temp dir is never on $PATH.
assert_contains "$OUTPUT_A" "$BIN_A is not on \$PATH" 'fresh install warns that the bin dir is not on PATH, naming it'

printf '%s\n' '--- Scenario (b): a second run over an already-installed bin dir reports unchanged ---'
STATUS_B=0
OUTPUT_B="$(OPENREPOSHAPE_BIN_DIR="$BIN_A" OPENREPOTOOLS_BIN_DIR="$BIN_A" "$SCRIPT_UNDER_TEST" 2>&1)" || STATUS_B=$?

assert_equal '0' "$STATUS_B" 'second run exit code'
assert_contains "$OUTPUT_B" 'openRepoShape: already installed at' 'second run reports openRepoShape unchanged'
assert_contains "$OUTPUT_B" 'openRepoTools: already installed at' 'second run reports openRepoTools unchanged'
assert_contains "$OUTPUT_B" 'park: already installed at' 'second run reports park unchanged'
assert_contains "$OUTPUT_B" 'resume: already installed at' 'second run reports resume unchanged'
assert_identical "$BIN_A/openRepoShape" "$SHAPE_VENDOR" 'openRepoShape still byte-identical after the second run'
assert_identical "$BIN_A/openRepoTools" "$TOOLS_VENDOR" 'openRepoTools still byte-identical after the second run'
assert_identical "$BIN_A/park" "$PARK_VENDOR" 'park still byte-identical after the second run'
assert_identical "$BIN_A/resume" "$RESUME_VENDOR" 'resume still byte-identical after the second run'

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

if (( failures == 0 )); then
    printf '%s\n' 'GREEN: setup-estate-commands regression test passed'
else
    printf 'RED: %d assertion(s) failed\n' "$failures"
    exit 1
fi
