#!/usr/bin/env bash

image_id_if_present() {
    docker image inspect --format '{{.Id}}' "$1" 2>/dev/null || true
}

record_rebuilt_cascade_image() {
    local image="$1"
    local bench_name="$2"
    local image_repo="${image%:*}"
    local produced_image
    local current_image_id
    local found=false

    # A Compose bench can publish several service images under the normalized
    # bench prefix (for example sim-bench-gene_bench:latest). Discover the
    # actual post-build references instead of assuming one basename tag.
    while IFS= read -r produced_image; do
        [[ -n "$produced_image" ]] || continue
        current_image_id="$(image_id_if_present "$produced_image")"
        [[ -n "$current_image_id" ]] || continue
        CASCADE_IMAGES+=("$produced_image")
        CASCADE_IMAGE_RECORDS+=("$produced_image=$current_image_id")
        found=true
    done < <(
        docker image ls --format '{{.Repository}}:{{.Tag}}' 2>/dev/null \
            | awk -v repo="$image_repo" '
                $0 == repo ":latest" || (index($0, repo "-") == 1 && $0 ~ /:latest$/)
            ' \
            | LC_ALL=C sort -u
    )

    if [ "$found" = false ]; then
        echo "Expected Layer 2 image $image was not produced by $bench_name" >&2
        return 1
    fi
}
