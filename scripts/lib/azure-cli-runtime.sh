#!/usr/bin/env bash
# Azure CLI transport for credential escrow. The caller owns and removes the
# private work directory, including the temporary container login cache.
source "$(dirname "${BASH_SOURCE[0]}")/openbenches-compat.sh"

azure_cli_runtime_init() {
    local work_dir="$1" allow_login="$2" container_tools azure_runtime
    container_tools="$(openbenches_resolve_env CONTAINER_TOOLS)"
    azure_runtime="$(openbenches_resolve_env --sensitive AZURE_CLI_RUNTIME auto)" || return "$?"
    AZURE_CLI_IMAGE="$(openbenches_resolve_env --sensitive AZURE_CLI_IMAGE mcr.microsoft.com/azure-cli:2.91.0-azurelinux3.0)" || return "$?"
    AZURE_CLI_WORK_DIR="$(realpath -- "$work_dir")"
    if [[ "$container_tools" == 1 || "$azure_runtime" == vault ]]; then
        declare -F workbenches_vault_start >/dev/null || source "$(dirname "${BASH_SOURCE[0]}")/tools-container.sh"
        workbenches_vault_start || return "$?"
        AZURE_CLI_MODE=vault
        AZURE_VAULT_SESSION="$(workbenches_runtime_docker exec "$WORKBENCHES_VAULT_CONTAINER" mktemp -d /tmp/workbenches-azure.XXXXXXXX)" || return 1
        workbenches_runtime_docker exec "$WORKBENCHES_VAULT_CONTAINER" mkdir -p "$AZURE_VAULT_SESSION/config" "$AZURE_VAULT_SESSION/home" || return 1
        return 0
    fi
    AZURE_CLI_BIN="$(type -P az || true)"
    AZURE_CLI_MODE=host
    if [[ -n "$AZURE_CLI_BIN" && "$azure_runtime" != docker ]]; then
        return 0
    fi

    AZURE_CLI_BIN="$(openbenches_data_root)/tools/azure-cli/bin/az"
    if [[ -x "$AZURE_CLI_BIN" && "$azure_runtime" != docker ]]; then
        return 0
    fi

    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        AZURE_CLI_MODE=docker
        mkdir -m 0700 "$AZURE_CLI_WORK_DIR/azure-config" "$AZURE_CLI_WORK_DIR/azure-home"
        printf 'Azure CLI will run in a temporary Docker container.\n' >&2
        return 0
    fi

    if [[ "$azure_runtime" == docker ]]; then
        printf 'Docker was selected for credential recovery but its daemon is unavailable.\n' >&2
        return 1
    fi
    if [[ "$allow_login" == true && -t 0 && -t 2 ]]; then
        local answer
        printf 'Azure CLI is missing and Docker is unavailable. Install Azure CLI for your user account? [y/N] (Q to cancel): ' >&2
        IFS= read -r answer || return 130
        [[ "${answer,,}" != q ]] || return 130
        if [[ "$answer" == [Yy] || "$answer" == [Yy][Ee][Ss] ]]; then
            local installer_dir
            installer_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
            bash "$installer_dir/setup-azure-cli.sh" >&2 || return $?
            [[ -x "$AZURE_CLI_BIN" ]] && return 0
        fi
    fi
    printf 'Azure recovery needs Azure CLI or a working Docker daemon. Run scripts/setup-azure-cli.sh to install the CLI for your user account.\n' >&2
    return 1
}

azure_cli_runtime_cleanup() {
    if [[ "${AZURE_CLI_MODE:-}" == vault && "${AZURE_VAULT_SESSION:-}" == /tmp/workbenches-azure.* ]]; then
        workbenches_runtime_docker exec "$WORKBENCHES_VAULT_CONTAINER" rm -rf -- "$AZURE_VAULT_SESSION" >/dev/null 2>&1 || true
    fi
}

run_azure_cli() {
    if [[ "$AZURE_CLI_MODE" == vault ]]; then
        local argument next_file=false source_file='' vault_file='' download=false result
        local -a arguments=()
        [[ "$*" != 'keyvault secret download '* ]] || download=true
        for argument in "$@"; do
            if [[ "$next_file" == true ]]; then
                # Only explicitly requested payload files cross the boundary.
                source_file=$argument
                case "$source_file" in "$AZURE_CLI_WORK_DIR/"*) ;; *) echo 'Azure payload must be inside the private recovery directory.' >&2; return 1 ;; esac
                vault_file="$AZURE_VAULT_SESSION/payload"
                if [[ "$download" != true ]]; then
                    workbenches_runtime_docker exec --interactive "$WORKBENCHES_VAULT_CONTAINER" sh -c 'umask 077; cat > "$1"' sh "$vault_file" < "$source_file" || return 1
                else
                    workbenches_runtime_docker exec "$WORKBENCHES_VAULT_CONTAINER" rm -f "$vault_file" || return 1
                fi
                arguments+=("$vault_file"); next_file=false
            else
                arguments+=("$argument")
                [[ "$argument" != --file ]] || next_file=true
            fi
        done
        workbenches_runtime_docker exec --env "HOME=$AZURE_VAULT_SESSION/home" --env "AZURE_CONFIG_DIR=$AZURE_VAULT_SESSION/config" \
            "$WORKBENCHES_VAULT_CONTAINER" az "${arguments[@]}"
        result=$?
        if [[ "$result" == 0 && "$download" == true && -n "$source_file" ]]; then
            # Stream only the requested payload; Docker archive reads omit tmpfs.
            (umask 077; workbenches_runtime_docker exec "$WORKBENCHES_VAULT_CONTAINER" cat "$vault_file" > "$source_file") || return 1
            chmod 600 "$source_file" || return 1
        fi
        [[ -z "$vault_file" ]] || workbenches_runtime_docker exec "$WORKBENCHES_VAULT_CONTAINER" rm -f "$vault_file" >/dev/null
        return "$result"
    fi
    if [[ "$AZURE_CLI_MODE" == host ]]; then
        "$AZURE_CLI_BIN" "$@"
        return
    fi

    # Keep paths identical so --file can refer to a private snapshot/download.
    # Do not expose the host home, existing Azure sessions, or Docker socket.
    docker run --rm \
        --user "$(id -u):$(id -g)" \
        --cap-drop ALL --security-opt no-new-privileges \
        --mount "type=bind,src=$AZURE_CLI_WORK_DIR,dst=$AZURE_CLI_WORK_DIR" \
        --env "HOME=$AZURE_CLI_WORK_DIR/azure-home" \
        --env "AZURE_CONFIG_DIR=$AZURE_CLI_WORK_DIR/azure-config" \
        --env AZURE_CORE_COLLECT_TELEMETRY=false \
        --env AZURE_CORE_LOGIN_EXPERIENCE_V2=off \
        --entrypoint az "$AZURE_CLI_IMAGE" "$@"
}

azure_cli_sign_in() {
    local tenant_id="$1"
    [[ -t 0 && -t 2 ]] || {
        printf 'Azure sign-in requires an interactive terminal; rerun restore with --azure-login from a terminal.\n' >&2
        return 1
    }
    printf 'Sign in to the organization tenant %s in your browser.\n' "$tenant_id" >&2
    # The device-code instructions go to stderr; login account/token output is
    # suppressed. Tenant policy may disallow this flow; retain login fallback.
    run_azure_cli login --tenant "$tenant_id" --use-device-code --output none --only-show-errors
}
