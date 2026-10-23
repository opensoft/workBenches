#!/usr/bin/env bash

# Interactive Setup UI for workBenches
# Provides keyboard-driven selection interface for installing components

# Character-based layout needs a UTF-8 locale, including on minimal hosts.
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
    *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) ;;
    *) if locale -a 2>/dev/null | grep -qiE '^C\.utf-?8$'; then
           export LC_CTYPE=C.UTF-8
           [[ -z "${LC_ALL:-}" ]] || export LC_ALL=C.UTF-8
       fi ;;
esac

# Setup logging
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/image-names.sh"
source "$SCRIPT_DIR/lib/setup-prerequisites.sh"
source "$SCRIPT_DIR/lib/setup-status-loader.sh"
source "$SCRIPT_DIR/../bootstrap.sh"
setup_version="$(workbenches_version)"
setup_ui_brand='openBenches v1.7'
LOG_DIR="$SCRIPT_DIR/../logs"
mkdir -p "$LOG_DIR"
LOG_FILE="${WORKBENCHES_SETUP_LOG_FILE:-$LOG_DIR/setup-$(date +%Y%m%d-%H%M%S).log}"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

is_wsl_windows() {
    [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qi microsoft /proc/version 2>/dev/null
}

run_windows_powershell() {
    local command="$1"
    if command -v powershell.exe >/dev/null 2>&1; then
        powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$command" | tr -d '\r'
    elif command -v pwsh.exe >/dev/null 2>&1; then
        pwsh.exe -NoProfile -ExecutionPolicy Bypass -Command "$command" | tr -d '\r'
    else
        return 127
    fi
}

ps_quote() {
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/''/g")"
}

windows_file_exists() {
    local path="$1"
    run_windows_powershell "if (Test-Path -LiteralPath $(ps_quote "$path")) { 'yes' } else { 'no' }" 2>/dev/null | grep -q '^yes$'
}

windows_env_file_exists() {
    local env_name="$1"
    local suffix="$2"
    run_windows_powershell "\$base = [Environment]::GetEnvironmentVariable($(ps_quote "$env_name")); if (\$base -and (Test-Path -LiteralPath (Join-Path \$base $(ps_quote "$suffix")))) { 'yes' } else { 'no' }" 2>/dev/null | grep -q '^yes$'
}

windows_command_exists() {
    local command="$1"
    run_windows_powershell "if (Get-Command $(ps_quote "$command") -ErrorAction SilentlyContinue) { 'yes' } else { 'no' }" 2>/dev/null | grep -q '^yes$'
}

# Log script start
log "=== Setup script started ==="
log "Version: $setup_version"
log "User: $USER"
log "PWD: $PWD"
log "Shell: $SHELL"
if [ -n "$WSL_DISTRO_NAME" ]; then
    log "WSL Distro: $WSL_DISTRO_NAME"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
LOADING_COLOR='\033[38;5;220m\033[5m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color
BOLD='\033[1m'
DIM='\033[2m'

# Neutral chrome leaves the component columns' existing colors untouched.
SILVER='\033[38;5;252m'
SILVER_MUTED='\033[38;5;245m'
SILVER_EDGE='\033[38;5;239m'
SILVER_FOCUS='\033[48;5;235m\033[38;5;255m'
setup_ui_width=87
setup_ui_painted=false
setup_ui_frame_columns=0
setup_ui_frame_rows=''
setup_ui_height=''
setup_ui_size_stale=true
setup_terminal_columns=88
setup_input_key=''
declare -a setup_ui_previous_lines=()

setup_ui_rule_v() {
    local ui_rule
    if [[ -z "${setup_rule_cache[$2]}" ]]; then
        printf -v ui_rule '%*s' "$2" ''
        setup_rule_cache[$2]="${ui_rule// /─}"
    fi
    printf -v "$1" '%s' "${setup_rule_cache[$2]}"
}

setup_ui_rule() {
    local result
    setup_ui_rule_v result "$1"
    printf '%s' "$result"
}

setup_ui_pair_v() {
    local ui_left="$2" ui_right="$3" ui_width="$4" ui_gap
    ui_right="${ui_right:0:$((ui_width - 1))}"
    if [[ -n "$ui_right" ]]; then ui_left="${ui_left:0:$((ui_width - ${#ui_right} - 1))}"
    else ui_left="${ui_left:0:ui_width}"; fi
    ui_gap=$((ui_width - ${#ui_left} - ${#ui_right}))
    printf -v "$1" '%s%*s%s' "$ui_left" "$ui_gap" '' "$ui_right"
}

setup_ui_pair() {
    local result
    setup_ui_pair_v result "$1" "$2" "$3"
    printf '%s' "$result"
}

setup_ui_banner() {
    local banner_key="$setup_ui_width:$setup_ui_layout:$setup_ui_height" banner_line banner_index banner_char banner_position banner_tone banner_result banner_gap
    [[ "$setup_banner_cache_key" != "$banner_key" ]] || return 0
    setup_banner_cache_key="$banner_key"
    setup_banner_lines=()
    if (( setup_ui_width < 43 + ${#setup_ui_brand} )) || [[ "$setup_ui_layout" == tight ]] || { [[ -n "$setup_ui_height" ]] && ((setup_ui_height < 40)); }; then
        banner_gap=$(( (setup_ui_width - 10 - ${#setup_ui_brand}) / 2 ))
        printf -v banner_result '  %bOpensoft%b%*s%b%s%b' "$SILVER" "$NC" "$banner_gap" '' "$SILVER" "$setup_ui_brand" "$NC"
        setup_banner_lines=("$banner_result")
        return
    fi
    local -a banner_logo=(
        '                                    ▄ '
        '█▀▀█ █▀▀█ █▀▀█ █▀▀▄ █▀▀▀ █▀▀█ █▀▀▀ ▀█▀▀'
        '█__█ █__█ █^^^ █__█ ▀▀▀█ █__█ █^^   █__'
        '▀▀▀▀ █▀▀▀ ▀▀▀▀ ▀~~▀ ▀▀▀▀ ▀▀▀▀ ▀     ▀▀▀'
    )
    local -a banner_tones=(255 252 250 246)
    for banner_index in "${!banner_logo[@]}"; do
        banner_line="${banner_logo[banner_index]}"
        printf -v banner_tone '\033[38;5;%sm' "${banner_tones[banner_index]}"
        banner_result="  $banner_tone"
        for ((banner_position=0; banner_position<${#banner_line}; banner_position++)); do
            banner_char="${banner_line:banner_position:1}"
            case "$banner_char" in
                _) banner_result+=$'\033[48;5;237m '$'\033[0m'"$banner_tone" ;;
                '^') banner_result+=$'\033[48;5;237m▀'$'\033[0m'"$banner_tone" ;;
                '~') banner_result+=$'\033[38;5;239m▀'"$banner_tone" ;;
                *) banner_result+="$banner_char" ;;
            esac
        done
        if ((banner_index == 2)); then
            banner_gap=$(( (setup_ui_width - 2 - ${#banner_line} - ${#setup_ui_brand}) / 2 ))
            printf -v banner_result '%s%*s%b%s%b' "$banner_result" "$banner_gap" '' "$SILVER" "$setup_ui_brand" "$NC"
        fi
        setup_banner_lines+=("$banner_result"$'\033[0m')
    done
}

draw_setup_banner() {
    setup_ui_banner
    printf '\n'
    printf '%s\n' "${setup_banner_lines[@]}"
    [[ "$setup_ui_layout" == tight ]] || printf '\n'
}

setup_requirement_counts() {
    requirements_ready=0
    requirements_total=0
    local key
    for key in "${requirement_items[@]}"; do
        case "$key" in vault|workbenches_account|ai_accounts) continue ;; esac
        requirements_total=$((requirements_total + 1))
        [[ "${component_status[$key]}" != up ]] || requirements_ready=$((requirements_ready + 1))
    done
}

setup_panel_top_v() {
    local panel_line panel_key="top:$setup_ui_width:$setup_ui_layout:$2:${3:-}"
    if [[ -z "${setup_panel_cache[$panel_key]}" ]]; then
        setup_ui_pair_v panel_line "$2" "${3:-}" "$((setup_ui_width - 6))"
        printf -v panel_line '%b╭─ %b%s%b ─╮%b' "$SILVER_EDGE" "$SILVER" "$panel_line" "$SILVER_EDGE" "$NC"
        setup_panel_cache[$panel_key]=$panel_line
    fi
    printf -v "$1" '%s' "${setup_panel_cache[$panel_key]}"
}

setup_panel_bottom_v() {
    local panel_rule
    setup_ui_rule_v panel_rule "$((setup_ui_width - 2))"
    printf -v "$1" '%b╰%s╯%b' "$SILVER_EDGE" "$panel_rule" "$NC"
}

setup_panel_top() {
    local result
    setup_panel_top_v result "$1" "${2:-}"
    printf '%s\n' "$result"
}

setup_panel_bottom() {
    local result
    setup_panel_bottom_v result
    printf '%s\n' "$result"
}

draw_requirements_summary() {
    local -a setup_frame_lines=()
    local setup_frame_region_height=0
    setup_frame_requirements_strip
    printf '%s\n' "${setup_frame_lines[@]}"
}

setup_status_label_v() {
    local status_text="$2"
    case "$status_text" in
        loading) status_text='Loading…' ;;
        up) status_text=Up ;;
        down) status_text=Down ;;
        installed|ready) status_text=Ready ;;
        'needs path') status_text='PATH setup needed' ;;
        configured) status_text=Configured ;;
        missing) status_text=Missing ;;
        optional|'not configured') status_text='Not configured' ;;
    esac
    printf -v "$1" '%s' "$status_text"
}

setup_status_label() {
    local result
    setup_status_label_v result "$1"
    printf '%s' "$result"
}

# Spinner for long operations
show_spinner() {
    local pid=$1
    local message="$2"
    local timeout=${3:-300}  # Default 5 minute timeout
    local spinner="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    local i=0
    local elapsed=0
    if [[ "${4:-}" == build ]]; then
        printf "  Build log: %s\n  Follow live: tail -f %q\n" "$LOG_FILE" "$LOG_FILE"
    fi

    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) % 10 ))
        printf "\r  ${YELLOW}${spinner:$i:1}${NC} ${message} ($((elapsed / 10))s elapsed)"
        sleep 0.1
        elapsed=$((elapsed + 1))

        # Timeout check (elapsed is in deciseconds)
        if [ $elapsed -ge $((timeout * 10)) ]; then
            printf "\r"
            echo -e "  ${RED}✗ Operation timed out after ${timeout}s${NC}"
            kill -9 $pid 2>/dev/null
            return 1
        fi
    done

    # Wait for process to fully complete and get exit status
    wait $pid 2>/dev/null
    local exit_status=$?
    printf "\r"
    return $exit_status
}

# Cursor control
CURSOR_UP='\033[1A'
CURSOR_DOWN='\033[1B'
CLEAR_LINE='\033[2K'
SAVE_CURSOR='\033[s'
RESTORE_CURSOR='\033[u'
HIDE_CURSOR='\033[?25l'
SHOW_CURSOR='\033[?25h'

# Track component states
declare -A component_checked
declare -A component_status
declare -A component_description
declare -A component_action  # Empty means keep; otherwise install/update/uninstall.
declare -A bench_runtime_status
declare -a component_order

# Current selection
current_selection=0
current_block=0

# Sections: 0=Benches, 1=AI Assistants, 2=Tools, 3=Requirements, 4=Profiles
CURRENT_SECTION=0  # Requirements has a separate page for narrow terminals.
requirements_notice=""
requirements_return_section=0
requirements_return_selection=0
profiles_return_section=0
profiles_return_selection=0
profiles_summary='Personal identity, GitHub, and company accounts'
profile_items=(personal_profiles workbenches_account ai_accounts)
declare -a bench_items
declare -a ai_items
declare -a tool_items
declare -a requirement_items
declare -A requirement_detail
setup_os_label=""
declare -A bench_status
declare -A ai_status
declare -A tool_status

# Initialize component data
init_components() {
    log "Initializing components..."
    # Load benches from config if available
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local config_file="$script_dir/../config/bench-config.json"
    log "Config file: $config_file"

    if [[ "${1:-}" != --loading && -f "$config_file" ]]; then
        # Get bench names from config
        while IFS= read -r bench_name; do
            bench_items+=("$bench_name")
            component_checked["bench_$bench_name"]=false
            component_description["bench_$bench_name"]="$bench_name"
        done < <(jq -r '.benches | keys[]' "$config_file" 2>/dev/null)
    fi

    # If no benches found, add some defaults
    if [[ "${1:-}" == --loading ]]; then
        bench_items=(loading)
        component_checked[bench_loading]=false
        component_description[bench_loading]="Loading benches"
    elif [ ${#bench_items[@]} -eq 0 ]; then
        bench_items=("flutterBench" "javaBench" "dotNetBench" "pyBench")
        for bench in "${bench_items[@]}"; do
            component_checked["bench_$bench"]=false
            component_description["bench_$bench"]="$bench"
        done
    fi

    # AI Assistants (CLIs + spec tools)
    ai_items=(
        "claude_cli"
        "copilot_cli"
        "codex_cli"
        "antigravity_cli"
        "opencode_cli"
        "pi_cli"
        "separator1"
        "spec_kit"
        "openspec"
    )
    # Browse-only references are appended separately from the managed catalog.
    ai_items+=("${setup_catalog_harness_refs[@]}")

    # Initialize AI items
    component_checked["claude_cli"]=false
    component_description["claude_cli"]="Claude Code CLI"

    component_checked["copilot_cli"]=false
    component_description["copilot_cli"]="GitHub Copilot CLI"

    component_checked["codex_cli"]=false
    component_description["codex_cli"]="Codex CLI"

    component_checked["antigravity_cli"]=false
    component_description["antigravity_cli"]="Antigravity CLI"

    component_checked["opencode_cli"]=false
    component_description["opencode_cli"]="OpenCode CLI"

    component_checked["pi_cli"]=false
    component_description["pi_cli"]="Pi Coding Agent"

    component_checked["spec_kit"]=false
    component_description["spec_kit"]="spec-kit"

    component_checked["openspec"]=false
    component_description["openspec"]="OpenSpec"

    # Tools
    tool_items=(
        "vscode"
        "warp"
        "wave"
        "amnezia_vpn"
        "0dcloud_vpn"
        "host_shell"
        "workspace_repo"
    )
    tool_items+=("${setup_catalog_tool_refs[@]}")

    # Initialize tool items
    component_checked["vscode"]=false
    component_description["vscode"]="VS Code"

    component_checked["warp"]=false
    component_description["warp"]="Warp Terminal"

    component_checked["wave"]=false
    component_description["wave"]="Wave Terminal"

    component_checked["amnezia_vpn"]=false
    component_description["amnezia_vpn"]="AmneziaVPN"

    component_checked["0dcloud_vpn"]=false
    component_description["0dcloud_vpn"]="0dcloud VPN"
    for item in host_shell workspace_repo ai_accounts; do
        component_checked[$item]=false
    done
    for item in "${!setup_reference_labels[@]}"; do
        component_checked[$item]=false
        component_action[$item]=''
        component_description[$item]="${setup_reference_labels[$item]}"
    done
    for item in "${!setup_catalog_labels[@]}"; do
        component_description[$item]="${setup_catalog_labels[$item]}"
        [[ -z "${setup_managed_harnesses[$item]:-}" ]] || { component_checked[$item]=false; component_action[$item]=''; }
    done
    component_description[host_shell]="Shell setup"
    component_description[workspace_repo]="Org workspace"
    component_description[ai_accounts]="AI accounts"
    component_description[workbenches_account]="workBenches account"
    component_checked[workbenches_account]=false
    component_description[docker]=Docker
    component_description[setup_tools]=Tools
    component_description[vault]=Vault
    component_description[wsl]="WSL 2"
    component_description[personal_profiles]='Personal & companies'
    component_description[workbenches_account]='Workstation account'
    component_status[personal_profiles]=optional
    requirement_items=(docker setup_tools vault)
    if is_wsl_windows; then requirement_items=(wsl "${requirement_items[@]}"); fi
}

load_requirements() {
    local key label state detail
    setup_os_label="$(workbenches_setup_os)"
    while IFS=$'\t' read -r key label state detail; do
        component_description[$key]="$label"
        component_status[$key]="$state"
        setup_sanitize_text detail "$detail"
        requirement_detail[$key]="$detail"
        component_checked[$key]=${component_checked[$key]:-false}
    done < <(workbenches_requirement_rows)
    component_status[workbenches_account]="$(python3 "$SCRIPT_DIR/setup-workbenches-account.py" --status)"
    requirement_detail[workbenches_account]='Organization sign-in. AI and vault access are managed separately.'
    component_status[ai_accounts]="$(check_component_status ai_accounts)"
    requirement_detail[ai_accounts]='Sign in, restore assistant profiles, or recover credentials from a vault.'
}

draw_requirements() {
    local -a setup_frame_lines=()
    local setup_frame_region_height=0
    setup_frame_workstation
    printf '%s\n' "${setup_frame_lines[@]}"
}

# Cached profile summary only: rendering never reads files or probes accounts.
draw_profiles() {
    local -a setup_frame_lines=()
    local setup_frame_region_height=0
    setup_frame_identities
    setup_frame_profiles
    printf '%s\n' "${setup_frame_lines[@]}"
}

activate_profile() {
    local item="${profile_items[$current_selection]}" result=0
    if ! setup_required_ready; then
        requirements_notice='Resolve Requirements before opening profile actions.'
        return 0
    fi
    stop_status_loader
    printf '%b\033[%d;1H' "$SHOW_CURSOR" "$(( ${#setup_ui_previous_lines[@]} + 1 ))"
    setup_ui_painted=false
    trap ':' INT
    case "$item" in
        personal_profiles) python3 "$SCRIPT_DIR/setup-profiles.py" || result=$? ;;
        workbenches_account) python3 "$SCRIPT_DIR/setup-workbenches-account.py" || result=$? ;;
        ai_accounts) configure_selected_accounts || result=$? ;;
    esac
    trap 'echo -e "${SHOW_CURSOR}"; exit 130' INT
    case "$result" in
        0) requirements_notice='Profile action completed.' ;;
        130) requirements_notice='Profile action cancelled; saved profiles kept.' ;;
        143) exit 143 ;;
        *) requirements_notice='Profile action needs attention. Open it to retry.' ;;
    esac
    profiles_summary="$(python3 "$SCRIPT_DIR/setup-profiles.py" --summary 2>/dev/null)" || profiles_summary='Profile metadata needs attention.'
    setup_sanitize_identities profiles_summary "$profiles_summary"
    refresh_component_statuses
}

# Service buttons act immediately; installation selections remain untouched.
activate_requirement() {
    local key=$1 action result=0
    if [[ "${component_status[$key]}" == loading || ( "$key" == vault && "${component_status[workbenches_account]}" == loading ) ]]; then
        requirements_notice='Checks are still loading. Q quits.'
        draw_ui
        return 0
    fi
    stop_status_loader
    action="$(workbenches_requirement_action "$key" "${component_status[$key]}" "${component_status[workbenches_account]}")"
    requirements_notice=''
    # Interactive helpers can write anywhere on screen. Repaint once on return.
    if [[ "$action" != Check ]]; then
        # A partial update leaves the cursor on whichever row changed last.
        # Put prompts below the TUI before handing the terminal to a helper.
        printf '%b\033[%d;1H' "$SHOW_CURSOR" "$(( ${#setup_ui_previous_lines[@]} + 1 ))"
        setup_ui_painted=false
    fi
    case "$action" in
        Connect|'Sign out')
            # Canceling the browser approval returns to the TUI, rather than
            # canceling an unrelated component installation plan.
            trap ':' INT
            if [[ "$action" == Connect ]]; then
                python3 "$SCRIPT_DIR/setup-workbenches-account.py" || result=$?
            else
                python3 "$SCRIPT_DIR/setup-workbenches-account.py" --logout || result=$?
            fi
            trap 'echo -e "${SHOW_CURSOR}"; exit 130' INT
            case "$result" in
                0) component_checked[workbenches_account]=false; component_action[workbenches_account]='' ;;
                130) requirements_notice='Connection cancelled.' ;;
                143) exit 143 ;;
                *) requirements_notice='Connection needs attention. Select Connect to retry.' ;;
            esac ;;
        Check) ;;
        *)
            if [[ "$key" == docker ]]; then
                ensure_docker "--${action,,}" && ensure_workstation_requirements || result=$?
            elif [[ "$key" == vault ]]; then
                ensure_workstation_requirements && workbenches_vault_start || result=$?
            else
                ensure_workstation_requirements || result=$?
            fi
            setup_propagate_cancel "$result"
            [[ "$result" == 0 ]] || requirements_notice="$action failed. Check Docker access and try again." ;;
    esac
    setup_sanitize_text requirements_notice "$requirements_notice"
    refresh_component_statuses
    draw_ui
    return 0
}

draw_requirement_item() {
    local item="$1" kind="$2" marker=' ' icon='✓' color="$GREEN" surface="$SILVER"
    local status detail line action width=$((setup_ui_width - 4))
    status="$(setup_status_label "${component_status[$item]}")"
    if [[ "$kind" == optional && "$item" != vault ]]; then
        icon='[ ]'; color="$SILVER_MUTED"
        case "${component_status[$item]}" in
            configured|installed) status='Connected'; color="$GREEN" ;;
            'signed in') status='Signed in'; color="$GREEN" ;;
            *) status='Not connected' ;;
        esac
        if [[ "${component_checked[$item]}" == true ]]; then
            icon='[✓]'; status='Selected'; color="$GREEN"
        fi
    elif [[ "${component_status[$item]}" == loading ]]; then
        icon='…'; color="$LOADING_COLOR"
    elif [[ "${component_status[$item]}" != up ]]; then
        icon='!'; color="$YELLOW"
    fi
    case "$item" in
        docker|wsl|setup_tools|vault)
            action="$(workbenches_requirement_action "$item" "${component_status[$item]}" "${component_status[workbenches_account]}")"
            if [[ "$item" == vault && "${component_status[$item]}" == up ]]; then
                if [[ "${component_status[workbenches_account]}" == 'signed in' ]]; then status+=' · Signed in'; else status+=' · Signed out'; fi
            fi
            [[ "${component_status[$item]}" == loading ]] || status+="  [$action]" ;;
    esac
    if [[ "$item" == "${requirement_items[$current_selection]}" ]]; then
        marker='›'; surface="$SILVER_FOCUS"
    fi
    line="$(setup_ui_pair "${component_description[$item]}" "$status" "$((width - ${#icon} - 3))")"
    printf '%b│%b %b%s %b%s%b %s %b%b│%b\n' "$SILVER_EDGE" "$NC" "$surface" "$marker" "$color" "$icon" "$surface" "$line" "$NC" "$SILVER_EDGE" "$NC"
    detail="${requirement_detail[$item]}"
    # Only the focused row needs its explanation; avoid repeated paragraphs.
    if [[ "$marker" == '›' ]]; then
        while [[ -n "$detail" ]]; do
            line="${detail:0:$((width - 4))}"
            if (( ${#detail} > width - 4 )) && [[ "$line" == *' '* ]]; then
                line="${line% *}"
            fi
            detail="${detail:${#line}}"
            detail="${detail# }"
            printf '%b│%b     %b%-*s %b│%b\n' "$SILVER_EDGE" "$NC" "$SILVER_MUTED" "$((width - 4))" "$line" "$SILVER_EDGE" "$NC"
        done
    fi
}

# Compare GitHub repository identities across HTTPS and SSH clone URLs.
normalize_bench_remote() {
    local url="$1"
    case "${url,,}" in
        https://github.com/*|ssh://git@github.com/*|git@github.com:*)
            url="${url,,}"
            case "$url" in
                https://github.com/*) url="${url#https://github.com/}" ;;
                ssh://git@github.com/*) url="${url#ssh://git@github.com/}" ;;
                git@github.com:*) url="${url#git@github.com:}" ;;
            esac
            url="${url%/}"
            printf 'github.com/%s\n' "${url%.git}"
            ;;
        *) printf '%s\n' "$url" ;;
    esac
}

component_binary_present() {
    [[ "$(python3 "$SCRIPT_DIR/setup-components.py" tool-status "$1")" == installed ]]
}

# Resolve only catalogued paths beneath supported bench roots.
bench_checkout_path() {
    local catalog_name="$1" catalog_output="$2" catalog_path
    local catalog_file="$SCRIPT_DIR/../config/bench-config.json"
    printf -v "$catalog_output" '%s' ''
    catalog_path=$(jq -r --arg n "$catalog_name" '.benches[$n].path // empty' "$catalog_file" 2>/dev/null) || return 1
    case "$catalog_path" in
        devBenches/?*|sysBenches/?*|bioBenches/?*) ;;
        *) return 1 ;;
    esac
    [[ "/$catalog_path/" != */../* ]] || return 1
    printf -v "$catalog_output" '%s' "$catalog_path"
}

# Check current installation status
check_component_status() {
    local component="$1"
    log "Checking status: $component"
    if [[ -n "${host_tool_status[$component]:-}" ]] && { ! is_wsl_windows || { [[ -z "${setup_reference_labels[$component]:-}" ]] && [[ ! "$component" =~ ^(vscode|warp|wave|amnezia_vpn|0dcloud_vpn)$ ]]; }; }; then
        printf '%s\n' "${host_tool_status[$component]}"; return
    fi

    if [[ -n "${setup_reference_labels[$component]:-}" ]]; then
        if is_wsl_windows; then echo 'needs check'
        else python3 "$SCRIPT_DIR/setup-components.py" tool-status "$component"; fi
        return
    fi
    if [[ -n "${setup_managed_harnesses[$component]:-}" ]]; then
        python3 "$SCRIPT_DIR/setup-components.py" tool-status "$component"
        return
    fi
    case "$component" in
        host_shell)
            if [[ -f "$HOME/.zshrc" ]] && cmp -s "$HOME/.zshrc" "$SCRIPT_DIR/../config/shell/zshrc"; then echo configured; else echo optional; fi
            ;;
        workspace_repo)
            [[ -f "${AGENT_PROTOCOL_ROOT:-$HOME/.agents}/workspace.yaml" ]] && echo configured || echo optional
            ;;
        ai_accounts)
            if compgen -G "${XDG_CONFIG_HOME:-$HOME/.config}/workbenches/*-profiles.json" >/dev/null; then echo configured; else echo optional; fi
            ;;
        claude_cli)
            if component_binary_present claude_cli; then
                # Check if credentials exist
                if python3 "$SCRIPT_DIR/profile_credentials.py" status claude; then
                    echo "installed"
                else
                    echo "needs creds"
                fi
            else
                echo "not installed"
            fi
            ;;
        copilot_cli)
            if component_binary_present copilot_cli; then
                echo "installed"
            else
                echo "not installed"
            fi
            ;;
        codex_cli)
            if component_binary_present codex_cli; then
                # Check if authenticated (auth.json or API key)
                if python3 "$SCRIPT_DIR/profile_credentials.py" status codex; then
                    echo "installed"
                else
                    echo "needs creds"
                fi
            else
                echo "not installed"
            fi
            ;;
        antigravity_cli)
            if component_binary_present antigravity_cli; then
                echo "installed"
            else
                echo "not installed"
            fi
            ;;
        opencode_cli)
            if component_binary_present opencode_cli; then
                if python3 "$SCRIPT_DIR/profile_credentials.py" status omniroute; then
                    echo "installed"
                else
                    echo "needs creds"
                fi
            else
                echo "not installed"
            fi
            ;;
        pi_cli)
            if component_binary_present pi_cli; then
                if python3 "$SCRIPT_DIR/profile_credentials.py" status pi; then
                    echo "installed"
                else
                    echo "needs creds"
                fi
            else
                echo "not installed"
            fi
            ;;
        spec_kit)
            python3 "$SCRIPT_DIR/setup-components.py" tool-status spec_kit
            ;;
        openspec)
            python3 "$SCRIPT_DIR/setup-components.py" tool-status openspec
            ;;
        vscode)
            # Check for VS Code - on WSL, check for Windows version
            if is_wsl_windows; then
                # WSL: Check for Windows VS Code and WSL extension
                if windows_file_exists "C:\\Program Files\\Microsoft VS Code\\Code.exe" ||
                   windows_env_file_exists "LOCALAPPDATA" "Programs\\Microsoft VS Code\\Code.exe"; then
                    # VS Code is installed, check for WSL extension by checking vscode-server directory
                    if [ -d "$HOME/.vscode-server" ]; then
                        # Check if Dev Containers extension is installed on Windows side
                        local windows_user=$(run_windows_powershell "[Environment]::UserName" 2>/dev/null)
                        local windows_ext_file="/mnt/c/Users/$windows_user/.vscode/extensions/extensions.json"

                        if [ -f "$windows_ext_file" ] && grep -q "ms-vscode-remote.remote-containers" "$windows_ext_file" 2>/dev/null; then
                            echo "installed"
                        else
                            echo "needs creds"  # Using "needs creds" status to indicate missing Dev Containers extension
                        fi
                    else
                        echo "needs creds"  # Using "needs creds" status to indicate missing WSL extension
                    fi
                else
                    echo "not installed"
                fi
            else
                # Native Linux: Check for Linux VS Code
                python3 "$SCRIPT_DIR/setup-components.py" tool-status vscode
            fi
            ;;
        warp)
            # Check for warp - on WSL, check for Windows version
            if is_wsl_windows; then
                # WSL: Check for Windows Warp
                if windows_file_exists "C:\\Program Files\\Warp\\Warp.exe" ||
                   windows_env_file_exists "LOCALAPPDATA" "Programs\\Warp\\Warp.exe"; then
                    echo "installed"
                else
                    echo "not installed"
                fi
            else
                # Native Linux: Check for Linux Warp
                python3 "$SCRIPT_DIR/setup-components.py" tool-status warp
            fi
            ;;
        wave)
            # Check for wave terminal - on WSL, check for Windows version
            if is_wsl_windows; then
                # WSL: Check for Windows Wave in common locations
                if windows_file_exists "C:\\Program Files\\Wave\\Wave.exe" ||
                   windows_env_file_exists "LOCALAPPDATA" "Programs\\waveterm\\Wave.exe" ||
                   windows_env_file_exists "LOCALAPPDATA" "Programs\\Wave\\Wave.exe"; then
                    echo "installed"
                else
                    echo "not installed"
                fi
            else
                # Native Linux: Check for Linux Wave
                python3 "$SCRIPT_DIR/setup-components.py" tool-status wave
            fi
            ;;
        amnezia_vpn)
            if [ -n "$WSL_DISTRO_NAME" ] || grep -qi microsoft /proc/version 2>/dev/null; then
                if windows_file_exists "C:\\Program Files\\AmneziaVPN\\AmneziaVPN.exe" ||
                   windows_file_exists "C:\\Program Files\\AmneziaVPN.ORG\\AmneziaVPN\\AmneziaVPN.exe"; then
                    echo "installed"
                else
                    echo "not installed"
                fi
            else
                python3 "$SCRIPT_DIR/setup-components.py" tool-status amnezia_vpn
            fi
            ;;
        0dcloud_vpn)
            if [ -n "$WSL_DISTRO_NAME" ] || grep -qi microsoft /proc/version 2>/dev/null; then
                if windows_file_exists "C:\\Program Files\\0dcloud\\0dcloud.exe"; then
                    echo "installed"
                else
                    echo "not installed"
                fi
            else
                python3 "$SCRIPT_DIR/setup-components.py" tool-status 0dcloud_vpn
            fi
            ;;
        bench_*)
            # Check if bench directory exists, has correct git remote, and is set up
            local bench_name="${component#bench_}"
            local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
            local config_file="$script_dir/../config/bench-config.json"

            # Get the path and URL from config
            local bench_path
            if ! bench_checkout_path "$bench_name" bench_path; then
                echo "needs check"
                return
            fi
            local bench_url=$(jq -r --arg n "$bench_name" '.benches[$n].url // empty' "$config_file" 2>/dev/null)

            local full_path="$script_dir/../$bench_path"

            # Check if directory exists
            if [ -d "$full_path" ]; then
                # Check if it has a git remote
                if { [ -d "$full_path/.git" ] || [ -f "$full_path/.git" ]; } && \
                   git -C "$full_path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
                    # Verify it has the correct remote (if URL is configured)
                    if [ -n "$bench_url" ] && [ "$bench_url" != "null" ]; then
                        local current_remote=$(cd "$full_path" && git remote get-url origin 2>/dev/null)
                        if [ "$(normalize_bench_remote "$current_remote")" = "$(normalize_bench_remote "$bench_url")" ]; then
                            # Bench is installed with correct remote, check if it has infrastructure
                            if [ -d "$full_path/.devcontainer" ] || \
                               [ -d "$full_path/devcontainer.example" ] || \
                               [ -f "$full_path/Dockerfile.layer2" ] || \
                               [ -f "$full_path/setup.sh" ] || \
                               [ -f "$full_path/build-layer.sh" ] || \
                               [ -f "$full_path/scripts/build-layer.sh" ]; then
                                bench_installation_status "$bench_name"
                            else
                                echo "needs setup"
                            fi
                        else
                            echo "needs check"  # Different checkout: never execute its setup script.
                        fi
                    else
                        # No URL configured, just check if it's a git repo
                        bench_installation_status "$bench_name"
                    fi
                else
                    echo "not installed"  # Directory exists but not a git repo
                fi
            else
                # Installed artifacts can remain after a checkout was removed.
                local runtime="$(bench_installation_status "$bench_name")"
                if [[ "$runtime" == 'needs setup' ]]; then echo 'not installed'; else echo "$runtime"; fi
            fi
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# A checkout is source availability; installed bench images/containers are runtime.
refresh_bench_inventory() {
    local bench state
    bench_runtime_status=()
    while IFS=$'\t' read -r bench state; do
        [[ -n "$bench" ]] && bench_runtime_status[$bench]="$state"
    done < <(python3 "$SCRIPT_DIR/setup-components.py" bench-statuses)
}

bench_installation_status() {
    local bench="$1"
    [[ -n "${bench_runtime_status[$bench]:-}" ]] || refresh_bench_inventory
    echo "${bench_runtime_status[$bench]:-needs check}"
}

refresh_component_statuses() {
    if [[ "$status_async_ui" == true ]]; then start_status_loader; return; fi
    refresh_host_tool_inventory
    local item
    setup_load_bench_metadata_sync
    refresh_bench_inventory
    for item in "${!component_description[@]}"; do
        case "$item" in docker|wsl|setup_tools|workbenches_account) continue ;; esac
        component_status[$item]="$(check_component_status "$item")"
    done
    load_requirements
    host_tool_status=()
}

uninstall_component() {
    local item="$1" removal_status=0
    [[ -z "${setup_reference_labels[$item]:-}" ]] || { echo 'Manage this entry with its original installer; see About.'; return 1; }
    if is_wsl_windows && [[ "$item" =~ ^(vscode|warp|wave|amnezia_vpn|0dcloud_vpn)$ ]]; then
        local target="$item"
        [[ "$item" != amnezia_vpn ]] || target=amnezia
        [[ "$item" != 0dcloud_vpn ]] || target=0dcloud
        "$SCRIPT_DIR/setup-windows-tools.sh" --uninstall "$target" || removal_status=$?
    else
        python3 "$SCRIPT_DIR/setup-components.py" uninstall "$item" || removal_status=$?
    fi
    setup_propagate_cancel "$removal_status"
    hash -r
    if [[ "$item" == bench_* ]]; then refresh_bench_inventory; fi
    component_status[$item]="$(check_component_status "$item")"
    if [[ "$removal_status" -eq 0 && ( "${component_status[$item]}" == installed || "${component_status[$item]}" == 'needs creds' ) ]]; then
        echo "Removal needs attention: $item is still installed."
        return 1
    fi
    return "$removal_status"
}

# Load all component statuses
load_statuses() {
    refresh_host_tool_inventory
    refresh_bench_inventory
    # Load statuses for benches
    for bench in "${bench_items[@]}"; do
        local key="bench_$bench"
        local status=$(check_component_status "$key")
        component_status["$key"]="$status"

        component_checked["$key"]=false
        component_action["$key"]=""
    done

    # Load statuses for AI items
    for item in "${ai_items[@]}"; do
        if [[ "$item" == separator* ]]; then
            continue
        fi
        local status=$(check_component_status "$item")
        component_status["$item"]="$status"

        component_checked["$item"]=false
        component_action["$item"]=""
    done

    # Load statuses for tool items
    for item in "${tool_items[@]}"; do
        local status=$(check_component_status "$item")
        component_status["$item"]="$status"

        component_checked["$item"]=false
        component_action["$item"]=""
    done
    load_requirements
    host_tool_status=()
}

# Draw a single component line
draw_component() {
    local index="$1"
    local component="${component_order[$index]}"
    local is_selected=$2
    local status="${component_status[$component]}"
    local checked="${component_checked[$component]}"
    local desc="${component_description[$component]}"

    # Determine checkbox state
    local checkbox="[ ]"
    if [ "$checked" = true ]; then
        checkbox="[${GREEN}✓${NC}]"
    fi

    # Determine status color
    local status_color="$RED"
    local status_symbol="✗"
    if [[ "$status" == loading ]]; then
        status_color="$LOADING_COLOR"
        status_symbol="…"
    elif [[ "$status" == "installed" || "$status" == "configured" ]]; then
        status_color="$GREEN"
        status_symbol="✓"
    elif [[ "$status" == "needs creds" || "$status" == "needs setup" || "$status" == "needs check" || "$status" == "needs docker" || "$status" == 'image only' ]]; then
        status_color="$YELLOW"
        status_symbol="⚠"
    fi

    # Selection highlight
    local line_prefix="  "
    local line_suffix=""
    if [ "$is_selected" = true ]; then
        line_prefix="${CYAN}▶ "
        line_suffix="${NC}"
    fi

    echo -e "${line_prefix}${checkbox} ${status_color}${status_symbol}${NC} ${desc}${line_suffix}"
}

# Draw block header
draw_block_header() {
    local block_num="$1"
    local is_current=$2
    local block_name="${block_names[$block_num]}"

    if [ "$is_current" = true ]; then
        echo -e "\n${BOLD}${YELLOW}┌─ ${block_name} ─┐${NC}"
    else
        echo -e "\n${DIM}┌─ ${block_name} ─┐${NC}"
    fi
}

# Track previous state for selective redraw
prev_selection=-1
prev_section=-1
prev_checked_state=""

# A variable-returning signature avoids a subshell for every key and idle tick.
setup_update_ui_signature() {
    local signature_key
    local signature_filters
    setup_cli_filter_key_v signature_filters
    setup_ui_signature="$signature_filters:$setup_cli_filter_row:$setup_harness_zone:$setup_harness_category:$setup_tool_zone:$setup_tool_category:$CURRENT_SECTION:$current_selection:${setup_bench_zone:-category}:${setup_bench_category:-}:${setup_about_offset:-0}:${setup_review_offset:-0}:${setup_list_offset:-0}:$setup_ui_width:$setup_ui_height:$requirements_notice:$profiles_summary"
    for signature_key in "${!component_description[@]}"; do
        setup_ui_signature+=";$signature_key:${component_status[$signature_key]}:${component_checked[$signature_key]}:${component_action[$signature_key]}:${requirement_detail[$signature_key]}"
    done
    for signature_key in "${!setup_bench_offset[@]}"; do
        setup_ui_signature+=";offset:$signature_key:${setup_bench_offset[$signature_key]}"
    done
}

# Get current checked state as string (for change detection)
get_checked_state() {
    local state=""
    for bench in "${bench_items[@]}"; do
        state+="${component_checked[bench_$bench]}:${component_action[bench_$bench]},"
    done
    for item in "${ai_items[@]}"; do
        [[ "$item" != separator* ]] && state+="${component_checked[$item]}:${component_action[$item]},"
    done
    for item in "${tool_items[@]}"; do
        state+="${component_checked[$item]}:${component_action[$item]},"
    done
    for item in vault workbenches_account ai_accounts; do
        state+="${component_checked[$item]}:${component_action[$item]},"
    done
    echo "$state"
}

# Update only the section headers line

# Redraw just the three sections content (not the whole UI)

# Update only the lines affected by cursor movement

# Draw a single item line for a section

# Draw a complete row (all 3 columns) for a given index

# Build a complete frame off-screen; discovery never runs in the renderer.

# Arrival-independent layout primitives; every frame path uses Bash builtins.
setup_ui_layout=roomy
setup_list_offset=0
setup_about_offset=0
setup_about_anchor=''
setup_about_window=2
setup_about_cache_key=''
declare -a setup_about_lines=()
declare -A setup_bench_offset setup_rule_cache setup_panel_cache
setup_banner_cache_key=''
declare -a setup_banner_lines=()

setup_frame_append() {
    setup_frame_lines+=("$1")
    setup_frame_region_height=$((setup_frame_region_height + 1))
}

setup_frame_row() {
    local frame_row
    setup_ui_pair_v frame_row "$1" "${2:-}" "$((setup_ui_width - 4))"
    printf -v frame_row '%b│%b %s%b %b│%b' "$SILVER_EDGE" "${3:-$NC}" "$frame_row" "$NC" "$SILVER_EDGE" "$NC"
    setup_frame_append "$frame_row"
}

setup_ui_list_window() {
    local window_total=$1 window_focus=$2 window_budget=$3 window_offset=${!4:-0} window_count window_try
    setup_window_above=0; setup_window_below=0
    if (( window_budget <= 0 || window_total <= window_budget )); then
        window_offset=0; window_count=$window_total
    else
        window_count=$((window_budget - 2)); ((window_count > 0)) || window_count=1
        for ((window_try=0; window_try<4; window_try++)); do
            (( window_offset <= window_focus )) || window_offset=$window_focus
            (( window_focus < window_offset + window_count )) || window_offset=$((window_focus - window_count + 1))
            (( window_offset >= 0 )) || window_offset=0
            (( window_offset + window_count <= window_total )) || window_offset=$((window_total - window_count))
            setup_window_above=$window_offset
            setup_window_below=$((window_total - window_offset - window_count))
            window_count=$window_budget
            (( setup_window_above == 0 )) || ((window_count--))
            (( setup_window_below == 0 )) || ((window_count--))
            ((window_count > 0)) || window_count=1
        done
        setup_window_above=$window_offset
        setup_window_below=$((window_total - window_offset - window_count))
    fi
    setup_window_start=$window_offset; setup_window_count=$window_count
    printf -v "$4" '%s' "$window_offset"
}

setup_ui_wrap() {
    local wrap_text="$1" wrap_width=$2 wrap_line='' wrap_word wrap_paragraph
    local -a wrap_words=()
    setup_wrapped_lines=()
    while IFS= read -r wrap_paragraph; do
        IFS=' ' read -r -a wrap_words <<< "$wrap_paragraph"
        wrap_line=''
        for wrap_word in "${wrap_words[@]}"; do
            if (( ${#wrap_line} + ${#wrap_word} + 1 > wrap_width )) && [[ -n "$wrap_line" ]]; then
                setup_wrapped_lines+=("$wrap_line"); wrap_line=''
            fi
            while (( ${#wrap_word} > wrap_width )); do
                setup_wrapped_lines+=("${wrap_word:0:wrap_width}"); wrap_word="${wrap_word:wrap_width}"
            done
            [[ -z "$wrap_line" ]] || wrap_line+=' '
            wrap_line+="$wrap_word"
        done
        setup_wrapped_lines+=("$wrap_line")
    done <<< "$wrap_text"
}

setup_about_scroll() {
    local about_step=$((setup_about_window - 1))
    ((about_step > 0)) || about_step=1
    setup_about_offset=$((setup_about_offset + $1 * about_step))
    ((setup_about_offset >= 0)) || setup_about_offset=0
    local about_max=$(( ${#setup_about_lines[@]} - setup_about_window ))
    ((about_max >= 0)) || about_max=0
    ((setup_about_offset <= about_max)) || setup_about_offset=$about_max
}

setup_frame_about() {
    local about_anchor="$1" about_title="$2" about_text="$3" about_window=$4
    local about_key="$1:$setup_ui_width:$setup_ui_height:$4:$3" about_total about_max about_range='' about_line about_index about_hint=''
    if [[ "$setup_about_anchor" != "$about_anchor" ]]; then setup_about_offset=0; fi
    setup_about_anchor="$about_anchor"
    if [[ "$setup_about_cache_key" != "$about_key" ]]; then
        setup_ui_wrap "$about_text" "$((setup_ui_width - 4))"
        # Leave room for paging markers without hiding any body characters.
        if [[ -n "$setup_ui_height" ]] && (( ${#setup_wrapped_lines[@]} > about_window )); then
            setup_ui_wrap "$about_text" "$((setup_ui_width - 11))"
        fi
        setup_about_lines=("${setup_wrapped_lines[@]}")
        setup_about_cache_key="$about_key"
    fi
    about_total=${#setup_about_lines[@]}
    [[ -n "$setup_ui_height" ]] || about_window=$about_total
    ((about_window > 0)) || about_window=1
    setup_about_window=$about_window
    about_max=$((about_total - about_window)); ((about_max >= 0)) || about_max=0
    ((setup_about_offset <= about_max)) || setup_about_offset=$about_max
    if ((about_max > 0)); then
        about_range="$((setup_about_offset+1))–$((setup_about_offset+about_window)) of $about_total"
        about_hint='PgUp/PgDn scroll'
    fi
    setup_panel_top_v about_line "$about_title" "$about_range"; setup_frame_append "$about_line"
    for ((about_index=setup_about_offset; about_index<about_total && about_index<setup_about_offset+about_window; about_index++)); do
        about_line="${setup_about_lines[about_index]}"
        if (( about_index == setup_about_offset && setup_about_offset > 0 )); then about_line="▲ more $about_line"; fi
        if (( about_index == setup_about_offset+about_window-1 && about_index+1 < about_total )); then about_line="▼ more $about_line"; fi
        setup_frame_row "$about_line"
    done
    if [[ -n "$about_hint" ]]; then
        setup_panel_top_v about_line "$about_hint" ''
        about_line="${about_line//╭/╰}"; about_line="${about_line//╮/╯}"
    else
        setup_panel_bottom_v about_line
    fi
    setup_frame_append "$about_line"
}

setup_frame_fit() {
    if [[ -n "$setup_ui_height" ]] && (( ${#setup_frame_lines[@]} > setup_ui_height )); then
        setup_frame_lines=("${setup_frame_lines[@]:${#setup_frame_lines[@]}-setup_ui_height}")
    fi
}

declare -a setup_frame_lines=()
setup_frame_region_height=0

setup_step_sections=(3 0 1 2 4 5)
setup_step_names=(Workstation Benches Harness Tools Profiles Review)
setup_section_step=([3]=0 [0]=1 [1]=2 [2]=3 [4]=4 [5]=5)
setup_bench_zone=category
setup_bench_category=''
setup_harness_zone=category
setup_harness_category=tui
declare -A setup_harness_offsets=()
setup_tool_zone=category
setup_tool_category=editors
declare -A setup_tool_offsets=()
setup_review_offset=0

requirements_return_set=false
profiles_return_set=false

setup_remember_target() {
    local target_prefix="$1" target_bench=''
    if [[ "$CURRENT_SECTION" == 0 && "$setup_bench_zone" == bench ]]; then target_bench="${bench_items[$current_selection]}"; fi
    printf -v "${target_prefix}_return_section" '%s' "$CURRENT_SECTION"
    printf -v "${target_prefix}_return_selection" '%s' "$current_selection"
    printf -v "${target_prefix}_return_zone" '%s' "$setup_bench_zone"
    printf -v "${target_prefix}_return_category" '%s' "$setup_bench_category"
    printf -v "${target_prefix}_return_bench" '%s' "$target_bench"
    local target_facet
    printf -v "${target_prefix}_return_filter_row" '%s' "$setup_cli_filter_row"
    for target_facet in "${setup_cli_filter_rows[@]}"; do
        printf -v "${target_prefix}_return_filter_${target_facet}" '%s' "${setup_cli_filter_selected[$target_facet]:-}"
    done
    printf -v "${target_prefix}_return_harness_zone" '%s' "$setup_harness_zone"
    printf -v "${target_prefix}_return_harness_category" '%s' "$setup_harness_category"
    printf -v "${target_prefix}_return_tool_zone" '%s' "$setup_tool_zone"
    printf -v "${target_prefix}_return_tool_category" '%s' "$setup_tool_category"
    printf -v "${target_prefix}_return_list_offset" '%s' "$setup_list_offset"
    printf -v "${target_prefix}_return_about_offset" '%s' "$setup_about_offset"
    printf -v "${target_prefix}_return_about_anchor" '%s' "$setup_about_anchor"
    printf -v "${target_prefix}_return_review_offset" '%s' "$setup_review_offset"
    printf -v "${target_prefix}_return_set" '%s' true
}

setup_restore_target() {
    local target_prefix="$1" target_field="${1}_return_set" target_bench target_index
    if [[ "${!target_field}" != true ]]; then setup_arrive_step 0; return; fi
    target_field="${target_prefix}_return_section"; CURRENT_SECTION=${!target_field}
    target_field="${target_prefix}_return_selection"; current_selection=${!target_field}
    target_field="${target_prefix}_return_zone"; setup_bench_zone=${!target_field}
    target_field="${target_prefix}_return_category"; setup_bench_category=${!target_field}
    target_field="${target_prefix}_return_review_offset"; setup_review_offset=${!target_field}
    local target_facet
    target_field="${target_prefix}_return_filter_row"; setup_cli_filter_row=${!target_field:-0}
    for target_facet in "${setup_cli_filter_rows[@]}"; do
        target_field="${target_prefix}_return_filter_${target_facet}"; setup_cli_filter_selected[$target_facet]=${!target_field:-all}
    done
    setup_cli_filter_cache_key=''
    target_field="${target_prefix}_return_harness_zone"; setup_harness_zone=${!target_field:-category}
    target_field="${target_prefix}_return_harness_category"; setup_harness_category=${!target_field:-tui}
    target_field="${target_prefix}_return_tool_zone"; setup_tool_zone=${!target_field:-category}
    target_field="${target_prefix}_return_tool_category"; setup_tool_category=${!target_field:-editors}
    target_field="${target_prefix}_return_list_offset"; setup_list_offset=${!target_field:-0}
    target_field="${target_prefix}_return_about_offset"; setup_about_offset=${!target_field:-0}
    target_field="${target_prefix}_return_about_anchor"; setup_about_anchor=${!target_field:-}
    target_field="${target_prefix}_return_bench"; target_bench=${!target_field}
    if [[ "$CURRENT_SECTION" == 0 && -n "$target_bench" ]]; then
        for target_index in "${!bench_items[@]}"; do
            [[ "${bench_items[target_index]}" != "$target_bench" ]] || current_selection=$target_index
        done
    fi
}

setup_benches_seen_catalog=false

setup_reconcile_bench_focus() {
    local focus_name="$1" focus_prefix focus_field focus_return_name focus_category focus_index focus_found=false
    [[ "$setup_catalog_loaded" == true ]] || return 0
    if [[ "$CURRENT_SECTION" == 0 ]]; then
        if [[ "$setup_benches_seen_catalog" != true ]]; then
            setup_bench_zone=category; setup_bench_category="${setup_bench_categories_focusable[0]:-}"
        elif [[ "$setup_bench_zone" == bench && -n "$focus_name" ]]; then
            if setup_focus_bench_name "$focus_name"; then
                setup_bench_category="${setup_bench_category_of[$focus_name]}"; focus_found=true
            else setup_bench_zone=category; fi
        fi
        if [[ "$focus_found" != true ]]; then
            if [[ -z "$setup_bench_category" || "${setup_bench_totals[$setup_bench_category]:-0}" == 0 ]]; then
                setup_bench_category="${setup_bench_categories_focusable[0]:-}"
            fi
            if [[ -n "$setup_bench_category" ]]; then
                local -a focus_members=()
                IFS=' ' read -r -a focus_members <<< "${setup_bench_members[$setup_bench_category]}"
                [[ -z "${focus_members[0]}" ]] || setup_focus_bench_name "${focus_members[0]}"
            fi
        fi
    fi
    for focus_prefix in requirements profiles; do
        focus_field="${focus_prefix}_return_bench"; focus_return_name=${!focus_field}
        [[ -n "$focus_return_name" ]] || continue
        focus_found=false
        for focus_index in "${!bench_items[@]}"; do
            if [[ "${bench_items[focus_index]}" == "$focus_return_name" ]]; then
                printf -v "${focus_prefix}_return_selection" '%s' "$focus_index"
                printf -v "${focus_prefix}_return_category" '%s' "${setup_bench_category_of[$focus_return_name]}"
                focus_found=true; break
            fi
        done
        if [[ "$focus_found" != true ]]; then
            focus_field="${focus_prefix}_return_category"; focus_category=${!focus_field}
            if [[ -z "$focus_category" || "${setup_bench_totals[$focus_category]:-0}" == 0 ]]; then focus_category="${setup_bench_categories_focusable[0]:-}"; fi
            printf -v "${focus_prefix}_return_zone" '%s' category
            printf -v "${focus_prefix}_return_category" '%s' "$focus_category"
            printf -v "${focus_prefix}_return_bench" '%s' ''
            printf -v "${focus_prefix}_return_selection" '%s' 0
        fi
    done
    setup_benches_seen_catalog=true
}

setup_focus_bench_name() {
    local focus_index
    for focus_index in "${!bench_items[@]}"; do
        [[ "${bench_items[focus_index]}" != "$1" ]] || { current_selection=$focus_index; return 0; }
    done
    return 1
}

setup_benches_key() {
    local zone_key="$1" zone_index=0 zone_name zone_bench_index=0
    local -a zone_members=()
    if [[ "$setup_benches_state" != ready ]]; then
        case "$zone_key" in up) return 0;; down) return 0;; tab) return 0;; backtab) return 0;; ' ') return 0;; d) return 0;; D) return 0;; esac
        return 1
    fi
    for zone_index in "${!setup_bench_categories_focusable[@]}"; do
        [[ "${setup_bench_categories_focusable[zone_index]}" != "$setup_bench_category" ]] && continue
        break
    done
    IFS=' ' read -r -a zone_members <<< "${setup_bench_members[$setup_bench_category]}"
    if [[ "$setup_bench_zone" == category ]]; then
        case "$zone_key" in
            up) ((zone_index <= 0)) || ((zone_index--)) ;;
            down)
                if ((zone_index + 1 < ${#setup_bench_categories_focusable[@]})); then ((zone_index++))
                else setup_bench_zone=bench; fi ;;
            tab) setup_bench_zone=bench ;;
            backtab) setup_bench_zone=bench ;;
            ' ') setup_bench_zone=bench ;;
            d) return 0 ;;
            D) return 0 ;;
            *) return 1 ;;
        esac
        setup_bench_category="${setup_bench_categories_focusable[zone_index]}"
        IFS=' ' read -r -a zone_members <<< "${setup_bench_members[$setup_bench_category]}"
        [[ -z "${zone_members[0]}" ]] || setup_focus_bench_name "${zone_members[0]}"
        setup_about_offset=0
        return 0
    fi
    for zone_bench_index in "${!zone_members[@]}"; do
        [[ "${zone_members[zone_bench_index]}" != "${bench_items[$current_selection]}" ]] && continue
        break
    done
    case "$zone_key" in
        up) if ((zone_bench_index > 0)); then ((zone_bench_index--)); else setup_bench_zone=category; fi ;;
        down) ((zone_bench_index + 1 >= ${#zone_members[@]})) || ((zone_bench_index++)) ;;
        tab) setup_bench_zone=category ;;
        backtab) setup_bench_zone=category ;;
        pageup) setup_about_scroll -1; return 0 ;;
        pagedown) setup_about_scroll 1; return 0 ;;
        *) return 1 ;;
    esac
    [[ -z "${zone_members[zone_bench_index]}" ]] || setup_focus_bench_name "${zone_members[zone_bench_index]}"
    setup_about_offset=0
    return 0
}

setup_category_summary_v() {
    local category_id="$2" category_text="${bench_category_label[$2]}" category_n=${setup_bench_totals[$2]:-0} category_installed=${setup_bench_installed[$2]:-0} category_queued=${setup_bench_queued[$2]:-0}
    if ((category_n == 0)); then category_text+=' · coming soon'
    else
        category_text+=" · $category_n bench"; ((category_n == 1)) || category_text+='es'
        ((category_installed == 0)) || category_text+=" · $category_installed installed"
        ((category_queued == 0)) || category_text+=" · $category_queued queued"
    fi
    printf -v "$1" '%s' "$category_text"
}

setup_frame_categories() {
    local category_id category_line category_marker category_color
    [[ "$setup_benches_state" == ready ]] || return 0
    [[ "$setup_ui_layout" != roomy ]] || setup_frame_append ''
    local category_min_benches=${setup_bench_totals[$setup_bench_category]:-0} category_needed
    ((category_min_benches <= 3)) || category_min_benches=3
    category_needed=$(( ${#setup_frame_lines[@]} + 1 + ${#setup_bench_categories[@]} + category_min_benches + 6 + setup_footer_height ))
    [[ "$setup_ui_layout" != roomy ]] || ((category_needed+=2))
    [[ -z "$requirements_notice" ]] || ((category_needed++))
    if [[ -n "$setup_ui_height" ]] && { ((setup_ui_height <= 24)) || ((category_needed > setup_ui_height)); }; then
        setup_categories_collapsed=true
        setup_category_summary_v category_line "$setup_bench_category"
        setup_ui_cut_v category_line "CATEGORY · $category_line" "$setup_ui_width"
        setup_frame_append "$category_line"
        return
    fi
    setup_categories_collapsed=false
    setup_ui_pair_v category_line CATEGORY 'Tab ⇄ benches' "$setup_ui_width"; setup_frame_append "$category_line"
    for category_id in "${setup_bench_categories[@]}"; do
        category_marker=○; category_color="$SILVER"
        [[ "$category_id" != "$setup_bench_category" ]] || category_marker=●
        (( ${setup_bench_totals[$category_id]:-0} > 0 )) || category_color="$SILVER_MUTED"
        setup_category_summary_v category_line "$category_id"
        setup_ui_cut_v category_line "$category_marker $category_line" "$setup_ui_width"
        printf -v category_line '%b%s%b' "$category_color" "$category_line" "$NC"
        setup_frame_append "$category_line"
    done
}

# Both catalogs use the same category/list navigation; indexes remain in the
# original flat arrays used by selection serialization and installers.
setup_catalog_members_v() {
    local members_value
    local -n members_map="setup_${2}_members"
    members_value="${members_map[$3]}"
    if [[ "$2" == harness && "$3" == tui ]]; then setup_cli_filters_refresh; members_value=$setup_cli_filter_members; fi
    printf -v "$1" '%s' "$members_value"
}

setup_cli_group_key() { setup_cli_filters_key "$1"; }

setup_focus_catalog_key() {
    local catalog_family="$1" catalog_key="$2" catalog_index
    local catalog_array=tool_items
    [[ "$catalog_family" != harness ]] || catalog_array=ai_items
    local -n catalog_items="$catalog_array"
    for catalog_index in "${!catalog_items[@]}"; do
        [[ "${catalog_items[catalog_index]}" != "$catalog_key" ]] || { current_selection=$catalog_index; return 0; }
    done
    return 1
}

setup_focus_tool_key() { setup_focus_catalog_key tool "$1"; }
setup_focus_harness_key() { setup_focus_catalog_key harness "$1"; }

setup_catalog_key() {
    local catalog_family="$1" catalog_key="$2" catalog_category_index=0 catalog_member_index=0 catalog_array=tool_items catalog_member_text
    if [[ "$catalog_family" == harness ]] && setup_cli_group_key "$catalog_key"; then return 0; fi
    local -n catalog_categories="setup_${catalog_family}_categories" catalog_members="setup_${catalog_family}_members"
    local -n catalog_category="setup_${catalog_family}_category" catalog_zone="setup_${catalog_family}_zone"
    [[ "$catalog_family" != harness ]] || catalog_array=ai_items
    local -n catalog_items="$catalog_array"
    local -a catalog_current_members=()
    for catalog_category_index in "${!catalog_categories[@]}"; do
        [[ "${catalog_categories[catalog_category_index]}" != "$catalog_category" ]] || break
    done
    setup_catalog_members_v catalog_member_text "$catalog_family" "$catalog_category"
    IFS=' ' read -r -a catalog_current_members <<< "$catalog_member_text"
    if [[ "$catalog_family" == harness && "$catalog_category" == tui && ${#catalog_current_members[@]} == 0 && "$catalog_zone" != category ]]; then
        case "$catalog_key" in
            up|tab|backtab) setup_harness_zone=category; setup_about_offset=0; return 0 ;;
            down|' '|d|D) return 0 ;;
            *) return 1 ;;
        esac
    fi
    if [[ "$catalog_zone" == category ]]; then
        case "$catalog_key" in
            up) ((catalog_category_index <= 0)) || ((catalog_category_index--)) ;;
            down) if ((catalog_category_index+1 < ${#catalog_categories[@]})); then ((catalog_category_index++)); else catalog_zone=$catalog_family; fi ;;
            tab|backtab|' ') catalog_zone=$catalog_family ;;
            d|D) return 0 ;;
            *) return 1 ;;
        esac
        catalog_category=${catalog_categories[catalog_category_index]}
        setup_catalog_members_v catalog_member_text "$catalog_family" "$catalog_category"
        IFS=' ' read -r -a catalog_current_members <<< "$catalog_member_text"
        ((${#catalog_current_members[@]} == 0)) || setup_focus_catalog_key "$catalog_family" "${catalog_current_members[0]}"
    else
        for catalog_member_index in "${!catalog_current_members[@]}"; do
            [[ "${catalog_current_members[catalog_member_index]}" != "${catalog_items[$current_selection]}" ]] || break
        done
        case "$catalog_key" in
            up) if ((catalog_member_index > 0)); then ((catalog_member_index--)); else catalog_zone=category; fi ;;
            down) ((catalog_member_index+1 >= ${#catalog_current_members[@]})) || ((catalog_member_index++)) ;;
            tab|backtab) catalog_zone=category ;;
            *) return 1 ;;
        esac
        setup_focus_catalog_key "$catalog_family" "${catalog_current_members[catalog_member_index]}"
    fi
    setup_about_offset=0
    return 0
}

setup_tools_key() { setup_catalog_key tool "$1"; }
setup_harnesses_key() { setup_catalog_key harness "$1"; }

setup_catalog_group_summary_v() {
    local group_key="$3" group_item group_count=0 group_ready=0 group_queued=0 group_text
    local -n group_members_map="setup_${2}_members" group_labels="setup_${2}_labels"
    local -a group_members=()
    IFS=' ' read -r -a group_members <<< "${group_members_map[$group_key]}"
    group_count=${#group_members[@]}
    for group_item in "${group_members[@]}"; do
        if [[ "${component_status[$group_item]}" == installed || "${component_status[$group_item]}" == 'needs creds' || "${component_status[$group_item]}" == 'image only' ]]; then ((group_ready++)); fi
        [[ "${component_checked[$group_item]}" != true || -z "${component_action[$group_item]}" ]] || ((group_queued++))
    done
    group_text="${group_labels[$group_key]} · $group_count item"
    ((group_count == 1)) || group_text+=s
    ((group_ready == 0)) || group_text+=" · $group_ready installed"
    ((group_queued == 0)) || group_text+=" · $group_queued queued"
    printf -v "$1" '%s' "$group_text"
}

setup_tool_group_summary_v() { setup_catalog_group_summary_v "$1" tool "$2"; }

setup_frame_catalog_categories() {
    local group_family=tool group_line group_key group_mark group_needed group_min=1 group_hint=tools
    [[ "$CURRENT_SECTION" != 1 ]] || { group_family=harness; group_hint=harnesses; }
    local -n group_categories="setup_${group_family}_categories" group_category="setup_${group_family}_category"
    [[ "$setup_ui_layout" != roomy ]] || setup_frame_append ''
    group_needed=$(( ${#setup_frame_lines[@]} + 1 + ${#group_categories[@]} + group_min + 6 + setup_footer_height ))
    [[ -z "$requirements_notice" ]] || ((group_needed++))
    [[ "$setup_ui_layout" != roomy ]] || ((group_needed+=2))
    if [[ -n "$setup_ui_height" ]] && { ((setup_ui_height <= 24)) || ((group_needed > setup_ui_height)); }; then
        setup_catalog_group_summary_v group_line "$group_family" "$group_category"
        setup_ui_cut_v group_line "CATEGORY · $group_line" "$setup_ui_width"
        setup_frame_append "$group_line"
        return
    fi
    setup_ui_pair_v group_line CATEGORY "Tab ⇄ $group_hint" "$setup_ui_width"; setup_frame_append "$group_line"
    for group_key in "${group_categories[@]}"; do
        group_mark=○; [[ "$group_key" != "$group_category" ]] || group_mark=●
        setup_catalog_group_summary_v group_line "$group_family" "$group_key"
        setup_ui_cut_v group_line "$group_mark $group_line" "$setup_ui_width"
        setup_frame_append "$group_line"
    done
}

setup_arrive_step() {
    CURRENT_SECTION=$1; current_selection=0; setup_list_offset=0; setup_about_offset=0
    if [[ "$CURRENT_SECTION" == 0 ]]; then
        setup_bench_zone=category
        setup_bench_category="${setup_bench_categories_focusable[0]:-}"
    fi
    if [[ "$CURRENT_SECTION" == 1 ]]; then setup_harness_zone=category; setup_harness_category=tui; fi
    if [[ "$CURRENT_SECTION" == 2 ]]; then setup_tool_zone=category; setup_tool_category=editors; fi
    [[ "$CURRENT_SECTION" != 5 ]] || setup_review_offset=0
}

setup_move_step() {
    local step_index=${setup_section_step[$CURRENT_SECTION]} step_next
    step_next=$((step_index+$1))
    ((step_next >= 0 && step_next < 6)) || return 0
    if [[ "$CURRENT_SECTION" == 0 && "$1" == -1 ]]; then
        setup_remember_target requirements
    fi
    if [[ ( "$CURRENT_SECTION" == 2 && "$1" == 1 ) || ( "$CURRENT_SECTION" == 5 && "$1" == -1 ) ]]; then
        setup_remember_target profiles
    fi
    setup_arrive_step "${setup_step_sections[step_next]}"
}

setup_frame_head() {
    local head_line head_os nav_plain='' nav_styled='' nav_item nav_mark nav_index nav_current=${setup_section_step[$CURRENT_SECTION]} nav_count nav_key nav_section nav_marks='' nav_color
    local -a nav_counts=(0 0 0 0 0 0)
    for nav_key in "${!component_checked[@]}"; do
        [[ "${component_checked[$nav_key]}" == true && -n "${component_action[$nav_key]}" ]] || continue
        if workstation_service_key "$nav_key"; then ((nav_counts[0]++))
        elif [[ "$nav_key" == bench_* ]]; then ((nav_counts[1]++))
        else
            for nav_item in "${ai_items[@]}"; do [[ "$nav_item" != "$nav_key" ]] || ((nav_counts[2]++)); done
            for nav_item in "${tool_items[@]}"; do [[ "$nav_item" != "$nav_key" ]] || ((nav_counts[3]++)); done
        fi
    done
    setup_ui_banner
    for head_line in "${setup_banner_lines[@]}"; do setup_frame_append "$head_line"; done
    setup_frame_append ''
    for ((nav_index=0; nav_index<6; nav_index++)); do
        nav_mark=○; nav_color="$SILVER_MUTED"
        if ((nav_index < nav_current)); then nav_mark=✓; fi
        if ((nav_index == nav_current)); then nav_mark=●; fi
        if ((nav_index == 0)); then
            if [[ "$status_checks_running" == true ]]; then nav_mark=…; nav_color="$LOADING_COLOR"
            elif setup_required_ready; then nav_mark=✓; nav_color="$GREEN"
            else nav_mark=⚠; nav_color="$YELLOW"; fi
        fi
        nav_marks+="$nav_mark"
        nav_item="$nav_mark ${setup_step_names[nav_index]}"
        nav_count=${nav_counts[nav_index]}
        ((nav_count == 0)) || nav_item+=" $nav_count"
        if ((nav_index == nav_current)); then
            nav_item=" $nav_item"
            printf -v head_line '%b%b%s%b' "$SILVER_FOCUS" "$nav_color" "$nav_item" "$NC"
        else printf -v head_line '%b%s%b' "$nav_color" "$nav_item" "$NC"; fi
        if [[ -n "$nav_plain" ]]; then nav_plain+=' ─ '; nav_styled+=' ─ '; fi
        nav_plain+="$nav_item"; nav_styled+="$head_line"
    done
    if (( ${#nav_plain} > setup_ui_width )); then
        head_line="Step $((nav_current+1)) of 6 · ${setup_step_names[nav_current]} $nav_marks"
    else head_line=$nav_styled; fi
    setup_frame_append "$head_line"
    if [[ -n "${setup_os_label:-}" ]]; then
        setup_ui_cut_v head_os "$setup_os_label" "$((setup_ui_width - 4))"
        setup_ui_rule_v head_line "$((setup_ui_width - ${#head_os} - 3))"
        head_line+=" $head_os ─"
    else setup_ui_rule_v head_line "$setup_ui_width"; fi
    setup_frame_append "$head_line"
}
setup_frame_selector() {
    if [[ "$CURRENT_SECTION" == 3 ]]; then
        setup_frame_append ''
        setup_frame_requirements_strip
    fi
    [[ "$CURRENT_SECTION" != 4 ]] || setup_frame_identities
    [[ "$CURRENT_SECTION" != 0 ]] || setup_frame_categories
    if [[ "$CURRENT_SECTION" == 1 || "$CURRENT_SECTION" == 2 ]]; then setup_frame_catalog_categories; fi
    return 0
}
setup_frame_notice() {
    local notice_line
    [[ -n "$requirements_notice" ]] || return 0
    printf -v notice_line '%b%s%b' "$YELLOW" "${requirements_notice:0:setup_ui_width}" "$NC"
    setup_frame_append "$notice_line"
}
declare -a setup_footer_lines=()
setup_footer_height=4

setup_frame_footer_prepare() {
    if [[ "$CURRENT_SECTION" == 1 && "$setup_harness_category" == tui ]]; then setup_cli_filters_refresh; fi
    local footer_key='' footer_name='' footer_state footer_context footer_total footer_count=0 footer_item footer_action footer_line footer_left_width footer_hint footer_width
    local -a footer_hints=()
    for footer_item in "${!component_checked[@]}"; do
        if [[ "${component_checked[$footer_item]}" == true && -n "${component_action[$footer_item]}" ]]; then ((footer_count++)); fi
    done
    case "$CURRENT_SECTION" in
        1) if [[ "$setup_harness_zone" == harness ]] && { [[ "$setup_harness_category" != tui ]] || ((setup_cli_filter_count > 0)); }; then footer_key="${ai_items[$current_selection]}"; fi ;;
        2) [[ "$setup_tool_zone" != tool ]] || footer_key="${tool_items[$current_selection]}" ;;
        3) footer_key="${requirement_items[$current_selection]}" ;;
        4) footer_key="${profile_items[$current_selection]}" ;;
    esac
    if [[ -n "$footer_key" ]]; then footer_name="${component_description[$footer_key]}"; fi
    footer_context=$footer_name
    if [[ "$CURRENT_SECTION" == 5 ]]; then footer_context='Review · Nothing applied yet'
    elif [[ "$CURRENT_SECTION" == 1 && "$setup_harness_zone" == filter ]]; then
        footer_context="FILTERS · $setup_cli_filter_count/$setup_cli_filter_total matches"
    elif [[ "$CURRENT_SECTION" == 1 && "$setup_harness_zone" == category ]]; then
        setup_catalog_group_summary_v footer_context harness "$setup_harness_category"
    elif [[ "$CURRENT_SECTION" == 2 && "$setup_tool_zone" == category ]]; then
        setup_tool_group_summary_v footer_context "$setup_tool_category"
    elif [[ "$CURRENT_SECTION" != 4 && -n "$footer_key" ]]; then
        setup_status_label_v footer_state "${component_status[$footer_key]}"
        footer_context+=" · $footer_state"
        [[ -z "${component_action[$footer_key]}" ]] || footer_context+=" → ${component_action[$footer_key]}"
    fi
    if [[ "$CURRENT_SECTION" == 1 && "$setup_harness_category" == tui && "$setup_harness_zone" == harness && "$setup_cli_filter_count" == 0 ]]; then footer_context='No matches · C clears filters'; fi
    if [[ -n "$footer_key" && "${component_action[$footer_key]}" == uninstall ]]; then footer_context="$footer_name · Remove; projects and credentials kept"; fi
    if [[ "$footer_key" == host_shell ]]; then footer_context='Shell setup · Replaces shell settings'; fi
    if [[ "$footer_key" == workspace_repo ]]; then footer_context='Org workspace · May create a GitHub repository'; fi
    if [[ -n "$footer_key" && -n "${setup_reference_labels[$footer_key]:-}" ]]; then footer_context+=" · Manual setup; see About"; fi
    footer_total="Changes selected: $footer_count"; ((setup_ui_width >= 60)) || footer_total="Changes: $footer_count"
    footer_left_width=$((setup_ui_width - ${#footer_total} - 1))
    setup_ui_cut_v footer_context "$footer_context" "$footer_left_width"
    setup_footer_lines=()
    if [[ "$CURRENT_SECTION" == 0 ]]; then
        setup_ui_rule_v footer_line "$footer_left_width"
        setup_ui_pair_v footer_line "$footer_line" "$footer_total" "$setup_ui_width"
        setup_footer_lines+=("$footer_line")
    else
        setup_ui_rule_v footer_line "$setup_ui_width"; setup_footer_lines+=("$footer_line")
        setup_ui_pair_v footer_line "$footer_context" "$footer_total" "$setup_ui_width"; setup_footer_lines+=("$footer_line")
    fi
    footer_action=Check
    if [[ "$CURRENT_SECTION" == 3 && -n "$footer_key" ]]; then workbenches_requirement_action_v footer_action "$footer_key" "${component_status[$footer_key]}" "${component_status[workbenches_account]}"; fi
    if ((setup_ui_width < 60)); then
        case "$CURRENT_SECTION" in
            3) footer_hints=('Navigation: Space Select  D Remove' '←→ Steps  Enter Review  Q Quit') ;;
            1)
                if [[ "$setup_harness_zone" == category ]]; then footer_hints=('Navigation: Tab Harnesses' '←→ Steps  Enter Review  Q Quit')
                else footer_hints=('Navigation: Tab Category  Space/D' '←→ Steps  Enter Review  Q Quit'); fi ;;
            2)
                if [[ "$setup_tool_zone" == category ]]; then footer_hints=('Navigation: Tab Tools' '←→ Steps  Enter Review  Q Quit')
                else footer_hints=('Navigation: Space Select  D Remove' '←→ Steps  Enter Review  Q Quit'); fi ;;
            4) footer_hints=('Navigation: Enter Open' '←→ Steps  G Back  Q Quit') ;;
            5) footer_hints=('Navigation: ↑↓ Scroll' '←→ Steps  Enter Apply  Q Quit') ;;
            0)
                if [[ "$setup_bench_zone" == category ]]; then footer_hints=('Navigation: Tab Benches' '←→ Steps  Enter Review  Q Quit')
                else footer_hints=('Navigation: Space Select  D Remove' '←→ Steps  Enter Review  Q Quit'); fi ;;
            *) footer_hints=('Navigation: Space Select  D Remove' '←→ Steps  Enter Review  Q Quit') ;;
        esac
    else
        case "$CURRENT_SECTION" in
            3) footer_hints=('Navigation: ↑↓ Move  Space Select  D Remove  PgUp/PgDn About' '←→ Steps  Enter Review  P Back  G Profiles  V Vault  R Refresh  Q Quit') ;;
            1)
                footer_action=Category; [[ "$setup_harness_zone" != category ]] || footer_action=Harnesses
                footer_hints=("Navigation: ↑↓ Move  Tab $footer_action  Space Select  D Remove  PgUp/PgDn About" '←→ Steps  P Workstation  R Refresh  Enter Review  Q Quit') ;;
            2)
                footer_action=Category; [[ "$setup_tool_zone" != category ]] || footer_action=Tools
                footer_hints=("Navigation: ↑↓ Move  Tab $footer_action  Space Select  D Remove  PgUp/PgDn About" '←→ Steps  P Workstation  R Refresh  Enter Review  Q Quit') ;;
            4) footer_hints=('Navigation: ↑↓ Move  Enter Open  PgUp/PgDn About' '←→ Steps  G Back  P Workstation  R Refresh  Q Quit') ;;
            5) footer_hints=('Navigation: ↑↓ Scroll  ← Back  Enter Apply' 'P Workstation  R Refresh  Q Quit') ;;
            0)
                footer_action=Category; [[ "$setup_bench_zone" != category ]] || footer_action=Benches
                footer_hints=("Navigation: ↑↓ Move  Tab $footer_action  Space Select  D Remove  PgUp/PgDn About" '←→ Steps  P Workstation  R Refresh  Enter Review  Q Quit') ;;
            *) footer_hints=('Navigation: ↑↓ Move  Space Select  D Remove' '←→ Steps  P Workstation  R Refresh  Enter Review  Q Quit') ;;
        esac
    fi
    if [[ -n "$footer_key" && -n "${setup_reference_labels[$footer_key]:-}" ]]; then
        if ((setup_ui_width < 60)); then footer_hints=('Navigation: Tab Category  [/] About' '←→ Steps  Enter Review  Q Quit')
        else footer_hints=('Navigation: ↑↓ Move  Tab Category  PgUp/PgDn About' 'Manual setup: see About  ←→ Steps  Enter Review  Q Quit'); fi
    fi
    if [[ "$CURRENT_SECTION" == 1 && "$setup_harness_category" == tui ]]; then
        if ((setup_ui_width < 60)); then
            if [[ "$setup_harness_zone" == filter ]]; then footer_hints=('Navigation: ←→ Column  ↑↓ Cycle' 'F Results  C All  Enter Review Q Quit')
            else footer_hints=('Navigation: Tab  Space/D  F/C' '←→ Steps  Enter Review  Q Quit'); fi
        else
            if [[ "$setup_harness_zone" == filter ]]; then footer_hints=('Navigation: ←→/Tab Column  ↑↓ Cycle  F Results  C Clear' 'Enter Review  PgUp/PgDn About  Q Quit')
            else
                footer_hints[0]='Navigation: ↑↓ Move  Tab Category  Space/D Select  F Filters  C Clear'
                if [[ "$setup_harness_zone" == category ]]; then footer_hints[0]='Navigation: ↑↓ Category  Tab List  F Filters  C Clear  [/] About'
                elif [[ -n "$footer_key" && -n "${setup_reference_labels[$footer_key]:-}" ]]; then footer_hints[0]='Navigation: ↑↓ Move  Tab Category  F Filters  C Clear  [/] About'; fi
            fi
        fi
    fi
    for footer_hint in "${footer_hints[@]}"; do
        setup_ui_wrap "$footer_hint" "$setup_ui_width"
        setup_footer_lines+=("${setup_wrapped_lines[@]}")
    done
    setup_footer_height=${#setup_footer_lines[@]}
}

setup_frame_footer() {
    local footer_output_line
    for footer_output_line in "${setup_footer_lines[@]}"; do setup_frame_append "$footer_output_line"; done
}

setup_review_rows=()
setup_review_window=1

setup_frame_requirements_strip() {
    local strip_title
    setup_requirement_counts
    strip_title="REQUIREMENTS · $requirements_ready/$requirements_total ready"
    [[ "$status_checks_running" != true ]] || strip_title='REQUIREMENTS · Loading…'
    setup_frame_append "$strip_title"
    setup_frame_append ''
}

setup_frame_service_row() {
    local service_key="$1" service_marker=' ' service_box='[ ]' service_icon=○ service_state service_left service_right service_color="$SILVER" service_queued=''
    [[ "${requirement_items[$current_selection]}" != "$service_key" ]] || service_marker=›
    [[ "${component_checked[$service_key]}" != true ]] || service_box='[✓]'
    case "${component_status[$service_key]}" in
        up) service_state='Installed · Up'; service_icon=✓; service_color="$GREEN" ;;
        down) service_state='Installed · Down'; service_icon=⚠; service_color="$YELLOW"
            if [[ "$service_key" == setup_tools || "$service_key" == vault ]] && [[ "${component_status[docker]}" != up ]]; then service_state=Unavailable; fi ;;
        missing) service_state='Not installed' ;;
        loading) service_state='Loading…'; service_icon=…; service_color="$LOADING_COLOR" ;;
        *) service_state='Needs check'; service_icon=⚠; service_color="$YELLOW" ;;
    esac
    service_left="$service_marker $service_box $service_icon ${component_description[$service_key]}"
    service_right=$service_state
    if [[ "${component_checked[$service_key]}" == true && -n "${component_action[$service_key]}" ]]; then
        service_queued="→ ${component_action[$service_key]^}"
        if ((setup_ui_width >= 50)); then service_right+="  $service_queued"
        else service_right=$service_queued; fi
    fi
    setup_frame_row "$service_left" "$service_right" "$service_color"
}

setup_frame_component_row() {
    local component_key="$1" component_focus="$2" component_marker=' ' component_box='[ ]' component_icon=○ component_state component_right='' component_color="$SILVER" component_action_label=''
    [[ "$component_focus" != true ]] || component_marker=›
    [[ "${component_checked[$component_key]}" != true ]] || component_box='[✓]'
    setup_status_label_v component_state "${component_status[$component_key]}"
    if [[ "${component_status[$component_key]}" == installed || "${component_status[$component_key]}" == 'needs creds' || "${component_status[$component_key]}" == 'image only' ]]; then component_icon=✓; component_color="$GREEN"; fi
    if [[ "${component_status[$component_key]}" == loading || -z "${component_status[$component_key]}" ]]; then
        component_icon=…; component_state='Loading…'; component_color="$LOADING_COLOR"
    fi
    if [[ "${component_checked[$component_key]}" == true && -n "${component_action[$component_key]}" ]]; then
        component_action_label="${component_action[$component_key]^}"
        [[ "$component_action_label" != Uninstall ]] || component_action_label=Remove
        component_right="→ $component_action_label"
    fi
    if ((setup_ui_width >= 50)); then
        [[ -z "$component_right" ]] || component_right="  $component_right"
        component_right="$component_state$component_right"
    fi
    if [[ -n "${setup_reference_labels[$component_key]:-}" ]]; then
        component_box='·'
        component_state='Manual setup'
        if [[ "${component_status[$component_key]}" == installed ]]; then component_state='Installed · manual'
        elif [[ "${component_status[$component_key]}" == 'needs check' ]]; then component_state='Check manually'
        elif [[ "${component_status[$component_key]}" == loading ]]; then component_state='Loading…'; fi
        if ((setup_ui_width < 50)); then
            case "${component_status[$component_key]}" in
                'needs check') component_state=Check ;;
                loading) component_state='…' ;;
                *) component_state=Manual ;;
            esac
        fi
        component_right=$component_state
    fi
    setup_frame_row "$component_marker $component_box $component_icon ${component_description[$component_key]}" "$component_right" "$component_color"
}

declare -A workstation_about=(
    [wsl]='Runs the Linux environment for your containers on Windows. WSL 2 is required on Windows.'
    [docker]='Runs the Linux containers used by your benches. Docker must be Up before setup can apply changes.'
    [setup_tools]='Provides the shared tools used by setup and your benches. These tools are required before setup can apply changes.'
    [vault]='Optional credential storage for connected accounts. You can set up benches without Vault. Use G Profiles to manage sign-in and credentials.'
)


# Generated static metadata: startup and rendering need no JSON/tool probes.
source "$SCRIPT_DIR/lib/setup-tool-catalog.generated.sh"
source "$SCRIPT_DIR/lib/setup-cli-filters.sh"

declare -A profile_about=(
    [personal_profiles]='Personal identity, GitHub and company accounts. Company, GitHub and AI access are authorized separately.'
    [workbenches_account]='Organization sign-in. AI and vault access are managed separately.'
    [ai_accounts]='Sign in, restore assistant profiles, or recover credentials from a vault.'
)

setup_ui_cut_v() {
    local cut_text="$2" cut_width=$3
    if (( ${#cut_text} > cut_width )); then cut_text="${cut_text:0:cut_width-1}…"; fi
    printf -v "$1" '%s' "$cut_text"
}

setup_frame_identities() {
    local identity_line="${profiles_summary//$'\n'/ · }"
    setup_ui_cut_v identity_line "IDENTITIES · $identity_line" "$setup_ui_width"
    setup_frame_append "$identity_line"
}

setup_frame_profiles() {
    local profile_line profile_index profile_key profile_marker profile_window=8
    setup_panel_top_v profile_line 'PROFILES' ''; setup_frame_append "$profile_line"
    for profile_index in "${!profile_items[@]}"; do
        profile_key="${profile_items[profile_index]}"; profile_marker=' '
        (( profile_index != current_selection )) || profile_marker=›
        setup_frame_row "$profile_marker ${component_description[$profile_key]}"
    done
    setup_panel_bottom_v profile_line; setup_frame_append "$profile_line"
    if [[ -n "$setup_ui_height" ]]; then
        profile_window=$((setup_ui_height - ${#setup_frame_lines[@]} - setup_footer_height - 2))
        ((profile_window <= 8)) || profile_window=8
        ((profile_window >= 2)) || profile_window=2
    fi
    profile_key="${profile_items[$current_selection]}"
    setup_frame_about "profile:$profile_key" "ABOUT ${component_description[$profile_key]}" "${profile_about[$profile_key]}" "$profile_window"
}


setup_frame_bench_row() {
    local row_name="$1" row_focused="$2" row_key="bench_$1" row_marker=' ' row_box='[ ]' row_icon=○ row_state row_action='' row_right='' row_left row_color="$SILVER"
    [[ "$row_focused" != true ]] || row_marker=›
    [[ "${component_checked[$row_key]}" != true ]] || row_box='[✓]'
    setup_status_label_v row_state "${component_status[$row_key]}"
    if [[ "${component_status[$row_key]}" == installed || "${component_status[$row_key]}" == 'needs creds' || "${component_status[$row_key]}" == 'image only' ]]; then row_icon=✓; row_color="$GREEN"; fi
    [[ "${component_status[$row_key]}" != installed ]] || row_state=Installed
    if [[ "${component_status[$row_key]}" == loading || -z "${component_status[$row_key]}" ]]; then row_icon=…; row_state='Loading…'; row_color="$LOADING_COLOR"; fi
    row_left="$row_marker $row_box $row_icon $row_name"
    if ((setup_ui_width >= 70)) && [[ -n "${bench_meta_tagline[$row_name]}" ]]; then row_left+=" · ${bench_meta_tagline[$row_name]}"; fi
    if [[ "${component_checked[$row_key]}" == true && -n "${component_action[$row_key]}" ]]; then
        row_action="${component_action[$row_key]^}"
        [[ "$row_action" != Uninstall ]] || row_action=Remove
        row_right="→ $row_action"
    fi
    if ((setup_ui_width >= 50)); then
        [[ -z "$row_right" ]] || row_right="  $row_right"
        row_right="$row_state$row_right"
    fi
    setup_frame_row "$row_left" "$row_right" "$row_color"
}

setup_frame_benches() {
    local bench_line bench_name bench_index bench_focus_index=0 bench_focused=false bench_budget=0 bench_offset_local=0 bench_about_window=8 bench_any_loading=false bench_about_text='' bench_about_title bench_about_anchor bench_part bench_field
    local -a bench_members=() bench_parts=()
    if [[ "$setup_benches_state" != ready ]]; then
        if [[ "$setup_benches_state" == unavailable ]]; then
            setup_ui_wrap 'The bench list could not be loaded. R retries.' "$setup_ui_width"
            for bench_line in "${setup_wrapped_lines[@]}"; do setup_frame_append "$bench_line"; done
        else setup_frame_append 'Loading benches…'; fi
        return
    fi
    if [[ -z "$setup_bench_category" ]]; then setup_bench_category="${setup_bench_categories_focusable[0]}"; fi
    [[ -n "$setup_bench_category" ]] || { setup_frame_append 'No benches available.'; return; }
    IFS=' ' read -r -a bench_members <<< "${setup_bench_members[$setup_bench_category]}"
    for bench_index in "${!bench_members[@]}"; do
        bench_name="${bench_members[bench_index]}"
        [[ "$bench_name" != "${bench_items[$current_selection]}" ]] || bench_focus_index=$bench_index
        if [[ "${component_status[bench_$bench_name]}" == loading || -z "${component_status[bench_$bench_name]}" ]]; then bench_any_loading=true; fi
    done
    bench_line="${setup_bench_installed[$setup_bench_category]:-0} of ${#bench_members[@]} installed"
    [[ "$bench_any_loading" != true ]] || bench_line='Loading…'
    [[ "$setup_ui_layout" != roomy ]] || setup_frame_append ''
    setup_panel_top_v bench_line "${bench_category_label[$setup_bench_category]}" "$bench_line"
    setup_frame_append "$bench_line"
    if [[ -n "$setup_ui_height" ]]; then
        bench_budget=$((setup_ui_height - ${#setup_frame_lines[@]} - setup_footer_height - 5))
        [[ "$setup_ui_layout" != roomy ]] || ((bench_budget--))
        ((bench_budget >= 3)) || bench_budget=3
    fi
    bench_offset_local=${setup_bench_offset[$setup_bench_category]:-0}
    setup_ui_list_window "${#bench_members[@]}" "$bench_focus_index" "$bench_budget" bench_offset_local
    setup_bench_offset[$setup_bench_category]=$bench_offset_local
    if ((setup_window_above > 0)); then setup_frame_row "▲ $setup_window_above more"; fi
    for ((bench_index=setup_window_start; bench_index<setup_window_start+setup_window_count; bench_index++)); do
        bench_name="${bench_members[bench_index]}"; bench_focused=false
        if [[ "$setup_bench_zone" == bench && "$bench_name" == "${bench_items[$current_selection]}" ]]; then bench_focused=true; fi
        setup_frame_bench_row "$bench_name" "$bench_focused"
    done
    if ((setup_window_below > 0)); then setup_frame_row "▼ $setup_window_below more"; fi
    setup_panel_bottom_v bench_line; setup_frame_append "$bench_line"
    [[ "$setup_ui_layout" != roomy ]] || setup_frame_append ''
    if [[ "$setup_bench_zone" == bench ]]; then
        bench_name="${bench_items[$current_selection]}"
        bench_about_anchor="bench:$bench_name"; bench_about_title="ABOUT ${bench_name^^}"
        bench_about_text="${bench_meta_description[$bench_name]}"
        for bench_field in used_for contains; do
            if [[ "$bench_field" == used_for ]]; then bench_part="${bench_meta_used_for[$bench_name]}"; bench_line='Use it for'
            else bench_part="${bench_meta_contains[$bench_name]}"; bench_line=Contains; fi
            [[ -n "$bench_part" ]] || continue
            IFS=$'\174' read -r -a bench_parts <<< "$bench_part"
            [[ -z "$bench_about_text" ]] || bench_about_text+=$'\n'
            bench_about_text+="$bench_line: "
            bench_line=''
            for bench_part in "${bench_parts[@]}"; do
                [[ -z "$bench_line" ]] || bench_line+='; '
                bench_line+="$bench_part"
            done
            bench_about_text+="$bench_line"
        done
        [[ -n "$bench_about_text" ]] || bench_about_text='No details for this bench yet.'
    else
        bench_about_anchor="category:$setup_bench_category"; bench_about_title="ABOUT ${bench_category_label[$setup_bench_category]^^}"
        bench_about_text="${bench_category_summary[$setup_bench_category]}"
        [[ -z "$bench_about_text" ]] || bench_about_text+=$'\n'
        bench_about_text+="Benches: ${setup_bench_members[$setup_bench_category]}"
    fi
    if [[ -n "$setup_ui_height" ]]; then
        bench_about_window=$((setup_ui_height - ${#setup_frame_lines[@]} - setup_footer_height - 2))
        ((bench_about_window <= 8)) || bench_about_window=8
        ((bench_about_window >= 2)) || bench_about_window=2
    fi
    setup_frame_about "$bench_about_anchor" "$bench_about_title" "$bench_about_text" "$bench_about_window"
}

setup_frame_components() {
    local component_line component_index component_key component_focus component_budget=0 component_focus_index=0 component_offset component_title component_about_title component_about_text component_anchor component_window=8 component_family=tool component_array=tool_items component_member_text component_offset_key
    [[ "$CURRENT_SECTION" != 1 ]] || { component_family=harness; component_array=ai_items; }
    local -n component_categories="setup_${component_family}_members" component_category="setup_${component_family}_category" component_zone="setup_${component_family}_zone"
    local -n component_labels="setup_${component_family}_labels" component_offsets="setup_${component_family}_offsets" component_summaries="setup_${component_family}_summaries" component_flat="$component_array"
    local -a component_items=()
    setup_catalog_members_v component_member_text "$component_family" "$component_category"
    IFS=' ' read -r -a component_items <<< "$component_member_text"
    component_offset_key=$component_category
    if [[ "$component_family" == harness && "$component_category" == tui ]]; then component_offset_key="tui:$setup_cli_filter_cache_key"; fi
    component_title="${component_labels[$component_category]}"; component_offset=${component_offsets[$component_offset_key]:-0}
    [[ "$component_family" != harness ]] || component_title="Harnesses · $component_title"
    for component_index in "${!component_items[@]}"; do
        [[ "${component_items[component_index]}" != "${component_flat[$current_selection]}" ]] || component_focus_index=$component_index
    done
    [[ "$setup_ui_layout" != roomy ]] || setup_frame_append ''
    if [[ "$component_family" == harness && "$component_category" == tui ]]; then setup_frame_cli_filter_bar; fi
    setup_panel_top_v component_line "$component_title" ''; setup_frame_append "$component_line"
    if [[ -n "$setup_ui_height" ]]; then
        component_budget=$((setup_ui_height - ${#setup_frame_lines[@]} - setup_footer_height - 9))
        [[ "$setup_ui_layout" != roomy ]] || ((component_budget--))
        ((component_budget >= 3)) || component_budget=3
    fi
    setup_ui_list_window "${#component_items[@]}" "$component_focus_index" "$component_budget" component_offset
    component_offsets[$component_offset_key]=$component_offset
    if ((${#component_items[@]} == 0)); then setup_frame_row 'No matching harnesses. F Filters · C Clear'; fi
    if ((setup_window_above > 0)); then setup_frame_row "▲ $setup_window_above more"; fi
    for ((component_index=setup_window_start; component_index<setup_window_start+setup_window_count; component_index++)); do
        component_key="${component_items[component_index]}"; component_focus=false
        if ((component_index == component_focus_index)) && [[ "$component_zone" == "$component_family" ]]; then component_focus=true; fi
        setup_frame_component_row "$component_key" "$component_focus"
    done
    if ((setup_window_below > 0)); then setup_frame_row "▼ $setup_window_below more"; fi
    setup_panel_bottom_v component_line; setup_frame_append "$component_line"
    [[ "$setup_ui_layout" != roomy ]] || setup_frame_append ''
    if [[ "$component_family" == harness && "$component_category" == tui && ${#component_items[@]} == 0 ]]; then
        component_anchor='harness-empty'; component_about_title='ABOUT · NO MATCHING HARNESSES'
        component_about_text='No known entries match these filters. Some capability/access metadata is partial or unverified. F edits filters; C clears them. Queued changes stay in Review.'
    elif [[ "$component_zone" == category ]]; then
        component_anchor="$component_family-category:$component_category"; component_about_title="ABOUT ${component_labels[$component_category]^^}"
        component_about_text="${component_summaries[$component_category]}"$'\nIncludes: '
        component_line=''
        for component_key in "${component_items[@]}"; do
            [[ -z "$component_line" ]] || component_line+=', '
            component_line+="${component_description[$component_key]}"
        done
        component_about_text+="$component_line"
    else
        component_key="${component_flat[$current_selection]}"; component_anchor="$component_family:$component_key"
        component_about_title="ABOUT ${component_description[$component_key]^^}"
        component_about_text="${component_about[$component_key]:-Select an item to see its details.}"
    fi
    if [[ -n "$setup_ui_height" ]]; then
        component_window=$((setup_ui_height - ${#setup_frame_lines[@]} - setup_footer_height - 2))
        ((component_window <= 8)) || component_window=8
        ((component_window >= 2)) || component_window=2
    fi
    if [[ "$component_family" == harness && "$component_category" == tui && "$component_zone" == filter ]]; then
        setup_frame_cli_filter_about "$component_window"
    else
        setup_frame_about "$component_anchor" "$component_about_title" "$component_about_text" "$component_window"
    fi
}



setup_frame_workstation() {
    local workstation_line workstation_key workstation_text workstation_window=8
    setup_requirement_counts
    setup_panel_top_v workstation_line Containers "$requirements_ready/$requirements_total ready"
    setup_frame_append "$workstation_line"
    for workstation_key in "${requirement_items[@]}"; do
        if [[ "$workstation_key" == workbenches_account || "$workstation_key" == ai_accounts ]]; then continue; fi
        setup_frame_service_row "$workstation_key"
    done
    setup_panel_bottom_v workstation_line; setup_frame_append "$workstation_line"
    [[ "$setup_ui_layout" != roomy ]] || setup_frame_append ''
    workstation_key="${requirement_items[$current_selection]}"
    workstation_text="${workstation_about[$workstation_key]}"
    if [[ -n "${requirement_detail[$workstation_key]}" ]]; then
        workstation_text+=$'\n'"Current check: ${requirement_detail[$workstation_key]}"
    fi
    if [[ -n "$setup_ui_height" ]]; then
        workstation_window=$((setup_ui_height - ${#setup_frame_lines[@]} - setup_footer_height - 2))
        ((workstation_window <= 8)) || workstation_window=8
        ((workstation_window >= 2)) || workstation_window=2
    fi
    setup_frame_about "workstation:$workstation_key" "ABOUT ${component_description[$workstation_key]^^}" "$workstation_text" "$workstation_window"
}

setup_apply_allowed() {
    local key only_removals=true only_services=true any=false
    [[ "$status_checks_running" != true ]] || return 1
    setup_required_ready && return 0
    for key in "${!component_checked[@]}"; do
        [[ "${component_checked[$key]}" == true && -n "${component_action[$key]}" ]] || continue
        any=true
        workstation_service_key "$key" || only_services=false
        if ! workstation_service_key "$key" || [[ "${component_action[$key]}" != uninstall ]]; then only_removals=false; fi
    done
    [[ "$any" == true && "$only_removals" == true ]] && return 0
    [[ "$only_services" == true ]] || return 1
    for key in "${requirement_items[@]}"; do
        [[ "$key" != vault ]] || continue
        [[ "${component_status[$key]}" == up || ( "${component_checked[$key]}" == true && "${component_action[$key]}" == install ) ]] || return 1
    done
}

setup_frame_review() {
    local review_action review_label review_step review_item review_key review_text review_index review_budget review_offset_local review_total=0 review_last_action=''
    local -a review_items=()
    setup_ui_wrap 'Nothing has changed yet. Enter applies these changes.' "$setup_ui_width"
    for review_text in "${setup_wrapped_lines[@]}"; do setup_frame_append "$review_text"; done
    if [[ "$status_checks_running" == true ]]; then
        printf -v review_text '%b%s%b' "$YELLOW" 'Apply waiting for checks.' "$NC"
        setup_frame_append "$review_text"
    elif ! setup_apply_allowed; then
        setup_ui_wrap 'Apply waiting: resolve workstation requirements first.' "$setup_ui_width"
        for review_text in "${setup_wrapped_lines[@]}"; do setup_frame_append "$review_text"; done
    fi
    setup_review_rows=()
    for review_action in install update uninstall; do
        review_items=()
        for review_step in 3 0 1 2; do
            case "$review_step" in
                3) review_label="${setup_step_names[0]}"; review_items=("${requirement_items[@]}") ;;
                0) review_label="${setup_step_names[1]}"; review_items=("${bench_items[@]}") ;;
                1) review_label="${setup_step_names[2]}"; review_items=("${ai_items[@]}") ;;
                2) review_label="${setup_step_names[3]}"; review_items=("${tool_items[@]}") ;;
            esac
            for review_item in "${review_items[@]}"; do
                review_key=$review_item
                [[ "$review_step" != 0 ]] || review_key="bench_$review_item"
                [[ "${component_checked[$review_key]}" == true && "${component_action[$review_key]}" == "$review_action" ]] || continue
                if (( review_total == 0 )) || [[ "$review_last_action" != "$review_action" ]]; then
                    case "$review_action" in install) review_text=INSTALL;; update) review_text=UPDATE;; uninstall) review_text='REMOVE · projects and credentials kept';; esac
                    setup_review_rows+=("$review_text"); review_last_action=$review_action
                fi
                setup_review_rows+=("  ${component_description[$review_key]:-$review_item} ($review_label)")
                if [[ -n "${setup_managed_harnesses[$review_key]:-}" ]]; then
                    local harness_target_names='Workstation' harness_bench_key
                    for harness_bench_key in "${bench_items[@]}"; do
                        if [[ "${component_checked[bench_$harness_bench_key]}" == true ]] && [[ "${component_action[bench_$harness_bench_key]}" == install || "${component_action[bench_$harness_bench_key]}" == update ]]; then
                            harness_target_names+=", $harness_bench_key"
                        fi
                    done
                    setup_ui_wrap "    Targets: $harness_target_names" "$setup_ui_width"
                    setup_review_rows+=("${setup_wrapped_lines[@]}")
                fi
                ((review_total++))
                if workstation_service_key "$review_key" && [[ "$review_action" == uninstall ]]; then
                    setup_review_rows+=('Warning: removes a workstation prerequisite; dependent benches may stop working.')
                    [[ "$review_key" != wsl ]] || setup_review_rows+=('Warning: WSL removal requires Windows host steps; distributions will not be deleted.')
                fi
                if [[ "$review_key" == host_shell ]]; then setup_review_rows+=('Warning: Shell setup replaces shell settings.'); fi
                if [[ "$review_key" == workspace_repo ]]; then setup_review_rows+=('Warning: Org workspace may create a GitHub repository.'); fi
            done
        done
    done
    if ((review_total == 0)); then
        setup_ui_wrap 'No changes selected. Enter finishes without changes.' "$setup_ui_width"
        for review_text in "${setup_wrapped_lines[@]}"; do setup_frame_append "$review_text"; done
        setup_review_window=0
        return
    fi
    review_budget=0
    if [[ -n "$setup_ui_height" ]]; then
        review_budget=$((setup_ui_height - ${#setup_frame_lines[@]} - setup_footer_height - 1))
        ((review_budget > 2)) || review_budget=3
    fi
    review_offset_local=$setup_review_offset
    setup_ui_list_window "${#setup_review_rows[@]}" "$setup_review_offset" "$review_budget" review_offset_local
    setup_review_window=$setup_window_count
    if ((setup_window_above > 0)); then setup_frame_append "▲ $setup_window_above more"; fi
    for ((review_index=setup_window_start; review_index<setup_window_start+setup_window_count; review_index++)); do
        review_text="${setup_review_rows[review_index]}"
        review_text="${review_text:0:setup_ui_width}"
        if [[ "$review_text" == Warning:* ]]; then printf -v review_text '%b%s%b' "$YELLOW" "$review_text" "$NC"; fi
        setup_frame_append "$review_text"
    done
    if ((setup_window_below > 0)); then setup_frame_append "▼ $setup_window_below more"; fi
}


setup_frame_build() {
    setup_frame_lines=()
    setup_ui_layout=roomy
    if [[ -n "$setup_ui_height" ]] && (( setup_ui_height < 40 )); then setup_ui_layout=tight; fi
    setup_frame_head
    setup_frame_footer_prepare
    setup_frame_selector
    setup_frame_notice
    if [[ "$CURRENT_SECTION" == 3 ]]; then setup_frame_workstation
    elif [[ "$CURRENT_SECTION" == 1 || "$CURRENT_SECTION" == 2 ]]; then setup_frame_components
    elif [[ "$CURRENT_SECTION" == 4 ]]; then setup_frame_profiles
    elif [[ "$CURRENT_SECTION" == 5 ]]; then setup_frame_review
    else setup_frame_benches; fi
    setup_frame_footer
    setup_frame_fit
}

render_setup_frame() {
    if [[ "$setup_ui_painted" != true || "$setup_ui_size_stale" == true ]]; then setup_ui_read_size; fi
    setup_frame_build
    printf '%s\n' "${setup_frame_lines[@]}"
}

# Size discovery is outside the fork-free builder and line-diff engine.
setup_measure_terminal() {
    setup_terminal_columns="$(tput cols 2>/dev/null)"
    setup_ui_height="$(tput lines 2>/dev/null)"
    [[ "$setup_terminal_columns" =~ ^[0-9]+$ ]] || setup_terminal_columns=88
    [[ "$setup_ui_height" =~ ^[1-9][0-9]*$ ]] || setup_ui_height=''
    setup_ui_width=$((setup_terminal_columns - 1))
    (( setup_ui_width <= 87 )) || setup_ui_width=87
    (( setup_ui_width >= 36 )) || setup_ui_width=36
}

setup_ui_read_size() {
    setup_measure_terminal
    setup_ui_size_stale=false
}

# Commit only changed lines in one write, without blanking the screen first.
draw_ui() {
    local output='' cursor index count
    if [[ "$setup_ui_painted" != true || "$setup_ui_size_stale" == true ]]; then setup_ui_read_size; fi
    setup_frame_build
    if [[ "$setup_ui_painted" != true || "$setup_ui_frame_columns" != "$setup_terminal_columns" || "$setup_ui_frame_rows" != "$setup_ui_height" ]]; then
        output=$'\033[?25l\033[0m\033[2J'
        setup_ui_previous_lines=()
    fi
    count=${#setup_frame_lines[@]}
    (( count >= ${#setup_ui_previous_lines[@]} )) || count=${#setup_ui_previous_lines[@]}
    for ((index=0; index<count; index++)); do
        if [[ "${setup_frame_lines[$index]:-}" != "${setup_ui_previous_lines[$index]:-}" ]]; then
            printf -v cursor '\033[%d;1H' "$((index + 1))"
            output+="${cursor}"$'\033[0m'"${setup_frame_lines[$index]:-}"$'\033[0m\033[K'
        fi
    done
    [[ -z "$output" ]] || printf '%s' "$output"
    setup_ui_previous_lines=("${setup_frame_lines[@]}")
    setup_ui_frame_columns=$setup_terminal_columns
    setup_ui_frame_rows=$setup_ui_height
    setup_ui_painted=true
}

# Keep action hints together and show detail only for the focused component.
draw_setup_footer() {
    local -a setup_frame_lines=()
    local setup_frame_region_height=0
    setup_frame_footer_prepare
    setup_frame_footer
    printf '%s\n' "${setup_frame_lines[@]}"
}




# Handle keyboard input
handle_input() {
    local key

    # Read single character
    local read_status
    # Some Bash builds restart an untimed read after WINCH. Bound the idle
    # wait too, so resize is noticed even when no checks or keys are pending.
    local -a read_options=(-rsn1 -t 0.15)
    if IFS= read "${read_options[@]}" key; then :; else
        read_status=$?
        if [[ "$read_status" -gt 128 && "$setup_ui_size_stale" == true ]]; then return 3; fi
        if [[ "$read_status" -gt 128 ]]; then return 3; fi
        return 2
    fi

    setup_input_key="$key"
    case "$key" in
        f|F|c|C) setup_input_key=filter; setup_cli_filters_key "$key" || :; return 0 ;;
        $'\t') setup_input_key=tab; [[ "$CURRENT_SECTION" != 0 ]] || setup_benches_key tab; [[ "$CURRENT_SECTION" != 2 ]] || setup_tools_key tab; [[ "$CURRENT_SECTION" != 1 ]] || setup_harnesses_key tab; return 0 ;;
        '[') setup_input_key=pageup; if [[ "$CURRENT_SECTION" != 5 ]]; then setup_about_scroll -1; fi; return 0 ;;
        ']') setup_input_key=pagedown; if [[ "$CURRENT_SECTION" != 5 ]]; then setup_about_scroll 1; fi; return 0 ;;
    esac
    # Consume every byte of supported escape sequences before dispatch.
    if [[ $key == $'\x1b' ]]; then
        IFS= read -rsn2 -t 0.1 key
        case "$key" in
            '[Z') setup_input_key=backtab; [[ "$CURRENT_SECTION" != 0 ]] || setup_benches_key backtab; [[ "$CURRENT_SECTION" != 2 ]] || setup_tools_key backtab; [[ "$CURRENT_SECTION" != 1 ]] || setup_harnesses_key backtab; return 0 ;;
            '[5'|'[6')
                local suffix
                IFS= read -rsn1 -t 0.1 suffix
                setup_input_key=unknown
                if [[ "$suffix" == '~' ]]; then
                    setup_input_key=pageup
                    [[ "$key" != '[6' ]] || setup_input_key=pagedown
                fi
                if [[ "$CURRENT_SECTION" != 5 ]]; then
                    [[ "$setup_input_key" != pageup ]] || setup_about_scroll -1
                    [[ "$setup_input_key" != pagedown ]] || setup_about_scroll 1
                fi
                return 0 ;;
            '[A') setup_input_key=up ;;
            '[B') setup_input_key=down ;;
            '[C') setup_input_key=right ;;
            '[D') setup_input_key=left ;;
            *) setup_input_key=unknown; return 0 ;;
        esac
        if [[ "$CURRENT_SECTION" == 0 ]] && setup_benches_key "$setup_input_key"; then return 0; fi
        if [[ "$CURRENT_SECTION" == 1 ]] && setup_harnesses_key "$setup_input_key"; then return 0; fi
        if [[ "$CURRENT_SECTION" == 2 ]] && setup_tools_key "$setup_input_key"; then return 0; fi
        case "$key" in
            '[A') # Up arrow - move up in current section
                if [[ "$CURRENT_SECTION" == 5 ]]; then
                    ((setup_review_offset <= 0)) || ((setup_review_offset--))
                    return 0
                fi
                if [ $current_selection -gt 0 ]; then
                    ((current_selection--))
                    # Skip separators in AI section
                    if [ $CURRENT_SECTION -eq 1 ]; then
                        local item="${ai_items[$current_selection]}"
                        while [[ "$item" == separator* ]] && [ $current_selection -gt 0 ]; do
                            ((current_selection--))
                            item="${ai_items[$current_selection]}"
                        done
                    fi
                fi
                ;;
            '[B') # Down arrow - move down in current section
                if [[ "$CURRENT_SECTION" == 5 ]]; then
                    ((setup_review_offset >= ${#setup_review_rows[@]} - 1)) || ((setup_review_offset++))
                    return 0
                fi
                local max_idx
                if [ $CURRENT_SECTION -eq 0 ]; then
                    max_idx=$((${#bench_items[@]} - 1))
                elif [ $CURRENT_SECTION -eq 1 ]; then
                    max_idx=$((${#ai_items[@]} - 1))
                elif [ $CURRENT_SECTION -eq 2 ]; then
                    max_idx=$((${#tool_items[@]} - 1))
                elif [ $CURRENT_SECTION -eq 4 ]; then
                    max_idx=$((${#profile_items[@]} - 1))
                else
                    max_idx=$((${#requirement_items[@]} - 1))
                fi

                if [ $current_selection -lt $max_idx ]; then
                    ((current_selection++))
                    # Skip separators in AI section
                    if [ $CURRENT_SECTION -eq 1 ]; then
                        local item="${ai_items[$current_selection]}"
                        while [[ "$item" == separator* ]] && [ $current_selection -lt $max_idx ]; do
                            ((current_selection++))
                            item="${ai_items[$current_selection]}"
                        done
                    fi
                fi
                ;;
            '[C') setup_move_step 1 ;;
            '[D') setup_move_step -1 ;;
        esac
    else
        case "$key" in
            ' '|d|D) # Space toggles install/update; D toggles explicit removal.
                [[ "$CURRENT_SECTION" != 5 ]] || return 0
                if [[ "$CURRENT_SECTION" == 0 ]] && setup_benches_key "$key"; then return 0; fi
                if [[ "$CURRENT_SECTION" == 1 ]] && setup_harnesses_key "$key"; then return 0; fi
                if [[ "$CURRENT_SECTION" == 2 ]] && setup_tools_key "$key"; then return 0; fi
                if [[ "$CURRENT_SECTION" == 4 ]]; then
                    [[ "$key" != ' ' ]] || activate_profile || return "$?"
                    return 0
                fi
                local input_key="$key"
                local key=""
                if [ $CURRENT_SECTION -eq 0 ]; then
                    local bench="${bench_items[$current_selection]}"
                    key="bench_$bench"
                elif [ $CURRENT_SECTION -eq 1 ]; then
                    local item="${ai_items[$current_selection]}"
                    if [[ "$item" == separator* ]]; then
                        return 0  # Skip separators
                    fi
                    key="$item"
                elif [ $CURRENT_SECTION -eq 2 ]; then
                    local item="${tool_items[$current_selection]}"
                    key="$item"
                else
                    key="${requirement_items[$current_selection]}"
                    case "$key" in
                        docker|wsl|setup_tools|vault)
                            case "${component_status[$key]}" in up|down|missing) ;; *) return 0 ;; esac
                            local service_request=install
                            if [[ "$input_key" == d || "$input_key" == D ]]; then
                                [[ "${component_status[$key]}" != missing ]] || return 0
                                service_request=uninstall
                            fi
                            if [[ "${component_checked[$key]}" == true && "${component_action[$key]}" == "$service_request" ]]; then
                                component_checked[$key]=false; component_action[$key]=''
                            else component_checked[$key]=true; component_action[$key]=$service_request; fi
                            return 0 ;;
                    esac
                fi

                # Determine action based on current status
                [[ -n "$key" ]] || return 0
                if [[ "$CURRENT_SECTION" == 1 && "$setup_harness_category" == tui ]]; then
                    setup_cli_filters_refresh
                    ((setup_cli_filter_count > 0)) && [[ " $setup_cli_filter_members " == *" $key "* ]] || return 0
                fi
                [[ -z "${setup_reference_labels[$key]:-}" ]] || return 0
                local status="${component_status[$key]}"
                local is_installed=false
                [[ "$status" != 'needs check' && "$status" != loading ]] || return 0
                [[ "$status" == "installed" || "$status" == "needs creds" || "$status" == 'image only' ]] && is_installed=true

                local requested="install"
                [[ "$is_installed" == true ]] && requested="update"
                if [[ "$key" == host_shell || "$key" == workspace_repo || "$key" == ai_accounts || "$key" == workbenches_account ]]; then
                    [[ "$input_key" != d && "$input_key" != D ]] || return 0
                    requested=install
                fi
                if [[ "$input_key" == d || "$input_key" == D ]]; then
                    local can_remove="$is_installed" remove_bench_key
                    [[ "$status" != 'needs path' || -z "${setup_managed_harnesses[$key]:-}" ]] || can_remove=true
                    if [[ "$can_remove" != true && -n "${setup_managed_harnesses[$key]:-}" ]]; then
                        for remove_bench_key in "${bench_items[@]}"; do
                            if [[ "${component_checked[bench_$remove_bench_key]}" == true && "${component_action[bench_$remove_bench_key]}" =~ ^(install|update)$ ]]; then can_remove=true; fi
                        done
                    fi
                    [[ "$can_remove" == true || ( "$key" == bench_* && "$status" == 'needs docker' ) ]] || return 0
                    requested="uninstall"
                fi
                if [[ "${component_action[$key]}" == "$requested" ]]; then
                    component_checked["$key"]=false
                    component_action["$key"]=""
                else
                    component_checked["$key"]=true
                    component_action["$key"]="$requested"
                fi
                setup_refresh_bench_counts
                ;;
            ''|$'\r'|$'\n') # Enter activates a focused service button.
                if [[ "$CURRENT_SECTION" == 4 ]]; then activate_profile; return "$?"; fi
                if [[ "$CURRENT_SECTION" != 5 ]]; then
                    setup_arrive_step 5
                    return 0
                fi
                if ! setup_apply_allowed; then
                    requirements_notice='Wait for checks and resolve workstation requirements before Apply.'
                    return 0
                fi
                return 1
                ;;
            'r'|'R') requirements_notice=''; refresh_component_statuses; draw_ui ;;
            'p'|'P')
                if [[ "$CURRENT_SECTION" == 3 ]]; then setup_restore_target requirements
                else setup_remember_target requirements; setup_arrive_step 3; fi ;;
            'g'|'G')
                if [[ "$CURRENT_SECTION" == 4 ]]; then setup_restore_target profiles
                else setup_remember_target profiles; setup_arrive_step 4; fi ;;
            'v'|'V') # Vault remains available from every step.
                local vault_section=$CURRENT_SECTION vault_selection=$current_selection vault_zone=$setup_bench_zone vault_category=$setup_bench_category
                activate_requirement vault || return "$?"
                CURRENT_SECTION=$vault_section; current_selection=$vault_selection
                setup_bench_zone=$vault_zone; setup_bench_category=$vault_category ;;
            'q'|'Q') # Quit
                return 2
                ;;
        esac
    fi

    return 0
}

# Setup OpenAI API Key
setup_openai_key_interactive() {
    echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${BLUE}  OpenAI API Key Setup (for GPT-4 and GPT-5)${NC}"
    echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}① Login to OpenAI and get your API key:${NC}"
    echo ""
    echo -e "   ${GREEN}➤ Click here or copy URL:${NC}"
    echo -e "   ${CYAN}${BOLD}https://platform.openai.com/api-keys${NC}"
    echo ""
    echo -e "${YELLOW}② Steps to get your API key:${NC}"
    echo -e "   ${DIM}1. Log in to your OpenAI account${NC}"
    echo -e "   ${DIM}2. Click '+ Create new secret key'${NC}"
    echo -e "   ${DIM}3. Copy the key (it starts with 'sk-')${NC}"
    echo ""
    echo -e "${YELLOW}③ Paste your API key below:${NC}"
    echo ""

    while true; do
        echo -e "${CYAN}┌────────────────────────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}│ ${BOLD}OpenAI API Key:${NC}${CYAN}                                             │${NC}"
        echo -e "${CYAN}└────────────────────────────────────────────────────────────┘${NC}"
        setup_read "  sk-" openai_key
        openai_key="sk-$openai_key"

        if [ -z "$openai_key" ]; then
            echo -e "${RED}✗ API key cannot be empty.${NC}"
            setup_read "Try again? [Y/n]: " retry
            [[ "$retry" =~ ^[Nn] ]] && return 1
        elif [[ ! "$openai_key" =~ ^sk- ]]; then
            echo -e "${RED}✗ Invalid OpenAI API key format. Keys should start with 'sk-'${NC}"
            setup_read "Try again? [Y/n]: " retry
            [[ "$retry" =~ ^[Nn] ]] && return 1
        else
            echo -e "${YELLOW}Testing API key...${NC}"
            local test_response
            test_response=$(curl -s -X POST "https://api.openai.com/v1/chat/completions" \
                -H "Authorization: Bearer $openai_key" \
                -H "Content-Type: application/json" \
                -d '{
                    "model": "gpt-4o-mini",
                    "messages": [{"role": "user", "content": "Hi"}],
                    "max_tokens": 5
                }' 2>/dev/null)

            if echo "$test_response" | grep -q '"choices"'; then
                echo -e "${GREEN}✓ OpenAI API key validated successfully!${NC}"
                export OPENAI_API_KEY="$openai_key"
                # Save to shell profile
                save_to_profile "OPENAI_API_KEY" "$openai_key"
                return 0
            else
                echo -e "${RED}✗ API key validation failed.${NC}"
                local error_msg=$(echo "$test_response" | grep -o '"message":"[^"]*"' | head -1)
                [ -n "$error_msg" ] && echo "  Error: $error_msg"
                setup_read "Try again? [Y/n]: " retry
                [[ "$retry" =~ ^[Nn] ]] && return 1
            fi
        fi
    done
}

# Setup Anthropic API Key
setup_anthropic_key_interactive() {
    echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${BLUE}  Anthropic (Claude) API Key Setup${NC}"
    echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}① Login to Anthropic Console and get your API key:${NC}"
    echo ""
    echo -e "   ${GREEN}➤ Click here or copy URL:${NC}"
    echo -e "   ${CYAN}${BOLD}https://console.anthropic.com/account/keys${NC}"
    echo ""
    echo -e "${YELLOW}② Steps to get your API key:${NC}"
    echo -e "   ${DIM}1. Log in to your Anthropic account${NC}"
    echo -e "   ${DIM}2. Click '+ Create Key' or copy existing key${NC}"
    echo -e "   ${DIM}3. Copy the key (it starts with 'sk-')${NC}"
    echo ""
    echo -e "${YELLOW}③ Paste your API key below:${NC}"
    echo ""

    while true; do
        echo -e "${CYAN}┌────────────────────────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}│ ${BOLD}Anthropic API Key:${NC}${CYAN}                                          │${NC}"
        echo -e "${CYAN}└────────────────────────────────────────────────────────────┘${NC}"
        setup_read "  sk-" anthropic_key
        anthropic_key="sk-$anthropic_key"

        if [ -z "$anthropic_key" ]; then
            echo -e "${RED}✗ API key cannot be empty.${NC}"
            setup_read "Try again? [Y/n]: " retry
            [[ "$retry" =~ ^[Nn] ]] && return 1
        elif [[ ! "$anthropic_key" =~ ^sk- ]]; then
            echo -e "${RED}✗ Invalid Anthropic API key format. Keys should start with 'sk-'${NC}"
            setup_read "Try again? [Y/n]: " retry
            [[ "$retry" =~ ^[Nn] ]] && return 1
        else
            echo -e "${YELLOW}Testing API key...${NC}"
            local test_response
            test_response=$(curl -s -X POST "https://api.anthropic.com/v1/messages" \
                -H "x-api-key: $anthropic_key" \
                -H "Content-Type: application/json" \
                -H "anthropic-version: 2023-06-01" \
                -d '{
                    "model": "claude-3-haiku-20240307",
                    "max_tokens": 5,
                    "messages": [{"role": "user", "content": "Hi"}]
                }' 2>/dev/null)

            if echo "$test_response" | grep -q '"content"'; then
                echo -e "${GREEN}✓ Anthropic API key validated successfully!${NC}"
                export ANTHROPIC_API_KEY="$anthropic_key"
                save_to_profile "ANTHROPIC_API_KEY" "$anthropic_key"
                return 0
            else
                echo -e "${RED}✗ API key validation failed.${NC}"
                local error_msg=$(echo "$test_response" | grep -o '"message":"[^"]*"' | head -1)
                [ -n "$error_msg" ] && echo "  Error: $error_msg"
                setup_read "Try again? [Y/n]: " retry
                [[ "$retry" =~ ^[Nn] ]] && return 1
            fi
        fi
    done
}

# Setup Claude Session Token
setup_claude_session_interactive() {
    echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${BLUE}  Claude Session Token Setup (Browser-Based Auth)${NC}"
    echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}① Login to Claude and open DevTools:${NC}"
    echo ""
    echo -e "   ${GREEN}➤ Click here or copy URL:${NC}"
    echo -e "   ${CYAN}${BOLD}https://claude.ai/${NC}"
    echo ""
    echo -e "${YELLOW}② Get your session key from browser cookies:${NC}"
    echo -e "   ${DIM}1. Press F12 to open DevTools${NC}"
    echo -e "   ${DIM}2. Go to: Application → Cookies → https://claude.ai${NC}"
    echo -e "   ${DIM}3. Find 'sessionKey' and copy its value${NC}"
    echo -e "   ${DIM}4. It starts with 'sk-ant-sid'${NC}"
    echo ""
    echo -e "${YELLOW}③ Paste your session key below:${NC}"
    echo ""

    while true; do
        echo -e "${CYAN}┌────────────────────────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}│ ${BOLD}Claude Session Key:${NC}${CYAN}                                         │${NC}"
        echo -e "${CYAN}└────────────────────────────────────────────────────────────┘${NC}"
        setup_read "  " session_key

        if [ -z "$session_key" ]; then
            echo -e "${RED}✗ Session key cannot be empty.${NC}"
            setup_read "Try again? [Y/n]: " retry
            [[ "$retry" =~ ^[Nn] ]] && return 1
        elif [[ ! "$session_key" =~ ^sk-ant-sid ]]; then
            echo -e "${YELLOW}⚠️  Warning: Session key format doesn't match expected pattern.${NC}"
            setup_read "Continue anyway? [y/N]: " continue_anyway
            [[ ! "$continue_anyway" =~ ^[Yy] ]] && continue
        fi

        mkdir -p "$HOME/.claude"
        cat > "$HOME/.claude/config.json" << EOF
{
  "sessionKey": "$session_key",
  "createdAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "createdBy": "workBenches interactive setup"
}
EOF
        chmod 600 "$HOME/.claude/config.json"
        echo -e "${GREEN}✓ Claude session key saved to ~/.claude/config.json${NC}"
        return 0
    done
}

# Save API key to shell profile
save_to_profile() {
    local key_name="$1"
    local key_value="$2"
    local shell_profile

    if [ -n "$ZSH_VERSION" ]; then
        shell_profile="$HOME/.zshrc"
    elif [ -n "$BASH_VERSION" ]; then
        shell_profile="$HOME/.bashrc"
    else
        shell_profile="$HOME/.profile"
    fi

    if grep -q "^export $key_name=" "$shell_profile" 2>/dev/null; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i "" "s/^export $key_name=.*/export $key_name='$key_value'/" "$shell_profile"
        else
            sed -i "s/^export $key_name=.*/export $key_name='$key_value'/" "$shell_profile"
        fi
    else
        echo "" >> "$shell_profile"
        echo "# workBenches AI API Key" >> "$shell_profile"
        echo "export $key_name='$key_value'" >> "$shell_profile"
    fi

    echo -e "${BLUE}  Saved to $shell_profile${NC}"
}

# Check if a directory is safe for cloning a repo into
# Returns:
#   0 = Safe to remove and clone (empty or only temp files)
#   10 = Safe to clone alongside (no conflicts with existing files)
#   1 = NOT safe (has conflicts or important files)
check_dir_safe_to_replace() {
    local dir="$1"
    local repo_url="$2"  # Optional: URL of repo being cloned

    if [ ! -d "$dir" ]; then
        # Directory doesn't exist, safe to clone
        return 0
    fi

    # Get list of files (excluding . and ..)
    local files
    files=$(ls -A "$dir" 2>/dev/null)

    if [ -z "$files" ]; then
        # Directory is empty, safe to remove and replace
        return 0
    fi

    # Check if only safe-to-remove files exist
    # Safe files: .DS_Store, Zone.Identifier files, desktop.ini, Thumbs.db
    local safe_patterns=(".DS_Store" "*:Zone.Identifier" "desktop.ini" "Thumbs.db")
    local has_unsafe=false

    for file in $files; do
        local is_safe=false
        for pattern in "${safe_patterns[@]}"; do
            if [[ "$file" == $pattern ]]; then
                is_safe=true
                break
            fi
        done
        if [ "$is_safe" = false ]; then
            has_unsafe=true
            break
        fi
    done

    if [ "$has_unsafe" = false ]; then
        # Only safe temp files, OK to remove and replace
        return 0
    fi

    # Has real files - if repo URL provided, check for conflicts
    if [ -n "$repo_url" ] && [ "$repo_url" != "null" ]; then
        log "Checking for file conflicts between existing directory and repo"

        # Clone to temp location to see what files would be created
        local temp_dir=$(mktemp -d)
        if workbenches_clone "$repo_url" "$temp_dir" --depth=1 --quiet 2>/dev/null; then
            # Get list of files/folders that would be created (top-level only)
            local repo_items
            repo_items=$(cd "$temp_dir" && ls -A | grep -v "^\.git$")

            # Check if any existing files/folders would conflict
            local has_conflict=false
            for item in $repo_items; do
                if [ -e "$dir/$item" ]; then
                    log "Conflict found: $item exists in both locations"
                    has_conflict=true
                    break
                fi
            done

            # Cleanup temp directory
            rm -rf "$temp_dir"

            if [ "$has_conflict" = false ]; then
                # No conflicts - safe to clone alongside existing files
                log "No file conflicts detected, can clone alongside"
                return 10  # Special code: clone alongside
            fi
        else
            # Failed to clone to temp - fall back to blocking
            rm -rf "$temp_dir" 2>/dev/null
        fi
    fi

    # Has unsafe files or conflicts - not safe
    return 1
}

# Process selected items
process_selections() {
    log "Processing selections - applying configuration changes"
    echo -e "${SHOW_CURSOR}"
    clear

    echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${BLUE}  Applying Configuration Changes${NC}"
    echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════════════════${NC}"
    echo ""

    local any_selected=false
    local success_count=0
    local fail_count=0 active_component=""
    local -A failed_components=()
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local config_file="$script_dir/../config/bench-config.json"

    # Process benches
    for bench in "${bench_items[@]}"; do
        local key="bench_$bench"
        if [[ "${component_checked[$key]}" == true && -n "${component_action[$key]}" ]]; then
            active_component="$key"
            local action="${component_action[$key]}"
            local status="${component_status[$key]}"
            local bench_path
            if ! bench_checkout_path "$bench" bench_path; then
                any_selected=true
                echo "Needs attention: cannot resolve $bench in the bench catalog"
                failed_components[$active_component]=true; ((fail_count++))
                continue
            fi
            if [[ "$status" == 'needs check' || "$status" == 'needs docker' ]]; then
                any_selected=true
                echo "Needs attention: cannot verify $bench runtime/checkout; refresh after restoring Docker or the expected checkout."
                failed_components[$active_component]=true; ((fail_count++))
                continue
            fi

            # Installed benches with no pending action: check Layer 2/3 images, skip if current
            if [[ "$status" == "installed" && -z "$action" ]]; then
                local full_bench_path="$script_dir/../$bench_path"
                local image_repo
                image_repo=$(bench_dir_to_image_repo "$bench")
                local l2_image="${image_repo}:latest"
                local l3_image="${image_repo}:$(whoami)"

                local l2_exists=false
                local l3_exists=false
                docker image inspect "$l2_image" >/dev/null 2>&1 && l2_exists=true
                docker image inspect "$l3_image" >/dev/null 2>&1 && l3_exists=true

                # Also check docker-compose-style names (e.g. sim-bench-gene_bench:latest)
                # These are complete images — no separate Layer 3 needed
                if [ "$l2_exists" = false ] && [ "$l3_exists" = false ]; then
                    local compose_match=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep -i "^${image_repo}" | head -1)
                    if [ -n "$compose_match" ]; then
                        l3_image="$compose_match"
                        l3_exists=true
                    fi
                fi

                if [ "$l2_exists" = true ] && [ "$l3_exists" = true ]; then
                    echo -e "${BOLD}${CYAN}▶ $bench${NC} ${GREEN}✓ up to date${NC} ${DIM}($l2_image + $l3_image)${NC}"
                    log "$bench: Layer 2 and Layer 3 images present, skipping"
                    ((success_count++))
                    continue
                elif [ "$l2_exists" = true ] && [ "$l3_exists" = false ]; then
                    echo -e "${BOLD}${CYAN}▶ $bench${NC} ${YELLOW}⚠ Layer 3 image missing${NC} ${DIM}(run: ensure-layer3.sh --base $l2_image)${NC}"
                    log "$bench: Layer 2 exists but Layer 3 ($l3_image) missing"
                    ((success_count++))
                    continue
                elif [ "$l2_exists" = false ] && [ "$l3_exists" = true ]; then
                    # Old-style :$USER image exists but no :latest — still functional
                    echo -e "${BOLD}${CYAN}▶ $bench${NC} ${GREEN}✓ up to date${NC} ${DIM}($l3_image)${NC}"
                    log "$bench: Layer 3 image present (legacy naming), skipping"
                    ((success_count++))
                    continue
                else
                    # No images at all — needs build, fall through to install path
                    echo -e "${BOLD}${CYAN}▶ $bench${NC} ${YELLOW}⚠ no Docker image found, will build${NC}"
                    log "$bench: no images found, falling through to install"
                fi
            fi

            any_selected=true

            if [[ "$action" == "uninstall" ]]; then
                log "Uninstalling bench: $bench"
                echo -e "${BOLD}${CYAN}▶ Uninstalling: $bench${NC}"
                if uninstall_component "$key"; then
                    ((success_count++))
                else
                    local removal_status=$?
                    setup_propagate_cancel "$removal_status"
                    failed_components[$active_component]=true; ((fail_count++))
                fi
                echo ""
            else
                # Check if needs setup vs install
                if [[ "$status" == "needs creds" || "$status" == "needs setup" || "$status" == "needs check" || "$status" == 'image only' ]]; then
                    # Bench is installed but not set up
                    log "Setting up bench: $bench"
                    echo -e "${BOLD}${CYAN}▶ Setting up: $bench${NC}"
                    local full_bench_path="$script_dir/../$bench_path"
                    local setup_script="$full_bench_path/setup.sh"

                    # If it's a git repo, fetch latest updates first
                    if [[ "${WORKBENCHES_FROZEN:-}" != 1 ]] && { [ -d "$full_bench_path/.git" ] || [ -f "$full_bench_path/.git" ]; }; then
                        local bench_url=$(jq -r --arg n "$bench" '.benches[$n].url // empty' "$config_file" 2>/dev/null)
                        if [ -n "$bench_url" ] && [ "$bench_url" != "null" ]; then
                            echo -e "  ${YELLOW}Fetching latest updates from: $bench_url${NC}"
                            log "Fetching updates for $bench before setup"

                            # Fetch in background with spinner
                            (
                                cd "$full_bench_path" && git fetch --all >> "$LOG_FILE" 2>&1 && git pull >> "$LOG_FILE" 2>&1
                                echo $? > /tmp/fetch_status_$$
                            ) &
                            local fetch_pid=$!
                            show_spinner $fetch_pid "Fetching updates for $bench"

                            local fetch_status=$(cat /tmp/fetch_status_$$ 2>/dev/null || echo "1")
                            rm -f /tmp/fetch_status_$$

                            if [ "$fetch_status" -eq 0 ]; then
                                log "Successfully fetched and pulled updates for $bench"
                                echo -e "  ${GREEN}✓ Updated to latest version${NC}"
                            else
                                log "WARNING: Failed to fetch updates for $bench"
                                echo -e "  ${YELLOW}⚠ Failed to fetch updates, continuing with current version${NC}"
                            fi
                        fi
                    fi

                    if [ -f "$setup_script" ]; then
                        log "Running setup script: $setup_script"
                        echo -e "  ${YELLOW}Running setup script...${NC}"
                        echo -e "  ${DIM}This may take several minutes...${NC}"

                        # Run setup in background with spinner (cd to bench dir first)
                        (
                            python3 "$script_dir/setup-bench-runtime.py" --bench "$bench" --setup "$setup_script" >> "$LOG_FILE" 2>&1
                            echo $? > /tmp/setup_status_$$
                        ) &
                        local setup_pid=$!
                        show_spinner $setup_pid "Setting up $bench" 1200 build

                        local setup_status=$(cat /tmp/setup_status_$$ 2>/dev/null || echo "1")
                        rm -f /tmp/setup_status_$$

                        if [ "$setup_status" -eq 0 ]; then
                            log "Successfully set up $bench"
                            echo -e "  ${GREEN}✓ $bench is ready (launch verified)${NC}"
                            echo -e "  ${DIM}Command 'new-${bench}-project' should now be available${NC}"
                            ((success_count++))
                        else
                            log "ERROR: Setup script failed for $bench"
                            echo -e "  ${RED}✗ Setup script failed${NC}"
                            failed_components[$active_component]=true; ((fail_count++))
                        fi
                    else
                        # No setup.sh — try inline setup: look for build-layer.sh
                        local build_script=""
                        if [ -f "$full_bench_path/scripts/build-layer.sh" ]; then
                            build_script="$full_bench_path/scripts/build-layer.sh"
                        elif [ -f "$full_bench_path/build-layer.sh" ]; then
                            build_script="$full_bench_path/build-layer.sh"
                        fi

                        if [ -n "$build_script" ]; then
                            log "No setup.sh found, running build-layer.sh inline for $bench"
                            echo -e "  ${YELLOW}No setup.sh — building bench image...${NC}"

                            (
                                cd "$(dirname "$build_script")" && bash "$build_script" >> "$LOG_FILE" 2>&1
                                echo $? > /tmp/setup_status_$$
                            ) &
                            local build_pid=$!
                            show_spinner $build_pid "Building $bench image" 1200

                            local build_status=$(cat /tmp/setup_status_$$ 2>/dev/null || echo "1")
                            rm -f /tmp/setup_status_$$

                            if [ "$build_status" -eq 0 ]; then
                                log "Successfully built image for $bench"
                                echo -e "  ${GREEN}✓ Image built for $bench${NC}"
                                ((success_count++))
                            else
                                log "ERROR: build-layer.sh failed for $bench"
                                echo -e "  ${RED}✗ Image build failed for $bench${NC}"
                                failed_components[$active_component]=true; ((fail_count++))
                            fi
                        else
                            # No setup.sh and no build-layer.sh — repo is cloned, that's sufficient
                            log "No setup.sh or build-layer.sh for $bench — repo cloned, ready for VS Code"
                            echo -e "  ${GREEN}✓ $bench repo is up to date${NC}"
                            echo -e "  ${DIM}Open in VS Code with Dev Containers to complete setup${NC}"
                            ((success_count++))
                        fi
                    fi
                    echo ""
                else
                    # Install from scratch (or fetch if directory exists)
                    echo -e "${BOLD}${CYAN}▶ Installing: $bench${NC}"

                    # Get bench info from config
                    if [ -f "$config_file" ]; then
                        local bench_url=$(jq -r --arg n "$bench" '.benches[$n].url // empty' "$config_file")
                        local full_bench_path="$script_dir/../$bench_path"

                        if [ -n "$bench_url" ] && [ "$bench_url" != "null" ]; then
                            # Check if directory already exists
                            if [ -d "$full_bench_path" ]; then
                                # Directory exists - check if it has git
                                if [ -d "$full_bench_path/.git" ] || [ -f "$full_bench_path/.git" ]; then
                                    # Release sources were prepared at their locked commit.
                                    if [[ "${WORKBENCHES_FROZEN:-}" == 1 ]]; then
                                        echo -e "  ${GREEN}Using frozen release source for $bench${NC}"
                                    else
                                        echo -e "  ${YELLOW}Directory exists, fetching updates from: $bench_url${NC}"
                                        log "Fetching and pulling updates for $bench from $bench_url"

                                        # Fetch and pull in background with spinner
                                        (
                                            cd "$full_bench_path" && git fetch --all >> "$LOG_FILE" 2>&1 && git pull >> "$LOG_FILE" 2>&1
                                            echo $? > /tmp/fetch_status_$$
                                        ) &
                                        local fetch_pid=$!
                                        show_spinner $fetch_pid "Updating $bench"

                                        local fetch_status=$(cat /tmp/fetch_status_$$ 2>/dev/null || echo "1")
                                        rm -f /tmp/fetch_status_$$

                                        if [ "$fetch_status" -eq 0 ]; then
                                            log "Successfully fetched and pulled updates for $bench"
                                            echo -e "  ${GREEN}✓ Successfully updated to latest version${NC}"
                                        else
                                            log "ERROR: Failed to fetch/pull updates for $bench"
                                            echo -e "  ${RED}✗ Failed to fetch updates${NC}"
                                            failed_components[$active_component]=true; ((fail_count++))
                                            echo ""
                                            continue
                                        fi
                                    fi
                                else
                                    # Directory exists but no git - check if safe to replace
                                    check_dir_safe_to_replace "$full_bench_path" "$bench_url"
                                    local safe_status=$?

                                    if [ $safe_status -eq 0 ] || [ $safe_status -eq 10 ]; then
                                        # Safe to proceed - either remove+clone or clone alongside
                                        if [ $safe_status -eq 0 ]; then
                                            # Empty or only temp files - remove and clone
                                            echo -e "  ${YELLOW}Directory is empty/has only temp files. Removing and cloning...${NC}"
                                            log "Removing safe-to-replace directory: $full_bench_path"
                                            rm -rf "$full_bench_path"
                                        else
                                            # Has files but no conflicts - clone alongside
                                            echo -e "  ${YELLOW}Directory has files but no conflicts. Cloning alongside...${NC}"
                                            log "Cloning alongside existing files: $full_bench_path"
                                        fi

                                        # Now clone
                                        echo -e "  ${YELLOW}Cloning from: $bench_url${NC}"
                                        log "Cloning $bench from $bench_url"

                                        # Clone in background with spinner
                                        (
                                            workbenches_clone "$bench_url" "$full_bench_path" >> "$LOG_FILE" 2>&1
                                            echo $? > /tmp/clone_status_$$
                                        ) &
                                        local clone_pid=$!
                                        show_spinner $clone_pid "Cloning $bench"

                                        local clone_status=$(cat /tmp/clone_status_$$ 2>/dev/null || echo "1")
                                        rm -f /tmp/clone_status_$$

                                        if [ "$clone_status" -ne 0 ]; then
                                            log "ERROR: Failed to clone $bench"
                                            echo -e "  ${RED}✗ Failed to clone $bench${NC}"
                                            failed_components[$active_component]=true; ((fail_count++))
                                            echo ""
                                            continue
                                        fi
                                        log "Successfully cloned $bench"
                                        echo -e "  ${GREEN}✓ Successfully cloned $bench${NC}"
                                    else
                                        # Directory has real files - cannot safely proceed
                                        echo -e "  ${RED}✗ Directory exists but is not a git repository${NC}"
                                        log "ERROR: $full_bench_path exists but has no .git directory"
                                        echo -e "  ${YELLOW}⚠ Cannot safely clone - directory may contain important files${NC}"
                                        echo ""
                                        echo -e "  ${CYAN}To resolve, manually:${NC}"
                                        echo -e "  ${DIM}1. Backup any important files from: $full_bench_path${NC}"
                                        echo -e "  ${DIM}2. Remove the directory: rm -rf $full_bench_path${NC}"
                                        echo -e "  ${DIM}3. Run this setup again${NC}"
                                        echo ""
                                        echo -e "  ${DIM}Or initialize as git repo:${NC}"
                                        echo -e "  ${DIM}cd $full_bench_path && git init && git remote add origin $bench_url && git fetch && git checkout -f origin/main${NC}"
                                        echo ""
                                        failed_components[$active_component]=true; ((fail_count++))
                                        echo ""
                                        continue
                                    fi
                                fi
                            else
                                # Directory doesn't exist, clone it
                                echo -e "  ${YELLOW}Cloning from: $bench_url${NC}"
                                log "Cloning $bench from $bench_url"

                                # Clone in background with spinner
                                (
                                    workbenches_clone "$bench_url" "$full_bench_path" >> "$LOG_FILE" 2>&1
                                    echo $? > /tmp/clone_status_$$
                                ) &
                                local clone_pid=$!
                                show_spinner $clone_pid "Cloning $bench"

                                local clone_status=$(cat /tmp/clone_status_$$ 2>/dev/null || echo "1")
                                rm -f /tmp/clone_status_$$

                                if [ "$clone_status" -ne 0 ]; then
                                    log "ERROR: Failed to clone $bench"
                                    echo -e "  ${RED}✗ Failed to clone $bench${NC}"
                                    failed_components[$active_component]=true; ((fail_count++))
                                    echo ""
                                    continue
                                fi
                                log "Successfully cloned $bench"
                                echo -e "  ${GREEN}✓ Successfully cloned $bench${NC}"
                            fi

                            # At this point, the repo is ready (either cloned or fetched)
                            # Check for and run setup script
                            local setup_script="$script_dir/../$bench_path/setup.sh"
                            if [ -f "$setup_script" ]; then
                                echo -e "  ${YELLOW}Running setup script...${NC}"
                                echo -e "  ${DIM}This may take several minutes...${NC}"
                                log "Running setup script for $bench"

                                # Run setup in background with spinner (cd to bench dir first)
                                (
                                    python3 "$script_dir/setup-bench-runtime.py" --bench "$bench" --setup "$setup_script" >> "$LOG_FILE" 2>&1
                                    echo $? > /tmp/setup_status_$$
                                ) &
                                local setup_pid=$!
                                show_spinner $setup_pid "Setting up $bench" 1200 build

                                local setup_status=$(cat /tmp/setup_status_$$ 2>/dev/null || echo "1")
                                rm -f /tmp/setup_status_$$

                                if [ "$setup_status" -eq 0 ]; then
                                    log "Successfully set up $bench"
                                    echo -e "  ${GREEN}✓ $bench is ready (launch verified)${NC}"
                                    ((success_count++))
                                else
                                    log "ERROR: Setup failed for $bench"
                                    echo -e "  ${YELLOW}⚠ Setup failed${NC}"
                                    echo -e "  ${DIM}Inspect the build log and rerun workBenches setup after stopping this bench; Wave will display a repair command if needed.${NC}"
                                    failed_components[$active_component]=true; ((fail_count++))
                                fi
                            else
                                # No setup.sh — try inline: build-layer.sh
                                local build_script=""
                                if [ -f "$full_bench_path/scripts/build-layer.sh" ]; then
                                    build_script="$full_bench_path/scripts/build-layer.sh"
                                elif [ -f "$full_bench_path/build-layer.sh" ]; then
                                    build_script="$full_bench_path/build-layer.sh"
                                fi

                                if [ -n "$build_script" ]; then
                                    log "No setup.sh, running build-layer.sh inline for $bench"
                                    echo -e "  ${YELLOW}Building bench image...${NC}"

                                    (
                                        cd "$(dirname "$build_script")" && bash "$build_script" >> "$LOG_FILE" 2>&1
                                        echo $? > /tmp/setup_status_$$
                                    ) &
                                    local build_pid=$!
                                    show_spinner $build_pid "Building $bench image" 1200

                                    local build_status=$(cat /tmp/setup_status_$$ 2>/dev/null || echo "1")
                                    rm -f /tmp/setup_status_$$

                                    if [ "$build_status" -eq 0 ]; then
                                        log "Successfully built image for $bench"
                                        echo -e "  ${GREEN}✓ Image built for $bench${NC}"
                                        ((success_count++))
                                    else
                                        log "ERROR: build-layer.sh failed for $bench"
                                        echo -e "  ${YELLOW}⚠ Image build failed${NC}"
                                        echo -e "  ${DIM}You may need to run manually: $build_script${NC}"
                                        ((success_count++))
                                    fi
                                else
                                    echo -e "  ${GREEN}✓ $bench cloned and ready${NC}"
                                    echo -e "  ${DIM}Open in VS Code with Dev Containers to complete setup${NC}"
                                    ((success_count++))
                                fi
                            fi
                        else
                            echo -e "  ${RED}✗ No repository URL found for $bench${NC}"
                            failed_components[$active_component]=true; ((fail_count++))
                        fi
                    else
                        echo -e "  ${RED}✗ Config file not found${NC}"
                        failed_components[$active_component]=true; ((fail_count++))
                    fi
                    echo ""
                fi
            fi
        fi
    done

    # Process AI items
    for item in "${ai_items[@]}"; do
        if [[ "$item" == separator* ]]; then
            continue
        fi

        if [[ "${component_checked[$item]}" == true && -n "${component_action[$item]}" ]]; then
            any_selected=true
            active_component="$item"
            local desc="${component_description[$item]}"
            local action="${component_action[$item]}"

            if [[ -n "${setup_managed_harnesses[$item]:-}" ]]; then
                local -a harness_targets=()
                local bench_key
                for bench_key in "${!component_checked[@]}"; do
                    if [[ "$bench_key" == bench_* && "${component_checked[$bench_key]}" == true && "${component_action[$bench_key]}" =~ ^(install|update)$ ]]; then
                        harness_targets+=(--bench "${bench_key#bench_}")
                    fi
                done
                echo "▶ $action: $desc (workstation and selected bench containers)"
                if python3 "$SCRIPT_DIR/setup-harnesses.py" "$action" "$item" "${harness_targets[@]}"; then
                    ((success_count++))
                else
                    setup_propagate_cancel "$?"
                    failed_components[$active_component]=true; ((fail_count++))
                fi
                echo ""
                continue
            fi

            # Handle uninstallation
            if [[ "$action" == "uninstall" ]]; then
                echo -e "${BOLD}${CYAN}▶ Uninstalling: $desc${NC}"

                if uninstall_component "$item"; then
                    ((success_count++))
                else
                    failed_components[$active_component]=true; ((fail_count++))
                fi
                echo ""
                continue
            fi

            # Handle installation or update
            local status="${component_status[$item]}"
            local is_installed=false
            [[ "$status" == "installed" || "$status" == "needs creds" ]] && is_installed=true

            if [ "$is_installed" = true ]; then
                echo -e "${BOLD}${CYAN}▶ Checking for updates: $desc${NC}"
            else
                echo -e "${BOLD}${CYAN}▶ Installing: $desc${NC}"
            fi

            case "$item" in
                claude_cli)
                    if [ "$is_installed" = true ]; then
                        echo -e "  ${YELLOW}Checking Claude Code CLI version...${NC}"
                        echo -e "  ${DIM}Claude CLI auto-updates in the background (native installer)${NC}"
                        echo -e "  ${GREEN}✓ Claude Code CLI is up to date${NC}"
                        ((success_count++))
                    else
                        echo -e "  ${YELLOW}Installing Claude Code CLI (native installer)...${NC}"
                        echo -e "  ${DIM}This may take a few minutes...${NC}"
                        echo -e "  ${BOLD}${RED}Please do not interrupt the installation (Ctrl+C)${NC}"
                        log "Starting Claude CLI installation via native installer"

                        # Install Claude Code CLI via native installer (npm method is deprecated)
                        # Native installer: no Node.js dependency, auto-updates, installs to ~/.local/bin
                        trap 'exit 130' INT
                        (
                            curl -fsSL https://claude.ai/install.sh | bash >> "$LOG_FILE" 2>&1
                        ) &
                        local install_pid=$!

                        if show_spinner $install_pid "Installing Claude CLI" 180; then
                            trap 'exit 130' INT
                            log "Claude CLI installed successfully via native installer"
                            echo -e "  ${GREEN}✓ Claude Code CLI installed${NC}"
                            echo -e "  ${DIM}Run 'claude' to start using it${NC}"
                            ((success_count++))
                        else
                            trap 'exit 130' INT
                            log "ERROR: Claude CLI installation failed"
                            echo -e "  ${RED}✗ Failed to install Claude Code CLI${NC}"
                            echo -e "  ${DIM}Manual install: curl -fsSL https://claude.ai/install.sh | bash${NC}"
                            failed_components[$active_component]=true; ((fail_count++))
                        fi
                    fi
                    ;;

                copilot_cli)
                    if command -v npm &> /dev/null; then
                        if [ "$is_installed" = true ]; then
                            echo -e "  ${YELLOW}Checking for Copilot CLI updates...${NC}"
                            if npm_update_tool "@github/copilot" "GitHub Copilot CLI"; then
                                ((success_count++))
                            else
                                failed_components[$active_component]=true; ((fail_count++))
                            fi
                        else
                            echo -e "  ${YELLOW}Installing GitHub Copilot CLI...${NC}"
                            if npm install -g @github/copilot; then
                                echo -e "  ${GREEN}✓ GitHub Copilot CLI installed${NC}"
                                ((success_count++))
                            else
                                echo -e "  ${RED}✗ Failed to install GitHub Copilot CLI${NC}"
                                failed_components[$active_component]=true; ((fail_count++))
                            fi
                        fi
                    else
                        echo -e "  ${RED}✗ npm not found - Node.js required${NC}"
                        echo -e "  ${DIM}Install Node.js: https://nodejs.org/${NC}"
                        failed_components[$active_component]=true; ((fail_count++))
                    fi
                    ;;

                codex_cli)
                    if command -v npm &> /dev/null; then
                        # Check Node.js version
                        local node_version=$(node --version 2>/dev/null | cut -d'v' -f2 | cut -d'.' -f1)
                        if [ -n "$node_version" ] && [ "$node_version" -ge 18 ]; then
                            if [ "$is_installed" = true ]; then
                                echo -e "  ${YELLOW}Checking for Codex CLI updates...${NC}"
                                if npm_update_tool "@openai/codex" "Codex CLI"; then
                                    ((success_count++))
                                else
                                    failed_components[$active_component]=true; ((fail_count++))
                                fi
                            else
                                echo -e "  ${YELLOW}Installing OpenAI Codex CLI...${NC}"
                                if npm install -g @openai/codex; then
                                    echo -e "  ${GREEN}✓ OpenAI Codex CLI installed${NC}"
                                    ((success_count++))
                                else
                                    echo -e "  ${RED}✗ Failed to install Codex CLI${NC}"
                                    failed_components[$active_component]=true; ((fail_count++))
                                fi
                            fi
                        else
                            echo -e "  ${RED}✗ Node.js 18+ required (current: v$node_version)${NC}"
                            echo -e "  ${DIM}Recommended: Node.js 24+${NC}"
                            echo -e "  ${DIM}Install/Update Node.js: https://nodejs.org/${NC}"
                            failed_components[$active_component]=true; ((fail_count++))
                        fi
                    else
                        echo -e "  ${RED}✗ npm not found - Node.js required${NC}"
                        echo -e "  ${DIM}Install Node.js 24+: https://nodejs.org/${NC}"
                        failed_components[$active_component]=true; ((fail_count++))
                    fi
                    ;;

                antigravity_cli)
                    if [ "$is_installed" = true ]; then
                        echo -e "  ${GREEN}✓ Antigravity CLI is already installed${NC}"
                        echo -e "  ${DIM}Antigravity CLI self-updates during regular runs${NC}"
                        ((success_count++))
                    else
                        echo -e "  ${YELLOW}Installing Antigravity CLI...${NC}"
                        echo -e "  ${DIM}This installs the 'agy' command from antigravity.google${NC}"
                        echo -e "  ${BOLD}${RED}Please do not interrupt the installation (Ctrl+C)${NC}"
                        log "Starting Antigravity CLI installation via official installer"

                        trap 'exit 130' INT
                        (
                            curl -fsSL https://antigravity.google/cli/install.sh | bash >> "$LOG_FILE" 2>&1
                        ) &
                        local install_pid=$!

                        if show_spinner $install_pid "Installing Antigravity CLI" 180; then
                            trap 'exit 130' INT
                            export PATH="$HOME/.local/bin:$PATH"
                            if command -v agy &> /dev/null; then
                                log "Antigravity CLI installed successfully"
                                echo -e "  ${GREEN}✓ Antigravity CLI installed${NC}"
                                echo -e "  ${DIM}Run 'agy' to start using it${NC}"
                                ((success_count++))
                            else
                                log "ERROR: Antigravity CLI installer completed but agy is not on PATH"
                                echo -e "  ${RED}✗ Antigravity CLI installed but 'agy' is not on PATH${NC}"
                                echo -e "  ${DIM}Add ~/.local/bin to PATH or run: ~/.local/bin/agy${NC}"
                                failed_components[$active_component]=true; ((fail_count++))
                            fi
                        else
                            trap 'exit 130' INT
                            log "ERROR: Antigravity CLI installation failed"
                            echo -e "  ${RED}✗ Failed to install Antigravity CLI${NC}"
                            echo -e "  ${DIM}Manual install: curl -fsSL https://antigravity.google/cli/install.sh | bash${NC}"
                            failed_components[$active_component]=true; ((fail_count++))
                        fi
                    fi
                    ;;

                opencode_cli)
                    if [ "$is_installed" = true ]; then
                        echo -e "  ${GREEN}✓ OpenCode CLI is installed${NC}"
                        ((success_count++))
                    elif command -v npm &>/dev/null && npm install -g opencode-ai; then
                        echo -e "  ${GREEN}✓ OpenCode CLI installed${NC}"
                        ((success_count++))
                    else
                        echo -e "  ${RED}✗ Failed to install OpenCode CLI${NC}"
                        failed_components[$active_component]=true; ((fail_count++))
                    fi
                    ;;

                pi_cli)
                    if [ "$is_installed" = true ]; then
                        echo -e "  ${GREEN}✓ Pi Coding Agent is installed${NC}"
                        ((success_count++))
                    elif [[ -x /usr/bin/npm ]] && /usr/bin/npm install -g --ignore-scripts @earendil-works/pi-coding-agent; then
                        echo -e "  ${GREEN}✓ Pi Coding Agent installed${NC}"
                        ((success_count++))
                    elif command -v npm &>/dev/null && npm install -g --ignore-scripts @earendil-works/pi-coding-agent; then
                        echo -e "  ${GREEN}✓ Pi Coding Agent installed${NC}"
                        ((success_count++))
                    else
                        echo -e "  ${RED}✗ Failed to install Pi Coding Agent${NC}"
                        failed_components[$active_component]=true; ((fail_count++))
                    fi
                    ;;

                spec_kit)
                    echo -e "  ${YELLOW}Installing spec-kit (GitHub Spec Kit)...${NC}"
                    # Check for uv
                    if ! command -v uvx &> /dev/null; then
                        echo -e "  ${YELLOW}Installing uv package manager...${NC}"
                        echo -e "  ${DIM}This may take a minute...${NC}"
                        log "Starting uv installation"

                        # Install uv in background with spinner
                        (
                            curl -LsSf https://astral.sh/uv/install.sh 2>&1 | sh >> "$LOG_FILE" 2>&1
                            echo $? > /tmp/uv_install_status_$$
                        ) &
                        local uv_pid=$!
                        show_spinner $uv_pid "Installing uv"

                        local uv_status=$(cat /tmp/uv_install_status_$$ 2>/dev/null || echo "1")
                        rm -f /tmp/uv_install_status_$$

                        if [ "$uv_status" -eq 0 ]; then
                            log "uv installed successfully"
                            # Source shell config to pick up PATH changes
                            if [ -n "$ZSH_VERSION" ]; then
                                source "$HOME/.zshrc" 2>/dev/null || export PATH="$HOME/.local/bin:$PATH"
                            elif [ -n "$BASH_VERSION" ]; then
                                source "$HOME/.bashrc" 2>/dev/null || export PATH="$HOME/.local/bin:$PATH"
                            else
                                export PATH="$HOME/.local/bin:$PATH"
                            fi
                        else
                            log "ERROR: uv installation failed"
                            echo -e "  ${RED}✗ uv installation failed${NC}"
                        fi
                    fi

                    if command -v uv &> /dev/null; then
                        # Install spec-kit persistently
                        if uv tool install specify-cli --from git+https://github.com/github/spec-kit.git &> /dev/null; then
                            echo -e "  ${GREEN}✓ spec-kit installed${NC}"
                            ((success_count++))
                        else
                            echo -e "  ${RED}✗ Failed to install spec-kit${NC}"
                            failed_components[$active_component]=true; ((fail_count++))
                        fi
                    else
                        echo -e "  ${RED}✗ uv installation failed${NC}"
                        echo -e "  ${DIM}Try manually: curl -LsSf https://astral.sh/uv/install.sh | sh${NC}"
                        echo -e "  ${DIM}Then restart your shell or run: source ~/.zshrc${NC}"
                        failed_components[$active_component]=true; ((fail_count++))
                    fi
                    ;;

                openspec)
                    if command -v npm &> /dev/null; then
                        if [ "$is_installed" = true ]; then
                            echo -e "  ${YELLOW}Checking for OpenSpec updates...${NC}"
                            if npm_update_tool "@fission-ai/openspec" "OpenSpec"; then
                                ((success_count++))
                            else
                                failed_components[$active_component]=true; ((fail_count++))
                            fi
                        else
                            echo -e "  ${YELLOW}Installing OpenSpec...${NC}"
                            if npm install -g @fission-ai/openspec@latest; then
                                echo -e "  ${GREEN}✓ OpenSpec installed${NC}"
                                ((success_count++))
                            else
                                echo -e "  ${RED}✗ Failed to install OpenSpec${NC}"
                                failed_components[$active_component]=true; ((fail_count++))
                            fi
                        fi
                    else
                        echo -e "  ${RED}✗ npm not found - Node.js required${NC}"
                        echo -e "  ${DIM}Install Node.js: https://nodejs.org/${NC}"
                        failed_components[$active_component]=true; ((fail_count++))
                    fi
                    ;;
            esac
            echo ""
        fi
    done

    # Process tool items
    for item in "${tool_items[@]}"; do
        if [[ "${component_checked[$item]}" == true && -n "${component_action[$item]}" ]]; then
            any_selected=true
            active_component="$item"
            local desc="${component_description[$item]}"
            local action="${component_action[$item]}"
            local status="${component_status[$item]}"
            local is_installed=false
            [[ "$status" == "installed" || "$status" == "needs creds" ]] && is_installed=true

            if [[ "$item" == ai_accounts ]]; then continue; fi
            if [[ "$item" == host_shell || "$item" == workspace_repo ]]; then
                local optional_status=0
                if [[ "$item" == host_shell ]]; then
                    "$SCRIPT_DIR/setup-shell.sh" || optional_status=$?
                else
                    log "WORKSPACE REPOSITORY"
                    { "$SCRIPT_DIR/setup-estate-commands.sh" && "$SCRIPT_DIR/setup-workspace-repo.sh"; } 2>&1 | tee -a "$LOG_FILE"
                    optional_status=${PIPESTATUS[0]}
                fi
                setup_propagate_cancel "$optional_status"
                if [[ "$optional_status" -eq 0 ]]; then ((success_count++)); else failed_components[$active_component]=true; ((fail_count++)); fi
                continue
            fi

            # Handle uninstallation
            if [[ "$action" == "uninstall" ]]; then
                echo -e "${BOLD}${CYAN}▶ Uninstalling: $desc${NC}"
                if uninstall_component "$item"; then
                    ((success_count++))
                else
                    failed_components[$active_component]=true; ((fail_count++))
                fi
                echo ""
                continue
            fi

            if [ "$is_installed" = true ]; then
                echo -e "${BOLD}${CYAN}▶ Checking: $desc${NC}"
                echo -e "  ${GREEN}✓ $desc is already installed${NC}"
                ((success_count++))
                echo ""
                continue
            fi

            # Handle installation
            if [ "$item" = "amnezia_vpn" ] || [ "$item" = "0dcloud_vpn" ]; then
                echo -e "${BOLD}${CYAN}▶ Configuring: $desc${NC}"
                if [ -x "$script_dir/setup-vpn.sh" ]; then
                    local vpn_target="amnezia"
                    local vpn_message="Installing/checking AmneziaVPN..."
                    if [ "$item" = "0dcloud_vpn" ]; then
                        vpn_target="0dcloud"
                        vpn_message="Installing/checking 0dcloud and patching TUN MTU..."
                    fi

                    echo -e "  ${YELLOW}${vpn_message}${NC}"
                    if "$script_dir/setup-vpn.sh" "$vpn_target"; then
                        echo -e "  ${GREEN}✓ $desc setup completed${NC}"
                        ((success_count++))
                    else
                        echo -e "  ${YELLOW}⚠ $desc setup needs attention${NC}"
                        echo -e "  ${DIM}See docs/vpn-setup.md for manual install steps${NC}"
                        failed_components[$active_component]=true; ((fail_count++))
                    fi
                else
                    echo -e "  ${RED}✗ setup-vpn.sh not found${NC}"
                    failed_components[$active_component]=true; ((fail_count++))
                fi
                echo ""
                continue
            fi

            if [ "$is_installed" = true ]; then
                echo -e "${BOLD}${CYAN}▶ Checking: $desc${NC}"
                echo -e "  ${GREEN}✓ $desc is already installed${NC}"
                ((success_count++))
            else
                echo -e "${BOLD}${CYAN}▶ Installing: $desc${NC}"

                case "$item" in
                    vscode)
                        # Check if running in WSL
                        if [ -n "$WSL_DISTRO_NAME" ] || grep -qi microsoft /proc/version 2>/dev/null; then
                            if [ -f "$script_dir/setup-windows-tools.sh" ]; then
                                if bash "$script_dir/setup-windows-tools.sh" vscode; then
                                    ((success_count++))
                                else
                                    failed_components[$active_component]=true; ((fail_count++))
                                fi
                            else
                                echo -e "  ${RED}✗ setup-windows-tools.sh not found${NC}"
                                failed_components[$active_component]=true; ((fail_count++))
                            fi
                        else
                            echo -e "  ${YELLOW}Installing Visual Studio Code for Linux...${NC}"
                            if command -v snap &> /dev/null; then
                                if sudo snap install code --classic; then
                                    echo -e "  ${GREEN}✓ VS Code installed via snap${NC}"
                                    ((success_count++))
                                else
                                    echo -e "  ${RED}✗ Failed to install VS Code${NC}"
                                    echo -e "  ${DIM}Visit: https://code.visualstudio.com/${NC}"
                                    failed_components[$active_component]=true; ((fail_count++))
                                fi
                            else
                                echo -e "  ${YELLOW}snap not available${NC}"
                                echo -e "  ${DIM}Manual install: https://code.visualstudio.com/${NC}"
                                failed_components[$active_component]=true; ((fail_count++))
                            fi
                        fi
                        ;;
                    warp)
                        # Check if running in WSL
                        if [ -n "$WSL_DISTRO_NAME" ] || grep -qi microsoft /proc/version 2>/dev/null; then
                            if [ -f "$script_dir/setup-windows-tools.sh" ]; then
                                if bash "$script_dir/setup-windows-tools.sh" warp; then
                                    ((success_count++))
                                else
                                    failed_components[$active_component]=true; ((fail_count++))
                                fi
                            else
                                echo -e "  ${RED}✗ setup-windows-tools.sh not found${NC}"
                                failed_components[$active_component]=true; ((fail_count++))
                            fi
                        else
                            echo -e "  ${YELLOW}Installing Warp Terminal for Linux...${NC}"
                            echo -e "  ${DIM}Visit: https://warp.dev${NC}"
                            echo -e "  ${YELLOW}Download and install .deb package from website${NC}"
                            failed_components[$active_component]=true; ((fail_count++))
                        fi
                        ;;
                    wave)
                        # Check if running in WSL
                        if [ -n "$WSL_DISTRO_NAME" ] || grep -qi microsoft /proc/version 2>/dev/null; then
                            if [ -f "$script_dir/setup-windows-tools.sh" ]; then
                                if bash "$script_dir/setup-windows-tools.sh" wave; then
                                    ((success_count++))
                                else
                                    failed_components[$active_component]=true; ((fail_count++))
                                fi
                            else
                                echo -e "  ${RED}✗ setup-windows-tools.sh not found${NC}"
                                failed_components[$active_component]=true; ((fail_count++))
                            fi
                        else
                            echo -e "  ${YELLOW}Installing Wave Terminal for Linux...${NC}"
                            echo -e "  ${DIM}Visit: https://waveterm.dev${NC}"
                            echo -e "  ${YELLOW}Download and install from website${NC}"
                            failed_components[$active_component]=true; ((fail_count++))
                        fi
                        ;;
                esac
            fi
            echo ""
        fi
    done

    # Verify selected applications against fresh installation evidence. A
    # successful installer exit alone must never report a missing tool as ready.
    refresh_component_statuses
    local verified_item final_status
    for verified_item in "${!component_action[@]}"; do
        [[ "${component_checked[$verified_item]}" == true ]] || continue
        workstation_service_key "$verified_item" && continue
        [[ "$verified_item" != host_shell && "$verified_item" != workspace_repo && "$verified_item" != ai_accounts && "$verified_item" != workbenches_account ]] || continue
        final_status="${component_status[$verified_item]}"
        if [[ "${component_action[$verified_item]}" == uninstall ]]; then
            [[ "$final_status" != installed && "$final_status" != 'needs creds' && "$final_status" != 'needs check' && "$final_status" != 'needs docker' && "$final_status" != 'image only' ]] && continue
        else
            [[ "$final_status" == installed || "$final_status" == 'needs creds' ]] && continue
        fi
        echo "Needs attention: ${component_description[$verified_item]} is $final_status after ${component_action[$verified_item]}."
        if [[ "${failed_components[$verified_item]:-}" != true ]]; then
            failed_components[$verified_item]=true
            ((fail_count++))
            [[ "$success_count" -le 0 ]] || ((success_count--))
        fi
    done

    if [[ "${component_checked[ai_accounts]}" == true ]]; then
        any_selected=true
        active_component=ai_accounts
        if [[ "$fail_count" -gt 0 ]]; then
            echo "AI accounts skipped because a selected change failed. Retry account setup after resolving it."
        elif configure_selected_accounts; then
            ((success_count++))
        else
            local account_status=$?
            setup_propagate_cancel "$account_status"
            echo "AI account setup needs attention; installed tools remain available."
            failed_components[$active_component]=true; ((fail_count++))
        fi
    else
        show_pending_authentication
    fi

    if [[ "${component_checked[workbenches_account]}" == true ]]; then
        any_selected=true
        if python3 "$SCRIPT_DIR/setup-workbenches-account.py"; then
            if [[ "$(python3 "$SCRIPT_DIR/setup-workbenches-account.py" --status)" == 'signed in' ]]; then ((success_count++)); fi
        else
            local workbenches_account_status=$?
            setup_propagate_cancel "$workbenches_account_status"
            echo 'Optional workBenches account sign-in failed; retry from Requirements.'
            ((fail_count++))
        fi
    fi

    # Summary
    echo ""
    echo -e "${BOLD}${BLUE}────────────────────────────────────────────────────────────────────────────${NC}"

    if [ "$any_selected" = false ]; then
        echo -e "${YELLOW}No items were selected.${NC}"
    else
        echo -e "${BOLD}Change Summary:${NC}"
        [ $success_count -gt 0 ] && echo -e "  ${GREEN}✓ Successful: $success_count${NC}"
        [ $fail_count -gt 0 ] && echo -e "  ${RED}✗ Failed: $fail_count${NC}"

        if [ $success_count -gt 0 ] && [ $fail_count -eq 0 ]; then
            echo -e "\n${GREEN}${BOLD}✓ All selected changes completed successfully!${NC}"
        elif [ $success_count -gt 0 ]; then
            echo -e "\n${YELLOW}⚠ Some selected changes need attention.${NC}"
        elif [ $fail_count -gt 0 ]; then
            echo -e "\n${RED}✗ Selected changes did not complete.${NC}"
        else
            echo 'No changes applied; optional account setup deferred.'
        fi
    fi

    echo ""

    [[ "$fail_count" -eq 0 ]]
}

configure_selected_accounts() {
    local providers="${WORKBENCHES_SELECTED_PROVIDERS:-}" item cli choice route_file route account_status
    local -a items_needing_creds=()
    for item in claude_cli codex_cli pi_cli opencode_cli copilot_cli antigravity_cli warp wave; do
        if [[ "${component_checked[$item]}" == true && "${component_action[$item]}" =~ ^(install|update)$ ]]; then
            items_needing_creds+=("${item%_cli}")
        fi
    done
    if [[ -z "$providers" ]]; then
        setup_read "AI assistant (codex/claude/pi/opencode/copilot/antigravity) [codex]" choice
        cli="${choice:-codex}"
        case "$cli" in
            codex) providers=openai ;;
            opencode) providers=omniroute ;;
            claude|pi|copilot|antigravity) providers="$cli" ;;
            *) echo "Unknown AI assistant; account setup stopped."; return 1 ;;
        esac
        items_needing_creds+=("$cli")
    fi
    export WORKBENCHES_SELECTED_PROVIDERS="$providers"
    route_file="$(mktemp)" || return 1
    WORKBENCHES_AUTH_ROUTE= WORKBENCHES_AUTH_ROUTE_FILE="$route_file" \
        "$SCRIPT_DIR/setup-ai-profiles.sh" --interactive
    account_status=$?
    route="$(cat "$route_file")"
    rm -f "$route_file"
    [[ "$account_status" -eq 0 ]] || return "$account_status"
    export WORKBENCHES_AUTH_ROUTE="${route%%:*}"
    if [[ "$route" == vault:* ]]; then
        export WORKBENCHES_VAULT_SERVICE="${route#vault:}"
    else
        unset WORKBENCHES_VAULT_SERVICE
    fi
    if [[ ",$providers," == *,claude,* ]] && [[ -x "$SCRIPT_DIR/setup-claude-workflows.sh" ]]; then
        "$SCRIPT_DIR/setup-claude-workflows.sh" || return "$?"
    fi
    if [[ "$WORKBENCHES_AUTH_ROUTE" == later ]]; then
        echo "Authentication pending. Select AI accounts to finish setup later."
        return 0
    fi
    if [ ${#items_needing_creds[@]} -gt 0 ]; then
        echo -e "${BOLD}${BLUE}────────────────────────────────────────────────────────────────────────────${NC}"
        echo -e "${BOLD}${YELLOW}Setting up Credentials${NC}"
        echo -e "${BOLD}${BLUE}────────────────────────────────────────────────────────────────────────────${NC}"
        echo ""


        for cli in "${items_needing_creds[@]}"; do
            case "$cli" in
                codex|claude|pi) python3 "$SCRIPT_DIR/profile_credentials.py" status "$cli" && continue ;;
                opencode) python3 "$SCRIPT_DIR/profile_credentials.py" status omniroute && continue ;;
            esac
            case "$cli" in
                codex)
                    echo -e "${CYAN}▶ Setting up Codex CLI authentication...${NC}"
                    echo ""

                    if guide_isolated_profile_logins \
                        "Codex" \
                        "${XDG_CONFIG_HOME:-$HOME/.config}/workbenches/openai-profiles.json" \
                        "pcodex"; then
                        continue
                    fi

                    # Check if already authenticated
                    if [ -f "$HOME/.codex/auth.json" ] || [ -n "$OPENAI_API_KEY" ]; then
                        echo -e "${GREEN}✓ Codex CLI already has credentials configured${NC}"
                        echo ""
                    else
                        echo -e "${YELLOW}Codex needs authentication to work.${NC}"
                        echo -e "${DIM}You can sign in with your ChatGPT account or use an API key.${NC}"
                        echo ""

                        while true; do
                            setup_read "Launch Codex authentication now? [Y/n]: " launch_codex
                            case $launch_codex in
                                [Yy]* | "" )
                                    echo ""
                                    echo -e "${YELLOW}Launching 'codex login'...${NC}"
                                    echo -e "${DIM}Follow the prompts to authenticate.${NC}"
                                    echo ""
                                    sleep 2

                                    # Launch codex login - handles authentication only
                                    if command -v codex &> /dev/null; then
                                        codex login
                                        setup_propagate_cancel "$?"
                                    fi
                                    echo ""
                                    break
                                    ;;
                                [Nn]* )
                                    echo ""
                                    echo -e "${YELLOW}Skipped. Run 'codex login' anytime to authenticate.${NC}"
                                    echo ""
                                    break
                                    ;;
                                * )
                                    echo "Please answer yes or no."
                                    ;;
                            esac
                        done
                    fi
                    ;;

                claude)
                    echo -e "${CYAN}▶ Setting up Claude CLI authentication...${NC}"
                    echo ""

                    if guide_isolated_profile_logins \
                        "Claude" \
                        "${XDG_CONFIG_HOME:-$HOME/.config}/workbenches/claude-profiles.json" \
                        "pclaude"; then
                        continue
                    fi

                    # Display important billing warning
                    echo -e "${BOLD}${YELLOW}⚠️  IMPORTANT BILLING INFORMATION${NC}"
                    echo -e "${BOLD}${BLUE}────────────────────────────────────────${NC}"
                    echo ""
                    echo -e "${YELLOW}Claude Code CLI offers TWO authentication options:${NC}"
                    echo ""
                    echo -e "${BOLD}${GREEN}1. Claude Pro/Max Subscription Login (OAuth)${NC}"
                    echo -e "   ${DIM}• Uses your Claude.ai web subscription${NC}"
                    echo -e "   ${DIM}• Included with Pro (\$20/mo) or Max (\$100/mo) plans${NC}"
                    echo -e "   ${DIM}• No additional API costs${NC}"
                    echo ""
                    echo -e "${BOLD}${CYAN}2. API Key Authentication${NC}"
                    echo -e "   ${DIM}• Uses Anthropic API credits${NC}"
                    echo -e "   ${DIM}• ${BOLD}${RED}BILLED SEPARATELY${NC}${DIM} from web subscription${NC}"
                    echo -e "   ${DIM}• Pay-per-use pricing (can be expensive)${NC}"
                    echo -e "   ${DIM}• Requires API key from console.anthropic.com${NC}"
                    echo ""
                    echo -e "${BOLD}${RED}⚠️  WARNING:${NC} ${YELLOW}API usage is NOT covered by your Claude subscription!${NC}"
                    echo -e "${DIM}Using an API key will incur separate charges based on usage.${NC}"
                    echo ""
                    echo -e "${BOLD}${BLUE}────────────────────────────────────────${NC}"
                    echo ""

                    if command -v claude &> /dev/null; then
                        # Check if already has credentials
                        if [ -f "$HOME/.claude/config.json" ] || [ -n "$ANTHROPIC_API_KEY" ]; then
                            echo -e "${GREEN}✓ Claude CLI already has credentials configured${NC}"
                            echo ""
                        else
                            echo -e "${YELLOW}To authenticate Claude CLI:${NC}"
                            echo -e "  ${BOLD}${GREEN}Recommended:${NC} Run ${CYAN}claude${NC} (uses Pro/Max subscription)${NC}"
                            echo -e "  ${DIM}Alternative: Set ANTHROPIC_API_KEY (separate billing)${NC}"
                            echo ""

                            while true; do
                                setup_read "Launch Claude CLI authentication now? [Y/n]: " launch_claude
                                case $launch_claude in
                                    [Yy]* | "" )
                                        echo ""
                                        echo -e "${YELLOW}Launching 'claude'...${NC}"
                                        echo -e "${DIM}Follow the prompts to choose your authentication method.${NC}"
                                        echo ""
                                        sleep 2

                                        # Launch claude - will prompt for authentication
                                        claude
                                        setup_propagate_cancel "$?"
                                        echo ""
                                        break
                                        ;;
                                    [Nn]* )
                                        echo ""
                                        echo -e "${YELLOW}Skipped. Run 'claude' anytime to authenticate.${NC}"
                                        echo ""
                                        break
                                        ;;
                                    * )
                                        echo "Please answer yes or no."
                                        ;;
                                esac
                            done
                        fi
                    fi
                    ;;

                antigravity)
                    echo -e "${CYAN}▶ Setting up Antigravity CLI authentication...${NC}"
                    echo ""

                    echo -e "${BOLD}${GREEN}✨ Antigravity CLI${NC}"
                    echo -e "${BOLD}${BLUE}────────────────────────────────────────${NC}"
                    echo ""
                    echo -e "${YELLOW}Antigravity CLI uses the 'agy' command.${NC}"
                    echo -e "  ${DIM}• Run agy to start the terminal UI${NC}"
                    echo -e "  ${DIM}• Sign in with your Google account or Google Cloud project when prompted${NC}"
                    echo -e "  ${DIM}• The CLI self-updates during regular runs${NC}"
                    echo ""
                    echo -e "${BOLD}${BLUE}────────────────────────────────────────${NC}"
                    echo ""

                    if command -v agy &> /dev/null; then
                        echo -e "${YELLOW}To authenticate Antigravity CLI:${NC}"
                        echo -e "  ${BOLD}${GREEN}Recommended:${NC} Run ${CYAN}agy${NC} and follow the sign-in prompts${NC}"
                        echo ""

                        while true; do
                            setup_read "Launch Antigravity CLI authentication now? [Y/n]: " launch_antigravity
                            case $launch_antigravity in
                                [Yy]* | "" )
                                    echo ""
                                    echo -e "${YELLOW}Launching 'agy'...${NC}"
                                    echo -e "${DIM}Follow the prompts to authenticate.${NC}"
                                    echo ""
                                    sleep 2

                                    agy
                                    echo ""
                                    break
                                    ;;
                                [Nn]* )
                                    echo ""
                                    echo -e "${YELLOW}Skipped. Run 'agy' anytime to authenticate.${NC}"
                                    echo ""
                                    break
                                    ;;
                                * )
                                    echo "Please answer yes or no."
                                    ;;
                            esac
                        done
                    else
                        echo -e "${YELLOW}Antigravity CLI not found. Install it first.${NC}"
                    fi
                    ;;

                opencode)
                    echo -e "${CYAN}▶ Setting up OpenCode provider authentication...${NC}"
                    if [[ "$WORKBENCHES_AUTH_ROUTE" == vault && "${WORKBENCHES_VAULT_SERVICE:-}" == azure ]] && "$SCRIPT_DIR/restore-opencode-omniroute-from-kv.sh"; then
                        echo -e "${GREEN}✓ Restored Opensoft OmniRoute authentication from approved durable storage${NC}"
                    else
                        echo -e "${YELLOW}OpenCode sign-in is needed.${NC}"
                        setup_read "Launch 'opencode auth login' now? [Y/n]: " launch_opencode
                        if [[ ! $launch_opencode =~ ^[Nn] ]]; then
                            opencode auth login
                            setup_propagate_cancel "$?"
                        else
                            echo -e "${YELLOW}Skipped. Run 'opencode auth login' anytime.${NC}"
                        fi
                    fi
                    echo ""
                    ;;

                pi)
                    echo -e "${CYAN}▶ Setting up Pi Coding Agent authentication...${NC}"
                    echo -e "${DIM}Pi credentials are isolated by canonical profile through ppi.${NC}"
                    setup_read "Launch a Pi profile login now? [Y/n]: " launch_pi
                    if [[ ! $launch_pi =~ ^[Nn] ]]; then
                        setup_read "Pi profile name or alias: " pi_profile
                        echo -e "${YELLOW}Run /login, choose a provider, verify the matching identity, then exit Pi.${NC}"
                        if command -v ppi >/dev/null 2>&1; then
                            ppi login "$pi_profile"
                            setup_propagate_cancel "$?"
                        elif [[ -x "$HOME/.local/bin/ppi" ]]; then
                            "$HOME/.local/bin/ppi" login "$pi_profile"
                            setup_propagate_cancel "$?"
                        else
                            echo -e "${YELLOW}No isolated Pi profile launcher is configured; using the standard Pi login flow.${NC}"
                            pi_command="$(command -v pi || true)"
                            [[ -n "$pi_command" ]] || pi_command="$HOME/.npm-global/bin/pi"
                            [[ -x "$pi_command" ]] || { echo -e "${RED}Pi CLI is not available.${NC}"; continue; }
                            "$pi_command"
                        fi
                    else
                        echo -e "${YELLOW}Skipped. Run 'ppi login PROFILE' anytime.${NC}"
                    fi
                    echo ""
                    ;;

                warp)
                    echo -e "${CYAN}▶ Setting up Warp account authentication...${NC}"
                    echo -e "${DIM}Warp login is optional, but required for AI and collaboration features.${NC}"
                    setup_read "Open the Warp login page now? [Y/n]: " launch_warp
                    if [[ ! $launch_warp =~ ^[Nn] ]]; then
                        if is_wsl_windows; then
                            powershell.exe -NoProfile -Command 'Start-Process "https://app.warp.dev/login"' >/dev/null 2>&1 || true
                        elif command -v xdg-open &>/dev/null; then
                            xdg-open https://app.warp.dev/login >/dev/null 2>&1 || true
                        fi
                        echo -e "${YELLOW}Complete login in Warp using the selected personal or work identity.${NC}"
                    fi
                    echo ""
                    ;;

                wave)
                    echo -e "${CYAN}▶ Setting up Wave AI credentials...${NC}"
                    echo -e "${DIM}Wave itself requires no account login. Provider keys belong in Wave's encrypted secrets store.${NC}"
                    setup_read "Open Wave's secrets UI now? [Y/n]: " launch_wave_secrets
                    if [[ ! $launch_wave_secrets =~ ^[Nn] ]]; then
                        if command -v wsh &>/dev/null; then
                            wsh secret ui || true
                        else
                            echo -e "${YELLOW}Open Wave, then choose Settings > Secrets.${NC}"
                        fi
                    fi
                    echo ""
                    ;;

                copilot)
                    echo -e "${CYAN}▶ Setting up GitHub Copilot CLI authentication...${NC}"
                    echo ""
                    if command -v copilot &> /dev/null; then
                        echo -e "${YELLOW}Run the following to authenticate:${NC}"
                        echo -e "  ${CYAN}copilot auth login${NC}"
                    fi
                    echo ""
                    ;;
            esac
        done

        echo -e "${BOLD}${BLUE}────────────────────────────────────────────────────────────────────────────${NC}"
    fi

    return 0
}

show_pending_authentication() {
    local item provider
    local -a pending=()
    for item in claude_cli codex_cli pi_cli opencode_cli; do
        [[ "${component_checked[$item]}" == true && "${component_action[$item]}" =~ ^(install|update)$ ]] || continue
        provider="${item%_cli}"
        [[ "$provider" == opencode ]] && provider=omniroute
        if ! python3 "$SCRIPT_DIR/profile_credentials.py" status "$provider"; then
            pending+=("${component_description[$item]}")
        fi
    done
    if [[ ${#pending[@]} -gt 0 ]]; then
        printf 'Authentication pending: %s. Select AI accounts to configure later.\n' "$(IFS=,; echo "${pending[*]}")"
    fi
}

guide_isolated_profile_logins() {
    local provider="$1" manifest="$2" launcher="$3"
    local profile_count name email answer

    [[ -f "$manifest" ]] || return 1
    command -v jq >/dev/null 2>&1 || return 1
    profile_count="$(jq '.profiles | length' "$manifest" 2>/dev/null)" || return 1
    [[ "$profile_count" =~ ^[0-9]+$ && "$profile_count" -gt 0 ]] || return 1
    python3 "$SCRIPT_DIR/profile_credentials.py" ready "$provider" && return 0

    echo -e "${GREEN}✓ Isolated ${provider} profiles are configured${NC}"
    jq -r '.profiles[] | "  \(.name)  <\(.email)>"' "$manifest"
    echo -e "${DIM}Each profile has its own credential home; the default login is preserved separately.${NC}"
    echo ""

    if ! command -v "$launcher" >/dev/null 2>&1 && [[ -x "$HOME/.local/bin/$launcher" ]]; then
        launcher="$HOME/.local/bin/$launcher"
    fi
    if ! command -v "$launcher" >/dev/null 2>&1; then
        echo -e "${YELLOW}Profile launcher '${launcher}' is not on PATH yet. Open a new shell, then run '${launcher} login <profile>'.${NC}"
        echo ""
        return 0
    fi

    setup_read "Walk through login for these ${provider} profiles now? [y/N]: " answer
    [[ "$answer" =~ ^[Yy] ]] || {
        echo -e "${YELLOW}Skipped. Use '${launcher} login <profile>' when ready.${NC}"
        echo ""
        return 0
    }

    while IFS=$'\t' read -r -u 3 name email; do
        python3 "$SCRIPT_DIR/profile_credentials.py" profile "$provider" "$name" && continue
        setup_read "Login ${name} (${email}) now? [y/N]: " answer
        if [[ "$answer" =~ ^[Yy] ]]; then
            "$launcher" login "$name"
            setup_propagate_cancel "$?"
            echo ""
        fi
    done 3< <(jq -r '.profiles[] | [.name, .email] | @tsv' "$manifest")
    return 0
}

# Install Node.js using recommended method
install_nodejs() {
    echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${BLUE}  Installing Node.js${NC}"
    echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo ""

    # Detect OS and install Node.js
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        OS=$(uname -s)
    fi

    case "$OS" in
        ubuntu|debian|pop)
            echo -e "${CYAN}Installing Node.js via NodeSource repository...${NC}"
            echo ""
            # Install Node.js 24.x LTS
            if curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash - && \
               sudo apt-get install -y nodejs; then
                echo ""
                echo -e "${GREEN}✓ Node.js installed successfully!${NC}"
                local installed_version=$(node --version 2>/dev/null)
                echo -e "  Version: ${installed_version}"
                return 0
            else
                echo -e "${RED}✗ Failed to install Node.js${NC}"
                return 1
            fi
            ;;
        fedora|rhel|centos)
            echo -e "${CYAN}Installing Node.js via NodeSource repository...${NC}"
            echo ""
            if curl -fsSL https://rpm.nodesource.com/setup_24.x | sudo bash - && \
               sudo yum install -y nodejs; then
                echo ""
                echo -e "${GREEN}✓ Node.js installed successfully!${NC}"
                return 0
            else
                echo -e "${RED}✗ Failed to install Node.js${NC}"
                return 1
            fi
            ;;
        arch|endeavouros|manjaro|omarchy)
            sudo pacman -S --needed nodejs npm
            return $?
            ;;
        alpine)
            echo -e "${CYAN}Installing Node.js via apk...${NC}"
            if sudo apk add nodejs npm; then
                echo -e "${GREEN}✓ Node.js installed successfully!${NC}"
                return 0
            else
                echo -e "${RED}✗ Failed to install Node.js${NC}"
                return 1
            fi
            ;;
        Darwin|darwin|macos)
            echo -e "${CYAN}Installing Node.js via Homebrew...${NC}"
            if command -v brew &> /dev/null; then
                if brew install node; then
                    echo -e "${GREEN}✓ Node.js installed successfully!${NC}"
                    return 0
                else
                    echo -e "${RED}✗ Failed to install Node.js${NC}"
                    return 1
                fi
            else
                echo -e "${RED}Homebrew not found.${NC}"
                echo -e "Install Homebrew first: ${BLUE}https://brew.sh${NC}"
                return 1
            fi
            ;;
        *)
            echo -e "${YELLOW}Unknown OS: $OS${NC}"
            echo -e "Please install Node.js manually from: ${BLUE}https://nodejs.org/${NC}"
            return 1
            ;;
    esac
}

# Update failures must preserve the failure status and the installed CLI.
# After moving from a system prefix, install into the new user prefix instead
# of reporting an empty npm update there as an update of the system package.
npm_update_tool() {
    local package="$1" label="$2" output status
    if [[ "${WORKBENCHES_NPM_PREFIX_CHANGED:-}" == 1 ]]; then
        output="$(npm install -g "$package" 2>&1)"
    else
        output="$(npm update -g "$package" 2>&1)"
    fi
    status=$?
    setup_propagate_cancel "$status"
    if [[ "$status" != 0 ]]; then
        log "ERROR: $label npm update failed (exit $status)"
        echo -e "  ${RED}✗ $label update failed (exit $status). Retry with: npm update -g $package${NC}"
        return "$status"
    fi
    if [[ "$output" == *"up to date"* || "$output" == *unchanged* ]]; then
        echo -e "  ${GREEN}✓ $label is already up to date${NC}"
    else
        echo -e "  ${GREEN}✓ $label updated${NC}"
    fi
}

# Node is only needed for selected npm-based installs/updates.
check_and_install_dependencies() {
    ensure_setup_dependencies || exit "$?"
}

ensure_selected_dependencies() {
    local item needs_node=false choice major minor minimum_major=20 minimum_minor=19
    for item in codex_cli copilot_cli pi_cli openspec "${!setup_harness_node_dependencies[@]}"; do
        if [[ "${component_checked[$item]}" == true && "${component_action[$item]}" =~ ^(install|update)$ ]]; then needs_node=true; fi
    done
    for item in "${!setup_harness_node_dependencies[@]}"; do
        if [[ "${component_checked[$item]}" == true && "${component_action[$item]}" =~ ^(install|update)$ ]]; then minimum_major=24; minimum_minor=0; fi
    done
    [[ "$needs_node" == true ]] || return 0
    IFS=. read -r major minor _ <<< "$(node --version 2>/dev/null)"
    major="${major#v}"
    if ! { [[ "$major" =~ ^[0-9]+$ && "$minor" =~ ^[0-9]+$ ]] && (( major > minimum_major || (major == minimum_major && minor >= minimum_minor) )) && command -v npm >/dev/null 2>&1; }; then
        echo "The selected tools require Node.js ${minimum_major}.${minimum_minor}+ and npm."
        setup_read "Install/update Node.js now? [y/N]" choice
        [[ "${choice,,}" == y || "${choice,,}" == yes ]] || exit 130
        install_nodejs || { setup_propagate_cancel "$?"; exit 1; }
    fi
    IFS=. read -r major minor _ <<< "$(node --version 2>/dev/null)"; major="${major#v}"
    [[ "$major" =~ ^[0-9]+$ && "$minor" =~ ^[0-9]+$ ]] && (( major > minimum_major || (major == minimum_major && minor >= minimum_minor) )) && command -v npm >/dev/null 2>&1 || exit 1
    # The root launcher exports the chosen location to all child installers.
    if [[ "${1:-}" != --dependencies-plan ]]; then
        ensure_npm_install_location || exit "$?"
        persist_npm_user_path
    fi
}

save_selection() {
    workstation_save_selection "$selection_file"
}

load_selection() {
    local item action rows
    rows="$(python3 "$SCRIPT_DIR/setup_selection.py" rows "$selection_file")" || exit "$?"
    for item in "${!component_checked[@]}"; do component_checked[$item]=false; done
    while IFS=$'\t' read -r item action; do
        [[ -n "$item" ]] || continue
        component_checked[$item]=true
        component_action[$item]="$action"
    done <<< "$rows"
}

# Main function
main() {
    log "Main function started"
    local mode=interactive selection_file=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --select-only|--apply-plan|--dependencies-plan) mode="$1"; selection_file="$2"; shift 2 ;;
            *) echo "Unknown setup option: $1" >&2; exit 2 ;;
        esac
    done

    ensure_setup_platform || return "$?"
    if [[ ( "$mode" == interactive || "$mode" == --select-only ) && -t 0 && -t 1 ]]; then
        status_async_ui=true
        init_components --loading
        CURRENT_SECTION=3
        setup_os_label="$(workbenches_setup_os)"
        initialize_loading_statuses
        status_checks_running=true
        # Draw before Docker, tool activation, jq, or Python can run.
        draw_ui
        trap 'stop_status_loader; printf "%b" "$SHOW_CURSOR"' EXIT
        start_status_loader
    else
        ensure_workstation_requirements || return "$?"
        init_components
        if [[ "$mode" == interactive || "$mode" == --select-only ]]; then CURRENT_SECTION=3; fi
        if [[ "$mode" == interactive || "$mode" == --select-only ]]; then setup_load_bench_metadata_sync; fi
        if [[ "$mode" != --dependencies-plan ]]; then load_statuses; fi
    fi
    if [[ "$mode" == --apply-plan || "$mode" == --dependencies-plan ]]; then
        load_selection
        workstation_plan_from_ui
        if [[ "$mode" == --apply-plan && "${WORKBENCHES_DEFER_WORKSTATION_REMOVE:-}" != 1 ]]; then
            workstation_plan_prepare || return "$?"
        fi
        if [[ "$mode" == --apply-plan ]] && workbenches_release_checkout; then
            export WORKBENCHES_FROZEN=1
            python3 "$SCRIPT_DIR/release-workbenches.py" prepare --selection "$selection_file" || return "$?"
        fi
        ensure_selected_dependencies "$mode"
        if [[ "$mode" == --apply-plan ]]; then
            [[ "$workstation_plan_only" == true ]] || process_selections || return "$?"
            if [[ "${WORKBENCHES_DEFER_WORKSTATION_REMOVE:-}" != 1 ]]; then workstation_plan_finish || return "$?"; fi
        fi
        return
    fi

    # Main loop
    log "Entering main UI loop"

    # The asynchronous path already painted before starting discovery.
    [[ "$status_async_ui" == true ]] || draw_ui

    # Store initial state
    local prev_sel=$current_selection
    local prev_sect=$CURRENT_SECTION
    setup_update_ui_signature
    local prev_state="$setup_ui_signature"

    while true; do
        handle_input
        local result=$?
        poll_status_loader

        # Render changed state; draw_ui commits only the lines that differ.
        setup_update_ui_signature
        local current_state="$setup_ui_signature"

        # Check if anything changed (selection or checkboxes)
        if [[ "$status_ui_dirty" == true || "$setup_ui_size_stale" == true ]] || [ $current_selection -ne $prev_sel ] || [ $CURRENT_SECTION -ne $prev_sect ] || [ "$current_state" != "$prev_state" ]; then
            draw_ui
            status_ui_dirty=false
            prev_sel=$current_selection
            prev_sect=$CURRENT_SECTION
            prev_state="$current_state"
        fi

        if [ $result -eq 1 ]; then
            # Enter pressed - process selections
            log "User pressed Enter - processing selections"
            if [[ "$mode" == --select-only ]]; then
                save_selection || exit "$?"
            else
                stop_status_loader
                workstation_plan_from_ui
                workstation_plan_prepare || return "$?"
                if [[ "$workstation_plan_only" != true ]]; then
                    ensure_selected_dependencies || return "$?"
                    process_selections || return "$?"
                fi
                workstation_plan_finish || return "$?"
            fi
            break
        elif [ $result -eq 2 ]; then
            # Quit pressed
            log "User pressed Quit - exiting"
            echo -e "${SHOW_CURSOR}"
            clear
            echo -e "${YELLOW}Setup cancelled.${NC}"
            log "=== Setup script cancelled ==="
            exit 130
        fi
    done

    stop_status_loader
    echo -e "${SHOW_CURSOR}"
    log "=== Setup script completed ==="
}

# Cleanup on exit
trap 'echo -e "${SHOW_CURSOR}"; exit 130' INT
trap 'echo -e "${SHOW_CURSOR}"; exit 143' TERM
trap 'setup_ui_size_stale=true' WINCH

# Run if executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
