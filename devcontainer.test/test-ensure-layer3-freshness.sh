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
    (
        cd "$ROOT_DIR/user-layer"
        find . -type f -print0 \
            | LC_ALL=C sort -z \
            | xargs -0 sha256sum \
            | sha256sum \
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

echo "ensure-layer3 recipe freshness tests passed"
