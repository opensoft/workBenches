#!/bin/bash

# Claude Session Helper
# Provides functions to read and validate Claude session tokens from ~/.claude/config.json

CLAUDE_CONFIG="$HOME/.claude/config.json"

# Get Claude session key
get_claude_session_key() {
    if [ ! -f "$CLAUDE_CONFIG" ]; then
        return 1
    fi
    
    if command -v jq &> /dev/null; then
        jq -r '.sessionKey // empty' "$CLAUDE_CONFIG" 2>/dev/null
    else
        # Fallback parsing without jq
        grep -o '"sessionKey"[[:space:]]*:[[:space:]]*"[^"]*"' "$CLAUDE_CONFIG" 2>/dev/null | cut -d'"' -f4
    fi
}

# Check if Claude session is configured
has_claude_session() {
    [ -f "$CLAUDE_CONFIG" ] && [ -n "$(get_claude_session_key)" ]
}

# Get session creation time
get_session_created_at() {
    if [ ! -f "$CLAUDE_CONFIG" ]; then
        return 1
    fi
    
    if command -v jq &> /dev/null; then
        jq -r '.createdAt // empty' "$CLAUDE_CONFIG" 2>/dev/null
    fi
}

# Export session key as environment variable
export_claude_session() {
    local session_key
    session_key=$(get_claude_session_key)
    
    if [ -n "$session_key" ]; then
        export CLAUDE_SESSION_KEY="$session_key"
        return 0
    else
        return 1
    fi
}

# Show session info
show_claude_session_info() {
    if ! has_claude_session; then
        echo "No Claude session configured."
        echo "Run: ./scripts/setup-workbenches.sh to set up Claude session"
        return 1
    fi
    
    local created_at
    created_at=$(get_session_created_at)
    
    echo "Claude Session Status:"
    echo "  ✓ Session key configured"
    echo "  📁 Location: $CLAUDE_CONFIG"
    if [ -n "$created_at" ]; then
        echo "  📅 Created: $created_at"
    fi
}

# Main function for standalone usage
main() {
    case "${1:-}" in
        "get"|"key")
            get_claude_session_key
            ;;
        "check"|"has")
            if has_claude_session; then
                echo "Claude session is configured"
                exit 0
            else
                echo "No Claude session configured"
                exit 1
            fi
            ;;
        "export")
            if export_claude_session; then
                echo "Claude session key exported as CLAUDE_SESSION_KEY"
                exit 0
            else
                echo "Failed to export Claude session key"
                exit 1
            fi
            ;;
        "info"|"status")
            show_claude_session_info
            ;;
        "help"|"-h"|"--help"|"")
            echo "Usage: $0 <command>"
            echo ""
            echo "Commands:"
            echo "  get, key      - Get the Claude session key"
            echo "  check, has    - Check if Claude session is configured"
            echo "  export        - Export session key as CLAUDE_SESSION_KEY env var"
            echo "  info, status  - Show session information"
            echo "  help          - Show this help message"
            echo ""
            echo "Source this file to use functions in other scripts:"
            echo "  source $0"
            ;;
        *)
            echo "Unknown command: $1"
            echo "Run '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Only run main if script is executed directly (not sourced)
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
