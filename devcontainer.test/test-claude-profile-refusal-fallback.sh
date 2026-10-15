#!/usr/bin/env bash
#
# claude-profile seeds CLAUDE_CODE_DISABLE_REFUSAL_FALLBACK=1 into every
# profile's settings.json `env` (Brett Heap, 2026-10-13: "we do not want the
# fallback to 4.8" and "ok lets add the env var to claude-profile and update
# pr 54"). The settings `env` entry is what reaches a subagent, which the
# `switchModelsOnFlag` setting never does. This suite pins the seeding in
# configure_profile_runtime: a fresh file carries the entry, a file that
# already has `env` keeps every other entry, an explicit value (so "0" opts a
# profile out) is never overwritten, and effortLevel / model keep their
# existing behaviour. Host-run and hermetic: HOME, CLAUDE_PROFILES_HOME and the
# profile manifest are redirected into a private sandbox, and the Claude binary
# is a stub that exits 0.

set -euo pipefail

# Count successful explicit assertions, including repeated fixture checks.
assertions=0
assertion() { assertions=$((assertions + 1)); }

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
launcher="$repo_root/base-image/files/claude-profile"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

key=CLAUDE_CODE_DISABLE_REFUSAL_FALLBACK

profiles_home="$test_root/profiles-home"
profile_dir="$profiles_home/profiles/team"
settings="$profile_dir/settings.json"
manifest="$test_root/claude-profiles.json"
fake_claude="$test_root/claude"
mkdir -p "$profile_dir"

printf '%s\n' \
  '{"profiles":[{"name":"team","email":"team@example.invalid","family":"test","profilePath":"team"}]}' \
  > "$manifest"
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

# expect DESCRIPTION JQ-FILTER FILE: the filter must be true for the file.
expect() {
  local description="$1" filter="$2" file="$3"
  if ! jq -e "$filter" "$file" >/dev/null; then
    echo "FAIL: $description" >&2
    echo "  filter: $filter" >&2
    echo "  file:   $file" >&2
    jq . "$file" >&2 || cat "$file" >&2
    exit 1
  fi
  assertion
}

# 1. A profile with no settings.json at all gets the entry from the new-file
#    program, beside the defaults that program has always written.
rm -f "$settings"
run_status
expect "fresh settings.json carries the variable as the string \"1\"" \
  ".env.$key == \"1\"" "$settings"
expect "fresh settings.json env holds only the variable" \
  ".env == {\"$key\": \"1\"}" "$settings"
expect "fresh settings.json keeps the xhigh effort default" \
  '.effortLevel == "xhigh"' "$settings"
expect "fresh settings.json keeps the default model" \
  '.model == "claude-fable-5-1"' "$settings"
expect "fresh settings.json keeps bypassPermissions" \
  '.permissions.defaultMode == "bypassPermissions"' "$settings"

# 2. Re-running over the file the launcher just wrote changes nothing.
cp "$settings" "$test_root/settings.first"
run_status
cmp -s "$test_root/settings.first" "$settings"
assertion
expect "a second launch still carries the variable" \
  ".env.$key == \"1\"" "$settings"

# 3. An existing file with no `env` key gains it, and the effort / model
#    already chosen in the file still win.
printf '%s\n' '{"model":"custom-model","effortLevel":"high"}' > "$settings"
run_status
expect "settings without env gain the variable" \
  ".env.$key == \"1\"" "$settings"
expect "an explicit model survives the env seeding" \
  '.model == "custom-model"' "$settings"
expect "an explicit effortLevel survives the env seeding" \
  '.effortLevel == "high"' "$settings"

# 4. An existing `env` keeps every entry it had and gains the variable.
printf '%s\n' '{"env":{"OTHER":"x"}}' > "$settings"
run_status
expect "an existing env entry is kept" '.env.OTHER == "x"' "$settings"
expect "an existing env gains the variable" ".env.$key == \"1\"" "$settings"
expect "an existing env holds exactly its own entry plus the variable" \
  ".env == {\"OTHER\": \"x\", \"$key\": \"1\"}" "$settings"
expect "effortLevel and model still default when absent from a file with env" \
  '.effortLevel == "xhigh" and .model == "claude-fable-5-1"' "$settings"

# 5. A live profile already carries other env entries; they all survive.
printf '%s\n' \
  '{"env":{"CLAUDE_AUTOCOMPACT_PCT_OVERRIDE":"70","OTHER":"x"},"model":"custom-model"}' \
  > "$settings"
run_status
expect "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE survives" \
  '.env.CLAUDE_AUTOCOMPACT_PCT_OVERRIDE == "70"' "$settings"
expect "a second unrelated env entry survives" '.env.OTHER == "x"' "$settings"
expect "the variable is added beside them" ".env.$key == \"1\"" "$settings"
expect "the explicit model survives" '.model == "custom-model"' "$settings"

# 6. An explicit "0" is the opt-out and must be left exactly as it is.
printf '%s\n' "{\"env\":{\"$key\":\"0\",\"OTHER\":\"x\"}}" > "$settings"
run_status
expect "an explicit \"0\" is preserved (the profile's opt-out)" \
  ".env.$key == \"0\"" "$settings"
expect "the entries beside an explicit \"0\" survive" \
  '.env.OTHER == "x"' "$settings"
run_status
expect "an explicit \"0\" is still preserved on the next launch" \
  ".env.$key == \"0\"" "$settings"

# 7. An explicit "1" stays "1".
printf '%s\n' "{\"env\":{\"$key\":\"1\"}}" > "$settings"
run_status
expect "an explicit \"1\" stays" ".env.$key == \"1\"" "$settings"

# 8. The rest of the file the launcher maintains is unchanged by the seeding.
printf '%s\n' '{"env":{"OTHER":"x"}}' > "$settings"
run_status
expect "statusLine is still maintained" \
  '.statusLine.type == "command" and .statusLine.refreshInterval == 10' "$settings"
expect "the file is still one JSON object" 'type == "object"' "$settings"

# 9. setup-claude-profiles.sh writes a profile's effortLevel / model before any
#    launch; the launcher is what puts `env` in, on that profile's first
#    launch, so a profile set up and then launched ends up with the variable
#    and keeps whatever env it already had.
setup_home="$test_root/setup-home"
setup_config="$test_root/setup-config"
setup_profiles="$test_root/setup-profiles"
setup_manifest="$test_root/setup-claude-profiles.json"
setup_profile="$setup_profiles/profiles/test/fresh"
mkdir -p "$setup_home"
printf '%s\n' \
  '{"version":1,"profiles":[{"name":"fresh","email":"fresh@example.invalid","family":"test","profilePath":"test/fresh"}]}' \
  > "$setup_manifest"

HOME="$setup_home" \
XDG_CONFIG_HOME="$setup_config" \
CLAUDE_PROFILES_HOME="$setup_profiles" \
CLAUDE_PROFILES_MANIFEST="$setup_manifest" \
  "$repo_root/scripts/setup-claude-profiles.sh" --manifest "$setup_manifest" >/dev/null
expect "setup leaves a profile settings file with the default model" \
  '.model == "claude-fable-5-1"' "$setup_profile/settings.json"

jq '.env = {"OTHER": "x"}' "$setup_profile/settings.json" > "$test_root/setup-settings.tmp"
mv "$test_root/setup-settings.tmp" "$setup_profile/settings.json"
HOME="$setup_home" \
XDG_CONFIG_HOME="$setup_config" \
CLAUDE_PROFILES_HOME="$setup_profiles" \
CLAUDE_PROFILES_MANIFEST="$setup_manifest" \
CLAUDE_BIN="$fake_claude" \
WORKBENCHES_SHARED_MCP_FAMILIES=none \
  "$launcher" status fresh >/dev/null
expect "a profile that setup wrote gets the variable on its first launch" \
  ".env.$key == \"1\"" "$setup_profile/settings.json"
expect "its other env entry survives that launch" \
  '.env.OTHER == "x"' "$setup_profile/settings.json"
expect "setup's model and effort survive that launch" \
  '.model == "claude-fable-5-1" and .effortLevel == "xhigh"' "$setup_profile/settings.json"

echo "PASS: Claude profile refusal-fallback env seeding"
printf "COUNT: %s assertions passed\n" "$assertions"
