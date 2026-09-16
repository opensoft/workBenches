#!/usr/bin/env bash

image_id_if_present() {
    local image="$1"
    local output

    if output="$(docker image inspect --format '{{.Id}}' "$image" 2>&1)"; then
        if [[ -z "$output" ]]; then
            echo "Docker returned an empty image ID for '$image'" >&2
            return 2
        fi
        printf '%s\n' "$output"
        return 0
    fi

    case "$output" in
        *"No such image"*|*"No such object"*) return 1 ;;
        *)
            echo "Could not inspect Docker image '$image'${output:+: $output}" >&2
            return 2
            ;;
    esac
}

select_layer2_build_script() {
    local bench_dir="$1"
    local candidate

    for candidate in \
        "$bench_dir/build-layer2.sh" \
        "$bench_dir/scripts/build-layer2.sh"; do
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

compose_build_commands() {
    local build_script="$1"
    awk '
        function emit(command, count, segment_index, word_count, word_index, subcommand, segment, words) {
            sub(/^[[:space:]]+/, "", command)
            if (command ~ /^#/) return
            sub(/[[:space:]]+#.*/, "", command)
            count = split(command, segments, /[;&|]+/)
            for (segment_index = 1; segment_index <= count; segment_index++) {
                segment = segments[segment_index]
                gsub(/[()]/, " ", segment)
                sub(/^[[:space:]]+/, "", segment)
                sub(/[[:space:]]+$/, "", segment)
                word_count = split(segment, words, /[[:space:]]+/)
                for (word_index = 1; word_index < word_count; word_index++) {
                    if (words[word_index] == "docker" \
                            && words[word_index + 1] == "compose") {
                        for (subcommand = word_index + 2; subcommand <= word_count; subcommand++) {
                            if (words[subcommand] ~ /^(build|config|cp|create|down|events|exec|images|kill|logs|ls|pause|port|ps|pull|push|restart|rm|run|start|stop|top|unpause|up|version|wait|watch)$/) {
                                if (words[subcommand] == "build") print segment
                                break
                            }
                        }
                        break
                    }
                }
            }
        }
        {
            command = command $0
            if (command ~ /\\$/) {
                sub(/\\$/, " ", command)
                next
            }
            emit(command)
            command = ""
        }
        END { if (command != "") emit(command) }
    ' "$build_script"
}

compose_command_files() {
    local command="$1"
    local expect_file=false
    local token
    local value
    local -a words=()

    read -r -a words <<< "$command"
    for token in "${words[@]}"; do
        if [[ "$expect_file" = true ]]; then
            value="$token"
            expect_file=false
        else
            case "$token" in
                -f|--file)
                    expect_file=true
                    continue
                    ;;
                -f=*|--file=*)
                    value="${token#*=}"
                    ;;
                *)
                    continue
                    ;;
            esac
        fi
        value="${value#\"}"
        value="${value%\"}"
        value="${value#\'}"
        value="${value%\'}"
        printf '%s\n' "$value"
    done
}

build_uses_default_compose_file() {
    local build_script="$1"
    local command
    local selected_file

    while IFS= read -r command; do
        selected_file="$(compose_command_files "$command")"
        if [[ -z "$selected_file" ]]; then
            return 0
        fi
    done < <(compose_build_commands "$build_script")
    return 1
}

static_shell_assignment() {
    local build_script="$1"
    local variable_name="$2"

    [[ "$variable_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 1
    awk -v variable_name="$variable_name" '
        {
            line = $0
            sub(/^[[:space:]]+/, "", line)
            if (line ~ /^#/) next
            sub(/[[:space:]]+#.*/, "", line)
            prefix = "^((export|local|readonly)[[:space:]]+)?" variable_name "="
            if (line ~ prefix) {
                sub(prefix, "", line)
                value = line
            }
        }
        END { if (value != "") print value }
    ' "$build_script"
}

resolve_compose_file_argument() {
    local selected_file="$1"
    local build_script="$2"
    local build_dir
    local variable_name
    local default_value
    local suffix
    local replacement
    local iteration

    build_dir="$(dirname "$build_script")"
    for iteration in 1 2 3 4 5 6; do
        variable_name=""
        default_value=""
        suffix=""
        if [[ "$selected_file" =~ ^\$\{([A-Za-z_][A-Za-z0-9_]*):-([^\}]+)\}(.*)$ ]]; then
            variable_name="${BASH_REMATCH[1]}"
            default_value="${BASH_REMATCH[2]}"
            suffix="${BASH_REMATCH[3]}"
        elif [[ "$selected_file" =~ ^\$\{([A-Za-z_][A-Za-z0-9_]*)\}(.*)$ ]]; then
            variable_name="${BASH_REMATCH[1]}"
            suffix="${BASH_REMATCH[2]}"
        elif [[ "$selected_file" =~ ^\$([A-Za-z_][A-Za-z0-9_]*)(/.*)?$ ]]; then
            variable_name="${BASH_REMATCH[1]}"
            suffix="${BASH_REMATCH[2]:-}"
        else
            break
        fi
        if [[ -n "$default_value" ]]; then
            if [[ -n "${!variable_name+x}" && -n "${!variable_name}" ]]; then
                replacement="${!variable_name}"
            else
                replacement="$default_value"
            fi
        elif [[ "$variable_name" == "SCRIPT_DIR" ]]; then
            replacement="$build_dir"
        else
            replacement="$(static_shell_assignment "$build_script" "$variable_name")"
            [[ -n "$replacement" ]] || return 1
            replacement="${replacement#\"}"
            replacement="${replacement%\"}"
            replacement="${replacement#\'}"
            replacement="${replacement%\'}"
        fi
        selected_file="$replacement$suffix"
    done
    [[ "$selected_file" != *'$'* && "$selected_file" != *'`'* ]] || return 1
    printf '%s\n' "$selected_file"
}

compose_generated_build_images() {
    local compose_file="$1"
    local default_project="$2"

    awk -v default_project="$default_project" '
        function flush_service() {
            if (service != "" && has_build && !has_image) {
                print project "-" service ":latest"
            }
            service = ""
            has_build = 0
            has_image = 0
        }
        BEGIN { project = default_project; in_services = 0; service_indent = -1 }
        {
            raw = $0
            sub(/[[:space:]]+#.*/, "", raw)
            if (raw ~ /^[[:space:]]*$/) next
            match(raw, /^[[:space:]]*/)
            indent = RLENGTH
            line = raw
            sub(/^[[:space:]]+/, "", line)
            sub(/[[:space:]]+$/, "", line)
            if (indent == 0 && line ~ /^name:[[:space:]]*/) {
                candidate = line
                sub(/^name:[[:space:]]*/, "", candidate)
                gsub(/^["\047]|["\047]$/, "", candidate)
                if (candidate ~ /^[a-z0-9][a-z0-9_-]*$/) project = candidate
                next
            }
            if (indent == 0 && line == "services:") {
                in_services = 1
                next
            }
            if (indent == 0) {
                flush_service()
                in_services = 0
                next
            }
            if (!in_services) next
            if (line ~ /^[A-Za-z0-9_.-]+:[[:space:]]*$/ \
                    && (service_indent < 0 || indent <= service_indent)) {
                flush_service()
                service = line
                sub(/:.*/, "", service)
                service_indent = indent
                next
            }
            if (service != "" && indent > service_indent) {
                if (line ~ /^build:([[:space:]]|$)/) has_build = 1
                if (line ~ /^image:([[:space:]]|$)/) has_image = 1
            }
        }
        END { flush_service() }
    ' "$compose_file"
}

build_selects_compose_file() {
    local build_script="$1"
    local compose_file="$2"
    local build_dir
    local command
    local selected_file
    local selected_path

    build_dir="$(dirname "$build_script")"
    compose_file="$(realpath -m -- "$compose_file")"

    while IFS= read -r command; do
        while IFS= read -r selected_file; do
            selected_file="$(resolve_compose_file_argument \
                "$selected_file" "$build_script")" || continue
            if [[ "$selected_file" == /* ]]; then
                selected_path="$(realpath -m -- "$selected_file")"
            else
                selected_path="$(realpath -m -- "$build_dir/$selected_file")"
            fi
            if [[ "$selected_path" == "$compose_file" ]]; then
                return 0
            fi
        done < <(compose_command_files "$command")
    done < <(compose_build_commands "$build_script")
    return 1
}

declared_cascade_images() {
    local image="$1"
    local build_script="${2:-}"
    local bench_dir="${3:-}"
    local image_repo="${image%:*}"
    local -a metadata_files=()
    local -a compose_files=()

    [[ -f "$build_script" ]] && metadata_files+=("$build_script")
    if [[ -f "$build_script" && -d "$bench_dir" ]]; then
        local build_dir
        local compose_dir
        local default_compose_name
        local default_compose_file=""
        local override_compose_name
        local override_prefix
        build_dir="$(dirname "$build_script")"
        if build_uses_default_compose_file "$build_script"; then
            for compose_dir in "$build_dir" "$bench_dir"; do
                for default_compose_name in \
                    compose.yaml compose.yml docker-compose.yaml docker-compose.yml; do
                    if [[ -f "$compose_dir/$default_compose_name" ]]; then
                        default_compose_file="$compose_dir/$default_compose_name"
                        metadata_files+=("$default_compose_file")
                        compose_files+=("$default_compose_file")
                        break 2
                    fi
                done
            done
            if [[ -n "$default_compose_file" ]]; then
                case "$(basename "$default_compose_file")" in
                    compose.*) override_prefix="compose.override" ;;
                    docker-compose.*) override_prefix="docker-compose.override" ;;
                esac
                for override_compose_name in \
                    "$override_prefix.yaml" "$override_prefix.yml"; do
                    if [[ -f "$(dirname "$default_compose_file")/$override_compose_name" ]]; then
                        metadata_files+=("$(dirname "$default_compose_file")/$override_compose_name")
                        compose_files+=("$(dirname "$default_compose_file")/$override_compose_name")
                        break
                    fi
                done
            fi
        fi
        while IFS= read -r -d '' compose_file; do
            if build_selects_compose_file "$build_script" "$compose_file"; then
                metadata_files+=("$compose_file")
                compose_files+=("$compose_file")
            fi
        done < <(find "$bench_dir" -maxdepth 3 -type f \
            \( -name 'compose*.yml' -o -name 'compose*.yaml' \
                -o -name 'docker-compose*.yml' -o -name 'docker-compose*.yaml' \) \
            -print0 2>/dev/null)
    fi

    # A Compose bench can publish several service images (for example
    # sim-bench-gene_bench:latest). Limit discovery to references declared by
    # the selected build script/Compose files so an unrelated pre-existing
    # daemon image cannot enter the cascade result merely by sharing a prefix.
    {
        if [[ "${#metadata_files[@]}" -gt 0 ]]; then
            awk '
                {
                    line = $0
                    sub(/^[[:space:]]+/, "", line)
                    if (line ~ /^#/) next
                    sub(/[[:space:]]+#.*/, "", line)
                    working = line
                    while (match(working, /[A-Za-z0-9][A-Za-z0-9._\/-]*:latest([^A-Za-z0-9_.-]|$)/)) {
                        ref = substr(working, RSTART, RLENGTH)
                        if (ref !~ /:latest$/) ref = substr(ref, 1, length(ref) - 1)
                        print ref
                        working = substr(working, RSTART + RLENGTH)
                    }
                    working = line
                    while (match(working, /[A-Za-z0-9][A-Za-z0-9._\/-]*:[$][{]USER:-[^}]+[}]/)) {
                        ref = substr(working, RSTART, RLENGTH)
                        sub(/:.*/, ":latest", ref)
                        print ref
                        working = substr(working, RSTART + RLENGTH)
                    }
                    working = line
                    while (match(working, /[A-Za-z0-9][A-Za-z0-9._\/-]*:[$][{][A-Za-z_][A-Za-z0-9_]*:-latest[}]/)) {
                        ref = substr(working, RSTART, RLENGTH)
                        sub(/:.*/, ":latest", ref)
                        print ref
                        working = substr(working, RSTART + RLENGTH)
                    }
                }
                /^[[:space:]]*image:[[:space:]]*/ {
                    ref = line
                    sub(/^[[:space:]]*image:[[:space:]]*/, "", ref)
                    gsub(/^[[:space:]]+/, "", ref)
                    gsub(/[[:space:]]+$/, "", ref)
                    quote = sprintf("%c", 39)
                    if ((substr(ref, 1, 1) == "\"" && substr(ref, length(ref), 1) == "\"") \
                        || (substr(ref, 1, 1) == quote && substr(ref, length(ref), 1) == quote)) {
                        ref = substr(ref, 2, length(ref) - 2)
                    }
                    while (match(ref, /[$][{][A-Za-z_][A-Za-z0-9_]*:-[A-Za-z0-9._\/-]+[}]/)) {
                        expression = substr(ref, RSTART, RLENGTH)
                        inner = substr(expression, 3, length(expression) - 3)
                        separator = index(inner, ":-")
                        variable_name = substr(inner, 1, separator - 1)
                        fallback = substr(inner, separator + 2)
                        replacement = ENVIRON[variable_name]
                        if (replacement == "") replacement = fallback
                        ref = substr(ref, 1, RSTART - 1) replacement substr(ref, RSTART + RLENGTH)
                    }
                    leaf = ref
                    sub(/^.*\//, "", leaf)
                    if (ref ~ /^[A-Za-z0-9][A-Za-z0-9._:\/-]*$/) {
                        if (leaf ~ /:latest$/) print ref
                        else if (leaf !~ /:/) print ref ":latest"
                    }
                }
            ' "${metadata_files[@]}" 2>/dev/null || true
        fi
        if [[ "${#compose_files[@]}" -gt 0 ]]; then
            local compose_file
            local compose_project
            compose_project="$(basename "$bench_dir" \
                | tr '[:upper:]' '[:lower:]' \
                | sed -E 's/[^a-z0-9_-]+/-/g; s/^[^a-z0-9]+//')"
            for compose_file in "${compose_files[@]}"; do
                compose_generated_build_images "$compose_file" "$compose_project"
            done
        fi
    } | awk -v repo="$image_repo" '
        $0 == repo ":latest" || (index($0, repo "-") == 1 && $0 ~ /:latest$/)
    ' | LC_ALL=C sort -u
}

capture_cascade_image_ids() {
    local image="$1"
    local build_script="${2:-}"
    local bench_dir="${3:-}"
    local declared_image
    local image_id
    local inspect_status
    local found=false

    while IFS= read -r declared_image; do
        [[ -n "$declared_image" ]] || continue
        found=true
        if image_id="$(image_id_if_present "$declared_image")"; then
            printf '%s=%s\n' "$declared_image" "$image_id"
        else
            inspect_status=$?
            [[ "$inspect_status" -eq 1 ]] || return "$inspect_status"
        fi
    done < <(declared_cascade_images "$image" "$build_script" "$bench_dir")
    if [[ "$found" = false ]]; then
        if image_id="$(image_id_if_present "$image")"; then
            printf '%s=%s\n' "$image" "$image_id"
        else
            inspect_status=$?
            [[ "$inspect_status" -eq 1 ]] || return "$inspect_status"
        fi
    fi
    return 0
}

record_rebuilt_cascade_image() {
    local image="$1"
    local bench_name="$2"
    local build_script="${3:-}"
    local bench_dir="${4:-}"
    local prebuild_image_records="${5:-}"
    local produced_image
    local current_image_id
    local inspect_status
    local prior_image
    local prior_id
    local prior_image_id
    local found=false
    local missing=false
    local stale=false
    local -a declared_images=()

    mapfile -t declared_images < <(declared_cascade_images "$image" "$build_script" "$bench_dir")
    if [[ "${#declared_images[@]}" -eq 0 ]]; then
        declared_images=("$image")
    fi

    for produced_image in "${declared_images[@]}"; do
        if current_image_id="$(image_id_if_present "$produced_image")"; then
            :
        else
            inspect_status=$?
            if [[ "$inspect_status" -eq 1 ]]; then
                echo "Declared Layer 2 image $produced_image was not produced by $bench_name" >&2
                missing=true
                continue
            fi
            return "$inspect_status"
        fi
        prior_image_id=""
        while IFS='=' read -r prior_image prior_id; do
            if [[ "$prior_image" == "$produced_image" ]]; then
                prior_image_id="$prior_id"
                break
            fi
        done <<< "$prebuild_image_records"
        if [[ -n "$prior_image_id" && "$current_image_id" == "$prior_image_id" ]]; then
            echo "Declared Layer 2 image $produced_image was not refreshed by $bench_name" >&2
            stale=true
            continue
        fi
        CASCADE_IMAGES+=("$produced_image")
        CASCADE_IMAGE_RECORDS+=("$produced_image=$current_image_id")
        found=true
    done

    if [ "$missing" = true ] || [ "$stale" = true ] || [ "$found" = false ]; then
        echo "Expected Layer 2 image $image was not produced by $bench_name" >&2
        return 1
    fi
}
