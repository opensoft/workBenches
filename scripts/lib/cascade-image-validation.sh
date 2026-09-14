#!/usr/bin/env bash

image_id_if_present() {
    docker image inspect --format '{{.Id}}' "$1" 2>/dev/null || true
}

record_rebuilt_cascade_image() {
    local image="$1"
    local bench_name="$2"
    local current_image_id

    current_image_id="$(image_id_if_present "$image")"
    if [[ -z "$current_image_id" ]]; then
        echo "Expected Layer 2 image $image was not produced by $bench_name" >&2
        return 1
    fi
    CASCADE_IMAGES+=("$image")
    CASCADE_IMAGE_RECORDS+=("$image=$current_image_id")
}
