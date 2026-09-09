#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

mkdir -p "$TEST_DIR/bin"
DOCKER_LOG="$TEST_DIR/docker.log"
export DOCKER_LOG

cat > "$TEST_DIR/bin/docker" <<'EOF'
#!/bin/bash
set -euo pipefail

printf '%s\n' "$*" >> "$DOCKER_LOG"

case "$1 $2" in
    "image inspect")
        if [[ "$3" == "--format" ]]; then
            if [[ "$4" == *recipe-sha256* ]]; then
                printf '%s\n' "${TEST_IMAGE_RECIPE_SHA256:-}"
            else
                printf '%s\n' 'sha256:new-user-image'
            fi
        fi
        ;;
    "container ls")
        if [[ " $* " == *" --all "* && "${TEST_STALE_CONTAINER:-false}" == true ]]; then
            printf '%s\n' stale-container
        fi
        ;;
    "container inspect")
        if [[ -f "${TEST_REMOVED_MARKER:-/nonexistent}" ]]; then
            exit 1
        fi
        case "$4" in
            *Config.Image*) printf '%s\n' dotnet-bench:brett ;;
            *State.Running*) printf '%s\n' false ;;
        esac
        ;;
    "inspect --format")
        if [[ "$3" == *Image* && "$4" == stale-container ]]; then
            printf '%s\n' 'sha256:old-user-image'
        elif [[ "$4" == *:latest ]]; then
            printf '%s\n' '2026-09-08T12:00:00Z'
        else
            printf '%s\n' '2026-09-08T12:01:00Z'
        fi
        ;;
    "create --name")
        printf '%s\n' test-container
        ;;
    "cp ensure-layer3-check"*)
        if [[ "$2" == *:/etc/passwd ]]; then
            printf 'brett:x:1000:%s::/home/brett:/bin/zsh\n' "${TEST_SOCKET_GID:-1000}" > "$3"
        else
            printf 'docker-host:x:%s:brett\n' "${TEST_SOCKET_GID:-1000}" > "$3"
        fi
        ;;
    "rm -f")
        ;;
    "rm stale-container")
        if [[ "${TEST_RM_ALREADY_ABSENT:-false}" == true ]]; then
            : > "$TEST_REMOVED_MARKER"
            exit 1
        fi
        ;;
    "build --build-arg")
        ;;
    *)
        echo "unexpected docker invocation: $*" >&2
        exit 1
        ;;
esac
EOF
chmod +x "$TEST_DIR/bin/docker"

export PATH="$TEST_DIR/bin:$PATH"
export TEST_SOCKET_GID="$(stat -c '%g' /var/run/docker.sock 2>/dev/null || true)"

recipe_sha256() {
    local hash_tool
    if command -v sha256sum >/dev/null 2>&1; then
        hash_tool=sha256sum
    else
        hash_tool=shasum
    fi

    (
        cd "$ROOT_DIR/user-layer"
        find . -type f -print \
            | LC_ALL=C sort \
            | while IFS= read -r recipe_file; do
                if [[ "$hash_tool" == sha256sum ]]; then
                    file_sha="$(sha256sum "$recipe_file" | awk '{print $1}')"
                else
                    file_sha="$(shasum -a 256 "$recipe_file" | awk '{print $1}')"
                fi
                printf '%s  %s\n' "$file_sha" "$recipe_file"
            done \
            | if [[ "$hash_tool" == sha256sum ]]; then sha256sum; else shasum -a 256; fi \
            | awk '{print $1}'
    )
}

run_check() {
    : > "$DOCKER_LOG"
    "$ROOT_DIR/scripts/ensure-layer3.sh" --base dotnet-bench:latest --user brett
}

export TEST_IMAGE_RECIPE_SHA256=stale
run_check
grep -q '^build ' "$DOCKER_LOG"

export TEST_IMAGE_RECIPE_SHA256="$(recipe_sha256)"
export TEST_STALE_CONTAINER=true
run_check
if grep -q '^build ' "$DOCKER_LOG"; then
    echo "matching recipe fingerprint unexpectedly rebuilt Layer 3" >&2
    exit 1
fi
grep -q '^rm stale-container$' "$DOCKER_LOG"

export TEST_RM_ALREADY_ABSENT=true
export TEST_REMOVED_MARKER="$TEST_DIR/removed"
run_check
grep -q '^rm stale-container$' "$DOCKER_LOG"
grep -q '^container inspect stale-container$' "$DOCKER_LOG"

echo "ensure-layer3 recipe freshness tests passed"
