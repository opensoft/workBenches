#!/usr/bin/env bash
# Run publisher package operations natively, with a staging HOME and no secrets.
set -euo pipefail
cwd=$1 stage_home=$2 guard=$3 native_tools=$4 control=$5 deadline_seconds=$6
shift 6
[[ "$cwd" == /* && "$stage_home" == /* && "$guard" == /* ]] || exit 2
[[ "$control" == "$guard"/operation-* && "$deadline_seconds" =~ ^[1-9][0-9]*$ ]] || exit 2
clean_env=("HOME=$stage_home" "PATH=$guard${native_tools:+:$native_tools}:$PATH")
while [[ "${1:-}" != -- ]]; do
    [[ "${1:-}" =~ ^[A-Z][A-Z0-9_]*= && "$1" != PATH=* ]] || exit 2
    clean_env+=("$1"); shift
done
shift
cd "$cwd"
child=''
finish() {
    if [[ -n "$child" ]] && kill -0 -- "-$child" 2>/dev/null; then
        kill -TERM -- "-$child" 2>/dev/null || true
        for ((attempt=0; attempt<20; attempt++)); do
            kill -0 -- "-$child" 2>/dev/null || break
            sleep 0.05
        done
        kill -KILL -- "-$child" 2>/dev/null || true
        wait "$child" 2>/dev/null || true
    fi
    : > "$control.done"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
[[ -f "$control" ]] || exit 143
# Bash job control gives this child its own process group on Linux and macOS.
set -m
env -i "${clean_env[@]}" "$@" </dev/null &
child=$!
started=$SECONDS
while kill -0 "$child" 2>/dev/null; do
    [[ -f "$control" ]] || exit 130
    ((SECONDS - started < deadline_seconds)) || exit 124
    sleep 0.05
done
status=0
wait "$child" || status=$?
exit "$status"
