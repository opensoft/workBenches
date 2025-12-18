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
declare -a CREATOR_SCRIPTS

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

# Check for AI support
AI_AVAILABLE=false
if [ -f "${WORKBENCHES_ROOT}/devBenches/frappeBench/scripts/lib/ai-provider.sh" ]; then
    source "${WORKBENCHES_ROOT}/devBenches/frappeBench/scripts/lib/common.sh" 2>/dev/null || true
    source "${WORKBENCHES_ROOT}/devBenches/frappeBench/scripts/lib/ai-provider.sh" 2>/dev/null || true
    
    if command -v get_primary_provider >/dev/null 2>&1; then
        provider=$(get_primary_provider 2>/dev/null) || true
        if [ -n "$provider" ]; then
            AI_AVAILABLE=true
            log_success "AI support available ($provider)"
        fi
    fi
fi

# If no available types, error out
if [ ${#AVAILABLE_TYPES[@]} -eq 0 ]; then
    die "No workspace creators found in devBenches"
fi

# If only one type available, use it directly
if [ ${#AVAILABLE_TYPES[@]} -eq 1 ]; then
    SELECTED_TYPE="${AVAILABLE_TYPES[0]}"
    log_info "Only ${SELECTED_TYPE} workspace creator available, using it..."
# If arguments provided, try to match to a type
elif [ $# -gt 0 ]; then
    # Try to match argument to a workspace type
    SELECTED_TYPE=""
    for type in "${AVAILABLE_TYPES[@]}"; do
        if [[ "${1,,}" == "${type,,}" ]] || [[ "${1,,}" == "new-${type,,}-workspace.sh" ]]; then
            SELECTED_TYPE="$type"
            break
        fi
    done
    
    if [ -z "$SELECTED_TYPE" ]; then
        log_error "Unknown workspace type: $1"
        log_info "Available types: ${AVAILABLE_TYPES[*]}"
        exit 1
    fi
# Otherwise, prompt user
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

# Route to appropriate creator
log_info "Creating ${SELECTED_TYPE} workspace..."
echo ""

CREATOR_SCRIPT="${CREATOR_SCRIPTS[$SELECTED_TYPE]}"

if [ ! -f "$CREATOR_SCRIPT" ]; then
    die "Creator script not found: $CREATOR_SCRIPT"
fi

# Pass through remaining arguments to the specific creator
shift || true
exec "$CREATOR_SCRIPT" "$@"
