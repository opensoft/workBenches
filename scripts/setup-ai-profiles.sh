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

# A private recovery mapping identifies the organization and its approved
# credential store. Create profile directories first, then recover missing
# credentials before tools offer their own interactive provider login.
recovery_manifest="${AI_CREDENTIAL_KV_MANIFEST:-$config_dir/ai-credential-keyvault.json}"
if [[ "$applied" == true && "${WORKBENCHES_SKIP_CREDENTIAL_RECOVERY:-}" != 1 && -f "$recovery_manifest" ]]; then
  echo "Recovering missing AI credentials from the configured organization vault..."
  if "$repo_dir/scripts/backup-ai-profile-credentials-to-kv.sh" restore \
      --manifest "$recovery_manifest" --azure-login; then
    :
  else
    recovery_status=$?
    case "$recovery_status" in 130|143) exit "$recovery_status" ;; esac
    echo "Credential recovery was unavailable. Existing credentials are preserved; provider sign-in remains available."
  fi
fi

compose_pi=false
for provider in claude openai gemini grok glm; do
  if [[ -f "$config_dir/$provider-profiles.json" ]]; then
    compose_pi=true
    break
  fi
done
if [[ "$compose_pi" == true ]]; then
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
  if [[ -x "$repo_dir/scripts/workbenches-mcp-sync" ]]; then
    {
      jq -r '.families[]?, .profiles[].family' "$config_dir/claude-profiles.json" 2>/dev/null || true
      jq -r '.families[]?, .profiles[].family' "$config_dir/openai-profiles.json" 2>/dev/null || true
    } | sort -u | while IFS= read -r family; do
      [[ -n "$family" ]] && "$repo_dir/scripts/workbenches-mcp-sync" ensure "$family"
    done
  fi
  echo "AI profile setup complete. Credentials remain isolated; profiles without recovered credentials can sign in separately."
else
  echo "No AI profile manifests were created or applied."
fi
