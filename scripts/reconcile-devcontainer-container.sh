#!/bin/bash
# Remove a stale devcontainer service container when its backing image has been
# deleted or no longer matches the expected bench image tag.

set -euo pipefail

CONTAINER_NAME=""
EXPECTED_IMAGE=""
EXPECTED_PROJECT=""
EXPECTED_SERVICE=""
REPLACE_EXISTING=false

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
        --project)
            EXPECTED_PROJECT="${2:-}"
            shift 2
            ;;
        --service)
            EXPECTED_SERVICE="${2:-}"
            shift 2
            ;;
        --replace-existing)
            REPLACE_EXISTING=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 --container <name> --image <image:tag> [--project <compose-project> --service <compose-service>] [--replace-existing]"
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

if [[ "$REPLACE_EXISTING" == true ]]; then
    echo "Removing existing devcontainer '$CONTAINER_NAME' (${CURRENT_CONFIG_IMAGE}) so the caller can recreate it"
    docker rm -f "$CONTAINER_NAME" >/dev/null
    exit 0
fi

if [[ -n "$EXPECTED_PROJECT" || -n "$EXPECTED_SERVICE" ]]; then
    CURRENT_PROJECT="$(docker inspect --format '{{ index .Config.Labels "com.docker.compose.project" }}' "$CONTAINER_NAME" 2>/dev/null || true)"
    CURRENT_SERVICE="$(docker inspect --format '{{ index .Config.Labels "com.docker.compose.service" }}' "$CONTAINER_NAME" 2>/dev/null || true)"
    CURRENT_PROJECT="${CURRENT_PROJECT//<no value>/}"
    CURRENT_SERVICE="${CURRENT_SERVICE//<no value>/}"

    PROJECT_MATCH=true
    SERVICE_MATCH=true
    if [[ -n "$EXPECTED_PROJECT" && "$CURRENT_PROJECT" != "$EXPECTED_PROJECT" ]]; then
        PROJECT_MATCH=false
    fi
    if [[ -n "$EXPECTED_SERVICE" && "$CURRENT_SERVICE" != "$EXPECTED_SERVICE" ]]; then
        SERVICE_MATCH=false
    fi

    if [[ "$PROJECT_MATCH" != true || "$SERVICE_MATCH" != true ]]; then
        echo "Removing existing devcontainer '$CONTAINER_NAME' (${CURRENT_CONFIG_IMAGE}): not managed by expected compose service '${EXPECTED_PROJECT}/${EXPECTED_SERVICE}'"
        docker rm -f "$CONTAINER_NAME" >/dev/null
        exit 0
    fi
fi

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
