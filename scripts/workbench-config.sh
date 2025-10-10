#!/bin/bash

# Workbench Configuration Manager
# Handles dynamic detection and storage of projects root path and infrastructure paths

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$HOME/.workbench-config.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }

# Function to find projects root directory
find_projects_root() {
    local current_dir="$1"
    local search_paths=(
        "projects"
        "Projects" 
        "devProjects"
        "DevProjects"
        "development"
        "Development"
        "code"
        "Code"
        "workspace"
        "Workspace"
    )
    
    # Start from current directory and search upward
    while [ "$current_dir" != "/" ]; do
        for path_name in "${search_paths[@]}"; do
            if [ -d "$current_dir/$path_name" ]; then
                # Verify it looks like a projects directory
                if [ -d "$current_dir/$path_name/workBenches" ] || 
                   [ -d "$current_dir/$path_name/infrastructure" ] ||
                   [ -d "$current_dir/$path_name/dartwingers" ]; then
                    echo "$current_dir/$path_name"
                    return 0
                fi
            fi
        done
        current_dir=$(dirname "$current_dir")
    done
    
    return 1
}

# Function to validate infrastructure path
validate_infrastructure() {
    local projects_root="$1"
    local infra_path="$projects_root/infrastructure"
    local adb_script="$infra_path/mobile/android/adb/scripts/start-adb-if-needed.sh"
    
    if [ ! -d "$infra_path" ]; then
        print_warning "Infrastructure directory not found at: $infra_path"
        return 1
    fi
    
    if [ ! -f "$adb_script" ]; then
        print_warning "ADB script not found at: $adb_script"
        return 1
    fi
    
    return 0
}

# Function to create/update configuration
create_config() {
    local projects_root="$1"
    local config_data=$(cat <<EOF
{
    "projectsRoot": "$projects_root",
    "infrastructure": {
        "path": "$projects_root/infrastructure",
        "adbScript": "$projects_root/infrastructure/mobile/android/adb/scripts/start-adb-if-needed.sh"
    },
    "workbenches": {
        "path": "$projects_root/workBenches",
        "flutterBench": "$projects_root/workBenches/devBenches/flutterBench"
    },
    "dartwingers": {
        "path": "$projects_root/dartwingers"
    },
    "version": "1.0.0",
    "lastUpdated": "$(date -Iseconds)"
}
EOF
    )
    
    echo "$config_data" > "$CONFIG_FILE"
    print_success "Configuration saved to: $CONFIG_FILE"
}

# Function to read configuration
read_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        return 1
    fi
    
    local key="$1"
    
    # Handle nested keys like "infrastructure.path"
    if [[ "$key" == *.* ]]; then
        # For nested keys, use a more complex approach
        case "$key" in
            "infrastructure.path")
                grep -A3 '"infrastructure":' "$CONFIG_FILE" | grep '"path":' | sed 's/.*": *"\([^"]*\)".*/\1/'
                ;;
            "infrastructure.adbScript")
                grep -A3 '"infrastructure":' "$CONFIG_FILE" | grep '"adbScript":' | sed 's/.*": *"\([^"]*\)".*/\1/'
                ;;
            "dartwingers.path")
                grep -A3 '"dartwingers":' "$CONFIG_FILE" | grep '"path":' | sed 's/.*": *"\([^"]*\)".*/\1/'
                ;;
            "workbenches.flutterBench")
                grep -A3 '"workbenches":' "$CONFIG_FILE" | grep '"flutterBench":' | sed 's/.*": *"\([^"]*\)".*/\1/'
                ;;
        esac
    else
        # Simple top-level key
        grep "\"$key\":" "$CONFIG_FILE" | sed 's/.*": *"\([^"]*\)".*/\1/'
    fi
}

# Function to get relative infrastructure path from project location
get_relative_infrastructure_path() {
    local project_path="$1"
    local projects_root=$(read_config "projectsRoot")
    
    if [ -z "$projects_root" ]; then
        print_error "No configuration found. Run: workbench-config.sh --setup"
        return 1
    fi
    
    # Calculate relative path from project to infrastructure
    local infra_path="$projects_root/infrastructure/mobile/android/adb/scripts/start-adb-if-needed.sh"
    python3 -c "import os.path; print(os.path.relpath('$infra_path', '$project_path'))" 2>/dev/null || {
        # Fallback if python3 not available
        echo "../../infrastructure/mobile/android/adb/scripts/start-adb-if-needed.sh"
    }
}

# Function to setup configuration interactively
setup_config() {
    print_info "Setting up workbench configuration..."
    
    # Try to auto-detect projects root
    local detected_root=$(find_projects_root "$PWD")
    
    if [ $? -eq 0 ]; then
        print_success "Auto-detected projects root: $detected_root"
        
        # Validate infrastructure
        if validate_infrastructure "$detected_root"; then
            print_success "Infrastructure validated successfully"
            create_config "$detected_root"
            return 0
        else
            print_warning "Infrastructure validation failed, but proceeding with detected path"
            create_config "$detected_root"
            return 0
        fi
    else
        print_error "Could not auto-detect projects root"
        print_info "Please manually specify your projects root directory"
        printf "Projects root path: "
        read -r manual_root
        
        if [ -d "$manual_root" ]; then
            create_config "$manual_root"
            return 0
        else
            print_error "Directory does not exist: $manual_root"
            return 1
        fi
    fi
}

# Function to show current configuration
show_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        print_warning "No configuration found. Run: workbench-config.sh --setup"
        return 1
    fi
    
    print_info "Current Workbench Configuration:"
    echo ""
    echo "Projects Root: $(read_config "projectsRoot")"
    echo "Infrastructure: $(read_config "infrastructure.path")"  
    echo "Dartwingers: $(read_config "dartwingers.path")"
    echo "Flutter Bench: $(read_config "workbenches.flutterBench")"
    echo ""
    echo "Config file: $CONFIG_FILE"
}

# Main command handling
case "$1" in
    --setup)
        setup_config
        ;;
    --show)
        show_config
        ;;
    --get-infrastructure-path)
        if [ -z "$2" ]; then
            print_error "Usage: workbench-config.sh --get-infrastructure-path <project-path>"
            exit 1
        fi
        get_relative_infrastructure_path "$2"
        ;;
    --get-root)
        read_config "projectsRoot"
        ;;
    --validate)
        projects_root=$(read_config "projectsRoot")
        if [ -n "$projects_root" ] && validate_infrastructure "$projects_root"; then
            print_success "Configuration is valid"
            exit 0
        else
            print_error "Configuration is invalid"
            exit 1
        fi
        ;;
    *)
        echo "Workbench Configuration Manager"
        echo ""
        echo "Usage: $0 [OPTION]"
        echo ""
        echo "Options:"
        echo "  --setup                              Set up workbench configuration"
        echo "  --show                               Show current configuration"
        echo "  --get-root                           Get projects root path"
        echo "  --get-infrastructure-path <path>     Get relative infrastructure path from project"
        echo "  --validate                           Validate current configuration"
        echo ""
        echo "Examples:"
        echo "  $0 --setup                           # Initial setup"
        echo "  $0 --show                            # View configuration"
        echo "  $0 --get-infrastructure-path /path/to/project"
        ;;
esac