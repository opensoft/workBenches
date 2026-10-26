#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
credential_tool="$repo_root/scripts/opencode-omniroute-credential"
restore_tool="$repo_root/scripts/restore-opencode-omniroute-from-kv.sh"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/omniroute-credential-test.XXXXXX")"
trap 'rm -rf -- "$test_root"' EXIT

export HOME="$test_root/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"
export WORKBENCHES_CREDENTIALS_HOME="$XDG_CONFIG_HOME/workbenches/credentials"
export WORKBENCHES_REGISTRY_ROOT="$XDG_DATA_HOME/workbenches/registries"
export FAKE_AZ_LOG="$test_root/az.log"
export FAKE_SECRET_FILE="$test_root/secret.json"
export FAKE_AZ_MODE=ok
mkdir -p "$HOME" "$test_root/bin" "$(dirname "$FAKE_SECRET_FILE")"

auth_file="$XDG_DATA_HOME/opencode/auth.json"
credential_file="$WORKBENCHES_CREDENTIALS_HOME/opencode/omniroute.json"

assert_secret_safe() {
    local output="$1"
    ! grep -Eq 'fixture-omniroute-key|replacement-omniroute-key|existing-omniroute-key|"key"' <<<"$output"
}

# Capture extracts exactly one provider record from mixed OpenCode auth.
mkdir -p "$(dirname "$auth_file")"
jq -n '{openai:{type:"oauth",access:"unrelated-openai"},omniroute:{type:"api",key:"fixture-omniroute-key"}}' >"$auth_file"
chmod 0600 "$auth_file"
output="$($credential_tool capture 2>&1)"
assert_secret_safe "$output"
jq -e 'keys == ["key","type"] and .type == "api" and .key == "fixture-omniroute-key"' "$credential_file" >/dev/null
[[ "$(stat -c '%a' "$credential_file")" == 600 ]]

# Install into an existing mixed-provider file without changing unrelated records.
jq -n '{openai:{type:"oauth",access:"unrelated-openai"},google:{type:"oauth",refresh:"unrelated-google"}}' >"$auth_file"
chmod 0600 "$auth_file"
before_openai="$(jq -cS '.openai' "$auth_file")"
before_google="$(jq -cS '.google' "$auth_file")"
output="$($credential_tool install 2>&1)"
assert_secret_safe "$output"
[[ "$before_openai" == "$(jq -cS '.openai' "$auth_file")" ]]
[[ "$before_google" == "$(jq -cS '.google' "$auth_file")" ]]
jq -e '.omniroute.type == "api" and .omniroute.key == "fixture-omniroute-key"' "$auth_file" >/dev/null

# Preserve an existing different OmniRoute record unless replacement is explicit.
jq '.omniroute.key = "existing-omniroute-key"' "$auth_file" >"$test_root/auth-replacement"
mv "$test_root/auth-replacement" "$auth_file"
chmod 0600 "$auth_file"
output="$($credential_tool install 2>&1)"
assert_secret_safe "$output"
jq -e '.omniroute.key == "existing-omniroute-key"' "$auth_file" >/dev/null
output="$($credential_tool install --force 2>&1)"
assert_secret_safe "$output"
jq -e '.omniroute.key == "fixture-omniroute-key" and .openai.access == "unrelated-openai"' "$auth_file" >/dev/null

# Fake Azure provides only the standalone OmniRoute provider record.
cat >"$test_root/bin/az" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$FAKE_AZ_LOG"
if [[ "$1 $2" == "account show" ]]; then
    [[ "${FAKE_AZ_MODE:-ok}" == wrong-tenant ]] && printf '%s\n' wrong-tenant || printf '%s\n' tenant-test
    exit 0
fi
if [[ "$1 $2" == "keyvault show" ]]; then
    printf '%s\n' /subscriptions/sub-test/resourceGroups/rg-test/providers/Microsoft.KeyVault/vaults/kv-test
    exit 0
fi
if [[ "$1 $2 $3" == "keyvault secret show" ]]; then
    jq -n '{
      id:"https://kv-test.vault.azure.net/secrets/ai-credential-omniroute-opencode/version1",
      contentType:"application/json; credential-format=omniroute",
      tags:{company:"opensoft",provider:"omniroute",profile:"opencode",managedBy:"workBenches"}
    }'
    exit 0
fi
if [[ "$1 $2 $3" == "keyvault secret download" ]]; then
    output=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --file) output="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    cp -- "$FAKE_SECRET_FILE" "$output"
    exit 0
fi
echo "unsupported fake az command" >&2
exit 2
EOF
chmod 0755 "$test_root/bin/az"
export PATH="$test_root/bin:$PATH"

registry="$WORKBENCHES_REGISTRY_ROOT/opensoft/Opensoft-Tenant"
mkdir -p "$registry/ai/vault"
cat >"$registry/ai/vault/azure-key-vault.json" <<'EOF'
{
  "schemaVersion": 1,
  "kind": "opensoft-ai-credential-vault",
  "owner": {"type":"tenant","id":"opensoft"},
  "tenantId": "tenant-test",
  "subscriptionId": "sub-test",
  "vaultName": "kv-test",
  "company": "opensoft",
  "entries": [{
    "provider": "omniroute",
    "registryProvider": "omniroute",
    "profile": "opencode",
    "credentialId": "opensoft.omniroute.opencode.credential",
    "secretName": "ai-credential-omniroute-opencode",
    "credentialPath": "~/.config/workbenches/credentials/opencode/omniroute.json",
    "enabled": true,
    "lifecycle": "active",
    "bootstrap": true
  }]
}
EOF
jq -n '{type:"api",key:"fixture-omniroute-key"}' >"$FAKE_SECRET_FILE"
chmod 0600 "$FAKE_SECRET_FILE"

rm -f -- "$credential_file" "$auth_file"
: >"$FAKE_AZ_LOG"
output="$($restore_tool 2>&1)"
assert_secret_safe "$output"
jq -e '.omniroute.type == "api" and .omniroute.key == "fixture-omniroute-key"' "$auth_file" >/dev/null
grep -q 'keyvault secret show' "$FAKE_AZ_LOG"
grep -q 'keyvault secret download' "$FAKE_AZ_LOG"

# Authority failure leaves authentication unchanged and returns fallback status.
rm -f -- "$credential_file" "$auth_file"
export FAKE_AZ_MODE=wrong-tenant
if output="$($restore_tool 2>&1)"; then
    echo "expected wrong-tenant bootstrap recovery to fail" >&2
    exit 1
fi
assert_secret_safe "$output"
[[ ! -e "$credential_file" && ! -e "$auth_file" ]]

# Canonical selection accepts only the canonical entry from a mixed manifest.
(
    export FAKE_AZ_MODE=ok
    export OPENBENCHES_CREDENTIALS_HOME="$XDG_CONFIG_HOME/openbenches/credentials"
    unset WORKBENCHES_CREDENTIALS_HOME WB_CREDENTIALS_HOME
    mkdir -p "$XDG_CONFIG_HOME/openbenches"
    canonical_credential_file="$OPENBENCHES_CREDENTIALS_HOME/opencode/omniroute.json"
    jq '.entries = [.entries[0], (.entries[0] | .credentialPath = "~/.config/openbenches/credentials/opencode/omniroute.json")]' \
        "$registry/ai/vault/azure-key-vault.json" >"$test_root/mixed-manifest.json"
    mv "$test_root/mixed-manifest.json" "$registry/ai/vault/azure-key-vault.json"
    rm -f -- "$credential_file" "$canonical_credential_file" "$auth_file"
    : >"$FAKE_AZ_LOG"
    output="$($restore_tool 2>&1)"
    assert_secret_safe "$output"
    jq -e '.type == "api" and .key == "fixture-omniroute-key"' "$canonical_credential_file" >/dev/null
    jq -e '.omniroute.type == "api" and .omniroute.key == "fixture-omniroute-key"' "$auth_file" >/dev/null
    [[ ! -e "$credential_file" ]]
    [[ "$(grep -c 'keyvault secret show' "$FAKE_AZ_LOG")" -eq 1 ]]
    [[ "$(grep -c 'keyvault secret download' "$FAKE_AZ_LOG")" -eq 1 ]]
)

# A legacy-only mapping is not authorized after selecting the canonical root.
(
    export FAKE_AZ_MODE=ok
    export OPENBENCHES_CREDENTIALS_HOME="$XDG_CONFIG_HOME/openbenches/credentials"
    unset WORKBENCHES_CREDENTIALS_HOME WB_CREDENTIALS_HOME
    canonical_credential_file="$OPENBENCHES_CREDENTIALS_HOME/opencode/omniroute.json"
    jq '.entries = [.entries[0]]' "$registry/ai/vault/azure-key-vault.json" >"$test_root/legacy-manifest.json"
    mv "$test_root/legacy-manifest.json" "$registry/ai/vault/azure-key-vault.json"
    rm -f -- "$credential_file" "$canonical_credential_file" "$auth_file"
    : >"$FAKE_AZ_LOG"
    if output="$($restore_tool 2>&1)"; then
        echo "expected legacy mapping to be refused in canonical-root mode" >&2
        exit 1
    fi
    assert_secret_safe "$output"
    [[ ! -e "$credential_file" && ! -e "$canonical_credential_file" && ! -e "$auth_file" ]]
    [[ ! -s "$FAKE_AZ_LOG" ]]
)

# Another path below the approved provider directory is still not the selected destination.
(
    export FAKE_AZ_MODE=ok
    export OPENBENCHES_CREDENTIALS_HOME="$XDG_CONFIG_HOME/openbenches/credentials"
    unset WORKBENCHES_CREDENTIALS_HOME WB_CREDENTIALS_HOME
    canonical_credential_file="$OPENBENCHES_CREDENTIALS_HOME/opencode/omniroute.json"
    unauthorized_credential_file="$OPENBENCHES_CREDENTIALS_HOME/opencode/other/omniroute.json"
    jq '.entries[0].credentialPath = "~/.config/openbenches/credentials/opencode/other/omniroute.json"' \
        "$registry/ai/vault/azure-key-vault.json" >"$test_root/unauthorized-manifest.json"
    mv "$test_root/unauthorized-manifest.json" "$registry/ai/vault/azure-key-vault.json"
    rm -f -- "$canonical_credential_file" "$auth_file"
    : >"$FAKE_AZ_LOG"
    if output="$($restore_tool 2>&1)"; then
        echo "expected unauthorized mapping to be refused" >&2
        exit 1
    fi
    assert_secret_safe "$output"
    [[ ! -e "$canonical_credential_file" && ! -e "$unauthorized_credential_file" && ! -e "$auth_file" ]]
    [[ ! -s "$FAKE_AZ_LOG" ]]
)

printf 'PASS: OpenCode OmniRoute standalone recovery contract\n'
