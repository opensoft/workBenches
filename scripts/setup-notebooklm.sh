#!/bin/bash

# NotebookLM Setup Script
# Installs NotebookLM CLI tools on the HOST (not in containers),
# authenticates with Google, and syncs credentials for the MCP server.
#
# Supports multiple Google accounts via named profiles.
#
# Usage:
#   ./setup-notebooklm.sh                  # Interactive setup
#   ./setup-notebooklm.sh login [profile]  # Login a specific profile
#   ./setup-notebooklm.sh sync             # Sync cookies to MCP profiles
#   ./setup-notebooklm.sh status           # Check auth status
#   ./setup-notebooklm.sh setup-mcp        # Configure MCP for AI tools

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Paths
NOTEBOOKLM_BASE="$HOME/.notebooklm"
NLM_MCP_BASE="$HOME/.notebooklm-mcp-cli"

# ========================================
# HELPERS
# ========================================

log_info()  { echo -e "${GREEN}✓${NC} $*"; }
log_warn()  { echo -e "${YELLOW}⚠${NC} $*"; }
log_error() { echo -e "${RED}✗${NC} $*"; }
log_step()  { echo -e "\n${BOLD}${CYAN}$*${NC}"; }

# ========================================
# INSTALL PREREQUISITES
# ========================================

install_prerequisites() {
    log_step "Checking prerequisites..."

    local needs_install=false

    # Check uv
    if command -v uv &>/dev/null; then
        log_info "uv: $(uv --version)"
    else
        log_error "uv not found. Install from https://docs.astral.sh/uv/"
        exit 1
    fi

    # Check notebooklm-py
    if command -v notebooklm &>/dev/null; then
        log_info "notebooklm-py: installed"
    else
        log_warn "notebooklm-py not found, installing..."
        uv tool install "notebooklm-py[browser]"
        needs_install=true
    fi

    # Check playwright chromium
    if [ -d "$HOME/.cache/ms-playwright" ] && find "$HOME/.cache/ms-playwright" -name "chromium*" -type d 2>/dev/null | grep -q .; then
        log_info "Playwright Chromium: installed"
    else
        log_warn "Playwright Chromium not found, installing..."
        uv tool run playwright install chromium
        needs_install=true
    fi

    # Check nlm (notebooklm-mcp-cli)
    if command -v nlm &>/dev/null; then
        log_info "notebooklm-mcp-cli (nlm): installed"
    else
        log_warn "nlm not found, installing..."
        uv tool install notebooklm-mcp-cli
        needs_install=true
    fi

    if [ "$needs_install" = true ]; then
        echo ""
        log_info "Prerequisites installed successfully"
    fi
}

# ========================================
# LOGIN
# ========================================

do_login() {
    local profile="${1:-default}"
    local notebooklm_home="$NOTEBOOKLM_BASE"

    if [ "$profile" != "default" ]; then
        notebooklm_home="$NOTEBOOKLM_BASE-$profile"
    fi

    log_step "Logging in profile: $profile"
    echo "  Auth dir: $notebooklm_home"
    echo ""
    echo "A browser window will open. Log in with your Google account"
    echo "that has access to NotebookLM, then close the browser."
    echo ""

    NOTEBOOKLM_HOME="$notebooklm_home" notebooklm login

    if [ -f "$notebooklm_home/storage_state.json" ]; then
        log_info "Login successful for profile: $profile"
        sync_profile "$profile"
    else
        log_error "Login failed — no storage_state.json found"
        return 1
    fi
}

# ========================================
# SYNC COOKIES
# ========================================

sync_profile() {
    local profile="${1:-default}"
    local notebooklm_home="$NOTEBOOKLM_BASE"

    if [ "$profile" != "default" ]; then
        notebooklm_home="$NOTEBOOKLM_BASE-$profile"
    fi

    local source="$notebooklm_home/storage_state.json"
    local dest_dir="$NLM_MCP_BASE/profiles/$profile"
    local dest="$dest_dir/cookies.json"

    if [ ! -f "$source" ]; then
        log_error "No auth found for profile '$profile' at $source"
        return 1
    fi

    mkdir -p "$dest_dir"

    # Extract cookies array from storage_state.json → cookies.json
    python3 -c "
import json
with open('$source') as f:
    state = json.load(f)
with open('$dest', 'w') as f:
    json.dump(state['cookies'], f, indent=2)
print(f'Synced {len(state[\"cookies\"])} cookies')
"

    log_info "Synced profile '$profile': $source → $dest"
}

sync_all() {
    log_step "Syncing all profiles to MCP..."

    local found=false

    # Sync default profile
    if [ -f "$NOTEBOOKLM_BASE/storage_state.json" ]; then
        sync_profile "default"
        found=true
    fi

    # Sync named profiles (directories named .notebooklm-<profile>)
    for dir in "$HOME"/.notebooklm-*/; do
        [ -d "$dir" ] || continue
        # Skip the mcp-cli directory
        [ "$dir" = "$NLM_MCP_BASE/" ] && continue
        local name=$(basename "$dir" | sed 's/^\.notebooklm-//')
        if [ -f "$dir/storage_state.json" ]; then
            sync_profile "$name"
            found=true
        fi
    done

    if [ "$found" = false ]; then
        log_warn "No authenticated profiles found. Run: $0 login [profile]"
    fi
}

# ========================================
# STATUS
# ========================================

show_status() {
    log_step "NotebookLM Authentication Status"

    echo ""
    printf "  %-15s %-12s %-12s %s\n" "Profile" "CLI Auth" "MCP Auth" "Location"
    printf "  %-15s %-12s %-12s %s\n" "-------" "--------" "--------" "--------"

    # Check default
    check_profile_status "default" "$NOTEBOOKLM_BASE"

    # Check named profiles
    for dir in "$HOME"/.notebooklm-*/; do
        [ -d "$dir" ] || continue
        [ "$dir" = "$NLM_MCP_BASE/" ] && continue
        local name=$(basename "$dir" | sed 's/^\.notebooklm-//')
        check_profile_status "$name" "$dir"
    done

    echo ""

    # Check MCP tool config
    log_step "MCP Server Configuration"
    if command -v nlm &>/dev/null; then
        nlm setup list 2>/dev/null || log_warn "Could not check MCP config"
    else
        log_warn "nlm not installed"
    fi
}

check_profile_status() {
    local name="$1"
    local cli_dir="$2"
    local mcp_dir="$NLM_MCP_BASE/profiles/$name"

    local cli_status="${RED}✗${NC}"
    local mcp_status="${RED}✗${NC}"

    if [ -f "$cli_dir/storage_state.json" ]; then
        cli_status="${GREEN}✓${NC}"
    fi

    if [ -f "$mcp_dir/cookies.json" ]; then
        mcp_status="${GREEN}✓${NC}"
    fi

    printf "  %-15s %-20b %-20b %s\n" "$name" "$cli_status" "$mcp_status" "$cli_dir"
}

# ========================================
# SETUP MCP FOR AI TOOLS
# ========================================

setup_mcp() {
    log_step "Configuring MCP server for AI tools..."

    if ! command -v nlm &>/dev/null; then
        log_error "nlm not installed. Run: $0 (to install prerequisites)"
        return 1
    fi

    # Check auth first
    if ! nlm login --check &>/dev/null; then
        log_error "Not authenticated. Run: $0 login"
        return 1
    fi

    local tools=("claude-code" "gemini")

    for tool in "${tools[@]}"; do
        echo ""
        if nlm setup add "$tool" 2>/dev/null; then
            log_info "Configured MCP for: $tool"
        else
            log_warn "Failed to configure MCP for: $tool"
        fi
    done

    echo ""
    log_info "MCP configuration complete. Restart your AI tools to activate."
}

# ========================================
# INTERACTIVE SETUP
# ========================================

interactive_setup() {
    echo ""
    echo -e "${BOLD}==========================================${NC}"
    echo -e "${BOLD}  NotebookLM Setup${NC}"
    echo -e "${BOLD}==========================================${NC}"
    echo ""
    echo "This script sets up NotebookLM CLI + MCP integration on your host."
    echo "Auth tokens are mounted into containers — no browser needed inside."
    echo ""

    # Step 1: Prerequisites
    install_prerequisites

    # Step 2: Ask about accounts
    log_step "Google Account Setup"
    echo ""
    echo "How many Google accounts do you use with NotebookLM?"
    echo "  1) One account (default)"
    echo "  2) Multiple accounts"
    echo ""
    read -p "Choice [1]: " account_choice
    account_choice="${account_choice:-1}"

    case "$account_choice" in
        1)
            do_login "default"
            ;;
        2)
            echo ""
            echo "Enter profile names (one per line, empty line to finish)."
            echo "Example: work, personal"
            echo ""
            while true; do
                read -p "Profile name (or Enter to finish): " pname
                [ -z "$pname" ] && break
                # Sanitize profile name
                pname=$(echo "$pname" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')
                do_login "$pname"
            done
            ;;
    esac

    # Step 3: Configure MCP
    echo ""
    read -p "Configure MCP server for AI tools (Claude Code, Gemini)? [Y/n]: " mcp_choice
    case "${mcp_choice:-Y}" in
        [Yy]* | "")
            setup_mcp
            ;;
    esac

    # Step 4: Summary
    echo ""
    show_status

    echo ""
    echo -e "${BOLD}Setup complete!${NC}"
    echo ""
    echo "Next steps:"
    echo "  - Rebuild containers to pick up the auth mounts"
    echo "  - Restart Claude Code / Gemini to activate MCP"
    echo "  - To re-auth: $0 login [profile]"
    echo "  - To check:   $0 status"
}

# ========================================
# MAIN
# ========================================

case "${1:-}" in
    login)
        install_prerequisites
        do_login "${2:-default}"
        ;;
    sync)
        sync_all
        ;;
    status)
        show_status
        ;;
    setup-mcp)
        setup_mcp
        ;;
    help|--help|-h)
        echo "Usage: $0 [command] [args]"
        echo ""
        echo "Commands:"
        echo "  (none)          Interactive setup"
        echo "  login [profile] Login a Google account (default: 'default')"
        echo "  sync            Sync all CLI cookies to MCP profiles"
        echo "  status          Show auth status for all profiles"
        echo "  setup-mcp       Configure MCP server for AI tools"
        echo "  help            Show this help"
        echo ""
        echo "Multi-account:"
        echo "  $0 login work      # Auth with work account"
        echo "  $0 login personal  # Auth with personal account"
        echo "  $0 sync            # Sync all to MCP"
        ;;
    *)
        interactive_setup
        ;;
esac
