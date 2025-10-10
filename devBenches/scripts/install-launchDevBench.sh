#!/bin/bash

# =============================================================================
# install-launchDevBench.sh - Global Installation Script
# =============================================================================
# Installs launchDevBench as a global system command with proper PATH setup
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAUNCHBENCH_SCRIPT="$SCRIPT_DIR/launchDevBench"
AI_HELPER_SCRIPT="$SCRIPT_DIR/ai-helper.sh"
CONFIG_SCRIPT="$SCRIPT_DIR/workbench-config.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print functions
print_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }

# Check if running with sufficient privileges
check_install_location() {
    # Try user-local installation first (recommended)
    if [ -d "$HOME/.local/bin" ]; then
        echo "$HOME/.local/bin"
        return 0
    elif [ -w "/usr/local/bin" ]; then
        echo "/usr/local/bin"
        return 0
    else
        echo ""
        return 1
    fi
}

# Create user-local bin directory if it doesn't exist
create_local_bin() {
    if [ ! -d "$HOME/.local/bin" ]; then
        print_info "Creating $HOME/.local/bin directory"
        mkdir -p "$HOME/.local/bin"
        
        if [ $? -eq 0 ]; then
            print_success "Created $HOME/.local/bin"
        else
            print_error "Failed to create $HOME/.local/bin"
            return 1
        fi
    fi
    return 0
}

# Check if directory is in PATH
is_in_path() {
    local dir="$1"
    case ":$PATH:" in
        *":$dir:"*) return 0 ;;
        *) return 1 ;;
    esac
}

# Add directory to PATH in shell profile
add_to_path() {
    local dir="$1"
    local shell_profile=""
    
    # Determine shell profile file
    if [ -n "$ZSH_VERSION" ]; then
        shell_profile="$HOME/.zshrc"
    elif [ -n "$BASH_VERSION" ]; then
        if [ -f "$HOME/.bashrc" ]; then
            shell_profile="$HOME/.bashrc"
        else
            shell_profile="$HOME/.bash_profile"
        fi
    else
        shell_profile="$HOME/.profile"
    fi
    
    print_info "Adding $dir to PATH in $shell_profile"
    
    # Check if PATH modification already exists
    if grep -q "export PATH.*$dir" "$shell_profile" 2>/dev/null; then
        print_warning "PATH modification already exists in $shell_profile"
        return 0
    fi
    
    # Add PATH modification
    {
        echo ""
        echo "# Added by launchDevBench installer"
        echo "if [ -d \"$dir\" ]; then"
        echo "    export PATH=\"$dir:\$PATH\""
        echo "fi"
    } >> "$shell_profile"
    
    if [ $? -eq 0 ]; then
        print_success "Added $dir to PATH in $shell_profile"
        print_warning "You may need to restart your shell or run: source $shell_profile"
        return 0
    else
        print_error "Failed to modify $shell_profile"
        return 1
    fi
}

# Install launchDevBench
install_launchdevbench() {
    # Verify source files exist
    if [ ! -f "$LAUNCHBENCH_SCRIPT" ]; then
        print_error "launchDevBench script not found at: $LAUNCHBENCH_SCRIPT"
        return 1
    fi
    
    if [ ! -f "$CONFIG_SCRIPT" ]; then
        print_error "workbench-config.sh script not found at: $CONFIG_SCRIPT"
        return 1
    fi
    
    # Determine installation directory
    local install_dir
    install_dir=$(check_install_location)
    
    if [ -z "$install_dir" ]; then
        print_error "No suitable installation directory found"
        print_info "Trying to create ~/.local/bin"
        
        if create_local_bin; then
            install_dir="$HOME/.local/bin"
        else
            print_error "Installation failed"
            return 1
        fi
    fi
    
    print_info "Installing launchDevBench to: $install_dir"
    
    # Copy main script
    cp "$LAUNCHBENCH_SCRIPT" "$install_dir/launchDevBench"
    if [ $? -ne 0 ]; then
        print_error "Failed to copy launchDevBench script"
        return 1
    fi
    
    # Make executable
    chmod +x "$install_dir/launchDevBench"
    
    # Copy helper scripts to a subdirectory
    local helper_dir="$install_dir/.launchDevBench-helpers"
    mkdir -p "$helper_dir"
    
    if [ -f "$AI_HELPER_SCRIPT" ]; then
        cp "$AI_HELPER_SCRIPT" "$helper_dir/"
        chmod +x "$helper_dir/ai-helper.sh"
    fi
    
    cp "$CONFIG_SCRIPT" "$helper_dir/"
    chmod +x "$helper_dir/workbench-config.sh"
    
    # Update script to use the new helper locations
    sed -i "s|CONFIG_SCRIPT=\"\$SCRIPT_DIR/workbench-config.sh\"|CONFIG_SCRIPT=\"$helper_dir/workbench-config.sh\"|" "$install_dir/launchDevBench"
    
    print_success "launchDevBench installed successfully"
    
    # Check PATH
    if ! is_in_path "$install_dir"; then
        print_warning "$install_dir is not in your PATH"
        if add_to_path "$install_dir"; then
            print_info "PATH updated - restart your shell to use 'launchDevBench' globally"
        else
            print_warning "You may need to manually add $install_dir to your PATH"
        fi
    else
        print_success "$install_dir is already in your PATH"
        print_success "You can now use 'launchDevBench' from anywhere!"
    fi
    
    return 0
}

# Uninstall launchDevBench
uninstall_launchdevbench() {
    local removed_any=false
    
    # Check common installation locations
    local locations=("$HOME/.local/bin" "/usr/local/bin")
    
    for location in "${locations[@]}"; do
        if [ -f "$location/launchDevBench" ]; then
            print_info "Removing launchDevBench from: $location"
            rm -f "$location/launchDevBench"
            rm -rf "$location/.launchDevBench-helpers"
            
            if [ $? -eq 0 ]; then
                print_success "Removed from $location"
                removed_any=true
            else
                print_error "Failed to remove from $location"
            fi
        fi
    done
    
    if [ "$removed_any" = true ]; then
        print_success "launchDevBench uninstalled successfully"
        print_warning "PATH modifications in shell profiles were not removed automatically"
    else
        print_warning "launchDevBench installation not found"
    fi
}

# Show installation status
show_status() {
    print_info "launchDevBench Installation Status:"
    echo ""
    
    local found_installations=0
    
    # Check installation locations
    local locations=("$HOME/.local/bin" "/usr/local/bin")
    
    for location in "${locations[@]}"; do
        if [ -f "$location/launchDevBench" ]; then
            print_success "Found: $location/launchDevBench"
            
            # Check if it's executable
            if [ -x "$location/launchDevBench" ]; then
                echo "  ✅ Executable: Yes"
            else
                echo "  ❌ Executable: No"
            fi
            
            # Check if location is in PATH
            if is_in_path "$location"; then
                echo "  ✅ In PATH: Yes"
            else
                echo "  ❌ In PATH: No"
            fi
            
            # Check helper files
            if [ -d "$location/.launchDevBench-helpers" ]; then
                echo "  ✅ Helper scripts: Present"
            else
                echo "  ❌ Helper scripts: Missing"
            fi
            
            found_installations=$((found_installations + 1))
            echo ""
        fi
    done
    
    if [ $found_installations -eq 0 ]; then
        print_warning "launchDevBench is not installed globally"
        print_info "Run: $0 --install"
    else
        # Test if command works
        if command -v launchDevBench >/dev/null 2>&1; then
            print_success "launchDevBench command is available globally"
        else
            print_warning "launchDevBench is installed but not accessible globally"
            print_info "You may need to restart your shell or update your PATH"
        fi
    fi
}

# Show help
show_help() {
    cat << EOF
launchDevBench Installer

USAGE:
    $0 [OPTION]

OPTIONS:
    --install     Install launchDevBench globally
    --uninstall   Remove launchDevBench global installation
    --status      Show installation status
    --help, -h    Show this help message

INSTALLATION:
    This installer will:
    1. Copy launchDevBench to ~/.local/bin (preferred) or /usr/local/bin
    2. Copy helper scripts to a subdirectory
    3. Make scripts executable
    4. Add installation directory to PATH (if needed)

REQUIREMENTS:
    - Bash shell
    - Write access to ~/.local/bin or /usr/local/bin
    - workbench-config.sh must be set up first

EXAMPLES:
    $0 --install      Install launchDevBench globally
    $0 --status       Check installation status
    $0 --uninstall    Remove installation

After installation, you can use:
    launchDevBench           # Interactive menu
    launchDevBench flutter   # Launch specific bench
    launchDevBench --help    # Show help
EOF
}

# Main function
main() {
    case "$1" in
        --install)
            print_info "Installing launchDevBench globally..."
            install_launchdevbench
            exit $?
            ;;
        --uninstall)
            print_info "Uninstalling launchDevBench..."
            uninstall_launchdevbench
            exit $?
            ;;
        --status)
            show_status
            exit 0
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            echo "launchDevBench Global Installer"
            echo ""
            echo "Use --help to see available options"
            echo ""
            echo "Quick start:"
            echo "  $0 --install    # Install globally"
            echo "  $0 --status     # Check status"
            ;;
    esac
}

main "$@"