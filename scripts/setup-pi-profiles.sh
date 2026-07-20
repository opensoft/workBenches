#!/usr/bin/env bash
set -euo pipefail
umask 077

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/workbenches"
manifest="${PI_PROFILES_MANIFEST:-$config_dir/pi-profiles.json}"
base="${PI_PROFILES_HOME:-$HOME/.pi-profiles}"

usage() { echo "Usage: setup-pi-profiles.sh [--manifest PATH]"; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest) manifest="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "jq is required." >&2; exit 1; }
npm_command="$(command -v npm || true)"
[[ -x /usr/bin/npm ]] && npm_command=/usr/bin/npm
jq -e '.version == 1 and (.profiles | type == "array") and all(.profiles[]; (.name|length)>0 and (.email|length)>0 and (.family|length)>0 and ((.providers//[])|type=="array"))' "$manifest" >/dev/null

mkdir -p "$base/profiles" "$base/shared/skills" "$base/shared/prompts" "$base/shared/extensions" "$base/shared/themes"
chmod 700 "$base" "$base/profiles" "$base/shared"

link_path() {
  local target="$1" link="$2"
  if [[ -L "$link" || ! -e "$link" ]]; then ln -sfn "$target" "$link"; fi
}

while IFS=$'\t' read -r name email family aliases providers; do
  profile_dir="$base/profiles/$name"
  agent_dir="$profile_dir/agent"
  mkdir -p "$agent_dir"
  chmod 700 "$profile_dir" "$agent_dir"
  tmp="$(mktemp "$profile_dir/.profile.XXXXXX.tmp")"
  jq -n --arg name "$name" --arg email "$email" --arg family "$family" --argjson aliases "$aliases" --argjson providers "$providers" \
    '{name:$name,email:$email,family:$family,aliases:$aliases,providers:$providers}' > "$tmp"
  chmod 600 "$tmp"
  mv -f "$tmp" "$profile_dir/.profile.json"
  if [[ ! -e "$agent_dir/settings.json" ]]; then
    printf '%s\n' '{"enableInstallTelemetry":false}' > "$agent_dir/settings.json"
    chmod 600 "$agent_dir/settings.json"
  fi
  if [[ -n "$npm_command" ]]; then
    settings_tmp="$(mktemp "$agent_dir/.settings.XXXXXX.tmp")"
    jq --arg npm "$npm_command" '.npmCommand = [$npm]' "$agent_dir/settings.json" > "$settings_tmp"
    chmod 600 "$settings_tmp"
    mv -f "$settings_tmp" "$agent_dir/settings.json"
  fi
  if jq -e 'index("claude") != null' <<<"$providers" >/dev/null; then
    settings_tmp="$(mktemp "$agent_dir/.settings.XXXXXX.tmp")"
    jq '
      .packages = (((.packages // []) | map(select(. != "npm:pi-claude-cli" and . != "npm:@ramarivera/pi-claude-cli" and . != "npm:@ramarivera/pi-claude-cli@0.3.1"))) + ["npm:@ramarivera/pi-claude-cli@0.3.1"])
      | .defaultProvider = "pi-claude-cli"
      | .defaultModel = "claude-fable-5"
    ' "$agent_dir/settings.json" > "$settings_tmp"
    chmod 600 "$settings_tmp"
    mv -f "$settings_tmp" "$agent_dir/settings.json"
  fi
  for item in skills prompts extensions themes; do link_path "../../../shared/$item" "$agent_dir/$item"; done
  [[ -e "$base/shared/AGENTS.md" ]] && link_path "../../../shared/AGENTS.md" "$agent_dir/AGENTS.md"
done < <(jq -r '.profiles[] | [.name,.email,.family,((.aliases//[])|tojson),((.providers//[])|tojson)] | @tsv' "$manifest")

mkdir -p "$HOME/.local/bin"
if ! command -v pi >/dev/null 2>&1 && [[ -x "$HOME/.npm-global/bin/pi" ]]; then
  ln -sfn "$HOME/.npm-global/bin/pi" "$HOME/.local/bin/pi"
fi
ln -sfn "$repo_dir/scripts/pi-profile" "$HOME/.local/bin/pi-profile"
ln -sfn "$repo_dir/scripts/pi-profile" "$HOME/.local/bin/ppi"
echo "Pi profiles configured under $base"
echo "Run: ppi list"
echo "Then: ppi login PROFILE"
