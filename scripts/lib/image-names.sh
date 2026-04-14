#!/bin/bash

# Canonical Docker image naming helpers for workBenches.
# Family base images use kebab-case for consistency with bench images.
# Legacy aliases remain available during the migration window.

WORKBENCH_BASE_REPO="workbench-base"
DEV_BENCH_BASE_REPO="dev-bench-base"
SYS_BENCH_BASE_REPO="sys-bench-base"
BIO_BENCH_BASE_REPO="bio-bench-base"

image_ref() {
    local repo="$1"
    local tag="${2:-latest}"
    printf '%s:%s\n' "$repo" "$tag"
}

family_base_repo() {
    case "$1" in
        workbench|0) printf '%s\n' "$WORKBENCH_BASE_REPO" ;;
        dev|1a) printf '%s\n' "$DEV_BENCH_BASE_REPO" ;;
        sys|1b) printf '%s\n' "$SYS_BENCH_BASE_REPO" ;;
        bio|1c) printf '%s\n' "$BIO_BENCH_BASE_REPO" ;;
        *)
            echo "Unknown bench family: $1" >&2
            return 1
            ;;
    esac
}

legacy_family_base_repo() {
    case "$1" in
        workbench|0) return 0 ;;
        dev|1a) printf '%s\n' "devbench-base" ;;
        sys|1b) printf '%s\n' "sysbench-base" ;;
        bio|1c) printf '%s\n' "biobench-base" ;;
        *)
            echo "Unknown bench family: $1" >&2
            return 1
            ;;
    esac
}

family_base_image() {
    image_ref "$(family_base_repo "$1")" "${2:-latest}"
}

family_base_state_key() {
    family_base_repo "$1"
}

legacy_family_base_image() {
    local repo
    repo=$(legacy_family_base_repo "$1") || return 1
    if [ -z "$repo" ]; then
        return 0
    fi
    image_ref "$repo" "${2:-latest}"
}

legacy_family_base_state_key() {
    legacy_family_base_repo "$1"
}

legacy_family_base_user_image() {
    local repo
    repo=$(legacy_family_base_repo "$1") || return 1
    if [ -z "$repo" ] || [ -z "${2:-}" ]; then
        return 0
    fi
    image_ref "$repo" "$2"
}

resolve_existing_image() {
    local image
    for image in "$@"; do
        if [ -n "$image" ] && docker image inspect "$image" >/dev/null 2>&1; then
            printf '%s\n' "$image"
            return 0
        fi
    done
    return 1
}

tag_family_base_legacy_alias() {
    local family="$1"
    local tag="${2:-latest}"
    local canonical_image
    local legacy_image

    canonical_image=$(family_base_image "$family" "$tag")
    legacy_image=$(legacy_family_base_image "$family" "$tag" 2>/dev/null || true)

    if [ -n "$legacy_image" ]; then
        docker tag "$canonical_image" "$legacy_image"
    fi
}

resolve_family_base_image() {
    local family="$1"
    local username="${2:-}"

    resolve_existing_image \
        "$(family_base_image "$family")" \
        "$(legacy_family_base_image "$family" 2>/dev/null || true)" \
        "$(legacy_family_base_user_image "$family" "$username" 2>/dev/null || true)"
}

bench_dir_to_image_repo() {
    local bench_dir_name="$1"

    case "$bench_dir_name" in
        dotNetBench) printf '%s\n' "dotnet-bench" ;;
        *)
            printf '%s\n' "$bench_dir_name" | perl -pe 's/([a-z0-9])([A-Z])/$1-$2/g; $_ = lc($_);'
            ;;
    esac
}
