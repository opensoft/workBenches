#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
helper="${1:-$repo_root/scripts/configure-wave-settings.sh}"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

bash -n "$helper" || fail "Wave settings helper has invalid shell syntax"

mkdir -p "$test_root/existing"
printf '%s\n' '{"custom":"keep","term:copyonselect":false}' > "$test_root/existing/settings.json"
chmod 0640 "$test_root/existing/settings.json"
"$helper" --waveterm-config "$test_root/existing" >/dev/null

python3 - "$test_root/existing/settings.json" <<'PY'
import json
import sys

settings = json.load(open(sys.argv[1], encoding="utf-8"))
assert settings["custom"] == "keep"
assert settings["app:disablectrlshiftdisplay"] is True
assert settings["term:copyonselect"] is False
PY

[[ "$(stat -c '%a' "$test_root/existing/settings.json")" == "640" ]] ||
    fail "existing settings mode was not preserved"

WAVETERM_CONFIG_DIR="$test_root/fresh" "$helper" >/dev/null
python3 - "$test_root/fresh/settings.json" <<'PY'
import json
import sys

settings = json.load(open(sys.argv[1], encoding="utf-8"))
assert settings == {
    "app:disablectrlshiftdisplay": True,
    "term:copyonselect": True,
}
PY

mkdir -p "$test_root/malformed"
printf '%s\n' '{not-json' > "$test_root/malformed/settings.json"
cp "$test_root/malformed/settings.json" "$test_root/malformed/settings.before"
if "$helper" --waveterm-config "$test_root/malformed" >/dev/null 2>&1; then
    fail "malformed JSON unexpectedly succeeded"
fi
cmp -s "$test_root/malformed/settings.before" "$test_root/malformed/settings.json" ||
    fail "malformed settings were modified"

mkdir -p "$test_root/empty"
: > "$test_root/empty/settings.json"
if "$helper" --waveterm-config "$test_root/empty" >/dev/null 2>&1; then
    fail "empty existing settings unexpectedly succeeded"
fi
[[ ! -s "$test_root/empty/settings.json" ]] || fail "empty settings were replaced"

mkdir -p "$test_root/symlink-target" "$test_root/symlink"
printf '%s\n' '{"custom":"target"}' > "$test_root/symlink-target/settings.json"
ln -s "$test_root/symlink-target/settings.json" "$test_root/symlink/settings.json"
if "$helper" --waveterm-config "$test_root/symlink" >/dev/null 2>&1; then
    fail "symlinked settings unexpectedly succeeded"
fi
[[ -L "$test_root/symlink/settings.json" ]] || fail "settings symlink was replaced"
grep -q '"custom":"target"' "$test_root/symlink-target/settings.json" ||
    fail "symlink target was modified"

if "$helper" --waveterm-config >/dev/null 2>&1; then
    fail "missing --waveterm-config operand unexpectedly succeeded"
fi

echo "PASS: Wave settings defaults are safe, atomic, and preserve existing values"
