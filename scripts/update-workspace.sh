#!/bin/bash
# Intelligent workspace updater for workBenches
# Automatically detects workspace type and routes to the appropriate updater
# Supports: Frappe, Flutter, .NET, and other frameworks

set -e

# Script metadata
SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="update-workspace.sh"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Log functions
log_info() { echo -e "${BLUE}ℹ${NC} $*"; }
log_success() { echo -e "${GREEN}✓${NC} $*"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $*"; }
log_error() { echo -e "${RED}✗${NC} $*" >&2; }

die() {
    log_error "$*"
    exit 1
}

# Determine workBenches root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKBENCHES_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Check if we're in a project that has its own workspace management scripts
check_for_project_scripts() {
    local current_dir="$(pwd)"
    for ((i=0; i<5; i++)); do
        if [ -f "${current_dir}/scripts/update-frappe-workspace.sh" ] && [ -d "${current_dir}/workspaces" ]; then
            # Found a Frappe project with its own workspace scripts
            echo "${current_dir}/scripts/update-frappe-workspace.sh"
            return 0
        fi
        current_dir="$(dirname "$current_dir")"
    done
    return 1
}

# If we found a project-specific script, use it instead
if PROJECT_SCRIPT=$(check_for_project_scripts); then
    # Delegate to project-specific script
    exec "$PROJECT_SCRIPT" "$@"
fi

echo ""
echo -e "${BLUE}=========================================="
echo "Workspace Updater (Intelligent Router v${SCRIPT_VERSION})"
echo -e "==========================================${NC}"
echo ""

# Detect available workspace updaters
declare -A UPDATER_SCRIPTS
declare -a AVAILABLE_TYPES

# Check Frappe
if [ -f "${WORKBENCHES_ROOT}/devBenches/frappeBench/scripts/update-frappe-workspace.sh" ]; then
    AVAILABLE_TYPES+=("Frappe")
    UPDATER_SCRIPTS["Frappe"]="${WORKBENCHES_ROOT}/devBenches/frappeBench/scripts/update-frappe-workspace.sh"
fi

# Check Flutter (when available)
if [ -f "${WORKBENCHES_ROOT}/devBenches/flutterBench/scripts/update-flutter-workspace.sh" ]; then
    AVAILABLE_TYPES+=("Flutter")
    UPDATER_SCRIPTS["Flutter"]="${WORKBENCHES_ROOT}/devBenches/flutterBench/scripts/update-flutter-workspace.sh"
fi

# Check .NET (when available)
if [ -f "${WORKBENCHES_ROOT}/devBenches/dotnetBench/scripts/update-dotnet-workspace.sh" ]; then
    AVAILABLE_TYPES+=("DotNET")
    UPDATER_SCRIPTS["DotNET"]="${WORKBENCHES_ROOT}/devBenches/dotnetBench/scripts/update-dotnet-workspace.sh"
fi

# Check for AI support (three-tier: CLI -> API key -> Manual TUI)
AI_AVAILABLE=false
AI_PROVIDER_NAME=""
AI_PROVIDER_TYPE=""

if [ -f "${WORKBENCHES_ROOT}/devBenches/frappeBench/scripts/lib/ai-provider.sh" ]; then
    source "${WORKBENCHES_ROOT}/devBenches/frappeBench/scripts/lib/common.sh" 2>/dev/null || true
    source "${WORKBENCHES_ROOT}/devBenches/frappeBench/scripts/lib/ai-provider.sh" 2>/dev/null || true
    source "${WORKBENCHES_ROOT}/devBenches/frappeBench/scripts/lib/git-project.sh" 2>/dev/null || true
    
    if command -v get_primary_provider_with_cli >/dev/null 2>&1; then
        provider_result=$(get_primary_provider_with_cli 2>/dev/null) || true
        
        if [ -n "$provider_result" ]; then
            AI_PROVIDER_NAME=$(echo "$provider_result" | cut -d'|' -f1)
            AI_PROVIDER_TYPE=$(echo "$provider_result" | cut -d'|' -f2)
            
            if [ "$AI_PROVIDER_NAME" != "none" ]; then
                AI_AVAILABLE=true
                export AI_PROVIDER="$AI_PROVIDER_NAME"
                export AI_PROVIDER_TYPE="$AI_PROVIDER_TYPE"
                log_success "AI support available: $AI_PROVIDER_NAME (via $AI_PROVIDER_TYPE)"
            fi
        fi
    fi
fi

# If no AI available, use manual workspace type detection
if [ ! "$AI_AVAILABLE" = true ] && [ -f "${WORKBENCHES_ROOT}/devBenches/scripts/workspace-type-detector.sh" ]; then
    source "${WORKBENCHES_ROOT}/devBenches/scripts/workspace-type-detector.sh" 2>/dev/null || true
    log_info "AI not available - will use manual workspace type selection if needed"
fi

# If no available types, error out
if [ ${#AVAILABLE_TYPES[@]} -eq 0 ]; then
    die "No workspace updaters found in devBenches"
fi

# Try to auto-detect workspace type from current directory
SELECTED_TYPE=""
if command -v find_git_root >/dev/null 2>&1 && command -v is_frappe_project >/dev/null 2>&1; then
    GIT_ROOT=$(find_git_root 2>/dev/null) || true
    if [ -n "$GIT_ROOT" ] && is_frappe_project "$GIT_ROOT"; then
        SELECTED_TYPE="Frappe"
        log_info "Detected Frappe project from current directory"
    fi
fi

# If only one type available, use it directly
if [ -z "$SELECTED_TYPE" ] && [ ${#AVAILABLE_TYPES[@]} -eq 1 ]; then
    SELECTED_TYPE="${AVAILABLE_TYPES[0]}"
    log_info "Only ${SELECTED_TYPE} workspace updater available, using it..."
# If explicit type specified as first argument
elif [ $# -gt 0 ]; then
    # Try to match argument to a workspace type
    for type in "${AVAILABLE_TYPES[@]}"; do
        if [[ "${1,,}" == "${type,,}" ]] || [[ "${1,,}" == "update-${type,,}-workspace.sh" ]]; then
            SELECTED_TYPE="$type"
            shift  # Remove the type argument
            break
        fi
    done
    
    # If still no match, try manual detection if AI not available
    if [ -z "$SELECTED_TYPE" ]; then
        if [ "$AI_AVAILABLE" = true ]; then
            log_info "Asking AI to determine workspace type..."
            # AI logic could go here in the future
        elif command -v show_workspace_selection_tui >/dev/null 2>&1; then
            log_info "Using manual workspace type detection..."
            SELECTED_TYPE=$(show_workspace_selection_tui ".")
            [ -z "$SELECTED_TYPE" ] && exit 1
            # Normalize type name
            case "${SELECTED_TYPE,,}" in
                frappe) SELECTED_TYPE="Frappe" ;;
                flutter) SELECTED_TYPE="Flutter" ;;
                dotnet) SELECTED_TYPE="DotNET" ;;
            esac
        fi
    fi
# If no type detected/specified, prompt user
fi

if [ -z "$SELECTED_TYPE" ]; then
    # If manual detector available and no AI, use it
    if [ ! "$AI_AVAILABLE" = true ] && command -v show_workspace_selection_tui >/dev/null 2>&1; then
        SELECTED_TYPE=$(show_workspace_selection_tui ".")
        [ -z "$SELECTED_TYPE" ] && exit 1
        # Normalize type name
        case "${SELECTED_TYPE,,}" in
            frappe) SELECTED_TYPE="Frappe" ;;
            flutter) SELECTED_TYPE="Flutter" ;;
            dotnet) SELECTED_TYPE="DotNET" ;;
        esac
    else
        echo ""
        log_info "Which type of workspace do you want to update?"
        echo ""
        
        for i in "${!AVAILABLE_TYPES[@]}"; do
            echo "  $((i + 1)). ${AVAILABLE_TYPES[$i]}"
        done
        
        echo ""
        echo -ne "${YELLOW}Select workspace type [1-${#AVAILABLE_TYPES[@]}]: ${NC}"
        read -r choice
        
        # Validate choice
        if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#AVAILABLE_TYPES[@]} ]; then
            log_error "Invalid choice"
            exit 1
        fi
        
        SELECTED_TYPE="${AVAILABLE_TYPES[$((choice - 1))]}"
    fi
fi

# Route to appropriate updater
log_info "Updating ${SELECTED_TYPE} workspace(s)..."
echo ""

UPDATER_SCRIPT="${UPDATER_SCRIPTS[$SELECTED_TYPE]}"

if [ ! -f "$UPDATER_SCRIPT" ]; then
    die "Updater script not found: $UPDATER_SCRIPT"
fi

# Pass through all remaining arguments to the specific updater
exec "$UPDATER_SCRIPT" "$@"
