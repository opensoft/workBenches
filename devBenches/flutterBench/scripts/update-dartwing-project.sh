#!/bin/bash

# ====================================
# Dartwing Project Template Update Script
# ====================================
# Updates existing Dartwing projects with the latest devcontainer template
# This is a wrapper around update-flutter-project.sh with Dartwingers-specific customizations
#
# Usage: ./update-dartwing-project.sh [project-path]

set -e

# ====================================
# Project Name Normalization (same as update-flutter-project.sh)
# ====================================

normalize_project_name() {
    local raw_name="$1"
    local normalized="$raw_name"
    
    # For Dartwingers projects, remove app/service prefixes
    # app -> dartwing
    # serviceDartwing -> dartwing
    # appLedgerLinc -> ledgerlinc
    # serviceLedgerLinc -> ledgerlinc
    
    # Remove 'app' prefix (case insensitive)
    if [[ "$normalized" =~ ^[Aa][Pp][Pp](.+)$ ]]; then
        normalized="${BASH_REMATCH[1]}"
    fi
    
    # Remove 'service' prefix (case insensitive) 
    if [[ "$normalized" =~ ^[Ss][Ee][Rr][Vv][Ii][Cc][Ee](.+)$ ]]; then
        normalized="${BASH_REMATCH[1]}"
    fi
    
    # Convert to lowercase for consistency
    normalized=$(echo "$normalized" | tr '[:upper:]' '[:lower:]')
    
    echo "$normalized"
}

PROJECT_PATH="${1:-$(pwd)}"
PROJECT_NAME_RAW=$(basename "$PROJECT_PATH")

# Special handling for Dartwingers orchestrator subdirectories
# For Dartwingers projects, use format: <parent-dir-name>-<current-dir-name>
if [[ "$PROJECT_NAME_RAW" =~ ^(app|gatekeeper|lib)$ ]]; then
    parent_dir=$(basename "$(dirname "$PROJECT_PATH")")
    grandparent_dir=$(basename "$(dirname "$(dirname "$PROJECT_PATH")")")  
    # Check if this is a Dartwingers project (parent dir contains dartwing or grandparent is dartwingers)
    if [[ -f "$(dirname "$PROJECT_PATH")/setup-dartwing-project.sh" ]] || [[ "$parent_dir" =~ dartwing ]] || [[ "$grandparent_dir" == "dartwingers" ]]; then
        PROJECT_NAME_RAW="${parent_dir}-${PROJECT_NAME_RAW}"
    fi
fi

# Normalize project name (remove app/service prefixes for Dartwingers projects)
PROJECT_NAME=$(normalize_project_name "$PROJECT_NAME_RAW")

# Log normalization if name changed
if [ "$PROJECT_NAME" != "$PROJECT_NAME_RAW" ]; then
    echo -e "${BLUE}📝 Normalized project name: $PROJECT_NAME_RAW → $PROJECT_NAME${NC}" >&2
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/../template"

# ====================================
# Utility Functions
# ====================================

log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

log_section() {
    echo ""
    echo -e "${CYAN}🎯 $1${NC}"
    echo "$(printf '=%.0s' {1..50})"
}

# ====================================
# Validation Functions  
# ====================================

validate_dartwing_project() {
    log_section "Validating Dartwing Project"
    
    if [ ! -d "$PROJECT_PATH" ]; then
        log_error "Project directory not found: $PROJECT_PATH"
        exit 1
    fi
    
    cd "$PROJECT_PATH"
    
    # Check if it's a Flutter project
    if [ ! -f "pubspec.yaml" ]; then
        log_error "Not a Flutter project (no pubspec.yaml found)"
        exit 1
    fi
    
    # Check if it looks like a Dartwing project
    local is_dartwing=false
    
    # Check for Dartwing indicators
    if [ -d ".devcontainer" ] && grep -q -i "dartwing\|service.*5000" .devcontainer/devcontainer.json 2>/dev/null; then
        is_dartwing=true
    elif [ -f ".devcontainer/docker-compose.override.yml" ]; then
        is_dartwing=true
    elif [ -f "docker-compose.yml" ] && grep -q -i "dartwing\|service.*image" docker-compose.yml 2>/dev/null; then
        is_dartwing=true
    elif echo "$PROJECT_NAME" | grep -q -i "dartwing"; then
        is_dartwing=true
    elif basename "$(dirname "$PROJECT_PATH")" | grep -q -i "dartwing"; then
        is_dartwing=true
    fi
    
    if [ "$is_dartwing" = false ]; then
        log_warning "This doesn't appear to be a Dartwing project"
        log_info "Indicators we look for:"
        log_info "  - Project name contains 'dartwing'"
        log_info "  - Located in 'dartwingers' directory"
        log_info "  - Has docker-compose.override.yml (Dartwingers projects)"
        log_info "  - Has .NET service container in docker-compose.yml"
        log_info "  - DevContainer mentions Dartwing or service port 5000"
        echo ""
        log_info "Continue anyway? (y/N)"
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            log_info "Update cancelled by user"
            exit 0
        fi
    fi
    
    log_success "Dartwing project validation passed"
    log_info "Project: $PROJECT_NAME"
    log_info "Path: $PROJECT_PATH"
}

# ====================================
# Dartwing Environment Configuration Functions
# ====================================

get_dartwing_env_value() {
    local env_file="$1"
    local key="$2"
    
    if [ -f "$env_file" ]; then
        grep "^${key}=" "$env_file" 2>/dev/null | cut -d'=' -f2- || echo "(not set)"
    else
        echo "(not set)"
    fi
}

check_dartwing_env_updates() {
    log_section "🎯 Checking Dartwing-Specific Environment Configuration"
    
    if [ ! -f ".devcontainer/.env" ]; then
        log_warning "No .devcontainer/.env file found - this should have been handled by the base Flutter update"
        return 0
    fi
    
    # Get current COMPOSE_PROJECT_NAME and SERVICE_CONTAINER_SUFFIX
    local current_compose_name=$(get_dartwing_env_value ".devcontainer/.env" "COMPOSE_PROJECT_NAME")
    local expected_compose_name="dartwingers"
    local current_service_suffix=$(get_dartwing_env_value ".devcontainer/.env" "SERVICE_CONTAINER_SUFFIX")
    local expected_service_suffix="gateway"
    
    # Check if COMPOSE_PROJECT_NAME needs to be updated for Dartwing
    local needs_compose_update=false
    local needs_suffix_update=false
    
    if [ "$current_compose_name" != "$expected_compose_name" ]; then
        needs_compose_update=true
    fi
    
    if [ "$current_service_suffix" != "$expected_service_suffix" ]; then
        needs_suffix_update=true
    fi
    
    if [ "$needs_compose_update" = true ] || [ "$needs_suffix_update" = true ]; then
        log_warning "Dartwing-specific environment configuration needs updating"
        echo ""
        echo -e "${YELLOW}📋 Dartwing Environment Configuration:${NC}"
        echo "══════════════════════════════════════════════════════════"
        echo ""
        
        if [ "$needs_compose_update" = true ]; then
            echo -e "${BLUE}COMPOSE_PROJECT_NAME:${NC}"
            echo -e "  Current: ${RED}$current_compose_name${NC}"
            echo -e "  Expected: ${GREEN}$expected_compose_name${NC}"
            echo -e "  Impact: Docker stack will be grouped under '${GREEN}dartwingers${NC}' for proper Dartwing integration"
            echo ""
        fi
        
        if [ "$needs_suffix_update" = true ]; then
            echo -e "${BLUE}SERVICE_CONTAINER_SUFFIX:${NC}"
            echo -e "  Current: ${RED}$current_service_suffix${NC}"
            echo -e "  Expected: ${GREEN}$expected_service_suffix${NC}"
            echo -e "  Impact: Service container will be named '${PROJECT_NAME}-${GREEN}gateway${NC}' instead of '${PROJECT_NAME}-service'"
            echo ""
        fi
        
        # Prompt user
        echo -e "${CYAN}Update Dartwing environment configuration?${NC}"
        read -p "Update? [Y/n]: " update_choice
        
        case $update_choice in
            [Nn]* )
                log_info "Skipping Dartwing environment updates"
                if [ "$needs_compose_update" = true ]; then
                    log_warning "Note: COMPOSE_PROJECT_NAME='$current_compose_name' may cause issues with Dartwing multi-service setup"
                fi
                if [ "$needs_suffix_update" = true ]; then
                    log_warning "Note: SERVICE_CONTAINER_SUFFIX='$current_service_suffix' - container will be named '${PROJECT_NAME}-$current_service_suffix'"
                fi
                ;;
            * )
                # Apply updates
                local updates_applied=()
                
                if [ "$needs_compose_update" = true ]; then
                    if [[ "$OSTYPE" == "darwin"* ]]; then
                        sed -i '' "s/COMPOSE_PROJECT_NAME=.*/COMPOSE_PROJECT_NAME=dartwingers/g" .devcontainer/.env
                    else
                        sed -i "s/COMPOSE_PROJECT_NAME=.*/COMPOSE_PROJECT_NAME=dartwingers/g" .devcontainer/.env
                    fi
                    updates_applied+=("COMPOSE_PROJECT_NAME=dartwingers")
                fi
                
                if [ "$needs_suffix_update" = true ]; then
                    if [[ "$OSTYPE" == "darwin"* ]]; then
                        sed -i '' "s/SERVICE_CONTAINER_SUFFIX=.*/SERVICE_CONTAINER_SUFFIX=gateway/g" .devcontainer/.env
                    else
                        sed -i "s/SERVICE_CONTAINER_SUFFIX=.*/SERVICE_CONTAINER_SUFFIX=gateway/g" .devcontainer/.env
                    fi
                    updates_applied+=("SERVICE_CONTAINER_SUFFIX=gateway")
                fi
                
                log_success "Updated Dartwing environment configuration in .devcontainer/.env:"
                for update in "${updates_applied[@]}"; do
                    echo "   • $update"
                done
                ;;
        esac
    else
        log_success "Dartwing environment configuration is correct"
        log_info "COMPOSE_PROJECT_NAME: $current_compose_name ✓"
        log_info "SERVICE_CONTAINER_SUFFIX: $current_service_suffix ✓"
    fi
}

# ====================================
# Dartwing-Specific Customizations
# ====================================

apply_dartwing_customizations() {
    log_section "Applying Dartwings-Specific Customizations"
    
    # Check if dartwingers docker-compose override template exists
    if [ ! -f "$TEMPLATE_DIR/.devcontainer/docker-compose.override.yml" ]; then
        log_warning "Dartwingers override template not found at: $TEMPLATE_DIR/.devcontainer/docker-compose.override.yml"
        log_info "Using standard Flutter docker-compose.yml only"
        return 0
    fi
    
    # Add docker-compose.override.yml for Dartwingers .NET service
    log_info "Adding docker-compose.override.yml for .NET service..."
    cp "$TEMPLATE_DIR/.devcontainer/docker-compose.override.yml" .devcontainer/docker-compose.override.yml
    log_success "Applied Dartwingers docker-compose override configuration"
    
    # Check and prompt for Dartwing-specific environment updates
    check_dartwing_env_updates
    
    log_success "Dartwingers customizations applied"
}

# ====================================
# Dartwing-Specific Analysis
# ====================================

analyze_dartwing_changes() {
    log_section "Analyzing Dartwing-Specific Changes"
    
    echo ""
    log_info "🎯 Dartwing Project Update Summary:"
    echo ""
    
    # Get the current service and app suffixes for display
    local service_suffix=$(get_dartwing_env_value ".devcontainer/.env" "SERVICE_CONTAINER_SUFFIX")
    if [ "$service_suffix" = "(not set)" ]; then
        service_suffix="service"  # default
    fi
    
    local app_suffix=$(get_dartwing_env_value ".devcontainer/.env" "APP_CONTAINER_SUFFIX")
    if [ "$app_suffix" = "(not set)" ]; then
        app_suffix="app"  # default
    fi
    
    echo "📦 Container Architecture:"
    echo "   • Flutter App Container: ${PROJECT_NAME}-${app_suffix}"
    echo "   • .NET Service Container: ${PROJECT_NAME}-${service_suffix}"
    echo "   • Stack Name: dartwingers"
    echo "   • Network: dartnet (shared)"
    echo ""
    
    echo "🔗 Service Connectivity:"
    echo "   • Flutter → .NET Service: http://service:5000"
    echo "   • .NET Service exposed on host: port 5000"
    echo "   • Flutter hot reload on host: port 8080"
    echo "   • Shared ADB server: shared-adb-server:5037"
    echo ""
    
    echo "⚙️  Key Configurations:"
    echo "   • .devcontainer/docker-compose.yml: Base Flutter container"
    echo "   • .devcontainer/docker-compose.override.yml: Adds .NET service container"
    echo "   • COMPOSE_PROJECT_NAME: dartwingers (for proper container naming)"
    echo "   • Network isolation: Both containers on dartnet"
    echo "   • Volume sharing: Source code mounted in both containers"
    echo ""
    
    log_info "🔍 Dartwing-Specific Validation Points:"
    echo "   1. Both containers should start successfully"
    echo "   2. Flutter app can reach .NET service at http://service:5000"
    echo "   3. ADB connection works from Flutter container"
    echo "   4. Hot reload works for Flutter development"
    echo "   5. .NET service APIs are accessible from Flutter"
    echo ""
}

# ====================================
# Main Dartwing Wrapper Function
# ====================================

main() {
    echo -e "${BLUE}Dartwing Project Template Update Script${NC}"
    echo "==============================================="
    echo ""
    echo -e "${CYAN}🎯 This script updates Dartwing projects with:${NC}"
    echo "   • Latest Flutter devcontainer template"
    echo "   • Dartwingers multi-service configuration"
    echo "   • .NET service container setup"
    echo "   • Shared ADB infrastructure integration"
    echo ""
    
    # Validate this is a Dartwing project
    validate_dartwing_project
    
    # Store original directory for post-processing
    local original_pwd="$PWD"
    
    # Call the base Flutter update script
    log_section "Running Base Flutter Template Update"
    log_info "Delegating to update-flutter-project.sh..."
    echo ""
    
    # Set environment variable to prevent circular delegation
    export FLUTTER_SCRIPT_CALLED_FROM_DARTWING=true
    
    if ! "$SCRIPT_DIR/update-flutter-project.sh" "$PROJECT_PATH"; then
        log_error "Base Flutter update failed"
        unset FLUTTER_SCRIPT_CALLED_FROM_DARTWING
        exit 1
    fi
    
    # Clean up environment variable
    unset FLUTTER_SCRIPT_CALLED_FROM_DARTWING
    
    # Return to project directory for post-processing
    cd "$PROJECT_PATH"
    
    # Apply Dartwing-specific customizations
    apply_dartwing_customizations
    
    # Provide Dartwing-specific analysis
    analyze_dartwing_changes
    
    # Additional commit if we made Dartwing-specific changes
    if git status --porcelain | grep -q .; then
        log_section "Committing Dartwing-Specific Changes"
        
        git add .
        git commit -m "Apply Dartwingers-specific customizations

- Add .devcontainer/docker-compose.override.yml for .NET service container
- Base .devcontainer/docker-compose.yml remains unchanged (Flutter container only)
- Ensure COMPOSE_PROJECT_NAME=dartwingers for proper container naming
- Docker Compose automatically merges base + override files

Customizations applied by: update-dartwing-project.sh"
        
        log_success "Dartwing customizations committed"
        
        # Push the updated branch if there's a remote
        if git remote get-url origin &>/dev/null; then
            local current_branch=$(git branch --show-current)
            if git push origin "$current_branch" 2>/dev/null; then
                log_success "Pushed Dartwing customizations to remote"
            else
                log_warning "Failed to push Dartwing customizations - you may need to push manually"
            fi
        fi
    fi
    
    # Return to original directory
    cd "$original_pwd"
    
    # Final summary
    log_section "Dartwing Update Complete"
    
    echo ""
    log_success "🎉 Dartwing project update completed successfully!"
    echo ""
    
    echo "🚀 Next steps for Dartwing development:"
    echo "   1. Review the updated branch and merge the pull request"
    echo "   2. Test both containers: docker-compose build"
    echo "   3. Open in VS Code: code ."
    echo "   4. Verify Flutter → .NET service communication"
    echo "   5. Test ADB connectivity for mobile development"
    echo ""
    
    echo "🔧 Testing Dartwing Integration:"
    echo "   • Flutter app: http://localhost:8080"
    echo "   • .NET service: http://localhost:5000"
    echo "   • Service-to-service: http://service:5000 (from Flutter container)"
    echo ""
    
    echo "📚 For spec-driven development with Dartwings:"
    echo "   • Use /constitution, /specify, /plan, /tasks, /implement commands"
    echo "   • See README.md and spec-driven.md for guidance"
    echo ""
    
    echo -e "${GREEN}🎯 Happy Dartwing Development with the latest template!${NC}"
    echo ""
}

# ====================================
# Script Execution
# ====================================

# Show usage if help requested
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    echo "Usage: $0 [project-path]"
    echo ""
    echo "Updates an existing Dartwing project with the latest devcontainer template."
    echo "This script wraps update-flutter-project.sh with Dartwingers-specific customizations."
    echo ""
    echo "Arguments:"
    echo "  project-path    Path to Dartwing project (default: current directory)"
    echo ""
    echo "This script will:"
    echo "  1. Validate the project is a Dartwing project"
    echo "  2. Run the base Flutter template update"
    echo "  3. Apply Dartwingers-specific customizations:"
    echo "     • Add .devcontainer/docker-compose.override.yml for .NET service container"
    echo "     • Keep base .devcontainer/docker-compose.yml unchanged (Flutter only)"
    echo "     • Set COMPOSE_PROJECT_NAME=dartwingers"
    echo "  4. Commit Dartwing-specific changes"
    echo "  5. Provide Dartwing-specific testing guidance"
    echo ""
    echo "Requirements:"
    echo "  - Git repository with no uncommitted changes"  
    echo "  - Dartwing/Flutter project (pubspec.yaml present)"
    echo "  - Latest devcontainer template with Dartwingers support"
    echo ""
    exit 0
fi

# Run main function
main "$@"