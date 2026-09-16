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
    local destination_parent
    local stage_dir=""
    local backup_dir=""
    local link_stage=""

    cursor_source="$(readlink -f -- "$cursor_launcher")" || return 1
    cursor_bundle_dir="$(dirname -- "$cursor_source")"
    if [ ! -x "$cursor_source" ] \
        || [ ! -x "$cursor_bundle_dir/node" ] \
        || [ ! -f "$cursor_bundle_dir/index.js" ]; then
        return 1
    fi

    destination_parent="$(dirname -- "$destination")"
    if ! install -d -m 0755 "$destination_parent" "$(dirname -- "$global_launcher")"; then
        return 1
    fi
    stage_dir="$(mktemp -d "${destination}.stage.XXXXXX")" || return 1
    if ! cp -a "$cursor_bundle_dir"/. "$stage_dir"/ \
        || ! install -m 0755 "$cursor_source" "$stage_dir/cursor-agent" \
        || ! chmod -R a+rX "$stage_dir" \
        || [ ! -x "$stage_dir/cursor-agent" ] \
        || [ ! -x "$stage_dir/node" ] \
        || [ ! -f "$stage_dir/index.js" ]; then
        rm -rf -- "$stage_dir"
        return 1
    fi

    if [ -e "$destination" ] || [ -L "$destination" ]; then
        backup_dir="$(mktemp -d "${destination}.backup.XXXXXX")" || {
            rm -rf -- "$stage_dir"
            return 1
        }
        if ! rmdir -- "$backup_dir" || ! mv -T -- "$destination" "$backup_dir"; then
            rm -rf -- "$stage_dir" "$backup_dir"
            return 1
        fi
    fi
    if ! mv -T -- "$stage_dir" "$destination"; then
        if [ -n "$backup_dir" ]; then
            mv -T -- "$backup_dir" "$destination" || true
        fi
        rm -rf -- "$stage_dir"
        return 1
    fi
    stage_dir=""

    link_stage="$(mktemp "$(dirname -- "$global_launcher")/.cursor-agent-link.XXXXXX")" || {
        rm -rf -- "$destination"
        if [ -n "$backup_dir" ]; then
            mv -T -- "$backup_dir" "$destination" || true
        fi
        return 1
    }
    if ! rm -f -- "$link_stage" \
        || ! ln -s -- "$destination/cursor-agent" "$link_stage" \
        || ! mv -Tf -- "$link_stage" "$global_launcher"; then
        rm -f -- "$link_stage"
        rm -rf -- "$destination"
        if [ -n "$backup_dir" ]; then
            mv -T -- "$backup_dir" "$destination" || true
        fi
        return 1
    fi
    link_stage=""
    if [ -n "$backup_dir" ] && ! rm -rf -- "$backup_dir"; then
        return 1
    fi

    # The native installer keeps a versioned copy under root's home. Once the
    # complete shared bundle and launcher are published, remove only that safely
    # confined duplicate. A publication failure always leaves this source intact.
    case "$cursor_bundle_dir" in
        "$managed_versions_root"/*)
            rm -f -- "$managed_bin_dir/agent" "$managed_bin_dir/cursor-agent" \
                || return 1
            rm -rf -- "$cursor_bundle_dir" || return 1
            ;;
    esac
    return 0
}
