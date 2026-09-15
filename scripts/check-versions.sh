#!/bin/bash

# Check installed tool versions across workBench container layers
# Compares installed versions against upstream latest
# Usage: ./check-versions.sh [--layer 0|1a|1b|1c|all] [--images image,...] [--image-ids image=id,...] [--check-layer3] [--write-manifest] [--manifest-file FILE] [--json]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/image-names.sh"
# shellcheck source=lib/layer3-recipe.sh
source "$SCRIPT_DIR/lib/layer3-recipe.sh"
# shellcheck source=../base-image/ai-cli-contract.sh
. "$REPO_DIR/base-image/ai-cli-contract.sh"
# Windows shells often export USERNAME with different casing (e.g. Brett).
# Default to the actual WSL/container user; use --user for an explicit override.
USERNAME="$(whoami)"
USER_UID="$(id -u)"
USER_GID="$(id -g)"
LAYER="all"
JSON_OUTPUT=false
CHECK_LAYER3=false
WRITE_MANIFEST=false
MANIFEST_FILE="$REPO_DIR/config/version-manifest.json"
declare -a TARGET_IMAGES=()
declare -a TARGET_IMAGE_ID_RECORDS=()

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --layer) LAYER="$2"; shift 2 ;;
        --images)
            IFS=',' read -r -a TARGET_IMAGES <<< "$2"
            shift 2
            ;;
        --image-ids)
            IFS=',' read -r -a TARGET_IMAGE_ID_RECORDS <<< "$2"
            shift 2
            ;;
        --check-layer3) CHECK_LAYER3=true; shift ;;
        --write-manifest) WRITE_MANIFEST=true; shift ;;
        --manifest-file) MANIFEST_FILE="$2"; shift 2 ;;
        --json) JSON_OUTPUT=true; shift ;;
        --user) USERNAME="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 [--layer 0|1a|1b|1c|all] [--images image,...] [--image-ids image=id,...] [--check-layer3] [--write-manifest] [--manifest-file FILE] [--json] [--user USERNAME]"
            echo ""
            echo "  --images IMAGE,...  Verify required shared CLI commands in selected Layer 2 images"
            echo "  --image-ids IMAGE=ID,... Pin selected image references to captured immutable IDs"
            echo "  --check-layer3      Report Layer 3 image activation state without changing Docker state"
            echo "  --write-manifest    Persist the version manifest (default: do not write)"
            echo "  --manifest-file FILE Write inside config/ instead of the default manifest path"
            echo "  --json              Print the manifest JSON to stdout"
            echo "  WORKBENCHES_LAYER3_IDENTITY_TIMEOUT_SECONDS  Image-export timeout (default: 600)"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

manifest_config_dir="$(realpath -m -- "$REPO_DIR/config")"
manifest_target="$(realpath -m -- "$MANIFEST_FILE")"
manifest_parent="$(dirname -- "$manifest_target")"
if [[ "$manifest_parent" != "$manifest_config_dir" ]]; then
    echo "Manifest output must stay inside $manifest_config_dir" >&2
    exit 1
fi
MANIFEST_FILE="$manifest_target"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# JSON accumulator
declare -a JSON_ENTRIES=()
declare -a JSON_IMAGE_ENTRIES=()
declare -A RUNNING_CONTAINER_BY_IMAGE=()
declare -A EXPECTED_IMAGE_IDS=()
IMAGE_PROBE_FAILURES=0
LAYER3_RECIPE_SHA256="$(layer3_recipe_sha256 "$REPO_DIR/user-layer")"
LAYER3_IDENTITY_TIMEOUT_SECONDS="${WORKBENCHES_LAYER3_IDENTITY_TIMEOUT_SECONDS:-600}"
if [[ ! "$LAYER3_IDENTITY_TIMEOUT_SECONDS" =~ ^[1-9][0-9]*$ ]]; then
    echo "WORKBENCHES_LAYER3_IDENTITY_TIMEOUT_SECONDS must be a positive integer" >&2
    exit 1
fi
DOCKER_SOCKET_PATH="${WORKBENCHES_DOCKER_SOCKET_PATH:-/var/run/docker.sock}"
DOCKER_SOCKET_GID=""
if [ -S "$DOCKER_SOCKET_PATH" ]; then
    DOCKER_SOCKET_GID="$(stat -c '%g' "$DOCKER_SOCKET_PATH" 2>/dev/null || true)"
fi

for image_id_record in "${TARGET_IMAGE_ID_RECORDS[@]}"; do
    image_reference="${image_id_record%%=*}"
    expected_image_id="${image_id_record#*=}"
    if [[ -z "$image_reference" || ! "$expected_image_id" =~ ^sha256:[0-9a-fA-F]{64}$ ]]; then
        echo "Invalid --image-ids entry: $image_id_record" >&2
        exit 1
    fi
    EXPECTED_IMAGE_IDS["$image_reference"]="$expected_image_id"
done

# ========================================
# HELPERS
# ========================================

# Get latest npm package version
npm_latest() {
    local pkg="$1"
    local registry_path="$pkg"
    if [[ "$pkg" == @*/* ]]; then
        registry_path="${pkg/\//%2F}"
    fi
    curl -fsSL --connect-timeout 10 --max-time 20 "https://registry.npmjs.org/$registry_path/latest" 2>/dev/null \
        | jq -r '.version // empty' 2>/dev/null || echo "unknown"
}

# Get latest GitHub release version (strips leading 'v')
github_latest() {
    local repo="$1"
    local tag
    if tag=$(curl -fsSL --connect-timeout 10 --max-time 20 "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null \
        | jq -r '.tag_name // empty' 2>/dev/null); then
        tag="${tag#v}"
        if [ -n "$tag" ]; then
            echo "$tag"
            return 0
        fi
    fi
    echo "unknown"
}

run_with_optional_timeout() {
    local timeout_seconds="$1"
    shift

    if command -v timeout >/dev/null 2>&1; then
        timeout "${timeout_seconds}s" "$@"
    else
        "$@"
    fi
}

# Get version from inside a container
container_version() {
    local image="$1"
    local cmd="$2"
    local timeout_seconds="${CONTAINER_VERSION_TIMEOUT:-90}"
    local output
    if output=$(run_with_optional_timeout "$timeout_seconds" docker run --rm --entrypoint="" "$image" sh -c "$cmd" 2>/dev/null); then
        printf '%s\n' "$output" | head -1
    else
        echo "not installed"
    fi
}

probe_image_commands() {
    local image="$1"
    local timeout_seconds="${CONTAINER_VERSION_TIMEOUT:-90}"

    run_with_optional_timeout "$timeout_seconds" docker run --rm \
        --network none \
        --cap-drop ALL \
        --security-opt no-new-privileges \
        --read-only \
        --entrypoint="" \
        "$image" \
        sh -c '
            for command do
                command_path="$(command -v "$command" 2>/dev/null || true)"
                if [ -n "$command_path" ]; then
                    printf "ok\t%s\t%s\n" "$command" "$command_path"
                else
                    printf "missing\t%s\t\n" "$command"
                fi
            done
        ' sh "${WORKBENCHES_REQUIRED_AI_CLIS[@]}"
}

image_id() {
    docker image inspect --format '{{.Id}}' "$1" 2>/dev/null || true
}

image_created_at() {
    docker image inspect --format '{{.Created}}' "$1" 2>/dev/null || true
}

record_image() {
    local image="$1"
    local layer="$2"
    local status="$3"
    local id="${4:-}"
    if [[ -z "$id" ]]; then
        id=$(image_id "$image")
    fi
    JSON_IMAGE_ENTRIES+=("$(jq -cn \
        --arg image "$image" \
        --arg id "${id:-n/a}" \
        --arg layer "$layer" \
        --arg status "$status" \
        '{image:$image,id:$id,layer:$layer,status:$status}')")
}

snapshot_running_containers() {
    local timeout_seconds="${DOCKER_INSPECT_TIMEOUT:-30}"
    local snapshot
    local configured_image
    local container_name

    if ! snapshot=$(run_with_optional_timeout "$timeout_seconds" \
        docker container ls --format '{{.Image}}\t{{.Names}}'); then
        echo "Could not inspect running containers for Layer 3 activation state" >&2
        return 1
    fi
    while IFS=$'\t' read -r configured_image container_name; do
        [[ -n "$configured_image" && -n "$container_name" ]] || continue
        RUNNING_CONTAINER_BY_IMAGE["$configured_image"]="$container_name"
    done <<< "$snapshot"
}

# Antigravity does not currently publish through npm. Its CLI changelog exposes
# the newest available version, so use that as the upstream latest signal.
antigravity_latest() {
    local image="$1"
    container_version "$image" "agy changelog 2>/dev/null | sed -n '1{s/:$//;p;q}' || echo unknown"
}

claude_code_runnable_latest() {
    local native_latest
    native_latest=$(curl --http1.1 -fsSL --retry 2 --connect-timeout 10 --max-time 20 \
        https://downloads.claude.ai/claude-code-releases/latest 2>/dev/null || true)
    if echo "$native_latest" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+'; then
        printf '%s\n' "$native_latest"
        return 0
    fi

    curl --http1.1 -fsSL --retry 2 --connect-timeout 10 --max-time 120 \
        https://registry.npmjs.org/@anthropic-ai%2fclaude-code 2>/dev/null \
        | jq -r '.versions | to_entries[] | select(.value.bin.claude == "cli.js") | .key' 2>/dev/null \
        | sort -V \
        | tail -1
}

# Extract just the version number from a version string
extract_version() {
    echo "$1" | grep -oE '[0-9]+\.[0-9]+[0-9.]*' | head -1 | sed 's/[.]*$//'
}

version_at_least() {
    local installed="$1"
    local latest="$2"

    [ "$installed" = "$latest" ] && return 0
    [ "$(printf '%s\n%s\n' "$latest" "$installed" | sort -V | head -1)" = "$latest" ]
}

# Compare and print versions
report_tool() {
    local tool="$1"
    local installed_raw="$2"
    local latest_raw="$3"
    local layer="$4"

    local installed=$(extract_version "$installed_raw")
    local latest=$(extract_version "$latest_raw")

    if [ -z "$installed" ] || [ "$installed" = "not installed" ]; then
        installed="n/a"
    fi
    if [ -z "$latest" ]; then
        latest="unknown"
    fi

    local status="✓"
    local color="$GREEN"
    if [ "$installed" = "n/a" ]; then
        status="✗"
        color="$RED"
    elif [ "$latest" != "unknown" ] && ! version_at_least "$installed" "$latest"; then
        status="⬆"
        color="$YELLOW"
    fi

    if [ "$JSON_OUTPUT" = false ]; then
        printf "  ${color}%-3s${NC} %-25s %-18s %-18s\n" "$status" "$tool" "$installed" "$latest"
    fi

    local status_name
    status_name="$([ "$status" = "✓" ] && echo "current" || ([ "$status" = "⬆" ] && echo "outdated" || echo "missing"))"
    JSON_ENTRIES+=("$(jq -cn \
        --arg tool "$tool" \
        --arg layer "$layer" \
        --arg installed "$installed" \
        --arg latest "$latest" \
        --arg status "$status_name" \
        '{tool:$tool,layer:$layer,installed:$installed,latest:$latest,status:$status}')")
}

report_optional_tool() {
    local tool="$1"
    local installed_raw="$2"
    local latest_raw="$3"
    local layer="$4"

    local installed=$(extract_version "$installed_raw")
    local latest=$(extract_version "$latest_raw")

    if [ -z "$installed" ] || [ "$installed" = "not installed" ]; then
        installed="optional"
    fi
    if [ -z "$latest" ]; then
        latest="unknown"
    fi

    if [ "$installed" = "optional" ] && [ "$latest" = "unknown" ]; then
        if [ "$JSON_OUTPUT" = false ]; then
            printf "  ${GREEN}%-3s${NC} %-25s %-18s %-18s\n" "✓" "$tool" "$installed" "$latest"
        fi
        JSON_ENTRIES+=("$(jq -cn \
            --arg tool "$tool" \
            --arg layer "$layer" \
            --arg installed "$installed" \
            --arg latest "$latest" \
            '{tool:$tool,layer:$layer,installed:$installed,latest:$latest,status:"optional"}')")
    else
        report_tool "$tool" "$installed_raw" "$latest_raw" "$layer"
    fi
}

print_layer_header() {
    local name="$1"
    local image="$2"
    if [ "$JSON_OUTPUT" = false ]; then
        echo ""
        echo -e "${BOLD}${CYAN}═══ $name ($image) ═══${NC}"
        printf "  %-3s %-25s %-18s %-18s\n" "" "Tool" "Installed" "Latest"
        printf "  %-3s %-25s %-18s %-18s\n" "" "----" "---------" "------"
    fi
}

skip_layer() {
    local message="$1"
    if [ "$JSON_OUTPUT" = false ]; then
        echo "$message"
    else
        echo "$message" >&2
    fi
}

check_selected_image() {
    local image="$1"
    local command
    local command_path
    local probe_output
    local probe_status
    local probe_index=0
    local expected_id="${EXPECTED_IMAGE_IDS[$image]:-}"
    local probe_reference
    local passed=true

    if [[ -n "$expected_id" ]]; then
        probe_reference="$expected_id"
    else
        probe_reference="$(image_id "$image")"
        expected_id="$probe_reference"
    fi
    if [[ -z "$probe_reference" ]] || ! docker image inspect "$probe_reference" >/dev/null 2>&1; then
        echo -e "${RED}✗ Selected Layer 2 image ($image) not found${NC}" >&2
        record_image "$image" "2" "missing" "$expected_id"
        IMAGE_PROBE_FAILURES=$((IMAGE_PROBE_FAILURES + 1))
        return
    fi
    EXPECTED_IMAGE_IDS["$image"]="$expected_id"

    print_layer_header "Layer 2: Selected Bench" "$image"
    if ! probe_output=$(probe_image_commands "$probe_reference" 2>/dev/null); then
        echo -e "${RED}✗ Selected Layer 2 image ($image) could not be probed${NC}" >&2
        record_image "$image" "2" "probe-failed" "$expected_id"
        IMAGE_PROBE_FAILURES=$((IMAGE_PROBE_FAILURES + 1))
        return
    fi
    while IFS=$'\t' read -r probe_status command command_path; do
        [[ -n "$command" ]] || continue
        if [[ "$probe_index" -ge "${#WORKBENCHES_REQUIRED_AI_CLIS[@]}" \
            || "$command" != "${WORKBENCHES_REQUIRED_AI_CLIS[$probe_index]}" ]]; then
            echo -e "${RED}✗ Unexpected command probe result for $image: $command${NC}" >&2
            passed=false
            continue
        fi
        probe_index=$((probe_index + 1))
        if [[ "$probe_status" == "ok" ]]; then
            if [ "$JSON_OUTPUT" = false ]; then
                printf "  ${GREEN}%-3s${NC} %-25s %s\n" "✓" "$command" "$command_path"
            fi
        elif [[ "$probe_status" == "missing" ]]; then
            printf "  ${RED}%-3s${NC} %-25s missing\n" "✗" "$command" >&2
            passed=false
        else
            echo -e "${RED}✗ Invalid command probe status for $image: $probe_status${NC}" >&2
            passed=false
        fi
    done <<< "$probe_output"
    if [[ "$probe_index" -ne "${#WORKBENCHES_REQUIRED_AI_CLIS[@]}" ]]; then
        echo -e "${RED}✗ Incomplete command probe results for $image${NC}" >&2
        passed=false
    fi

    if [ "$passed" = true ]; then
        record_image "$image" "2" "verified" "$expected_id"
    else
        record_image "$image" "2" "missing-required-cli" "$expected_id"
        IMAGE_PROBE_FAILURES=$((IMAGE_PROBE_FAILURES + 1))
    fi
}

check_selected_images() {
    local image

    for image in "${TARGET_IMAGES[@]}"; do
        [[ -n "$image" ]] || continue
        check_selected_image "$image"
    done
}

layer3_identity_is_current() {
    local image="$1"
    local image_username
    local image_uid
    local image_gid
    local image_docker_gid
    local -a pipeline_status

    image_username="$(docker image inspect --format '{{ index .Config.Labels "io.opensoft.workbenches.layer3.username" }}' "$image" 2>/dev/null || true)"
    image_uid="$(docker image inspect --format '{{ index .Config.Labels "io.opensoft.workbenches.layer3.uid" }}' "$image" 2>/dev/null || true)"
    image_gid="$(docker image inspect --format '{{ index .Config.Labels "io.opensoft.workbenches.layer3.gid" }}' "$image" 2>/dev/null || true)"
    image_docker_gid="$(docker image inspect --format '{{ index .Config.Labels "io.opensoft.workbenches.layer3.docker-socket-gid" }}' "$image" 2>/dev/null || true)"

    [[ "$image_username" == "$USERNAME" \
        && "$image_uid" == "$USER_UID" \
        && "$image_gid" == "$USER_GID" ]] || return 1
    if [[ -n "$DOCKER_SOCKET_GID" && "$image_docker_gid" != "$DOCKER_SOCKET_GID" ]]; then
        return 1
    fi

    run_with_optional_timeout "$LAYER3_IDENTITY_TIMEOUT_SECONDS" \
        docker image save "$image" 2>/dev/null \
        | python3 "$SCRIPT_DIR/lib/check-image-identity.py" \
            "$USERNAME" "$USER_UID" "$USER_GID" "$DOCKER_SOCKET_GID"
    pipeline_status=("${PIPESTATUS[@]}")
    if [[ "${pipeline_status[0]}" -ne 0 ]]; then
        return 2
    fi
    return "${pipeline_status[1]}"
}

check_layer3_image() {
    local base_image="$1"
    local base_image_id="${EXPECTED_IMAGE_IDS[$base_image]:-$base_image}"
    local user_image="${base_image%:*}:${USERNAME}"
    local running_container
    local base_created
    local user_created
    local user_image_id
    local user_recipe
    local identity_status=0

    running_container="${RUNNING_CONTAINER_BY_IMAGE[$user_image]:-}"
    if [[ -n "$running_container" ]]; then
        if [ "$JSON_OUTPUT" = false ]; then
            echo -e "${YELLOW}↷ Layer 3 $user_image activation deferred by running container '$running_container'${NC}"
        fi
        record_image "$user_image" "3" "activation-deferred-running"
        return
    fi

    user_image_id="$(image_id "$user_image")"
    if [[ -z "$user_image_id" ]]; then
        if [ "$JSON_OUTPUT" = false ]; then
            echo -e "${YELLOW}↷ Layer 3 $user_image is missing; activation has not occurred${NC}"
        fi
        record_image "$user_image" "3" "activation-missing"
        return
    fi

    base_created=$(image_created_at "$base_image_id")
    user_created=$(image_created_at "$user_image_id")
    user_recipe="$(docker image inspect --format '{{ index .Config.Labels "io.opensoft.workbenches.layer3.recipe-sha256" }}' "$user_image_id" 2>/dev/null || true)"
    if [[ "$user_recipe" != "$LAYER3_RECIPE_SHA256" ]]; then
        if [ "$JSON_OUTPUT" = false ]; then
            echo -e "${YELLOW}↷ Layer 3 $user_image has a stale recipe; activation is required${NC}"
        fi
        record_image "$user_image" "3" "activation-stale" "$user_image_id"
    elif [[ -z "$base_created" || -z "$user_created" \
        || "$user_created" < "$base_created" || "$user_created" == "$base_created" ]]; then
        if [ "$JSON_OUTPUT" = false ]; then
            echo -e "${YELLOW}↷ Layer 3 $user_image is older than $base_image; activation is required${NC}"
        fi
        record_image "$user_image" "3" "activation-stale" "$user_image_id"
    else
        layer3_identity_is_current "$user_image_id" || identity_status=$?
        case "$identity_status" in
            0)
                if [ "$JSON_OUTPUT" = false ]; then
                    echo -e "${GREEN}✓ Layer 3 $user_image is current${NC}"
                fi
                record_image "$user_image" "3" "current" "$user_image_id"
                ;;
            1)
                if [ "$JSON_OUTPUT" = false ]; then
                    echo -e "${YELLOW}↷ Layer 3 $user_image has stale user/group configuration; activation is required${NC}"
                fi
                record_image "$user_image" "3" "activation-stale" "$user_image_id"
                ;;
            *)
                echo "Could not inspect Layer 3 identity for $user_image; activation state is unknown" >&2
                record_image "$user_image" "3" "activation-inspection-failed" "$user_image_id"
                IMAGE_PROBE_FAILURES=$((IMAGE_PROBE_FAILURES + 1))
                ;;
        esac
    fi
}

check_selected_layer3_images() {
    local image

    [ "$CHECK_LAYER3" = true ] || return 0
    snapshot_running_containers
    for image in "${TARGET_IMAGES[@]}"; do
        [[ -n "$image" ]] || continue
        check_layer3_image "$image"
    done
}

# ========================================
# LAYER 0: workbench-base
# ========================================

check_layer0() {
    local image="workbench-base:latest"

    if ! docker image inspect "$image" >/dev/null 2>&1; then
        skip_layer "  Layer 0 image ($image) not found — skipping"
        return
    fi

    print_layer_header "Layer 0: System Base" "$image"

    report_tool "git" \
        "$(container_version "$image" "git --version")" \
        "$(github_latest "git/git")" \
        "0"

    report_tool "gh" \
        "$(container_version "$image" "gh --version")" \
        "$(github_latest "cli/cli")" \
        "0"

    report_tool "vim" \
        "$(container_version "$image" "vim --version | head -1")" \
        "$(github_latest "vim/vim")" \
        "0"

    report_tool "neovim" \
        "$(container_version "$image" "nvim --version | head -1")" \
        "$(github_latest "neovim/neovim")" \
        "0"

    report_tool "yq" \
        "$(container_version "$image" "yq --version")" \
        "$(github_latest "mikefarah/yq")" \
        "0"

    report_tool "zoxide" \
        "$(container_version "$image" "zoxide --version")" \
        "$(github_latest "ajeetdsouza/zoxide")" \
        "0"

    report_tool "uv" \
        "$(container_version "$image" "uv --version")" \
        "$(github_latest "astral-sh/uv")" \
        "0"

    report_tool "fzf" \
        "$(container_version "$image" "fzf --version")" \
        "$(github_latest "junegunn/fzf")" \
        "0"

    report_tool "jq" \
        "$(container_version "$image" "jq --version")" \
        "$(github_latest "jqlang/jq")" \
        "0"

    report_tool "tldr" \
        "$(container_version "$image" "node -p 'require(\"/usr/lib/node_modules/tldr/package.json\").version' 2>/dev/null || tldr --version 2>/dev/null || echo n/a")" \
        "$(npm_latest "tldr")" \
        "0"

    # AI CLIs (installed in Layer 0 for all benches)
    report_tool "claude-code" \
        "$(container_version "$image" "claude --version 2>/dev/null || echo n/a")" \
        "$(claude_code_runnable_latest)" \
        "0"

    report_tool "codex" \
        "$(container_version "$image" "codex --version 2>/dev/null || echo n/a")" \
        "$(npm_latest "@openai/codex")" \
        "0"

    report_tool "antigravity-cli" \
        "$(container_version "$image" "agy --version 2>/dev/null || echo n/a")" \
        "n/a" \
        "0"

    report_optional_tool "agy" \
        "$(container_version "$image" "agy --version 2>/dev/null || echo n/a")" \
        "$(antigravity_latest "$image")" \
        "0"

    report_tool "copilot" \
        "$(container_version "$image" "copilot --version 2>/dev/null || github-copilot-cli --version 2>/dev/null || echo n/a")" \
        "$(npm_latest "@github/copilot")" \
        "0"

    report_tool "letta-code" \
        "$(container_version "$image" "letta --version 2>/dev/null || echo n/a")" \
        "$(npm_latest "@letta-ai/letta-code")" \
        "0"
}

# ========================================
# LAYER 1a: dev-bench-base
# ========================================

check_layer1a() {
    local image
    image=$(resolve_existing_image "$(family_base_image dev)" "$(legacy_family_base_image dev 2>/dev/null || true)" || true)

    if [ -z "$image" ]; then
        skip_layer "  Layer 1a image ($image) not found — skipping"
        return
    fi

    print_layer_header "Layer 1a: Developer Base" "$image"

    # AI CLIs are inherited from Layer 0, only check dev-specific tools here

    report_tool "python3" \
        "$(container_version "$image" "python3 --version")" \
        "$(github_latest "python/cpython")" \
        "1a"

    report_tool "node" \
        "$(container_version "$image" "node --version")" \
        "$(curl -s https://nodejs.org/dist/index.json 2>/dev/null | jq -r '[.[] | select(.lts != false)][0].version // empty' 2>/dev/null)" \
        "1a"

    report_tool "npm" \
        "$(container_version "$image" "npm --version")" \
        "$(npm_latest "npm")" \
        "1a"

    report_tool "bun" \
        "$(container_version "$image" "bun --version 2>/dev/null || echo n/a")" \
        "$(github_latest "oven-sh/bun")" \
        "1a"

    report_tool "yarn" \
        "$(container_version "$image" "yarn --version 2>/dev/null || echo n/a")" \
        "$(npm_latest "yarn")" \
        "1a"

    report_tool "gt" \
        "$(container_version "$image" "gt --version 2>/dev/null || echo n/a")" \
        "$(npm_latest "@withgraphite/graphite-cli")" \
        "1a"

    report_tool "spec-kit" \
        "$(container_version "$image" "specify --version 2>/dev/null || uv tool list 2>/dev/null | grep specify-cli | head -1 || echo n/a")" \
        "$(github_latest "github/spec-kit")" \
        "1a"

    report_tool "openspec" \
        "$(container_version "$image" "openspec --version 2>/dev/null || echo n/a")" \
        "$(npm_latest "@fission-ai/openspec")" \
        "1a"
}

# ========================================
# LAYER 1b: sys-bench-base
# ========================================

check_layer1b() {
    local image
    image=$(resolve_existing_image "$(family_base_image sys)" "$(legacy_family_base_image sys 2>/dev/null || true)" || true)

    if [ -z "$image" ]; then
        skip_layer "  Layer 1b image ($image) not found — skipping"
        return
    fi

    print_layer_header "Layer 1b: Sys/DevOps Base" "$image"

    report_tool "terraform" \
        "$(container_version "$image" "terraform version | head -1")" \
        "$(github_latest "hashicorp/terraform")" \
        "1b"

    report_tool "tofu" \
        "$(container_version "$image" "tofu version | head -1")" \
        "$(github_latest "opentofu/opentofu")" \
        "1b"

    report_tool "kubectl" \
        "$(container_version "$image" "kubectl version --client 2>/dev/null | head -1")" \
        "$(curl -sL https://dl.k8s.io/release/stable.txt 2>/dev/null | sed 's/^v//')" \
        "1b"

    report_tool "helm" \
        "$(container_version "$image" "helm version --short")" \
        "$(github_latest "helm/helm")" \
        "1b"

    report_tool "k9s" \
        "$(container_version "$image" "k9s version --short 2>/dev/null || k9s version | head -1")" \
        "$(github_latest "derailed/k9s")" \
        "1b"

    report_tool "stern" \
        "$(container_version "$image" "stern --version")" \
        "$(github_latest "stern/stern")" \
        "1b"

    report_tool "aws-cli" \
        "$(container_version "$image" "aws --version")" \
        "$(github_latest "aws/aws-cli")" \
        "1b"

    report_tool "az" \
        "$(container_version "$image" "az version 2>/dev/null | jq -r '.\"azure-cli\"' 2>/dev/null || echo n/a")" \
        "$(github_latest "Azure/azure-cli")" \
        "1b"

    report_tool "gcloud" \
        "$(container_version "$image" "gcloud version 2>/dev/null | head -1")" \
        "unknown" \
        "1b"

    report_tool "ansible" \
        "$(container_version "$image" "python3 -m pip show ansible 2>/dev/null | awk '/^Version:/{print \$2}' || ansible --version | head -1")" \
        "$(pip index versions ansible 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo unknown)" \
        "1b"

    report_tool "promtool" \
        "$(container_version "$image" "promtool --version 2>&1 | head -1")" \
        "$(github_latest "prometheus/prometheus")" \
        "1b"

    report_tool "lazydocker" \
        "$(container_version "$image" "lazydocker --version")" \
        "$(github_latest "jesseduffield/lazydocker")" \
        "1b"
}

# ========================================
# LAYER 1c: bio-bench-base
# ========================================

check_layer1c() {
    local image
    image=$(resolve_existing_image "$(family_base_image bio)" "$(legacy_family_base_image bio 2>/dev/null || true)" || true)

    if [ -z "$image" ]; then
        skip_layer "  Layer 1c image ($image) not found — skipping"
        return
    fi

    print_layer_header "Layer 1c: Bio Base" "$image"

    report_tool "conda" \
        "$(container_version "$image" "conda --version")" \
        "$(github_latest "conda/conda")" \
        "1c"
}

# ========================================
# MAIN
# ========================================

if [ "$JSON_OUTPUT" = false ]; then
    echo "=========================================="
    echo "workBenches Version Check"
    echo "=========================================="
    echo "User: $USERNAME"
    echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
fi

case "$LAYER" in
    0)   check_layer0 ;;
    1a)  check_layer1a ;;
    1b)  check_layer1b ;;
    1c)  check_layer1c ;;
    all)
        check_layer0
        check_layer1a
        check_layer1b
        check_layer1c
        ;;
    *)
        echo "Unknown layer: $LAYER"
        echo "Usage: $0 [--layer 0|1a|1b|1c|all]"
        exit 1
        ;;
esac

check_selected_images
check_selected_layer3_images

# Count outdated
outdated_count=0
for entry in "${JSON_ENTRIES[@]}"; do
    if echo "$entry" | grep -q '"status":"outdated"'; then
        outdated_count=$((outdated_count + 1))
    fi
done

if [ "$JSON_OUTPUT" = false ]; then
    echo ""
    echo -e "${BOLD}Summary:${NC} ${#JSON_ENTRIES[@]} tools checked, ${outdated_count} outdated, ${#JSON_IMAGE_ENTRIES[@]} images recorded"
    if [ "$outdated_count" -gt 0 ]; then
        echo -e "${YELLOW}Run scripts/update-and-rebuild.sh to update outdated layers${NC}"
    fi
fi

render_manifest() {
    local tools_json
    local images_json

    tools_json="$(printf '%s\n' "${JSON_ENTRIES[@]}" | jq -s '.')"
    images_json="$(printf '%s\n' "${JSON_IMAGE_ENTRIES[@]}" | jq -s '.')"
    jq -n \
        --arg checked_at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        --arg user "$USERNAME" \
        --argjson tools "$tools_json" \
        --argjson images "$images_json" \
        '{checked_at:$checked_at,user:$user,tools:$tools,images:$images}'
}

if [ "$WRITE_MANIFEST" = true ]; then
    manifest_temp="$(mktemp "$manifest_config_dir/.version-manifest.XXXXXX")"
    if ! render_manifest > "$manifest_temp" || ! mv -f -- "$manifest_temp" "$MANIFEST_FILE"; then
        rm -f -- "$manifest_temp"
        echo "Could not atomically write the version manifest" >&2
        exit 1
    fi
    if [ "$JSON_OUTPUT" = false ]; then
        echo ""
        echo "Version manifest written to ${MANIFEST_FILE#$REPO_DIR/}"
    fi
fi

if [ "$JSON_OUTPUT" = true ]; then
    render_manifest
fi

if [ "$IMAGE_PROBE_FAILURES" -gt 0 ]; then
    exit 1
fi
