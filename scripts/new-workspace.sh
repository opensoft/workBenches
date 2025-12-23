#!/bin/bash
# Intelligent workspace creator for workBenches
# Automatically detects available workspace types and routes to the appropriate creator
# Supports: Frappe, Flutter, .NET, and other frameworks

set -e

# Script metadata
SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="new-workspace.sh"

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

echo ""
echo -e "${BLUE}=========================================="
echo "Workspace Creator (Intelligent Router v${SCRIPT_VERSION})"
echo -e "==========================================${NC}"
echo ""

# Detect available workspace creators
declare -a AVAILABLE_TYPES
declare -A CREATOR_SCRIPTS

# Check Frappe
if [ -f "${WORKBENCHES_ROOT}/devBenches/frappeBench/scripts/new-frappe-workspace.sh" ]; then
    AVAILABLE_TYPES+=("Frappe")
    CREATOR_SCRIPTS["Frappe"]="${WORKBENCHES_ROOT}/devBenches/frappeBench/scripts/new-frappe-workspace.sh"
fi

# Check Flutter (when available)
if [ -f "${WORKBENCHES_ROOT}/devBenches/flutterBench/scripts/new-flutter-workspace.sh" ]; then
    AVAILABLE_TYPES+=("Flutter")
    CREATOR_SCRIPTS["Flutter"]="${WORKBENCHES_ROOT}/devBenches/flutterBench/scripts/new-flutter-workspace.sh"
fi

# Check .NET (when available)
if [ -f "${WORKBENCHES_ROOT}/devBenches/dotnetBench/scripts/new-dotnet-workspace.sh" ]; then
    AVAILABLE_TYPES+=("DotNET")
    CREATOR_SCRIPTS["DotNET"]="${WORKBENCHES_ROOT}/devBenches/dotnetBench/scripts/new-dotnet-workspace.sh"
fi

# Check for AI support (three-tier: CLI -> API key -> Manual TUI)
AI_AVAILABLE=false
AI_PROVIDER_NAME=""
AI_PROVIDER_TYPE=""

if [ -f "${WORKBENCHES_ROOT}/devBenches/frappeBench/scripts/lib/ai-provider.sh" ]; then
    source "${WORKBENCHES_ROOT}/devBenches/frappeBench/scripts/lib/common.sh" 2>/dev/null || true
    source "${WORKBENCHES_ROOT}/devBenches/frappeBench/scripts/lib/ai-provider.sh" 2>/dev/null || true
    
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
    log_info "AI not available - will use manual workspace type selection"
fi

# If no available types, error out
if [ ${#AVAILABLE_TYPES[@]} -eq 0 ]; then
    die "No workspace creators found in devBenches"
fi

# NATO phonetic alphabet for workspace naming
declare -A NATO_PHONETIC=(
    [alpha]=1 [bravo]=1 [charlie]=1 [delta]=1 [echo]=1
    [foxtrot]=1 [golf]=1 [hotel]=1 [india]=1 [juliet]=1
    [kilo]=1 [lima]=1 [mike]=1 [november]=1 [oscar]=1
    [papa]=1 [quebec]=1 [romeo]=1 [sierra]=1 [tango]=1
    [uniform]=1 [victor]=1 [whiskey]=1 [xray]=1 [yankee]=1
    [zulu]=1
)

# Function to check if workspace already exists
check_workspace_exists() {
    local workspace_name="$1"
    # Try to find the workspace directory in common locations
    
    # Check in Frappe workspace root if available
    if [ -d "${WORKBENCHES_ROOT}/devBenches/frappeBench/workspaces/${workspace_name}" ]; then
        return 0
    fi
    
    return 1
}

# Function to get the workspace root directory for a given type
get_workspace_root_for_type() {
    local type="$1"
    case "$type" in
        Frappe) echo "${WORKBENCHES_ROOT}/devBenches/frappeBench/workspaces" ;;
        Flutter) echo "${WORKBENCHES_ROOT}/devBenches/flutterBench/workspaces" ;;
        DotNET) echo "${WORKBENCHES_ROOT}/devBenches/dotnetBench/workspaces" ;;
    esac
}

# If only one type available, use it directly
if [ ${#AVAILABLE_TYPES[@]} -eq 1 ]; then
    SELECTED_TYPE="${AVAILABLE_TYPES[0]}"
    log_info "Only ${SELECTED_TYPE} workspace creator available, using it..."
# If arguments provided, try to match to a type or treat as workspace name
elif [ $# -gt 0 ]; then
    # Try to match argument to a workspace type
    SELECTED_TYPE=""
    for type in "${AVAILABLE_TYPES[@]}"; do
        if [[ "${1,,}" == "${type,,}" ]] || [[ "${1,,}" == "new-${type,,}-workspace.sh" ]]; then
            SELECTED_TYPE="$type"
            break
        fi
    done
    
    # If not a type, check if it's a NATO phonetic name
    if [ -z "$SELECTED_TYPE" ]; then
        if [[ -n "${NATO_PHONETIC[${1,,}]}" ]]; then
            # This is a NATO name, treat it as workspace name
            WORKSPACE_NAME="${1,,}"
            
            # Check if workspace already exists
            if check_workspace_exists "$WORKSPACE_NAME"; then
                log_error "Workspace '$WORKSPACE_NAME' already exists"
                exit 1
            fi
            
            # If only one type, use it directly
            if [ ${#AVAILABLE_TYPES[@]} -eq 1 ]; then
                SELECTED_TYPE="${AVAILABLE_TYPES[0]}"
            else
                # Multiple types available - try to auto-detect based on context
                # Check if we're in a Frappe project (look up directory tree)
                DETECTED_FRAPPE=false
                current_dir="$(pwd)"
                for ((i=0; i<8; i++)); do
                    # Check for Frappe project indicators
                    if [ -d "$current_dir/workspaces" ] || \
                       [ -f "$current_dir/scripts/init-bench.sh" ] || \
                       [ -d "$current_dir/devcontainer.example" ] || \
                       ( [ -f "$current_dir/README.md" ] && grep -qi "frappe" "$current_dir/README.md" 2>/dev/null ) || \
                       ( [ -d "$current_dir/.warp" ] && grep -qi "frappe" "$current_dir/.warp/"*.md 2>/dev/null ); then
                        DETECTED_FRAPPE=true
                        log_info "Detected Frappe project at: $current_dir"
                        break
                    fi
                    [ "$current_dir" = "/" ] && break
                    current_dir="$(dirname "$current_dir")"
                done
                
                if [ "$DETECTED_FRAPPE" = true ]; then
                    # We're in what looks like a Frappe project
                    SELECTED_TYPE="Frappe"
                    log_info "Detected Frappe project context, creating Frappe workspace"
                else
                    # Can't auto-detect, prompt user
                    echo ""
                    log_info "Workspace name: ${YELLOW}${WORKSPACE_NAME}${NC}"
                    log_info "Which type of workspace do you want to create?"
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
            
            # Shift arguments and pass workspace name to creator
            shift
            exec "${CREATOR_SCRIPTS[$SELECTED_TYPE]}" "$WORKSPACE_NAME" "$@"
        else
            # If AI not available, try manual detection
            if [ ! "$AI_AVAILABLE" = true ] && command -v show_workspace_selection_tui >/dev/null 2>&1; then
                log_info "Unknown workspace type '$1', using manual detection..."
                SELECTED_TYPE=$(show_workspace_selection_tui ".")
                [ -z "$SELECTED_TYPE" ] && exit 1
                # Normalize type name (frappe -> Frappe, flutter -> Flutter, dotnet -> DotNET)
                case "${SELECTED_TYPE,,}" in
                    frappe) SELECTED_TYPE="Frappe" ;;
                    flutter) SELECTED_TYPE="Flutter" ;;
                    dotnet) SELECTED_TYPE="DotNET" ;;
                esac
            else
                log_error "Unknown workspace type: $1"
                log_info "Available types: ${AVAILABLE_TYPES[*]}"
                exit 1
            fi
        fi
    fi
# Otherwise, prompt user
else
    # NOTE: When running in Warp, this script can leverage Warp's AI to automatically
    # determine the workspace type based on the current directory context.
    # Warp AI will analyze the project structure and suggest the appropriate type.
    
    # Try to auto-detect project type first using heuristics
    DETECTED_FRAPPE=false
    current_dir="$(pwd)"
    for ((i=0; i<8; i++)); do
        # Check for Frappe project indicators
        if [ -d "$current_dir/workspaces" ] || \
           [ -f "$current_dir/scripts/init-bench.sh" ] || \
           [ -d "$current_dir/devcontainer.example" ] || \
           ( [ -f "$current_dir/README.md" ] && grep -qi "frappe" "$current_dir/README.md" 2>/dev/null ) || \
           ( [ -d "$current_dir/.warp" ] && grep -qi "frappe" "$current_dir/.warp/"*.md 2>/dev/null ); then
            DETECTED_FRAPPE=true
            log_info "Detected Frappe project at: $current_dir"
            break
        fi
        [ "$current_dir" = "/" ] && break
        current_dir="$(dirname "$current_dir")"
    done
    
    if [ "$DETECTED_FRAPPE" = true ]; then
        # We're in what looks like a Frappe project
        SELECTED_TYPE="Frappe"
        log_success "Auto-detected project type: Frappe (AI-assisted)"
    # If AI not available and manual detector available, use it
    elif [ ! "$AI_AVAILABLE" = true ] && command -v show_workspace_selection_tui >/dev/null 2>&1; then
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
        log_info "Which type of workspace do you want to create?"
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

# Route to appropriate creator
log_info "Creating ${SELECTED_TYPE} workspace..."
echo ""

# Check if we're in a project directory with its own workspace creator
PROJECT_CREATOR=""
current_dir="$(pwd)"
for ((i=0; i<8; i++)); do
    if [ -f "${current_dir}/scripts/new-workspace.sh" ] && [ -d "${current_dir}/workspaces" ]; then
        PROJECT_CREATOR="${current_dir}/scripts/new-workspace.sh"
        log_info "Found project-local workspace creator"
        break
    fi
    [ "$current_dir" = "/" ] && break
    current_dir="$(dirname "$current_dir")"
done

# Use project creator if found, otherwise use shared creator
if [ -n "$PROJECT_CREATOR" ]; then
    CREATOR_SCRIPT="$PROJECT_CREATOR"
else
    CREATOR_SCRIPT="${CREATOR_SCRIPTS[$SELECTED_TYPE]}"
fi

if [ ! -f "$CREATOR_SCRIPT" ]; then
    die "Creator script not found: $CREATOR_SCRIPT"
fi

# Pass through remaining arguments to the specific creator
shift || true
exec "$CREATOR_SCRIPT" "$@"
