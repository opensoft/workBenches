#!/usr/bin/env bash

# Publish Cursor's self-contained launcher bundle to a stable system path.
# Optional paths keep the helper independently testable without touching the
# host filesystem.
publish_cursor_bundle() {
    local cursor_launcher="$1"
    local destination="${2:-/opt/cursor-agent}"
    local global_launcher="${3:-/usr/local/bin/cursor-agent}"
    local managed_versions_root="${4:-$HOME/.local/share/cursor-agent/versions}"
    local managed_bin_dir="${5:-$HOME/.local/bin}"
    local cursor_source
    local cursor_bundle_dir

    cursor_source="$(readlink -f -- "$cursor_launcher")"
    cursor_bundle_dir="$(dirname -- "$cursor_source")"
    if [ ! -x "$cursor_source" ] \
        || [ ! -x "$cursor_bundle_dir/node" ] \
        || [ ! -f "$cursor_bundle_dir/index.js" ]; then
        return 1
    fi

    rm -rf -- "$destination"
    install -d -m 0755 "$destination" "$(dirname -- "$global_launcher")"
    cp -a "$cursor_bundle_dir"/. "$destination"/
    install -m 0755 "$cursor_source" "$destination/cursor-agent"
    chmod -R a+rX "$destination"
    ln -sfn "$destination/cursor-agent" "$global_launcher"

    # The native installer keeps a versioned copy under root's home. Once the
    # shared bundle is verified, remove only that safely confined duplicate.
    case "$cursor_bundle_dir" in
        "$managed_versions_root"/*)
            rm -f -- "$managed_bin_dir/agent" "$managed_bin_dir/cursor-agent"
            rm -rf -- "$cursor_bundle_dir"
            ;;
    esac
}
