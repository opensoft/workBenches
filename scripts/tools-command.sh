#!/usr/bin/env bash
# Host-side command shim. The executables and their libraries stay in Docker.
set -uo pipefail
# Native bench scripts can prepend their Docker adapter. The transport itself
# must always invoke the native Docker client, never recurse through that adapter.
if [[ -n "${WORKBENCHES_NATIVE_PATH:-}" ]]; then export PATH="$WORKBENCHES_NATIVE_PATH"; fi
root="${WORKBENCHES_TOOLS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$root/scripts/lib/tools-container.sh"
tool="${0##*/}"
if [[ "$tool" == tools-command.sh ]]; then tool=$1; shift; fi
case "$tool" in python3|jq|git|curl|rclone) ;; *) echo 'Unsupported setup tool.' >&2; exit 2 ;; esac
[[ "$(workbenches_tools_state)" == up ]] || workbenches_tools_start || exit "$?"
session_root="${XDG_CACHE_HOME:-$HOME/.cache}/workbenches/tools/sessions"
umask 077
mkdir -p "$session_root" || exit 1
session="$(mktemp -d "$session_root/command.XXXXXX")" || exit 1
broker=''
cleanup() {
    if [[ -n "$broker" ]]; then
        # Close the session before signalling: a broker between requests can
        # leave its loop normally even if a TERM trap races with child reaping.
        rm -f "$session/alive"
        kill "$broker" 2>/dev/null || true
        local attempt
        for ((attempt=0; attempt<40; attempt++)); do
            kill -0 "$broker" 2>/dev/null || break
            sleep 0.05
        done
        kill -KILL "$broker" 2>/dev/null || true
        wait "$broker" 2>/dev/null || true
    fi
    rm -rf -- "$session"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
export WORKBENCHES_NATIVE_PATH="${WORKBENCHES_NATIVE_PATH:-$PATH}"
export WORKBENCHES_HOST_RPC="$session"
bash "$root/scripts/lib/tools-host-broker.sh" "$session" &
broker=$!
for ((attempt=0; attempt<100; attempt++)); do [[ ! -f "$session/alive" ]] || break; sleep 0.01; done
[[ -f "$session/alive" ]] || exit 1

# Pass the current invocation's environment, not stale values captured when
# the persistent container was created. Values are never put on the argv.
args=(--interactive --workdir "$PWD" --env WORKBENCHES_HOST_RPC)
[[ ! -t 0 || ! -t 1 ]] || args+=(--tty)
while IFS= read -r variable; do
    case "$variable" in
        HOME|USER|LOGNAME|LANES_OS|DISPLAY|WAYLAND_DISPLAY|BROWSER|TERM|COLORTERM|LANG|LC_*|TMPDIR|XDG_*|SSH_AUTH_SOCK|GIT_*|GH_*|WORKBENCHES_*|AI_*|AZURE_*|OPENAI_*|ANTHROPIC_*|CLAUDE_*|CODEX_*|CHATGPT_*|PI_*|OMNIROUTE_*|OPENCODE_*|WAVE_*|PROJECTS_ROOT|WSL_*|npm_config_*|NPM_CONFIG_*)
            case "$variable" in WORKBENCHES_NATIVE_PATH|WORKBENCHES_TOOLS_BIN|WORKBENCHES_DOCKER_ENDPOINT) continue ;; esac
            args+=(--env "$variable") ;;
    esac
done < <(compgen -e)
workbenches_runtime_docker exec "${args[@]}" "$WORKBENCHES_TOOLS_CONTAINER" "$tool" "$@"
result=$?
if [[ "$result" == 77 && -f "$session/sudo-required" ]]; then
    cleanup; trap - EXIT
    sudo -v || exit "$?"
    exec "$root/scripts/tools-command.sh" "$tool" "$@"
fi
exit "$result"
