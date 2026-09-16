#!/usr/bin/env bash
set -euo pipefail
umask 077

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
credential_tool="$repo_dir/scripts/opencode-omniroute-credential"
escrow_tool="$repo_dir/scripts/backup-ai-profile-credentials-to-kv.sh"
credentials_root="${WORKBENCHES_CREDENTIALS_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/workbenches/credentials}"
credential_file="${OMNIROUTE_CREDENTIAL_FILE:-$credentials_root/opencode/omniroute.json}"
registry_root="${WORKBENCHES_REGISTRY_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/workbenches/registries}"
temp_dir=""

cleanup() {
    [[ -z "$temp_dir" || ! -d "$temp_dir" ]] || rm -rf -- "$temp_dir"
}
trap cleanup EXIT

if "$credential_tool" status >/dev/null 2>&1; then
    echo "OpenCode OmniRoute credential is already configured."
    exit 0
fi

if [[ -f "$credential_file" ]]; then
    "$credential_tool" install
    exit 0
fi

command -v az >/dev/null 2>&1 || {
    echo "OmniRoute recovery unavailable: Azure CLI is not installed." >&2
    exit 1
}

candidates=()
if [[ -n "${AI_CREDENTIAL_KV_MANIFEST:-}" ]]; then
    candidates+=("$AI_CREDENTIAL_KV_MANIFEST")
fi
candidates+=("${XDG_CONFIG_HOME:-$HOME/.config}/workbenches/ai-credential-keyvault.json")
if [[ -n "${WORKBENCHES_OPENSOFT_REGISTRY:-}" ]]; then
    candidates+=("${WORKBENCHES_OPENSOFT_REGISTRY%/}/ai/vault/azure-key-vault.json")
fi
if [[ -d "$registry_root" ]]; then
    while IFS= read -r candidate; do
        candidates+=("$candidate")
    done < <(find "$registry_root" -maxdepth 5 -type f -path '*/ai/vault/azure-key-vault.json' -print 2>/dev/null | sort)
fi
if [[ -f "$HOME/projects/Opensoft-Tenant/ai/vault/azure-key-vault.json" ]]; then
    candidates+=("$HOME/projects/Opensoft-Tenant/ai/vault/azure-key-vault.json")
fi

manifest=""
for candidate in "${candidates[@]}"; do
    [[ -f "$candidate" && ! -L "$candidate" ]] || continue
    if jq -e '
      .owner == {type:"tenant",id:"opensoft"}
      and (.entries | any(
        .provider == "omniroute"
        and .profile == "opencode"
        and .enabled == true
        and .bootstrap == true
        and .credentialPath == "~/.config/workbenches/credentials/opencode/omniroute.json"
      ))
    ' "$candidate" >/dev/null 2>&1; then
        manifest="$candidate"
        break
    fi
done

[[ -n "$manifest" ]] || {
    echo "OmniRoute recovery unavailable: no authorized Key Vault mapping was found." >&2
    exit 1
}

temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/omniroute-restore.XXXXXX")"
chmod 0700 "$temp_dir"
private_manifest="$temp_dir/manifest.json"
jq '
  {
    schemaVersion,
    tenantId,
    subscriptionId,
    vaultName,
    company,
    entries: [.entries[] | select(
      .provider == "omniroute"
      and .profile == "opencode"
      and .enabled == true
      and .bootstrap == true
    )]
  }
' "$manifest" >"$private_manifest"
chmod 0600 "$private_manifest"

if ! "$escrow_tool" restore \
    --manifest "$private_manifest" \
    --provider omniroute \
    --profile opencode; then
    echo "OmniRoute recovery failed; interactive OpenCode authentication remains available." >&2
    exit 1
fi

"$credential_tool" install
