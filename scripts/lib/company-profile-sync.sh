#!/usr/bin/env bash
# Opt-in launch synchronization; no discovery or network for unmanaged profiles.
wb_sync_before() {
    local path=$1 action=$2 lease status=0
    wb_sync_managed=false
    [[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/workbenches/company-sync-enabled" ]] || return 0
    wb_sync_helper="$(command -v workbenches-credential-sync || true)"
    [[ -n "$wb_sync_helper" ]] || { echo 'Company sync helper is missing; repair it from Profiles.' >&2; return 1; }
    "$wb_sync_helper" --is-managed "$path" || status=$?
    [[ "$status" != 1 ]] || return 0
    [[ "$status" == 0 ]] || return "$status"
    wb_sync_managed=true
    if [[ "$action" == login ]]; then
        "$wb_sync_helper" --before-login "$path" || return "$?"
    else
        "$wb_sync_helper" --before-launch "$path" || return "$?"
    fi
    command -v flock >/dev/null 2>&1 || { echo 'Managed profile coordination needs flock.' >&2; return 1; }
    lease="$("$wb_sync_helper" --lease-path "$path")" || return "$?"
    exec {wb_sync_fd}>"$lease"
    flock -x "$wb_sync_fd"
}

wb_sync_after_login() {
    [[ "${wb_sync_managed:-false}" == true ]] || return 0
    exec {wb_sync_fd}>&-
    "$wb_sync_helper" --after-login "$1"
}
