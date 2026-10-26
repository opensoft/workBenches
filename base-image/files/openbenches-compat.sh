#!/usr/bin/env bash

openbenches_resolve_env() {
    local sensitive=false
    if [[ "${1:-}" == --sensitive ]]; then
        sensitive=true
        shift
    fi
    if [[ $# -lt 1 || $# -gt 2 ]]; then
        echo 'Usage: openbenches_resolve_env [--sensitive] SUFFIX [DEFAULT]' >&2
        return 2
    fi
    local suffix="$1" default="${2-}"
    if [[ ! "$suffix" =~ ^[A-Z][A-Z0-9_]*$ ]]; then
        echo 'openBenches environment suffix must be an uppercase variable-name suffix.' >&2
        return 2
    fi

    local name value selected_name='' selected_value=''
    for name in "OPENBENCHES_$suffix" "WORKBENCHES_$suffix" "WB_$suffix"; do
        declare -p "$name" >/dev/null 2>&1 || continue
        value="${!name-}"
        if [[ -z "$selected_name" ]]; then
            selected_name="$name"
            selected_value="$value"
        elif [[ "$sensitive" == true && "$value" != "$selected_value" ]]; then
            printf 'openBenches environment conflict: %s and %s differ. Set configured aliases to one identical value or unset the conflicting alias, then retry.\n' \
                "$selected_name" "$name" >&2
            return 2
        fi
    done
    if [[ -n "$selected_name" ]]; then
        printf '%s\n' "$selected_value"
    else
        printf '%s\n' "$default"
    fi
}

openbenches_state_root() {
    if [[ $# -lt 1 || $# -gt 2 ]]; then
        echo 'Usage: openbenches_state_root {config|cache|data} [XDG_BASE]' >&2
        return 2
    fi
    local kind="$1" base
    case "$kind" in
        config) base="${2:-${XDG_CONFIG_HOME:-$HOME/.config}}" ;;
        cache) base="${2:-${XDG_CACHE_HOME:-$HOME/.cache}}" ;;
        data) base="${2:-${XDG_DATA_HOME:-$HOME/.local/share}}" ;;
        *) echo 'State root kind must be config, cache, or data.' >&2; return 2 ;;
    esac
    if [[ -d "$base/openbenches" ]]; then
        printf '%s\n' "$base/openbenches"
    else
        printf '%s\n' "$base/workbenches"
    fi
}

openbenches_config_root() {
    if [[ $# -gt 1 ]]; then
        echo 'Usage: openbenches_config_root [XDG_CONFIG_HOME]' >&2
        return 2
    fi
    openbenches_state_root config "${1-}"
}

openbenches_cache_root() {
    if [[ $# -gt 1 ]]; then
        echo 'Usage: openbenches_cache_root [XDG_CACHE_HOME]' >&2
        return 2
    fi
    openbenches_state_root cache "${1-}"
}

openbenches_data_root() {
    if [[ $# -gt 1 ]]; then
        echo 'Usage: openbenches_data_root [XDG_DATA_HOME]' >&2
        return 2
    fi
    openbenches_state_root data "${1-}"
}

openbenches_link_command() {
    if [[ $# -ne 2 ]]; then
        echo 'Usage: openbenches_link_command IMPLEMENTATION ALIAS' >&2
        return 2
    fi
    local implementation="$1" alias="$2"
    if [[ -e "$alias" || -L "$alias" ]]; then
        if [[ -L "$alias" && "$(readlink -f "$alias")" == "$(readlink -f "$implementation")" ]]; then
            return 0
        fi
        printf 'Existing command was preserved; resolve its name collision first: %s\n' "$alias" >&2
        return 1
    fi
    ln -s "$implementation" "$alias"
}
