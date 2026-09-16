#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
case_root="$(mktemp -d)"
trap 'rm -rf "$case_root"' EXIT
mock_bin="$case_root/bin"
docker_log="$case_root/docker.log"
timeout_log="$case_root/timeout.log"
pinned_tag_file="$case_root/pinned-tag"
mkdir -p "$mock_bin"

base_image_id="sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'if [[ "${1:-}" == image && "${2:-}" == inspect ]]; then' \
    '  image="${!#}"' \
    '  if [[ "$image" == workbenches-layer3-base-pin:* ]]; then' \
    '    [[ -f "$MOCK_PINNED_TAG_FILE" && "$image" == "$(cat "$MOCK_PINNED_TAG_FILE")" ]] || exit 1' \
    '  fi' \
    '  if [[ "$image" == py-bench:latest ]]; then' \
    '    printf "%s\n" "${MOCK_TAG_IMAGE_ID:-sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb}"' \
    '  else' \
    '    printf "%s\n" "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"' \
    '  fi' \
    '  exit 0' \
    'fi' \
    'if [[ "${1:-}" == tag ]]; then' \
    '  printf "%s\n" "$*" >> "$MOCK_DOCKER_LOG"' \
    '  printf "%s\n" "$3" > "$MOCK_PINNED_TAG_FILE"' \
    '  exit 0' \
    'fi' \
    'if [[ "${1:-}" == image && "${2:-}" == rm ]]; then' \
    '  printf "%s\n" "$*" >> "$MOCK_DOCKER_LOG"' \
    '  rm -f "$MOCK_PINNED_TAG_FILE"' \
    '  exit 0' \
    'fi' \
    'if [[ "${1:-}" == run ]]; then' \
    '  printf "%s\n" "$*" >> "$MOCK_DOCKER_LOG"' \
    '  printf "%s\n" "codex-cli 0.199.0"' \
    '  exit 0' \
    'fi' \
    'printf "%s\n" "$*" >> "$MOCK_DOCKER_LOG"' > "$mock_bin/docker"
chmod 0755 "$mock_bin/docker"

printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'printf "%s\n" "$*" >> "$MOCK_TIMEOUT_LOG"' \
    'if [[ "${MOCK_TIMEOUT_FAIL:-false}" == true ]]; then exit 124; fi' \
    'shift' \
    'exec "$@"' > "$mock_bin/timeout"
chmod 0755 "$mock_bin/timeout"

run_build() {
    : > "$docker_log"
    : > "$timeout_log"
    MOCK_DOCKER_LOG="$docker_log" MOCK_TIMEOUT_LOG="$timeout_log" \
        MOCK_PINNED_TAG_FILE="$pinned_tag_file" PATH="$mock_bin:$PATH" \
        "$repo_root/user-layer/build.sh" --base py-bench:latest --user tester "$@" >/dev/null
}

run_build
pinned_ref="$(awk '$1 == "tag" { print $3; exit }' "$docker_log")"
[[ "$pinned_ref" == workbenches-layer3-base-pin:* ]]
grep -Fq -- "tag $base_image_id $pinned_ref" "$docker_log"
grep -Fq -- "run --rm --network none --entrypoint= $pinned_ref sh -c codex --version" "$docker_log"
grep -Fq -- "--build-arg BASE_IMAGE=$pinned_ref" "$docker_log"
grep -Fq -- "--build-arg BASE_IMAGE_ID=$base_image_id" "$docker_log"
grep -Fq -- '--build-arg CODEX_VERSION=0.199.0' "$docker_log"
grep -Fq -- "image rm $pinned_ref" "$docker_log"
grep -Fq -- "30s docker run --rm --network none --entrypoint= $pinned_ref sh -c codex --version" "$timeout_log"

MOCK_TAG_IMAGE_ID=sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc \
    run_build --base-image-id "$base_image_id"
pinned_ref="$(awk '$1 == "tag" { print $3; exit }' "$docker_log")"
grep -Fq -- "tag $base_image_id $pinned_ref" "$docker_log"
grep -Fq -- "--build-arg BASE_IMAGE_ID=$base_image_id" "$docker_log"

WORKBENCHES_CODEX_VERSION_PROBE_TIMEOUT_SECONDS=7 run_build
pinned_ref="$(awk '$1 == "tag" { print $3; exit }' "$docker_log")"
grep -Fq -- "7s docker run --rm --network none --entrypoint= $pinned_ref sh -c codex --version" "$timeout_log"

if WORKBENCHES_CODEX_VERSION_PROBE_TIMEOUT_SECONDS=0 run_build; then
    echo 'invalid Codex probe timeout was accepted' >&2
    exit 1
fi

if MOCK_TIMEOUT_FAIL=true run_build; then
    echo 'Codex probe timeout did not fail the build' >&2
    exit 1
fi

run_build --codex-version 0.200.0
grep -Fq -- '--build-arg CODEX_VERSION=0.200.0' "$docker_log"
pinned_ref="$(awk '$1 == "tag" { print $3; exit }' "$docker_log")"
grep -Fq -- "--build-arg BASE_IMAGE=$pinned_ref" "$docker_log"
grep -Fq -- "--build-arg BASE_IMAGE_ID=$base_image_id" "$docker_log"
if grep -Fq -- 'run --rm --network none' "$docker_log"; then
    echo 'explicit Codex version unexpectedly probed the base image' >&2
    exit 1
fi

if run_build --codex-version latest; then
    echo 'mutable Codex dist-tag was accepted as an exact version' >&2
    exit 1
fi

printf 'layer3 Codex version inherits the exact base version and remains overridable\n'
