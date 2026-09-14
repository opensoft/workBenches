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
    'printf "%s\n" "$*" >> "$MOCK_DOCKER_LOG"' > "$mock_bin/docker"
chmod 0755 "$mock_bin/docker"

run_build() {
    : > "$docker_log"
    MOCK_DOCKER_LOG="$docker_log" PATH="$mock_bin:$PATH" \
        "$repo_root/user-layer/build.sh" --base py-bench:latest --user tester "$@" >/dev/null
}

run_build
grep -Fq -- '--build-arg CODEX_VERSION=latest' "$docker_log"

run_build --codex-version 0.200.0
grep -Fq -- '--build-arg CODEX_VERSION=0.200.0' "$docker_log"

printf 'layer3 Codex version build arguments are explicit and overridable\n'
