#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
checker="$repo_root/scripts/check-versions.sh"
installer="$repo_root/base-image/install-ai-clis.sh"
fixture="$repo_root/devcontainer.test/fixtures/fake-docker-cascade-validation.sh"
temp_dir="$(mktemp -d)"
fake_bin="$temp_dir/bin"
manifest="$(mktemp "$repo_root/config/.version-manifest.test.XXXXXX")"
rm -f -- "$manifest"
log="$temp_dir/docker.log"
default_image_id="sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
retagged_image_id="sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
captured_image_id="sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

cleanup() {
    rm -f -- "$manifest"
    rm -rf "$temp_dir"
}
trap cleanup EXIT

mkdir -p "$fake_bin"
cp "$fixture" "$fake_bin/docker"
chmod +x "$fake_bin/docker"
: > "$log"

bash -n "$checker"
bash -n "$repo_root/scripts/update-and-rebuild.sh"
test "$(bash -c 'source "$1"; bench_dir_to_image_repo 365Bench' _ "$repo_root/scripts/lib/image-names.sh")" = "m365-bench"

source "$repo_root/base-image/ai-cli-contract.sh"
source "$repo_root/scripts/lib/layer3-recipe.sh"
export FAKE_DOCKER_LAYER3_RECIPE_SHA256="$(layer3_recipe_sha256 "$repo_root/user-layer")"
test "${WORKBENCHES_REQUIRED_AI_CLIS[0]}" = claude
test "${WORKBENCHES_REQUIRED_AI_CLIS[-1]}" = cursor-agent
grep -Fq 'required_clis=("${WORKBENCHES_REQUIRED_AI_CLIS[@]}")' "$installer"

checker_help="$("$checker" --help)"
grep -Fq -- '--images IMAGE,...' <<< "$checker_help"
grep -Fq -- '--image-ids IMAGE=ID,...' <<< "$checker_help"
grep -Fq -- '--check-layer3' <<< "$checker_help"
grep -Fq -- '--write-manifest' <<< "$checker_help"
grep -Fq -- '--manifest-file FILE' <<< "$checker_help"
rebuild_help="$("$repo_root/scripts/update-and-rebuild.sh" --help)"
grep -Fq -- '--write-manifest' <<< "$rebuild_help"
grep -Fq 'CHECK_ARGS+=(--images "$CASCADE_IMAGE_LIST" --image-ids "$CASCADE_IMAGE_ID_LIST" --check-layer3)' "$repo_root/scripts/update-and-rebuild.sh"

PATH="$fake_bin:$PATH" \
FAKE_DOCKER_LOG="$log" \
"$checker" --layer 0 --images test-bench:latest --check-layer3 --user brett > "$temp_dir/success.out"

test ! -e "$manifest"
grep -Fq 'Layer 3 test-bench:brett is current' "$temp_dir/success.out"
grep -Fq "$default_image_id sh -c" "$log"
if grep -Fq 'test-bench:latest sh -c' "$log"; then
    echo "standalone verification followed a mutable image tag" >&2
    exit 1
fi
test "$(grep -cx 'probe-batch' "$log")" -eq 1
test "$(grep -c '^container ls --format ' "$log")" -eq 1

PATH="$fake_bin:$PATH" \
FAKE_DOCKER_LOG="$log" \
FAKE_DOCKER_LAYER3_RECIPE_SHA256=stale \
"$checker" --layer 0 --images test-bench:latest --check-layer3 --user brett \
    > "$temp_dir/stale-recipe.out"
grep -Fq 'has a stale recipe' "$temp_dir/stale-recipe.out"

PATH="$fake_bin:$PATH" \
FAKE_DOCKER_LOG="$log" \
FAKE_DOCKER_LAYER3_IDENTITY_STATUS=1 \
"$checker" --layer 0 --images test-bench:latest --check-layer3 --user brett \
    > "$temp_dir/stale-identity.out"
grep -Fq 'has stale user/group configuration' "$temp_dir/stale-identity.out"

PATH="$fake_bin:$PATH" \
FAKE_DOCKER_LOG="$log" \
"$checker" --layer 0 --images test-bench:latest --check-layer3 --json --user brett \
    > "$temp_dir/success.json" 2> "$temp_dir/success-json.err"
jq -e '.user == "brett" and ([.images[].status] | index("verified") != null) and ([.images[].status] | index("current") != null)' \
    "$temp_dir/success.json" >/dev/null

: > "$log"
PATH="$fake_bin:$PATH" \
FAKE_DOCKER_LOG="$log" \
FAKE_DOCKER_RUNNING_CONTAINERS=$'test-bench:brett\tlive-bench\n' \
"$checker" --layer 0 --images test-bench:latest --check-layer3 --user brett > "$temp_dir/running.out"
grep -Fq "activation deferred by running container 'live-bench'" "$temp_dir/running.out"
test "$(grep -c '^container ls --format ' "$log")" -eq 1

if PATH="$fake_bin:$PATH" \
    FAKE_DOCKER_LOG="$log" \
    FAKE_DOCKER_MISSING_CLI=claude \
    "$checker" --layer 0 --images test-bench:latest --user brett > "$temp_dir/missing.out" 2>&1; then
    echo "expected a missing required CLI to fail validation" >&2
    exit 1
fi
grep -Fq 'claude' "$temp_dir/missing.out"

PATH="$fake_bin:$PATH" \
FAKE_DOCKER_LOG="$log" \
"$checker" --layer 0 --images test-bench:latest --check-layer3 --write-manifest --manifest-file "$manifest" --user 'brett"qa' > /dev/null

test -s "$manifest"
jq -e '.user == "brett\"qa"' "$manifest" >/dev/null
grep -Fq '"image": "test-bench:latest"' "$manifest"
grep -Fq '"image": "test-bench:brett\"qa"' "$manifest"
grep -Fq "\"id\": \"$default_image_id\"" "$manifest"

rm -f -- "$manifest"
: > "$log"
PATH="$fake_bin:$PATH" \
FAKE_DOCKER_LOG="$log" \
FAKE_DOCKER_IMAGE_ID="$retagged_image_id" \
"$checker" --layer 0 \
    --images test-bench:latest \
    --image-ids "test-bench:latest=$captured_image_id" \
    --write-manifest \
    --manifest-file "$manifest" \
    --user brett > /dev/null
jq -e --arg id "$captured_image_id" '.images[] | select(.image == "test-bench:latest" and .id == $id and .status == "verified")' "$manifest" >/dev/null
grep -Fq "$captured_image_id sh -c" "$log"
if grep -Fq 'test-bench:latest sh -c' "$log"; then
    echo "immutable cascade verification followed a moved tag" >&2
    exit 1
fi
if "$checker" --layer 0 --images test-bench:latest \
    --image-ids test-bench:latest=mutable-tag >/dev/null 2>&1; then
    echo "expected a mutable --image-ids value to be rejected" >&2
    exit 1
fi
if "$checker" --layer 0 --write-manifest --manifest-file "$temp_dir/outside.json" >/dev/null 2>&1; then
    echo "expected an out-of-config manifest path to be rejected" >&2
    exit 1
fi

source "$repo_root/scripts/lib/cascade-image-validation.sh"
NO_CACHE=true
CASCADE_IMAGES=()
CASCADE_IMAGE_RECORDS=()
PATH="$fake_bin:$PATH" FAKE_DOCKER_LOG="$log" FAKE_DOCKER_IMAGE_ID="$captured_image_id" \
    record_rebuilt_cascade_image test-bench:latest testBench
test "${CASCADE_IMAGES[*]}" = test-bench:latest
test "${CASCADE_IMAGE_RECORDS[*]}" = "test-bench:latest=$captured_image_id"

CASCADE_IMAGES=()
CASCADE_IMAGE_RECORDS=()
compose_metadata="$temp_dir/sim-build.sh"
printf '%s\n' \
    'echo "Image: sim-bench-gene_bench:latest"' \
    'echo "Image: sim-bench-ui:latest"' > "$compose_metadata"
PATH="$fake_bin:$PATH" FAKE_DOCKER_LOG="$log" \
FAKE_DOCKER_IMAGE_ID="$captured_image_id" \
    record_rebuilt_cascade_image sim-bench:latest simBench "$compose_metadata"
test "${CASCADE_IMAGES[*]}" = "sim-bench-gene_bench:latest sim-bench-ui:latest"
test "${#CASCADE_IMAGE_RECORDS[@]}" -eq 2
if grep -Eq '(^| )(build|rm|stop|restart)( |$)' "$log"; then
    echo "Layer 3 inspection attempted a Docker mutation" >&2
    exit 1
fi

printf 'cascade image validation checks passed\n'
