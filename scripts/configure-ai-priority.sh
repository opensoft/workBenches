#!/bin/bash
# AI Provider Priority Configuration
# Allows users to set their preferred order of AI providers with a TUI
# Version: 1.0.0

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Config file location
CONFIG_DIR="${HOME}/.config/workbenches"
PRIORITY_CONFIG="${CONFIG_DIR}/ai-provider-priority.conf"

# Default provider list (in default priority order)
DEFAULT_PROVIDERS=(
    "codex"
    "claude"
    "gemini"
    "copilot"
    "grok"
    "meta"
    "kimi2"
    "deepseek"
)

# Provider display names
declare -A PROVIDER_NAMES=(
    ["codex"]="GitHub Codex"
    ["claude"]="Claude (Anthropic)"
    ["gemini"]="Google Gemini"
    ["copilot"]="GitHub Copilot"
    ["grok"]="xAI Grok"
    ["meta"]="Meta Llama"
    ["kimi2"]="Moonshot Kimi 2"
    ["deepseek"]="DeepSeek"
)

# Provider CLI commands to check
declare -A PROVIDER_CLI=(
    ["codex"]="codex"
    ["claude"]="claude"
    ["gemini"]="gemini"
    ["copilot"]="copilot"
    ["grok"]="grok"
    ["meta"]="llama"
    ["kimi2"]="kimi"
    ["deepseek"]="deepseek"
)

# Log functions
log_info() { echo -e "${BLUE}ℹ${NC} $*"; }
log_success() { echo -e "${GREEN}✓${NC} $*"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $*"; }
log_error() { echo -e "${RED}✗${NC} $*" >&2; }

# Check if provider CLI is installed
is_provider_installed() {
    local provider="$1"
    local cli_cmd="${PROVIDER_CLI[$provider]}"
    command -v "$cli_cmd" >/dev/null 2>&1
}

# Get installed status symbol
get_status_symbol() {
    local provider="$1"
    if is_provider_installed "$provider"; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
    fi
}

# Load current priority configuration
load_priority_config() {
    if [ -f "$PRIORITY_CONFIG" ]; then
        mapfile -t CURRENT_PRIORITY < "$PRIORITY_CONFIG"
        
        # Validate and merge with defaults
        # Add any new providers not in config
        for provider in "${DEFAULT_PROVIDERS[@]}"; do
            if ! printf '%s\n' "${CURRENT_PRIORITY[@]}" | grep -q "^${provider}$"; then
                CURRENT_PRIORITY+=("$provider")
            fi
        done
    else
        CURRENT_PRIORITY=("${DEFAULT_PROVIDERS[@]}")
    fi
}

# Save priority configuration
save_priority_config() {
    mkdir -p "$CONFIG_DIR"
    printf '%s\n' "${CURRENT_PRIORITY[@]}" > "$PRIORITY_CONFIG"
    log_success "AI provider priority saved to $PRIORITY_CONFIG"
}

# Display current configuration
show_current_config() {
    clear
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}          AI Provider Priority Configuration${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}Current Priority Order:${NC}"
    echo ""
    
    local index=1
    for provider in "${CURRENT_PRIORITY[@]}"; do
        local status=$(get_status_symbol "$provider")
        local name="${PROVIDER_NAMES[$provider]}"
        printf "  ${CYAN}%2d.${NC} %s %-30s %s\n" "$index" "$status" "$name" "(${provider})"
        ((index++))
    done
    
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${GREEN}✓${NC} = Installed    ${RED}✗${NC} = Not Installed"
    echo ""
}

# Interactive TUI to reorder providers
interactive_reorder() {
    while true; do
        show_current_config
        
        echo -e "${YELLOW}Options:${NC}"
        echo "  1-${#CURRENT_PRIORITY[@]}) Move provider to top priority"
        echo "  r) Reset to defaults"
        echo "  s) Save and exit"
        echo "  q) Quit without saving"
        echo ""
        read -p "Enter your choice: " choice
        
        case "$choice" in
            [1-9]|[1-9][0-9])
                if [ "$choice" -ge 1 ] && [ "$choice" -le ${#CURRENT_PRIORITY[@]} ]; then
                    # Move selected provider to top
                    local selected_provider="${CURRENT_PRIORITY[$((choice - 1))]}"
                    
                    # Remove from current position
                    unset 'CURRENT_PRIORITY[$((choice - 1))]'
                    CURRENT_PRIORITY=("${CURRENT_PRIORITY[@]}")
                    
                    # Insert at top
                    CURRENT_PRIORITY=("$selected_provider" "${CURRENT_PRIORITY[@]}")
                    
                    log_success "Moved ${PROVIDER_NAMES[$selected_provider]} to top priority"
                    sleep 1
                else
                    log_error "Invalid selection"
                    sleep 1
                fi
                ;;
            r|R)
                CURRENT_PRIORITY=("${DEFAULT_PROVIDERS[@]}")
                log_success "Reset to default priority order"
                sleep 1
                ;;
            s|S)
                save_priority_config
                echo ""
                log_success "Configuration saved!"
                sleep 1
                return 0
                ;;
            q|Q)
                log_info "Exiting without saving"
                return 1
                ;;
            *)
                log_error "Invalid choice"
                sleep 1
                ;;
        esac
    done
}

# Advanced TUI with swap functionality
advanced_reorder() {
    while true; do
        show_current_config
        
        echo -e "${YELLOW}Advanced Options:${NC}"
        echo "  m <from> <to>  - Move provider (e.g., 'm 3 1' moves 3rd to 1st)"
        echo "  s <a> <b>      - Swap two providers (e.g., 's 1 2')"
        echo "  t <num>        - Move provider to top (e.g., 't 3')"
        echo "  r              - Reset to defaults"
        echo "  save           - Save and exit"
        echo "  quit           - Quit without saving"
        echo ""
        read -p "Command: " cmd arg1 arg2
        
        case "$cmd" in
            m|M)
                if [[ "$arg1" =~ ^[0-9]+$ ]] && [[ "$arg2" =~ ^[0-9]+$ ]]; then
                    local from=$((arg1 - 1))
                    local to=$((arg2 - 1))
                    
                    if [ "$from" -ge 0 ] && [ "$from" -lt ${#CURRENT_PRIORITY[@]} ] && \
                       [ "$to" -ge 0 ] && [ "$to" -lt ${#CURRENT_PRIORITY[@]} ]; then
                        local provider="${CURRENT_PRIORITY[$from]}"
                        
                        # Remove from current position
                        unset "CURRENT_PRIORITY[$from]"
                        CURRENT_PRIORITY=("${CURRENT_PRIORITY[@]}")
                        
                        # Insert at new position
                        CURRENT_PRIORITY=("${CURRENT_PRIORITY[@]:0:$to}" "$provider" "${CURRENT_PRIORITY[@]:$to}")
                        
                        log_success "Moved ${PROVIDER_NAMES[$provider]} from position $arg1 to $arg2"
                        sleep 1
                    else
                        log_error "Invalid positions"
                        sleep 1
                    fi
                else
                    log_error "Usage: m <from> <to>"
                    sleep 1
                fi
                ;;
            s|S)
                if [[ "$arg1" =~ ^[0-9]+$ ]] && [[ "$arg2" =~ ^[0-9]+$ ]]; then
                    local pos1=$((arg1 - 1))
                    local pos2=$((arg2 - 1))
                    
                    if [ "$pos1" -ge 0 ] && [ "$pos1" -lt ${#CURRENT_PRIORITY[@]} ] && \
                       [ "$pos2" -ge 0 ] && [ "$pos2" -lt ${#CURRENT_PRIORITY[@]} ]; then
                        local temp="${CURRENT_PRIORITY[$pos1]}"
                        CURRENT_PRIORITY[$pos1]="${CURRENT_PRIORITY[$pos2]}"
                        CURRENT_PRIORITY[$pos2]="$temp"
                        
                        log_success "Swapped positions $arg1 and $arg2"
                        sleep 1
                    else
                        log_error "Invalid positions"
                        sleep 1
                    fi
                else
                    log_error "Usage: s <a> <b>"
                    sleep 1
                fi
                ;;
            t|T)
                if [[ "$arg1" =~ ^[0-9]+$ ]]; then
                    local pos=$((arg1 - 1))
                    
                    if [ "$pos" -ge 0 ] && [ "$pos" -lt ${#CURRENT_PRIORITY[@]} ]; then
                        local provider="${CURRENT_PRIORITY[$pos]}"
                        
                        # Remove from current position
                        unset "CURRENT_PRIORITY[$pos]"
                        CURRENT_PRIORITY=("${CURRENT_PRIORITY[@]}")
                        
                        # Insert at top
                        CURRENT_PRIORITY=("$provider" "${CURRENT_PRIORITY[@]}")
                        
                        log_success "Moved ${PROVIDER_NAMES[$provider]} to top priority"
                        sleep 1
                    else
                        log_error "Invalid position"
                        sleep 1
                    fi
                else
                    log_error "Usage: t <num>"
                    sleep 1
                fi
                ;;
            r|R)
                CURRENT_PRIORITY=("${DEFAULT_PROVIDERS[@]}")
                log_success "Reset to default priority order"
                sleep 1
                ;;
            save)
                save_priority_config
                echo ""
                log_success "Configuration saved!"
                sleep 1
                return 0
                ;;
            quit)
                log_info "Exiting without saving"
                return 1
                ;;
            *)
                log_error "Unknown command. Try: m, s, t, r, save, quit"
                sleep 1
                ;;
        esac
    done
}

# Show help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Configure AI provider priority order for workBenches.

Options:
  -h, --help           Show this help message
  -s, --show           Show current configuration
  -i, --interactive    Interactive simple mode (default)
  -a, --advanced       Advanced mode with more options
  --reset              Reset to default priorities

Examples:
  $0                   # Interactive configuration
  $0 --show            # Show current settings
  $0 --advanced        # Advanced configuration mode
  $0 --reset           # Reset to defaults

Default Priority Order:
EOF
    for i in "${!DEFAULT_PROVIDERS[@]}"; do
        local provider="${DEFAULT_PROVIDERS[$i]}"
        echo "  $((i + 1)). ${PROVIDER_NAMES[$provider]} (${provider})"
    done
}

# Main function
main() {
    # Load current configuration
    load_priority_config
    
    case "${1:-}" in
        -h|--help)
            show_help
            ;;
        -s|--show)
            show_current_config
            echo -e "${CYAN}Configuration file:${NC} $PRIORITY_CONFIG"
            echo ""
            ;;
        --reset)
            CURRENT_PRIORITY=("${DEFAULT_PROVIDERS[@]}")
            save_priority_config
            log_success "Reset to default priority order"
            ;;
        -a|--advanced)
            advanced_reorder
            ;;
        -i|--interactive|"")
            interactive_reorder
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Run '$0 --help' for usage information"
            exit 1
            ;;
    esac
}

# Run main
main "$@"
