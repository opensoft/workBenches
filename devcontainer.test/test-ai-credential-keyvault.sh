#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
subject="$repo_root/scripts/backup-ai-profile-credentials-to-kv.sh"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/ai-credential-kv-test.XXXXXX")"
trap 'rm -rf -- "$test_root"' EXIT

export HOME="$test_root/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_STATE_HOME="$HOME/.local/state"
export CLAUDE_PROFILES_HOME="$HOME/.claude-profiles"
export FAKE_AZ_LOG="$test_root/az.log"
export FAKE_SECRET_FILE="$test_root/secret.json"
export FAKE_AZ_MODE=ok
mkdir -p "$HOME" "$test_root/bin" "$XDG_CONFIG_HOME/workbenches"

cat >"$test_root/bin/az" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$FAKE_AZ_LOG"

if [[ "$1 $2" == "account show" ]]; then
    if [[ "${FAKE_AZ_MODE:-ok}" == wrong-tenant ]]; then
        printf '%s\n' wrong-tenant
    else
        printf '%s\n' tenant-test
    fi
    exit 0
fi

if [[ "$1 $2" == "keyvault show" ]]; then
    printf '%s\n' /subscriptions/sub-test/resourceGroups/rg-test/providers/Microsoft.KeyVault/vaults/kv-test
    exit 0
fi

if [[ "$1 $2 $3" == "keyvault secret show" ]]; then
    company=opensoft
    provider=claude
    profile=team-001
    manager=workBenches
    content_type='application/json; credential-format=claude'
    case "${FAKE_AZ_MODE:-ok}" in
        bad-tags) profile=team-999 ;;
        bad-content-type) content_type='application/octet-stream' ;;
    esac
    jq -n \
      --arg id 'https://kv-test.vault.azure.net/secrets/ai-credential-claude-team-001/version1' \
      --arg contentType "$content_type" \
      --arg company "$company" \
      --arg provider "$provider" \
      --arg profile "$profile" \
      --arg managedBy "$manager" \
      '{id:$id,contentType:$contentType,tags:{company:$company,provider:$provider,profile:$profile,managedBy:$managedBy}}'
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

printf 'unsupported fake az command: %s\n' "$*" >&2
exit 2
EOF
chmod 0755 "$test_root/bin/az"
export PATH="$test_root/bin:$PATH"

target="$CLAUDE_PROFILES_HOME/profiles/opensoft/team/team-001/.credentials.json"
manifest="$XDG_CONFIG_HOME/workbenches/ai-credential-keyvault.json"
state="$XDG_STATE_HOME/workbenches/ai-credential-keyvault-backups.json"

write_manifest() {
    local credential_path="$1"
    jq -n \
      --arg credentialPath "$credential_path" \
      '{
        schemaVersion:1,
        tenantId:"tenant-test",
        subscriptionId:"sub-test",
        vaultName:"kv-test",
        company:"opensoft",
        entries:[{
          provider:"claude",
          profile:"team-001",
          credentialPath:$credentialPath,
          secretName:"ai-credential-claude-team-001",
          enabled:true
        }]
      }' >"$manifest"
    chmod 0600 "$manifest"
}

write_valid_secret() {
    jq -n '{claudeAiOauth:{accessToken:"fixture-access",refreshToken:"fixture-refresh",expiresAt:4102444800000}}' >"$FAKE_SECRET_FILE"
    chmod 0600 "$FAKE_SECRET_FILE"
}

assert_secret_safe() {
    local output="$1"
    ! grep -Eq 'fixture-access|fixture-refresh|accessToken|refreshToken' <<<"$output"
}

write_manifest "$target"
write_valid_secret

# Missing target: restore one exact version and record it.
output="$($subject restore --manifest "$manifest" --state "$state" --provider claude --profile team-001 2>&1)"
assert_secret_safe "$output"
cmp -s -- "$FAKE_SECRET_FILE" "$target"
[[ "$(stat -c '%a' "$target")" == 600 ]]
jq -e '.backups[] | select(.provider == "claude" and .profile == "team-001" and .status == "restored" and (.secretId | endswith("/version1")))' "$state" >/dev/null

# Existing target: preserve it and do not query secret metadata or download.
jq -n '{claudeAiOauth:{accessToken:"local-access",refreshToken:"local-refresh"}}' >"$target"
chmod 0600 "$target"
before="$(sha256sum "$target" | awk '{print $1}')"
: >"$FAKE_AZ_LOG"
output="$($subject restore --manifest "$manifest" --state "$state" --provider claude --profile team-001 2>&1)"
assert_secret_safe "$output"
grep -q '^KEEP' <<<"$output"
[[ "$before" == "$(sha256sum "$target" | awk '{print $1}')" ]]
! grep -q 'keyvault secret show' "$FAKE_AZ_LOG"
! grep -q 'keyvault secret download' "$FAKE_AZ_LOG"

# Explicit force: replace the existing valid target.
: >"$FAKE_AZ_LOG"
output="$($subject restore --force --manifest "$manifest" --state "$state" --provider claude --profile team-001 2>&1)"
assert_secret_safe "$output"
cmp -s -- "$FAKE_SECRET_FILE" "$target"

# Metadata mismatch: reject before download and leave no target.
rm -f -- "$target"
: >"$FAKE_AZ_LOG"
export FAKE_AZ_MODE=bad-tags
if output="$($subject restore --manifest "$manifest" --state "$state" --provider claude --profile team-001 2>&1)"; then
    echo 'expected bad-tag restore to fail' >&2
    exit 1
fi
assert_secret_safe "$output"
[[ ! -e "$target" ]]
! grep -q 'keyvault secret download' "$FAKE_AZ_LOG"

# Invalid downloaded payload: reject without materialization.
export FAKE_AZ_MODE=ok
printf '{"not":"a claude credential"}\n' >"$FAKE_SECRET_FILE"
: >"$FAKE_AZ_LOG"
if output="$($subject restore --manifest "$manifest" --state "$state" --provider claude --profile team-001 2>&1)"; then
    echo 'expected invalid-payload restore to fail' >&2
    exit 1
fi
assert_secret_safe "$output"
[[ ! -e "$target" ]]

# Unsafe target: reject before secret metadata retrieval.
write_valid_secret
write_manifest "$HOME/outside/.credentials.json"
: >"$FAKE_AZ_LOG"
if output="$($subject restore --manifest "$manifest" --state "$state" --provider claude --profile team-001 2>&1)"; then
    echo 'expected unsafe-target restore to fail' >&2
    exit 1
fi
assert_secret_safe "$output"
[[ ! -e "$HOME/outside/.credentials.json" ]]
! grep -q 'keyvault secret show' "$FAKE_AZ_LOG"

# Wrong tenant: fail before any secret query.
write_manifest "$target"
export FAKE_AZ_MODE=wrong-tenant
: >"$FAKE_AZ_LOG"
if output="$($subject restore --manifest "$manifest" --state "$state" --provider claude --profile team-001 2>&1)"; then
    echo 'expected wrong-tenant restore to fail' >&2
    exit 1
fi
assert_secret_safe "$output"
! grep -q 'keyvault secret show' "$FAKE_AZ_LOG"

printf 'PASS: AI credential Key Vault restore contract\n'
