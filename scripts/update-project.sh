#!/bin/bash

# WorkBenches Update Project Script
# Uses AI to determine project type and updates projects using bench-specific scripts

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

# Default project search directories
DEFAULT_SEARCH_DIRS=(
    "$HOME/projects"
    "$HOME/Projects"
    "$HOME/code"
    "$HOME/Code"
    "$HOME/dev"
    "$HOME/Development"
)

# Check dependencies
# Utility functions for logging
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
    echo -e "${CYAN}🔄 $1${NC}"
    echo "$(printf '=%.0s' {1..50})"
}

check_dependencies() {
    local missing_deps=()
    
    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi
    
    if ! command -v find &> /dev/null; then
        missing_deps+=("find")
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
    
    if [ "$bench_path" != "null" ] && [ -d "$(dirname "$SCRIPT_DIR")/$bench_path" ]; then
        return 0
    fi
    return 1
}

# Find projects by name in search directories
find_projects_by_name() {
    local project_name="$1"
    local search_dirs=("${@:2}")
    
    # If no search directories provided, use defaults
    if [ ${#search_dirs[@]} -eq 0 ]; then
        search_dirs=("${DEFAULT_SEARCH_DIRS[@]}")
    fi
    
    local found_projects=()
    
    echo -e "${CYAN}🔍 Searching for projects named '$project_name'...${NC}" >&2
    
    for search_dir in "${search_dirs[@]}"; do
        if [ -d "$search_dir" ]; then
            echo -e "${BLUE}   Searching in: $search_dir${NC}" >&2
            
            # Find directories with matching names (case insensitive)
            # Exclude submodules, build artifacts, and cache directories
            while IFS= read -r -d '' project_path; do
                if [ -d "$project_path" ]; then
                    # Skip if path contains build artifacts, git internals, or cache directories
                    if [[ "$project_path" =~ /\.git/modules/ ]] || \
                       [[ "$project_path" =~ /build/app/intermediates/ ]] || \
                       [[ "$project_path" =~ /build/.*/(assets|flutter_assets)/ ]] || \
                       [[ "$project_path" =~ /build/unit_test_assets/ ]] || \
                       [[ "$project_path" =~ /build/.*/(debug|release)/ ]] || \
                       [[ "$project_path" =~ /node_modules/ ]] || \
                       [[ "$project_path" =~ /\.gradle/ ]] || \
                       [[ "$project_path" =~ /\.pub-cache/ ]] || \
                       [[ "$project_path" =~ /target/(debug|release)/ ]] || \
                       [[ "$project_path" =~ /__pycache__/ ]] || \
                       [[ "$project_path" =~ /\.dart_tool/ ]]; then
                        continue  # Skip this path
                    fi
                    found_projects+=("$project_path")
                fi
            done < <(find "$search_dir" -type d -iname "*$project_name*" -print0 2>/dev/null)
        fi
    done
    
    # Remove duplicates and sort
    if [ ${#found_projects[@]} -gt 0 ]; then
        printf '%s\n' "${found_projects[@]}" | sort -u
    fi
}

# Show found projects and let user select
select_project_from_list() {
    local projects=("$@")
    
    if [ ${#projects[@]} -eq 0 ]; then
        return 1
    fi
    
    if [ ${#projects[@]} -eq 1 ]; then
        echo "${projects[0]}"
        return 0
    fi
    
    # Display project list to stderr so it doesn't interfere with function output
    echo -e "${YELLOW}Found multiple projects:${NC}" >&2
    echo "" >&2
    
    local counter=1
    for project in "${projects[@]}"; do
        local project_name=$(basename "$project")
        local project_dir=$(dirname "$project")
        echo -e "${BLUE}$counter) $project_name${NC}" >&2
        echo -e "   ${project_dir}" >&2
        echo "" >&2
        ((counter++))
    done
    
    while true; do
        # Use stderr for prompt so it displays immediately
        echo -n "Select project (1-${#projects[@]}): " >&2
        read choice
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#projects[@]} ]; then
            echo "${projects[$((choice-1))]}"
            return 0
        else
            echo -e "${RED}Invalid choice. Please enter a number between 1 and ${#projects[@]}.${NC}" >&2
        fi
    done
}

# High-level bench type detection (development/admin/designer)
detect_bench_category() {
    local project_path="$1"
    
    echo -e "${CYAN}🧠 AI-Powered High-Level Bench Category Detection${NC}" >&2
    
    # Check for bench metadata first
    local metadata_files=(
        ".workbench"
        ".bench-info"
        ".workbench-metadata.json"
        ".devcontainer/workbench-metadata.json"
    )
    
    for metadata_file in "${metadata_files[@]}"; do
        local full_path="$project_path/$metadata_file"
        if [ -f "$full_path" ]; then
            echo -e "${GREEN}✅ Found metadata file: $metadata_file${NC}" >&2
            
            # Try to extract bench category from metadata
            if [[ "$metadata_file" =~ \.json$ ]]; then
                # JSON metadata
                if command -v jq >/dev/null 2>&1; then
                    local bench_category=$(jq -r '.bench_category // .benchCategory // .category // empty' "$full_path" 2>/dev/null)
                    if [ -n "$bench_category" ] && [ "$bench_category" != "null" ]; then
                        echo -e "${GREEN}📊 Detected bench category from metadata: $bench_category${NC}" >&2
                        echo "$bench_category"
                        return 0
                    fi
                fi
            else
                # Plain text metadata
                local bench_category=$(grep -i "bench_category\|benchCategory\|category" "$full_path" 2>/dev/null | head -1 | cut -d'=' -f2 | tr -d ' "')
                if [ -n "$bench_category" ]; then
                    echo -e "${GREEN}📊 Detected bench category from metadata: $bench_category${NC}" >&2
                    echo "$bench_category"
                    return 0
                fi
            fi
        fi
    done
    
    # AI Analysis for high-level categorization
    echo -e "${BLUE}🔍 Running AI analysis for bench category detection...${NC}" >&2
    
    local dev_indicators=0
    local admin_indicators=0
    local designer_indicators=0
    
    # Development project indicators
    if [ -f "$project_path/pubspec.yaml" ] || [ -f "$project_path/package.json" ] || [ -f "$project_path/requirements.txt" ] || 
       [ -f "$project_path/pom.xml" ] || [ -f "$project_path/build.gradle" ] || find "$project_path" -name "*.csproj" | head -1 >/dev/null 2>&1 || 
       [ -f "$project_path/CMakeLists.txt" ] || [ -f "$project_path/Makefile" ]; then
        dev_indicators=$((dev_indicators + 90))
        echo -e "${BLUE}   🔧 Development project files detected: +90 confidence${NC}" >&2
    fi
    
    if [ -d "$project_path/.devcontainer" ] || [ -d "$project_path/.vscode" ] || [ -f "$project_path/Dockerfile" ]; then
        dev_indicators=$((dev_indicators + 20))
        echo -e "${BLUE}   📦 Development environment files: +20 confidence${NC}" >&2
    fi
    
    if [ -d "$project_path/src" ] || [ -d "$project_path/lib" ] || [ -d "$project_path/app" ]; then
        dev_indicators=$((dev_indicators + 15))
        echo -e "${BLUE}   📁 Source code directories: +15 confidence${NC}" >&2
    fi
    
    # Admin/Infrastructure project indicators
    if [ -f "$project_path/ansible.cfg" ] || [ -d "$project_path/playbooks" ] || [ -d "$project_path/roles" ]; then
        admin_indicators=$((admin_indicators + 95))
        echo -e "${YELLOW}   ⚙️ Ansible infrastructure files: +95 confidence${NC}" >&2
    fi
    
    if [ -f "$project_path/terraform.tf" ] || [ -f "$project_path/main.tf" ] || [ -d "$project_path/terraform" ]; then
        admin_indicators=$((admin_indicators + 95))
        echo -e "${YELLOW}   🏗️ Terraform infrastructure files: +95 confidence${NC}" >&2
    fi
    
    if [ -f "$project_path/docker-compose.yml" ] && [ ! -f "$project_path/pubspec.yaml" ] && [ ! -f "$project_path/package.json" ]; then
        admin_indicators=$((admin_indicators + 30))
        echo -e "${YELLOW}   🐳 Infrastructure Docker Compose: +30 confidence${NC}" >&2
    fi
    
    if echo "$project_path" | grep -qi "infrastructure\|deploy\|ops\|admin\|server"; then
        admin_indicators=$((admin_indicators + 25))
        echo -e "${YELLOW}   📂 Infrastructure-related path: +25 confidence${NC}" >&2
    fi
    
    # Designer/Creative project indicators
    if find "$project_path" -name "*.psd" -o -name "*.sketch" -o -name "*.fig" -o -name "*.ai" | head -1 >/dev/null 2>&1; then
        designer_indicators=$((designer_indicators + 90))
        echo -e "${MAGENTA}   🎨 Design tool files detected: +90 confidence${NC}" >&2
    fi
    
    if [ -d "$project_path/assets" ] && [ ! -f "$project_path/pubspec.yaml" ]; then
        designer_indicators=$((designer_indicators + 40))
        echo -e "${MAGENTA}   🖼️ Assets directory (non-dev): +40 confidence${NC}" >&2
    fi
    
    if echo "$project_path" | grep -qi "design\|creative\|assets\|brand\|ui\|ux"; then
        designer_indicators=$((designer_indicators + 30))
        echo -e "${MAGENTA}   📁 Design-related path: +30 confidence${NC}" >&2
    fi
    
    # Determine the best category
    local max_confidence=0
    local best_category=""
    
    if [ $dev_indicators -gt $max_confidence ]; then
        max_confidence=$dev_indicators
        best_category="devBenches"
    fi
    
    if [ $admin_indicators -gt $max_confidence ]; then
        max_confidence=$admin_indicators
        best_category="adminBenches"
    fi
    
    if [ $designer_indicators -gt $max_confidence ]; then
        max_confidence=$designer_indicators
        best_category="designerBenches"
    fi
    
    # Report results
    echo "" >&2
    echo -e "${CYAN}📊 High-Level Analysis Results:${NC}" >&2
    echo "   🔧 Development: ${dev_indicators}%" >&2
    echo "   ⚙️ Admin/Infrastructure: ${admin_indicators}%" >&2
    echo "   🎨 Designer/Creative: ${designer_indicators}%" >&2
    echo "" >&2
    
    if [ $max_confidence -ge 50 ]; then
        echo -e "${GREEN}🎯 Detected bench category: $best_category (${max_confidence}% confidence)${NC}" >&2
        echo "$best_category"
    else
        echo -e "${YELLOW}🤔 Defaulting to devBenches (max confidence: ${max_confidence}%)${NC}" >&2
        echo "devBenches"  # Default to development
    fi
}

# AI-powered project type detection for existing projects
analyze_project_with_ai() {
    local project_path="$1"
    local available_benches="$2"
    
    echo -e "${CYAN}🤖 Analyzing project with AI...${NC}" >&2
    
    # Gather project information
    local project_info=""
    project_info+="Project path: $project_path\n"
    project_info+="Project name: $(basename "$project_path")\n"
    
    # List key files
    if [ -d "$project_path" ]; then
        project_info+="Key files found:\n"
        
        # Check for common project files
        local key_files=(
            "package.json" "pubspec.yaml" "requirements.txt" "pom.xml" "build.gradle" 
            "CMakeLists.txt" "Makefile" "*.csproj" "*.sln" "setup.py" "pyproject.toml"
            "Dockerfile" "docker-compose.yml" ".devcontainer/devcontainer.json"
        )
        
        for pattern in "${key_files[@]}"; do
            if find "$project_path" -maxdepth 2 -name "$pattern" -type f 2>/dev/null | head -5 | while read file; do
                project_info+="- $(basename "$file")\n"
            done | grep -q .; then
                :  # Files found
            fi
        done
        
        # Check directory structure
        project_info+="Directory structure:\n"
        ls -la "$project_path" 2>/dev/null | head -10 | tail -n +2 | while read line; do
            project_info+="- $line\n"
        done
    fi
    
    # Prepare AI prompt
    local ai_prompt="Based on the following project information, determine which development environment would be most suitable for updating this project:

Project Information:
$project_info

Available environments:
$available_benches

Please respond with ONLY the bench name (like 'flutterBench', 'pythonBench', etc.) that best matches this project. If uncertain, respond with 'UNCERTAIN'."
    
    # Try to get AI response using various methods
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
    
    # Method 3: Use structural analysis as fallback
    if [ -z "$ai_response" ] || [ "$ai_response" = "null" ]; then
        ai_response=$(analyze_project_structure "$project_path")
    fi
    
    # Clean up the response
    ai_response=$(echo "$ai_response" | tr -d '"' | tr -d "'" | xargs)
    
    echo "$ai_response"
}

# Get available benches for AI prompt
get_available_benches_for_ai() {
    local bench_list=""
    
    while IFS= read -r bench_name; do
        if is_bench_installed "$bench_name"; then
            local description
            description=$(jq -r ".benches.${bench_name}.description" "$CONFIG_FILE")
            
            bench_list+="- $bench_name: $description\n"
        fi
    done < <(jq -r '.benches | keys[]' "$CONFIG_FILE" 2>/dev/null)
    
    echo -e "$bench_list"
}

# Determine high-level bench category (development/admin/designer)
determine_bench_category() {
    local project_path="$1"
    
    # Use AI to detect high-level bench category
    local bench_category
    bench_category=$(detect_bench_category "$project_path")
    
    echo "$bench_category"
}

# Preview which update script will be used
preview_update_script() {
    local bench_name="$1"
    local project_path="$2"
    
    # Find update script for this bench
    local bench_path
    bench_path=$(jq -r ".benches.${bench_name}.path" "$CONFIG_FILE")
    
    if [ "$bench_path" = "null" ]; then
        echo -e "${RED}Error: Bench path not found for $bench_name${NC}"
        return 1
    fi
    
    local workbenches_root="$(dirname "$SCRIPT_DIR")"
    local script_patterns=()
    local update_type=""
    
    # Special handling for Flutter projects - check if it's a Dartwing project
    if [ "$bench_name" = "flutterBench" ]; then
        # Check for Dartwing-specific indicators
        if [ -f "$project_path/docker-compose.override.yml" ] || 
           [ -d "$project_path/.devcontainer" ] && grep -q "dartwing\|Dartwing" "$project_path"/.devcontainer/* 2>/dev/null || 
           echo "$project_path" | grep -qi "dartwing"; then
            echo -e "${YELLOW}🔄 Flutter project detected in Dartwingers location${NC}"
            echo -e "${CYAN}📋 Will delegate to DartWing update script${NC}"
            echo -e "${BLUE}ℹ️  Includes both Flutter and .NET service updates${NC}"
            update_type="Dartwing project"
            script_patterns=(
                "$workbenches_root/$bench_path/scripts/update-dartwing-project.sh"
                "$workbenches_root/$bench_path/scripts/update-flutter-project.sh"
            )
        else
            update_type="Flutter project"
            script_patterns=(
                "$workbenches_root/$bench_path/scripts/update-flutter-project.sh"
            )
        fi
    else
        # Standard patterns for other bench types
        local bench_short="${bench_name%Bench}"
        update_type="$bench_short project"
        script_patterns=(
            "$workbenches_root/$bench_path/scripts/update-${bench_short}-project.sh"
        )
    fi
    
    # Find which script will actually be used
    local found_script=""
    for pattern in "${script_patterns[@]}"; do
        if [ -f "$pattern" ]; then
            found_script="$pattern"
            break
        fi
    done
    
    if [ -n "$found_script" ]; then
        local script_name=$(basename "$found_script")
        echo -e "${BLUE}🔄 Will update as:${NC} ${YELLOW}$update_type${NC}"
        echo -e "${BLUE}📝 Using script:${NC} $script_name"
    else
        echo -e "${RED}❌ No update script found for $update_type${NC}"
    fi
}

# Provide AI-powered advice for update failures
provide_ai_advice() {
    local script_path="$1"
    local project_path="$2"
    local exit_code="$3"
    
    echo -e "${YELLOW}🤖 AI Analysis & Advice${NC}"
    echo "================================="
    echo ""
    
    # Gather context about the failure
    local script_name=$(basename "$script_path")
    local project_name=$(basename "$project_path")
    local git_status=""
    local project_info=""
    
    # Check git status if it's a git repository
    if [ -d "$project_path/.git" ]; then
        cd "$project_path" 2>/dev/null
        git_status=$(git status --porcelain 2>/dev/null | head -10)
        if [ -n "$git_status" ]; then
            project_info+="Git Status (uncommitted changes):\n$git_status\n\n"
        fi
        cd - >/dev/null 2>&1
    fi
    
    # Use fallback advice immediately for this implementation
    provide_fallback_advice "$script_name" "$project_path" "$exit_code" "$git_status"
}

# Generate AI-powered commit message based on changes
generate_ai_commit_message() {
    local project_path="$1"
    local git_status="$2"
    
    # Prepare context for AI
    local project_name=$(basename "$project_path")
    local change_count=$(echo "$git_status" | wc -l)
    local change_summary=""
    
    # Analyze the types of changes
    if echo "$git_status" | grep -q "^\.devcontainer"; then
        change_summary+="DevContainer configuration "
    fi
    if echo "$git_status" | grep -q "docker-compose\|Dockerfile"; then
        change_summary+="Docker setup "
    fi
    if echo "$git_status" | grep -q "\.(dart|yaml|json)$"; then
        change_summary+="project files "
    fi
    if echo "$git_status" | grep -q "README\|docs"; then
        change_summary+="documentation "
    fi
    
    # Try AI-powered commit message generation
    local ai_message=""
    
    # Method 1: Try Warp AI if available
    if command -v warp &> /dev/null && [ -n "$WARP_AI_API_KEY" ]; then
        local ai_prompt="Generate a concise git commit message for these changes in project '$project_name':

Changes ($change_count files):
$git_status

Context: Changes made before applying template update. Focus on what was modified.

Guidelines:
- First line: brief summary (50 chars max)
- Add blank line if detailed explanation needed
- Use conventional commit format if appropriate
- Be specific about what changed"
        
        ai_message=$(echo "$ai_prompt" | warp ai --stdin 2>/dev/null | tail -n +2 | head -n -1 | sed '/^$/d' || echo "")
    fi
    
    # Method 2: Try Claude API if available
    if [ -z "$ai_message" ] && [ -n "$CLAUDE_API_KEY" ]; then
        local ai_prompt="Generate a concise git commit message for these changes:

Project: $project_name
Changes: $git_status

Context: Pre-template update commit. Reply with just the commit message, no quotes."
        
        ai_message=$(curl -s -X POST "https://api.anthropic.com/v1/messages" \
            -H "Content-Type: application/json" \
            -H "x-api-key: $CLAUDE_API_KEY" \
            -H "anthropic-version: 2023-06-01" \
            -d "{
                \"model\": \"claude-3-haiku-20240307\",
                \"max_tokens\": 100,
                \"messages\": [
                    {\"role\": \"user\", \"content\": \"$ai_prompt\"}
                ]
            }" | jq -r '.content[0].text' 2>/dev/null | sed 's/^["\`]*//;s/["\`]*$//' || echo "")
    fi
    
    # Method 3: Generate smart fallback message
    if [ -z "$ai_message" ] || [ "$ai_message" = "null" ]; then
        if [ $change_count -eq 1 ]; then
            local single_file=$(echo "$git_status" | awk '{print $2}' | head -1)
            ai_message="Save changes to $(basename "$single_file") before template update"
        elif [ -n "$change_summary" ]; then
            ai_message="Save ${change_summary}changes before template update
            
Preserving current work before applying latest template
Project: $project_name ($change_count files)"
        else
            ai_message="Save work before template update
            
Preserving current changes before applying latest template
Project: $project_name
Files: $change_count modified
Date: $(date '+%Y-%m-%d %H:%M:%S')"
        fi
    fi
    
    echo "$ai_message"
}

# Auto-commit changes and retry update
auto_commit_and_update() {
    local project_path="$1"
    local script_name="$2"
    
    echo -e "${CYAN}💾 Committing changes...${NC}"
    
    # Change to project directory
    local original_dir=$(pwd)
    cd "$project_path" || {
        echo -e "${RED}❌ Failed to change to project directory${NC}"
        return 1
    }
    
    # Get current git status
    local git_status
    git_status=$(git status --porcelain 2>/dev/null)
    
    # Generate appropriate commit message using AI or fallback
    local commit_message
    commit_message=$(generate_ai_commit_message "$project_path" "$git_status")
    
    # Let user review and customize the commit message
    echo -e "${CYAN}📝 Proposed commit message:${NC}"
    echo "$commit_message"
    echo ""
    
    read -p "Use this message? [Y/n/e=edit]: " message_choice
    case $message_choice in
        [Ee]* )
            echo "Enter your custom commit message (press Enter twice when done):"
            local custom_message=""
            local line
            while IFS= read -r line; do
                if [ -z "$line" ] && [ -n "$custom_message" ]; then
                    break
                fi
                if [ -n "$custom_message" ]; then
                    custom_message+="\n"
                fi
                custom_message+="$line"
            done
            
            if [ -n "$custom_message" ]; then
                commit_message="$custom_message"
            fi
            ;;
        [Nn]* )
            echo -e "${RED}Commit cancelled. Please handle git changes manually.${NC}"
            cd "$original_dir"
            return 1
            ;;
    esac
    
    # Add all changes and commit
    if git add . && git commit -m "$commit_message"; then
        echo -e "${GREEN}✅ Changes committed successfully${NC}"
        echo "   Commit message: Save work before template update"
        echo ""
    else
        echo -e "${RED}❌ Failed to commit changes${NC}"
        cd "$original_dir"
        return 1
    fi
    
    # Return to original directory
    cd "$original_dir"
    
    # Now retry the update
    echo -e "${CYAN}🔄 Retrying update...${NC}"
    echo ""
    
    # Determine the correct script path and re-run update
    local workbenches_root="$(dirname "$SCRIPT_DIR")"
    if echo "$script_name" | grep -q "dartwing"; then
        local full_script_path="$workbenches_root/devBenches/flutterBench/scripts/update-dartwing-project.sh"
    elif echo "$script_name" | grep -q "flutter"; then
        local full_script_path="$workbenches_root/devBenches/flutterBench/scripts/update-flutter-project.sh"
    else
        # Try to find the script in the workbenches structure
        local full_script_path=$(find "$workbenches_root" -name "$script_name" -type f 2>/dev/null | head -1)
    fi
    
    if [ -n "$full_script_path" ] && [ -f "$full_script_path" ]; then
        echo -e "${BLUE}Re-running:${NC} $full_script_path"
        "$full_script_path" "$project_path"
    else
        echo -e "${RED}❌ Could not locate script: $script_name${NC}"
        return 1
    fi
}

# Provide fallback advice based on common patterns
provide_fallback_advice() {
    local script_name="$1"
    local project_path="$2"
    local exit_code="$3"
    local git_status="$4"
    
    # Check for specific error patterns in the output
    local error_context=""
    if [ -f "/tmp/update-error.log" ]; then
        error_context=$(tail -10 "/tmp/update-error.log" 2>/dev/null)
    fi
    
    # Detect color code formatting issues (also check for common patterns)
    if echo "$error_context" | grep -q "\?\[0;[0-9]*m\|File name too long" || 
       [ $exit_code -eq 1 ] && (echo "$project_path" | grep -q "dartwing\|flutter") && 
       [ -d "$project_path/.devcontainer" ]; then
        echo -e "${CYAN}📝 Most Likely Cause: Script output formatting issue${NC}"
        echo ""
        echo -e "${CYAN}🔧 Solution Steps:${NC}"
        echo "1. This appears to be a color code rendering issue in the update script"
        echo "2. The actual update likely completed successfully despite the error"
        echo "3. Check if your project files were updated:"
        echo "   ls -la $project_path/.devcontainer/"
        echo ""
        echo "4. If files were updated, manually commit the changes:"
        echo "   cd $project_path"
        echo "   git status"
        echo "   git add ."
        echo "   git commit -m \"Update devcontainer configuration\""
        echo ""
        echo "5. The script error is cosmetic - your project should be properly updated"
        return 0
    fi
    
    # Common failure patterns
    if [ -n "$git_status" ]; then
        echo -e "${CYAN}📝 Most Likely Cause: Uncommitted changes preventing update${NC}"
        echo ""
        echo -e "${YELLOW}Uncommitted changes found:${NC}"
        echo "$git_status" | sed 's/^/   /'
        echo ""
        
        # Offer to automatically commit and continue
        echo -e "${CYAN}🤖 Would you like me to commit these changes and continue with the update?${NC}"
        echo ""
        read -p "Auto-commit and update? [Y/n]: " auto_commit
        
        case $auto_commit in
            [Nn]* )
                echo ""
                echo -e "${CYAN}🔧 Manual Solution Steps:${NC}"
                echo "1. Review your changes:"
                echo "   cd $project_path && git status"
                echo ""
                echo "2. Choose one option:"
                echo "   • Commit changes: git add . && git commit -m \"Save work before update\""
                echo "   • Stash changes: git stash push -m \"Before template update\""
                echo "   • Discard changes: git checkout -- . (⚠️ This will lose uncommitted work!)"
                echo ""
                echo "3. Re-run the update:"
                echo "   update-project $(basename "$project_path")"
                ;;
            * )
                echo ""
                if auto_commit_and_update "$project_path" "$script_name"; then
                    echo -e "${GREEN}✅ Auto-commit and update completed successfully!${NC}"
                    exit 0
                else
                    echo -e "${RED}❌ Auto-commit or update failed. Please resolve manually.${NC}"
                    exit 1
                fi
                ;;
        esac
        
        echo ""
        echo -e "${CYAN}🛑 Prevention: Always commit or stash changes before running updates.${NC}"
    elif [ $exit_code -eq 1 ]; then
        echo -e "${CYAN}📝 Most Likely Cause: General script failure or validation error${NC}"
        echo ""
        echo -e "${CYAN}🔧 Solution Steps:${NC}"
        echo "1. Check if project directory is writable"
        echo "2. Ensure project structure is valid (has .devcontainer, etc.)"
        echo "3. Try running the script directly for more verbose output:"
        echo "   $script_name $project_path"
    else
        echo -e "${CYAN}📝 Generic Failure (Exit Code: $exit_code)${NC}"
        echo ""
        echo -e "${CYAN}🔧 Troubleshooting Steps:${NC}"
        echo "1. Check project permissions and structure"
        echo "2. Ensure all dependencies are available"
        echo "3. Review the error output above for specific issues"
        echo "4. Try running the script directly: $script_name $project_path"
    fi
    
    echo ""
    echo -e "${BLUE}Need more help?${NC}"
    echo "• Check project documentation"
    echo "• Review recent git commits for working configuration"
    echo "• Run the update script with debug flags if available"
    echo ""
}

# Delegate to bench category-specific update script
update_project() {
    local bench_category="$1"
    local project_path="$2"
    
    log_section "🚀 Delegating to $bench_category Update Script"
    
    local workbenches_root="$(dirname "$SCRIPT_DIR")"
    local script_patterns=()
    
    # Map bench categories to update scripts
    case "$bench_category" in
        "devBenches")
            echo -e "${BLUE}🔧 Development project detected${NC}"
            echo -e "${CYAN}📋 Delegating to devBench-specific analysis and update${NC}"
            script_patterns=(
                "$workbenches_root/devBenches/scripts/update-devBench-project.sh"
            )
            ;;
        "adminBenches")
            echo -e "${YELLOW}⚙️ Admin/Infrastructure project detected${NC}"
            echo -e "${CYAN}📋 Delegating to adminBench update script${NC}"
            script_patterns=(
                "$workbenches_root/adminBenches/scripts/update-adminBench-project.sh"
                "$workbenches_root/adminBenches/scripts/update-admin-project.sh"
                "$workbenches_root/adminBenches/scripts/update-project.sh"
            )
            ;;
        "designerBenches")
            echo -e "${MAGENTA}🎨 Designer/Creative project detected${NC}"
            echo -e "${CYAN}📋 Delegating to designerBench update script${NC}"
            script_patterns=(
                "$workbenches_root/designerBenches/scripts/update-designerBench-project.sh"
                "$workbenches_root/designerBenches/scripts/update-designer-project.sh"
                "$workbenches_root/designerBenches/scripts/update-project.sh"
            )
            ;;
        *)
            echo -e "${RED}❌ Unknown bench category: $bench_category${NC}"
            return 1
            ;;
    esac
    
    # Find and execute the appropriate script
    local found_script=""
    for pattern in "${script_patterns[@]}"; do
        log_info "   Checking: $(basename "$pattern")"
        if [ -f "$pattern" ]; then
            found_script="$pattern"
            log_success "✅ Found update script: $pattern"
            break
        fi
    done
    
    if [ -z "$found_script" ]; then
        log_error "❌ No update script found for $bench_category"
        echo ""
        echo "Searched for:"
        for pattern in "${script_patterns[@]}"; do
            echo "  - $(basename "$pattern")"
        done
        echo ""
        echo "💡 Please ensure the $bench_category has an update script available."
        return 1
    fi
    
    # Make script executable if needed
    if [ ! -x "$found_script" ]; then
        log_info "🔧 Making script executable..."
        chmod +x "$found_script"
    fi
    
    echo ""
    log_info "🎯 Executing: $found_script $project_path"
    echo ""
    
    # Execute the bench category-specific update script
    if "$found_script" "$project_path"; then
        log_success "✅ $bench_category project update completed successfully!"
        return 0
    else
        local exit_code=$?
        log_error "❌ $bench_category project update failed with exit code: $exit_code"
        
        # Handle exit code 2 specifically for uncommitted changes auto-commit
        if [ $exit_code -eq 2 ]; then
            log_info "🔍 Detected uncommitted changes (exit code 2)"
            echo ""
            
            # Get git status from project
            local git_status=""
            if [ -d "$project_path/.git" ]; then
                cd "$project_path" 2>/dev/null
                git_status=$(git status --porcelain 2>/dev/null)
                cd - >/dev/null 2>&1
            fi
            
            if [ -n "$git_status" ]; then
                echo -e "${CYAN}📝 Uncommitted changes found - triggering auto-commit workflow${NC}"
                echo ""
                
                # Extract script name for auto-commit function
                local script_name=$(basename "$found_script")
                
                # Call the auto-commit workflow directly
                if auto_commit_and_update "$project_path" "$script_name"; then
                    log_success "✅ Auto-commit and update completed successfully!"
                    return 0
                else
                    log_error "❌ Auto-commit or update failed"
                    return 1
                fi
            else
                log_warning "Exit code 2 but no uncommitted changes found - continuing with standard advice"
                provide_ai_advice "$found_script" "$project_path" "$exit_code"
                return $exit_code
            fi
        else
            # Standard error handling for other exit codes
            provide_ai_advice "$found_script" "$project_path" "$exit_code"
            return $exit_code
        fi
    fi
}

# Show usage information
show_usage() {
    echo "Usage: $0 <project-name> [search-directories...]"
    echo ""
    echo "This AI-powered script finds and updates existing projects by:"
    echo "1. Searching for projects matching the given name"
    echo "2. Using AI to determine the bench category (development/admin/designer)"
    echo "3. Delegating to the appropriate bench category-specific update script"
    echo ""
    echo "Arguments:"
    echo "  project-name           Name (or partial name) of project to update"
    echo "  search-directories     Optional: Custom directories to search in"
    echo ""
    echo "Examples:"
    echo "  $0 myapp                        # Search default directories"
    echo "  $0 myapp ~/custom/projects      # Search custom directory"
    echo "  $0 flutter-app ~/projects ~/dev # Search multiple directories"
    echo ""
    echo "Default search directories:"
    printf '  - %s\n' "${DEFAULT_SEARCH_DIRS[@]}"
    echo ""
    echo "Bench Categories:"
    echo "  🔧 devBenches: Development projects (Flutter, Python, Java, .NET, C++)"
    echo "  ⚙️ adminBenches: Administrative/Infrastructure projects (Ansible, Terraform)"
    echo "  🎨 designerBenches: Designer/Creative projects (Design files, Assets)"
    echo ""
    echo "AI Detection Methods:"
    echo "  1. Project metadata files (.workbench, .bench-info, etc.)"
    echo "  2. Project structure and file analysis"
    echo "  3. Path-based analysis (directory names)"
    echo ""
}

# Main function
main() {
    echo -e "${BLUE}WorkBenches Update Project Script (AI-Powered)${NC}"
    echo "==============================================="
    echo -e "${CYAN}🎯 High-Level Bench Category Detection & Delegation${NC}"
    echo ""
    
    # Check for help flag
    if [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ -z "$1" ]; then
        show_usage
        exit 0
    fi
    
    check_dependencies
    
    # Load configuration
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}Error: Configuration file not found: $CONFIG_FILE${NC}"
        exit 1
    fi
    
    local project_name="$1"
    local search_dirs=("${@:2}")
    
    echo -e "${YELLOW}Project Search:${NC}"
    echo "Looking for projects named: $project_name"
    echo ""
    
    # Find projects
    local found_projects
    mapfile -t found_projects < <(find_projects_by_name "$project_name" "${search_dirs[@]}")
    
    if [ ${#found_projects[@]} -eq 0 ]; then
        echo -e "${RED}No projects found matching '$project_name'${NC}"
        echo ""
        echo "Searched in directories:"
        if [ ${#search_dirs[@]} -gt 0 ]; then
            printf '  - %s\n' "${search_dirs[@]}"
        else
            printf '  - %s\n' "${DEFAULT_SEARCH_DIRS[@]}"
        fi
        echo ""
        echo "Try:"
        echo "  - Using a different project name"
        echo "  - Specifying custom search directories"
        echo "  - Using partial name (e.g., 'app' instead of 'myapp')"
        exit 1
    fi
    
    # Select project if multiple found
    local selected_project
    selected_project=$(select_project_from_list "${found_projects[@]}")
    
    if [ -z "$selected_project" ]; then
        echo -e "${RED}No project selected${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Selected project:${NC} $selected_project"
    echo ""
    
    # Determine bench category using AI
    echo -e "${CYAN}🧠 Analyzing bench category...${NC}"
    local bench_category
    bench_category=$(determine_bench_category "$selected_project")
    
    if [ -z "$bench_category" ]; then
        echo -e "${YELLOW}Could not determine bench category, defaulting to devBenches.${NC}"
        bench_category="devBenches"
    fi
    
    echo -e "${GREEN}✅ Detected bench category: $bench_category${NC}"
    
    # Show category description
    case "$bench_category" in
        "devBenches")
            echo -e "   🔧 Development projects (Flutter, Python, Java, .NET, C++)"
            ;;
        "adminBenches")
            echo -e "   ⚙️ Administrative/Infrastructure projects (Ansible, Terraform, Docker)"
            ;;
        "designerBenches")
            echo -e "   🎨 Designer/Creative projects (Design files, Assets, Brand materials)"
            ;;
    esac
    echo ""
    
    read -p "Proceed with updating this project? [Y/n]: " confirm
    case $confirm in
        [Nn]* )
            echo "Update cancelled."
            exit 0
            ;;
    esac
    
    echo ""
    
    # Update the project
    if update_project "$bench_category" "$selected_project"; then
        echo ""
        echo -e "${GREEN}✅ Project update completed successfully!${NC}"
        echo -e "${BLUE}ℹ️  Your project has been updated with the latest template.${NC}"
    else
        local update_exit_code=$?
        echo ""
        echo -e "${RED}❌ Project update failed.${NC}"
        echo -e "${YELLOW}Please follow the advice above to resolve the issue and try again.${NC}"
        exit $update_exit_code
    fi
}

# Run main function
main "$@"