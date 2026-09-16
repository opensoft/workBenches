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
    "run --rm")
        printf '%s\n' 'codex-cli 0.199.0'
        ;;
    "image inspect")
        image="${!#}"
        if [[ "$image" == workbenches-layer3-base-pin:* ]]; then
            [[ -f "$TEST_PINNED_TAG_FILE" \
                && "$image" == "$(cat "$TEST_PINNED_TAG_FILE")" ]] || exit 1
        fi
        if [[ "$3" == "--format" ]]; then
            if [[ "$4" == *recipe-sha256* ]]; then
                printf '%s\n' "${TEST_IMAGE_RECIPE_SHA256:-}"
            elif [[ "$4" == *base-image-id* ]]; then
                printf '%s\n' "${TEST_IMAGE_BASE_IMAGE_ID:-}"
            elif [[ "$4" == *'.Id'* ]]; then
                if [[ "$image" == *:latest && "${TEST_RETAGS_BASE:-false}" == true ]]; then
                    count=0
                    [[ ! -f "$TEST_BASE_ID_COUNT_FILE" ]] || count="$(cat "$TEST_BASE_ID_COUNT_FILE")"
                    count=$((count + 1))
                    printf '%s\n' "$count" > "$TEST_BASE_ID_COUNT_FILE"
                    if [[ "$count" -gt 1 ]]; then
                        printf '%s\n' 'sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc'
                    else
                        printf '%s\n' 'sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
                    fi
                else
                    printf '%s\n' 'sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
                fi
            else
                printf '%s\n' 'sha256:new-user-image'
            fi
        fi
        ;;
    "image rm")
        rm -f "$TEST_PINNED_TAG_FILE"
        ;;
    "tag "*)
        printf '%s\n' "$3" > "$TEST_PINNED_TAG_FILE"
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
            printf 'brett:x:%s:%s::/home/brett:/bin/zsh\n' \
                "${TEST_IMAGE_USER_UID:-$TEST_USER_UID}" \
                "${TEST_IMAGE_USER_GID:-$TEST_USER_GID}" > "$3"
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
export TEST_USER_UID="$(id -u)"
export TEST_USER_GID="$(id -g)"
export TEST_PINNED_TAG_FILE="$TEST_DIR/pinned-tag"
export TEST_BASE_ID_COUNT_FILE="$TEST_DIR/base-id-count"

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
    rm -f "$TEST_BASE_ID_COUNT_FILE"
    "$ROOT_DIR/scripts/ensure-layer3.sh" --base dotnet-bench:latest --user brett
}

export TEST_IMAGE_RECIPE_SHA256=stale
export TEST_IMAGE_BASE_IMAGE_ID=sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
run_check
grep -q '^build ' "$DOCKER_LOG"

export TEST_IMAGE_RECIPE_SHA256="$(recipe_sha256)"
export TEST_IMAGE_BASE_IMAGE_ID=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
run_check
grep -q '^build ' "$DOCKER_LOG"

export TEST_IMAGE_BASE_IMAGE_ID=sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
export TEST_IMAGE_USER_UID=4242
identity_output="$(run_check)"
grep -q 'does not match host UID:GID' <<< "$identity_output"
grep -q '^build ' "$DOCKER_LOG"
unset TEST_IMAGE_USER_UID

export TEST_IMAGE_USER_GID=4242
identity_output="$(run_check)"
grep -q 'does not match host UID:GID' <<< "$identity_output"
grep -q '^build ' "$DOCKER_LOG"
unset TEST_IMAGE_USER_GID

export TEST_RETAGS_BASE=true
retag_output="$(run_check)"
grep -q 'changed during validation' <<< "$retag_output"
grep -q '^build ' "$DOCKER_LOG"
export TEST_RETAGS_BASE=false

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
