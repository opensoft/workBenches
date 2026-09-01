#!/usr/bin/env bash
# Refresh a stopped bench's user image and remove a stale container so the
# caller can recreate it. Running benches are always left untouched.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CONTAINER_NAME=""
BASE_IMAGE=""
USERNAME="$(id -un 2>/dev/null || whoami)"
EXTRA_CHOWN=""
EXPECTED_PROJECT=""
EXPECTED_SERVICE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --container) CONTAINER_NAME="${2:-}"; shift 2 ;;
        --base) BASE_IMAGE="${2:-}"; shift 2 ;;
        --user) USERNAME="${2:-}"; shift 2 ;;
        --chown) EXTRA_CHOWN="${2:-}"; shift 2 ;;
        --project) EXPECTED_PROJECT="${2:-}"; shift 2 ;;
        --service) EXPECTED_SERVICE="${2:-}"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 --container NAME --base IMAGE:latest [--user NAME] [--chown \"DIRS\"] [--project NAME] [--service NAME]"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

if [[ -z "$CONTAINER_NAME" || -z "$BASE_IMAGE" ]]; then
    echo "Both --container and --base are required." >&2
    exit 1
fi

if docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
    if [[ "$(docker container inspect --format '{{.State.Running}}' "$CONTAINER_NAME")" == "true" ]]; then
        echo "prepare-bench-start: '$CONTAINER_NAME' is running; leaving its container and Layer 3 image unchanged"
        exit 0
    fi
fi

ensure_args=(--base "$BASE_IMAGE" --user "$USERNAME")
if [[ -n "$EXTRA_CHOWN" ]]; then
    ensure_args+=(--chown "$EXTRA_CHOWN")
fi
"$SCRIPT_DIR/ensure-layer3.sh" "${ensure_args[@]}"

reconcile_args=(
    --container "$CONTAINER_NAME"
    --image "${BASE_IMAGE%%:*}:$USERNAME"
)
if [[ -n "$EXPECTED_PROJECT" ]]; then
    reconcile_args+=(--project "$EXPECTED_PROJECT")
fi
if [[ -n "$EXPECTED_SERVICE" ]]; then
    reconcile_args+=(--service "$EXPECTED_SERVICE")
fi
"$SCRIPT_DIR/reconcile-devcontainer-container.sh" "${reconcile_args[@]}"
