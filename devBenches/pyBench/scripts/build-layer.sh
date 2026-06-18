#!/bin/bash
# Build Layer 2 and ensure Layer 3 (py-bench)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"

USERNAME=${1:-$(whoami)}
if [ "$USERNAME" = "--user" ]; then
    USERNAME="${2:-$(whoami)}"
fi

if docker image inspect "py-bench:latest" >/dev/null 2>&1; then
    echo "Layer 2 image py-bench:latest already exists; skipping rebuild."
else
    "${SCRIPT_DIR}/build-layer2.sh" --user "$USERNAME"
fi

exec "${REPO_DIR}/scripts/ensure-layer3.sh" --base "py-bench:latest" --user "$USERNAME"
