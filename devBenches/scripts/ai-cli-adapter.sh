#!/bin/bash
# AI CLI Adapter - Provider detection and unified interface
# Version: 1.0.0
# Supports: Codex, Claude Code, Gemini CLI with subscription auth
# Shared across all bench types (frappe, flutter, dotnet)

# Prevent double-sourcing
if [ -n "$_AI_CLI_ADAPTER_SOURCED" ]; then
    return 0
fi
_AI_CLI_ADAPTER_SOURCED=1

# CLI detection status codes
readonly CLI_AUTHENTICATED="authenticated"
readonly CLI_INSTALLED_NOT_AUTH="installed_not_authenticated"
readonly CLI_NOT_INSTALLED="not_installed"

# Load user-configured provider priority or use defaults
PRIORITY_CONFIG="${HOME}/.config/workbenches/ai-provider-priority.conf"
if [ -f "$PRIORITY_CONFIG" ]; then
    mapfile -t PROVIDER_PRIORITY < "$PRIORITY_CONFIG"
else
    # Default provider priority order
    PROVIDER_PRIORITY=("codex" "claude" "gemini" "copilot" "grok" "meta" "kimi2" "deepseek")
fi

# Timeout for CLI probes (seconds)
readonly PROBE_TIMEOUT=10

# ============================================================================
# CLI Detection Functions
# ============================================================================

# Check if Codex CLI is installed and authenticated
check_codex_status() {
    # Check if CLI is installed
    if ! command -v codex >/dev/null 2>&1; then
        echo "$CLI_NOT_INSTALLED"
        return 1
    fi
    
    # Check if config directory exists
    if [ ! -d "$HOME/.codex" ]; then
        echo "$CLI_INSTALLED_NOT_AUTH"
        return 1
    fi
    
    # Check for OAuth token in auth.json
    if [ -f "$HOME/.codex/auth.json" ]; then
        # Verify the auth file is not empty and contains tokens
        if [ -s "$HOME/.codex/auth.json" ] && grep -q '"tokens"' "$HOME/.codex/auth.json" 2>/dev/null; then
            echo "$CLI_AUTHENTICATED"
            return 0
        fi
    fi
    
    echo "$CLI_INSTALLED_NOT_AUTH"
    return 1
}

# Check if Claude Code CLI is installed and authenticated
check_claude_status() {
    # Check if CLI is installed
    if ! command -v claude >/dev/null 2>&1; then
        echo "$CLI_NOT_INSTALLED"
        return 1
    fi
    
    # Check if config directory exists
    if [ ! -d "$HOME/.claude" ]; then
        echo "$CLI_INSTALLED_NOT_AUTH"
        return 1
    fi
    
    # Two-step verification: Force subscription mode
    # Run in subshell with ANTHROPIC_API_KEY explicitly unset
    local test_output
    if test_output=$(
        unset ANTHROPIC_API_KEY
        timeout "$PROBE_TIMEOUT" claude -p "test" 2>&1
    ); then
        # Check if command succeeded without login prompt
        if ! echo "$test_output" | grep -qi "login\|authenticate\|sign in" 2>/dev/null; then
            echo "$CLI_AUTHENTICATED"
            return 0
        fi
    fi
    
    echo "$CLI_INSTALLED_NOT_AUTH"
    return 1
}

# Check if Gemini CLI is installed and authenticated
check_gemini_status() {
    # Check if CLI is installed
    if ! command -v gemini >/dev/null 2>&1; then
        echo "$CLI_NOT_INSTALLED"
        return 1
    fi
    
    # Check if config directory exists
    if [ ! -d "$HOME/.gemini" ]; then
        echo "$CLI_INSTALLED_NOT_AUTH"
        return 1
    fi
    
    # Check for OAuth credentials file - if it exists, assume authenticated
    # Note: In WSL, the OAuth callback can fail, so we trust the file existence
    # rather than probing which may trigger re-authentication
    if [ -f "$HOME/.gemini/oauth_creds.json" ]; then
        # Verify the credentials file is not empty and looks valid
        if [ -s "$HOME/.gemini/oauth_creds.json" ]; then
            echo "$CLI_AUTHENTICATED"
            return 0
        fi
    fi
    
    echo "$CLI_INSTALLED_NOT_AUTH"
    return 1
}

# Check if Grok CLI is installed and authenticated
check_grok_status() {
    # Check if CLI is installed
    if ! command -v grok >/dev/null 2>&1; then
        echo "$CLI_NOT_INSTALLED"
        return 1
    fi
    
    # Check if config directory exists with API key
    if [ -f "$HOME/.grok/api-key" ]; then
        # Verify the key file is not empty
        if [ -s "$HOME/.grok/api-key" ]; then
            echo "$CLI_AUTHENTICATED"
            return 0
        fi
    fi
    
    echo "$CLI_INSTALLED_NOT_AUTH"
    return 1
}

# Check if Copilot CLI is installed and authenticated
check_copilot_status() {
    # Check if CLI is installed (try both command names)
    if ! command -v copilot >/dev/null 2>&1 && ! command -v github-copilot-cli >/dev/null 2>&1; then
        echo "$CLI_NOT_INSTALLED"
        return 1
    fi
    
    # Check for CLI credentials in ~/.copilot-cli/
    if [ -d "$HOME/.copilot-cli" ]; then
        # Check if credentials directory has OAuth tokens
        if [ -n "$(find "$HOME/.copilot-cli" -type f 2>/dev/null | head -1)" ]; then
            echo "$CLI_AUTHENTICATED"
            return 0
        fi
    fi
    
    # Fallback: Check gh copilot extension auth
    if [ -d "$HOME/.config/gh" ]; then
        if command -v gh >/dev/null 2>&1; then
            if gh auth status >/dev/null 2>&1; then
                echo "$CLI_AUTHENTICATED"
                return 0
            fi
        fi
    fi
    
    echo "$CLI_INSTALLED_NOT_AUTH"
    return 1
}

# Generic check for other providers (meta, kimi2, deepseek)
check_generic_cli_status() {
    local provider="$1"
    local cli_cmd="$2"
    
    # Check if CLI is installed
    if ! command -v "$cli_cmd" >/dev/null 2>&1; then
        echo "$CLI_NOT_INSTALLED"
        return 1
    fi
    
    # Check if config directory exists
    if [ -d "$HOME/.${provider}" ]; then
        # Assume authenticated if config dir exists
        echo "$CLI_AUTHENTICATED"
        return 0
    fi
    
    echo "$CLI_INSTALLED_NOT_AUTH"
    return 1
}

# ============================================================================
# Provider Selection Logic
# ============================================================================

# Get status of all CLI providers
get_all_cli_status() {
    local -A cli_status_map
    
    for provider in "${PROVIDER_PRIORITY[@]}"; do
        case "$provider" in
            codex)
                cli_status_map["codex"]=$(check_codex_status)
                ;;
            claude)
                cli_status_map["claude"]=$(check_claude_status)
                ;;
            gemini)
                cli_status_map["gemini"]=$(check_gemini_status)
                ;;
            grok)
                cli_status_map["grok"]=$(check_grok_status)
                ;;
            copilot)
                cli_status_map["copilot"]=$(check_copilot_status)
                ;;
            meta)
                cli_status_map["meta"]=$(check_generic_cli_status "meta" "llama")
                ;;
            kimi2)
                cli_status_map["kimi2"]=$(check_generic_cli_status "kimi" "kimi")
                ;;
            deepseek)
                cli_status_map["deepseek"]=$(check_generic_cli_status "deepseek" "deepseek")
                ;;
        esac
    done
    
    # Output as key=value pairs
    for provider in "${!cli_status_map[@]}"; do
        echo "$provider=${cli_status_map[$provider]}"
    done
}

# Get first authenticated CLI provider
get_authenticated_cli() {
    for provider in "${PROVIDER_PRIORITY[@]}"; do
        local cli_status
        case "$provider" in
            codex)
                cli_status=$(check_codex_status)
                ;;
            claude)
                cli_status=$(check_claude_status)
                ;;
            gemini)
                cli_status=$(check_gemini_status)
                ;;
            grok)
                cli_status=$(check_grok_status)
                ;;
            copilot)
                cli_status=$(check_copilot_status)
                ;;
            meta)
                cli_status=$(check_generic_cli_status "meta" "llama")
                ;;
            kimi2)
                cli_status=$(check_generic_cli_status "kimi" "kimi")
                ;;
            deepseek)
                cli_status=$(check_generic_cli_status "deepseek" "deepseek")
                ;;
        esac
        
        if [ "$cli_status" = "$CLI_AUTHENTICATED" ]; then
            echo "$provider"
            return 0
        fi
    done
    
    return 1
}

# Get list of installed but not authenticated CLIs
get_unauthenticated_clis() {
    local -a unauthenticated
    
    for provider in "${PROVIDER_PRIORITY[@]}"; do
        local cli_status
        case "$provider" in
            codex)
                cli_status=$(check_codex_status)
                ;;
            claude)
                cli_status=$(check_claude_status)
                ;;
            gemini)
                cli_status=$(check_gemini_status)
                ;;
            grok)
                cli_status=$(check_grok_status)
                ;;
            copilot)
                cli_status=$(check_copilot_status)
                ;;
            meta)
                cli_status=$(check_generic_cli_status "meta" "llama")
                ;;
            kimi2)
                cli_status=$(check_generic_cli_status "kimi" "kimi")
                ;;
            deepseek)
                cli_status=$(check_generic_cli_status "deepseek" "deepseek")
                ;;
        esac
        
        if [ "$cli_status" = "$CLI_INSTALLED_NOT_AUTH" ]; then
            unauthenticated+=("$provider")
        fi
    done
    
    if [ ${#unauthenticated[@]} -gt 0 ]; then
        printf '%s\n' "${unauthenticated[@]}"
        return 0
    fi
    
    return 1
}

# ============================================================================
# User Interaction
# ============================================================================

# Prompt user to authenticate CLI tools
prompt_cli_authentication() {
    local -a unauthenticated
    mapfile -t unauthenticated < <(get_unauthenticated_clis)
    
    if [ ${#unauthenticated[@]} -eq 0 ]; then
        return 1
    fi
    
    echo ""
    echo -e "\033[1;33m⚠ AI CLI tools detected but not authenticated\033[0m"
    echo ""
    echo "Found installed:"
    for provider in "${unauthenticated[@]}"; do
        echo "  • $provider"
    done
    echo ""
    echo "Authentication commands:"
    for provider in "${unauthenticated[@]}"; do
        case "$provider" in
            codex)
                echo "  • Codex: \033[0;36mcodex login\033[0m"
                ;;
            claude)
                echo "  • Claude Code: \033[0;36mclaude\033[0m (will prompt for login)"
                ;;
            gemini)
                echo "  • Gemini: \033[0;36mgemini\033[0m (will prompt for login)"
                ;;
        esac
    done
    echo ""
    echo -ne "\033[1;33mWould you like to authenticate now? [Y/n]: \033[0m"
    read -r response
    
    if [[ ! "$response" =~ ^[nN] ]]; then
        echo ""
        echo "Please authenticate in another terminal, then press Enter to continue..."
        echo "(Or Ctrl+C to cancel)"
        read -r
        
        # Re-check authentication
        local authenticated
        authenticated=$(get_authenticated_cli)
        if [ -n "$authenticated" ]; then
            echo -e "\033[0;32m✓ Successfully authenticated with $authenticated\033[0m"
            echo "$authenticated"
            return 0
        else
            echo -e "\033[0;33m⚠ Authentication not detected, will try fallback methods\033[0m"
            return 1
        fi
    else
        echo ""
        echo -e "\033[0;34mℹ Will try API key fallback or manual detection\033[0m"
        return 1
    fi
}

# ============================================================================
# Unified Call Interface
# ============================================================================

# Call AI CLI with unified interface
call_ai_cli() {
    local prompt="$1"
    local output_format="${2:-text}"
    
    # Get authenticated provider
    local provider
    provider=$(get_authenticated_cli)
    
    if [ -z "$provider" ]; then
        echo "Error: No authenticated CLI provider available" >&2
        return 1
    fi
    
    case "$provider" in
        codex)
            if [ "$output_format" = "json" ]; then
                codex exec --output-last-message --json "$prompt"
            else
                codex exec --output-last-message "$prompt"
            fi
            ;;
        claude)
            # Ensure ANTHROPIC_API_KEY is unset for subscription mode
            (
                unset ANTHROPIC_API_KEY
                if [ "$output_format" = "json" ]; then
                    claude -p "$prompt" --output-format json
                else
                    claude -p "$prompt"
                fi
            )
            ;;
        gemini)
            if [ "$output_format" = "json" ]; then
                gemini -p "$prompt" --output json
            else
                gemini -p "$prompt"
            fi
            ;;
        *)
            echo "Error: Unknown provider: $provider" >&2
            return 1
            ;;
    esac
}

# ============================================================================
# Main Provider Selection
# ============================================================================

# Select best available AI provider (CLI first, then fallback)
# Returns: provider_name|provider_type (e.g., "codex|cli" or "none|none")
select_ai_provider() {
    # First: Try to get authenticated CLI
    local cli_provider
    cli_provider=$(get_authenticated_cli)
    
    if [ -n "$cli_provider" ]; then
        echo "${cli_provider}|cli"
        return 0
    fi
    
    # Second: Check if CLIs are installed but not authenticated
    if get_unauthenticated_clis >/dev/null 2>&1; then
        # Prompt user to authenticate
        local authenticated
        if authenticated=$(prompt_cli_authentication); then
            echo "${authenticated}|cli"
            return 0
        fi
        # User declined, will fall back
    fi
    
    # No CLI available
    echo "none|none"
    return 1
}
