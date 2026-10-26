#!/usr/bin/env bash
# Opt-in launch synchronization; no discovery or network for unmanaged profiles.
openbenches_sync_dir="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
openbenches_sync_compat="$openbenches_sync_dir/openbenches-compat.sh"
[[ -f "$openbenches_sync_compat" ]] || openbenches_sync_compat="$openbenches_sync_dir/lib/openbenches-compat.sh"
[[ -f "$openbenches_sync_compat" ]] || openbenches_sync_compat=/usr/local/share/openbenches/openbenches-compat.sh
source "$openbenches_sync_compat"

wb_sync_before() {
    local path=$1 action=$2 lease status=0 config_root
    wb_sync_managed=false
    config_root="$(openbenches_config_root)"
    [[ -f "$config_root/company-sync-enabled" ]] || return 0
    wb_sync_helper="$(command -v workbenches-credential-sync || command -v openbenches-credential-sync || true)"
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
