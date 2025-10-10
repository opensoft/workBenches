#!/bin/bash

# ====================================
# Flutter Development Status Script
# ====================================
# Provides comprehensive status check for Flutter development environment
# Used by devcontainer.json postStartCommand

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

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
# Status Check Functions
# ====================================

check_setup_logs() {
    log_section "Setup Status"
    
    # Check if setup logs exist
    if [ -f "/tmp/flutter-setup-success.log" ]; then
        log_success "Previous Flutter setup completed successfully"
        echo "Recent setup actions:"
        tail -3 "/tmp/flutter-setup-success.log" | sed 's/^/  • /'
    elif [ -f "/tmp/flutter-setup-errors.log" ]; then
        log_warning "Previous Flutter setup had issues"
        echo "Recent errors:"
        tail -3 "/tmp/flutter-setup-errors.log" | sed 's/^/  • /'
        echo ""
        log_info "💡 Full setup log: cat /tmp/flutter-setup.log"
    else
        log_info "No previous setup logs found"
    fi
}

check_flutter_status() {
    log_section "Flutter Environment"
    
    # Check Flutter installation
    if command -v flutter >/dev/null 2>&1; then
        local flutter_version=$(flutter --version | head -n 1)
        log_success "Flutter installed: $flutter_version"
        
        # Quick flutter doctor check (non-verbose)
        log_info "Running flutter doctor..."
        flutter doctor --version
    else
        log_error "Flutter command not found"
        return 1
    fi
}

check_project_status() {
    log_section "Project Status"
    
    if [ -f "pubspec.yaml" ]; then
        local project_name="unknown"
        if command -v grep >/dev/null 2>&1; then
            project_name=$(grep "^name:" pubspec.yaml | cut -d: -f2 | xargs || echo "unknown")
        fi
        log_success "Flutter project: $project_name"
        
        # Check if dependencies are installed
        if [ -f "pubspec.lock" ]; then
            log_success "Dependencies installed (pubspec.lock exists)"
            local dep_count=$(grep -c "name:" pubspec.lock 2>/dev/null || echo "unknown")
            log_info "Dependencies: $dep_count packages"
        else
            log_warning "Dependencies not installed (run: flutter pub get)"
        fi
        
        # Check for build directory
        if [ -d "build" ]; then
            log_info "Build artifacts exist (project has been built)"
        else
            log_info "No build artifacts (clean project)"
        fi
    else
        log_warning "Not a Flutter project (no pubspec.yaml)"
        log_info "💡 Create a Flutter project: flutter create <app_name>"
    fi
}

check_android_status() {
    log_section "Android Development"
    
    # Check ADB connection
    if command -v adb >/dev/null 2>&1; then
        log_success "ADB command available"
        
        log_info "Checking connected devices..."
        local devices_output
        devices_output=$(adb devices 2>/dev/null || echo "ADB connection failed")
        
        if echo "$devices_output" | grep -q "device$"; then
            local device_count=$(echo "$devices_output" | grep -c "device$")
            log_success "Android devices connected: $device_count"
            echo "Connected devices:"
            echo "$devices_output" | grep "device$" | sed 's/^/  • /'
        elif echo "$devices_output" | grep -q "offline"; then
            log_warning "Android devices found but offline"
            echo "$devices_output" | grep "offline" | sed 's/^/  • /'
        else
            log_info "No Android devices connected"
            log_info "💡 Connect a device or start an emulator"
        fi
    else
        log_error "ADB command not found"
        log_info "💡 Install Android SDK or check PATH"
    fi
}

check_development_ports() {
    log_section "Development Ports"
    
    # Common Flutter/Dart development ports
    local ports=(8080 9100 9101 5000 5001)
    
    for port in "${ports[@]}"; do
        if command -v netstat >/dev/null 2>&1; then
            if netstat -ln 2>/dev/null | grep -q ":$port "; then
                case $port in
                    8080) log_info "Port $port: Flutter hot reload (in use)" ;;
                    9100) log_info "Port $port: Flutter DevTools (in use)" ;;
                    9101) log_info "Port $port: Dart VM Service (in use)" ;;
                    5000) log_info "Port $port: .NET Service (in use)" ;;
                    5001) log_info "Port $port: .NET HTTPS (in use)" ;;
                    *) log_info "Port $port: (in use)" ;;
                esac
            else
                case $port in
                    8080) log_info "Port $port: Available for Flutter hot reload" ;;
                    9100) log_info "Port $port: Available for Flutter DevTools" ;;
                    9101) log_info "Port $port: Available for Dart VM Service" ;;
                    5000) log_info "Port $port: Available for .NET Service" ;;
                    5001) log_info "Port $port: Available for .NET HTTPS" ;;
                    *) log_info "Port $port: Available" ;;
                esac
            fi
        fi
    done
}

show_development_commands() {
    log_section "Development Commands"
    
    echo "🚀 Flutter Development:"
    echo "   • flutter run                    - Run on connected device"
    echo "   • flutter run -d web-server      - Run in web browser"
    echo "   • flutter run --hot              - Enable hot reload"
    echo "   • flutter build apk              - Build Android APK"
    echo ""
    
    echo "🔧 Development Tools:"
    echo "   • flutter doctor                 - Check development setup"
    echo "   • flutter devices                - List available devices"
    echo "   • flutter pub get                - Install dependencies"
    echo "   • flutter clean                  - Clean build artifacts"
    echo ""
    
    echo "📱 Android Tools:"
    echo "   • adb devices                    - List connected devices"
    echo "   • adb logcat                     - View device logs"
    echo "   • adb shell                      - Access device shell"
    echo ""
    
    if [ -f "docker-compose.override.yml" ]; then
        echo "🐳 Dartwing Services:"
        echo "   • docker-compose up -d service  - Start .NET service"
        echo "   • docker-compose logs service   - View .NET service logs"
        echo "   • curl http://service:5000       - Test .NET service"
        echo ""
    fi
}

# ====================================
# Main Execution
# ====================================

main() {
    echo -e "${CYAN}Flutter Development Environment Status${NC}"
    echo "═══════════════════════════════════════════════════════════════"
    
    check_setup_logs
    check_flutter_status
    check_project_status
    check_android_status
    check_development_ports
    show_development_commands
    
    echo ""
    log_success "🎉 Development environment status check complete!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Run main function
main "$@"