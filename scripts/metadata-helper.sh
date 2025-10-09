#!/bin/bash

# ====================================
# WorkBenches Project Metadata Helper Functions
# ====================================
# Provides reusable functions for reading, writing, and managing project metadata
# Supports multi-bench projects and parent/child project relationships
#
# Usage: Source this file in other scripts: source metadata-helper.sh

# Metadata file locations (in order of preference)
METADATA_FILES=(
    ".workbench-metadata.json"
    ".devcontainer/workbench-metadata.json"
    ".workbench"
    ".bench-info"
)

# ====================================
# Utility Functions
# ====================================

log_metadata() {
    echo -e "\033[0;36m📊 $1\033[0m" >&2
}

log_metadata_success() {
    echo -e "\033[0;32m✅ $1\033[0m" >&2
}

log_metadata_warning() {
    echo -e "\033[1;33m⚠️  $1\033[0m" >&2
}

log_metadata_error() {
    echo -e "\033[0;31m❌ $1\033[0m" >&2
}

# ====================================
# Metadata Schema Functions
# ====================================

# Generate a complete metadata JSON object
generate_project_metadata() {
    local project_path="$1"
    local bench_type="$2"
    local bench_category="$3"
    local parent_project="${4:-}"
    local sibling_projects="${5:-}"
    
    local project_name=$(basename "$project_path")
    local created_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local created_by_user=$(whoami)
    local workbench_version="1.0.0"  # TODO: Get from config
    
    # Generate JSON
    cat <<EOF
{
  "workbench_metadata": {
    "version": "$workbench_version",
    "created_date": "$created_date",
    "created_by_user": "$created_by_user",
    "last_updated": "$created_date"
  },
  "project_info": {
    "name": "$project_name",
    "path": "$project_path",
    "bench_category": "$bench_category",
    "bench_type": "$bench_type"
  },
  "project_relationships": {
    "parent_project": $([ -n "$parent_project" ] && echo "\"$parent_project\"" || echo "null"),
    "sibling_projects": $([ -n "$sibling_projects" ] && echo "$sibling_projects" || echo "[]"),
    "is_multi_bench_project": $([ -n "$sibling_projects" ] && [ "$sibling_projects" != "[]" ] && echo "true" || echo "false")
  },
  "creation_context": {
    "working_directory": "$(pwd)",
    "environment": {
      "os": "$(uname -s)",
      "shell": "$SHELL",
      "user": "$USER",
      "home": "$HOME"
    }
  }
}
EOF
}

# ====================================
# Metadata File Management
# ====================================

# Write metadata to project
write_project_metadata() {
    local project_path="$1"
    local bench_type="$2" 
    local bench_category="$3"
    local parent_project="${4:-}"
    local sibling_projects="${5:-}"
    
    log_metadata "Writing metadata for project: $(basename "$project_path")"
    
    # Generate metadata
    local metadata_json=$(generate_project_metadata "$project_path" "$bench_type" "$bench_category" "$parent_project" "$sibling_projects")
    
    # Write to primary location (.workbench-metadata.json in project root)
    local metadata_file="$project_path/.workbench-metadata.json"
    echo "$metadata_json" > "$metadata_file"
    log_metadata_success "Created metadata file: .workbench-metadata.json"
    
    # Also create .devcontainer version if .devcontainer exists
    if [ -d "$project_path/.devcontainer" ]; then
        echo "$metadata_json" > "$project_path/.devcontainer/workbench-metadata.json"
        log_metadata_success "Created backup metadata: .devcontainer/workbench-metadata.json"
    fi
    
    # Create simple .workbench file for compatibility
    cat > "$project_path/.workbench" <<EOF
# WorkBench Project Metadata
bench_category=$bench_category
bench_type=$bench_type
created_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
created_by_user=$(whoami)
$([ -n "$parent_project" ] && echo "parent_project=$parent_project")
EOF
    log_metadata_success "Created simple metadata: .workbench"
    
    return 0
}

# Read metadata from project
read_project_metadata() {
    local project_path="$1"
    
    # Try each metadata file location
    for metadata_file in "${METADATA_FILES[@]}"; do
        local full_path="$project_path/$metadata_file"
        if [ -f "$full_path" ]; then
            if [[ "$metadata_file" =~ \.json$ ]]; then
                # JSON metadata
                if command -v jq >/dev/null 2>&1; then
                    cat "$full_path"
                    return 0
                else
                    log_metadata_warning "jq not available, cannot read JSON metadata"
                fi
            else
                # Plain text metadata - convert to JSON-like output
                echo "{"
                while IFS='=' read -r key value; do
                    if [[ ! "$key" =~ ^# ]] && [ -n "$key" ]; then
                        echo "  \"$key\": \"$value\","
                    fi
                done < "$full_path"
                echo "}"
                return 0
            fi
        fi
    done
    
    log_metadata_warning "No metadata found in: $project_path"
    return 1
}

# Update existing metadata
update_project_metadata() {
    local project_path="$1"
    local update_field="$2"
    local new_value="$3"
    
    local metadata_file="$project_path/.workbench-metadata.json"
    
    if [ -f "$metadata_file" ] && command -v jq >/dev/null 2>&1; then
        # Update JSON metadata
        local updated_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        local temp_file=$(mktemp)
        
        jq --arg field "$update_field" --arg value "$new_value" --arg date "$updated_date" \
           '.[$field] = $value | .workbench_metadata.last_updated = $date' \
           "$metadata_file" > "$temp_file" && mv "$temp_file" "$metadata_file"
        
        log_metadata_success "Updated metadata: $update_field = $new_value"
        return 0
    else
        log_metadata_error "Cannot update metadata - file not found or jq not available"
        return 1
    fi
}

# ====================================
# Multi-Bench Project Detection
# ====================================

# Detect if project is part of a multi-bench setup
detect_multi_bench_project() {
    local project_path="$1"
    
    log_metadata "Analyzing project structure for multi-bench setup..."
    
    local project_dir=$(dirname "$project_path")
    local parent_dir=$(dirname "$project_dir")
    local project_name=$(basename "$project_path")
    
    # Look for sibling projects (other bench types in same parent)
    local sibling_projects=()
    local potential_parent=""
    
    # Check if parent directory contains multiple sub-projects
    local subproject_count=0
    local has_dev_indicators=false
    
    if [ -d "$project_dir" ]; then
        for potential_sibling in "$project_dir"/*; do
            if [ -d "$potential_sibling" ] && [ "$potential_sibling" != "$project_path" ]; then
                # Check if this looks like a development project
                if [ -f "$potential_sibling/pubspec.yaml" ] || \
                   [ -f "$potential_sibling/package.json" ] || \
                   [ -f "$potential_sibling/requirements.txt" ] || \
                   [ -f "$potential_sibling/pom.xml" ] || \
                   find "$potential_sibling" -name "*.csproj" -o -name "*.sln" | head -1 >/dev/null 2>&1; then
                    
                    sibling_projects+=($(basename "$potential_sibling"))
                    subproject_count=$((subproject_count + 1))
                    has_dev_indicators=true
                fi
            fi
        done
    fi
    
    # Determine if this is a multi-bench project
    if [ $subproject_count -ge 1 ] && [ "$has_dev_indicators" = true ]; then
        potential_parent=$(basename "$project_dir")
        log_metadata_success "Multi-bench project detected!"
        log_metadata "  Parent: $potential_parent"
        log_metadata "  Siblings: ${sibling_projects[*]}"
        
        # Return results
        echo "MULTI_BENCH"
        echo "PARENT:$potential_parent"
        echo "SIBLINGS:$(printf '%s,' "${sibling_projects[@]}" | sed 's/,$//')"
        return 0
    else
        log_metadata "Single-bench project detected"
        echo "SINGLE_BENCH"
        return 0
    fi
}

# Get sibling projects with their bench types
analyze_sibling_projects() {
    local project_path="$1"
    local project_dir=$(dirname "$project_path")
    
    local siblings_json="["
    local first=true
    
    for potential_sibling in "$project_dir"/*; do
        if [ -d "$potential_sibling" ] && [ "$potential_sibling" != "$project_path" ]; then
            local sibling_name=$(basename "$potential_sibling")
            local sibling_bench_type="unknown"
            
            # Detect bench type of sibling
            if [ -f "$potential_sibling/pubspec.yaml" ]; then
                sibling_bench_type="flutterBench"
            elif [ -f "$potential_sibling/requirements.txt" ] || [ -f "$potential_sibling/setup.py" ]; then
                sibling_bench_type="pythonBench"
            elif [ -f "$potential_sibling/pom.xml" ] || [ -f "$potential_sibling/build.gradle" ]; then
                sibling_bench_type="javaBench"
            elif find "$potential_sibling" -name "*.csproj" -o -name "*.sln" | head -1 >/dev/null 2>&1; then
                sibling_bench_type="dotNetBench"
            elif [ -f "$potential_sibling/CMakeLists.txt" ] || [ -f "$potential_sibling/Makefile" ]; then
                sibling_bench_type="cppBench"
            fi
            
            # Add to JSON array
            if [ "$first" = true ]; then
                first=false
            else
                siblings_json+=","
            fi
            
            siblings_json+="{\"name\":\"$sibling_name\",\"bench_type\":\"$sibling_bench_type\"}"
        fi
    done
    
    siblings_json+="]"
    echo "$siblings_json"
}

# ====================================
# Validation Functions
# ====================================

# Validate metadata exists and is well-formed
validate_project_metadata() {
    local project_path="$1"
    
    log_metadata "Validating metadata for: $(basename "$project_path")"
    
    local metadata_found=false
    local validation_errors=()
    
    # Check for any metadata files
    for metadata_file in "${METADATA_FILES[@]}"; do
        local full_path="$project_path/$metadata_file"
        if [ -f "$full_path" ]; then
            metadata_found=true
            log_metadata_success "Found metadata file: $metadata_file"
            
            # Validate JSON structure if it's a JSON file
            if [[ "$metadata_file" =~ \.json$ ]] && command -v jq >/dev/null 2>&1; then
                if ! jq empty "$full_path" 2>/dev/null; then
                    validation_errors+=("Invalid JSON in $metadata_file")
                fi
            fi
        fi
    done
    
    if [ "$metadata_found" = false ]; then
        validation_errors+=("No metadata files found")
    fi
    
    # Report validation results
    if [ ${#validation_errors[@]} -eq 0 ]; then
        log_metadata_success "Metadata validation passed"
        return 0
    else
        log_metadata_error "Metadata validation failed:"
        for error in "${validation_errors[@]}"; do
            log_metadata_error "  - $error"
        done
        return 1
    fi
}

# ====================================
# Legacy Support Functions  
# ====================================

# Convert old metadata formats to new format
upgrade_legacy_metadata() {
    local project_path="$1"
    
    # Check for legacy .devbench file
    if [ -f "$project_path/.devbench" ]; then
        log_metadata "Found legacy .devbench file, upgrading..."
        
        # Read legacy format and convert
        local bench_type=$(grep -i "type" "$project_path/.devbench" 2>/dev/null | cut -d'=' -f2 | tr -d ' "' || echo "unknown")
        local bench_category="devBenches"  # Assume dev for legacy
        
        # Create new metadata
        write_project_metadata "$project_path" "$bench_type" "$bench_category"
        
        # Keep legacy file for compatibility
        log_metadata_success "Legacy metadata upgraded, keeping .devbench for compatibility"
        return 0
    fi
    
    return 1
}

# ====================================
# Main Interface Functions
# ====================================

# Initialize metadata for a new project
initialize_project_metadata() {
    local project_path="$1"
    local bench_type="$2"
    local bench_category="${3:-devBenches}"
    
    log_metadata "Initializing metadata for project: $(basename "$project_path")"
    
    # Analyze multi-bench setup
    local multi_bench_info
    multi_bench_info=$(detect_multi_bench_project "$project_path")
    
    local parent_project=""
    local sibling_projects="[]"
    
    if echo "$multi_bench_info" | grep -q "MULTI_BENCH"; then
        parent_project=$(echo "$multi_bench_info" | grep "PARENT:" | cut -d':' -f2)
        local siblings=$(echo "$multi_bench_info" | grep "SIBLINGS:" | cut -d':' -f2)
        
        if [ -n "$siblings" ]; then
            sibling_projects=$(analyze_sibling_projects "$project_path")
        fi
    fi
    
    # Write metadata
    write_project_metadata "$project_path" "$bench_type" "$bench_category" "$parent_project" "$sibling_projects"
    
    # Update sibling projects to reference this new project
    if [ "$sibling_projects" != "[]" ]; then
        update_sibling_metadata "$project_path" "$parent_project"
    fi
    
    log_metadata_success "Project metadata initialized successfully"
    return 0
}

# Update all sibling projects to reference the new project
update_sibling_metadata() {
    local new_project_path="$1"
    local parent_project="$2"
    local project_dir=$(dirname "$new_project_path")
    local new_project_name=$(basename "$new_project_path")
    
    for sibling_dir in "$project_dir"/*; do
        if [ -d "$sibling_dir" ] && [ "$sibling_dir" != "$new_project_path" ]; then
            local metadata_file="$sibling_dir/.workbench-metadata.json"
            if [ -f "$metadata_file" ] && command -v jq >/dev/null 2>&1; then
                log_metadata "Updating sibling metadata: $(basename "$sibling_dir")"
                
                # Add new project to sibling list
                local temp_file=$(mktemp)
                local updated_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
                
                jq --arg new_name "$new_project_name" --arg date "$updated_date" \
                   '.project_relationships.sibling_projects += [{"name": $new_name, "bench_type": "unknown"}] | 
                    .project_relationships.is_multi_bench_project = true |
                    .workbench_metadata.last_updated = $date' \
                   "$metadata_file" > "$temp_file" && mv "$temp_file" "$metadata_file"
            fi
        fi
    done
}

# Show metadata summary for a project
show_project_metadata() {
    local project_path="$1"
    
    log_metadata "Project Metadata Summary: $(basename "$project_path")"
    echo ""
    
    if ! validate_project_metadata "$project_path"; then
        echo "No valid metadata found."
        return 1
    fi
    
    local metadata_file="$project_path/.workbench-metadata.json"
    if [ -f "$metadata_file" ] && command -v jq >/dev/null 2>&1; then
        echo "📊 Project Information:"
        jq -r '.project_info | to_entries[] | "  \(.key): \(.value)"' "$metadata_file" 2>/dev/null
        
        echo ""
        echo "🔗 Project Relationships:"
        jq -r '.project_relationships | to_entries[] | "  \(.key): \(.value)"' "$metadata_file" 2>/dev/null
        
        echo ""
        echo "⏰ Creation Info:"
        jq -r '.workbench_metadata | to_entries[] | "  \(.key): \(.value)"' "$metadata_file" 2>/dev/null
    else
        # Fallback to simple .workbench file
        cat "$project_path/.workbench" 2>/dev/null || echo "No metadata available"
    fi
    
    return 0
}

# ====================================
# Export functions for use in other scripts
# ====================================

# Make functions available when sourced
if [ "${BASH_SOURCE[0]}" != "${0}" ]; then
    log_metadata "Metadata helper functions loaded successfully"
fi