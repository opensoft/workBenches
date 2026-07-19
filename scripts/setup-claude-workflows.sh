#!/usr/bin/env bash
# Install workBenches-managed Claude workflow files into the user profile.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKBENCHES_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_DIR="$WORKBENCHES_ROOT/config/claude/workflows"
TARGET_DIR="$HOME/.claude/workflows"

if [ ! -d "$SOURCE_DIR" ]; then
    echo "No Claude workflow source directory found: $SOURCE_DIR"
    exit 0
fi

mkdir -p "$TARGET_DIR"

installed=0
kept=0

while IFS= read -r -d '' source_file; do
    workflow_name="$(basename "$source_file")"
    target_file="$TARGET_DIR/$workflow_name"

    if [ -e "$target_file" ] || [ -L "$target_file" ]; then
        echo "Claude workflow already exists, leaving unchanged: $target_file"
        kept=$((kept + 1))
        continue
    fi

    install -m 0644 "$source_file" "$target_file"
    echo "Installed Claude workflow: $target_file"
    installed=$((installed + 1))
done < <(find "$SOURCE_DIR" -maxdepth 1 -type f -name '*.js' -print0 | sort -z)

echo "Claude workflows: $installed installed, $kept already present"
