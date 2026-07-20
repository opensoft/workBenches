#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/workbenches"

usage() {
  echo "Usage: setup-ai-profiles.sh [--interactive|--apply-existing]"
}

mode=interactive
while [[ $# -gt 0 ]]; do
  case "$1" in
    --interactive) mode=interactive; shift ;;
    --apply-existing) mode=existing; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ "$mode" == interactive ]]; then
  python3 "$repo_dir/scripts/onboard-ai-profiles.py"
fi

applied=false
if [[ -f "$config_dir/claude-profiles.json" ]]; then
  "$repo_dir/scripts/setup-claude-profiles.sh" --manifest "$config_dir/claude-profiles.json"
  applied=true
fi
if [[ -f "$config_dir/openai-profiles.json" ]]; then
  "$repo_dir/scripts/setup-codex-profiles.sh" --manifest "$config_dir/openai-profiles.json"
  applied=true
fi
for provider in gemini grok glm; do
  manifest="$config_dir/$provider-profiles.json"
  if [[ -f "$manifest" ]]; then
    "$repo_dir/scripts/setup-provider-profiles.sh" --provider "$provider" --manifest "$manifest"
    applied=true
  fi
done

if ls "$config_dir"/{claude,openai,gemini,grok,glm}-profiles.json >/dev/null 2>&1; then
  pi_profile_roots=(
    --profile-root "claude=${CLAUDE_PROFILES_HOME:-$HOME/.claude-profiles}/profiles"
    --profile-root "openai=${CODEX_PROFILES_HOME:-$HOME/.chatgpt-profiles}/profiles"
    --profile-root "gemini=${GEMINI_PROFILES_HOME:-$HOME/.gemini-profiles}/profiles"
    --profile-root "grok=${GROK_PROFILES_HOME:-$HOME/.grok-profiles}/profiles"
    --profile-root "glm=${GLM_PROFILES_HOME:-$HOME/.glm-profiles}/profiles"
  )
  python3 "$repo_dir/scripts/compose-pi-profiles.py" \
    --config-dir "$config_dir" \
    "${pi_profile_roots[@]}" \
    --output "$config_dir/pi-profiles.json"
fi
if [[ -f "$config_dir/pi-profiles.json" ]]; then
  "$repo_dir/scripts/setup-pi-profiles.sh" --manifest "$config_dir/pi-profiles.json"
  applied=true
fi

if [[ "$applied" == true ]]; then
  echo "AI profile setup complete. Provider credentials remain isolated and require their own login."
else
  echo "No AI profile manifests were created or applied."
fi
