#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
case_root="$(mktemp -d)"
trap 'rm -rf "$case_root"' EXIT
mock_bin="$case_root/bin"
docker_log="$case_root/docker.log"
mkdir -p "$mock_bin"

printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'if [[ "${1:-}" == image && "${2:-}" == inspect ]]; then exit 0; fi' \
    'if [[ "${1:-}" == run ]]; then' \
    '  printf "%s\n" "$*" >> "$MOCK_DOCKER_LOG"' \
    '  printf "%s\n" "codex-cli 0.199.0"' \
    '  exit 0' \
    'fi' \
    'printf "%s\n" "$*" >> "$MOCK_DOCKER_LOG"' > "$mock_bin/docker"
chmod 0755 "$mock_bin/docker"

run_build() {
    : > "$docker_log"
    MOCK_DOCKER_LOG="$docker_log" PATH="$mock_bin:$PATH" \
        "$repo_root/user-layer/build.sh" --base py-bench:latest --user tester "$@" >/dev/null
}

run_build
grep -Fq -- 'run --rm --network none --entrypoint= py-bench:latest sh -c codex --version' "$docker_log"
grep -Fq -- '--build-arg CODEX_VERSION=0.199.0' "$docker_log"

run_build --codex-version 0.200.0
grep -Fq -- '--build-arg CODEX_VERSION=0.200.0' "$docker_log"
if grep -Fq -- 'run --rm --network none' "$docker_log"; then
    echo 'explicit Codex version unexpectedly probed the base image' >&2
    exit 1
fi

if run_build --codex-version latest; then
    echo 'mutable Codex dist-tag was accepted as an exact version' >&2
    exit 1
fi

printf 'layer3 Codex version inherits the exact base version and remains overridable\n'
