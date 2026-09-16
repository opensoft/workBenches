#!/usr/bin/env bash
set -euo pipefail
umask 077

MANIFEST="${AI_CREDENTIAL_KV_MANIFEST:-${XDG_CONFIG_HOME:-$HOME/.config}/workbenches/ai-credential-keyvault.json}"
STATE_FILE="${AI_CREDENTIAL_KV_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/workbenches/ai-credential-keyvault-backups.json}"
ACTION=""
PROVIDER_FILTER=""
PROFILE_FILTER=""
FORCE=false
MAX_SECRET_BYTES=24576
TEMP_DIR=""

usage() {
    cat <<'EOF'
Usage:
  backup-ai-profile-credentials-to-kv.sh {audit|backup|verify|restore} [options]

Options:
  --manifest PATH      Private manifest (default: ~/.config/workbenches/ai-credential-keyvault.json)
  --state PATH         Private version registry (default: ~/.local/state/workbenches/ai-credential-keyvault-backups.json)
  --provider NAME      Process only one provider
  --profile NAME       Process only one profile name
  --force              Replace an existing credential during restore
  -h, --help           Show this help

The command never prints credential values. "backup" creates a new Key Vault
secret version and verifies that exact version byte-for-byte. "restore"
validates and downloads one exact secret version, preserves existing local
credentials by default, and installs an owner-only file atomically.
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
      and all(.entries[];
        (.provider | type == "string" and length > 0)
        and (.profile | type == "string" and length > 0)
        and (.credentialPath | type == "string" and length > 0)
        and (.secretName | type == "string" and length > 0)
        and (.enabled | type == "boolean")
      )
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
        omniroute)
            jq -e '
              type == "object"
              and (keys | sort) == ["key", "type"]
              and .type == "api"
              and (.key | type == "string" and length > 0)
            ' "$path" >/dev/null
            ;;
        *)
            return 1
            ;;
    esac
}

validate_credential_file() {
    local provider="$1"
    local path="$2"
    local size

    [[ -f "$path" && ! -L "$path" ]] || return 1
    size="$(stat -c '%s' "$path")"
    (( size > 0 && size <= MAX_SECRET_BYTES )) || return 1
    jq -e 'type == "object"' "$path" >/dev/null || return 1
    validate_credential_shape "$provider" "$path"
}

validate_entry_metadata() {
    local provider="$1"
    local profile="$2"
    local path="$3"
    local secret_name="$4"

    [[ "$provider" =~ ^[a-z0-9-]+$ ]] || return 1
    [[ "$profile" =~ ^[a-z0-9-]+$ ]] || return 1
    [[ "$secret_name" =~ ^[a-zA-Z0-9-]{1,127}$ ]] || return 1
    [[ "$secret_name" == "ai-credential-$provider-$profile" ]] || return 1
    [[ "$path" == /* ]] || return 1
}

validate_entry() {
    local provider="$1"
    local profile="$2"
    local path="$3"
    local secret_name="$4"

    validate_entry_metadata "$provider" "$profile" "$path" "$secret_name" || return 1
    [[ -f "$path" && ! -L "$path" ]] || return 1
    [[ "$(stat -c '%u' "$path")" == "$(id -u)" ]] || return 1
    owner_only_mode "$path" || return 1
    validate_credential_file "$provider" "$path"
}

approved_profile_root() {
    case "$1" in
        claude) printf '%s/profiles\n' "${CLAUDE_PROFILES_HOME:-$HOME/.claude-profiles}" ;;
        codex) printf '%s/profiles\n' "${CODEX_PROFILES_HOME:-${CHATGPT_PROFILES_HOME:-$HOME/.chatgpt-profiles}}" ;;
        pi) printf '%s/profiles\n' "${PI_PROFILES_HOME:-$HOME/.pi-profiles}" ;;
        omniroute) printf '%s/opencode\n' "${WORKBENCHES_CREDENTIALS_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/workbenches/credentials}" ;;
        *) return 1 ;;
    esac
}

validate_restore_target() {
    local provider="$1"
    local target="$2"
    local root root_real target_real expected_suffix current parent

    root="$(approved_profile_root "$provider" || true)"
    [[ -n "$root" ]] || return 1
    case "$provider" in
        claude) expected_suffix='/.credentials.json' ;;
        codex) expected_suffix='/auth.json' ;;
        pi) expected_suffix='/agent/auth.json' ;;
        omniroute) expected_suffix='/omniroute.json' ;;
        *) return 1 ;;
    esac
    [[ "$target" == *"$expected_suffix" ]] || return 1
    [[ ! -L "$root" && ! -L "$target" ]] || return 1

    root_real="$(realpath -m -- "$root")"
    target_real="$(realpath -m -- "$target")"
    [[ "$target_real" == "$root_real/"* ]] || return 1

    parent="$(dirname "$target")"
    current="$parent"
    while [[ "$current" == "$root" || "$current" == "$root/"* ]]; do
        [[ ! -L "$current" ]] || return 1
        [[ "$current" == "$root" ]] && break
        current="$(dirname "$current")"
    done
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

record_restore() {
    local provider="$1"
    local profile="$2"
    local target="$3"
    local secret_id="$4"
    local restored_at="$5"
    local state_dir state_tmp

    ensure_state_file
    state_dir="$(dirname "$STATE_FILE")"
    state_tmp="$(mktemp "$state_dir/.ai-credential-state.XXXXXX")"
    jq \
      --arg provider "$provider" \
      --arg profile "$profile" \
      --arg source "$target" \
      --arg secretId "$secret_id" \
      --arg restoredAt "$restored_at" \
      '
        ([.backups[] | select(.provider == $provider and .profile == $profile)][0] // {}) as $existing
        | .backups = (
            [.backups[] | select(.provider != $provider or .profile != $profile)]
            + [($existing + {
                provider: $provider,
                profile: $profile,
                source: $source,
                secretId: $secretId,
                restoredAt: $restoredAt,
                status: "restored"
              })]
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

restore_entry() {
    local subscription_id="$1"
    local vault_name="$2"
    local company="$3"
    local provider="$4"
    local profile="$5"
    local target="$6"
    local secret_name="$7"
    local metadata secret_id content_type tag_company tag_provider tag_profile tag_manager
    local download target_dir target_tmp restored_at

    validate_entry_metadata "$provider" "$profile" "$target" "$secret_name" ||
        { printf 'FAIL  %-8s %-16s invalid manifest entry\n' "$provider" "$profile" >&2; return 1; }
    validate_restore_target "$provider" "$target" ||
        { printf 'FAIL  %-8s %-16s unsafe credential target\n' "$provider" "$profile" >&2; return 1; }

    if [[ -e "$target" && "$FORCE" != true ]]; then
        printf 'KEEP  %-8s %-16s existing credential preserved\n' "$provider" "$profile"
        return 2
    fi
    [[ ! -e "$target" || ( -f "$target" && ! -L "$target" ) ]] ||
        { printf 'FAIL  %-8s %-16s existing target is not a regular file\n' "$provider" "$profile" >&2; return 1; }

    metadata="$TEMP_DIR/${provider}-${profile}.metadata.json"
    az keyvault secret show \
      --subscription "$subscription_id" \
      --vault-name "$vault_name" \
      --name "$secret_name" \
      --query '{id:id,contentType:contentType,tags:tags}' \
      -o json \
      --only-show-errors >"$metadata" || return 1

    secret_id="$(jq -r '.id // ""' "$metadata")"
    content_type="$(jq -r '.contentType // ""' "$metadata")"
    tag_company="$(jq -r '.tags.company // ""' "$metadata")"
    tag_provider="$(jq -r '.tags.provider // ""' "$metadata")"
    tag_profile="$(jq -r '.tags.profile // ""' "$metadata")"
    tag_manager="$(jq -r '.tags.managedBy // ""' "$metadata")"
    [[ "$secret_id" =~ ^https://${vault_name}\.vault\.azure\.net/secrets/${secret_name}/[a-zA-Z0-9]+$ ]] ||
        { printf 'FAIL  %-8s %-16s Azure returned an unexpected secret version URI\n' "$provider" "$profile" >&2; return 1; }
    [[ "$content_type" == "application/json; credential-format=$provider" ]] ||
        { printf 'FAIL  %-8s %-16s secret content type does not match provider\n' "$provider" "$profile" >&2; return 1; }
    [[ "$tag_company" == "$company" && "$tag_provider" == "$provider" && "$tag_profile" == "$profile" && "$tag_manager" == "workBenches" ]] ||
        { printf 'FAIL  %-8s %-16s secret tags do not match manifest entry\n' "$provider" "$profile" >&2; return 1; }

    download="$TEMP_DIR/${provider}-${profile}.restore"
    az keyvault secret download \
      --subscription "$subscription_id" \
      --id "$secret_id" \
      --file "$download" \
      --encoding utf-8 \
      --only-show-errors \
      -o none || return 1
    chmod 0600 "$download"
    validate_credential_file "$provider" "$download" ||
        { printf 'FAIL  %-8s %-16s downloaded credential has invalid format\n' "$provider" "$profile" >&2; return 1; }

    target_dir="$(dirname "$target")"
    mkdir -p -- "$target_dir"
    [[ ! -L "$target_dir" && "$(stat -c '%u' "$target_dir")" == "$(id -u)" ]] ||
        { printf 'FAIL  %-8s %-16s target directory is not owner-controlled\n' "$provider" "$profile" >&2; return 1; }
    chmod 0700 "$target_dir"
    target_tmp="$(mktemp "$target_dir/.credential.XXXXXX.tmp")"
    chmod 0600 "$target_tmp"
    cp -- "$download" "$target_tmp"
    mv -f -- "$target_tmp" "$target"
    restored_at="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    record_restore "$provider" "$profile" "$target" "$secret_id" "$restored_at" ||
        { printf 'FAIL  %-8s %-16s credential installed but version state could not be recorded\n' "$provider" "$profile" >&2; return 1; }
    printf 'OK    %-8s %-16s %s\n' "$provider" "$profile" "$secret_id"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        audit|backup|verify|restore)
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
        --force)
            FORCE=true
            shift
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
require_command realpath
validate_manifest

if [[ "$FORCE" == true && "$ACTION" != "restore" ]]; then
    die "--force is valid only with restore"
fi

if [[ "$ACTION" == "backup" || "$ACTION" == "verify" || "$ACTION" == "restore" ]]; then
    require_command az
fi

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ai-credential-kv.XXXXXX")"
chmod 0700 "$TEMP_DIR"

tenant_id="$(jq -r '.tenantId' "$MANIFEST")"
subscription_id="$(jq -r '.subscriptionId' "$MANIFEST")"
vault_name="$(jq -r '.vaultName' "$MANIFEST")"
company="$(jq -r '.company' "$MANIFEST")"

if [[ "$ACTION" == "backup" || "$ACTION" == "verify" || "$ACTION" == "restore" ]]; then
    verify_azure_context "$subscription_id" "$tenant_id" "$vault_name"
fi

selected=0
passed=0
preserved=0
failed=0
while IFS=$'\t' read -r provider profile credential_path secret_name; do
    [[ -z "$PROVIDER_FILTER" || "$provider" == "$PROVIDER_FILTER" ]] || continue
    [[ -z "$PROFILE_FILTER" || "$profile" == "$PROFILE_FILTER" ]] || continue
    selected=$((selected + 1))

    source="$(expand_home "$credential_path" || true)"
    if [[ -z "$source" ]] || ! validate_entry_metadata "$provider" "$profile" "$source" "$secret_name"; then
        printf 'FAIL  %-8s %-16s invalid manifest entry\n' "$provider" "$profile" >&2
        failed=$((failed + 1))
        continue
    fi
    if [[ "$ACTION" != "restore" ]] && ! validate_entry "$provider" "$profile" "$source" "$secret_name"; then
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
        restore)
            restore_status=0
            restore_entry "$subscription_id" "$vault_name" "$company" "$provider" "$profile" "$source" "$secret_name" || restore_status=$?
            case "$restore_status" in
                0) passed=$((passed + 1)) ;;
                2) preserved=$((preserved + 1)) ;;
                *) failed=$((failed + 1)) ;;
            esac
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
printf 'Summary: selected=%d passed=%d preserved=%d failed=%d\n' "$selected" "$passed" "$preserved" "$failed"
(( failed == 0 ))
