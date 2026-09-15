#!/usr/bin/env bash

image_id_if_present() {
    docker image inspect --format '{{.Id}}' "$1" 2>/dev/null || true
}

build_uses_default_compose_file() {
    local build_script="$1"
    local command
    local trimmed
    local compose_command_pattern='(^|[[:space:];&|()])docker[[:space:]]+compose([[:space:]]|$)'
    local compose_file_pattern='(^|[[:space:]])(-f|--file)(=|[[:space:]])'

    while IFS= read -r command; do
        trimmed="${command#"${command%%[![:space:]]*}"}"
        [[ "$trimmed" == \#* ]] && continue
        if [[ "$command" =~ $compose_command_pattern \
            && ! "$command" =~ $compose_file_pattern ]]; then
            return 0
        fi
    done < <(awk '
        {
            command = command $0
            if (command ~ /\\$/) {
                sub(/\\$/, " ", command)
                next
            }
            print command
            command = ""
        }
        END { if (command != "") print command }
    ' "$build_script")
    return 1
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
        local compose_dir
        local default_compose_name
        build_dir="$(dirname "$build_script")"
        if build_uses_default_compose_file "$build_script"; then
            for compose_dir in "$build_dir" "$bench_dir"; do
                for default_compose_name in \
                    compose.yaml compose.yml docker-compose.yaml docker-compose.yml; do
                    if [[ -f "$compose_dir/$default_compose_name" ]]; then
                        metadata_files+=("$compose_dir/$default_compose_name")
                        break 2
                    fi
                done
            done
        fi
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
            awk '
                /^[[:space:]]*image:[[:space:]]*/ {
                    ref = $0
                    sub(/^[[:space:]]*image:[[:space:]]*/, "", ref)
                    sub(/[[:space:]]+#.*/, "", ref)
                    gsub(/^[[:space:]]+/, "", ref)
                    gsub(/[[:space:]]+$/, "", ref)
                    quote = sprintf("%c", 39)
                    if ((substr(ref, 1, 1) == "\"" && substr(ref, length(ref), 1) == "\"") \
                        || (substr(ref, 1, 1) == quote && substr(ref, length(ref), 1) == quote)) {
                        ref = substr(ref, 2, length(ref) - 2)
                    }
                    leaf = ref
                    sub(/^.*\//, "", leaf)
                    if (ref ~ /^[A-Za-z0-9][A-Za-z0-9._:\/-]*$/ && leaf !~ /:/) {
                        print ref ":latest"
                    }
                }
            ' "${metadata_files[@]}" 2>/dev/null || true
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
