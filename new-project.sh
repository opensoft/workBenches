#!/bin/bash

# WorkBenches New Project Script
# Lists installed benches and creates projects using bench-specific scripts

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/bench-config.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check dependencies
check_dependencies() {
    local missing_deps=()
    
    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo -e "${RED}Error: Missing required dependencies: ${missing_deps[*]}${NC}"
        echo "Please install the missing dependencies and run again."
        exit 1
    fi
}

# Check if a bench is installed
is_bench_installed() {
    local bench_name="$1"
    local bench_path
    bench_path=$(jq -r ".benches.${bench_name}.path" "$CONFIG_FILE" 2>/dev/null)
    
    if [ "$bench_path" != "null" ] && [ -d "$SCRIPT_DIR/$bench_path" ]; then
        return 0
    fi
    return 1
}

# Get available project types from installed benches
get_available_project_types() {
    local project_types=()
    
    while IFS= read -r bench_name; do
        if is_bench_installed "$bench_name"; then
            local project_scripts
            project_scripts=$(jq -r ".benches.${bench_name}.project_scripts[]? | .name" "$CONFIG_FILE" 2>/dev/null)
            
            if [ -n "$project_scripts" ]; then
                while IFS= read -r script_name; do
                    if [ -n "$script_name" ] && [ "$script_name" != "null" ]; then
                        project_types+=("${bench_name}:${script_name}")
                    fi
                done <<< "$project_scripts"
            fi
        fi
    done < <(jq -r '.benches | keys[]' "$CONFIG_FILE" 2>/dev/null)
    
    printf '%s\n' "${project_types[@]}"
}

# Show available project types
show_available_project_types() {
    local available_types
    mapfile -t available_types < <(get_available_project_types)
    
    if [ ${#available_types[@]} -eq 0 ]; then
        echo -e "${RED}No project creation scripts found in installed benches.${NC}"
        echo ""
        echo "Available benches with project creation capabilities:"
        echo "  - flutterBench: Has Flutter and DartWing project creation scripts"
        echo ""
        echo "To install benches, run: ./setup-workbenches.sh"
        return 1
    fi
    
    echo -e "${YELLOW}Available project types:${NC}"
    echo ""
    
    local counter=1
    for type in "${available_types[@]}"; do
        local bench_name="${type%%:*}"
        local script_name="${type##*:}"
        local bench_desc
        local script_desc
        
        bench_desc=$(jq -r ".benches.${bench_name}.description" "$CONFIG_FILE")
        script_desc=$(jq -r ".benches.${bench_name}.project_scripts[] | select(.name==\"$script_name\") | .description" "$CONFIG_FILE")
        
        echo -e "${BLUE}$counter) $script_name${NC} (${bench_name})"
        echo -e "   ${script_desc}"
        echo -e "   ${GREEN}✓ Includes specKit for spec-driven development${NC}"
        echo ""
        ((counter++))
    done
    
    return 0
}

# Prompt for project type selection
prompt_project_type() {
    local available_types
    mapfile -t available_types < <(get_available_project_types)
    
    while true; do
        read -p "Enter your choice (1-${#available_types[@]}): " choice
        
        # Validate input
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#available_types[@]} ]; then
            local selected_type="${available_types[$((choice-1))]}"
            echo "$selected_type"
            return 0
        else
            echo -e "${RED}Invalid choice. Please enter a number between 1 and ${#available_types[@]}.${NC}"
        fi
    done
}

# Get project name and optional target directory
get_project_details() {
    echo -e "${YELLOW}Project configuration:${NC}"
    
    # Get project name
    while true; do
        read -p "Enter project name: " project_name
        if [ -n "$project_name" ]; then
            # Validate project name (basic alphanumeric with hyphens/underscores)
            if [[ "$project_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
                break
            else
                echo -e "${RED}Invalid project name. Use only letters, numbers, hyphens, and underscores.${NC}"
            fi
        else
            echo -e "${RED}Project name cannot be empty.${NC}"
        fi
    done
    
    # Get optional target directory
    echo ""
    echo "Target directory options:"
    echo "  1) Use default (~/projects/$project_name)"
    echo "  2) Specify custom directory"
    echo ""
    
    local target_dir=""
    while true; do
        read -p "Enter your choice (1-2): " dir_choice
        case $dir_choice in
            1)
                target_dir=""
                break
                ;;
            2)
                read -p "Enter target directory (project will be created as subdirectory): " target_dir
                if [ -n "$target_dir" ]; then
                    # Expand tilde if present
                    target_dir="${target_dir/#\~/$HOME}"
                    
                    # Check if directory exists
                    if [ ! -d "$target_dir" ]; then
                        echo -e "${YELLOW}Warning: Directory $target_dir does not exist.${NC}"
                        read -p "Create it? [y/N]: " create_dir
                        case $create_dir in
                            [Yy]* )
                                mkdir -p "$target_dir" || {
                                    echo -e "${RED}Failed to create directory: $target_dir${NC}"
                                    continue
                                }
                                break
                                ;;
                            * )
                                continue
                                ;;
                        esac
                    else
                        break
                    fi
                else
                    echo -e "${RED}Target directory cannot be empty.${NC}"
                fi
                ;;
            *)
                echo -e "${RED}Invalid choice. Please enter 1 or 2.${NC}"
                ;;
        esac
    done
    
    echo "${project_name}|${target_dir}"
}

# Copy specKit to a project directory
copy_speckit_to_project() {
    local project_path="$1"
    local speckit_source="$SCRIPT_DIR/specKit"
    
    echo -e "${CYAN}📋 Copying specKit for spec-driven development...${NC}"
    
    if [ ! -d "$speckit_source" ]; then
        echo -e "${RED}Error: specKit not found at $speckit_source${NC}"
        echo "Run ./setup-workbenches.sh to install specKit"
        return 1
    fi
    
    if [ ! -d "$project_path" ]; then
        echo -e "${RED}Error: Project directory not found: $project_path${NC}"
        return 1
    fi
    
    # Copy specKit contents (excluding .git)
    if cp -r "$speckit_source"/* "$project_path/" 2>/dev/null; then
        # Copy hidden files, ignore errors for files that don't exist
        cp -r "$speckit_source"/.[^.]* "$project_path/" 2>/dev/null || true
        
        # Remove git-related files if they were copied
        rm -rf "$project_path/.git" 2>/dev/null || true
        
        echo -e "${GREEN}✓ specKit copied successfully to project${NC}"
        return 0
    else
        echo -e "${RED}Error: Failed to copy specKit to project${NC}"
        return 1
    fi
}

# Execute the bench-specific project creation script
create_project() {
    local bench_name="$1"
    local script_name="$2"
    local project_name="$3"
    local target_dir="$4"
    
    # Get bench path and script path
    local bench_path
    local script_path
    bench_path=$(jq -r ".benches.${bench_name}.path" "$CONFIG_FILE")
    script_path=$(jq -r ".benches.${bench_name}.project_scripts[] | select(.name==\"$script_name\") | .script" "$CONFIG_FILE")
    
    local full_script_path="$SCRIPT_DIR/$bench_path/$script_path"
    
    # Verify script exists and is executable
    if [ ! -f "$full_script_path" ]; then
        echo -e "${RED}Error: Script not found: $full_script_path${NC}"
        return 1
    fi
    
    if [ ! -x "$full_script_path" ]; then
        echo -e "${YELLOW}Making script executable: $full_script_path${NC}"
        chmod +x "$full_script_path"
    fi
    
    # Show what we're about to do
    echo -e "${CYAN}Creating $script_name project...${NC}"
    echo -e "${BLUE}Project name:${NC} $project_name"
    echo -e "${BLUE}Script:${NC} $full_script_path"
    if [ -n "$target_dir" ]; then
        echo -e "${BLUE}Target directory:${NC} $target_dir"
        echo -e "${BLUE}Full path:${NC} $target_dir/$project_name"
    else
        echo -e "${BLUE}Target directory:${NC} ~/projects (default)"
        echo -e "${BLUE}Full path:${NC} ~/projects/$project_name"
    fi
    echo ""
    
    # Execute the script
    local script_exit_code=0
    if [ -n "$target_dir" ]; then
        "$full_script_path" "$project_name" "$target_dir"
        script_exit_code=$?
    else
        "$full_script_path" "$project_name"
        script_exit_code=$?
    fi
    
    # Check if the bench script includes specKit copying
    local includes_speckit
    includes_speckit=$(jq -r ".benches.${bench_name}.project_scripts[] | select(.name==\"$script_name\") | .includes_speckit // false" "$CONFIG_FILE")
    
    # If the script succeeded and doesn't include specKit, copy it ourselves
    if [ $script_exit_code -eq 0 ] && [ "$includes_speckit" != "true" ]; then
        echo ""
        echo -e "${YELLOW}Adding specKit for spec-driven development...${NC}"
        
        # Determine the project path
        local project_path
        if [ -n "$target_dir" ]; then
            project_path="$target_dir/$project_name"
        else
            project_path="$HOME/projects/$project_name"
        fi
        
        copy_speckit_to_project "$project_path"
    fi
    
    return $script_exit_code
}

# Show usage information
show_usage() {
    echo "Usage: $0 [project-name] [target-directory]"
    echo ""
    echo "Arguments:"
    echo "  project-name      Optional: Name of the project to create"
    echo "  target-directory  Optional: Directory where project should be created"
    echo ""
    echo "Examples:"
    echo "  $0                          # Interactive mode"
    echo "  $0 myapp                    # Interactive type selection for 'myapp'"
    echo "  $0 myapp ~/custom/path      # Interactive type selection with custom path"
    echo ""
    echo "This script will:"
    echo "  1. Show available project types from installed benches"
    echo "  2. Let you select the project type"
    echo "  3. Delegate to the appropriate bench-specific script"
    echo ""
}

# Main function
main() {
    echo -e "${BLUE}WorkBenches New Project Script${NC}"
    echo "=============================="
    echo ""
    
    # Check for help flag
    if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        show_usage
        exit 0
    fi
    
    check_dependencies
    
    # Load configuration
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}Error: Configuration file not found: $CONFIG_FILE${NC}"
        exit 1
    fi
    
    # Show available project types
    if ! show_available_project_types; then
        exit 1
    fi
    
    # Get project type selection
    echo "Which type of project would you like to create?"
    local selected_type
    selected_type=$(prompt_project_type)
    
    local bench_name="${selected_type%%:*}"
    local script_name="${selected_type##*:}"
    
    echo ""
    echo -e "${GREEN}Selected: $script_name project (from $bench_name)${NC}"
    echo ""
    
    # Get project details (name and optional directory)
    local project_details project_name target_dir
    
    if [ -n "$1" ]; then
        # Project name provided as argument
        project_name="$1"
        target_dir="$2"
        echo -e "${BLUE}Using provided project name:${NC} $project_name"
        if [ -n "$target_dir" ]; then
            echo -e "${BLUE}Using provided target directory:${NC} $target_dir"
        fi
    else
        # Interactive mode
        project_details=$(get_project_details)
        project_name="${project_details%%|*}"
        target_dir="${project_details##*|}"
    fi
    
    echo ""
    
    # Create the project
    create_project "$bench_name" "$script_name" "$project_name" "$target_dir"
    
    echo ""
    echo -e "${GREEN}Project creation completed successfully!${NC}"
    echo -e "${BLUE}Your project includes specKit for spec-driven development.${NC}"
    echo -e "${BLUE}Use /constitution, /specify, /plan, /tasks, /implement commands in your AI coding assistant.${NC}"
}

# Run main function
main "$@"