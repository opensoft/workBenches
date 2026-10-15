#!/usr/bin/env bash
# Private noninteractive native-host callbacks. Invoked only by tools-command.sh.
set -uo pipefail
session=$1
export PATH="$WORKBENCHES_NATIVE_PATH"
umask 077
cleanup() { rm -f "$session/alive"; [[ -z "${command_pid:-}" ]] || kill "$command_pid" 2>/dev/null || true; }
trap 'cleanup; exit 143' TERM
trap 'cleanup; exit 130' INT
trap cleanup EXIT
touch "$session/alive"

resolve_path() {
    local target=$1 link count=0
    [[ "$target" == /* ]] || target="$PWD/$target"
    while [[ -L "$target" ]]; do
        ((count+=1)); ((count <= 40)) || return 1
        link=$(readlink "$target") || return 1
        if [[ "$link" == /* ]]; then target=$link; else target="$(dirname "$target")/$link"; fi
    done
    local parent
    parent="$(cd -P "$(dirname "$target")" && pwd)" || return 1
    printf '%s/%s\n' "$parent" "$(basename "$target")"
}

dispatch() {
    local action=$1; shift
    case "$action" in
        @which) PATH="$WORKBENCHES_NATIVE_PATH" command -v "$1" ;;
        @resolve) resolve_path "$1" ;;
        @read) cat -- "$1" ;;
        @access) case "$2" in x) [[ -x "$1" ]] ;; w) [[ -w "$1" ]] ;; *) return 2 ;; esac ;;
        sudo)
            if ! sudo -n true </dev/null >/dev/null 2>&1; then
                touch "$request/sudo-required"; return 77
            fi
            sudo -n "$@" ;;
        @*) return 2 ;;
        *) "$action" "$@" ;;
    esac
}

while [[ -f "$session/alive" ]]; do
    for request in "$session"/request-*; do
        [[ -f "$request/ready" && ! -f "$request/exit" ]] || continue
        (
            exec 6< "$request/request"
            IFS= read -r -d '' cwd <&6
            IFS= read -r -d '' deadline <&6
            IFS= read -r -d '' count <&6
            [[ "$count" =~ ^[0-9]+$ && "$deadline" =~ ^[0-9]+$ && "$count" -le 4096 ]] || exit 2
            args=()
            for ((index=0; index<count; index++)); do IFS= read -r -d '' value <&6; args+=("$value"); done
            IFS= read -r -d '' count <&6
            [[ "$count" =~ ^[0-9]+$ && "$count" -le 4096 ]] || exit 2
            for ((index=0; index<count; index++)); do
                IFS= read -r -d '' key <&6; IFS= read -r -d '' value <&6
                [[ "$key" =~ ^[a-zA-Z_][a-zA-Z_0-9]*$ ]] || exit 2
                case "$key" in PATH|PYTHONPATH|LD_LIBRARY_PATH) continue ;; esac
                export "$key=$value"
            done
            cd "$cwd" || exit 2
            dispatch "${args[@]}"
        ) < "$request/input" > "$request/stdout" 2> "$request/stderr" &
        command_pid=$!
        started=$SECONDS
        IFS= read -r deadline < "$request/timeout" || deadline=30
        [[ "$deadline" =~ ^[0-9]+$ ]] || deadline=30
        while kill -0 "$command_pid" 2>/dev/null; do
            if [[ -f "$request/cancel" ]] || (( SECONDS - started > deadline )); then
                kill "$command_pid" 2>/dev/null || true
                break
            fi
            sleep 0.025
        done
        wait "$command_pid"; result=$?
        command_pid=''
        printf '%s\n' "$result" > "$request/exit.new"
        mv "$request/exit.new" "$request/exit"
    done
    sleep 0.025
done
