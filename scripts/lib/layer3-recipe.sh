#!/usr/bin/env bash

layer3_recipe_sha256() {
    local recipe_dir="$1"
    local hash_tool
    if command -v sha256sum >/dev/null 2>&1; then
        hash_tool=sha256sum
    elif command -v shasum >/dev/null 2>&1; then
        hash_tool=shasum
    else
        echo "sha256sum or shasum is required to fingerprint the Layer 3 recipe" >&2
        return 1
    fi

    (
        cd "$recipe_dir"
        find . -type f -print \
            | LC_ALL=C sort \
            | while IFS= read -r recipe_file; do
                if [[ "$hash_tool" == sha256sum ]]; then
                    file_sha="$(sha256sum "$recipe_file" | awk '{print $1}')"
                else
                    file_sha="$(shasum -a 256 "$recipe_file" | awk '{print $1}')"
                fi
                printf '%s  %s\n' "$file_sha" "$recipe_file"
            done \
            | if [[ "$hash_tool" == sha256sum ]]; then sha256sum; else shasum -a 256; fi \
            | awk '{print $1}'
    )
}
