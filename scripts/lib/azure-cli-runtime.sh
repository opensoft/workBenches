#!/usr/bin/env bash
# Azure CLI transport for credential escrow. The caller owns and removes the
# private work directory, including the temporary container login cache.

azure_cli_runtime_init() {
    local work_dir="$1" allow_login="$2"
    AZURE_CLI_WORK_DIR="$(realpath -- "$work_dir")"
    AZURE_CLI_BIN="$(type -P az || true)"
    AZURE_CLI_MODE=host
    if [[ -n "$AZURE_CLI_BIN" ]]; then
        return 0
    fi

    AZURE_CLI_BIN="${XDG_DATA_HOME:-$HOME/.local/share}/workbenches/tools/azure-cli/bin/az"
    if [[ -x "$AZURE_CLI_BIN" ]]; then
        return 0
    fi

    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        AZURE_CLI_MODE=docker
        AZURE_CLI_IMAGE="${WORKBENCHES_AZURE_CLI_IMAGE:-mcr.microsoft.com/azure-cli:2.91.0-azurelinux3.0}"
        mkdir -m 0700 "$AZURE_CLI_WORK_DIR/azure-config" "$AZURE_CLI_WORK_DIR/azure-home"
        printf 'Azure CLI will run in a temporary Docker container.\n' >&2
        return 0
    fi

    if [[ "$allow_login" == true && -t 0 && -t 2 ]]; then
        local answer
        printf 'Azure CLI is missing and Docker is unavailable. Install Azure CLI for your user account? [y/N]: ' >&2
        IFS= read -r answer || return 1
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

run_azure_cli() {
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
