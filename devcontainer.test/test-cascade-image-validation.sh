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
identity_parser_status=0
printf 'not-an-image-archive' \
    | python3 "$repo_root/scripts/lib/check-image-identity.py" brett 1000 1000 '' \
    || identity_parser_status=$?
test "$identity_parser_status" -eq 2
test "$(bash -c 'source "$1"; bench_dir_to_image_repo 365Bench' _ "$repo_root/scripts/lib/image-names.sh")" = "m365-bench"

source "$repo_root/base-image/ai-cli-contract.sh"
source "$repo_root/scripts/lib/layer3-recipe.sh"
export FAKE_DOCKER_LAYER3_RECIPE_SHA256="$(layer3_recipe_sha256 "$repo_root/user-layer")"
export FAKE_DOCKER_LAYER3_DOCKER_SOCKET_GID="$(stat -c '%g' /var/run/docker.sock 2>/dev/null || true)"
test "${WORKBENCHES_REQUIRED_AI_CLIS[0]}" = claude
test "${WORKBENCHES_REQUIRED_AI_CLIS[-1]}" = cursor-agent
grep -Fq 'required_clis=("${WORKBENCHES_REQUIRED_AI_CLIS[@]}")' "$installer"
test "$(grep -Fc -- '- user-layer/build.sh' "$repo_root/.github/workflows/cascade-image-validation.yml")" -eq 2

assert_layer3_identity_rejected() {
    : > "$log"
    if PATH="$fake_bin:$PATH" FAKE_DOCKER_LOG="$log" \
        "$repo_root/user-layer/build.sh" --base test-bench:latest "$@" \
            > "$temp_dir/root-layer3.out" 2>&1; then
        echo "expected Layer 3 to reject a root-equivalent identity" >&2
        exit 1
    fi
    grep -Fq 'requires a valid non-root username and canonical positive UID/GID' \
        "$temp_dir/root-layer3.out"
    test ! -s "$log"
}
assert_layer3_identity_rejected --user root --uid 0 --gid 0
assert_layer3_identity_rejected --user 00 --uid 1000 --gid 1000
assert_layer3_identity_rejected --user '' --uid 1000 --gid 1000
assert_layer3_identity_rejected --user 'bad.name' --uid 1000 --gid 1000
assert_layer3_identity_rejected --user 'bad$' --uid 1000 --gid 1000
assert_layer3_identity_rejected --user tester --uid 00 --gid 1000
assert_layer3_identity_rejected --user tester --uid 1000 --gid 000

checker_help="$("$checker" --help)"
grep -Fq -- '--images IMAGE,...' <<< "$checker_help"
grep -Fq -- '--image-ids IMAGE=ID,...' <<< "$checker_help"
grep -Fq -- '--check-layer3' <<< "$checker_help"
grep -Fq -- '--write-manifest' <<< "$checker_help"
grep -Fq -- '--manifest-file FILE' <<< "$checker_help"
grep -Fq -- 'WORKBENCHES_LAYER3_IDENTITY_TIMEOUT_SECONDS' <<< "$checker_help"
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
if grep -Fq 'layer3-identity-probe' "$log"; then
    echo "Layer 3 inspection created an identity-probe container" >&2
    exit 1
fi
grep -Fq 'image save sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd' "$log"

PATH="$fake_bin:$PATH" \
FAKE_DOCKER_LOG="$log" \
FAKE_DOCKER_LAYER3_DOCKER_SOCKET_GID=1234 \
WORKBENCHES_DOCKER_SOCKET_PATH="$temp_dir/missing-docker.sock" \
"$checker" --layer 0 --images test-bench:latest --check-layer3 --user brett \
    > "$temp_dir/no-socket.out"
grep -Fq 'Layer 3 test-bench:brett is current' "$temp_dir/no-socket.out"

PATH="$fake_bin:$PATH" \
FAKE_DOCKER_LOG="$log" \
FAKE_DOCKER_LAYER3_RECIPE_SHA256=stale \
"$checker" --layer 0 --images test-bench:latest --check-layer3 --user brett \
    > "$temp_dir/stale-recipe.out"
grep -Fq 'has a stale recipe' "$temp_dir/stale-recipe.out"

PATH="$fake_bin:$PATH" \
FAKE_DOCKER_LOG="$log" \
FAKE_DOCKER_LAYER3_PASSWD_USERNAME=other-user \
"$checker" --layer 0 --images test-bench:latest --check-layer3 --user brett \
    > "$temp_dir/stale-identity.out"
grep -Fq 'has stale user/group configuration' "$temp_dir/stale-identity.out"

if PATH="$fake_bin:$PATH" \
    FAKE_DOCKER_LOG="$log" \
    FAKE_DOCKER_IMAGE_SAVE_FAIL=true \
    "$checker" --layer 0 --images test-bench:latest --check-layer3 --user brett \
        > "$temp_dir/inspection-failed.out" 2>&1; then
    echo "expected a failed image export to fail inspection" >&2
    exit 1
fi
grep -Fq 'activation state is unknown' "$temp_dir/inspection-failed.out"
if grep -Fq 'has stale user/group configuration' "$temp_dir/inspection-failed.out"; then
    echo "failed image export was misclassified as a stale identity" >&2
    exit 1
fi

if WORKBENCHES_LAYER3_IDENTITY_TIMEOUT_SECONDS=invalid \
    "$checker" --layer 0 >/dev/null 2> "$temp_dir/invalid-timeout.err"; then
    echo "expected an invalid Layer 3 identity timeout to fail" >&2
    exit 1
fi
grep -Fq 'must be a positive integer' "$temp_dir/invalid-timeout.err"

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
if "$checker" --layer 0 --write-manifest --manifest-file "$repo_root/config/.." >/dev/null 2>&1; then
    echo "expected a normalized manifest path outside config to be rejected" >&2
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
compose_bench_dir="$temp_dir/sim-bench"
mkdir -p "$compose_bench_dir"
compose_metadata="$compose_bench_dir/sim-build.sh"
printf '%s\n' 'docker compose -f docker-compose.yml build' > "$compose_metadata"
printf '%s\n' \
    'services:' \
    '  gene:' \
    '    image: sim-bench-gene_bench:latest' \
    '  ui:' \
    '    image: sim-bench-ui' \
    '  # image: sim-bench-retired:latest' > "$compose_bench_dir/docker-compose.yml"
printf '%s\n' \
    'services:' \
    '  dev:' \
    '    image: sim-bench-dev:latest' > "$compose_bench_dir/docker-compose.dev.yml"
PATH="$fake_bin:$PATH" FAKE_DOCKER_LOG="$log" \
FAKE_DOCKER_IMAGE_ID="$captured_image_id" \
    record_rebuilt_cascade_image sim-bench:latest simBench "$compose_metadata" "$compose_bench_dir"
test "${CASCADE_IMAGES[*]}" = "sim-bench-gene_bench:latest sim-bench-ui:latest"
test "${#CASCADE_IMAGE_RECORDS[@]}" -eq 2
if grep -Fq 'sim-bench-dev:latest' "$log"; then
    echo "cascade capture inspected an unrelated Compose output" >&2
    exit 1
fi
if grep -Fq 'sim-bench-retired:latest' "$log"; then
    echo "cascade capture inspected a commented Compose output" >&2
    exit 1
fi

CASCADE_IMAGES=()
CASCADE_IMAGE_RECORDS=()
if PATH="$fake_bin:$PATH" FAKE_DOCKER_LOG="$log" \
    FAKE_DOCKER_IMAGE_ID="$captured_image_id" \
    record_rebuilt_cascade_image sim-bench:latest simBench "$compose_metadata" "$compose_bench_dir" \
        "sim-bench-gene_bench:latest=$captured_image_id
sim-bench-ui:latest=$captured_image_id"; then
    echo "expected unchanged pre-build Compose images to fail cascade capture" >&2
    exit 1
fi
test "${#CASCADE_IMAGES[@]}" -eq 0
test "${#CASCADE_IMAGE_RECORDS[@]}" -eq 0

CASCADE_IMAGES=()
CASCADE_IMAGE_RECORDS=()
printf '%s\n' 'docker compose build' > "$compose_metadata"
PATH="$fake_bin:$PATH" FAKE_DOCKER_LOG="$log" \
FAKE_DOCKER_IMAGE_ID="$captured_image_id" \
    record_rebuilt_cascade_image sim-bench:latest simBench "$compose_metadata" "$compose_bench_dir"
test "${CASCADE_IMAGES[*]}" = "sim-bench-gene_bench:latest sim-bench-ui:latest"
test "${#CASCADE_IMAGE_RECORDS[@]}" -eq 2
if grep -Fq 'sim-bench-dev:latest' "$log"; then
    echo "default Compose discovery inspected an unrelated Compose output" >&2
    exit 1
fi

CASCADE_IMAGES=()
CASCADE_IMAGE_RECORDS=()
if PATH="$fake_bin:$PATH" FAKE_DOCKER_LOG="$log" \
    FAKE_DOCKER_MISSING_IMAGE=sim-bench-ui:latest \
    record_rebuilt_cascade_image sim-bench:latest simBench "$compose_metadata" "$compose_bench_dir"; then
    echo "expected a missing declared Compose image to fail cascade capture" >&2
    exit 1
fi
test "${CASCADE_IMAGES[*]}" = sim-bench-gene_bench:latest
test "${#CASCADE_IMAGE_RECORDS[@]}" -eq 1
if grep -Eq '(^| )(build|create|rm|stop|restart)( |$)' "$log"; then
    echo "Layer 3 inspection attempted a Docker mutation" >&2
    exit 1
fi

printf 'cascade image validation checks passed\n'
