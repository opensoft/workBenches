#!/bin/bash

# ====================================
# Flutter Project Template Update Script
# ====================================
# Updates existing Flutter projects with the latest devcontainer template
# 
# Workflow:
# 1. Detect project type and current branch
# 2. Create new branch (devcontainer-config-latest)
# 3. Apply latest template files
# 4. Auto-merge obvious conflicts with AI assistance
# 5. Present suggestions for complex conflicts
# 6. Create pull request back to original branch
#
# Usage: ./update-flutter-project.sh [project-path]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/../templates/flutter-devcontainer-template"
WORKBENCHES_DIR="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Project path (default to current directory)
PROJECT_PATH="${1:-$(pwd)}"
PROJECT_NAME=$(basename "$PROJECT_PATH")
TEMPLATE_BRANCH="devcontainer-config-latest"
BACKUP_DIR=""

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
    echo -e "${CYAN}🔄 $1${NC}"
    echo "$(printf '=%.0s' {1..50})"
}

# ====================================
# Validation Functions
# ====================================

validate_project() {
    log_section "Validating Project"
    
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
    
    # Check if it's a git repository
    if [ ! -d ".git" ]; then
        log_error "Not a git repository"
        log_info "Initialize git first: git init && git add . && git commit -m 'Initial commit'"
        exit 1
    fi
    
    # Check for uncommitted changes
    if ! git diff-index --quiet HEAD -- 2>/dev/null; then
        log_warning "Uncommitted changes detected. Offering auto-commit option..."
        local git_status=$(git status --porcelain)
        echo "$git_status"
        echo ""
        
        # Offer auto-commit
        echo -e "${CYAN}🤖 Would you like to auto-commit these changes before continuing?${NC}"
        echo ""
        read -p "Auto-commit and continue? [Y/n]: " auto_commit_choice
        
        case $auto_commit_choice in
            [Nn]* )
                log_error "Please commit or stash your changes first, then re-run the update."
                echo ""
                echo "Options:"
                echo "  • Commit: git add . && git commit -m 'Save work before template update'"
                echo "  • Stash: git stash push -m 'Before template update'"
                exit 2
                ;;
            * )
                # Auto-commit the changes
                log_info "Auto-committing changes..."
                
                # Generate simple commit message
                local project_name="$PROJECT_NAME"
                local change_count=$(echo "$git_status" | wc -l)
                local commit_message="Save work before template update

Preserving current changes before applying latest devcontainer template
Project: $project_name
Files modified: $change_count
Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
                
                # Show proposed commit message
                echo -e "${CYAN}📝 Proposed commit message:${NC}"
                echo "$commit_message"
                echo ""
                
                read -p "Use this message? [Y/n/e=edit]: " message_choice
                case $message_choice in
                    [Ee]* )
                        echo "Enter your custom commit message (single line):"
                        read -r custom_message
                        if [ -n "$custom_message" ]; then
                            commit_message="$custom_message"
                        fi
                        ;;
                    [Nn]* )
                        log_error "Commit cancelled. Please handle changes manually."
                        exit 2
                        ;;
                esac
                
                # Commit the changes
                if git add . && git commit -m "$commit_message"; then
                    log_success "Changes committed successfully!"
                    echo ""
                else
                    log_error "Failed to commit changes. Please handle manually."
                    exit 1
                fi
                ;;
        esac
    fi
    
    log_success "Project validation passed"
    log_info "Project: $PROJECT_NAME"
    log_info "Path: $PROJECT_PATH"
}

validate_template() {
    log_section "Validating Template"
    
    if [ ! -d "$TEMPLATE_DIR" ]; then
        log_error "Template directory not found: $TEMPLATE_DIR"
        exit 1
    fi
    
    # Check for essential template files
    local essential_files=(
        ".devcontainer/devcontainer.json"
        ".devcontainer/docker-compose.yml"
        ".devcontainer/.env.example"
        ".devcontainer/Dockerfile"
    )
    
    for file in "${essential_files[@]}"; do
        if [ ! -f "$TEMPLATE_DIR/$file" ]; then
            log_error "Template missing essential file: $file"
            exit 1
        fi
    done
    
    log_success "Template validation passed"
    log_info "Template: $TEMPLATE_DIR"
}

# ====================================
# AI-Enhanced Project Type Detection
# ====================================
# Provides fuzzy matching and confidence scoring for project type detection
# Replaces simple grep-based detection with intelligent pattern recognition

detect_project_type() {
    # Redirect log output to stderr to prevent capture in variable assignment
    log_section "🤖 AI-Enhanced Project Type Detection" >&2
    
    local project_type="flutter"
    local confidence=0
    local max_confidence=0
    local best_match=""
    local detection_reasons=()
    
    # ====================================
    # Dartwing Pattern Recognition
    # ====================================
    
    # High-confidence Dartwing patterns (90%+ confidence)
    local dartwing_patterns=(
        # Exact matches (95% confidence)
        "^dartwing$:95:exact match"
        "^appDartwing$:95:exact app prefix match"
        "^DartWing$:95:exact capitalized match"
        "^DartWingApp$:95:exact capitalized app match"
        
        # App variations (90-95% confidence) 
        "^dartwingapp$:92:dartwing + app"
        "^dartwingerapp$:90:dartwingers + app variant"
        "^appdartwing$:92:app + dartwing"
        "^appDartWing$:92:app + capitalized dartwing"
        
        # Case variations (85-90% confidence)
        "^dartWing$:88:camelCase variant"
        "^dartWingApp$:88:camelCase app variant"  
        "^DARTWING$:85:uppercase variant"
        "^DARTWINGAPP$:85:uppercase app variant"
        
        # Partial matches with high confidence (80-85% confidence)
        "dartwing.*app:82:contains dartwing + app"
        "app.*dartwing:82:contains app + dartwing"
        ".*dartwingers.*:80:contains dartwingers"
    )
    
    # Medium-confidence Dartwing patterns (70-85% confidence)
    local dartwing_medium_patterns=(
        # Common misspellings/variations
        "dartwng:75:missing 'i' variant"
        "dartwin:78:missing 'g' variant" 
        "dartwg:72:missing 'in' variant"
        "dtwing:70:missing 'ar' variant"
        
        # Partial word matches
        ".*dart.*wing.*:75:contains dart + wing"
        ".*wing.*dart.*:72:contains wing + dart"
        
        # Related project indicators
        ".*dart.*mobile.*:70:dart mobile project"
        ".*mobile.*dart.*:70:mobile dart project"
    )
    
    # ====================================
    # Project Name Analysis
    # ====================================
    
    log_info "Analyzing project name: '$PROJECT_NAME'" >&2
    
    # Normalize project name for comparison
    local normalized_name=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]')
    
    # Check high-confidence patterns
    for pattern_entry in "${dartwing_patterns[@]}"; do
        IFS=':' read -r pattern conf_score reason <<< "$pattern_entry"
        
        if [[ $normalized_name =~ $pattern ]]; then
            if [ "$conf_score" -gt "$max_confidence" ]; then
                max_confidence=$conf_score
                project_type="dartwing"
                best_match="$pattern"
                detection_reasons+=("Name match: $reason (${conf_score}% confidence)")
                log_info "🎯 High-confidence match: $reason (${conf_score}%)" >&2
            fi
        fi
    done
    
    # Check medium-confidence patterns only if no high-confidence match
    if [ "$max_confidence" -lt 80 ]; then
        for pattern_entry in "${dartwing_medium_patterns[@]}"; do
            IFS=':' read -r pattern conf_score reason <<< "$pattern_entry"
            
            if [[ $normalized_name =~ $pattern ]]; then
                if [ "$conf_score" -gt "$max_confidence" ]; then
                    max_confidence=$conf_score
                    project_type="dartwing"
                    best_match="$pattern"
                    detection_reasons+=("Name match: $reason (${conf_score}% confidence)")
                    log_info "🔍 Medium-confidence match: $reason (${conf_score}%)" >&2
                fi
            fi
        done
    fi
    
    # ====================================
    # File Content Analysis
    # ====================================
    
    local file_confidence=0
    
    # Check devcontainer.json for Dartwing indicators
    if [ -f ".devcontainer/devcontainer.json" ]; then
        if grep -qi "dartwing\|DartWing" .devcontainer/devcontainer.json 2>/dev/null; then
            file_confidence=85
            detection_reasons+=("DevContainer contains Dartwing references (85% confidence)")
            log_info "📄 DevContainer file indicates Dartwing project" >&2
        fi
    fi
    
    # Check docker-compose files
    for compose_file in "docker-compose.yml" ".devcontainer/docker-compose.yml" "docker-compose.override.yml"; do
        if [ -f "$compose_file" ] && grep -qi "dartwing" "$compose_file" 2>/dev/null; then
            file_confidence=80
            detection_reasons+=("Docker Compose contains Dartwing references (80% confidence)")
            log_info "🐳 Docker Compose indicates Dartwing project" >&2
            break
        fi
    done
    
    # Check pubspec.yaml for Dartwing-specific dependencies or naming
    if [ -f "pubspec.yaml" ]; then
        if grep -qi "dartwing\|dart.*wing" pubspec.yaml 2>/dev/null; then
            file_confidence=75
            detection_reasons+=("Pubspec contains Dartwing references (75% confidence)")
            log_info "📦 Pubspec indicates Dartwing project" >&2
        fi
    fi
    
    # Check README files
    for readme in "README.md" "readme.md" "README.txt"; do
        if [ -f "$readme" ] && grep -qi "dartwing\|dart.*wing" "$readme" 2>/dev/null; then
            file_confidence=70
            detection_reasons+=("README contains Dartwing references (70% confidence)")
            log_info "📖 README indicates Dartwing project" >&2
            break
        fi
    done
    
    # ====================================
    # Directory Structure Analysis  
    # ====================================
    
    local structure_confidence=0
    
    # Check parent directory names
    local parent_dir=$(basename "$(dirname "$PWD")")
    local grandparent_dir=$(basename "$(dirname "$(dirname "$PWD")")")
    
    if [[ $parent_dir =~ dartwing|dartwingers ]] || [[ $grandparent_dir =~ dartwing|dartwingers ]]; then
        structure_confidence=65
        detection_reasons+=("Located in Dartwing-related directory structure (65% confidence)")
        log_info "📁 Directory structure indicates Dartwing project" >&2
    fi
    
    # ====================================
    # Confidence Calculation & Decision
    # ====================================
    
    # Combine confidences (weighted average)
    local name_weight=50
    local file_weight=30  
    local structure_weight=20
    
    local combined_confidence=$(( 
        (max_confidence * name_weight + 
         file_confidence * file_weight + 
         structure_confidence * structure_weight) / 100 
    ))
    
    # Make final decision
    if [ "$combined_confidence" -ge 70 ]; then
        project_type="dartwing"
        confidence=$combined_confidence
    else
        # Check for LedgerLinc (existing logic)
        if echo "$PROJECT_NAME" | grep -qi "ledgerlinc"; then
            project_type="ledgerlinc"
            confidence=90
            detection_reasons+=("LedgerLinc project detected (90% confidence)")
        else
            project_type="flutter"
            confidence=60
            detection_reasons+=("Default Flutter project (60% confidence)")
        fi
    fi
    
    # ====================================
    # Report Results
    # ====================================
    
    log_success "🎯 Project Type: $project_type (${confidence}% confidence)" >&2
    
    if [ ${#detection_reasons[@]} -gt 0 ]; then
        log_info "🔍 Detection reasoning:" >&2
        for reason in "${detection_reasons[@]}"; do
            log_info "   • $reason" >&2
        done
    fi
    
    # Warn if confidence is low
    if [ "$confidence" -lt 70 ] && [ "$project_type" = "dartwing" ]; then
        log_warning "⚠️  Low confidence detection - please verify project type" >&2
    elif [ "$confidence" -ge 90 ]; then
        log_success "🎉 High confidence detection - very likely correct" >&2
    fi
    
    # Only output the project type to stdout for capture
    echo "$project_type"
}

# ====================================
# Git Workflow Functions
# ====================================

get_current_branch() {
    git branch --show-current 2>/dev/null || git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main"
}

create_update_branch() {
    # Redirect log output to stderr to prevent capture in variable assignment
    log_section "Creating Update Branch" >&2
    
    local current_branch
    current_branch=$(get_current_branch)
    
    log_info "Current branch: $current_branch" >&2
    
    # Delete existing update branch if it exists
    if git show-ref --verify --quiet "refs/heads/$TEMPLATE_BRANCH"; then
        log_warning "Branch $TEMPLATE_BRANCH already exists, deleting it" >&2
        git branch -D "$TEMPLATE_BRANCH" >&2
    fi
    
    # Create and checkout new branch
    git checkout -b "$TEMPLATE_BRANCH" >&2
    log_success "Created and switched to branch: $TEMPLATE_BRANCH" >&2
    
    # Only output the branch name to stdout for capture
    echo "$current_branch"
}

# ====================================
# File Management Functions
# ====================================

create_backup() {
    log_section "Creating Backup"
    
    BACKUP_DIR="/tmp/project-update-backup-$(date +%s)"
    mkdir -p "$BACKUP_DIR"
    
    # Backup key configuration files
    local files_to_backup=(
        ".devcontainer"
        ".vscode"
        "docker-compose.yml"
        "Dockerfile"
        ".env"
        ".gitignore"
    )
    
    for file in "${files_to_backup[@]}"; do
        if [ -e "$file" ]; then
            cp -r "$file" "$BACKUP_DIR/"
            log_info "Backed up: $file"
        fi
    done
    
    log_success "Backup created: $BACKUP_DIR"
}

apply_template_files() {
    log_section "Applying Template Files"
    
    # Files to copy from template
    local template_files=(
        ".devcontainer"
        ".vscode"
        ".gitignore"
        "scripts"
    )
    
    # Always copy .env.example
    cp "$TEMPLATE_DIR/.devcontainer/.env.example" .
    log_info "Copied: .env.example"
    
    # Create .env if it doesn't exist
    if [ ! -f ".env" ]; then
        cp ".env.example" ".env"
        log_info "Created: .env from .env.example"
    fi
    
    for file in "${template_files[@]}"; do
        if [ -e "$TEMPLATE_DIR/$file" ]; then
            cp -r "$TEMPLATE_DIR/$file" .
            log_info "Copied: $file"
        fi
    done
    
    # Copy README as reference
    if [ -f "$TEMPLATE_DIR/README.md" ]; then
        cp "$TEMPLATE_DIR/README.md" "DEVCONTAINER_README.md"
        log_info "Copied: README.md → DEVCONTAINER_README.md"
    fi
    
    log_success "Template files applied"
}

# ====================================
# Configuration Merging Functions
# ====================================

configure_env_file() {
    log_section "Configuring Environment File"
    
    if [ ! -f ".env" ]; then
        log_error ".env file not found after template application"
        return 1
    fi
    
    # Auto-detect configuration values
    local current_uid=$(id -u)
    local current_gid=$(id -g)
    local current_user=$(whoami)
    
    # Detect parent directory for compose project name
    local parent_dir=$(basename "$(dirname "$PROJECT_PATH")")
    local compose_project_name="flutter"
    if [[ "$parent_dir" == "dartwingers" ]]; then
        compose_project_name="dartwingers"
    fi
    
    # Apply automatic replacements
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' "s/PROJECT_NAME=myproject/PROJECT_NAME=$PROJECT_NAME/g" .env
        sed -i '' "s/USER_UID=1000/USER_UID=$current_uid/g" .env
        sed -i '' "s/USER_GID=1000/USER_GID=$current_gid/g" .env
        sed -i '' "s/COMPOSE_PROJECT_NAME=flutter/COMPOSE_PROJECT_NAME=$compose_project_name/g" .env
    else
        # Linux
        sed -i "s/PROJECT_NAME=myproject/PROJECT_NAME=$PROJECT_NAME/g" .env
        sed -i "s/USER_UID=1000/USER_UID=$current_uid/g" .env
        sed -i "s/USER_GID=1000/USER_GID=$current_gid/g" .env
        sed -i "s/COMPOSE_PROJECT_NAME=flutter/COMPOSE_PROJECT_NAME=$compose_project_name/g" .env
    fi
    
    # Remove .env.example from project root (it's now available in .devcontainer/.env.example)
    if [ -f ".env.example" ]; then
        rm .env.example
        log_info "Removed .env.example (available in .devcontainer/.env.example for reference)"
    fi
    
    log_success "Environment file configured"
    log_info "PROJECT_NAME: $PROJECT_NAME"
    log_info "USER_UID: $current_uid"
    log_info "USER_GID: $current_gid"
    log_info "COMPOSE_PROJECT_NAME: $compose_project_name"
}

# ====================================
# Legacy File Cleanup Functions
# ====================================

cleanup_legacy_devcontainer_files() {
    log_section "Cleaning Up Legacy DevContainer Files"
    
    # Files that should now be in .devcontainer/ directory
    # Only remove files from project root if they exist in .devcontainer/
    local devcontainer_files=(
        ".env.example"
        "Dockerfile"
        "docker-compose.yml"
        "docker-compose.override.yml"
    )
    
    local cleaned_files=()
    
    for file in "${devcontainer_files[@]}"; do
        # Check if file exists in both project root AND .devcontainer/
        if [ -f "$file" ] && [ -f ".devcontainer/$file" ]; then
            log_info "Removing legacy $file from project root (now in .devcontainer/)"
            rm "$file"
            cleaned_files+=("$file")
        fi
    done
    
    if [ ${#cleaned_files[@]} -gt 0 ]; then
        log_success "Cleaned up ${#cleaned_files[@]} legacy files: ${cleaned_files[*]}"
        log_info "These files are now properly organized in .devcontainer/ directory"
    else
        log_success "No legacy DevContainer files found in project root to clean up"
    fi
}

analyze_configuration_conflicts() {
    # Redirect log output to stderr to prevent capture in variable assignment
    log_section "Analyzing Configuration Conflicts" >&2
    
    local conflicts_found=false
    
    # Check for old vs new devcontainer structure
    if [ -f "$BACKUP_DIR/.devcontainer/devcontainer.json" ]; then
        echo "" >&2
        log_info "Analyzing devcontainer.json changes..." >&2
        
        # Check for old ADB service configuration
        if grep -q "adb-service" "$BACKUP_DIR/.devcontainer/devcontainer.json" 2>/dev/null; then
            log_warning "CONFLICT: Old configuration uses internal adb-service" >&2
            log_info "  → New configuration uses shared ADB infrastructure" >&2
            log_info "  → This will eliminate port 5037 conflicts" >&2
            conflicts_found=true
        fi
        
        # Check for old port configuration
        if grep -q "5037" "$BACKUP_DIR/.devcontainer/devcontainer.json" 2>/dev/null; then
            log_warning "CONFLICT: Old configuration binds port 5037" >&2
            log_info "  → New configuration connects to external ADB server" >&2
            log_info "  → This change resolves the port binding issue you mentioned" >&2
            conflicts_found=true
        fi
    fi
    
    # Check for docker-compose changes
    if [ -f "$BACKUP_DIR/docker-compose.yml" ]; then
        echo "" >&2
        log_info "Analyzing docker-compose.yml changes..." >&2
        
        # Check for old compose structure
        if grep -q "adb-service:" "$BACKUP_DIR/docker-compose.yml" 2>/dev/null; then
            log_warning "CONFLICT: Old compose file includes adb-service container" >&2
            log_info "  → New configuration uses external shared ADB service" >&2
            log_info "  → Container will connect to shared-adb-server:5037" >&2
            conflicts_found=true
        fi
        
        # Check for hardcoded values vs env variables
        if ! grep -q "\${.*}" "$BACKUP_DIR/docker-compose.yml" 2>/dev/null; then
            log_warning "CONFLICT: Old compose file uses hardcoded values" >&2
            log_info "  → New configuration uses .env variables for flexibility" >&2
            conflicts_found=true
        fi
    fi
    
    if [ "$conflicts_found" = false ]; then
        log_success "No major configuration conflicts detected" >&2
    fi
    
    # Only output the result to stdout for capture
    echo "$conflicts_found"
}

# ====================================
# AI-Powered Conflict Resolution
# ====================================

suggest_manual_review() {
    log_section "Manual Review Suggestions"
    
    echo ""
    log_info "🤖 AI Recommendations for your review:"
    echo ""
    
    echo "1. 🔍 REVIEW: Port 5037 Binding Resolution"
    echo "   • Old: Internal adb-service binds port 5037"
    echo "   • New: Connects to external shared-adb-server:5037"
    echo "   • ✅ This resolves your port conflict concern!"
    echo ""
    
    echo "2. 🔍 REVIEW: Environment Configuration"
    echo "   • Check .env file for project-specific settings"
    echo "   • Verify ADB_SERVER_HOST=shared-adb-server is correct"
    echo "   • Ensure NETWORK_NAME=dartnet matches your setup"
    echo ""
    
    echo "3. 🔍 REVIEW: Infrastructure Dependencies"
    echo "   • New config expects: ../../../infrastructure/mobile/android/adb/scripts/start-adb-if-needed.sh"
    echo "   • Verify this script exists or adjust path in devcontainer.json"
    echo ""
    
    echo "4. 🔍 REVIEW: Custom Modifications"
    if [ -f "$BACKUP_DIR/.devcontainer/devcontainer.json" ]; then
        echo "   • Compare custom VS Code extensions:"
        echo "     - Old: $(grep -A 20 '"extensions"' "$BACKUP_DIR/.devcontainer/devcontainer.json" 2>/dev/null | wc -l) lines"
        echo "     - New: $(grep -A 20 '"extensions"' .devcontainer/devcontainer.json 2>/dev/null | wc -l) lines"
    fi
    echo "   • Check for custom port mappings or volume mounts"
    echo ""
    
    echo "5. 🔍 REVIEW: Network Configuration"
    echo "   • New: Uses external 'dartnet' network"
    echo "   • Ensure shared infrastructure creates this network"
    echo ""
    
    log_warning "After review, test the configuration:"
    echo "   1. Commit changes: git add . && git commit -m 'Update devcontainer config'"
    echo "   2. Test container build: docker-compose build"
    echo "   3. Test VS Code integration: Open in container"
    echo ""
}

# ====================================
# Azure DevOps Helper Functions
# ====================================

get_azure_devops_org() {
    local remote_url="$1"
    local org=""
    
    # Extract organization from various Azure DevOps URL formats
    if [[ "$remote_url" =~ dev\.azure\.com/([^/]+) ]]; then
        org="${BASH_REMATCH[1]}"
    elif [[ "$remote_url" =~ @vs-ssh\.visualstudio\.com:v3/([^/]+)/ ]]; then
        org="${BASH_REMATCH[1]}"
    elif [[ "$remote_url" =~ ([^@]+)\.visualstudio\.com ]]; then
        org="${BASH_REMATCH[1]}"
    elif [[ "$remote_url" =~ ssh\.dev\.azure\.com.*/([^/]+) ]]; then
        org="${BASH_REMATCH[1]}"
    fi
    
    echo "$org"
}

get_azure_devops_project() {
    local remote_url="$1"
    local project=""
    
    # Extract project from various Azure DevOps URL formats
    if [[ "$remote_url" =~ dev\.azure\.com/[^/]+/([^/]+) ]]; then
        project="${BASH_REMATCH[1]}"
    elif [[ "$remote_url" =~ visualstudio\.com.*?/([^/]+)/[^/]+$ ]]; then
        project="${BASH_REMATCH[1]}"
    fi
    
    echo "$project"
}

# ====================================
# Pull Request Workflow
# ====================================

create_pull_request() {
    local original_branch="$1"
    log_section "Creating Pull Request"
    
    # Add and commit all changes
    git add .
    
    # Check if there are changes to commit
    if git diff-index --quiet --cached HEAD --; then
        log_warning "No changes to commit"
        return 1
    fi
    
    # Create comprehensive commit message
    local commit_msg="Update devcontainer configuration to latest template

Key Changes:
- Migrate from internal adb-service to shared ADB infrastructure
- Add .env-based configuration for flexibility
- Remove port 5037 binding conflicts
- Update to latest Flutter devcontainer template
- Add AI-powered conflict resolution recommendations

Template Version: $(date +%Y-%m-%d)
Original Branch: $original_branch
"
    
    git commit -m "$commit_msg"
    log_success "Changes committed to $TEMPLATE_BRANCH"
    
    # Check if we have a remote and can create PR
    if git remote get-url origin &>/dev/null; then
        local remote_url
        remote_url=$(git remote get-url origin)
        
        log_info "Remote repository detected: $remote_url"
        
        # Push the branch
        if git push -u origin "$TEMPLATE_BRANCH" 2>/dev/null; then
            log_success "Branch pushed to remote: $TEMPLATE_BRANCH"
            
            # Detect repository type from remote URL
            local repo_type="unknown"
            if [[ "$remote_url" =~ visualstudio\.com|dev\.azure\.com ]]; then
                repo_type="azure"
            elif [[ "$remote_url" =~ github\.com ]]; then
                repo_type="github"
            fi
            
            log_info "Detected repository type: $repo_type"
            
            # Create PR based on repository type
            local pr_created=false
            
            # Try Azure DevOps CLI for Azure DevOps repos
            if [ "$repo_type" = "azure" ] && command -v az &> /dev/null; then
                log_info "Attempting to create pull request with Azure DevOps CLI..."
                
                # Check if Azure DevOps extension is installed
                if az extension list --query "[?name=='azure-devops'].name" -o tsv 2>/dev/null | grep -q "azure-devops"; then
                    # Check if user is authenticated with Azure CLI
                    if ! az account show &>/dev/null; then
                        log_warning "Azure CLI not authenticated for API access"
                        log_info "Note: SSH keys work for Git operations, but PR creation requires API authentication"
                        log_info "Choose one:"
                        log_info "  1. Azure AD: az login"
                        # Extract organization from remote URL for better guidance
                        local ado_org
                        ado_org=$(get_azure_devops_org "$remote_url")
                        if [ -n "$ado_org" ]; then
                            log_info "  2. Personal Access Token: az devops login --organization https://dev.azure.com/$ado_org"
                        else
                            log_info "  2. Personal Access Token: az devops login --organization https://dev.azure.com/YourOrg"
                        fi
                        log_info "  3. Set AZURE_DEVOPS_EXT_PAT environment variable with your PAT"
                        echo ""
                        
                        # Check if PAT is set as environment variable
                        if [ -n "$AZURE_DEVOPS_EXT_PAT" ]; then
                            log_info "Found AZURE_DEVOPS_EXT_PAT environment variable, attempting PR creation..."
                        else
                            log_warning "Skipping automatic PR creation - authentication required"
                        fi
                    fi
                    
                    # Only attempt PR creation if authenticated OR PAT env var is set
                    if az account show &>/dev/null || [ -n "$AZURE_DEVOPS_EXT_PAT" ]; then
                        local pr_title="Update devcontainer configuration to latest template"
                    local pr_description="This PR updates the devcontainer configuration using the latest Flutter template.

## 🎯 Key Changes
- ✅ **Resolves port 5037 binding conflicts** - migrates from internal adb-service to shared infrastructure
- ✅ **Adds .env-based configuration** for project flexibility  
- ✅ **Updates to latest template structure** with modern Docker Compose patterns
- ✅ **Includes AI-powered conflict analysis** and recommendations

## 🔧 Configuration Changes
- **ADB**: Now connects to external \`shared-adb-server:5037\` instead of binding port 5037
- **Environment**: Uses \`.env\` file for customizable settings per project
- **Network**: Connects to shared \`dartnet\` network managed by infrastructure
- **Template**: Updated VS Code extensions and optimized development workflow

## ✅ Testing Checklist
- [ ] Container builds successfully: \`docker-compose build\`
- [ ] VS Code opens in container without errors
- [ ] ADB connection works: \`adb devices\` shows connected emulators
- [ ] Flutter commands work: \`flutter doctor\`, \`flutter pub get\`

## 📋 Infrastructure Requirements
- Shared ADB infrastructure must be running
- Network \`dartnet\` must exist (created by shared infrastructure)
- Script: \`../../../infrastructure/mobile/android/adb/scripts/start-adb-if-needed.sh\`

---
🤖 Generated by: update-flutter-project.sh script
📅 Template version: $(date +%Y-%m-%d)  
🔀 Source branch: $TEMPLATE_BRANCH → $original_branch"
                    
                    # Create PR using Azure DevOps CLI
                    if az repos pr create \
                        --source-branch "$TEMPLATE_BRANCH" \
                        --target-branch "$original_branch" \
                        --title "$pr_title" \
                        --description "$pr_description" \
                        --auto-complete true \
                        --delete-source-branch true \
                        2>/dev/null; then
                        
                        log_success "Azure DevOps pull request created successfully!"
                        
                        # Get PR details
                        local pr_info
                        pr_info=$(az repos pr list --source-branch "$TEMPLATE_BRANCH" --status active --output json 2>/dev/null | jq -r '.[0] | "ID: \(.pullRequestId) - \(.url)"' 2>/dev/null || echo "")
                        if [ -n "$pr_info" ] && [ "$pr_info" != "ID:  - " ]; then
                            log_info "PR Details: $pr_info"
                        fi
                        
                        pr_created=true
                        else
                            log_warning "Failed to create Azure DevOps PR automatically"
                        fi
                    fi
                else
                    log_warning "Azure DevOps CLI extension not installed"
                    log_info "Install with: az extension add --name azure-devops"
                fi
            fi
            
            # Try GitHub CLI for GitHub repos
            if [ "$repo_type" = "github" ] && [ "$pr_created" = false ] && command -v gh &> /dev/null; then
                log_info "Attempting to create pull request with GitHub CLI..."
                
                local pr_title="Update devcontainer configuration to latest template"
                local pr_body="This PR updates the devcontainer configuration using the latest Flutter template.

## Key Changes
- ✅ **Resolves port 5037 binding conflicts** - migrates from internal adb-service to shared infrastructure
- ✅ **Adds .env-based configuration** for project flexibility  
- ✅ **Updates to latest template structure** with modern Docker Compose patterns
- ✅ **Includes AI-powered conflict analysis** and recommendations

## Configuration Changes
- **ADB**: Now connects to external \`shared-adb-server:5037\` instead of binding port 5037
- **Environment**: Uses \`.env\` file for customizable settings per project
- **Network**: Connects to shared \`dartnet\` network managed by infrastructure
- **Template**: Updated VS Code extensions and optimized development workflow

## Testing Checklist
- [ ] Container builds successfully: \`docker-compose build\`
- [ ] VS Code opens in container without errors
- [ ] ADB connection works: \`adb devices\` shows connected emulators
- [ ] Flutter commands work: \`flutter doctor\`, \`flutter pub get\`

## Infrastructure Requirements
- Shared ADB infrastructure must be running
- Network \`dartnet\` must exist (created by shared infrastructure)
- Script: \`../../../infrastructure/mobile/android/adb/scripts/start-adb-if-needed.sh\`

Generated by: update-flutter-project.sh script
Template version: $(date +%Y-%m-%d)"

                if gh pr create --title "$pr_title" --body "$pr_body" --base "$original_branch" --head "$TEMPLATE_BRANCH" 2>/dev/null; then
                    log_success "GitHub pull request created successfully!"
                    
                    # Get PR URL
                    local pr_url
                    pr_url=$(gh pr view --json url -q .url 2>/dev/null || echo "")
                    if [ -n "$pr_url" ]; then
                        log_info "PR URL: $pr_url"
                    fi
                    
                    pr_created=true
                else
                    log_warning "Failed to create GitHub PR automatically"
                fi
            fi
            
            # Manual PR instructions if automatic creation failed
            if [ "$pr_created" = false ]; then
                log_warning "Automatic PR creation failed or not available"
                echo ""
                log_info "Manual PR creation instructions:"
                
                if [ "$repo_type" = "azure" ]; then
                    echo "  🔗 Azure DevOps:"
                    echo "     1. Go to your Azure DevOps repository"
                    echo "     2. Navigate to Repos > Pull Requests"
                    echo "     3. Click 'New Pull Request'"
                    echo "     4. Source: $TEMPLATE_BRANCH → Target: $original_branch"
                    echo "     5. Use the commit message as the PR description"
                elif [ "$repo_type" = "github" ]; then
                    echo "  🔗 GitHub:"
                    echo "     1. Go to your GitHub repository"
                    echo "     2. Click 'Compare & pull request' banner"
                    echo "     3. Or: Create pull request from $TEMPLATE_BRANCH to $original_branch"
                    echo "     4. Use the commit message as the PR description"
                else
                    echo "  🔗 Generic Git Platform:"
                    echo "     1. Go to your repository web interface"
                    echo "     2. Create a pull/merge request"
                    echo "     3. Source: $TEMPLATE_BRANCH → Target: $original_branch"
                    echo "     4. Use the commit message as the description"
                fi
                echo ""
            fi
            
        else
            log_warning "Failed to push branch to remote"
            log_info "You can push manually: git push -u origin $TEMPLATE_BRANCH"
        fi
    else
        log_info "No remote repository configured"
        log_info "Changes committed locally to branch: $TEMPLATE_BRANCH"
    fi
    
    return 0
}

# ====================================
# Auto-merge Functionality
# ====================================

auto_merge_back_to_source() {
    local original_branch="$1"
    
    log_section "Auto-merge Back to Source Branch"
    
    # Check if user wants auto-merge
    echo ""
    echo -e "${CYAN}🔄 Would you like to automatically merge the changes back to $original_branch?${NC}"
    echo "This will:"
    echo "   1. Switch to $original_branch"
    echo "   2. Merge $TEMPLATE_BRANCH"
    echo "   3. Push to remote"
    echo "   4. Clean up the temporary branch"
    echo ""
    
    read -p "Auto-merge and clean up? [Y/n]: " auto_merge_choice
    
    case $auto_merge_choice in
        [Nn]* )
            log_info "Skipping auto-merge. You can manually merge later:"
            echo "   git checkout $original_branch"
            echo "   git merge $TEMPLATE_BRANCH"
            echo "   git push origin $original_branch"
            echo "   git branch -d $TEMPLATE_BRANCH"
            return 0
            ;;
    esac
    
    echo ""
    log_info "🔄 Auto-merging changes back to $original_branch..."
    
    # Switch to original branch
    if ! git checkout "$original_branch"; then
        log_error "Failed to switch to $original_branch"
        return 1
    fi
    
    log_success "Switched to $original_branch"
    
    # Pull latest changes from remote to avoid conflicts
    if git remote get-url origin &>/dev/null; then
        log_info "Pulling latest changes from remote..."
        git pull origin "$original_branch" || {
            log_warning "Pull had conflicts or issues, but continuing with merge"
        }
    fi
    
    # Attempt to merge
    log_info "Merging $TEMPLATE_BRANCH into $original_branch..."
    
    if git merge "$TEMPLATE_BRANCH" --no-edit; then
        log_success "✅ Successfully merged $TEMPLATE_BRANCH into $original_branch"
        
        # Push to remote
        if git remote get-url origin &>/dev/null; then
            log_info "Pushing merged changes to remote..."
            if git push origin "$original_branch"; then
                log_success "✅ Pushed $original_branch to remote"
            else
                log_warning "Failed to push to remote, but merge completed locally"
            fi
        fi
        
        # Clean up temporary branch
        log_info "Cleaning up temporary branch..."
        
        # Delete local branch
        if git branch -d "$TEMPLATE_BRANCH" 2>/dev/null; then
            log_success "✅ Deleted local branch: $TEMPLATE_BRANCH"
        else
            log_warning "Could not delete local branch $TEMPLATE_BRANCH (may have additional commits)"
        fi
        
        # Delete remote branch if it exists
        if git remote get-url origin &>/dev/null; then
            if git push origin --delete "$TEMPLATE_BRANCH" 2>/dev/null; then
                log_success "✅ Deleted remote branch: $TEMPLATE_BRANCH"
            else
                log_info "Remote branch $TEMPLATE_BRANCH not found or already deleted"
            fi
        fi
        
        echo ""
        log_success "🎉 Auto-merge completed successfully!"
        log_info "📋 Summary:"
        echo "   ✅ Changes merged into: $original_branch"
        echo "   ✅ Remote updated: origin/$original_branch"
        echo "   ✅ Temporary branch cleaned up"
        echo ""
        
        return 0
        
    else
        log_error "❌ Merge failed - likely due to conflicts"
        echo ""
        log_info "🔧 Manual resolution required:"
        echo "   1. Resolve conflicts in the files Git indicates"
        echo "   2. Run: git add <resolved-files>"
        echo "   3. Run: git commit"
        echo "   4. Push: git push origin $original_branch"
        echo "   5. Clean up: git branch -d $TEMPLATE_BRANCH"
        echo ""
        
        return 1
    fi
}

# ====================================
# Dartwing Delegation Functions
# ====================================

# Check if we should delegate to update-dartwing-project.sh
check_dartwing_delegation() {
    local project_type="$1"
    local confidence="$2"
    
    # Redirect log output to stderr to prevent capture in variable assignment
    log_section "🔄 Checking Dartwing Project Delegation" >&2
    
    # Check if we're being called FROM update-dartwing-project.sh to avoid infinite recursion
    if [ -n "${FLUTTER_SCRIPT_CALLED_FROM_DARTWING:-}" ]; then
        log_info "🔄 Called from Dartwing script - continuing with Flutter-only template" >&2
        echo "CONTINUE_FLUTTER"
        return 0
    fi
    
    # Only delegate if we detected a Dartwing project with reasonable confidence
    if [ "$project_type" = "dartwing" ] && [ "$confidence" -ge 70 ]; then
        log_info "🎯 Dartwing project detected with ${confidence}% confidence" >&2
        log_info "📋 Delegating to specialized Dartwing update script..." >&2
        
        # Find the dartwing update script
        local dartwing_script="$SCRIPT_DIR/update-dartwing-project.sh"
        
        if [ -f "$dartwing_script" ]; then
            log_success "✅ Found Dartwing script: $dartwing_script" >&2
            echo "DELEGATE_TO_DARTWING"
            return 0
        else
            log_warning "⚠️  Dartwing script not found: $dartwing_script" >&2
            log_info "📝 Continuing with standard Flutter template" >&2
            echo "CONTINUE_FLUTTER"
            return 0
        fi
    else
        if [ "$project_type" = "dartwing" ]; then
            log_warning "⚠️  Low confidence Dartwing detection (${confidence}%)" >&2
            log_info "📝 Continuing with standard Flutter template" >&2
        fi
        echo "CONTINUE_FLUTTER"
        return 0
    fi
}

# Delegate to update-dartwing-project.sh
delegate_to_dartwing() {
    log_section "🚀 Delegating to Dartwing Update Script"
    
    local dartwing_script="$SCRIPT_DIR/update-dartwing-project.sh"
    
    echo ""
    log_info "🎯 This Flutter project has been identified as a Dartwing project"
    log_info "🔄 Delegating to specialized Dartwing update script for:"
    echo "   • Flutter devcontainer template"
    echo "   • .NET service container configuration"
    echo "   • Docker Compose override setup"
    echo "   • Dartwingers-specific customizations"
    echo ""
    
    log_info "📝 Executing: $dartwing_script $PROJECT_PATH"
    echo ""
    
    # Execute the Dartwing script
    if "$dartwing_script" "$PROJECT_PATH"; then
        log_success "✅ Dartwing project update completed successfully!"
        return 0
    else
        local exit_code=$?
        log_error "❌ Dartwing project update failed with exit code: $exit_code"
        return $exit_code
    fi
}

# ====================================
# Main Workflow
# ====================================

show_summary() {
    log_section "Update Summary"
    
    echo ""
    log_success "Project update completed successfully!"
    echo ""
    
    echo "📋 What was changed:"
    echo "   • DevContainer configuration updated to latest template"
    echo "   • Docker Compose migrated to .env-based configuration"
    echo "   • ADB service changed from internal to shared infrastructure"
    echo "   • Port 5037 binding conflict resolved"
    echo "   • VS Code settings and extensions updated"
    echo "   • Legacy DevContainer files cleaned up from project root"
    echo ""
    
    echo "📁 Files modified:"
    echo "   • .devcontainer/ - Updated with latest template (includes Docker files)"
    echo "   • .vscode/ - Updated tasks and settings"
    echo "   • .env - Project-specific settings"
    echo "   • .env.example - Template for other projects (from .devcontainer/.env.example)"
    echo ""
    
    echo "💾 Backup location: $BACKUP_DIR"
    echo ""
    
    log_info "Next steps:"
    echo "   1. Review the changes in branch: $TEMPLATE_BRANCH"
    echo "   2. Test the container: docker-compose build && code ."
    echo "   3. If satisfied, merge the pull request"
    echo "   4. Delete backup: rm -rf $BACKUP_DIR"
    echo ""
}

show_summary_merged() {
    local merged_branch="$1"
    log_section "Update & Merge Summary"
    
    echo ""
    log_success "Project update and merge completed successfully!"
    echo ""
    
    echo "🎯 What happened:"
    echo "   • DevContainer configuration updated to latest template"
    echo "   • Changes automatically merged into: $merged_branch"
    echo "   • Remote repository updated"
    echo "   • Temporary update branch cleaned up"
    echo "   • Docker Compose migrated to .env-based configuration"
    echo "   • ADB service changed from internal to shared infrastructure"
    echo "   • Port 5037 binding conflict resolved"
    echo "   • VS Code settings and extensions updated"
    echo "   • Legacy DevContainer files cleaned up from project root"
    echo ""
    
    echo "📁 Files modified in $merged_branch:"
    echo "   • .devcontainer/ - Updated with latest template (includes Docker files)"
    echo "   • .vscode/ - Updated tasks and settings"
    echo "   • .env - Project-specific settings"
    echo "   • .env.example - Template for other projects (from .devcontainer/.env.example)"
    echo ""
    
    echo "💾 Backup location: $BACKUP_DIR"
    echo ""
    
    log_info "✅ Ready for development:"
    echo "   1. Test the container: docker-compose build && code ."
    echo "   2. Verify your changes are working as expected"
    echo "   3. Delete backup when satisfied: rm -rf $BACKUP_DIR"
    echo ""
    
    log_success "🚀 Your $merged_branch branch is now up to date with the latest template!"
    echo ""
}

main() {
    echo -e "${BLUE}Flutter Project Template Update Script${NC}"
    echo "========================================"
    echo ""
    
    # Validate inputs
    validate_project
    validate_template
    
    # Detect project characteristics
    local project_type
    project_type=$(detect_project_type)
    
    # Extract confidence from the detection (parse from stderr if needed)
    # For now, use the confidence from the latest detection logic
    local confidence=60  # Default confidence
    
    # Enhanced project type detection with confidence extraction
    cd "$PROJECT_PATH"
    local normalized_name=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]')
    
    # Re-run confidence calculation for delegation decision
    local max_confidence=0
    local dartwing_patterns=(
        "^dartwing$:95" "^appDartwing$:95" "^DartWing$:95" "^DartWingApp$:95"
        "^dartwingapp$:92" "^appdartwing$:92" "^dartWingApp$:88" "^DARTWING$:85"
    )
    
    for pattern_entry in "${dartwing_patterns[@]}"; do
        IFS=':' read -r pattern conf_score <<< "$pattern_entry"
        if [[ $normalized_name =~ $pattern ]] && [ "$conf_score" -gt "$max_confidence" ]; then
            max_confidence=$conf_score
        fi
    done
    
    # File and structure confidence (simplified)
    local file_confidence=0
    if [ -f ".devcontainer/devcontainer.json" ] && grep -qi "dartwing" .devcontainer/devcontainer.json 2>/dev/null; then
        file_confidence=85
    fi
    
    local structure_confidence=0
    local parent_dir=$(basename "$(dirname "$PWD")")
    if [[ $parent_dir =~ dartwing|dartwingers ]]; then
        structure_confidence=65
    fi
    
    # Combined confidence calculation
    confidence=$(( (max_confidence * 50 + file_confidence * 30 + structure_confidence * 20) / 100 ))
    
    # Check if we should delegate to Dartwing script
    local delegation_decision
    delegation_decision=$(check_dartwing_delegation "$project_type" "$confidence")
    
    if [ "$delegation_decision" = "DELEGATE_TO_DARTWING" ]; then
        # Delegate to Dartwing script and exit
        delegate_to_dartwing
        exit $?
    fi
    
    # Continue with standard Flutter workflow
    log_info "📱 Proceeding with standard Flutter project update"
    
    # Git workflow
    local original_branch
    original_branch=$(create_update_branch)
    
    # Create backup
    create_backup
    
    # Apply template
    apply_template_files
    configure_env_file
    
    # Clean up legacy files
    cleanup_legacy_devcontainer_files
    
    # Analyze conflicts
    local has_conflicts
    has_conflicts=$(analyze_configuration_conflicts)
    
    # Provide AI recommendations
    suggest_manual_review
    
    # Create PR workflow
    if create_pull_request "$original_branch"; then
        log_success "Pull request workflow completed"
    else
        log_info "Manual merge required - no changes to commit"
    fi
    
    # Auto-merge workflow
    local auto_merge_success=false
    if auto_merge_back_to_source "$original_branch"; then
        auto_merge_success=true
    else
        # If auto-merge failed, switch back to original branch
        git checkout "$original_branch" 2>/dev/null
        log_info "Switched back to original branch: $original_branch"
    fi
    
    # Show summary (adjust based on auto-merge result)
    if [ "$auto_merge_success" = true ]; then
        show_summary_merged "$original_branch"
    else
        show_summary
    fi
    
    echo -e "${GREEN}🎉 Update process completed!${NC}"
    echo -e "${BLUE}Your project is now using the latest devcontainer template.${NC}"
    echo ""
}

# ====================================
# Script Execution
# ====================================

# Show usage if help requested
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    echo "Usage: $0 [project-path]"
    echo ""
    echo "Updates an existing Flutter project with the latest devcontainer template."
    echo ""
    echo "Arguments:"
    echo "  project-path    Path to Flutter project (default: current directory)"
    echo ""
    echo "This script will:"
    echo "  1. Create a new branch (devcontainer-config-latest)"
    echo "  2. Apply the latest template files"
    echo "  3. Configure environment variables automatically"
    echo "  4. Clean up legacy DevContainer files from project root"
    echo "  5. Analyze and resolve conflicts with AI assistance"
    echo "  6. Create a pull request for review"
    echo "  7. Optionally auto-merge changes back to source branch"
    echo ""
    echo "Requirements:"
    echo "  - Git repository with no uncommitted changes"
    echo "  - Flutter project (pubspec.yaml present)"
    echo "  - Latest devcontainer template available"
    echo ""
    exit 0
fi

# Run main function
main "$@"