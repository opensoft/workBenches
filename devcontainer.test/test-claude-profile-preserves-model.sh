#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
launcher="$repo_root/base-image/files/claude-profile"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

profiles_home="$test_root/profiles-home"
profile_dir="$profiles_home/profiles/team"
manifest="$test_root/claude-profiles.json"
fake_claude="$test_root/claude"
mkdir -p "$profile_dir"

printf '%s\n' \
  '{"profiles":[{"name":"team","email":"team@example.invalid","family":"test","profilePath":"team"}]}' \
  > "$manifest"
printf '%s\n' '{"model":"custom-model","effortLevel":"high"}' > "$profile_dir/settings.json"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fake_claude"
chmod +x "$fake_claude"

run_status() {
  HOME="$test_root/home" \
  CLAUDE_PROFILES_HOME="$profiles_home" \
  CLAUDE_PROFILES_MANIFEST="$manifest" \
  CLAUDE_BIN="$fake_claude" \
  WORKBENCHES_SHARED_MCP_FAMILIES=none \
    "$launcher" status team >/dev/null
}

run_status
jq -e '.model == "custom-model" and .effortLevel == "high"' "$profile_dir/settings.json" >/dev/null

printf '%s\n' '{"effortLevel":"high"}' > "$profile_dir/settings.json"
run_status
jq -e '.model == "claude-fable-5-1" and .effortLevel == "high"' "$profile_dir/settings.json" >/dev/null

echo "PASS: Claude profile model preservation"
