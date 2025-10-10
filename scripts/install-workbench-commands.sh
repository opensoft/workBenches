#!/bin/bash

# =============================================================================
# install-workbench-commands.sh - Global WorkBenches Commands Installer
# =============================================================================
# Installs key workBenches commands globally for easy access from anywhere
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKBENCHES_ROOT="$(dirname "$SCRIPT_DIR")"

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

# Commands to install globally
declare -A COMMANDS=(
    ["launchBench"]="Universal bench launcher with AI-powered routing"
    ["onp"]="Opensoft New Project - Quick project creation command"
    ["setup-workbenches"]="WorkBenches setup and configuration"
    ["update-bench-config"]="Auto-discover and update bench configuration"
    ["new-bench"]="Create new development benches with AI assistance"
    ["workbench-config"]="Shared configuration manager for all workbench types"
    ["update-project"]="AI-powered universal project updater for all bench types"
)

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
        echo "# Added by workBenches installer"
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

# Create wrapper script for a command
create_command_wrapper() {
    local command_name="$1"
    local original_path="$2"
    local install_path="$3"
    local description="$4"
    
    # Get the actual script file name from the original path
    local script_filename=$(basename "$original_path")
    
    # Create wrapper script
    cat > "$install_path/$command_name" << EOF
#!/bin/bash
# $description
# Auto-generated wrapper by workBenches installer

# Get the directory where this wrapper is located
WRAPPER_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"

# Try to find workBenches installation
WORKBENCHES_ROOT=""

# Check if we have a stored path
if [ -f "\$WRAPPER_DIR/.workbenches-path" ]; then
    WORKBENCHES_ROOT="\$(cat "\$WRAPPER_DIR/.workbenches-path")"
fi

# Validate the stored path
if [ -z "\$WORKBENCHES_ROOT" ] || [ ! -f "\$WORKBENCHES_ROOT/scripts/$script_filename" ]; then
    # Try to find workBenches in common locations
    SEARCH_PATHS=(
        "$WORKBENCHES_ROOT"
        "\$HOME/projects/workBenches"
        "\$HOME/workBenches"
        "\$HOME/Projects/workBenches"
        "\$HOME/code/workBenches"
        "\$HOME/development/workBenches"
    )
    
    for path in "\${SEARCH_PATHS[@]}"; do
        if [ -f "\$path/scripts/$script_filename" ]; then
            WORKBENCHES_ROOT="\$path"
            # Store the found path for next time
            echo "\$WORKBENCHES_ROOT" > "\$WRAPPER_DIR/.workbenches-path"
            break
        fi
    done
fi

# Execute the actual command
if [ -n "\$WORKBENCHES_ROOT" ] && [ -f "\$WORKBENCHES_ROOT/scripts/$script_filename" ]; then
    exec "\$WORKBENCHES_ROOT/scripts/$script_filename" "\$@"
else
    echo "❌ Error: Could not locate workBenches installation"
    echo "Expected to find: workBenches/scripts/$script_filename"
    echo ""
    echo "Please ensure workBenches is properly installed and try:"
    echo "  setup-workbenches --install-commands"
    exit 1
fi
EOF
    
    chmod +x "$install_path/$command_name"
    return 0
}

# Install all workBench commands
install_commands() {
    print_info "Installing workBenches commands globally..."
    
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
    
    print_info "Installing to: $install_dir"
    
    # Store workbenches path for wrappers
    echo "$WORKBENCHES_ROOT" > "$install_dir/.workbenches-path"
    
    # Install each command
    local installed_count=0
    for cmd_name in "${!COMMANDS[@]}"; do
        local cmd_desc="${COMMANDS[$cmd_name]}"
        local source_script=""
        
        # Map command names to script files
        case "$cmd_name" in
            "launchBench")
                source_script="$SCRIPT_DIR/launchBench"
                ;;
            "onp")
                source_script="$SCRIPT_DIR/onp"
                ;;
            "setup-workbenches")
                source_script="$SCRIPT_DIR/setup-workbenches.sh"
                ;;
            "update-bench-config")
                source_script="$SCRIPT_DIR/update-bench-config.sh"
                ;;
            "new-bench")
                source_script="$SCRIPT_DIR/new-bench.sh"
                ;;
            "workbench-config")
                source_script="$SCRIPT_DIR/workbench-config.sh"
                ;;
            "update-project")
                source_script="$SCRIPT_DIR/update-project.sh"
                ;;
        esac
        
        # Verify source script exists
        if [ ! -f "$source_script" ]; then
            print_warning "Source script not found: $source_script"
            continue
        fi
        
        # Create wrapper
        if create_command_wrapper "$cmd_name" "$source_script" "$install_dir" "$cmd_desc"; then
            print_success "Installed: $cmd_name"
            ((installed_count++))
        else
            print_error "Failed to install: $cmd_name"
        fi
    done
    
    print_success "Installed $installed_count commands"
    
    # Check PATH
    if ! is_in_path "$install_dir"; then
        print_warning "$install_dir is not in your PATH"
        if add_to_path "$install_dir"; then
            print_info "PATH updated - restart your shell to use commands globally"
        else
            print_warning "You may need to manually add $install_dir to your PATH"
        fi
    else
        print_success "$install_dir is already in your PATH"
        print_success "Commands are now available globally!"
    fi
    
    return 0
}

# Uninstall workBench commands
uninstall_commands() {
    local removed_any=false
    
    # Check common installation locations
    local locations=("$HOME/.local/bin" "/usr/local/bin")
    
    for location in "${locations[@]}"; do
        for cmd_name in "${!COMMANDS[@]}"; do
            if [ -f "$location/$cmd_name" ]; then
                print_info "Removing $cmd_name from: $location"
                rm -f "$location/$cmd_name"
                
                if [ $? -eq 0 ]; then
                    print_success "Removed $cmd_name from $location"
                    removed_any=true
                else
                    print_error "Failed to remove $cmd_name from $location"
                fi
            fi
        done
        
        # Remove workbenches path file
        if [ -f "$location/.workbenches-path" ]; then
            rm -f "$location/.workbenches-path"
        fi
    done
    
    if [ "$removed_any" = true ]; then
        print_success "WorkBenches commands uninstalled successfully"
        print_warning "PATH modifications in shell profiles were not removed automatically"
    else
        print_warning "No workBenches commands found to remove"
    fi
}

# Show installation status
show_status() {
    print_info "WorkBenches Commands Installation Status:"
    echo ""
    
    local found_installations=0
    local locations=("$HOME/.local/bin" "/usr/local/bin")
    
    for location in "${locations[@]}"; do
        local found_in_location=false
        
        for cmd_name in "${!COMMANDS[@]}"; do
            if [ -f "$location/$cmd_name" ]; then
                if [ "$found_in_location" = false ]; then
                    echo -e "${BLUE}$location:${NC}"
                    found_in_location=true
                    found_installations=$((found_installations + 1))
                fi
                
                printf "  ${GREEN}✓${NC} %-20s %s\n" "$cmd_name" "${COMMANDS[$cmd_name]}"
                
                # Check if it's executable and in PATH
                if [ -x "$location/$cmd_name" ]; then
                    if command -v "$cmd_name" >/dev/null 2>&1; then
                        echo "    ${GREEN}✓ Available globally${NC}"
                    else
                        echo "    ${YELLOW}⚠ Not in PATH${NC}"
                    fi
                else
                    echo "    ${RED}✗ Not executable${NC}"
                fi
            fi
        done
        
        if [ "$found_in_location" = true ]; then
            echo ""
        fi
    done
    
    if [ $found_installations -eq 0 ]; then
        print_warning "No workBenches commands installed globally"
        print_info "Run: $0 --install"
    fi
}

# Show help
show_help() {
    cat << EOF
WorkBenches Commands Global Installer

USAGE:
    $0 [OPTION]

OPTIONS:
    --install     Install workBenches commands globally
    --uninstall   Remove workBenches commands from global installation
    --status      Show installation status
    --help, -h    Show this help message

COMMANDS INSTALLED:
$(for cmd in "${!COMMANDS[@]}"; do
    printf "    %-20s %s\n" "$cmd" "${COMMANDS[$cmd]}"
done)

INSTALLATION:
    This installer will:
    1. Create command wrappers in ~/.local/bin (preferred) or /usr/local/bin
    2. Make commands executable and globally accessible
    3. Add installation directory to PATH (if needed)
    4. Store workBenches location for dynamic path resolution

USAGE AFTER INSTALLATION:
    launchBench                   # Launch any bench with AI routing
    onp myproject                 # Quick project creation
    setup-workbenches            # Setup and configure workBenches
    update-bench-config          # Update bench configuration
    new-bench                    # Create new development benches

REQUIREMENTS:
    - workBenches must be properly set up
    - Write access to ~/.local/bin or /usr/local/bin
EOF
}

# Main function
main() {
    case "$1" in
        --install)
            print_info "Installing workBenches commands globally..."
            install_commands
            exit $?
            ;;
        --uninstall)
            print_info "Uninstalling workBenches commands..."
            uninstall_commands
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
            echo "WorkBenches Commands Global Installer"
            echo ""
            echo "Use --help to see available options"
            echo ""
            echo "Quick start:"
            echo "  $0 --install    # Install commands globally"
            echo "  $0 --status     # Check installation status"
            ;;
    esac
}

main "$@"