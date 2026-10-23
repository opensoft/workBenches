#!/usr/bin/env bash

layer3_harness_selection() {
    local repo=${1:-} selection key mode bytes content
    [[ "$repo" =~ ^[a-z0-9][a-z0-9-]*$ ]] || return 0
    selection="$HOME/.config/workbenches/harnesses/benches/$repo.list"
    [[ -e "$selection" || -L "$selection" ]] || return 0
    [[ -f "$selection" && ! -L "$selection" && -O "$selection" ]] || { echo 'Invalid private bench harness selection' >&2; return 1; }
    local parent
    for parent in "$HOME/.config" "$HOME/.config/workbenches" "$HOME/.config/workbenches/harnesses" "$HOME/.config/workbenches/harnesses/benches"; do
        [[ -d "$parent" && ! -L "$parent" && -O "$parent" ]] || return 1
    done
    mode=$(stat -c '%a' "$selection" 2>/dev/null) || mode=$(stat -f '%Lp' "$selection") || return 1
    [[ "$mode" =~ ^[0-7]+$ ]] && (( (8#$mode & 077) == 0 )) || return 1
    bytes=$(wc -c < "$selection"); ((bytes <= 16384)) || return 1
    if IFS= read -r -d '' content < "$selection"; then return 1; fi
    [[ -z "$content" || "$content" == *$'\n' ]] || return 1
    local -A seen=()
    source "$(dirname "${BASH_SOURCE[0]}")/setup-tool-catalog.generated.sh"
    while IFS= read -r key || [[ -n "$key" ]]; do
        [[ "$key" =~ ^[a-z][a-z0-9_]*$ && -n "${setup_managed_harnesses[$key]:-}" && -z "${seen[$key]:-}" ]] || return 1
        seen[$key]=true
    done < "$selection"
    ((${#seen[@]} == 0)) || printf '%s\n' "${!seen[@]}" | LC_ALL=C sort
}

layer3_recipe_sha256() {
    local recipe_dir="$1"
    local hash_tool recipe_hash selection
    if (($# >= 3)); then selection=$3; else selection=$(layer3_harness_selection "${2:-}") || return 1; fi
    if command -v sha256sum >/dev/null 2>&1; then
        hash_tool=sha256sum
    elif command -v shasum >/dev/null 2>&1; then
        hash_tool=shasum
    else
        echo "sha256sum or shasum is required to fingerprint the Layer 3 recipe" >&2
        return 1
    fi

    recipe_hash=$(
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
    ) || return 1
    if [[ -z "$selection" ]]; then printf '%s\n' "$recipe_hash"
    else printf '%s\n%s\n' "$recipe_hash" "$selection" | if [[ "$hash_tool" == sha256sum ]]; then sha256sum; else shasum -a 256; fi | awk '{print $1}'; fi
}
