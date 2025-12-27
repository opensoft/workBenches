#!/bin/bash
# Build Layer 2 (cloud-bench)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

USERNAME=${1:-$(whoami)}
if [ "$USERNAME" = "--user" ]; then
    USERNAME="${2:-$(whoami)}"
fi

exec "${SCRIPT_DIR}/build-layer2.sh" --user "$USERNAME"
