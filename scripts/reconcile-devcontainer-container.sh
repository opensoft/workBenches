#!/bin/bash
# Remove a stale devcontainer service container when its backing image has been
# deleted or no longer matches the expected bench image tag.

set -euo pipefail

CONTAINER_NAME=""
EXPECTED_IMAGE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --container)
            CONTAINER_NAME="${2:-}"
            shift 2
            ;;
        --image)
            EXPECTED_IMAGE="${2:-}"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 --container <name> --image <image:tag>"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

if [[ -z "$CONTAINER_NAME" || -z "$EXPECTED_IMAGE" ]]; then
    echo "Both --container and --image are required." >&2
    exit 1
fi

if ! docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
    exit 0
fi

if ! docker image inspect "$EXPECTED_IMAGE" >/dev/null 2>&1; then
    echo "Expected image '$EXPECTED_IMAGE' is not available." >&2
    exit 1
fi

CURRENT_IMAGE_ID="$(docker inspect --format '{{.Image}}' "$CONTAINER_NAME")"
CURRENT_CONFIG_IMAGE="$(docker inspect --format '{{.Config.Image}}' "$CONTAINER_NAME")"
EXPECTED_IMAGE_ID="$(docker image inspect --format '{{.Id}}' "$EXPECTED_IMAGE")"

REMOVE_REASON=""
if ! docker image inspect "$CURRENT_IMAGE_ID" >/dev/null 2>&1; then
    REMOVE_REASON="backing image '$CURRENT_IMAGE_ID' no longer exists locally"
elif [[ "$CURRENT_IMAGE_ID" != "$EXPECTED_IMAGE_ID" ]]; then
    REMOVE_REASON="container image '$CURRENT_IMAGE_ID' does not match expected '$EXPECTED_IMAGE_ID'"
fi

if [[ -z "$REMOVE_REASON" ]]; then
    exit 0
fi

echo "Removing stale devcontainer '$CONTAINER_NAME' (${CURRENT_CONFIG_IMAGE}): $REMOVE_REASON"
docker rm -f "$CONTAINER_NAME" >/dev/null
