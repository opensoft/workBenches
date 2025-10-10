#!/bin/bash

# ====================================
# Smart Flutter Project Setup Script
# ====================================
# Handles automatic Flutter updates, dependency installation, and error logging
# Used by devcontainer.json onCreateCommand for robust container initialization

set -euo pipefail

# Configuration
LOG_FILE="/tmp/flutter-setup.log"
ERROR_LOG="/tmp/flutter-setup-errors.log"
SUCCESS_LOG="/tmp/flutter-setup-success.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ====================================
# Logging Functions
# ====================================

log_info() {
    local message="$1"
    echo -e "${BLUE}ℹ️  $message${NC}" | tee -a "$LOG_FILE"
}

log_success() {
    local message="$1"
    echo -e "${GREEN}✅ $message${NC}" | tee -a "$LOG_FILE" >> "$SUCCESS_LOG"
}

log_warning() {
    local message="$1"
    echo -e "${YELLOW}⚠️  $message${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    local message="$1"
    echo -e "${RED}❌ $message${NC}" | tee -a "$LOG_FILE" >> "$ERROR_LOG"
}

log_section() {
    local message="$1"
    echo "" | tee -a "$LOG_FILE"
    echo -e "${CYAN}🎯 $message${NC}" | tee -a "$LOG_FILE"
    echo "$(printf '=%.0s' {1..50})" | tee -a "$LOG_FILE"
}

# ====================================
# Error Handling
# ====================================

cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "Setup failed with exit code $exit_code"
        log_info "📋 Error details logged to: $ERROR_LOG"
        log_info "📋 Full log available at: $LOG_FILE"
        
        # Create error summary for user
        echo ""
        echo -e "${RED}🚨 Flutter Setup Failed${NC}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        if [ -f "$ERROR_LOG" ]; then
            echo "Recent errors:"
            tail -5 "$ERROR_LOG"
        fi
        echo ""
        echo "🔧 To debug:"
        echo "   • Check full logs: cat $LOG_FILE"
        echo "   • Check errors: cat $ERROR_LOG"
        echo "   • Re-run manually: $0"
        echo ""
    else
        log_success "Flutter setup completed successfully"
        if [ -f "$SUCCESS_LOG" ]; then
            echo ""
            echo -e "${GREEN}🎉 Setup Summary${NC}"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            tail -5 "$SUCCESS_LOG"
        fi
    fi
}

trap cleanup EXIT

# ====================================
# Setup Functions
# ====================================

initialize_logs() {
    # Clear previous logs
    > "$LOG_FILE"
    > "$ERROR_LOG"
    > "$SUCCESS_LOG"
    
    log_info "Flutter Project Setup Started"
    log_info "Timestamp: $(date)"
    log_info "Working Directory: $(pwd)"
    log_info "User: $(whoami)"
}

check_flutter_project() {
    log_section "Checking Flutter Project"
    
    if [ ! -f "pubspec.yaml" ]; then
        log_warning "No pubspec.yaml found - not a Flutter project"
        log_info "💡 To create a Flutter project: flutter create <app_name>"
        return 1
    fi
    
    log_success "Flutter project detected (pubspec.yaml found)"
    
    # Show project info
    if command -v yq >/dev/null 2>&1; then
        local project_name=$(yq eval '.name' pubspec.yaml 2>/dev/null || echo "unknown")
        local flutter_version=$(yq eval '.environment.flutter' pubspec.yaml 2>/dev/null || echo "not specified")
        log_info "Project name: $project_name"
        log_info "Flutter version constraint: $flutter_version"
    fi
    
    return 0
}

check_and_upgrade_flutter() {
    log_section "Checking Flutter Version"
    
    # Check if flutter command exists
    if ! command -v flutter >/dev/null 2>&1; then
        log_error "Flutter command not found in PATH"
        return 1
    fi
    
    # Get current Flutter version
    local current_version
    current_version=$(flutter --version | head -n 1 | grep -oP 'Flutter \K[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
    log_info "Current Flutter version: $current_version"
    
    # Check for available updates (non-interactive)
    log_info "Checking for Flutter updates..."
    
    # Capture flutter upgrade output
    local upgrade_output
    if upgrade_output=$(flutter upgrade --dry-run 2>&1); then
        if echo "$upgrade_output" | grep -q "Flutter is already up to date"; then
            log_success "Flutter is already up to date"
            return 0
        elif echo "$upgrade_output" | grep -q "A new version of Flutter is available"; then
            log_warning "Flutter update available - performing automatic upgrade..."
            
            # Perform the actual upgrade
            if flutter upgrade 2>&1 | tee -a "$LOG_FILE"; then
                local new_version
                new_version=$(flutter --version | head -n 1 | grep -oP 'Flutter \K[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
                log_success "Flutter upgraded successfully to version: $new_version"
            else
                log_error "Flutter upgrade failed"
                return 1
            fi
        else
            log_info "Flutter version check completed"
        fi
    else
        log_warning "Could not check Flutter version status (possibly offline)"
        log_info "Continuing with current Flutter installation..."
    fi
    
    return 0
}

install_dependencies() {
    log_section "Installing Flutter Dependencies"
    
    # Run flutter pub get with error handling
    log_info "Running 'flutter pub get'..."
    if flutter pub get 2>&1 | tee -a "$LOG_FILE"; then
        log_success "Dependencies installed successfully"
    else
        log_error "Failed to install dependencies with 'flutter pub get'"
        return 1
    fi
    
    # Run flutter precache (but don't fail if it doesn't work)
    log_info "Running 'flutter precache' for faster subsequent builds..."
    if flutter precache --android 2>&1 | tee -a "$LOG_FILE"; then
        log_success "Flutter precache completed"
    else
        log_warning "Flutter precache failed (not critical - continuing)"
    fi
    
    return 0
}

verify_setup() {
    log_section "Verifying Setup"
    
    # Check flutter doctor
    log_info "Running 'flutter doctor'..."
    if flutter doctor 2>&1 | tee -a "$LOG_FILE"; then
        log_success "Flutter doctor completed"
    else
        log_warning "Flutter doctor reported issues (check logs for details)"
    fi
    
    # List dependencies
    if [ -f "pubspec.yaml" ]; then
        log_info "Project dependencies:"
        grep -A 20 "dependencies:" pubspec.yaml | head -20 | tee -a "$LOG_FILE"
    fi
    
    return 0
}

# ====================================
# Main Execution
# ====================================

main() {
    initialize_logs
    
    # Check if this is a Flutter project
    if ! check_flutter_project; then
        log_info "Skipping Flutter setup - not a Flutter project"
        exit 0
    fi
    
    # Check and upgrade Flutter if needed
    if ! check_and_upgrade_flutter; then
        log_error "Flutter version check/upgrade failed"
        exit 1
    fi
    
    # Install project dependencies
    if ! install_dependencies; then
        log_error "Dependency installation failed"
        exit 1
    fi
    
    # Verify the setup
    verify_setup
    
    log_success "🎉 Flutter project setup completed successfully!"
    log_info "📋 Full setup log: $LOG_FILE"
}

# Run main function
main "$@"