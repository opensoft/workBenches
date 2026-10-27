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

selected="${WORKBENCHES_SELECTED_PROVIDERS:-}"
route="${WORKBENCHES_AUTH_ROUTE:-}"
source_pane_used=false
if [[ "$mode" == interactive && -t 0 && -t 1 && "${WORKBENCHES_PROFILE_SOURCE_FLOW:-}" != 1 ]]; then
  source_route="$(mktemp)"
  trap 'rm -f "$source_route"' EXIT
  python3 "$repo_dir/scripts/setup-profiles.py" --ai-onboarding "$source_route"
  source_pane_used=true
  source_choice="$(cat "$source_route")"
  rm -f "$source_route"
  trap - EXIT
  if [[ "$source_choice" == later ]]; then route=later; fi
fi
if [[ -n "$selected" && -t 0 && -t 1 && -z "$route" ]]; then
  route_file="$(mktemp)"
  trap 'rm -f "$route_file"' EXIT
  python3 "$repo_dir/scripts/setup-credential-recovery.py" --choose-route "$route_file"
  route="$(cat "$route_file")"
  if [[ -n "${WORKBENCHES_AUTH_ROUTE_FILE:-}" ]]; then printf '%s' "$route" > "$WORKBENCHES_AUTH_ROUTE_FILE"; fi
fi
if [[ -n "${WORKBENCHES_AUTH_ROUTE_FILE:-}" && -n "$route" ]]; then printf '%s' "$route" > "$WORKBENCHES_AUTH_ROUTE_FILE"; fi
if [[ "$route" == vault:* ]]; then
  export WORKBENCHES_VAULT_SERVICE="${route#vault:}"
  route=vault
fi
export WORKBENCHES_AUTH_ROUTE="$route"
if [[ "$mode" == interactive && "$source_pane_used" != true && "$route" != later && "$route" != existing && ( -z "$selected" || ",$selected," == *,openai,* || ",$selected," == *,claude,* || ",$selected," == *,pi,* ) ]]; then
  if [[ "$route" == vault ]]; then export WORKBENCHES_REQUIRE_PROFILE=1; fi
  python3 "$repo_dir/scripts/onboard-ai-profiles.py"
fi

applied=false
selected_provider() {
  [[ -z "$selected" || ",$selected," == *",$1,"* ]]
}
usable_manifest() {
  [[ -f "$1" ]] || return 1
  # Standalone runs retain legacy family-only scaffolding.
  [[ -z "$selected" ]] || jq -e '.profiles | length > 0' "$1" >/dev/null
}
if selected_provider claude && usable_manifest "$config_dir/claude-profiles.json"; then
  "$repo_dir/scripts/setup-claude-profiles.sh" --manifest "$config_dir/claude-profiles.json"
  applied=true
fi
if selected_provider openai && usable_manifest "$config_dir/openai-profiles.json"; then
  "$repo_dir/scripts/setup-codex-profiles.sh" --manifest "$config_dir/openai-profiles.json"
  applied=true
fi
for provider in gemini grok glm; do
  manifest="$config_dir/$provider-profiles.json"
  if selected_provider "$provider" && usable_manifest "$manifest"; then
    "$repo_dir/scripts/setup-provider-profiles.sh" --provider "$provider" --manifest "$manifest"
    applied=true
  fi
done

compose_pi=false
for provider in claude openai gemini grok glm; do
  if [[ -f "$config_dir/$provider-profiles.json" ]]; then
    compose_pi=true
    break
  fi
done
if selected_provider pi && [[ "$compose_pi" == true ]]; then
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
if selected_provider pi && usable_manifest "$config_dir/pi-profiles.json"; then
  "$repo_dir/scripts/setup-pi-profiles.sh" --manifest "$config_dir/pi-profiles.json"
  applied=true
fi

# Create every profile home before offering mapped recovery. Interactive setup
# lets users select their stores; unattended runs retain configured Azure recovery.
if [[ ( "$applied" == true || -n "$selected" ) && "$route" != later && "$route" != direct && "${WORKBENCHES_SKIP_CREDENTIAL_RECOVERY:-}" != 1 ]]; then
  recovery_mode=--apply-existing
  if [[ -t 0 && -t 1 ]]; then
    recovery_mode=--interactive
  fi
  if python3 "$repo_dir/scripts/setup-credential-recovery.py" "$recovery_mode"; then
    :
  else
    recovery_status=$?
    case "$recovery_status" in 130|143) exit "$recovery_status" ;; esac
    echo "Credential recovery was unavailable. Existing credentials are preserved; provider sign-in remains available."
  fi
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
