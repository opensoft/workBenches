#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
checker="$repo_root/scripts/check-versions.sh"
installer="$repo_root/base-image/install-ai-clis.sh"
fixture="$repo_root/devcontainer.test/fixtures/fake-docker-cascade-validation.sh"
export TEST_REAL_DOCKER="$(command -v docker)"
"$TEST_REAL_DOCKER" compose version >/dev/null
temp_dir="$(mktemp -d)"
fake_bin="$temp_dir/bin"
manifest="$(mktemp "$repo_root/config/.version-manifest.test.XXXXXX")"
rm -f -- "$manifest"
log="$temp_dir/docker.log"
default_image_id="sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
retagged_image_id="sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
captured_image_id="sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
running_image_id="sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"

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
test "$(grep -Fc -- '- user-layer/**' "$repo_root/.github/workflows/cascade-image-validation.yml")" -eq 2
grep -Fq "root|''|[!a-z_]*|*[!a-z0-9_-]*" "$repo_root/user-layer/Dockerfile"
if grep -Fq "grep -Eq '^[a-z_][a-z0-9_-]*$'" "$repo_root/user-layer/Dockerfile"; then
    echo "Layer 3 Dockerfile still uses line-oriented username validation" >&2
    exit 1
fi

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

assert_layer3_ensure_identity_rejected() {
    : > "$log"
    if PATH="$fake_bin:$PATH" FAKE_DOCKER_LOG="$log" \
        "$repo_root/scripts/ensure-layer3.sh" --base test-bench:latest "$@" \
            > "$temp_dir/root-layer3-ensure.out" 2>&1; then
        echo "expected ensure-layer3 to reject an invalid identity before its fast path" >&2
        exit 1
    fi
    grep -Fq 'requires a valid non-root username and canonical positive UID/GID' \
        "$temp_dir/root-layer3-ensure.out"
    test ! -s "$log"
}
assert_layer3_ensure_identity_rejected --user root
assert_layer3_ensure_identity_rejected --user 'bad.name'

checker_help="$("$checker" --help)"
grep -Fq -- '--images IMAGE,...' <<< "$checker_help"
grep -Fq -- '--image-ids IMAGE=ID,...' <<< "$checker_help"
grep -Fq -- '--layer3-images IMAGE,...' <<< "$checker_help"
grep -Fq -- '--check-layer3' <<< "$checker_help"
grep -Fq -- '--write-manifest' <<< "$checker_help"
grep -Fq -- '--manifest-file FILE' <<< "$checker_help"
grep -Fq -- 'WORKBENCHES_LAYER3_IDENTITY_TIMEOUT_SECONDS' <<< "$checker_help"
if "$checker" --layer 0 --check-layer3 > "$temp_dir/missing-layer3-images.out" 2>&1; then
    echo "expected --check-layer3 without --images to fail" >&2
    exit 1
fi
grep -Fq -- '--check-layer3 requires --images IMAGE,...' "$temp_dir/missing-layer3-images.out"
rebuild_help="$("$repo_root/scripts/update-and-rebuild.sh" --help)"
grep -Fq -- '--write-manifest' <<< "$rebuild_help"
grep -Fq 'build_args+=(--docker-gid "$docker_socket_gid")' "$repo_root/scripts/update-and-rebuild.sh"
grep -Fq 'CHECK_ARGS+=(--images "$CASCADE_IMAGE_LIST" --image-ids "$CASCADE_IMAGE_ID_LIST")' "$repo_root/scripts/update-and-rebuild.sh"
grep -Fq 'CHECK_ARGS+=(--layer3-images "$CASCADE_LAYER3_IMAGE_LIST" --check-layer3)' "$repo_root/scripts/update-and-rebuild.sh"
grep -Fq 'CHECK_ARGS+=(--layer all --images "$LAYER3_BASE" --check-layer3)' "$repo_root/scripts/update-and-rebuild.sh"

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

: > "$log"
PATH="$fake_bin:$PATH" \
FAKE_DOCKER_LOG="$log" \
"$checker" --layer 0 \
    --images test-bench:latest,sim-bench-gene_bench:latest \
    --layer3-images test-bench:latest \
    --check-layer3 --user brett > "$temp_dir/separate-layer3-targets.out"
grep -Fq 'Layer 3 test-bench:brett is current' "$temp_dir/separate-layer3-targets.out"
if grep -Fq 'sim-bench-gene_bench:brett' "$log"; then
    echo "Compose service output was incorrectly treated as a Layer 3 base" >&2
    exit 1
fi

: > "$log"
PATH="$fake_bin:$PATH" \
FAKE_DOCKER_LOG="$log" \
FAKE_DOCKER_RUNNING_CONTAINERS=$'test-bench@sha256:old\tid-bench\n' \
"$checker" --layer 0 --images test-bench:latest --check-layer3 --user brett \
    > "$temp_dir/running-id.out"
grep -Fq "activation deferred by running container 'id-bench'" "$temp_dir/running-id.out"
grep -Fq "container inspect --format {{.Image}} id-bench" "$log"

: > "$log"
PATH="$fake_bin:$PATH" \
FAKE_DOCKER_LOG="$log" \
FAKE_DOCKER_RUNNING_CONTAINERS="$running_image_id"$'\tid-only-bench\n' \
FAKE_DOCKER_RUNNING_CONTAINER_IMAGE_ID="$running_image_id" \
"$checker" --layer 0 --images test-bench:latest --check-layer3 --json --user brett \
    > "$temp_dir/running-id-only.json"
jq -e --arg id "$running_image_id" \
    '.images[] | select(.image == "test-bench:brett" and .status == "activation-deferred-running" and .id == $id)' \
    "$temp_dir/running-id-only.json" >/dev/null
if grep -Fq 'image save' "$log"; then
    echo "ID-only running Layer 3 image did not defer activation" >&2
    exit 1
fi

: > "$log"
PATH="$fake_bin:$PATH" \
FAKE_DOCKER_LOG="$log" \
FAKE_DOCKER_RUNNING_CONTAINERS=$'test-bench@sha256:old\told-digest-bench\n' \
FAKE_DOCKER_RUNNING_CONTAINER_IMAGE_ID="$running_image_id" \
"$checker" --layer 0 --images test-bench:latest --check-layer3 --json --user brett \
    > "$temp_dir/running-retagged.json"
jq -e --arg id "$running_image_id" \
    '.images[] | select(.image == "test-bench:brett" and .status == "activation-deferred-running" and .id == $id)' \
    "$temp_dir/running-retagged.json" >/dev/null
if grep -Fq 'image save' "$log"; then
    echo "retagged running Layer 3 image was inspected as the current tag" >&2
    exit 1
fi

: > "$log"
PATH="$fake_bin:$PATH" \
FAKE_DOCKER_LOG="$log" \
FAKE_DOCKER_RUNNING_CONTAINERS=$'registry.example/team/test-bench:brett\tother-repository-bench\n' \
FAKE_DOCKER_RUNNING_CONTAINER_IMAGE_ID="$running_image_id" \
"$checker" --layer 0 --images test-bench:latest --check-layer3 --user brett \
    > "$temp_dir/different-repository.out"
grep -Fq 'Layer 3 test-bench:brett is current' "$temp_dir/different-repository.out"
grep -Fq 'image save sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd' "$log"

PATH="$fake_bin:$PATH" \
FAKE_DOCKER_LOG="$log" \
FAKE_DOCKER_LAYER3_DOCKER_SOCKET_GID=1234 \
WORKBENCHES_DOCKER_SOCKET_PATH="$temp_dir/missing-docker.sock" \
"$checker" --layer 0 --images test-bench:latest --check-layer3 --user brett \
    > "$temp_dir/no-socket.out"
grep -Fq 'Layer 3 test-bench:brett is current' "$temp_dir/no-socket.out"

if PATH="$fake_bin:$PATH" \
    FAKE_DOCKER_LOG="$log" \
    FAKE_DOCKER_IMAGE_INSPECT_FAIL=test-bench:brett \
    "$checker" --layer 0 --images test-bench:latest --check-layer3 --json --user brett \
        > "$temp_dir/user-image-inspection-failed.json" \
        2> "$temp_dir/user-image-inspection-failed.err"; then
    echo "expected a failed Layer 3 image-ID inspection to fail validation" >&2
    exit 1
fi
grep -Fq 'activation state is unknown' "$temp_dir/user-image-inspection-failed.err"
jq -e \
    '.images[] | select(.image == "test-bench:brett" and .status == "activation-inspection-failed" and .id == "n/a")' \
    "$temp_dir/user-image-inspection-failed.json" >/dev/null
if jq -e '.images[] | select(.image == "test-bench:brett" and .status == "activation-missing")' \
    "$temp_dir/user-image-inspection-failed.json" >/dev/null; then
    echo "failed Layer 3 image-ID inspection was misclassified as missing" >&2
    exit 1
fi

PATH="$fake_bin:$PATH" \
FAKE_DOCKER_LOG="$log" \
FAKE_DOCKER_MISSING_IMAGE=test-bench:brett \
"$checker" --layer 0 --images test-bench:latest --check-layer3 --json --user brett \
    > "$temp_dir/user-image-missing.json" 2> "$temp_dir/user-image-missing.err"
jq -e \
    '.images[] | select(.image == "test-bench:brett" and .status == "activation-missing")' \
    "$temp_dir/user-image-missing.json" >/dev/null

printf '%s\n' 'previous-valid-manifest' > "$manifest"
if PATH="$fake_bin:$PATH" \
    FAKE_DOCKER_LOG="$log" \
    FAKE_DOCKER_MISSING_IMAGE=test-bench:brett \
    "$checker" --layer 0 --images test-bench:latest --check-layer3 --write-manifest \
        --manifest-file "$manifest" --user brett \
        > "$temp_dir/missing-image-manifest.out" 2> "$temp_dir/missing-image-manifest.err"; then
    echo "expected a missing Layer 3 image ID to reject manifest persistence" >&2
    exit 1
fi
test "$(cat "$manifest")" = 'previous-valid-manifest'
grep -Fq 'immutable image ID is missing' "$temp_dir/missing-image-manifest.err"
rm -f -- "$manifest"

PATH="$fake_bin:$PATH" \
FAKE_DOCKER_LOG="$log" \
FAKE_DOCKER_LAYER3_RECIPE_SHA256=stale \
"$checker" --layer 0 --images test-bench:latest --check-layer3 --user brett \
    > "$temp_dir/stale-recipe.out"
grep -Fq 'has a stale recipe' "$temp_dir/stale-recipe.out"

PATH="$fake_bin:$PATH" \
FAKE_DOCKER_LOG="$log" \
FAKE_DOCKER_LAYER3_BASE_IMAGE_ID="$retagged_image_id" \
"$checker" --layer 0 --images test-bench:latest --check-layer3 --user brett \
    > "$temp_dir/stale-base-image.out"
grep -Fq 'was built from a different base image' "$temp_dir/stale-base-image.out"

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

if PATH="$fake_bin:$PATH" \
    FAKE_DOCKER_LOG="$log" \
    FAKE_DOCKER_LABEL_INSPECT_FAIL=true \
    "$checker" --layer 0 --images test-bench:latest --check-layer3 --user brett \
        > "$temp_dir/metadata-inspection-failed.out" 2>&1; then
    echo "expected failed Layer 3 metadata inspection to fail validation" >&2
    exit 1
fi
grep -Fq 'activation state is unknown' "$temp_dir/metadata-inspection-failed.out"
if grep -Fq 'has stale user/group configuration' "$temp_dir/metadata-inspection-failed.out"; then
    echo "failed metadata inspection was misclassified as stale identity" >&2
    exit 1
fi

for failure_kind in created recipe base_image_label; do
    failure_env="FAKE_DOCKER_${failure_kind^^}_INSPECT_FAIL"
    if env PATH="$fake_bin:$PATH" \
        FAKE_DOCKER_LOG="$log" \
        "$failure_env=true" \
        "$checker" --layer 0 --images test-bench:latest --check-layer3 --json --user brett \
            > "$temp_dir/${failure_kind}-inspection-failed.json" \
            2> "$temp_dir/${failure_kind}-inspection-failed.err"; then
        echo "expected failed Layer 3 $failure_kind inspection to fail validation" >&2
        exit 1
    fi
    grep -Fq 'activation state is unknown' "$temp_dir/${failure_kind}-inspection-failed.err"
    jq -e \
        '.images[] | select(.image == "test-bench:brett" and .status == "activation-inspection-failed")' \
        "$temp_dir/${failure_kind}-inspection-failed.json" >/dev/null
    if grep -Fq 'activation is required' "$temp_dir/${failure_kind}-inspection-failed.err"; then
        echo "failed $failure_kind inspection was misclassified as stale" >&2
        exit 1
    fi
done

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

printf '%s\n' 'previous-valid-manifest' > "$manifest"
if PATH="$fake_bin:$PATH" \
    FAKE_DOCKER_LOG="$log" \
    FAKE_DOCKER_IMAGE_INSPECT_FAIL=test-bench:latest \
    "$checker" --layer 0 --images test-bench:latest --write-manifest \
        --manifest-file "$manifest" --user brett \
        > "$temp_dir/failed-manifest.out" 2> "$temp_dir/failed-manifest.err"; then
    echo "expected a failed image probe to reject manifest persistence" >&2
    exit 1
fi
test "$(cat "$manifest")" = 'previous-valid-manifest'
grep -Fq 'manifest not written' "$temp_dir/failed-manifest.err"
rm -f -- "$manifest"

PATH="$fake_bin:$PATH" \
FAKE_DOCKER_LOG="$log" \
"$checker" --layer 0 --images test-bench:latest --check-layer3 --json --write-manifest --manifest-file "$manifest" --user 'brett"qa' \
    > "$temp_dir/written-manifest.json"

test -s "$manifest"
cmp -s "$manifest" "$temp_dir/written-manifest.json"
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

layer2_selection_dir="$temp_dir/layer2-selection"
mkdir -p "$layer2_selection_dir/scripts" "$layer2_selection_dir/.devcontainer"
printf '%s\n' '#!/usr/bin/env bash' > "$layer2_selection_dir/build-layer.sh"
printf '%s\n' '#!/usr/bin/env bash' > "$layer2_selection_dir/scripts/build-layer.sh"
printf '%s\n' '#!/usr/bin/env bash' > "$layer2_selection_dir/build.sh"
printf '%s\n' '#!/usr/bin/env bash' > "$layer2_selection_dir/.devcontainer/build.sh"
chmod +x "$layer2_selection_dir/build-layer.sh" "$layer2_selection_dir/scripts/build-layer.sh"
chmod +x "$layer2_selection_dir/build.sh" "$layer2_selection_dir/.devcontainer/build.sh"
if select_layer2_build_script "$layer2_selection_dir" >/dev/null; then
    echo "Layer 2 cascade selected a full Layer 2 + Layer 3 build helper" >&2
    exit 1
fi
printf '%s\n' '#!/usr/bin/env bash' > "$layer2_selection_dir/scripts/build-layer2.sh"
chmod +x "$layer2_selection_dir/scripts/build-layer2.sh"
test "$(select_layer2_build_script "$layer2_selection_dir")" \
    = "$layer2_selection_dir/scripts/build-layer2.sh"

tag_filter_build="$temp_dir/tag-filter-build.sh"
printf '%s\n' \
    'docker build --build-arg CACHE_IMAGE=sim-bench-cache:latest -t sim-bench:latest .' \
    > "$tag_filter_build"
test "$(declared_cascade_images sim-bench:latest "$tag_filter_build" "$temp_dir")" \
    = 'sim-bench:latest'

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
    '  preview:' \
    '    image: sim-bench-preview:latest-dev' \
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
CASCADE_LAYER3_IMAGES=()
record_cascade_layer3_base_if_captured sim-bench:latest
test "${#CASCADE_LAYER3_IMAGES[@]}" -eq 0
if grep -Fq 'sim-bench-dev:latest' "$log"; then
    echo "cascade capture inspected an unrelated Compose output" >&2
    exit 1
fi
if grep -Fq 'sim-bench-retired:latest' "$log"; then
    echo "cascade capture inspected a commented Compose output" >&2
    exit 1
fi
if grep -Fq 'sim-bench-preview:latest' "$log"; then
    echo "cascade capture truncated a non-latest image tag" >&2
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
printf '%s\n' \
    'services:' \
    '  override:' \
    '    image: sim-bench-override:latest' \
    > "$compose_bench_dir/docker-compose.override.yml"
printf '%s\n' 'docker compose build' > "$compose_metadata"
PATH="$fake_bin:$PATH" FAKE_DOCKER_LOG="$log" \
FAKE_DOCKER_IMAGE_ID="$captured_image_id" \
    record_rebuilt_cascade_image sim-bench:latest simBench "$compose_metadata" "$compose_bench_dir"
test "${CASCADE_IMAGES[*]}" = "sim-bench-gene_bench:latest sim-bench-override:latest sim-bench-ui:latest"
test "${#CASCADE_IMAGE_RECORDS[@]}" -eq 3
if grep -Fq 'sim-bench-dev:latest' "$log"; then
    echo "default Compose discovery inspected an unrelated Compose output" >&2
    exit 1
fi

printf '%s\n' \
    '# docker compose -f docker-compose.dev.yml build' \
    'docker compose -f docker-compose.dev.yml down' \
    'docker compose -f docker-compose.yml build' > "$compose_metadata"
CASCADE_IMAGES=()
CASCADE_IMAGE_RECORDS=()
: > "$log"
PATH="$fake_bin:$PATH" FAKE_DOCKER_LOG="$log" \
FAKE_DOCKER_IMAGE_ID="$captured_image_id" \
    record_rebuilt_cascade_image sim-bench:latest simBench "$compose_metadata" "$compose_bench_dir"
test "${CASCADE_IMAGES[*]}" = "sim-bench-gene_bench:latest sim-bench-ui:latest"
if grep -Fq 'sim-bench-dev:latest' "$log"; then
    echo "non-build Compose metadata entered cascade capture" >&2
    exit 1
fi

printf '%s\n' \
    'SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"' \
    'COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"' \
    'docker compose -f "$COMPOSE_FILE" build' > "$compose_metadata"
CASCADE_IMAGES=()
CASCADE_IMAGE_RECORDS=()
: > "$log"
PATH="$fake_bin:$PATH" FAKE_DOCKER_LOG="$log" \
FAKE_DOCKER_IMAGE_ID="$captured_image_id" \
    record_rebuilt_cascade_image sim-bench:latest simBench "$compose_metadata" "$compose_bench_dir"
test "${CASCADE_IMAGES[*]}" = "sim-bench-gene_bench:latest sim-bench-ui:latest"
if grep -Fq 'sim-bench-dev:latest' "$log"; then
    echo "variable-backed Compose selection captured the wrong metadata" >&2
    exit 1
fi

printf '%s\n' \
    'SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"' \
    'COMPOSE_FILE="${COMPOSE_FILE:-$SCRIPT_DIR/docker-compose.yml}"' \
    'docker compose -f "$COMPOSE_FILE" build' > "$compose_metadata"
CASCADE_IMAGES=()
CASCADE_IMAGE_RECORDS=()
PATH="$fake_bin:$PATH" FAKE_DOCKER_LOG="$log" \
FAKE_DOCKER_IMAGE_ID="$captured_image_id" \
    record_rebuilt_cascade_image sim-bench:latest simBench "$compose_metadata" "$compose_bench_dir"
test "${CASCADE_IMAGES[*]}" = "sim-bench-gene_bench:latest sim-bench-ui:latest"

printf '%s\n' \
    'services:' \
    '  api:' \
    '    build: .' \
    '    image: ${API_IMAGE:-sim-bench-api}:latest' \
    > "$compose_bench_dir/docker-compose.repository-variable.yml"
printf '%s\n' 'docker compose -f docker-compose.repository-variable.yml build' > "$compose_metadata"
CASCADE_IMAGES=()
CASCADE_IMAGE_RECORDS=()
PATH="$fake_bin:$PATH" FAKE_DOCKER_LOG="$log" \
FAKE_DOCKER_IMAGE_ID="$captured_image_id" \
    record_rebuilt_cascade_image sim-bench:latest simBench "$compose_metadata" "$compose_bench_dir"
test "${CASCADE_IMAGES[*]}" = "sim-bench-api:latest"

printf '%s\n' \
    'services:' \
    '  worker:' \
    '    build: .' \
    > "$compose_bench_dir/docker-compose.generated.yml"
printf '%s\n' 'docker compose -f docker-compose.generated.yml build' > "$compose_metadata"
CASCADE_IMAGES=()
CASCADE_IMAGE_RECORDS=()
PATH="$fake_bin:$PATH" FAKE_DOCKER_LOG="$log" \
FAKE_DOCKER_IMAGE_ID="$captured_image_id" \
    record_rebuilt_cascade_image sim-bench:latest simBench "$compose_metadata" "$compose_bench_dir"
test "${CASCADE_IMAGES[*]}" = "sim-bench-worker:latest"
test "${CASCADE_IMAGE_RECORDS[*]}" = "sim-bench-worker:latest=$captured_image_id"
CASCADE_LAYER3_IMAGES=()
record_cascade_layer3_base_if_captured sim-bench:latest
test "${#CASCADE_LAYER3_IMAGES[@]}" -eq 0

printf '%s\n' \
    'services:' \
    '  api:' \
    '    build: .' \
    '  worker:' \
    '    build: .' \
    > "$compose_bench_dir/docker-compose.services.yml"
printf '%s\n' \
    'services:' \
    '  api:' \
    '    image: sim-bench-api-custom:latest' \
    > "$compose_bench_dir/docker-compose.services.override.yml"
printf '%s\n' \
    'docker compose -f docker-compose.services.yml -f docker-compose.services.override.yml -p sim-bench-ci build api' \
    > "$compose_metadata"
CASCADE_IMAGES=()
CASCADE_IMAGE_RECORDS=()
PATH="$fake_bin:$PATH" FAKE_DOCKER_LOG="$log" \
FAKE_DOCKER_IMAGE_ID="$captured_image_id" \
    record_rebuilt_cascade_image sim-bench:latest simBench "$compose_metadata" "$compose_bench_dir"
test "${CASCADE_IMAGES[*]}" = "sim-bench-api-custom:latest"
if grep -Fq 'sim-bench-ci-worker:latest' "$log"; then
    echo "Compose service selection inspected an unrequested output" >&2
    exit 1
fi

printf '%s\n' \
    'COMPOSE_PROJECT_NAME=sim-bench-ci docker compose -f docker-compose.generated.yml build worker' \
    > "$compose_metadata"
CASCADE_IMAGES=()
CASCADE_IMAGE_RECORDS=()
PATH="$fake_bin:$PATH" FAKE_DOCKER_LOG="$log" \
FAKE_DOCKER_IMAGE_ID="$captured_image_id" \
    record_rebuilt_cascade_image sim-bench:latest simBench "$compose_metadata" "$compose_bench_dir"
test "${CASCADE_IMAGES[*]}" = "sim-bench-ci-worker:latest"

CASCADE_IMAGES=(sim-bench:latest)
CASCADE_LAYER3_IMAGES=()
record_cascade_layer3_base_if_captured sim-bench:latest
record_cascade_layer3_base_if_captured sim-bench:latest
test "${CASCADE_LAYER3_IMAGES[*]}" = sim-bench:latest

printf '%s\n' \
    'services:' \
    '  variable:' \
    '    image: sim-bench-variable:${IMAGE_TAG:-latest}' \
    > "$compose_bench_dir/docker-compose.variable.yml"
printf '%s\n' 'docker compose -f docker-compose.variable.yml build' > "$compose_metadata"
CASCADE_IMAGES=()
CASCADE_IMAGE_RECORDS=()
PATH="$fake_bin:$PATH" FAKE_DOCKER_LOG="$log" \
FAKE_DOCKER_IMAGE_ID="$captured_image_id" \
    record_rebuilt_cascade_image sim-bench:latest simBench "$compose_metadata" "$compose_bench_dir"
test "${CASCADE_IMAGES[*]}" = "sim-bench-variable:latest"
test "${CASCADE_IMAGE_RECORDS[*]}" = "sim-bench-variable:latest=$captured_image_id"

first_build_dir="$temp_dir/first-build"
mkdir -p "$first_build_dir"
printf '%s\n' '#!/usr/bin/env bash' 'docker build -t first-bench:latest .' \
    > "$first_build_dir/build.sh"
PATH="$fake_bin:$PATH" FAKE_DOCKER_LOG="$log" \
FAKE_DOCKER_MISSING_IMAGE=first-bench:latest \
    capture_cascade_image_ids first-bench:latest \
        "$first_build_dir/build.sh" "$first_build_dir" \
        > "$temp_dir/first-build.records"
test ! -s "$temp_dir/first-build.records"

if PATH="$fake_bin:$PATH" FAKE_DOCKER_LOG="$log" \
    FAKE_DOCKER_IMAGE_INSPECT_FAIL=first-bench:latest \
    capture_cascade_image_ids first-bench:latest \
        "$first_build_dir/build.sh" "$first_build_dir" \
        > "$temp_dir/failed-first-build.records" 2> "$temp_dir/failed-first-build.err"; then
    echo "expected a failed pre-build image-ID inspection to fail" >&2
    exit 1
fi
grep -Fq "Could not inspect Docker image 'first-bench:latest'" "$temp_dir/failed-first-build.err"

CASCADE_IMAGES=()
CASCADE_IMAGE_RECORDS=()
printf '%s\n' 'docker compose -f docker-compose.yml build' > "$compose_metadata"
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
