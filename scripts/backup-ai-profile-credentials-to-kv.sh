#!/usr/bin/env bash
set -euo pipefail
umask 077

MANIFEST="${AI_CREDENTIAL_KV_MANIFEST:-${XDG_CONFIG_HOME:-$HOME/.config}/workbenches/ai-credential-keyvault.json}"
STATE_FILE="${AI_CREDENTIAL_KV_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/workbenches/ai-credential-keyvault-backups.json}"
ACTION=""
PROVIDER_FILTER=""
PROFILE_FILTER=""
MAX_SECRET_BYTES=24576
TEMP_DIR=""

usage() {
    cat <<'EOF'
Usage:
  backup-ai-profile-credentials-to-kv.sh {audit|backup|verify} [options]

Options:
  --manifest PATH      Private manifest (default: ~/.config/workbenches/ai-credential-keyvault.json)
  --state PATH         Private version registry (default: ~/.local/state/workbenches/ai-credential-keyvault-backups.json)
  --provider NAME      Process only one provider
  --profile NAME       Process only one profile name
  -h, --help           Show this help

The command never prints credential values. "backup" creates a new Key Vault
secret version and verifies that exact version byte-for-byte.
EOF
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

cleanup() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf -- "$TEMP_DIR"
    fi
}
trap cleanup EXIT

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "$1 is required"
}

expand_home() {
    local path="$1"
    case "$path" in
        "~") printf '%s\n' "$HOME" ;;
        "~/"*) printf '%s/%s\n' "$HOME" "${path:2}" ;;
        /*) printf '%s\n' "$path" ;;
        *) return 1 ;;
    esac
}

owner_only_mode() {
    local path="$1"
    local mode
    mode="$(stat -c '%a' "$path")"
    (( (8#$mode & 077) == 0 ))
}

validate_manifest() {
    [[ -f "$MANIFEST" ]] || die "manifest not found: $MANIFEST"
    [[ ! -L "$MANIFEST" ]] || die "manifest must not be a symlink: $MANIFEST"
    [[ "$(stat -c '%u' "$MANIFEST")" == "$(id -u)" ]] || die "manifest is not owned by the current user"
    owner_only_mode "$MANIFEST" || die "manifest must not be readable or writable by group/other"
    jq -e '
      .schemaVersion == 1
      and (.tenantId | type == "string" and length > 0)
      and (.subscriptionId | type == "string" and length > 0)
      and (.vaultName | type == "string" and length > 0)
      and (.company | type == "string" and length > 0)
      and (.entries | type == "array")
    ' "$MANIFEST" >/dev/null || die "manifest schema is invalid"
    jq -e '
      [.entries[] | select(.enabled == true) | "\(.provider)/\(.profile)"] as $profiles
      | [.entries[] | select(.enabled == true) | .secretName] as $secrets
      | ($profiles | length) == ($profiles | unique | length)
        and (($secrets | length) == ($secrets | unique | length))
    ' "$MANIFEST" >/dev/null || die "enabled manifest entries must have unique provider/profile and secret names"
}

validate_credential_shape() {
    local provider="$1"
    local path="$2"
    case "$provider" in
        claude)
            jq -e '
              .claudeAiOauth | type == "object"
              and (.accessToken | type == "string" and length > 0)
              and (.refreshToken | type == "string" and length > 0)
            ' "$path" >/dev/null
            ;;
        codex)
            jq -e '
              (
                (.tokens | type == "object")
                and (.tokens.access_token | type == "string" and length > 0)
                and (.tokens.refresh_token | type == "string" and length > 0)
              )
              or
              (
                ((.personal_access_token // .OPENAI_API_KEY) | type == "string")
                and ((.personal_access_token // .OPENAI_API_KEY) | length > 0)
              )
            ' "$path" >/dev/null
            ;;
        pi)
            jq -e 'type == "object" and length > 0' "$path" >/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

validate_entry() {
    local provider="$1"
    local profile="$2"
    local path="$3"
    local secret_name="$4"
    local size

    [[ "$provider" =~ ^[a-z0-9-]+$ ]] || return 1
    [[ "$profile" =~ ^[a-z0-9-]+$ ]] || return 1
    [[ "$secret_name" =~ ^[a-zA-Z0-9-]{1,127}$ ]] || return 1
    [[ "$secret_name" == "ai-credential-$provider-$profile" ]] || return 1
    [[ -f "$path" && ! -L "$path" ]] || return 1
    [[ "$(stat -c '%u' "$path")" == "$(id -u)" ]] || return 1
    owner_only_mode "$path" || return 1
    size="$(stat -c '%s' "$path")"
    (( size > 0 && size <= MAX_SECRET_BYTES )) || return 1
    jq -e 'type == "object"' "$path" >/dev/null || return 1
    validate_credential_shape "$provider" "$path"
}

stable_snapshot() {
    local source="$1"
    local destination="$2"
    local before snapshot after

    before="$(sha256sum "$source" | awk '{print $1}')"
    cp -- "$source" "$destination"
    chmod 0600 "$destination"
    snapshot="$(sha256sum "$destination" | awk '{print $1}')"
    after="$(sha256sum "$source" | awk '{print $1}')"
    [[ "$before" == "$snapshot" && "$snapshot" == "$after" ]]
}

ensure_state_file() {
    local state_dir
    state_dir="$(dirname "$STATE_FILE")"
    mkdir -p "$state_dir"
    chmod 0700 "$state_dir"
    if [[ ! -f "$STATE_FILE" ]]; then
        printf '{"schemaVersion":1,"backups":[]}\n' >"$STATE_FILE"
        chmod 0600 "$STATE_FILE"
    fi
    [[ ! -L "$STATE_FILE" ]] || die "state file must not be a symlink: $STATE_FILE"
    [[ "$(stat -c '%u' "$STATE_FILE")" == "$(id -u)" ]] || die "state file is not owned by the current user"
    owner_only_mode "$STATE_FILE" || die "state file must not be readable or writable by group/other"
    jq -e '.schemaVersion == 1 and (.backups | type == "array")' "$STATE_FILE" >/dev/null ||
        die "state file schema is invalid"
}

record_backup() {
    local provider="$1"
    local profile="$2"
    local source="$3"
    local secret_id="$4"
    local backed_up_at="$5"
    local state_dir state_tmp

    ensure_state_file
    state_dir="$(dirname "$STATE_FILE")"
    state_tmp="$(mktemp "$state_dir/.ai-credential-state.XXXXXX")"
    jq \
      --arg provider "$provider" \
      --arg profile "$profile" \
      --arg source "$source" \
      --arg secretId "$secret_id" \
      --arg backedUpAt "$backed_up_at" \
      '
        .backups = (
          [.backups[] | select(.provider != $provider or .profile != $profile)]
          + [{
              provider: $provider,
              profile: $profile,
              source: $source,
              secretId: $secretId,
              backedUpAt: $backedUpAt,
              status: "verified"
            }]
          | sort_by(.provider, .profile)
        )
      ' "$STATE_FILE" >"$state_tmp"
    chmod 0600 "$state_tmp"
    mv -f -- "$state_tmp" "$STATE_FILE"
}

verify_azure_context() {
    local subscription_id="$1"
    local tenant_id="$2"
    local vault_name="$3"
    local actual_tenant

    actual_tenant="$(az account show --subscription "$subscription_id" --query tenantId -o tsv --only-show-errors)"
    [[ "$actual_tenant" == "$tenant_id" ]] ||
        die "subscription tenant does not match the manifest"
    az keyvault show \
      --subscription "$subscription_id" \
      --name "$vault_name" \
      --query id \
      -o tsv \
      --only-show-errors >/dev/null
}

backup_entry() {
    local subscription_id="$1"
    local vault_name="$2"
    local company="$3"
    local provider="$4"
    local profile="$5"
    local source="$6"
    local secret_name="$7"
    local snapshot download secret_id backed_up_at source_after

    snapshot="$TEMP_DIR/${provider}-${profile}.snapshot"
    download="$TEMP_DIR/${provider}-${profile}.download"

    stable_snapshot "$source" "$snapshot" ||
        { printf 'FAIL  %-8s %-16s source changed during snapshot\n' "$provider" "$profile" >&2; return 1; }

    secret_id="$(
      az keyvault secret set \
        --subscription "$subscription_id" \
        --vault-name "$vault_name" \
        --name "$secret_name" \
        --file "$snapshot" \
        --encoding utf-8 \
        --content-type "application/json; credential-format=$provider" \
        --tags \
          "company=$company" \
          "provider=$provider" \
          "profile=$profile" \
          "managedBy=workBenches" \
          "environment=prod" \
        --query id \
        -o tsv \
        --only-show-errors
    )"
    [[ -n "$secret_id" ]] || return 1
    [[ "$secret_id" =~ ^https://${vault_name}\.vault\.azure\.net/secrets/${secret_name}/[a-zA-Z0-9]+$ ]] ||
        { printf 'FAIL  %-8s %-16s Azure returned an unexpected secret version URI\n' "$provider" "$profile" >&2; return 1; }

    az keyvault secret download \
      --subscription "$subscription_id" \
      --id "$secret_id" \
      --file "$download" \
      --encoding utf-8 \
      --only-show-errors \
      -o none
    chmod 0600 "$download"
    cmp -s -- "$snapshot" "$download" ||
        { printf 'FAIL  %-8s %-16s downloaded version differs\n' "$provider" "$profile" >&2; return 1; }

    source_after="$(sha256sum "$source" | awk '{print $1}')"
    [[ "$source_after" == "$(sha256sum "$snapshot" | awk '{print $1}')" ]] ||
        { printf 'STALE %-8s %-16s source changed after upload: %s\n' "$provider" "$profile" "$secret_id" >&2; return 1; }

    backed_up_at="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    record_backup "$provider" "$profile" "$source" "$secret_id" "$backed_up_at"
    printf 'OK    %-8s %-16s %s\n' "$provider" "$profile" "$secret_id"
}

verify_entry() {
    local subscription_id="$1"
    local vault_name="$2"
    local provider="$3"
    local profile="$4"
    local source="$5"
    local secret_id download

    ensure_state_file
    secret_id="$(
      jq -r \
        --arg provider "$provider" \
        --arg profile "$profile" \
        '.backups[] | select(.provider == $provider and .profile == $profile) | .secretId' \
        "$STATE_FILE"
    )"
    [[ -n "$secret_id" ]] ||
        { printf 'MISS  %-8s %-16s no recorded version\n' "$provider" "$profile" >&2; return 1; }
    [[ "$secret_id" =~ ^https://${vault_name}\.vault\.azure\.net/secrets/ai-credential-${provider}-${profile}/[a-zA-Z0-9]+$ ]] ||
        { printf 'FAIL  %-8s %-16s recorded version URI is outside the configured secret\n' "$provider" "$profile" >&2; return 1; }
    download="$TEMP_DIR/${provider}-${profile}.verify"
    az keyvault secret download \
      --subscription "$subscription_id" \
      --id "$secret_id" \
      --file "$download" \
      --encoding utf-8 \
      --only-show-errors \
      -o none
    chmod 0600 "$download"
    cmp -s -- "$source" "$download" ||
        { printf 'STALE %-8s %-16s local source differs from recorded version\n' "$provider" "$profile" >&2; return 1; }
    printf 'OK    %-8s %-16s %s\n' "$provider" "$profile" "$secret_id"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        audit|backup|verify)
            [[ -z "$ACTION" ]] || die "only one action may be specified"
            ACTION="$1"
            shift
            ;;
        --manifest)
            [[ $# -ge 2 ]] || die "--manifest requires a path"
            MANIFEST="$2"
            shift 2
            ;;
        --state)
            [[ $# -ge 2 ]] || die "--state requires a path"
            STATE_FILE="$2"
            shift 2
            ;;
        --provider)
            [[ $# -ge 2 ]] || die "--provider requires a value"
            PROVIDER_FILTER="$2"
            shift 2
            ;;
        --profile)
            [[ $# -ge 2 ]] || die "--profile requires a value"
            PROFILE_FILTER="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "unknown argument: $1"
            ;;
    esac
done

[[ -n "$ACTION" ]] || { usage >&2; exit 2; }
require_command jq
require_command stat
require_command sha256sum
require_command cmp
validate_manifest

if [[ "$ACTION" == "backup" || "$ACTION" == "verify" ]]; then
    require_command az
fi

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ai-credential-kv.XXXXXX")"
chmod 0700 "$TEMP_DIR"

tenant_id="$(jq -r '.tenantId' "$MANIFEST")"
subscription_id="$(jq -r '.subscriptionId' "$MANIFEST")"
vault_name="$(jq -r '.vaultName' "$MANIFEST")"
company="$(jq -r '.company' "$MANIFEST")"

if [[ "$ACTION" == "backup" || "$ACTION" == "verify" ]]; then
    verify_azure_context "$subscription_id" "$tenant_id" "$vault_name"
fi

selected=0
passed=0
failed=0
while IFS=$'\t' read -r provider profile credential_path secret_name; do
    [[ -z "$PROVIDER_FILTER" || "$provider" == "$PROVIDER_FILTER" ]] || continue
    [[ -z "$PROFILE_FILTER" || "$profile" == "$PROFILE_FILTER" ]] || continue
    selected=$((selected + 1))

    source="$(expand_home "$credential_path" || true)"
    if [[ -z "$source" ]] || ! validate_entry "$provider" "$profile" "$source" "$secret_name"; then
        printf 'FAIL  %-8s %-16s invalid or missing canonical credential\n' "$provider" "$profile" >&2
        failed=$((failed + 1))
        continue
    fi

    case "$ACTION" in
        audit)
            printf 'OK    %-8s %-16s local credential is backup-ready\n' "$provider" "$profile"
            passed=$((passed + 1))
            ;;
        backup)
            if backup_entry "$subscription_id" "$vault_name" "$company" "$provider" "$profile" "$source" "$secret_name"; then
                passed=$((passed + 1))
            else
                failed=$((failed + 1))
            fi
            ;;
        verify)
            if verify_entry "$subscription_id" "$vault_name" "$provider" "$profile" "$source"; then
                passed=$((passed + 1))
            else
                failed=$((failed + 1))
            fi
            ;;
    esac
done < <(
    jq -r '
      .entries[]
      | select(.enabled == true)
      | [.provider, .profile, .credentialPath, .secretName]
      | @tsv
    ' "$MANIFEST"
)

(( selected > 0 )) || die "no manifest entries matched the filters"
printf 'Summary: selected=%d passed=%d failed=%d\n' "$selected" "$passed" "$failed"
(( failed == 0 ))
