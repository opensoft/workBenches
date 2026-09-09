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

setup_home="$test_root/setup-home"
setup_config="$test_root/setup-config"
setup_profiles="$test_root/setup-profiles"
setup_manifest="$test_root/setup-claude-profiles.json"
preserved_profile="$setup_profiles/profiles/test/preserved"
fresh_profile="$setup_profiles/profiles/test/fresh"
retained_profile="$setup_profiles/profiles/legacy/retained"
mkdir -p "$setup_home" "$preserved_profile" "$retained_profile"
printf '%s\n' '{"model":"custom-model","effortLevel":"high"}' > "$preserved_profile/settings.json"
printf '%s\n' '{"model":"retained-model"}' > "$retained_profile/settings.json"
printf '%s\n' \
  '{"version":1,"profiles":[{"name":"preserved","email":"preserved@example.invalid","family":"test","profilePath":"test/preserved"},{"name":"fresh","email":"fresh@example.invalid","family":"test","profilePath":"test/fresh"}]}' \
  > "$setup_manifest"

run_setup() {
  HOME="$setup_home" \
  XDG_CONFIG_HOME="$setup_config" \
  CLAUDE_PROFILES_HOME="$setup_profiles" \
  CLAUDE_PROFILES_MANIFEST="$setup_manifest" \
    "$repo_root/scripts/setup-claude-profiles.sh" --manifest "$setup_manifest" >/dev/null
}

run_setup
jq -e '.model == "custom-model" and .effortLevel == "high"' "$preserved_profile/settings.json" >/dev/null
jq -e '.model == "claude-fable-5-1"' "$fresh_profile/settings.json" >/dev/null
jq -e '.model == "retained-model"' "$retained_profile/settings.json" >/dev/null

printf '%s\n' '{"effortLevel":"high"}' > "$preserved_profile/settings.json"
run_setup
jq -e '.model == "claude-fable-5-1" and .effortLevel == "high"' "$preserved_profile/settings.json" >/dev/null

echo "PASS: Claude profile model preservation"
