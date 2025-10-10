#!/bin/bash

# WorkBenches New Project Script
# Uses AI to determine project type and creates projects using bench-specific scripts

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../config/bench-config.json"

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
    
    if ! command -v curl &> /dev/null; then
        missing_deps+=("curl")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo -e "${RED}Error: Missing required dependencies: ${missing_deps[*]}${NC}"
        echo "Please install the missing dependencies and run again."
        exit 1
    fi
}

# AI-powered project type detection
analyze_project_with_ai() {
    local project_description="$1"
    local available_benches="$2"
    
    echo -e "${CYAN}🤖 Analyzing project requirements with AI...${NC}" >&2
    
    # Prepare AI prompt
    local ai_prompt="Based on the following project description, determine which development environment would be most suitable:

Project Description: $project_description

Available environments:
$available_benches

Please respond with ONLY the bench name (like 'flutterBench', 'pythonBench', etc.) that best matches the project requirements. If uncertain, respond with 'UNCERTAIN'."
    
    # Try to get AI response using Warp AI or fallback methods
    local ai_response=""
    
    # Method 1: Try using Warp AI through environment variables if available
    if command -v warp &> /dev/null && [ -n "$WARP_AI_API_KEY" ]; then
        ai_response=$(echo "$ai_prompt" | warp ai --stdin 2>/dev/null | tail -n1 | tr -d '\n' || echo "")
    fi
    
    # Method 2: Try Claude API if available
    if [ -z "$ai_response" ] && [ -n "$CLAUDE_API_KEY" ]; then
        ai_response=$(curl -s -X POST "https://api.anthropic.com/v1/messages" \
            -H "Content-Type: application/json" \
            -H "x-api-key: $CLAUDE_API_KEY" \
            -H "anthropic-version: 2023-06-01" \
            -d "{
                \"model\": \"claude-3-haiku-20240307\",
                \"max_tokens\": 50,
                \"messages\": [
                    {\"role\": \"user\", \"content\": \"$ai_prompt\"}
                ]
            }" | jq -r '.content[0].text' 2>/dev/null || echo "")
    fi
    
    # Method 3: Simple keyword matching as fallback
    if [ -z "$ai_response" ] || [ "$ai_response" = "null" ]; then
        ai_response=$(analyze_project_keywords "$project_description")
    fi
    
    # Clean up the response
    ai_response=$(echo "$ai_response" | tr -d '"' | tr -d "'" | xargs)
    
    echo "$ai_response"
}

# Fallback keyword-based analysis
analyze_project_keywords() {
    local description="$1"
    local desc_lower=$(echo "$description" | tr '[:upper:]' '[:lower:]')
    
    # Check each bench's keywords
    while IFS= read -r bench_name; do
        if is_bench_installed "$bench_name"; then
            local keywords
            keywords=$(jq -r ".benches.${bench_name}.ai_keywords[]?" "$CONFIG_FILE" 2>/dev/null)
            
            if [ -n "$keywords" ]; then
                while IFS= read -r keyword; do
                    if [[ "$desc_lower" == *"$keyword"* ]]; then
                        echo "$bench_name"
                        return 0
                    fi
                done <<< "$keywords"
            fi
        fi
    done < <(jq -r '.benches | keys[]' "$CONFIG_FILE" 2>/dev/null)
    
    echo "UNCERTAIN"
}

# Get available benches for AI prompt
get_available_benches_for_ai() {
    local bench_list=""
    
    while IFS= read -r bench_name; do
        if is_bench_installed "$bench_name"; then
            local description
            local keywords
            description=$(jq -r ".benches.${bench_name}.description" "$CONFIG_FILE")
            keywords=$(jq -r ".benches.${bench_name}.ai_keywords[]?" "$CONFIG_FILE" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
            
            bench_list+="- $bench_name: $description"
            if [ -n "$keywords" ]; then
                bench_list+="\n  Keywords: $keywords"
            fi
            bench_list+="\n"
        fi
    done < <(jq -r '.benches | keys[]' "$CONFIG_FILE" 2>/dev/null)
    
    echo -e "$bench_list"
}

# Get project description from user
get_project_description() {
    echo -e "${YELLOW}Project Analysis:${NC}"
    echo "Describe what kind of project you want to create."
    echo "Examples:"
    echo "  - 'A mobile app for iOS and Android with beautiful UI'"
    echo "  - 'A Python web application with machine learning features'"
    echo "  - 'A Java microservice with Spring Boot'"
    echo "  - 'A C++ game engine with high performance'"
    echo ""
    
    local description=""
    while [ -z "$description" ]; do
        read -p "Project description: " description
        if [ -z "$description" ]; then
            echo -e "${RED}Please provide a project description.${NC}"
        fi
    done
    
    echo "$description"
}

# Determine project type using AI
determine_project_type() {
    local project_description="$1"
    
    # Get available benches for AI analysis
    local available_benches
    available_benches=$(get_available_benches_for_ai)
    
    if [ -z "$available_benches" ]; then
        echo -e "${RED}No installed benches found for project creation.${NC}"
        return 1
    fi
    
    # Use AI to analyze the project
    local suggested_bench
    suggested_bench=$(analyze_project_with_ai "$project_description" "$available_benches")
    
    echo "$suggested_bench"
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
    echo "This AI-powered script analyzes your project description and automatically"
    echo "suggests the most appropriate development environment."
    echo ""
    echo "Arguments:"
    echo "  project-name      Optional: Name of the project to create"
    echo "  target-directory  Optional: Directory where project should be created"
    echo ""
    echo "Examples:"
    echo "  $0                          # Interactive mode with AI analysis"
    echo "  $0 myapp                    # AI analysis then create 'myapp'"
    echo "  $0 myapp ~/custom/path      # AI analysis with custom path"
    echo ""
    echo "AI Detection Methods:"
    echo "  1. Warp AI (if WARP_AI_API_KEY is set)"
    echo "  2. Claude API (if CLAUDE_API_KEY is set)"
    echo "  3. Keyword matching (fallback)"
    echo ""
    echo "This script will:"
    echo "  1. Ask you to describe your project"
    echo "  2. Analyze the description using AI"
    echo "  3. Suggest the best development environment"
    echo "  4. Create the project using the appropriate bench-specific script"
    echo "  5. Include specKit for spec-driven development"
    echo ""
    echo "Supported project types: Flutter/Dart, Python, Java, .NET/C#, C++"
    echo ""
}

# Main function
main() {
    echo -e "${BLUE}WorkBenches New Project Script (AI-Powered)${NC}"
    echo "=============================================="
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
    
    # Get project description for AI analysis
    local project_description
    project_description=$(get_project_description)
    
    echo ""
    echo -e "${CYAN}🧠 Analyzing your project requirements...${NC}"
    
    # Determine project type using AI
    local suggested_bench
    suggested_bench=$(determine_project_type "$project_description")
    
    local bench_name=""
    local script_name=""
    
    # Handle AI response
    if [ "$suggested_bench" = "UNCERTAIN" ] || [ -z "$suggested_bench" ]; then
        echo -e "${YELLOW}AI analysis was uncertain. Showing available options...${NC}"
        echo ""
        
        # Fallback to manual selection
        if ! show_available_project_types; then
            exit 1
        fi
        
        echo "Which type of project would you like to create?"
        local selected_type
        selected_type=$(prompt_project_type)
        
        bench_name="${selected_type%%:*}"
        script_name="${selected_type##*:}"
    else
        # AI suggested a bench, find the appropriate script
        bench_name="$suggested_bench"
        
        # Get the first available project script for this bench
        script_name=$(jq -r ".benches.${bench_name}.project_scripts[0].name" "$CONFIG_FILE" 2>/dev/null)
        
        if [ "$script_name" = "null" ] || [ -z "$script_name" ]; then
            echo -e "${RED}Error: No project creation script found for $bench_name${NC}"
            exit 1
        fi
        
        echo -e "${GREEN}✅ AI Recommendation: $script_name project (from $bench_name)${NC}"
        
        # Confirm with user
        local script_desc
        script_desc=$(jq -r ".benches.${bench_name}.project_scripts[] | select(.name==\"$script_name\") | .description" "$CONFIG_FILE")
        echo -e "   ${script_desc}"
        echo ""
        
        read -p "Proceed with this recommendation? [Y/n]: " confirm
        case $confirm in
            [Nn]* )
                echo ""
                echo -e "${YELLOW}Showing all available options...${NC}"
                
                if ! show_available_project_types; then
                    exit 1
                fi
                
                echo "Which type of project would you like to create?"
                local selected_type
                selected_type=$(prompt_project_type)
                
                bench_name="${selected_type%%:*}"
                script_name="${selected_type##*:}"
                ;;
        esac
    fi
    
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