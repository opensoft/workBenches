#!/usr/bin/env bash
# Standalone fresh-workstation bootstrap and shared GitHub clone transport.

workbenches_version() {
    local version='' root="${BASH_SOURCE[0]%/*}"
    if [[ -r "$root/VERSION" ]] && IFS= read -r version < "$root/VERSION" &&
        [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
        printf '%s\n' "$version"
    else
        printf '0.0.0-dev\n'
    fi
}

# Run only after Tools is available, never during first-paint readiness checks.
workbenches_release_checkout() {
    [[ "${WORKBENCHES_FROZEN:-}" != 1 ]] || return 0
    local root="${BASH_SOURCE[0]%/*}" tagged head
    tagged="$(git -C "$root" rev-parse --verify "refs/tags/v$(workbenches_version)^{commit}" 2>/dev/null)" || return 1
    head="$(git -C "$root" rev-parse HEAD 2>/dev/null)" || return 1
    [[ "$tagged" == "$head" ]]
}

workbenches_github_repo() {
    local url="$1"
    case "$url" in
        https://github.com/*) url="${url#https://github.com/}" ;;
        ssh://git@github.com/*) url="${url#ssh://git@github.com/}" ;;
        git@github.com:*) url="${url#git@github.com:}" ;;
        *) return 1 ;;
    esac
    url="${url%/}"
    url="${url%.git}"
    [[ "$url" =~ ^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$ ]] || return 1
    printf '%s\n' "$url"
}

workbenches_ssh_command() {
    local ssh_command="${GIT_SSH_COMMAND:-${GIT_SSH:-}}"
    if [[ -z "$ssh_command" ]]; then
        ssh_command="$(git config --get core.sshCommand 2>/dev/null || true)"
    fi
    printf '%s -o BatchMode=yes -o ConnectTimeout=5 -o ConnectionAttempts=1 -o StrictHostKeyChecking=yes\n' "${ssh_command:-ssh}"
}

workbenches_clone_url() {
    local url="$1" repo status
    if ! repo="$(workbenches_github_repo "$url")"; then
        printf '%s\n' "$url"
        return 0
    fi
    # Probe the repository, not just whether a key file exists. This respects
    # ssh-agent and SSH config and never asks for a key passphrase or host trust.
    if GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="$(workbenches_ssh_command)" \
        git ls-remote "git@github.com:$repo.git" HEAD >/dev/null 2>&1; then
        printf 'git@github.com:%s.git\n' "$repo"
    else
        status=$?
        case "$status" in 130|143) return "$status" ;; esac
        printf 'https://github.com/%s.git\n' "$repo"
    fi
}

workbenches_clone() {
    local requested_url="$1" destination="$2" url repo status
    shift 2
    url="$(workbenches_clone_url "$requested_url")" || return $?
    printf 'Cloning from %s\n' "$url" >&2
    if [[ "$url" == git@github.com:* ]]; then
        if GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="$(workbenches_ssh_command)" \
            git clone "$@" "$url" "$destination"; then
            return 0
        else
            status=$?
            case "$status" in 130|143) return "$status" ;; esac
        fi
        repo="$(workbenches_github_repo "$url")" || return 1
        url="https://github.com/$repo.git"
        printf 'SSH clone failed; retrying with %s\n' "$url" >&2
    fi
    # Git owns failed-clone cleanup. Never delete an existing destination to retry.
    if workbenches_github_repo "$url" >/dev/null; then
        # An exact identity rewrite wins over the common global rule that
        # rewrites all GitHub HTTPS URLs to SSH; fallback must remain HTTPS.
        GIT_TERMINAL_PROMPT=0 git -c "url.$url.insteadOf=$url" clone "$@" "$url" "$destination"
    else
        git clone "$@" "$url" "$destination"
    fi
}

workbenches_init_submodules() {
    local root="$1" key url chosen status
    shift
    local -a config_args=()
    while read -r key url; do
        [[ -n "$key" ]] || continue
        chosen="$(workbenches_clone_url "$url")" || return $?
        config_args+=(-c "$key=$chosen")
        if [[ "$chosen" == https://github.com/* ]]; then
            config_args+=(-c "url.$chosen.insteadOf=$chosen")
        fi
    done < <(git -C "$root" config -f .gitmodules --get-regexp '^submodule\..*\.url$')
    if GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="$(workbenches_ssh_command)" \
        git "${config_args[@]}" -C "$root" submodule update --init --recursive -- "$@"; then
        return 0
    else
        status=$?
        case "$status" in 130|143) return "$status" ;; esac
    fi
    printf 'Submodule update failed; retrying GitHub repositories with HTTPS.\n' >&2
    GIT_TERMINAL_PROMPT=0 git \
        -c 'url.https://github.com/.insteadOf=git@github.com:' \
        -c 'url.https://github.com/.insteadOf=ssh://git@github.com/' \
        -C "$root" submodule update --init --recursive -- "$@"
}

workbenches_prepare_fresh_roots() {
    local kind base
    for kind in config cache data; do
        case "$kind" in
            config) base="${XDG_CONFIG_HOME:-$HOME/.config}" ;;
            cache) base="${XDG_CACHE_HOME:-$HOME/.cache}" ;;
            data) base="${XDG_DATA_HOME:-$HOME/.local/share}" ;;
        esac
        if [[ ! -d "$base/openbenches" && ! -d "$base/workbenches" ]]; then
            mkdir -p -m 700 "$base/openbenches" || return $?
        fi
    done
}

workbenches_bootstrap_main() {
    local destination="${HOME:?HOME is required}/Projects/openBenches" setup=false branch=""
    command -v git >/dev/null 2>&1 || { echo 'Install Git first, then rerun bootstrap.' >&2; return 1; }
    case "${1:-}" in
        --clone)
            [[ $# -ge 3 ]] || { echo 'Usage: bootstrap.sh --clone URL DESTINATION [git clone options]' >&2; return 2; }
            shift
            workbenches_clone "$@"
            return $?
            ;;
        --submodules)
            [[ $# == 2 ]] || { echo 'Usage: bootstrap.sh --submodules CHECKOUT' >&2; return 2; }
            workbenches_init_submodules "$2"
            return $?
            ;;
    esac
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --directory|--branch)
                [[ $# -ge 2 ]] || { echo "$1 requires a value" >&2; return 2; }
                if [[ "$1" == --directory ]]; then destination="$2"; else branch="$2"; fi
                shift 2
                ;;
            --setup) setup=true; shift ;;
            --help|-h)
                echo 'Usage: bootstrap.sh [--directory PATH] [--branch NAME] [--setup]'
                echo '       bootstrap.sh --clone URL DESTINATION [git clone options]'
                echo '       bootstrap.sh --submodules CHECKOUT'
                return 0
                ;;
            *) echo "Unknown option: $1" >&2; return 2 ;;
        esac
    done
    local -a clone_args=()
    [[ -z "$branch" ]] || clone_args=(--branch "$branch")
    mkdir -p "$(dirname "$destination")" || return $?
    workbenches_clone https://github.com/opensoft/openBenches.git "$destination" "${clone_args[@]}" || return $?
    if [[ "${OPENBENCHES_FROZEN:-${WORKBENCHES_FROZEN:-${WB_FROZEN:-}}}" != 1 ]]; then
        workbenches_prepare_fresh_roots || return $?
    fi
    if [[ "$setup" == true ]]; then
        (cd "$destination" && bash ./setup.sh)
    else
        printf 'Cloned openBenches to %s. Run ./setup.sh from that directory when ready.\n' "$destination"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set -euo pipefail
    workbenches_bootstrap_main "$@"
fi
