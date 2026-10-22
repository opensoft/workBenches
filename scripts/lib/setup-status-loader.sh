#!/usr/bin/env bash
# The foreground TUI never executes discovery. Private rows are data, not code.
status_async_ui=false
status_checks_running=false
status_ui_dirty=false
status_loader_pid=''
status_loader_dir=''
declare -A host_tool_status

# Outside text is never terminal control data. Byte rules also work in LANG=C.
setup_sanitize_text() {
    local LC_ALL=C
    local sanitize_value="$2" sanitize_char sanitize_next sanitize_result='' sanitize_index
    for ((sanitize_index=0; sanitize_index<${#sanitize_value}; sanitize_index++)); do
        sanitize_char="${sanitize_value:sanitize_index:1}"
        sanitize_next="${sanitize_value:sanitize_index+1:1}"
        if [[ "$sanitize_char" == $'\302' && "$sanitize_next" == [$'\200'-$'\237'] ]]; then
            sanitize_result+=' '; ((sanitize_index++))
        elif [[ "$sanitize_char" == [$'\001'-$'\037'$'\177'] ]]; then
            sanitize_result+=' '
        else
            sanitize_result+="$sanitize_char"
        fi
    done
    printf -v "$1" '%s' "$sanitize_result"
}

setup_sanitize_identities() {
    local identities_text="${2//$'\036'/$'\n'}" identities_line identities_result='' identities_clean
    while IFS= read -r identities_line; do
        setup_sanitize_text identities_clean "$identities_line"
        [[ -z "$identities_result" ]] || identities_result+=$'\n'
        identities_result+="$identities_clean"
    done <<< "$identities_text"
    printf -v "$1" '%s' "$identities_result"
}

declare -A setup_bench_path bench_category_label bench_category_order bench_category_summary
declare -A bench_meta_category bench_meta_tagline bench_meta_description bench_meta_used_for bench_meta_contains
setup_catalog_loaded=false
bench_categories_loaded=false
bench_meta_loaded=false
setup_benches_state=loading

declare -a setup_bench_categories=() setup_bench_categories_focusable=()
declare -A setup_bench_category_of setup_bench_members setup_bench_totals setup_bench_installed setup_bench_queued
setup_bench_counts_signature=''

setup_refresh_bench_counts() {
    local name category key signature='' state
    for name in "${bench_items[@]}"; do
        key="bench_$name"
        signature+="$name:${component_status[$key]}:${component_checked[$key]}:${component_action[$key]};"
    done
    [[ "$signature" != "$setup_bench_counts_signature" ]] || return 0
    setup_bench_counts_signature="$signature"
    setup_bench_totals=(); setup_bench_installed=(); setup_bench_queued=()
    setup_bench_categories_focusable=()
    for name in "${bench_items[@]}"; do
        category="${setup_bench_category_of[$name]:-other-benches}"; key="bench_$name"
        setup_bench_totals[$category]=$(( ${setup_bench_totals[$category]:-0} + 1 ))
        state="${component_status[$key]}"
        if [[ "$state" == installed || "$state" == 'needs creds' || "$state" == 'image only' ]]; then
            setup_bench_installed[$category]=$(( ${setup_bench_installed[$category]:-0} + 1 ))
        fi
        if [[ "${component_checked[$key]}" == true && -n "${component_action[$key]}" ]]; then
            setup_bench_queued[$category]=$(( ${setup_bench_queued[$category]:-0} + 1 ))
        fi
    done
    for category in "${setup_bench_categories[@]}"; do
        [[ "${setup_bench_totals[$category]:-0}" == 0 ]] || setup_bench_categories_focusable+=("$category")
    done
}

setup_derive_bench_categories() {
    local LC_ALL=C
    local name category candidate previous order previous_order index word label
    local -a names=() categories=() words=()
    local -A known=()
    setup_bench_category_of=(); setup_bench_members=()
    if [[ "$bench_categories_loaded" == true ]]; then
        for category in "${!bench_category_order[@]}"; do known[$category]=true; done
    fi
    # Insertion sorts keep this arrival-time derivation inside Bash.
    for name in "${bench_items[@]}"; do
        index=${#names[@]}
        while (( index > 0 )) && [[ "${names[index-1]}" > "$name" ]]; do
            names[index]="${names[index-1]}"; ((index--))
        done
        names[index]=$name
    done
    for name in "${names[@]}"; do
        category="${bench_meta_category[$name]}"
        if [[ "$bench_categories_loaded" != true && "$bench_meta_loaded" != true ]]; then
            category=other-benches
        elif [[ -z "$category" ]]; then
            case "${setup_bench_path[$name]}" in
                devBenches/*) category=software-engineering ;;
                bioBenches/*) category=science ;;
                sysBenches/*) category=system-administration ;;
                *) category=other-benches ;;
            esac
        fi
        setup_bench_category_of[$name]=$category
        [[ -z "${setup_bench_members[$category]}" ]] || setup_bench_members[$category]+=' '
        setup_bench_members[$category]+="$name"
        if [[ -z "${bench_category_label[$category]}" ]]; then
            label=''; IFS=- read -r -a words <<< "$category"
            for word in "${words[@]}"; do
                [[ -z "$label" ]] || label+=' '
                label+="${word^}"
            done
            [[ "$category" != other-benches ]] || label='Other benches'
            bench_category_label[$category]=$label
        fi
    done
    for category in "${!bench_category_label[@]}"; do
        if [[ "${known[$category]}" != true && -z "${setup_bench_members[$category]}" ]]; then continue; fi
        order=1000000
        [[ "${known[$category]}" != true ]] || order=$((10#${bench_category_order[$category]:-999}))
        index=${#categories[@]}
        while (( index > 0 )); do
            previous="${categories[index-1]}"; previous_order=1000000
            [[ "${known[$previous]}" != true ]] || previous_order=$((10#${bench_category_order[$previous]:-999}))
            if (( previous_order < order )) || { (( previous_order == order )) && [[ "$previous" < "$category" ]]; }; then break; fi
            categories[index]=$previous; ((index--))
        done
        categories[index]=$category
    done
    setup_bench_categories=("${categories[@]}")
    setup_bench_counts_signature='!'
    setup_refresh_bench_counts
}

setup_read_bench_metadata() {
    local directory="$1" id order label summary name category tagline description uses contents field
    local -a consumed_metadata=()
    if [[ -f "$directory/bench-categories" ]]; then
        bench_category_label=(); bench_category_order=(); bench_category_summary=()
        while IFS=$'\t' read -r id order label summary; do
            [[ "$id" =~ ^[a-z0-9][a-z0-9-]*$ ]] || continue
            [[ "$order" =~ ^[0-9]{1,6}$ ]] || order=999
            [[ "$label" != - && -n "$label" ]] || label="$id"
            [[ "$summary" != - ]] || summary=''
            setup_sanitize_text label "$label"; setup_sanitize_text summary "$summary"
            bench_category_order[$id]=$order; bench_category_label[$id]=$label; bench_category_summary[$id]=$summary
        done < "$directory/bench-categories"
        bench_categories_loaded=true; status_ui_dirty=true
        consumed_metadata+=("$directory/bench-categories")
    fi
    if [[ -f "$directory/bench-meta" ]]; then
        bench_meta_category=(); bench_meta_tagline=(); bench_meta_description=()
        bench_meta_used_for=(); bench_meta_contains=()
        while IFS=$'\t' read -r name category tagline description uses contents; do
            [[ "$name" =~ ^[a-zA-Z0-9_+-]+$ ]] || continue
            [[ "$category" =~ ^[a-z0-9][a-z0-9-]*$ ]] || category=''
            for field in tagline description uses contents; do
                [[ "${!field}" != - ]] || printf -v "$field" '%s' ''
                setup_sanitize_text "$field" "${!field}"
            done
            bench_meta_category[$name]=$category; bench_meta_tagline[$name]=$tagline
            bench_meta_description[$name]=$description; bench_meta_used_for[$name]=$uses; bench_meta_contains[$name]=$contents
        done < "$directory/bench-meta"
        bench_meta_loaded=true; status_ui_dirty=true
        consumed_metadata+=("$directory/bench-meta")
    fi
    (( ${#consumed_metadata[@]} == 0 )) || rm -f -- "${consumed_metadata[@]}"
    return 0
}

setup_update_benches_state() {
    if [[ "$setup_catalog_loaded" == true && ( "$bench_meta_loaded" == true || "$status_checks_running" != true ) ]]; then
        setup_benches_state=ready
    elif [[ "$status_checks_running" == true ]]; then
        setup_benches_state=loading
    else
        setup_benches_state=unavailable
    fi
}

setup_load_bench_metadata_sync() {
    local status_worker_dir metadata_directory
    metadata_directory=$(mktemp -d "${TMPDIR:-/tmp}/workbenches-metadata.XXXXXX") || return 1
    status_worker_dir="$metadata_directory"
    if ! setup_publish_bench_metadata; then
        rm -rf "$metadata_directory"
        setup_benches_state=unavailable
        return 1
    fi
    local name path
    setup_bench_path=()
    while IFS=$'\t' read -r name path; do
        [[ "$name" =~ ^[a-zA-Z0-9_+-]+$ ]] || continue
        case "$path" in devBenches/?*|sysBenches/?*|bioBenches/?*)
            [[ "/$path/" == */../* ]] || setup_bench_path[$name]=$path ;; esac
    done < "$metadata_directory/catalog"
    setup_catalog_loaded=true
    setup_read_bench_metadata "$metadata_directory"
    setup_update_benches_state
    setup_derive_bench_categories
    rm -rf "$metadata_directory"
}

initialize_loading_statuses() {
    local key
    for key in "${!component_description[@]}"; do component_status[$key]=loading; done
    for key in "${requirement_items[@]}"; do requirement_detail[$key]='Checking workstation readiness…'; done
}

setup_required_ready() {
    local key
    for key in "${requirement_items[@]}"; do
        case "$key" in vault|workbenches_account|ai_accounts) continue ;; esac
        [[ "${component_status[$key]}" == up ]] || return 1
    done
}

status_publish() {
    local key=$1 state=$2 detail="${3:-}"
    [[ -d "$status_worker_dir" ]] || exit 143
    [[ "$key" =~ ^[a-zA-Z0-9_+-]+$ ]] || return 1
    printf '%s\t%s\n' "$state" "$detail" > "$status_worker_dir/$key.tmp"
    mv "$status_worker_dir/$key.tmp" "$status_worker_dir/$key.row"
}

refresh_host_tool_inventory() {
    local key state
    host_tool_status=()
    while IFS=$'\t' read -r key state; do
        [[ "$key" =~ ^[a-zA-Z0-9_]+$ && -n "${component_description[$key]:-}" ]] || continue
        host_tool_status[$key]=$state
        if [[ -n "${status_worker_dir:-}" ]] && { ! is_wsl_windows || [[ ! "$key" =~ ^(vscode|warp|wave|amnezia_vpn|0dcloud_vpn)$ ]]; }; then
            status_publish "$key" "$state"
        fi
    done < <(python3 "$SCRIPT_DIR/setup-components.py" tool-statuses)
}

# Publish complete metadata snapshots before any per-bench status row.
setup_publish_bench_metadata() {
    local catalog_file="$SCRIPT_DIR/../config/bench-config.json"
    jq -r '
        def clean: tostring | gsub("[[:cntrl:]]"; " ") | sub("^ +"; "") | sub(" +$"; "");
        def field: if . == null then "-" else clean | if . == "" then "-" else . end end;
        .benches | to_entries | sort_by(.key)[] | [.key, (.value.path | field)] | join("\t")
    ' "$catalog_file" > "$status_worker_dir/catalog.tmp" || return
    mv "$status_worker_dir/catalog.tmp" "$status_worker_dir/catalog"
    jq -r '
        def clean: tostring | gsub("[[:cntrl:]]"; " ") | sub("^ +"; "") | sub(" +$"; "");
        def field: if . == null then "-" else clean | if . == "" then "-" else . end end;
        (.categories // {}) | to_entries | sort_by(.value.order // 999, .key)[] |
        [.key, ((.value.order // 999) | tostring), ((.value.label // .key) | field),
         (.value.summary | field)] | join("\t")
    ' "$catalog_file" > "$status_worker_dir/bench-categories.tmp" || return
    mv "$status_worker_dir/bench-categories.tmp" "$status_worker_dir/bench-categories"
    jq -r '
        def clean: tostring | gsub("[[:cntrl:]]"; " ") | sub("^ +"; "") | sub(" +$"; "");
        def field: if . == null then "-" else clean | if . == "" then "-" else . end end;
        def items: (. // []) | map(clean | gsub("\\|"; "/")) | map(select(. != "")) | join("|") | field;
        .benches | to_entries | sort_by(.key)[] |
        [.key, (.value.category | field), (.value.tagline | field), (.value.description | field),
         (.value.usedFor | items), (.value.contains | items)] | join("\t")
    ' "$catalog_file" > "$status_worker_dir/bench-meta.tmp" || return
    mv "$status_worker_dir/bench-meta.tmp" "$status_worker_dir/bench-meta"
}

status_collect_inventory() {
    local key label state detail name
    bench_items=()
    init_components
    setup_publish_bench_metadata || return
    status_publish workbenches_account "$(python3 "$SCRIPT_DIR/setup-workbenches-account.py" --status)"
    local profile_summary
    profile_summary="$(python3 "$SCRIPT_DIR/setup-profiles.py" --summary 2>/dev/null)" || profile_summary='Profile metadata needs attention.'
    profile_summary="${profile_summary//$'\n'/$'\036'}"
    status_publish personal_profiles optional "$profile_summary"
    for key in host_shell workspace_repo ai_accounts; do status_publish "$key" "$(check_component_status "$key")"; done
    refresh_bench_inventory
    for name in "${bench_items[@]}"; do
        key="bench_$name"
        status_publish "$key" "$(check_component_status "$key")"
    done
    refresh_host_tool_inventory
    # Windows desktop checks need the native PowerShell probes.
    if is_wsl_windows; then
        for key in vscode warp wave amnezia_vpn 0dcloud_vpn; do status_publish "$key" "$(check_component_status "$key")"; done
    fi
}

status_worker_bootstrap() {
    local key label state detail docker_state='' wsl_ready=true
    status_worker_dir=$1
    trap 'exit 143' TERM
    while IFS=$'\t' read -r key label state detail; do
        status_publish "$key" "$state" "$detail"
        [[ "$key" != docker ]] || docker_state=$state
        [[ "$key" != wsl || "$state" == up ]] || wsl_ready=false
    done < <(workbenches_requirement_rows)
    if [[ "$docker_state" == up && "$wsl_ready" == true ]]; then
        status_publish setup_tools loading 'Starting Tools; first-time image preparation may take a few minutes.'
        if ! workbenches_tools_activate; then
            status_publish setup_tools down 'Tools could not start. Select Start to retry; details are in the setup log.'
            touch "$status_worker_dir/done"
            return
        fi
        printf '%s\n' "${WORKBENCHES_DOCKER_ENDPOINT:-}" > "$status_worker_dir/tools-ready.tmp"
        mv "$status_worker_dir/tools-ready.tmp" "$status_worker_dir/tools-ready"
        status_publish setup_tools up 'Python 3, jq, Git and curl are available in Tools.'
        # One transport/broker session for the whole read-only inventory. All
        # nested jq/Git/Python calls use the image binaries, not Docker exec each time.
        python3 - "$SCRIPT_DIR/setup-status-worker.sh" "$status_worker_dir" <<'PY'
import os, sys
os.execvp('bash', ['bash', sys.argv[1], sys.argv[2]])
PY
    fi
    touch "$status_worker_dir/done"
}

stop_status_loader() {
    if [[ -n "$status_loader_pid" ]]; then
        # Stop only this loader's descendants, including a pending Docker probe
        # or build client. ps emits IDs only; command lines/env are never read.
        local pid parent index child
        local -a descendants=("$status_loader_pid") pairs=()
        while read -r pid parent; do pairs+=("$pid:$parent"); done < <(ps -axo pid=,ppid= 2>/dev/null)
        for ((index=0; index<${#descendants[@]}; index++)); do
            for child in "${pairs[@]}"; do
                [[ "${child#*:}" != "${descendants[$index]}" ]] || descendants+=("${child%%:*}")
            done
        done
        for ((index=${#descendants[@]}-1; index>=0; index--)); do kill -TERM "${descendants[$index]}" 2>/dev/null || true; done
        wait "$status_loader_pid" 2>/dev/null || true
    fi
    status_loader_pid=''
    if [[ -n "$status_loader_dir" ]]; then
        [[ ! -f "$status_loader_dir/worker.log" ]] || cat "$status_loader_dir/worker.log" >> "$LOG_FILE"
        rm -rf -- "$status_loader_dir"
    fi
    status_loader_dir=''
    status_checks_running=false
}

start_status_loader() {
    stop_status_loader
    initialize_loading_statuses
    setup_catalog_loaded=false; bench_categories_loaded=false; bench_meta_loaded=false
    setup_benches_state=loading
    status_checks_running=true
    status_ui_dirty=true
    status_loader_dir="$(mktemp -d "${TMPDIR:-/tmp}/workbenches-status.XXXXXX")" || {
        status_checks_running=false; setup_benches_state=unavailable; requirements_notice='Could not start readiness checks. R retries.'; return 1;
    }
    status_worker_bootstrap "$status_loader_dir" </dev/null > "$status_loader_dir/worker.log" 2>&1 &
    status_loader_pid=$!
}

poll_status_loader() {
    [[ "$status_checks_running" == true && -n "$status_loader_dir" ]] || return 0
    local key state detail file reading name path selected='' index endpoint old_name
    local -a old_benches=()
    local -A present_benches=()
    if [[ -f "$status_loader_dir/tools-ready" ]]; then
        IFS= read -r endpoint < "$status_loader_dir/tools-ready"
        if [[ "$endpoint" == unix:///* || "${WORKBENCHES_TEST_NATIVE_TOOLS:-}" == 1 ]]; then
            [[ -z "$endpoint" ]] || export WORKBENCHES_DOCKER_ENDPOINT=$endpoint
            workbenches_tools_use_shims
        fi
        rm -f "$status_loader_dir/tools-ready"
    fi
    if [[ -f "$status_loader_dir/catalog" ]]; then
        [[ "$CURRENT_SECTION" != 0 ]] || selected="${bench_items[$current_selection]}"
        old_benches=("${bench_items[@]}")
        bench_items=(); setup_bench_path=()
        while IFS=$'\t' read -r name path; do
            [[ "$name" =~ ^[a-zA-Z0-9_+-]+$ ]] || continue
            case "$path" in devBenches/?*|sysBenches/?*|bioBenches/?*)
                [[ "/$path/" == */../* ]] || setup_bench_path[$name]=$path ;; esac
            present_benches[$name]=true
            bench_items+=("$name"); key="bench_$name"
            component_description[$key]=$name
            component_status[$key]=loading
            component_checked[$key]="${component_checked[$key]:-false}"
        done < "$status_loader_dir/catalog"
        for old_name in "${old_benches[@]}"; do
            [[ "${present_benches[$old_name]}" == true ]] || {
                unset 'component_checked[bench_'"$old_name"']' 'component_action[bench_'"$old_name"']'
            }
        done
        unset 'component_description[bench_loading]' 'component_status[bench_loading]' 'component_checked[bench_loading]'
        if [[ "$CURRENT_SECTION" == 0 ]]; then
            current_selection=0
            for index in "${!bench_items[@]}"; do [[ "${bench_items[$index]}" != "$selected" ]] || current_selection=$index; done
        fi
        rm -f "$status_loader_dir/catalog"
        setup_catalog_loaded=true
        status_ui_dirty=true
    fi
    setup_read_bench_metadata "$status_loader_dir"
    setup_update_benches_state
    if [[ "$status_ui_dirty" == true ]]; then setup_derive_bench_categories; fi
    for file in "$status_loader_dir"/*.row; do
        [[ -f "$file" ]] || continue
        key="${file##*/}"; key="${key%.row}"
        if [[ ! "$key" =~ ^[a-zA-Z0-9_+-]+$ || -z "${component_description[$key]:-}" ]]; then
            rm -f "$file"; continue
        fi
        reading="$file.reading"
        mv "$file" "$reading" 2>/dev/null || continue
        IFS=$'\t' read -r state detail < "$reading"
        case "$state" in
            up|down|missing|loading|installed|'not installed'|'needs check'|'needs creds'|'needs setup'|'needs docker'|'image only'|configured|optional|'sign in'|'signed in'|'not configured'|'needs configuration') ;;
            *) state='needs check' ;;
        esac
        if [[ "${component_status[$key]}" != "$state" ]]; then
            component_status[$key]=$state
            status_ui_dirty=true
        fi
        if [[ "$key" == personal_profiles ]]; then
            setup_sanitize_identities profiles_summary "$detail"
        fi
        setup_sanitize_text detail "$detail"
        if [[ -n "$detail" && "${requirement_detail[$key]:-}" != "$detail" ]]; then
            requirement_detail[$key]=$detail
            status_ui_dirty=true
        fi
        rm -f "$reading"
    done
    setup_refresh_bench_counts
    if [[ -f "$status_loader_dir/done" ]] || ! kill -0 "$status_loader_pid" 2>/dev/null; then
        # Drain any newer rows published while an earlier version was consumed.
        local -a remaining=("$status_loader_dir"/*.row)
        [[ ! -f "${remaining[0]}" ]] || return 0
        for key in "${!component_status[@]}"; do
            [[ "${component_status[$key]}" != loading ]] || component_status[$key]='needs check'
        done
        stop_status_loader
        setup_update_benches_state
        setup_derive_bench_categories
        status_ui_dirty=true
        if ! setup_required_ready; then
            requirements_notice='Resolve workstation requirements to continue.'
            if [[ "$CURRENT_SECTION" != 3 ]]; then
                requirements_return_section=$CURRENT_SECTION; requirements_return_selection=$current_selection
                CURRENT_SECTION=3; current_selection=0
            fi
            for index in "${!requirement_items[@]}"; do
                key="${requirement_items[$index]}"
                case "$key" in vault|workbenches_account|ai_accounts) continue ;; esac
                [[ "${component_status[$key]}" == up ]] || { current_selection=$index; break; }
            done
        fi
    fi
}
