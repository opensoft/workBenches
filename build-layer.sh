#!/bin/bash
# Build Layer 0 (workbench-base:latest, user-agnostic)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec "${SCRIPT_DIR}/base-image/build.sh"
