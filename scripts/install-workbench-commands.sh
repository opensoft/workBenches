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
    ["project"]="Create, inspect, diagnose and maintain projects"
    ["launchBench"]="Universal bench launcher with AI-powered routing"
    ["onp"]="Opensoft New Project - Quick project creation command"
    ["new-workspace"]="Intelligent workspace creator - routes to Frappe, Flutter, .NET, etc."
    ["update-workspace"]="Intelligent workspace updater - routes to appropriate updater"
    ["delete-workspace"]="Intelligent workspace deleter - routes to appropriate deleter"
    ["setup-workbenches"]="WorkBenches setup and configuration"
    ["update-bench-config"]="Auto-discover and update bench configuration"
    ["new-bench"]="Create new development benches with AI assistance"
    ["workbench-config"]="Shared configuration manager for all workbench types"
    ["update-project"]="AI-powered universal project updater for all bench types"
    ["amnezia-endpoint"]="Amnezia endpoint manifest client wrapper"
)

# Check if running with sufficient privileges
check_install_location() {
    # User-local installation is always the default. The caller creates it.
    echo "$HOME/.local/bin"
}

configured_install_location() {
    local install_dir="${OPENREPOPROJECT_BIN_DIR:-}"
    [ -n "$install_dir" ] || return 1
    case "$install_dir" in
        '~') install_dir="$HOME" ;;
        '~/'*) install_dir="$HOME/${install_dir#'~/'}" ;;
    esac
    [[ "$install_dir" == /* ]] || return 2
    printf '%s\n' "$install_dir"
}

configured_discovery_file() {
    local discovery_file="${WORKBENCHES_PROJECT_DISCOVERY_FILE:-$HOME/.config/workbenches/project-bin}"
    case "$discovery_file" in
        '~') discovery_file="$HOME" ;;
        '~/'*) discovery_file="$HOME/${discovery_file#'~/'}" ;;
    esac
    [[ "$discovery_file" == /* ]] || return 2
    printf '%s\n' "$discovery_file"
}

persisted_install_location() {
    local mode="${1:-owned}"
    local discovery_file discovered_dir extra_line
    discovery_file="$(configured_discovery_file)" || return $?
    [ -f "$discovery_file" ] && [ ! -L "$discovery_file" ] || return 1
    IFS= read -r discovered_dir < "$discovery_file" || return 1
    IFS= read -r extra_line < <(sed -n '2p' "$discovery_file") || true
    [ -z "$extra_line" ] || return 1
    [[ "$discovered_dir" == /* ]] || return 1
    if ! python3 -I "$SCRIPT_DIR/setup-project-command.py" \
            --bin-dir "$discovered_dir" --resolve-owned >/dev/null 2>&1; then
        if [ "$mode" != "remove" ] \
            || ! python3 -I "$SCRIPT_DIR/setup-project-command.py" \
                --bin-dir "$discovered_dir" --resolve-removal-pending \
                >/dev/null 2>&1; then
            return 1
        fi
    fi
    printf '%s\n' "$discovered_dir"
}

ensure_workbenches_marker() {
    local install_dir="$1"
    local marker="$install_dir/.workbenches-path"
    local staged_marker

    staged_marker="$(mktemp "$install_dir/.workbenches-path.stage.XXXXXX")" || return 1
    if ! printf '%s\n' "$WORKBENCHES_ROOT" > "$staged_marker" \
        || ! chmod 0644 "$staged_marker"; then
        rm -f -- "$staged_marker"
        return 1
    fi
    if [ -L "$marker" ] || { [ -e "$marker" ] && [ ! -f "$marker" ]; }; then
        print_error "Refusing non-regular workBenches path marker: $marker"
        rm -f -- "$staged_marker"
        return 1
    fi
    if [ -f "$marker" ]; then
        if cmp -s "$staged_marker" "$marker"; then
            rm -f -- "$staged_marker"
            return 0
        fi
        print_error "Refusing to replace a different workBenches path marker: $marker"
        rm -f -- "$staged_marker"
        return 1
    fi
    if ln "$staged_marker" "$marker" 2>/dev/null; then
        rm -f -- "$staged_marker"
        return 0
    fi
    if [ -f "$marker" ] && [ ! -L "$marker" ] \
        && cmp -s "$staged_marker" "$marker"; then
        rm -f -- "$staged_marker"
        return 0
    fi
    print_error "Concurrent workBenches path marker collision: $marker"
    rm -f -- "$staged_marker"
    return 1
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
    local login_shell
    login_shell="$(basename "${SHELL:-}")"
    
    # Determine shell profile file
    if [ "$login_shell" = "zsh" ] || [ -n "$ZSH_VERSION" ]; then
        shell_profile="$HOME/.zshrc"
    elif [ "$login_shell" = "bash" ] || [ -n "$BASH_VERSION" ]; then
        if [ -f "$HOME/.bashrc" ]; then
            shell_profile="$HOME/.bashrc"
        else
            shell_profile="$HOME/.bash_profile"
        fi
    else
        shell_profile="$HOME/.profile"
    fi
    
    print_info "Adding $dir to PATH in $shell_profile"
    
    local quoted_dir
    quoted_dir="'${dir//\'/\'\\\'\'}'"

    # Check if this exact safely quoted path is already present.
    if grep -Fq -- "$quoted_dir" "$shell_profile" 2>/dev/null; then
        print_warning "PATH modification already exists in $shell_profile"
        return 0
    fi
    
    # Add PATH modification
    {
        echo ""
        echo "# Added by workBenches installer"
        printf 'if [ -d %s ]; then\n' "$quoted_dir"
        printf '    export PATH=%s:"$PATH"\n' "$quoted_dir"
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
    local write_status=$?
    [ "$write_status" -eq 0 ] || return "$write_status"
    chmod +x "$install_path/$command_name" || return $?
    return 0
}

# Install all workBench commands
install_commands() {
    print_info "Installing workBenches commands globally..."
    
    # Determine installation directory
    local install_dir
    if [ -n "${OPENREPOPROJECT_BIN_DIR:-}" ]; then
        if ! install_dir="$(configured_install_location)"; then
            print_error "OPENREPOPROJECT_BIN_DIR must be an absolute path"
            return 1
        fi
        if [ -e "$install_dir" ] && [ ! -d "$install_dir" ]; then
            print_error "Configured installation path is not a directory: $install_dir"
            return 1
        fi
        if [ -d "$install_dir" ] && [ ! -w "$install_dir" ]; then
            print_error "Configured installation directory is not writable: $install_dir"
            return 1
        fi
    else
        install_dir=$(check_install_location)
    fi
    
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

    if [ ! -d "$install_dir" ]; then
        if ! mkdir -p "$install_dir"; then
            print_error "Failed to create installation directory: $install_dir"
            return 1
        fi
    fi
    if [ ! -w "$install_dir" ]; then
        print_error "Installation directory is not writable: $install_dir"
        return 1
    fi
    
    print_info "Installing to: $install_dir"

    # Install the authoritative executable; do not replace it with a wrapper.
    # A skip is successful but does not authorize project-dependent wrappers.
    local project_available=false
    if [ "${WORKBENCHES_SKIP_PROJECT_COMMAND:-0}" = "1" ]; then
        print_warning "Project command was skipped; preserving any existing command and omitting onp"
    else
        python3 -I "$SCRIPT_DIR/setup-project-command.py" \
            --bin-dir "$install_dir" --workbenches "$WORKBENCHES_ROOT" \
            --install-onp || return $?
        if python3 -I "$SCRIPT_DIR/setup-project-command.py" \
            --bin-dir "$install_dir" --resolve-owned >/dev/null 2>&1; then
            project_available=true
        else
            print_error "Project command installation did not produce a verified executable"
            return 1
        fi
    fi

    ensure_workbenches_marker "$install_dir" || return $?
    
    # Install each command
    local installed_count=0
    local install_failed=false
    for cmd_name in "${!COMMANDS[@]}"; do
        if [ "$cmd_name" = "project" ]; then
            if [ "$project_available" = true ]; then
                # Already installed and verified by its dedicated installer above.
                installed_count=$((installed_count + 1))
            fi
            continue
        fi
        if [ "$cmd_name" = "onp" ] && [ "$project_available" = false ]; then
            continue
        fi
        if [ "$cmd_name" = "onp" ]; then
            print_success "Installed: onp"
            ((installed_count++))
            continue
        fi
        local cmd_desc="${COMMANDS[$cmd_name]}"
        local source_script=""
        
        # Map command names to script files
        case "$cmd_name" in
            "launchBench")
                source_script="$SCRIPT_DIR/launchBench"
                ;;
            "new-workspace")
                source_script="$SCRIPT_DIR/new-workspace.sh"
                ;;
            "update-workspace")
                source_script="$SCRIPT_DIR/update-workspace.sh"
                ;;
            "delete-workspace")
                source_script="$SCRIPT_DIR/delete-workspace.sh"
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
            "amnezia-endpoint")
                source_script="$SCRIPT_DIR/amnezia-endpoint"
                ;;
        esac
        
        # Verify source script exists
        if [ ! -f "$source_script" ]; then
            print_warning "Source script not found: $source_script"
            install_failed=true
            continue
        fi
        
        # Create wrapper
        if create_command_wrapper "$cmd_name" "$source_script" "$install_dir" "$cmd_desc"; then
            print_success "Installed: $cmd_name"
            ((installed_count++))
        else
            print_error "Failed to install: $cmd_name"
            install_failed=true
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
    
    if [ "$install_failed" = true ]; then
        print_error "One or more command wrappers could not be installed"
        return 1
    fi
    return 0
}

# Uninstall workBench commands
uninstall_commands() {
    local removed_any=false
    local uninstall_failed=false
    local project_remove_status
    local configured_dir=""
    
    # Check common installation locations
    local locations=("$HOME/.local/bin" "/usr/local/bin")
    if [ -n "${OPENREPOPROJECT_BIN_DIR:-}" ]; then
        if ! configured_dir="$(configured_install_location)"; then
            print_error "OPENREPOPROJECT_BIN_DIR must be an absolute path"
            return 1
        fi
        if [ "$configured_dir" != "$HOME/.local/bin" ] \
            && [ "$configured_dir" != "/usr/local/bin" ]; then
            locations=("$configured_dir" "${locations[@]}")
        fi
    else
        local discovery_status=0
        configured_dir="$(persisted_install_location remove)" || discovery_status=$?
        if [ "$discovery_status" -eq 2 ]; then
            print_error "WORKBENCHES_PROJECT_DISCOVERY_FILE must be an absolute path"
            return 1
        fi
        if [ "$discovery_status" -eq 0 ] \
            && [ "$configured_dir" != "$HOME/.local/bin" ] \
            && [ "$configured_dir" != "/usr/local/bin" ]; then
            locations=("$configured_dir" "${locations[@]}")
        fi
    fi
    
    for location in "${locations[@]}"; do
        for cmd_name in "${!COMMANDS[@]}"; do
            if [ "$cmd_name" = "project" ]; then
                python3 -I "$SCRIPT_DIR/setup-project-command.py" --bin-dir "$location" --remove
                project_remove_status=$?
                if [ "$project_remove_status" -eq 0 ]; then
                    print_success "Removed installer-owned project artifacts from $location"
                    removed_any=true
                elif [ "$project_remove_status" -ne 3 ]; then
                    print_error "Failed to verify project ownership in $location"
                    uninstall_failed=true
                fi
                continue
            fi
            # The project installer verifies and removes its onp alias. Never
            # pass a colliding user-owned command to the generic remover.
            if [ "$cmd_name" = "onp" ]; then
                continue
            fi
            if [ -f "$location/$cmd_name" ]; then
                print_info "Removing $cmd_name from: $location"
                rm -f "$location/$cmd_name"
                
                if [ $? -eq 0 ]; then
                    print_success "Removed $cmd_name from $location"
                    removed_any=true
                else
                    print_error "Failed to remove $cmd_name from $location"
                    uninstall_failed=true
                fi
            fi
        done
        
        # Remove workbenches path file
        if [ -f "$location/.workbenches-path" ]; then
            if ! rm -f "$location/.workbenches-path"; then
                print_error "Failed to remove workBenches path marker from $location"
                uninstall_failed=true
            fi
        fi
    done
    
    if [ "$uninstall_failed" = true ]; then
        print_error "One or more installer-owned project artifacts could not be removed"
        return 1
    elif [ "$removed_any" = true ]; then
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
    local configured_dir=""
    local locations=("$HOME/.local/bin" "/usr/local/bin")
    if [ -n "${OPENREPOPROJECT_BIN_DIR:-}" ]; then
        if ! configured_dir="$(configured_install_location)"; then
            print_error "OPENREPOPROJECT_BIN_DIR must be an absolute path"
            return 1
        fi
        if [ "$configured_dir" != "$HOME/.local/bin" ] \
            && [ "$configured_dir" != "/usr/local/bin" ]; then
            locations=("$configured_dir" "${locations[@]}")
        fi
    else
        local discovery_status=0
        configured_dir="$(persisted_install_location)" || discovery_status=$?
        if [ "$discovery_status" -eq 2 ]; then
            print_error "WORKBENCHES_PROJECT_DISCOVERY_FILE must be an absolute path"
            return 1
        fi
        if [ "$discovery_status" -eq 0 ] \
            && [ "$configured_dir" != "$HOME/.local/bin" ] \
            && [ "$configured_dir" != "/usr/local/bin" ]; then
            locations=("$configured_dir" "${locations[@]}")
        fi
    fi
    
    for location in "${locations[@]}"; do
        local location_header_printed=false
        local found_in_location=false
        
        for cmd_name in "${!COMMANDS[@]}"; do
            if [ -f "$location/$cmd_name" ]; then
                if [ "$location_header_printed" = false ]; then
                    echo -e "${BLUE}$location:${NC}"
                    location_header_printed=true
                fi

                local ownership_option=""
                [ "$cmd_name" = "project" ] && ownership_option="--resolve-owned"
                [ "$cmd_name" = "onp" ] && ownership_option="--resolve-onp-owned"
                if [ -n "$ownership_option" ] \
                    && ! python3 -I "$SCRIPT_DIR/setup-project-command.py" \
                        --bin-dir "$location" "$ownership_option" >/dev/null 2>&1; then
                    printf "  ${RED}✗${NC} %-20s %s (unowned or tampered)\n" \
                        "$cmd_name" "${COMMANDS[$cmd_name]}"
                    continue
                fi

                if [ "$found_in_location" = false ]; then
                    found_in_location=true
                    found_installations=$((found_installations + 1))
                fi
                
                printf "  ${GREEN}✓${NC} %-20s %s\n" "$cmd_name" "${COMMANDS[$cmd_name]}"
                
                # Check if it's executable and in PATH
                if [ -x "$location/$cmd_name" ]; then
                    resolved_command="$(command -v "$cmd_name" 2>/dev/null || true)"
                    if [ "$resolved_command" = "$location/$cmd_name" ]; then
                        echo "    ${GREEN}✓ Available globally${NC}"
                    elif [ -n "$resolved_command" ]; then
                        echo "    ${YELLOW}⚠ Shadowed in PATH by $resolved_command${NC}"
                    else
                        echo "    ${YELLOW}⚠ Not in PATH${NC}"
                    fi
                else
                    echo "    ${RED}✗ Not executable${NC}"
                fi
            fi
        done
        
        if [ "$location_header_printed" = true ]; then
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
    amnezia-endpoint list        # List current Amnezia VPN endpoints

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
            exit $?
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
