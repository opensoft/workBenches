#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
helper="$repo_root/scripts/configure-wave-settings.sh"
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

echo "PASS: Wave settings defaults are safe, atomic, and preserve existing values"
