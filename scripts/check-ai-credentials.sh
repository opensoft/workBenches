#!/bin/bash

# AI Credentials Status Checker
# Checks all configured AI services and shows their status

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_CONFIG="$HOME/.claude/config.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Source the Claude helper
source "$SCRIPT_DIR/claude-session-helper.sh" 2>/dev/null || true

# Check if Claude session exists and is valid
check_claude_session() {
    if [ ! -f "$CLAUDE_CONFIG" ]; then
        echo "not_configured"
        return
    fi
    
    local session_key
    session_key=$(get_claude_session_key 2>/dev/null)
    
    if [ -z "$session_key" ]; then
        echo "invalid"
        return
    fi
    
    # Basic format validation
    if [[ "$session_key" =~ ^sk-ant-sid ]]; then
        echo "configured"
    else
        echo "invalid_format"
    fi
}

# Check if OpenAI API key is configured
check_openai_key() {
    if [ -z "$OPENAI_API_KEY" ]; then
        echo "not_configured"
        return
    fi
    
    if [[ "$OPENAI_API_KEY" =~ ^sk- ]]; then
        echo "configured"
    else
        echo "invalid_format"
    fi
}

# Check if Anthropic API key is configured
check_anthropic_key() {
    if [ -z "$ANTHROPIC_API_KEY" ]; then
        echo "not_configured"
        return
    fi
    
    if [[ "$ANTHROPIC_API_KEY" =~ ^sk- ]]; then
        echo "configured"
    else
        echo "invalid_format"
    fi
}

# Get status icon and color
get_status_display() {
    local status="$1"
    case "$status" in
        "configured")
            echo -e "${GREEN}✓ Configured${NC}"
            ;;
        "not_configured")
            echo -e "${RED}✗ Not Configured${NC}"
            ;;
        "invalid"|"invalid_format")
            echo -e "${RED}✗ Invalid Format${NC}"
            ;;
        *)
            echo -e "${YELLOW}? Unknown${NC}"
            ;;
    esac
}

# Get location info
get_location_info() {
    local service="$1"
    case "$service" in
        "claude_session")
            if [ -f "$CLAUDE_CONFIG" ]; then
                echo "$CLAUDE_CONFIG"
            else
                echo "${RED}Not found${NC}"
            fi
            ;;
        "openai")
            if [ -n "$OPENAI_API_KEY" ]; then
                echo "Environment: \$OPENAI_API_KEY"
            else
                echo "${RED}Not set${NC}"
            fi
            ;;
        "anthropic")
            if [ -n "$ANTHROPIC_API_KEY" ]; then
                echo "Environment: \$ANTHROPIC_API_KEY"
            else
                echo "${RED}Not set${NC}"
            fi
            ;;
    esac
}

# Show credentials status
show_credentials_status() {
    echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
    echo -e "${CYAN}       AI Credentials Status Report${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
    echo ""
    
    # Check each service
    local claude_status=$(check_claude_session)
    local openai_status=$(check_openai_key)
    local anthropic_status=$(check_anthropic_key)
    
    # Display Claude Session
    echo -e "${BLUE}1. Claude Session Token${NC}"
    echo -e "   Status:   $(get_status_display "$claude_status")"
    echo -e "   Location: $(get_location_info "claude_session")"
    if [ "$claude_status" = "configured" ] && [ -f "$CLAUDE_CONFIG" ]; then
        local created_at=$(get_session_created_at 2>/dev/null)
        if [ -n "$created_at" ]; then
            echo -e "   Created:  ${created_at}"
        fi
    fi
    echo ""
    
    # Display OpenAI API Key
    echo -e "${BLUE}2. OpenAI API Key${NC}"
    echo -e "   Status:   $(get_status_display "$openai_status")"
    echo -e "   Location: $(get_location_info "openai")"
    if [ "$openai_status" = "configured" ]; then
        # Show first and last 4 chars of key
        local key_preview="${OPENAI_API_KEY:0:7}...${OPENAI_API_KEY: -4}"
        echo -e "   Key:      ${key_preview}"
    fi
    echo ""
    
    # Display Anthropic API Key
    echo -e "${BLUE}3. Anthropic API Key (Claude API)${NC}"
    echo -e "   Status:   $(get_status_display "$anthropic_status")"
    echo -e "   Location: $(get_location_info "anthropic")"
    if [ "$anthropic_status" = "configured" ]; then
        # Show first and last 4 chars of key
        local key_preview="${ANTHROPIC_API_KEY:0:7}...${ANTHROPIC_API_KEY: -4}"
        echo -e "   Key:      ${key_preview}"
    fi
    echo ""
    
    echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
    
    # Summary
    local configured_count=0
    [ "$claude_status" = "configured" ] && ((configured_count++))
    [ "$openai_status" = "configured" ] && ((configured_count++))
    [ "$anthropic_status" = "configured" ] && ((configured_count++))
    
    echo ""
    if [ $configured_count -eq 0 ]; then
        echo -e "${RED}⚠️  No AI services configured${NC}"
        echo -e "   Run: ${CYAN}./scripts/setup-workbenches.sh${NC} to set up"
    elif [ $configured_count -eq 3 ]; then
        echo -e "${GREEN}✓ All AI services configured${NC}"
    else
        echo -e "${YELLOW}ℹ️  $configured_count of 3 services configured${NC}"
    fi
    echo ""
}

# Interactive menu to update credentials
interactive_update() {
    while true; do
        show_credentials_status
        
        echo ""
        echo -e "${YELLOW}Options:${NC}"
        echo "  1) Update Claude Session Token"
        echo "  2) Update OpenAI API Key"
        echo "  3) Update Anthropic API Key"
        echo "  4) Set up all services"
        echo "  5) Exit"
        echo ""
        read -p "Enter your choice (1-5): " choice
        
        case $choice in
            1)
                echo ""
                echo -e "${CYAN}Launching Claude session setup...${NC}"
                "$SCRIPT_DIR/setup-workbenches.sh" --claude-only 2>/dev/null || {
                    # Fallback if flag not supported - run full setup
                    echo -e "${YELLOW}Running full setup (select Claude option)...${NC}"
                    sleep 2
                    "$SCRIPT_DIR/setup-workbenches.sh"
                }
                ;;
            2)
                echo ""
                echo -e "${CYAN}OpenAI API Key Setup${NC}"
                echo "Get your API key from: https://platform.openai.com/api-keys"
                echo ""
                read -p "Enter your OpenAI API key (or 'skip' to skip): " new_key
                if [ "$new_key" != "skip" ] && [ -n "$new_key" ]; then
                    # Update in shell profile
                    update_env_key "OPENAI_API_KEY" "$new_key"
                    export OPENAI_API_KEY="$new_key"
                    echo -e "${GREEN}✓ OpenAI API key updated${NC}"
                fi
                echo ""
                read -p "Press Enter to continue..."
                ;;
            3)
                echo ""
                echo -e "${CYAN}Anthropic API Key Setup${NC}"
                echo "Get your API key from: https://console.anthropic.com/account/keys"
                echo ""
                read -p "Enter your Anthropic API key (or 'skip' to skip): " new_key
                if [ "$new_key" != "skip" ] && [ -n "$new_key" ]; then
                    # Update in shell profile
                    update_env_key "ANTHROPIC_API_KEY" "$new_key"
                    export ANTHROPIC_API_KEY="$new_key"
                    echo -e "${GREEN}✓ Anthropic API key updated${NC}"
                fi
                echo ""
                read -p "Press Enter to continue..."
                ;;
            4)
                echo ""
                echo -e "${CYAN}Launching full setup...${NC}"
                sleep 1
                "$SCRIPT_DIR/setup-workbenches.sh"
                ;;
            5)
                echo ""
                echo -e "${GREEN}Exiting...${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid choice. Please enter 1-5.${NC}"
                sleep 2
                ;;
        esac
        
        clear
    done
}

# Update environment variable in shell profile
update_env_key() {
    local key_name="$1"
    local key_value="$2"
    local shell_profile
    
    # Determine shell profile file
    if [ -n "$ZSH_VERSION" ]; then
        shell_profile="$HOME/.zshrc"
    elif [ -n "$BASH_VERSION" ]; then
        shell_profile="$HOME/.bashrc"
    else
        shell_profile="$HOME/.profile"
    fi
    
    # Check if key already exists in profile
    if grep -q "^export $key_name=" "$shell_profile" 2>/dev/null; then
        # Use sed to update the existing line
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS
            sed -i "" "s/^export $key_name=.*/export $key_name='$key_value'/" "$shell_profile"
        else
            # Linux
            sed -i "s/^export $key_name=.*/export $key_name='$key_value'/" "$shell_profile"
        fi
        echo -e "${BLUE}Updated $key_name in $shell_profile${NC}"
    else
        echo "" >> "$shell_profile"
        echo "# workBenches AI API Key" >> "$shell_profile"
        echo "export $key_name='$key_value'" >> "$shell_profile"
        echo -e "${BLUE}Added $key_name to $shell_profile${NC}"
    fi
    
    echo -e "${YELLOW}Note: Restart terminal or run 'source $shell_profile' to use the key in new sessions.${NC}"
}

# Main function
main() {
    case "${1:-}" in
        "status"|"check"|"")
            show_credentials_status
            ;;
        "interactive"|"update"|"menu"|"-i"|"--interactive")
            interactive_update
            ;;
        "help"|"-h"|"--help")
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  status, check        - Show credential status (default)"
            echo "  interactive, -i      - Interactive menu to update credentials"
            echo "  --interactive        - Same as -i"
            echo "  update, menu         - Alias for interactive"
            echo "  help, -h, --help     - Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                     # Show status"
            echo "  $0 status              # Show status"
            echo "  $0 -i                  # Interactive update menu"
            echo "  $0 --interactive       # Interactive update menu"
            echo "  $0 interactive         # Interactive update menu"
            ;;
        *)
            echo "Unknown command: $1"
            echo "Run '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Run main
main "$@"
