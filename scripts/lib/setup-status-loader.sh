#!/usr/bin/env bash
# The foreground TUI never executes discovery. Private rows are data, not code.
status_async_ui=false
status_checks_running=false
status_ui_dirty=false
status_loader_pid=''
status_loader_dir=''
declare -A host_tool_status
# Bench catalog presentation for the Benches step, keyed by bench name or
# category id. Rendering only reads these; jq runs in the loader or in main().
declare -A bench_meta_category bench_meta_tagline bench_meta_description bench_meta_used_for bench_meta_contains
declare -A bench_category_label bench_category_order bench_category_summary
bench_meta_loaded=false

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

# Bench metadata as TSV from config/bench-config.json: "meta" rows are name,
# category id, tagline, description, usedFor and contains (lists joined by "|");
# "categories" rows are id, order, label and summary. Tabs, newlines and other
# control characters never reach a value, and an empty value travels as "-"
# because Bash's tab splitting would merge it with the next field. A bench
# without a category takes one from its path.
bench_metadata_rows() {
    local kind=$1 config="${2:-$SCRIPT_DIR/../config/bench-config.json}"
    jq -r --arg kind "$kind" '
        def clean: tostring | gsub("[[:cntrl:]]"; " ") | gsub("^ +| +$"; "");
        def cell: clean | if . == "" then "-" else . end;
        def items: if type == "array" then map(clean | gsub("[|]"; "/") | select(. != "")) | join("|") else "" end;
        if $kind == "categories" then
            (.categories // {}) | to_entries[] | select(.value | type == "object")
            | [.key, (.value.order // 999), (.value.label // .key), (.value.summary // "")]
        else
            (.benches // {}) | to_entries[] | select(.value | type == "object")
            | .key as $name | .value as $bench | ($bench.path // "" | tostring) as $path
            | [$name,
               ($bench.category // (if ($path | startswith("devBenches/")) then "software-engineering"
                   elif ($path | startswith("bioBenches/")) then "science"
                   elif ($path | startswith("sysBenches/")) then "system-administration"
                   else "other" end)),
               ($bench.tagline // ""), ($bench.description // ""),
               ($bench.usedFor | items), ($bench.contains | items)]
        end
        | map(cell) | join("\t")' "$config"
}

# Read "meta" rows into the bench_meta_* arrays; names match the catalog's rule.
bench_meta_apply() {
    local name category tagline description used contains
    bench_meta_category=(); bench_meta_tagline=(); bench_meta_description=()
    bench_meta_used_for=(); bench_meta_contains=()
    while IFS=$'\t' read -r name category tagline description used contains; do
        [[ "$name" =~ ^[a-zA-Z0-9_+-]+$ ]] || continue
        [[ "$category" =~ ^[a-z0-9][a-z0-9-]*$ ]] || category=other
        [[ "$tagline" != - ]] || tagline=''
        [[ "$description" != - ]] || description=''
        [[ "$used" != - ]] || used=''
        [[ "$contains" != - ]] || contains=''
        bench_meta_category[$name]=$category
        bench_meta_tagline[$name]=$tagline
        bench_meta_description[$name]=$description
        bench_meta_used_for[$name]=$used
        bench_meta_contains[$name]=$contains
    done
}

# Read "categories" rows into the bench_category_* arrays.
bench_categories_apply() {
    local id order label summary
    bench_category_label=(); bench_category_order=(); bench_category_summary=()
    while IFS=$'\t' read -r id order label summary; do
        [[ "$id" =~ ^[a-z0-9][a-z0-9-]*$ ]] || continue
        [[ "$order" =~ ^[0-9]{1,6}$ ]] || order=999
        [[ "$label" != - ]] || label=$id
        [[ "$summary" != - ]] || summary=''
        bench_category_label[$id]=$label
        bench_category_order[$id]=$((10#$order))
        bench_category_summary[$id]=$summary
    done
}

# Worker side: publish both files atomically, categories first, so the TUI
# treats bench-meta as the signal that the catalog's metadata is complete.
bench_metadata_publish() {
    local kind file
    for kind in categories meta; do
        file="$status_worker_dir/bench-$kind"
        bench_metadata_rows "$kind" > "$file.tmp" 2>/dev/null || : > "$file.tmp"
        mv "$file.tmp" "$file"
    done
}

# Synchronous path (no TTY): the same arrays straight from the config.
load_bench_metadata() {
    local config="$SCRIPT_DIR/../config/bench-config.json"
    [[ -f "$config" ]] && command -v jq >/dev/null 2>&1 || return 0
    bench_categories_apply < <(bench_metadata_rows categories "$config" 2>/dev/null)
    bench_meta_apply < <(bench_metadata_rows meta "$config" 2>/dev/null)
    bench_meta_loaded=true
}

status_collect_inventory() {
    local key label state detail name
    bench_items=()
    init_components
    printf '%s\n' "${bench_items[@]}" > "$status_worker_dir/catalog.tmp"
    mv "$status_worker_dir/catalog.tmp" "$status_worker_dir/catalog"
    bench_metadata_publish
    status_publish workbenches_account "$(python3 "$SCRIPT_DIR/setup-workbenches-account.py" --status)"
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
    status_checks_running=true
    status_ui_dirty=true
    status_loader_dir="$(mktemp -d "${TMPDIR:-/tmp}/workbenches-status.XXXXXX")" || {
        status_checks_running=false; requirements_notice='Could not start readiness checks. R retries.'; return 1;
    }
    status_worker_bootstrap "$status_loader_dir" </dev/null > "$status_loader_dir/worker.log" 2>&1 &
    status_loader_pid=$!
}

poll_status_loader() {
    [[ "$status_checks_running" == true && -n "$status_loader_dir" ]] || return 0
    local key state detail file reading name selected='' index endpoint catalog_changed=false
    if [[ -f "$status_loader_dir/tools-ready" ]]; then
        IFS= read -r endpoint < "$status_loader_dir/tools-ready"
        if [[ "$endpoint" == unix:///* || "${WORKBENCHES_TEST_NATIVE_TOOLS:-}" == 1 ]]; then
            [[ -z "$endpoint" ]] || export WORKBENCHES_DOCKER_ENDPOINT=$endpoint
            workbenches_tools_use_shims
        fi
        rm -f "$status_loader_dir/tools-ready"
    fi
    if [[ -f "$status_loader_dir/bench-categories" ]]; then
        bench_categories_apply < "$status_loader_dir/bench-categories"
        rm -f "$status_loader_dir/bench-categories"
        catalog_changed=true; status_ui_dirty=true
    fi
    if [[ -f "$status_loader_dir/bench-meta" ]]; then
        bench_meta_apply < "$status_loader_dir/bench-meta"
        rm -f "$status_loader_dir/bench-meta"
        bench_meta_loaded=true; catalog_changed=true; status_ui_dirty=true
    fi
    if [[ -f "$status_loader_dir/catalog" ]]; then
        catalog_changed=true
        [[ "$CURRENT_SECTION" != 0 ]] || selected="${bench_items[$current_selection]}"
        bench_items=()
        while IFS= read -r name; do
            [[ "$name" =~ ^[a-zA-Z0-9_+-]+$ ]] || continue
            bench_items+=("$name"); key="bench_$name"
            component_description[$key]=$name
            component_status[$key]=loading
            component_checked[$key]="${component_checked[$key]:-false}"
        done < "$status_loader_dir/catalog"
        unset 'component_description[bench_loading]' 'component_status[bench_loading]' 'component_checked[bench_loading]'
        if [[ "$CURRENT_SECTION" == 0 ]]; then
            current_selection=0
            for index in "${!bench_items[@]}"; do [[ "${bench_items[$index]}" != "$selected" ]] || current_selection=$index; done
        fi
        rm -f "$status_loader_dir/catalog"
        status_ui_dirty=true
    fi
    # Keep the Benches step's zone, category and focus consistent with the new data.
    if [[ "$catalog_changed" == true && "$CURRENT_SECTION" == 0 ]] && declare -F wizard_bench_sync >/dev/null; then
        wizard_bench_sync
    fi
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
        if [[ -n "$detail" && "${requirement_detail[$key]:-}" != "$detail" ]]; then
            requirement_detail[$key]=$detail
            status_ui_dirty=true
        fi
        rm -f "$reading"
    done
    if [[ -f "$status_loader_dir/done" ]] || ! kill -0 "$status_loader_pid" 2>/dev/null; then
        # Drain any newer rows published while an earlier version was consumed.
        local -a remaining=("$status_loader_dir"/*.row)
        [[ ! -f "${remaining[0]}" ]] || return 0
        for key in "${!component_status[@]}"; do
            [[ "${component_status[$key]}" != loading ]] || component_status[$key]='needs check'
        done
        stop_status_loader
        status_ui_dirty=true
        if ! setup_required_ready; then
            requirements_notice='Resolve workstation requirements to continue.'
            if [[ "$CURRENT_SECTION" != 3 ]]; then
                requirements_return_section=$CURRENT_SECTION; requirements_return_selection=$current_selection
                requirements_return_zone=${wizard_bench_zone:-benches}; requirements_return_category=${wizard_category:-}
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
