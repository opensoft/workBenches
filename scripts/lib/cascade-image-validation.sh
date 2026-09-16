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

strip_shell_quotes() {
    local value="$1"
    value="${value#\"}"
    value="${value%\"}"
    value="${value#\'}"
    value="${value%\'}"
    printf '%s\n' "$value"
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

compose_config_images_for_command() {
    local command="$1"
    local build_script="$2"
    local bench_dir="${3:-}"
    local build_dir
    local docker_index=-1
    local build_index=-1
    local index
    local token
    local value
    local variable_name
    local resolved
    local compose_json
    local selected_json
    local output
    local service_options=false
    local -a words=()
    local -a compose_args=()
    local -a compose_env=()
    local -a services=()

    build_dir="$(dirname "$build_script")"
    if [[ -n "$bench_dir" \
        && "$(realpath -m -- "$build_dir")" == "$(realpath -m -- "$bench_dir/scripts")" ]]; then
        build_dir="$bench_dir"
    fi
    read -r -a words <<< "$command"

    for ((index = 0; index + 1 < ${#words[@]}; index++)); do
        if [[ "${words[index]}" == docker && "${words[index + 1]}" == compose ]]; then
            docker_index=$index
            break
        fi
    done
    ((docker_index >= 0)) || return 1

    # Preserve simple command-prefix assignments such as
    # COMPOSE_PROJECT_NAME=sim-bench-ci without evaluating shell code.
    for ((index = 0; index < docker_index; index++)); do
        token="${words[index]}"
        if [[ "$token" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] \
            && [[ "$token" != *'`'* && "$token" != *'$('* ]]; then
            variable_name="${token%%=*}"
            value="$(strip_shell_quotes "${token#*=}")"
            [[ "$value" != *'$'* ]] || return 1
            if [[ "$variable_name" == COMPOSE_PROJECT_NAME ]]; then
                [[ "$value" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || return 1
            fi
            compose_env+=("$variable_name=$value")
        fi
    done

    index=$((docker_index + 2))
    while ((index < ${#words[@]})); do
        token="${words[index]}"
        if [[ "$token" == build ]]; then
            build_index=$index
            break
        fi
        case "$token" in
            -f|--file|--env-file|--project-directory)
                ((index++))
                ((index < ${#words[@]})) || return 1
                value="$(strip_shell_quotes "${words[index]}")"
                resolved="$(resolve_compose_file_argument "$value" "$build_script")" \
                    || return 1
                if [[ "$resolved" != /* ]]; then
                    resolved="$(realpath -m -- "$build_dir/$resolved")"
                fi
                compose_args+=("$token" "$resolved")
                ;;
            -f=*|--file=*|--env-file=*|--project-directory=*)
                value="${token#*=}"
                value="$(strip_shell_quotes "$value")"
                resolved="$(resolve_compose_file_argument "$value" "$build_script")" \
                    || return 1
                if [[ "$resolved" != /* ]]; then
                    resolved="$(realpath -m -- "$build_dir/$resolved")"
                fi
                compose_args+=("${token%%=*}=$resolved")
                ;;
            -p|--project-name|--profile|--ansi|--parallel|--progress)
                ((index++))
                ((index < ${#words[@]})) || return 1
                value="$(strip_shell_quotes "${words[index]}")"
                if [[ "$token" == -p || "$token" == --project-name ]]; then
                    value="$(resolve_compose_file_argument "$value" "$build_script")" \
                        || return 1
                    [[ "$value" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || return 1
                fi
                compose_args+=("$token" "$value")
                ;;
            --project-name=*|--profile=*|--ansi=*|--parallel=*|--progress=*)
                value="$(strip_shell_quotes "${token#*=}")"
                if [[ "$token" == --project-name=* ]]; then
                    value="$(resolve_compose_file_argument "$value" "$build_script")" \
                        || return 1
                    [[ "$value" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || return 1
                fi
                compose_args+=("${token%%=*}=$value")
                ;;
            --compatibility|--dry-run)
                compose_args+=("$token")
                ;;
            *)
                echo "Unsupported Docker Compose build prefix in '$command': $token" >&2
                return 1
                ;;
        esac
        ((index++))
    done
    ((build_index >= 0)) || return 1

    for ((index = build_index + 1; index < ${#words[@]}; index++)); do
        token="${words[index]}"
        if [[ "$service_options" == true ]]; then
            value="$(strip_shell_quotes "$token")"
            [[ "$value" =~ ^[A-Za-z0-9_.-]+$ ]] || return 1
            services+=("$value")
            continue
        fi
        case "$token" in
            --)
                service_options=true
                ;;
            --build-arg|--builder|-m|--memory|--progress|--provenance|--sbom|--ssh)
                ((index++))
                ((index < ${#words[@]})) || return 1
                ;;
            --build-arg=*|--builder=*|--memory=*|--progress=*|--provenance=*|--sbom=*|--ssh=*|-[mq]*)
                ;;
            --with-dependencies)
                echo "Cannot safely derive Compose dependency build outputs from '$command'" >&2
                return 1
                ;;
            --check|--no-cache|--pull|--push|-q|--quiet)
                ;;
            -*)
                echo "Unsupported Docker Compose build option in '$command': $token" >&2
                return 1
                ;;
            *)
                value="$(strip_shell_quotes "$token")"
                [[ "$value" =~ ^[A-Za-z0-9_.-]+$ ]] || return 1
                services+=("$value")
                ;;
        esac
    done

    if ! compose_json="$(
        cd "$build_dir"
        env "${compose_env[@]}" docker compose "${compose_args[@]}" \
            config --format json
    )"; then
        echo "Could not resolve Compose outputs for '$command'" >&2
        return 1
    fi
    selected_json="$(printf '%s\n' "${services[@]}" \
        | jq -Rsc 'split("\n") | map(select(length > 0))')"
    if ! output="$(jq -r --argjson selected "$selected_json" '
        (.services // {}) as $services
        | if ($selected | length) > 0 and any($selected[];
                (($services[.] // {}) | (.build // null)) == null)
            then error("selected Compose service is not buildable")
            else .
          end
        | .name as $project
        | [
            $services
            | to_entries[]
            | select((.value.build // null) != null)
            | .key as $service
            | select(($selected | length) == 0 or ($selected | index($service)) != null)
            | (.value.image // ($project + "-" + $service))
          ]
        | if length == 0 then error("Compose command has no buildable services") else .[] end
    ' <<< "$compose_json")"; then
        echo "Could not derive buildable Compose outputs for '$command'" >&2
        return 1
    fi

    while IFS= read -r value; do
        [[ -n "$value" ]] || continue
        value="$(strip_shell_quotes "$value")"
        if [[ "$value" =~ ^[A-Za-z0-9][A-Za-z0-9._:/-]*$ ]]; then
            local leaf="${value##*/}"
            if [[ "$leaf" != *:* ]]; then
                value+=":latest"
            fi
            printf '%s\n' "$value"
        fi
    done <<< "$output"
}

declared_cascade_images() {
    local image="$1"
    local build_script="${2:-}"
    local bench_dir="${3:-}"
    local image_repo="${image%:*}"

    # A Compose bench can publish several service images (for example
    # sim-bench-gene_bench:latest). Docker build tags come only from the selected
    # build script. Compose outputs come from Compose's fully merged model for
    # each build command, preserving file order, project selection, automatic
    # overrides, and any selected services.
    {
        if [[ -f "$build_script" ]]; then
            awk '
                function resolve_defaults(ref, expression, inner, separator, variable_name, fallback, replacement) {
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
                    return ref
                }
                function resolve_static_reference(ref, variable_name, replacement, iteration) {
                    for (iteration = 1; iteration <= 6; iteration++) {
                        variable_name = ""
                        if (ref ~ /^[$][A-Za-z_][A-Za-z0-9_]*$/) {
                            variable_name = substr(ref, 2)
                        } else if (ref ~ /^[$][{][A-Za-z_][A-Za-z0-9_]*[}]$/) {
                            variable_name = substr(ref, 3, length(ref) - 3)
                        } else {
                            break
                        }
                        replacement = assignments[variable_name]
                        if (replacement == "") replacement = ENVIRON[variable_name]
                        if (replacement == "") break
                        gsub(/^["\047]|["\047]$/, "", replacement)
                        ref = replacement
                    }
                    return ref
                }
                function emit_output(ref, leaf) {
                    gsub(/^["\047]|["\047\\]+$/, "", ref)
                    ref = resolve_static_reference(ref)
                    if (ref ~ /:[$][{]USER:-[^}]+[}]$/) {
                        sub(/:[$][{]USER:-[^}]+[}]$/, ":latest", ref)
                    }
                    if (ref ~ /:[$][{][A-Za-z_][A-Za-z0-9_]*:-latest[}]$/) {
                        sub(/:[$][{][A-Za-z_][A-Za-z0-9_]*:-latest[}]$/, ":latest", ref)
                    }
                    ref = resolve_defaults(ref)
                    leaf = ref
                    sub(/^.*\//, "", leaf)
                    if (ref ~ /^[A-Za-z0-9][A-Za-z0-9._:\/-]*$/) {
                        if (leaf ~ /:latest$/) print ref
                        else if (leaf !~ /:/) print ref ":latest"
                    }
                }
                {
                    line = $0
                    sub(/^[[:space:]]+/, "", line)
                    if (line ~ /^#/) next
                    sub(/[[:space:]]+#.*/, "", line)
                    assignment = line
                    sub(/^(export|local|readonly)[[:space:]]+/, "", assignment)
                    if (assignment ~ /^[A-Za-z_][A-Za-z0-9_]*=/) {
                        variable_name = assignment
                        sub(/=.*/, "", variable_name)
                        assignment = substr(assignment, length(variable_name) + 2)
                        if (assignment !~ /[[:space:]]/) {
                            assignments[variable_name] = assignment
                        }
                    }
                    word_count = split(line, words, /[[:space:]]+/)
                    for (word_index = 1; word_index <= word_count; word_index++) {
                        if (words[word_index] == "-t" || words[word_index] == "--tag") {
                            if (word_index < word_count) emit_output(words[word_index + 1])
                        } else if (words[word_index] ~ /^(-t|--tag)=/) {
                            ref = words[word_index]
                            sub(/^[^=]*=/, "", ref)
                            emit_output(ref)
                        }
                    }
                }
            ' "$build_script" 2>/dev/null || true
        fi
        if [[ -f "$build_script" ]]; then
            local compose_command
            while IFS= read -r compose_command; do
                compose_config_images_for_command \
                    "$compose_command" "$build_script" "$bench_dir" \
                    || return
            done < <(compose_build_commands "$build_script")
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
    local declared_images

    declared_images="$(declared_cascade_images "$image" "$build_script" "$bench_dir")" \
        || return
    while IFS= read -r declared_image; do
        [[ -n "$declared_image" ]] || continue
        found=true
        if image_id="$(image_id_if_present "$declared_image")"; then
            printf '%s=%s\n' "$declared_image" "$image_id"
        else
            inspect_status=$?
            [[ "$inspect_status" -eq 1 ]] || return "$inspect_status"
        fi
    done <<< "$declared_images"
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
    local declared_image_output
    local -a declared_images=()

    declared_image_output="$(declared_cascade_images "$image" "$build_script" "$bench_dir")" \
        || return
    if [[ -n "$declared_image_output" ]]; then
        mapfile -t declared_images <<< "$declared_image_output"
    fi
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

record_cascade_layer3_base_if_captured() {
    local layer2_base="$1"
    local captured_image
    local existing_image

    for captured_image in "${CASCADE_IMAGES[@]}"; do
        [[ "$captured_image" == "$layer2_base" ]] || continue
        for existing_image in "${CASCADE_LAYER3_IMAGES[@]}"; do
            [[ "$existing_image" == "$layer2_base" ]] && return 0
        done
        CASCADE_LAYER3_IMAGES+=("$layer2_base")
        return 0
    done
}
