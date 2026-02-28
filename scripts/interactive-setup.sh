#!/usr/bin/env bash

# Interactive Setup UI for workBenches
# Provides keyboard-driven selection interface for installing components

# Setup logging
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/../logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/setup-$(date +%Y%m%d-%H%M%S).log"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# Log script start
log "=== Setup script started ==="
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
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color
BOLD='\033[1m'
DIM='\033[2m'

# Spinner for long operations
show_spinner() {
    local pid=$1
    local message="$2"
    local timeout=${3:-300}  # Default 5 minute timeout
    local spinner="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    local i=0
    local elapsed=0
    
    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) % 10 ))
        printf "\r  ${YELLOW}${spinner:$i:1}${NC} ${message}"
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
declare -A component_action  # "install" or "uninstall"
declare -a component_order

# Current selection
current_selection=0
current_block=0

# Three main sections: 0=Benches, 1=AI Assistants, 2=Tools
CURRENT_SECTION=0  # 0=Benches, 1=AI Assistants, 2=Tools
declare -a bench_items
declare -a ai_items
declare -a tool_items
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
    
    if [ -f "$config_file" ]; then
        # Get bench names from config
        while IFS= read -r bench_name; do
            bench_items+=("$bench_name")
            component_checked["bench_$bench_name"]=false
            component_description["bench_$bench_name"]="$bench_name"
        done < <(jq -r '.benches | keys[]' "$config_file" 2>/dev/null)
    fi
    
    # If no benches found, add some defaults
    if [ ${#bench_items[@]} -eq 0 ]; then
        bench_items=("flutterBench" "javaBench" "dotNetBench" "pythonBench")
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
        "gemini_cli"
        "opencode_cli"
        "separator1"
        "spec_kit"
        "openspec"
    )
    
    # Initialize AI items
    component_checked["claude_cli"]=false
    component_description["claude_cli"]="Claude Code CLI"
    
    component_checked["copilot_cli"]=false
    component_description["copilot_cli"]="GitHub Copilot CLI"
    
    component_checked["codex_cli"]=false
    component_description["codex_cli"]="Codex CLI"
    
    component_checked["gemini_cli"]=false
    component_description["gemini_cli"]="Gemini CLI"
    
    component_checked["opencode_cli"]=false
    component_description["opencode_cli"]="OpenCode CLI"
    
    component_checked["spec_kit"]=false
    component_description["spec_kit"]="spec-kit"
    
    component_checked["openspec"]=false
    component_description["openspec"]="OpenSpec"
    
    # Tools
    tool_items=(
        "vscode"
        "warp"
        "wave"
    )
    
    # Initialize tool items
    component_checked["vscode"]=false
    component_description["vscode"]="Visual Studio Code"
    
    component_checked["warp"]=false
    component_description["warp"]="Warp Terminal"
    
    component_checked["wave"]=false
    component_description["wave"]="Wave Terminal"
}

# Check current installation status
check_component_status() {
    local component="$1"
    log "Checking status: $component"
    
    case "$component" in
        claude_cli)
            if command -v claude &> /dev/null; then
                # Check if credentials exist
                if [ -n "$ANTHROPIC_API_KEY" ] || [ -f "$HOME/.claude.json" ]; then
                    echo "installed"
                else
                    echo "needs creds"
                fi
            else
                echo "not installed"
            fi
            ;;
        copilot_cli)
            if command -v copilot &> /dev/null; then
                echo "installed"
            else
                echo "not installed"
            fi
            ;;
        codex_cli)
            if command -v codex &> /dev/null; then
                # Check if authenticated (auth.json or API key)
                if [ -f "$HOME/.codex/auth.json" ] || [ -n "$OPENAI_API_KEY" ]; then
                    echo "installed"
                else
                    echo "needs creds"
                fi
            else
                echo "not installed"
            fi
            ;;
        gemini_cli)
            if command -v gemini &> /dev/null; then
                echo "installed"
            else
                echo "not installed"
            fi
            ;;
        opencode_cli)
            if command -v opencode &> /dev/null; then
                echo "installed"
            else
                echo "not installed"
            fi
            ;;
        spec_kit)
            command -v specify &> /dev/null && echo "installed" || echo "not installed"
            ;;
        openspec)
            command -v openspec &> /dev/null && echo "installed" || echo "not installed"
            ;;
        vscode)
            # Check for VS Code - on WSL, check for Windows version
            if [ -n "$WSL_DISTRO_NAME" ] || grep -qi microsoft /proc/version 2>/dev/null; then
                # WSL: Check for Windows VS Code and WSL extension
                if command -v code &> /dev/null || [ -f "/mnt/c/Program Files/Microsoft VS Code/Code.exe" ] || [ -f "/mnt/c/Users/*/AppData/Local/Programs/Microsoft VS Code/Code.exe" ]; then
                    # VS Code is installed, check for WSL extension by checking vscode-server directory
                    if [ -d "$HOME/.vscode-server" ]; then
                        # Check if Dev Containers extension is installed on Windows side
                        local windows_user=$(powershell.exe -c "[Environment]::UserName" 2>/dev/null | tr -d '\r')
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
                command -v code &> /dev/null && echo "installed" || echo "not installed"
            fi
            ;;
        warp)
            # Check for warp - on WSL, check for Windows version
            if [ -n "$WSL_DISTRO_NAME" ] || grep -qi microsoft /proc/version 2>/dev/null; then
                # WSL: Check for Windows Warp
                if [ -f "/mnt/c/Program Files/Warp/Warp.exe" ] || [ -f "/mnt/c/Users/"*/AppData/Local/Programs/Warp/Warp.exe 2>/dev/null ]; then
                    echo "installed"
                else
                    echo "not installed"
                fi
            else
                # Native Linux: Check for Linux Warp
                if command -v warp-terminal &> /dev/null || [ -d "$HOME/.warp" ] || [ -d "/usr/share/warp-terminal" ]; then
                    echo "installed"
                else
                    echo "not installed"
                fi
            fi
            ;;
        wave)
            # Check for wave terminal - on WSL, check for Windows version
            if [ -n "$WSL_DISTRO_NAME" ] || grep -qi microsoft /proc/version 2>/dev/null; then
                # WSL: Check for Windows Wave in common locations
                if [ -f "/mnt/c/Program Files/Wave/Wave.exe" ] || \
                   find /mnt/c/Users/*/AppData/Local/Programs/waveterm/Wave.exe -type f 2>/dev/null | grep -q .; then
                    echo "installed"
                else
                    echo "not installed"
                fi
            else
                # Native Linux: Check for Linux Wave
                if command -v wave &> /dev/null || [ -d "$HOME/.waveterm" ]; then
                    echo "installed"
                else
                    echo "not installed"
                fi
            fi
            ;;
        bench_*)
            # Check if bench directory exists, has correct git remote, and is set up
            local bench_name="${component#bench_}"
            local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
            local config_file="$script_dir/../config/bench-config.json"
            
            # Get the path and URL from config
            local bench_path=$(jq -r ".benches.${bench_name}.path // \"\"" "$config_file" 2>/dev/null)
            local bench_url=$(jq -r ".benches.${bench_name}.url // \"\"" "$config_file" 2>/dev/null)
            
            if [ -z "$bench_path" ] || [ "$bench_path" = "null" ]; then
                # Fallback: check root directory
                bench_path="$bench_name"
            fi
            
            local full_path="$script_dir/../$bench_path"
            
            # Check if directory exists
            if [ -d "$full_path" ]; then
                # Check if it has a git remote
                if [ -d "$full_path/.git" ]; then
                    # Verify it has the correct remote (if URL is configured)
                    if [ -n "$bench_url" ] && [ "$bench_url" != "null" ]; then
                        local current_remote=$(cd "$full_path" && git remote get-url origin 2>/dev/null)
                        if [ "$current_remote" = "$bench_url" ]; then
                            # Bench is installed with correct remote, check if set up
                            # Look for new-<bench>-project command
                            local expected_command="new-${bench_name}-project"
                            # Convert camelCase to kebab-case for command name
                            expected_command=$(echo "$expected_command" | sed 's/\([A-Z]\)/-\L\1/g' | sed 's/^-//')
                            
                            if command -v "$expected_command" &> /dev/null; then
                                echo "installed"  # Fully set up
                            else
                                echo "needs creds"  # Installed but not set up (using needs creds for warning state)
                            fi
                        else
                            echo "not installed"  # Wrong remote
                        fi
                    else
                        # No URL configured, just check if it's a git repo
                        echo "installed"
                    fi
                else
                    echo "not installed"  # Directory exists but not a git repo
                fi
            else
                echo "not installed"
            fi
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Load all component statuses
load_statuses() {
    # Load statuses for benches
    for bench in "${bench_items[@]}"; do
        local key="bench_$bench"
        local status=$(check_component_status "$key")
        component_status["$key"]="$status"
        
        # Auto-check if installed or needs creds
        if [[ "$status" == "installed" || "$status" == "needs creds" ]]; then
            component_checked["$key"]=true
        fi
    done
    
    # Load statuses for AI items
    for item in "${ai_items[@]}"; do
        if [[ "$item" == separator* ]]; then
            continue
        fi
        local status=$(check_component_status "$item")
        component_status["$item"]="$status"
        
        # Auto-check if installed or needs creds
        if [[ "$status" == "installed" || "$status" == "needs creds" ]]; then
            component_checked["$item"]=true
        fi
    done
    
    # Load statuses for tool items
    for item in "${tool_items[@]}"; do
        local status=$(check_component_status "$item")
        component_status["$item"]="$status"
        
        # Auto-check if installed
        if [[ "$status" == "installed" ]]; then
            component_checked["$item"]=true
        fi
    done
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
    if [[ "$status" == "installed" || "$status" == "configured" ]]; then
        status_color="$GREEN"
        status_symbol="✓"
    elif [[ "$status" == "needs creds" ]]; then
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

# Get current checked state as string (for change detection)
get_checked_state() {
    local state=""
    for bench in "${bench_items[@]}"; do
        state+="${component_checked[bench_$bench]},"
    done
    for item in "${ai_items[@]}"; do
        [[ "$item" != separator* ]] && state+="${component_checked[$item]},"
    done
    for item in "${tool_items[@]}"; do
        state+="${component_checked[$item]},"
    done
    echo "$state"
}

# Update only the section headers line
update_section_headers() {
    # Position cursor at header line (banner=7, header box=3, nav=2 = line 13)
    tput cup 13 0
    tput el  # Clear to end of line
    
    local benches_active=$( [ $CURRENT_SECTION -eq 0 ] && echo "true" || echo "false" )
    local ai_active=$( [ $CURRENT_SECTION -eq 1 ] && echo "true" || echo "false" )
    local tools_active=$( [ $CURRENT_SECTION -eq 2 ] && echo "true" || echo "false" )
    
    local bench_header="${DIM}┌────── BENCHES ────────┐${NC}"
    local ai_header="${DIM}┌─── AI ASSISTANTS ─────┐${NC}"
    local tools_header="${DIM}┌─────── TOOLS ─────────┐${NC}"
    
    [ "$benches_active" = "true" ] && bench_header="${BOLD}${YELLOW}┌────── BENCHES ────────┐${NC}"
    [ "$ai_active" = "true" ] && ai_header="${BOLD}${YELLOW}┌─── AI ASSISTANTS ─────┐${NC}"
    [ "$tools_active" = "true" ] && tools_header="${BOLD}${YELLOW}┌─────── TOOLS ─────────┐${NC}"
    
    echo -e "${bench_header}      ${ai_header}      ${tools_header}"
}

# Redraw just the three sections content (not the whole UI)
draw_three_sections_only() {
    # Position cursor at first content line after header (line 14)
    tput cup 14 0
    
    draw_three_sections
}

# Update only the lines affected by cursor movement
update_selection_lines() {
    local old_sel=$1
    local old_sect=$2
    local new_sel=$3
    local new_sect=$4
    
    # Calculate base line offset (banner=7, header=4, nav=2 = 13 lines)
    local base_line=14
    
    # If section changed, just update headers and cursor lines
    if [ $old_sect -ne $new_sect ]; then
        update_section_headers
        # Need to redraw the old line in old section and new line in new section
        # For simplicity when switching sections, just do full redraw
        # Could optimize further but sections changes are less frequent
        draw_three_sections_only
        return
    fi
    
    # For vertical movement within same section, redraw both affected rows
    # Since we have 3 columns, we need to redraw the entire row
    
    # Redraw old row
    if [ $old_sel -ge 0 ]; then
        tput cup $((base_line + old_sel)) 0
        tput el  # Clear to end of line
        echo -ne "$(draw_row $old_sel)"
    fi
    
    # Redraw new row
    if [ $new_sel -ge 0 ]; then
        tput cup $((base_line + new_sel)) 0
        tput el  # Clear to end of line
        echo -ne "$(draw_row $new_sel)"
    fi
    
    # Return cursor to invisible position
    tput cup $((base_line + new_sel + 5)) 0
}

# Draw a single item line for a section
draw_item_for_section() {
    local sect=$1
    local idx=$2
    local selected=$3
    
    local key=""
    if [ $sect -eq 0 ]; then
        local bench="${bench_items[$idx]}"
        key="bench_$bench"
    elif [ $sect -eq 1 ]; then
        local item="${ai_items[$idx]}"
        [[ "$item" == separator* ]] && echo "" && return
        key="$item"
    else
        local item="${tool_items[$idx]}"
        key="$item"
    fi
    
    draw_item_compact "$key" "$selected" "true"
}

# Draw a complete row (all 3 columns) for a given index
draw_row() {
    local i=$1
    
    local benches_active=$( [ $CURRENT_SECTION -eq 0 ] && echo "true" || echo "false" )
    local ai_active=$( [ $CURRENT_SECTION -eq 1 ] && echo "true" || echo "false" )
    local tools_active=$( [ $CURRENT_SECTION -eq 2 ] && echo "true" || echo "false" )
    
    # Left column (Benches) - 24 chars wide
    local left_content="                        "
    if [ $i -lt ${#bench_items[@]} ]; then
        local bench="${bench_items[$i]}"
        local is_selected=$( [ $CURRENT_SECTION -eq 0 ] && [ $i -eq $current_selection ] && echo "true" || echo "false" )
        left_content=$(draw_item_compact "bench_$bench" "$is_selected" "$benches_active")
    fi
    
    # Middle column (AI) - 24 chars wide
    local middle_content="                        "
    if [ $i -lt ${#ai_items[@]} ]; then
        local item="${ai_items[$i]}"
        if [[ "$item" == separator* ]]; then
            middle_content="${DIM}────────────────────────${NC}"
        else
            local is_selected=$( [ $CURRENT_SECTION -eq 1 ] && [ $i -eq $current_selection ] && echo "true" || echo "false" )
            middle_content=$(draw_item_compact "$item" "$is_selected" "$ai_active")
        fi
    fi
    
    # Right column (Tools) - 24 chars wide
    local right_content="                        "
    if [ $i -lt ${#tool_items[@]} ]; then
        local item="${tool_items[$i]}"
        local is_selected=$( [ $CURRENT_SECTION -eq 2 ] && [ $i -eq $current_selection ] && echo "true" || echo "false" )
        right_content=$(draw_item_compact "$item" "$is_selected" "$tools_active")
    fi
    
    echo -e "${left_content}      ${middle_content}      ${right_content}"
}

# Draw the entire UI (full redraw)
draw_ui() {
    tput clear
    tput cup 0 0
    echo -e "${HIDE_CURSOR}"
    
    # Opensoft Banner
    echo -e "${BOLD}${CYAN}"
    echo "   ___                            __ _   "
    echo "  / _ \\ _ __    ___  _ __   ___ / _| |_ "
    echo " | | | | '_ \\  / _ \\| '_ \\ / __| |_| __|"
    echo " | |_| | |_) ||  __/| | | |\\__ \\  _| |_ "
    echo "  \\___/| .__/  \\___||_| |_||___/_|  \\__|"
    echo "       |_|                               "
    echo -e "${NC}"

    # Header
    echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${BLUE}║               WorkBenches Configuration Manager                    ║${NC}"
    echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Navigation:${NC} ↑/↓ Move  ${CYAN}←/→:${NC} Switch Section  ${CYAN}Space:${NC} Toggle  ${CYAN}Enter:${NC} Apply Changes  ${CYAN}Q:${NC} Quit"
    echo ""
    
    # Draw three sections side by side
    draw_three_sections
    
    echo ""
    
    # Show selected count
    local selected_count=0
    for bench in "${bench_items[@]}"; do
        [ "${component_checked[bench_$bench]}" = true ] && ((selected_count++))
    done
    for item in "${ai_items[@]}"; do
        [[ "$item" != separator* ]] && [ "${component_checked[$item]}" = true ] && ((selected_count++))
    done
    for item in "${tool_items[@]}"; do
        [ "${component_checked[$item]}" = true ] && ((selected_count++))
    done
    
    echo -e "${MAGENTA}Changes selected: $selected_count${NC}"
}


# Draw three sections side by side
draw_three_sections() {
    local benches_active=$( [ $CURRENT_SECTION -eq 0 ] && echo "true" || echo "false" )
    local ai_active=$( [ $CURRENT_SECTION -eq 1 ] && echo "true" || echo "false" )
    local tools_active=$( [ $CURRENT_SECTION -eq 2 ] && echo "true" || echo "false" )
    
    # Section headers (borders adjusted to match content)
    local bench_header="${DIM}┌────── BENCHES ────────┐${NC}"
    local ai_header="${DIM}┌─── AI ASSISTANTS ─────┐${NC}"
    local tools_header="${DIM}┌─────── TOOLS ─────────┐${NC}"
    
    [ "$benches_active" = "true" ] && bench_header="${BOLD}${YELLOW}┌────── BENCHES ────────┐${NC}"
    [ "$ai_active" = "true" ] && ai_header="${BOLD}${YELLOW}┌─── AI ASSISTANTS ─────┐${NC}"
    [ "$tools_active" = "true" ] && tools_header="${BOLD}${YELLOW}┌─────── TOOLS ─────────┐${NC}"
    
    echo -e "${bench_header}      ${ai_header}      ${tools_header}"
    
    # Draw items in all three columns
    local max_items=${#bench_items[@]}
    [ ${#ai_items[@]} -gt $max_items ] && max_items=${#ai_items[@]}
    [ ${#tool_items[@]} -gt $max_items ] && max_items=${#tool_items[@]}
    
    for ((i=0; i<$max_items; i++)); do
        # Left column (Benches) - 24 chars wide
        local left_content="                        "
        if [ $i -lt ${#bench_items[@]} ]; then
            local bench="${bench_items[$i]}"
            local is_selected=$( [ $CURRENT_SECTION -eq 0 ] && [ $i -eq $current_selection ] && echo "true" || echo "false" )
            left_content=$(draw_item_compact "bench_$bench" "$is_selected" "$benches_active")
        fi
        
        # Middle column (AI) - 24 chars wide
        local middle_content="                        "
        if [ $i -lt ${#ai_items[@]} ]; then
            local item="${ai_items[$i]}"
            if [[ "$item" == separator* ]]; then
                middle_content="${DIM}────────────────────────${NC}"
            else
                local is_selected=$( [ $CURRENT_SECTION -eq 1 ] && [ $i -eq $current_selection ] && echo "true" || echo "false" )
                middle_content=$(draw_item_compact "$item" "$is_selected" "$ai_active")
            fi
        fi
        
        # Right column (Tools) - 24 chars wide
        local right_content="                        "
        if [ $i -lt ${#tool_items[@]} ]; then
            local item="${tool_items[$i]}"
            local is_selected=$( [ $CURRENT_SECTION -eq 2 ] && [ $i -eq $current_selection ] && echo "true" || echo "false" )
            right_content=$(draw_item_compact "$item" "$is_selected" "$tools_active")
        fi
        
        echo -e "${left_content}      ${middle_content}      ${right_content}"
    done
    
    # Section footers (borders adjusted to match content)
    local bench_footer="${DIM}└───────────────────────┘${NC}"
    local ai_footer="${DIM}└───────────────────────┘${NC}"
    local tools_footer="${DIM}└───────────────────────┘${NC}"
    
    [ "$benches_active" = "true" ] && bench_footer="${BOLD}${YELLOW}└───────────────────────┘${NC}"
    [ "$ai_active" = "true" ] && ai_footer="${BOLD}${YELLOW}└───────────────────────┘${NC}"
    [ "$tools_active" = "true" ] && tools_footer="${BOLD}${YELLOW}└───────────────────────┘${NC}"
    
    echo -e "${bench_footer}      ${ai_footer}      ${tools_footer}"
}

# Draw a single item (compact version for 3-column layout)
draw_item_compact() {
    local key="$1"
    local is_selected="$2"
    local section_active="$3"
    
    local checked="${component_checked[$key]}"
    local desc="${component_description[$key]}"
    local status=$(check_component_status "$key")
    
    # Checkbox with action indicator
    local checkbox="[ ]"
    local action="${component_action[$key]}"
    
    if [ "$checked" = true ]; then
        if [[ "$action" == "uninstall" ]]; then
            checkbox="[${RED}X${NC}]"
        else
            checkbox="[${GREEN}✓${NC}]"
        fi
    fi
    
    # Status indicator
    local status_color="$RED"
    local status_symbol="✗"
    
    if [[ "$status" == "installed" || "$status" == "configured" ]]; then
        status_color="$GREEN"
        status_symbol="✓"
    elif [[ "$status" == "needs creds" ]]; then
        status_color="$YELLOW"
        status_symbol="⚠"
    fi
    
    # Selection highlight
    local prefix="  "
    if [ "$is_selected" = "true" ] && [ "$section_active" = "true" ]; then
        prefix="${CYAN}▶ "
    fi
    
    # Format with proper width (24 chars total for each column)
    # Using 16 chars for description to reach total of 24 visible chars
    # Breakdown: prefix(2) + checkbox(3) + space(1) + status(1) + space(1) + desc(16) = 24
    printf "%b%s %b%s%b %-16s" "$prefix" "$checkbox" "$status_color" "$status_symbol" "$NC" "${desc:0:16}"
}

# Handle keyboard input
handle_input() {
    local key
    
    # Read single character
    IFS= read -rsn1 key
    
    # Handle escape sequences (arrow keys, etc.)
    if [[ $key == $'\x1b' ]]; then
        read -rsn2 -t 0.1 key
        case "$key" in
            '[A') # Up arrow - move up in current section
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
                local max_idx
                if [ $CURRENT_SECTION -eq 0 ]; then
                    max_idx=$((${#bench_items[@]} - 1))
                elif [ $CURRENT_SECTION -eq 1 ]; then
                    max_idx=$((${#ai_items[@]} - 1))
                else
                    max_idx=$((${#tool_items[@]} - 1))
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
            '[C') # Right arrow - switch section right
                if [ $CURRENT_SECTION -lt 2 ]; then
                    ((CURRENT_SECTION++))
                    current_selection=0
                fi
                ;;
            '[D') # Left arrow - switch section left
                if [ $CURRENT_SECTION -gt 0 ]; then
                    ((CURRENT_SECTION--))
                    current_selection=0
                fi
                ;;
        esac
    else
        case "$key" in
            ' ') # Spacebar - toggle selection
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
                else
                    local item="${tool_items[$current_selection]}"
                    key="$item"
                fi
                
                # Determine action based on current status
                local status="${component_status[$key]}"
                local is_installed=false
                [[ "$status" == "installed" || "$status" == "needs creds" ]] && is_installed=true
                
                if [ "${component_checked[$key]}" = true ]; then
                    # Currently checked
                    if [ "$is_installed" = true ]; then
                        # Installed item: toggle to uninstall
                        component_action["$key"]="uninstall"
                        # Keep checked but marked for uninstall
                    else
                        # Not installed: uncheck (cancel install)
                        component_checked["$key"]=false
                        component_action["$key"]=""
                    fi
                else
                    # Currently unchecked
                    component_checked["$key"]=true
                    if [ "$is_installed" = true ]; then
                        # Installed item: mark to keep (cancel uninstall)
                        component_action["$key"]=""
                    else
                        # Not installed: mark to install
                        component_action["$key"]="install"
                    fi
                fi
                ;;
            '') # Enter - confirm and process
                return 1
                ;;
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
        read -p "  sk-" openai_key
        openai_key="sk-$openai_key"
        
        if [ -z "$openai_key" ]; then
            echo -e "${RED}✗ API key cannot be empty.${NC}"
            read -p "Try again? [Y/n]: " retry
            [[ "$retry" =~ ^[Nn] ]] && return 1
        elif [[ ! "$openai_key" =~ ^sk- ]]; then
            echo -e "${RED}✗ Invalid OpenAI API key format. Keys should start with 'sk-'${NC}"
            read -p "Try again? [Y/n]: " retry
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
                read -p "Try again? [Y/n]: " retry
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
        read -p "  sk-" anthropic_key
        anthropic_key="sk-$anthropic_key"
        
        if [ -z "$anthropic_key" ]; then
            echo -e "${RED}✗ API key cannot be empty.${NC}"
            read -p "Try again? [Y/n]: " retry
            [[ "$retry" =~ ^[Nn] ]] && return 1
        elif [[ ! "$anthropic_key" =~ ^sk- ]]; then
            echo -e "${RED}✗ Invalid Anthropic API key format. Keys should start with 'sk-'${NC}"
            read -p "Try again? [Y/n]: " retry
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
                read -p "Try again? [Y/n]: " retry
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
        read -p "  " session_key
        
        if [ -z "$session_key" ]; then
            echo -e "${RED}✗ Session key cannot be empty.${NC}"
            read -p "Try again? [Y/n]: " retry
            [[ "$retry" =~ ^[Nn] ]] && return 1
        elif [[ ! "$session_key" =~ ^sk-ant-sid ]]; then
            echo -e "${YELLOW}⚠️  Warning: Session key format doesn't match expected pattern.${NC}"
            read -p "Continue anyway? [y/N]: " continue_anyway
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
        if git clone --depth=1 --quiet "$repo_url" "$temp_dir" 2>/dev/null; then
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
    local fail_count=0
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local config_file="$script_dir/../config/bench-config.json"
    local -a items_needing_creds=()
    
    # Process benches
    for bench in "${bench_items[@]}"; do
        local key="bench_$bench"
        if [ "${component_checked[$key]}" = true ]; then
            local action="${component_action[$key]}"
            local status="${component_status[$key]}"
            any_selected=true
            
            if [[ "$action" == "uninstall" ]]; then
                log "Uninstalling bench: $bench"
                echo -e "${BOLD}${CYAN}▶ Uninstalling: $bench${NC}"
                local bench_path=$(jq -r ".benches.${bench}.path // \"$bench\"" "$config_file" 2>/dev/null)
                if [ -d "$script_dir/../$bench_path" ]; then
                    log "Removing directory: $script_dir/../$bench_path"
                    if rm -rf "$script_dir/../$bench_path"; then
                        log "Successfully uninstalled $bench"
                        echo -e "  ${GREEN}✓ Successfully uninstalled $bench${NC}"
                        ((success_count++))
                    else
                        log "ERROR: Failed to uninstall $bench"
                        echo -e "  ${RED}✗ Failed to uninstall $bench${NC}"
                        ((fail_count++))
                    fi
                else
                    echo -e "  ${YELLOW}⚠ $bench not found, already uninstalled${NC}"
                fi
                echo ""
            else
                # Check if needs setup vs install
                if [[ "$status" == "needs creds" ]]; then
                    # Bench is installed but not set up
                    log "Setting up bench: $bench"
                    echo -e "${BOLD}${CYAN}▶ Setting up: $bench${NC}"
                    local bench_path=$(jq -r ".benches.${bench}.path // \"$bench\"" "$config_file" 2>/dev/null)
                    local full_bench_path="$script_dir/../$bench_path"
                    local setup_script="$full_bench_path/setup.sh"
                    
                    # If it's a git repo, fetch latest updates first
                    if [ -d "$full_bench_path/.git" ] || [ -f "$full_bench_path/.git" ]; then
                        local bench_url=$(jq -r ".benches.${bench}.url // \"\"" "$config_file" 2>/dev/null)
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
                        
                        # Run setup in background with spinner
                        (
                            bash "$setup_script" >> "$LOG_FILE" 2>&1
                            echo $? > /tmp/setup_status_$$
                        ) &
                        local setup_pid=$!
                        show_spinner $setup_pid "Setting up $bench"
                        
                        local setup_status=$(cat /tmp/setup_status_$$ 2>/dev/null || echo "1")
                        rm -f /tmp/setup_status_$$
                        
                        if [ "$setup_status" -eq 0 ]; then
                            log "Successfully set up $bench"
                            echo -e "  ${GREEN}✓ Successfully set up $bench${NC}"
                            echo -e "  ${DIM}Command 'new-${bench}-project' should now be available${NC}"
                            ((success_count++))
                        else
                            log "ERROR: Setup script failed for $bench"
                            echo -e "  ${RED}✗ Setup script failed${NC}"
                            ((fail_count++))
                        fi
                    else
                        echo -e "  ${YELLOW}⚠ No setup script found at: $setup_script${NC}"
                        echo -e "  ${DIM}Please manually set up $bench by running its setup script${NC}"
                        ((fail_count++))
                    fi
                    echo ""
                else
                    # Install from scratch (or fetch if directory exists)
                    echo -e "${BOLD}${CYAN}▶ Installing: $bench${NC}"
                    
                    # Get bench info from config
                    if [ -f "$config_file" ]; then
                        local bench_url=$(jq -r ".benches.${bench}.url // \"\"" "$config_file")
                        local bench_path=$(jq -r ".benches.${bench}.path // \"$bench\"" "$config_file")
                        local full_bench_path="$script_dir/../$bench_path"
                        
                        if [ -n "$bench_url" ] && [ "$bench_url" != "null" ]; then
                            # Check if directory already exists
                            if [ -d "$full_bench_path" ]; then
                                # Directory exists - check if it has git
                                if [ -d "$full_bench_path/.git" ] || [ -f "$full_bench_path/.git" ]; then
                                    # Has git repo, do a fetch and pull
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
                                        ((fail_count++))
                                        echo ""
                                        continue
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
                                            git clone "$bench_url" "$full_bench_path" >> "$LOG_FILE" 2>&1
                                            echo $? > /tmp/clone_status_$$
                                        ) &
                                        local clone_pid=$!
                                        show_spinner $clone_pid "Cloning $bench"
                                        
                                        local clone_status=$(cat /tmp/clone_status_$$ 2>/dev/null || echo "1")
                                        rm -f /tmp/clone_status_$$
                                        
                                        if [ "$clone_status" -ne 0 ]; then
                                            log "ERROR: Failed to clone $bench"
                                            echo -e "  ${RED}✗ Failed to clone $bench${NC}"
                                            ((fail_count++))
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
                                        ((fail_count++))
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
                                    git clone "$bench_url" "$full_bench_path" >> "$LOG_FILE" 2>&1
                                    echo $? > /tmp/clone_status_$$
                                ) &
                                local clone_pid=$!
                                show_spinner $clone_pid "Cloning $bench"
                                
                                local clone_status=$(cat /tmp/clone_status_$$ 2>/dev/null || echo "1")
                                rm -f /tmp/clone_status_$$
                                
                                if [ "$clone_status" -ne 0 ]; then
                                    log "ERROR: Failed to clone $bench"
                                    echo -e "  ${RED}✗ Failed to clone $bench${NC}"
                                    ((fail_count++))
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
                                
                                # Run setup in background with spinner
                                (
                                    bash "$setup_script" >> "$LOG_FILE" 2>&1
                                    echo $? > /tmp/setup_status_$$
                                ) &
                                local setup_pid=$!
                                show_spinner $setup_pid "Setting up $bench"
                                
                                local setup_status=$(cat /tmp/setup_status_$$ 2>/dev/null || echo "1")
                                rm -f /tmp/setup_status_$$
                                
                                if [ "$setup_status" -eq 0 ]; then
                                    log "Successfully set up $bench"
                                    echo -e "  ${GREEN}✓ Successfully set up $bench${NC}"
                                    ((success_count++))
                                else
                                    log "WARNING: Setup failed for $bench"
                                    echo -e "  ${YELLOW}⚠ Setup failed${NC}"
                                    echo -e "  ${DIM}You may need to run setup manually: $setup_script${NC}"
                                    ((success_count++))
                                fi
                            else
                                echo -e "  ${YELLOW}⚠ No setup script found${NC}"
                                echo -e "  ${DIM}Bench may require manual setup${NC}"
                                ((success_count++))
                            fi
                        else
                            echo -e "  ${RED}✗ No repository URL found for $bench${NC}"
                            ((fail_count++))
                        fi
                    else
                        echo -e "  ${RED}✗ Config file not found${NC}"
                        ((fail_count++))
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
        
        if [ "${component_checked[$item]}" = true ]; then
            any_selected=true
            local desc="${component_description[$item]}"
            local action="${component_action[$item]}"
            
            # Handle uninstallation
            if [[ "$action" == "uninstall" ]]; then
                echo -e "${BOLD}${CYAN}▶ Uninstalling: $desc${NC}"
                
                case "$item" in
                    claude_cli)
                        if command -v claude &> /dev/null; then
                            echo -e "  ${YELLOW}Uninstalling Claude Code CLI...${NC}"
                            echo -e "  ${DIM}Note: Manual uninstall required, check Claude documentation${NC}"
                        else
                            echo -e "  ${YELLOW}⚠ Claude CLI not found${NC}"
                        fi
                        ;;
                    copilot_cli)
                        if command -v npm &> /dev/null; then
                            if sudo npm uninstall -g @github/copilot 2>/dev/null; then
                                echo -e "  ${GREEN}✓ GitHub Copilot CLI uninstalled${NC}"
                                ((success_count++))
                            else
                                echo -e "  ${RED}✗ Failed to uninstall GitHub Copilot CLI${NC}"
                                ((fail_count++))
                            fi
                        fi
                        ;;
                    codex_cli)
                        if command -v npm &> /dev/null; then
                            if sudo npm uninstall -g @openai/codex 2>/dev/null; then
                                echo -e "  ${GREEN}✓ Codex CLI uninstalled${NC}"
                                ((success_count++))
                            else
                                echo -e "  ${RED}✗ Failed to uninstall Codex CLI${NC}"
                                ((fail_count++))
                            fi
                        fi
                        ;;
                    openspec)
                        if command -v npm &> /dev/null; then
                            if sudo npm uninstall -g @fission-ai/openspec 2>/dev/null; then
                                echo -e "  ${GREEN}✓ OpenSpec uninstalled${NC}"
                                ((success_count++))
                            else
                                echo -e "  ${RED}✗ Failed to uninstall OpenSpec${NC}"
                                ((fail_count++))
                            fi
                        fi
                        ;;
                    *)
                        echo -e "  ${YELLOW}⚠ Uninstall not implemented for $desc${NC}"
                        ;;
                esac
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
                        trap '' INT
                        (
                            curl -fsSL https://claude.ai/install.sh | bash >> "$LOG_FILE" 2>&1
                        ) &
                        local install_pid=$!
                        
                        if show_spinner $install_pid "Installing Claude CLI" 180; then
                            trap - INT
                            log "Claude CLI installed successfully via native installer"
                            echo -e "  ${GREEN}✓ Claude Code CLI installed${NC}"
                            echo -e "  ${DIM}Run 'claude' to start using it${NC}"
                            ((success_count++))
                            items_needing_creds+=("claude")
                        else
                            trap - INT
                            log "ERROR: Claude CLI installation failed"
                            echo -e "  ${RED}✗ Failed to install Claude Code CLI${NC}"
                            echo -e "  ${DIM}Manual install: curl -fsSL https://claude.ai/install.sh | bash${NC}"
                            ((fail_count++))
                        fi
                    fi
                    ;;
                    
                copilot_cli)
                    if command -v npm &> /dev/null; then
                        if [ "$is_installed" = true ]; then
                            echo -e "  ${YELLOW}Checking for Copilot CLI updates...${NC}"
                            # Check if update available
                            local update_output=$(sudo npm update -g @github/copilot 2>&1)
                            if echo "$update_output" | grep -q "up to date\|unchanged"; then
                                echo -e "  ${GREEN}✓ GitHub Copilot CLI is already up to date${NC}"
                                ((success_count++))
                            else
                                echo -e "  ${GREEN}✓ GitHub Copilot CLI updated${NC}"
                                ((success_count++))
                            fi
                        else
                            echo -e "  ${YELLOW}Installing GitHub Copilot CLI...${NC}"
                            if sudo npm install -g @github/copilot; then
                                echo -e "  ${GREEN}✓ GitHub Copilot CLI installed${NC}"
                                ((success_count++))
                                items_needing_creds+=("copilot")
                            else
                                echo -e "  ${RED}✗ Failed to install GitHub Copilot CLI${NC}"
                                ((fail_count++))
                            fi
                        fi
                    else
                        echo -e "  ${RED}✗ npm not found - Node.js required${NC}"
                        echo -e "  ${DIM}Install Node.js: https://nodejs.org/${NC}"
                        ((fail_count++))
                    fi
                    ;;
                    
                codex_cli)
                    if command -v npm &> /dev/null; then
                        # Check Node.js version
                        local node_version=$(node --version 2>/dev/null | cut -d'v' -f2 | cut -d'.' -f1)
                        if [ -n "$node_version" ] && [ "$node_version" -ge 18 ]; then
                            if [ "$is_installed" = true ]; then
                                echo -e "  ${YELLOW}Checking for Codex CLI updates...${NC}"
                                # Check if update available
                                local update_output=$(sudo npm update -g @openai/codex 2>&1)
                                if echo "$update_output" | grep -q "up to date\|unchanged"; then
                                    echo -e "  ${GREEN}✓ Codex CLI is already up to date${NC}"
                                    ((success_count++))
                                else
                                    echo -e "  ${GREEN}✓ Codex CLI updated${NC}"
                                    ((success_count++))
                                fi
                            else
                                echo -e "  ${YELLOW}Installing OpenAI Codex CLI...${NC}"
                                if sudo npm install -g @openai/codex; then
                                    echo -e "  ${GREEN}✓ OpenAI Codex CLI installed${NC}"
                                    ((success_count++))
                                    items_needing_creds+=("codex")
                                else
                                    echo -e "  ${RED}✗ Failed to install Codex CLI${NC}"
                                    ((fail_count++))
                                fi
                            fi
                        else
                            echo -e "  ${RED}✗ Node.js 18+ required (current: v$node_version)${NC}"
                            echo -e "  ${DIM}Recommended: Node.js 22+${NC}"
                            echo -e "  ${DIM}Install/Update Node.js: https://nodejs.org/${NC}"
                            ((fail_count++))
                        fi
                    else
                        echo -e "  ${RED}✗ npm not found - Node.js required${NC}"
                        echo -e "  ${DIM}Install Node.js 22+: https://nodejs.org/${NC}"
                        ((fail_count++))
                    fi
                    ;;
                    
                gemini_cli)
                    if command -v npm &> /dev/null; then
                        # Check Node.js version
                        local node_version=$(node --version 2>/dev/null | cut -d'v' -f2 | cut -d'.' -f1)
                        if [ -n "$node_version" ] && [ "$node_version" -ge 18 ]; then
                            if [ "$is_installed" = true ]; then
                                echo -e "  ${YELLOW}Checking for Gemini CLI updates...${NC}"
                                # Check if update available
                                local update_output=$(sudo npm update -g @google/gemini-cli 2>&1)
                                if echo "$update_output" | grep -q "up to date\|unchanged"; then
                                    echo -e "  ${GREEN}✓ Gemini CLI is already up to date${NC}"
                                    ((success_count++))
                                else
                                    echo -e "  ${GREEN}✓ Gemini CLI updated${NC}"
                                    ((success_count++))
                                fi
                            else
                                echo -e "  ${YELLOW}Installing Google Gemini CLI...${NC}"
                                echo -e "  ${DIM}This may take a few minutes...${NC}"
                                echo -e "  ${BOLD}${RED}Please do not interrupt the installation (Ctrl+C)${NC}"
                                log "Starting Gemini CLI installation via npm"
                                
                                # Check if npm prefix is in user directory
                                local npm_prefix=$(npm config get prefix 2>/dev/null)
                                local needs_sudo=false
                                
                                # Check if prefix is a system directory (not in home directory)
                                if [[ "$npm_prefix" != "$HOME"* ]]; then
                                    needs_sudo=true
                                    log "npm prefix is in system directory ($npm_prefix), using sudo"
                                else
                                    log "npm prefix is in user directory ($npm_prefix), no sudo needed"
                                fi
                                
                                # Install Gemini CLI via npm in background with spinner
                                # Temporarily ignore interrupts during installation
                                trap '' INT
                                (
                                    if [ "$needs_sudo" = true ]; then
                                        sudo npm install -g @google/gemini-cli >> "$LOG_FILE" 2>&1
                                    else
                                        npm install -g @google/gemini-cli >> "$LOG_FILE" 2>&1
                                    fi
                                ) &
                                local install_pid=$!
                                
                                if show_spinner $install_pid "Installing Gemini CLI" 180; then
                                    # Restore interrupt handling
                                    trap - INT
                                    log "Gemini CLI installed successfully via npm"
                                    echo -e "  ${GREEN}✓ Gemini CLI installed${NC}"
                                    echo -e "  ${DIM}Run 'gemini' to start using it${NC}"
                                    echo -e "  ${CYAN}✨ Free tier: 60 requests/min, 1000/day with Google login${NC}"
                                    ((success_count++))
                                    items_needing_creds+=("gemini")
                                else
                                    # Restore interrupt handling even on failure
                                    trap - INT
                                    log "ERROR: Gemini CLI installation failed"
                                    echo -e "  ${RED}✗ Failed to install Gemini CLI${NC}"
                                    echo -e "  ${DIM}Manual install: npm install -g @google/gemini-cli${NC}"
                                    ((fail_count++))
                                fi
                            fi
                        else
                            echo -e "  ${RED}✗ Node.js 18+ required (current: v$node_version)${NC}"
                            echo -e "  ${DIM}Recommended: Node.js 22+${NC}"
                            echo -e "  ${DIM}Install/Update Node.js: https://nodejs.org/${NC}"
                            ((fail_count++))
                        fi
                    else
                        echo -e "  ${RED}✗ npm not found - Node.js required${NC}"
                        echo -e "  ${DIM}Install Node.js 22+: https://nodejs.org/${NC}"
                        ((fail_count++))
                    fi
                    ;;
                    
                opencode_cli)
                    echo -e "  ${YELLOW}Installing OpenCode CLI...${NC}"
                    echo -e "  ${DIM}Note: OpenCode may require additional setup${NC}"
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
                            ((fail_count++))
                        fi
                    else
                        echo -e "  ${RED}✗ uv installation failed${NC}"
                        echo -e "  ${DIM}Try manually: curl -LsSf https://astral.sh/uv/install.sh | sh${NC}"
                        echo -e "  ${DIM}Then restart your shell or run: source ~/.zshrc${NC}"
                        ((fail_count++))
                    fi
                    ;;
                    
                openspec)
                    if command -v npm &> /dev/null; then
                        if [ "$is_installed" = true ]; then
                            echo -e "  ${YELLOW}Checking for OpenSpec updates...${NC}"
                            # Check if update available
                            local update_output=$(sudo npm update -g @fission-ai/openspec 2>&1)
                            if echo "$update_output" | grep -q "up to date\|unchanged"; then
                                echo -e "  ${GREEN}✓ OpenSpec is already up to date${NC}"
                                ((success_count++))
                            else
                                echo -e "  ${GREEN}✓ OpenSpec updated${NC}"
                                ((success_count++))
                            fi
                        else
                            echo -e "  ${YELLOW}Installing OpenSpec...${NC}"
                            if sudo npm install -g @fission-ai/openspec@latest; then
                                echo -e "  ${GREEN}✓ OpenSpec installed${NC}"
                                ((success_count++))
                            else
                                echo -e "  ${RED}✗ Failed to install OpenSpec${NC}"
                                ((fail_count++))
                            fi
                        fi
                    else
                        echo -e "  ${RED}✗ npm not found - Node.js required${NC}"
                        echo -e "  ${DIM}Install Node.js: https://nodejs.org/${NC}"
                        ((fail_count++))
                    fi
                    ;;
            esac
            echo ""
        fi
    done
    
    # Process tool items
    for item in "${tool_items[@]}"; do
        if [ "${component_checked[$item]}" = true ]; then
            any_selected=true
            local desc="${component_description[$item]}"
            local action="${component_action[$item]}"
            local status="${component_status[$item]}"
            local is_installed=false
            [[ "$status" == "installed" ]] && is_installed=true
            
            # Handle uninstallation
            if [[ "$action" == "uninstall" ]]; then
                echo -e "${BOLD}${CYAN}▶ Uninstalling: $desc${NC}"
                echo -e "  ${YELLOW}⚠ Manual uninstall required for $desc${NC}"
                echo ""
                continue
            fi
            
            # Handle installation
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
                            # Check if VS Code is installed
                            if command -v code &> /dev/null; then
                                # VS Code is installed, check for WSL extension by checking vscode-server directory
                                if [ -d "$HOME/.vscode-server" ]; then
                                    # Check if Dev Containers extension is installed on Windows side
                                    local windows_user=$(powershell.exe -c "[Environment]::UserName" 2>/dev/null | tr -d '\r')
                                    local windows_ext_file="/mnt/c/Users/$windows_user/.vscode/extensions/extensions.json"
                                    
                                    if [ -f "$windows_ext_file" ] && grep -q "ms-vscode-remote.remote-containers" "$windows_ext_file" 2>/dev/null; then
                                        echo -e "  ${GREEN}✓ VS Code with WSL and Dev Containers extensions are installed${NC}"
                                        ((success_count++))
                                    else
                                        echo -e "  ${YELLOW}⚠ VS Code is installed but Dev Containers extension is missing${NC}"
                                        echo ""
                                        echo -e "  ${CYAN}${BOLD}Install the Dev Containers extension:${NC}"
                                        echo -e "  ${DIM}Run the following command from WSL:${NC}"
                                        echo -e "  ${BLUE}code --install-extension ms-vscode-remote.remote-containers${NC}"
                                        echo ""
                                        echo -e "  ${DIM}Or open VS Code and search for 'Dev Containers' in the Extensions panel${NC}"
                                        echo -e "  ${DIM}The Dev Containers extension is essential for devcontainer support${NC}"
                                        echo ""
                                    fi
                                else
                                    echo -e "  ${YELLOW}⚠ VS Code is installed but WSL extension is not set up${NC}"
                                    echo ""
                                    echo -e "  ${CYAN}${BOLD}Set up WSL integration:${NC}"
                                    echo -e "  ${DIM}Run the following command from WSL to initialize:${NC}"
                                    echo -e "  ${BLUE}code .${NC}"
                                    echo ""
                                    echo -e "  ${DIM}This will install the VS Code Server in WSL${NC}"
                                    echo -e "  ${DIM}After WSL is set up, install the Dev Containers extension:${NC}"
                                    echo -e "  ${BLUE}code --install-extension ms-vscode-remote.remote-containers${NC}"
                                    echo ""
                                fi
                            else
                                echo -e "  ${YELLOW}WSL detected - Please install Windows version of VS Code${NC}"
                                echo ""
                                echo -e "  ${CYAN}${BOLD}Download VS Code for Windows:${NC}"
                                echo -e "  ${BLUE}https://code.visualstudio.com/download${NC}"
                                echo ""
                                echo -e "  ${YELLOW}Instructions:${NC}"
                                echo -e "  ${DIM}1. Download and install VS Code for Windows${NC}"
                                echo -e "  ${DIM}2. After installing, run 'code .' from WSL to set up integration${NC}"
                                echo -e "  ${DIM}3. Install required extensions:${NC}"
                                echo -e "  ${BLUE}   code --install-extension ms-vscode-remote.remote-wsl${NC}"
                                echo -e "  ${BLUE}   code --install-extension ms-vscode-remote.remote-containers${NC}"
                                echo ""
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
                                    ((fail_count++))
                                fi
                            else
                                echo -e "  ${YELLOW}snap not available${NC}"
                                echo -e "  ${DIM}Manual install: https://code.visualstudio.com/${NC}"
                                ((fail_count++))
                            fi
                        fi
                        ;;
                    warp)
                        # Check if running in WSL
                        if [ -n "$WSL_DISTRO_NAME" ] || grep -qi microsoft /proc/version 2>/dev/null; then
                            echo -e "  ${YELLOW}WSL detected - Please install Windows version of Warp Terminal${NC}"
                            echo ""
                            echo -e "  ${CYAN}${BOLD}Download Warp for Windows:${NC}"
                            echo -e "  ${BLUE}https://warp.dev${NC}"
                            echo ""
                            echo -e "  ${YELLOW}Instructions:${NC}"
                            echo -e "  ${DIM}1. Visit warp.dev and click 'Download for Windows'${NC}"
                            echo -e "  ${DIM}2. Run the Windows installer (.exe)${NC}"
                            echo -e "  ${DIM}3. Launch Warp from Windows to use with WSL${NC}"
                            echo -e "  ${DIM}   Or use: winget install Warp.Warp${NC}"
                            echo ""
                        else
                            echo -e "  ${YELLOW}Installing Warp Terminal for Linux...${NC}"
                            echo -e "  ${DIM}Visit: https://warp.dev${NC}"
                            echo -e "  ${YELLOW}Download and install .deb package from website${NC}"
                        fi
                        ;;
                    wave)
                        # Check if running in WSL
                        if [ -n "$WSL_DISTRO_NAME" ] || grep -qi microsoft /proc/version 2>/dev/null; then
                            echo -e "  ${YELLOW}WSL detected - Please install Windows version of Wave Terminal${NC}"
                            echo ""
                            echo -e "  ${CYAN}${BOLD}Download Wave Terminal for Windows:${NC}"
                            echo -e "  ${BLUE}https://waveterm.dev${NC}"
                            echo ""
                            echo -e "  ${YELLOW}Instructions:${NC}"
                            echo -e "  ${DIM}1. Visit waveterm.dev${NC}"
                            echo -e "  ${DIM}2. Download the Windows installer${NC}"
                            echo -e "  ${DIM}3. Run the installer and launch Wave from Windows${NC}"
                            echo ""
                        else
                            echo -e "  ${YELLOW}Installing Wave Terminal for Linux...${NC}"
                            echo -e "  ${DIM}Visit: https://waveterm.dev${NC}"
                            echo -e "  ${YELLOW}Download and install from website${NC}"
                        fi
                        ;;
                esac
            fi
            echo ""
        fi
    done
    
    # Summary
    echo ""
    echo -e "${BOLD}${BLUE}────────────────────────────────────────────────────────────────────────────${NC}"
    
    if [ "$any_selected" = false ]; then
        echo -e "${YELLOW}No items were selected.${NC}"
    else
        echo -e "${BOLD}Installation Summary:${NC}"
        [ $success_count -gt 0 ] && echo -e "  ${GREEN}✓ Successful: $success_count${NC}"
        [ $fail_count -gt 0 ] && echo -e "  ${RED}✗ Failed: $fail_count${NC}"
        
        if [ $success_count -gt 0 ] && [ $fail_count -eq 0 ]; then
            echo -e "\n${GREEN}${BOLD}✓ All installations completed successfully!${NC}"
        elif [ $success_count -gt 0 ]; then
            echo -e "\n${YELLOW}⚠️  Some installations completed with errors.${NC}"
        else
            echo -e "\n${RED}✗ All installations failed.${NC}"
        fi
    fi
    
    echo ""
    
    # Handle credential setup for newly installed CLIs
    if [ ${#items_needing_creds[@]} -gt 0 ]; then
        echo -e "${BOLD}${BLUE}────────────────────────────────────────────────────────────────────────────${NC}"
        echo -e "${BOLD}${YELLOW}Setting up Credentials${NC}"
        echo -e "${BOLD}${BLUE}────────────────────────────────────────────────────────────────────────────${NC}"
        echo ""
        
        for cli in "${items_needing_creds[@]}"; do
            case "$cli" in
                codex)
                    echo -e "${CYAN}▶ Setting up Codex CLI authentication...${NC}"
                    echo ""
                    
                    # Check if already authenticated
                    if [ -f "$HOME/.codex/auth.json" ] || [ -n "$OPENAI_API_KEY" ]; then
                        echo -e "${GREEN}✓ Codex CLI already has credentials configured${NC}"
                        echo ""
                    else
                        echo -e "${YELLOW}Codex needs authentication to work.${NC}"
                        echo -e "${DIM}You can sign in with your ChatGPT account or use an API key.${NC}"
                        echo ""
                        
                        while true; do
                            read -p "Launch Codex authentication now? [Y/n]: " launch_codex
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
                                read -p "Launch Claude CLI authentication now? [Y/n]: " launch_claude
                                case $launch_claude in
                                    [Yy]* | "" )
                                        echo ""
                                        echo -e "${YELLOW}Launching 'claude'...${NC}"
                                        echo -e "${DIM}Follow the prompts to choose your authentication method.${NC}"
                                        echo ""
                                        sleep 2
                                        
                                        # Launch claude - will prompt for authentication
                                        claude
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
                    
                gemini)
                    echo -e "${CYAN}▶ Setting up Gemini CLI authentication...${NC}"
                    echo ""
                    
                    echo -e "${BOLD}${GREEN}✨ Gemini CLI Free Tier${NC}"
                    echo -e "${BOLD}${BLUE}────────────────────────────────────────${NC}"
                    echo ""
                    echo -e "${YELLOW}Gemini CLI offers generous free tier access:${NC}"
                    echo -e "  ${DIM}• 60 requests per minute${NC}"
                    echo -e "  ${DIM}• 1,000 requests per day${NC}"
                    echo -e "  ${DIM}• Access to Gemini 2.5 Pro (1M token context)${NC}"
                    echo -e "  ${DIM}• No credit card required${NC}"
                    echo ""
                    echo -e "${CYAN}Authentication options:${NC}"
                    echo -e "  ${BOLD}${GREEN}1. Login with Google${NC} ${DIM}(Recommended - Free tier)${NC}"
                    echo -e "  ${CYAN}2. API Key${NC} ${DIM}(For higher limits or enterprise)${NC}"
                    echo ""
                    echo -e "${BOLD}${BLUE}────────────────────────────────────────${NC}"
                    echo ""
                    
                    if command -v gemini &> /dev/null; then
                        # Check if already has credentials
                        if [ -f "$HOME/.gemini/config.json" ] || [ -n "$GEMINI_API_KEY" ]; then
                            echo -e "${GREEN}✓ Gemini CLI already has credentials configured${NC}"
                            echo ""
                        else
                            echo -e "${YELLOW}To authenticate Gemini CLI:${NC}"
                            echo -e "  ${BOLD}${GREEN}Recommended:${NC} Run ${CYAN}gemini${NC} and login with Google${NC}"
                            echo -e "  ${DIM}Alternative: Set GEMINI_API_KEY from AI Studio${NC}"
                            echo ""
                            
                            while true; do
                                read -p "Launch Gemini CLI authentication now? [Y/n]: " launch_gemini
                                case $launch_gemini in
                                    [Yy]* | "" )
                                        echo ""
                                        echo -e "${YELLOW}Launching 'gemini'...${NC}"
                                        echo -e "${DIM}Select 'Login with Google' when prompted for best experience.${NC}"
                                        echo ""
                                        sleep 2
                                        
                                        # Launch gemini - will prompt for authentication
                                        gemini
                                        echo ""
                                        break
                                        ;;
                                    [Nn]* )
                                        echo ""
                                        echo -e "${YELLOW}Skipped. Run 'gemini' anytime to authenticate.${NC}"
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
    
    echo -e "${BLUE}Note: You may need to restart your shell for changes to take effect.${NC}"
    echo ""
    read -p "Press Enter to continue..."
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
            # Install Node.js 22.x LTS
            if curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - && \
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
            if curl -fsSL https://rpm.nodesource.com/setup_22.x | sudo bash - && \
               sudo yum install -y nodejs; then
                echo ""
                echo -e "${GREEN}✓ Node.js installed successfully!${NC}"
                return 0
            else
                echo -e "${RED}✗ Failed to install Node.js${NC}"
                return 1
            fi
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

# Check and install required dependencies
check_and_install_dependencies() {
    echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${BLUE}  Checking System Dependencies${NC}"
    echo -e "${BOLD}${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    local all_ok=true
    
    # Check git
    if command -v git &> /dev/null; then
        local git_version=$(git --version | awk '{print $3}')
        echo -e "  ${GREEN}✓ git${NC} - installed (version: $git_version)"
    else
        echo -e "  ${RED}✗ git${NC} - not installed (required)"
        all_ok=false
    fi
    
    # Check jq
    if command -v jq &> /dev/null; then
        local jq_version=$(jq --version 2>&1 | sed 's/jq-//')
        echo -e "  ${GREEN}✓ jq${NC} - installed (version: $jq_version)"
    else
        echo -e "  ${RED}✗ jq${NC} - not installed (required)"
        all_ok=false
    fi
    
    # Check curl
    if command -v curl &> /dev/null; then
        local curl_version=$(curl --version | head -n1 | awk '{print $2}')
        echo -e "  ${GREEN}✓ curl${NC} - installed (version: $curl_version)"
    else
        echo -e "  ${RED}✗ curl${NC} - not installed (required)"
        all_ok=false
    fi
    
    echo ""
    
    # Check Node.js (important for many AI CLIs)
    local node_needs_install=false
    if command -v node &> /dev/null; then
        local node_version=$(node --version | sed 's/v//')
        local node_major=$(echo $node_version | cut -d'.' -f1)
        if [ "$node_major" -ge 18 ]; then
            echo -e "  ${GREEN}✓ Node.js${NC} - installed (version: v$node_version)"
            if command -v npm &> /dev/null; then
                local npm_version=$(npm --version)
                echo -e "  ${GREEN}✓ npm${NC} - installed (version: $npm_version)"
            fi
        else
            echo -e "  ${YELLOW}⚠ Node.js${NC} - outdated (v$node_version, need 18+)"
            node_needs_install=true
        fi
    else
        echo -e "  ${YELLOW}⚠ Node.js${NC} - not installed (required for Codex, Copilot, OpenSpec)"
        node_needs_install=true
    fi
    
    echo ""
    
    # Handle missing core dependencies
    if [ "$all_ok" = false ]; then
        echo -e "${RED}Missing required core dependencies.${NC}"
        echo -e "${YELLOW}Please install manually:${NC}"
        echo -e "  Ubuntu/Debian: ${CYAN}sudo apt update && sudo apt install -y git jq curl${NC}"
        echo -e "  macOS:         ${CYAN}brew install git jq curl${NC}"
        echo ""
        read -p "Press Enter to exit..."
        exit 1
    fi
    
    # Offer to install Node.js if needed
    if [ "$node_needs_install" = true ]; then
        echo -e "${YELLOW}Node.js is required for several AI coding assistants.${NC}"
        echo ""
        while true; do
            read -p "Would you like to install Node.js now? [Y/n]: " install_choice
            case $install_choice in
                [Yy]* | "" )
                    echo ""
                    if install_nodejs; then
                        echo ""
                        echo -e "${GREEN}✓ Node.js installation complete!${NC}"
                        echo ""
                        sleep 2
                        break
                    else
                        echo ""
                        echo -e "${YELLOW}You can install Node.js later from: ${BLUE}https://nodejs.org/${NC}"
                        echo ""
                        sleep 2
                        break
                    fi
                    ;;
                [Nn]* )
                    echo ""
                    echo -e "${YELLOW}Skipping Node.js installation.${NC}"
                    echo -e "  Note: AI CLIs requiring Node.js will not be installable."
                    echo ""
                    sleep 2
                    break
                    ;;
                * )
                    echo "Please answer yes or no."
                    ;;
            esac
        done
    fi
}

# Main function
main() {
    log "Main function started"
    
    # Check and install dependencies first
    log "Checking dependencies..."
    check_and_install_dependencies
    
    # Initialize
    log "Initializing components and loading statuses..."
    init_components
    load_statuses
    
    # Main loop
    log "Entering main UI loop"
    
    # Initial full draw
    draw_ui
    
    # Store initial state
    local prev_sel=$current_selection
    local prev_sect=$CURRENT_SECTION
    local prev_state=$(get_checked_state)
    
    while true; do
        handle_input
        local result=$?
        
        # Simple approach: just redraw on any change
        # This is more reliable than selective updates
        local current_state=$(get_checked_state)
        
        # Check if anything changed (selection or checkboxes)
        if [ $current_selection -ne $prev_sel ] || [ $CURRENT_SECTION -ne $prev_sect ] || [ "$current_state" != "$prev_state" ]; then
            draw_ui
            prev_sel=$current_selection
            prev_sect=$CURRENT_SECTION
            prev_state="$current_state"
        fi
        
        if [ $result -eq 1 ]; then
            # Enter pressed - process selections
            log "User pressed Enter - processing selections"
            process_selections
            break
        elif [ $result -eq 2 ]; then
            # Quit pressed
            log "User pressed Quit - exiting"
            echo -e "${SHOW_CURSOR}"
            clear
            echo -e "${YELLOW}Setup cancelled.${NC}"
            log "=== Setup script cancelled ==="
            exit 0
        fi
    done
    
    echo -e "${SHOW_CURSOR}"
    log "=== Setup script completed ==="
}

# Cleanup on exit
trap 'echo -e "${SHOW_CURSOR}"; exit' INT TERM

# Run if executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main
fi
