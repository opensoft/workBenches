#!/usr/bin/env bash

image_id_if_present() {
    docker image inspect --format '{{.Id}}' "$1" 2>/dev/null || true
}

record_rebuilt_cascade_image() {
    local image="$1"
    local bench_name="$2"
    local build_script="${3:-}"
    local bench_dir="${4:-}"
    local image_repo="${image%:*}"
    local produced_image
    local current_image_id
    local found=false
    local missing=false
    local -a metadata_files=()
    local -a declared_images=()

    [[ -f "$build_script" ]] && metadata_files+=("$build_script")
    if [[ -f "$build_script" && -d "$bench_dir" ]]; then
        local build_dir
        local compose_relative_to_bench
        local compose_relative_to_build
        build_dir="$(dirname "$build_script")"
        while IFS= read -r -d '' compose_file; do
            compose_relative_to_bench="$(realpath --relative-to="$bench_dir" "$compose_file")"
            compose_relative_to_build="$(realpath --relative-to="$build_dir" "$compose_file")"
            if grep -Fq -- "$compose_relative_to_bench" "$build_script" \
                || grep -Fq -- "$compose_relative_to_build" "$build_script"; then
                metadata_files+=("$compose_file")
            fi
        done < <(find "$bench_dir" -maxdepth 3 -type f \
            \( -name 'compose.yml' -o -name 'compose.yaml' \
                -o -name 'docker-compose.yml' -o -name 'docker-compose.yaml' \) \
            -print0 2>/dev/null)
    fi

    # A Compose bench can publish several service images (for example
    # sim-bench-gene_bench:latest). Limit discovery to references declared by
    # the selected build script/Compose files so an unrelated pre-existing
    # daemon image cannot enter the cascade result merely by sharing a prefix.
    mapfile -t declared_images < <({
        if [[ "${#metadata_files[@]}" -gt 0 ]]; then
            grep -Eho '[A-Za-z0-9][A-Za-z0-9._/-]*:latest' "${metadata_files[@]}" 2>/dev/null || true
            grep -Eho '[A-Za-z0-9][A-Za-z0-9._/-]*:\$\{USER:-[^}]+\}' "${metadata_files[@]}" 2>/dev/null \
                | sed 's/:.*/:latest/' || true
        fi
    } | awk -v repo="$image_repo" '
        $0 == repo ":latest" || (index($0, repo "-") == 1 && $0 ~ /:latest$/)
    ' | LC_ALL=C sort -u)
    if [[ "${#declared_images[@]}" -eq 0 ]]; then
        declared_images=("$image")
    fi

    for produced_image in "${declared_images[@]}"; do
        current_image_id="$(image_id_if_present "$produced_image")"
        if [[ -z "$current_image_id" ]]; then
            echo "Declared Layer 2 image $produced_image was not produced by $bench_name" >&2
            missing=true
            continue
        fi
        CASCADE_IMAGES+=("$produced_image")
        CASCADE_IMAGE_RECORDS+=("$produced_image=$current_image_id")
        found=true
    done

    if [ "$missing" = true ] || [ "$found" = false ]; then
        echo "Expected Layer 2 image $image was not produced by $bench_name" >&2
        return 1
    fi
}
