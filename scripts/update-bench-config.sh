#!/bin/bash

# Auto-discover and update bench-config.json
# This script scans for benches and their project creation scripts

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../config/bench-config.json"
BACKUP_FILE="$CONFIG_FILE.backup"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check dependencies
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is required but not installed${NC}"
    exit 1
fi

echo -e "${BLUE}WorkBenches Configuration Auto-Discovery${NC}"
echo "========================================="
echo ""

# Backup existing config
if [ -f "$CONFIG_FILE" ]; then
    cp "$CONFIG_FILE" "$BACKUP_FILE"
    echo -e "${YELLOW}📋 Backed up existing config to: $BACKUP_FILE${NC}"
fi

# Auto-discover benches (directories with .git that aren't specKit or workBenches root)
discover_benches() {
    echo -e "${BLUE}🔍 Discovering benches...${NC}"
    
    local benches=()
    while IFS= read -r git_dir; do
        local bench_path="${git_dir%/.git}"
        local bench_name="$(basename "$bench_path")"
        
        # Skip specKit (infrastructure) and root workBenches
        if [ "$bench_name" != "specKit" ] && [ "$bench_path" != "." ]; then
            # Get remote URL if available
            local remote_url=""
            if cd "$bench_path" 2>/dev/null; then
                remote_url=$(git remote get-url origin 2>/dev/null || echo "")
                cd - > /dev/null
            fi
            
            benches+=("$bench_path|$remote_url")
            echo -e "  ✓ Found: ${GREEN}$bench_name${NC} at $bench_path"
        fi
    done < <(find . -name ".git" -type d 2>/dev/null)
    
    printf '%s\n' "${benches[@]}"
}

# Discover project scripts in a bench
discover_project_scripts() {
    local bench_path="$1"
    local scripts=()
    
    # Look for common project creation script patterns
    while IFS= read -r script_file; do
        if [ -f "$script_file" ]; then
            local script_name="$(basename "$script_file")"
            local script_type=""
            local description=""
            
            # Try to extract script type and description from filename and content
            case "$script_name" in
                *new-flutter-project*)
                    script_type="flutter"
                    description="Create a new Flutter project with DevContainer setup"
                    ;;
                *new-dartwing-project*)
                    script_type="dartwing"
                    description="Create a new DartWing project with specialized configuration"
                    ;;
                *new-python-project*)
                    script_type="python"
                    description="Create a new Python project"
                    ;;
                *new-java-project*)
                    script_type="java"
                    description="Create a new Java project"
                    ;;
                *new-dotnet-project*|*new-csharp-project*)
                    script_type="dotnet"
                    description="Create a new .NET project"
                    ;;
                *new-cpp-project*)
                    script_type="cpp"
                    description="Create a new C++ project"
                    ;;
                *)
                    # Generic detection
                    script_type=$(echo "$script_name" | sed -n 's/.*new-\([^-]*\)-.*/\1/p')
                    if [ -z "$script_type" ]; then
                        script_type=$(echo "$script_name" | sed -n 's/new-\([^.]*\).*/\1/p')
                    fi
                    description="Create a new $script_type project"
                    ;;
            esac
            
            if [ -n "$script_type" ]; then
                # Check if script handles spec-kit init by looking for specify init calls
                local includes_speckit="false"
                if grep -q "specify init\|init_speckit\|spec-kit" "$script_file" 2>/dev/null; then
                    includes_speckit="true"
                fi
                
                local relative_script="${script_file#$bench_path/}"
                scripts+=("$script_type|$relative_script|$description|$includes_speckit")
            fi
        fi
    done < <(find "$bench_path" -name "*new-*project*" -o -name "*create-*project*" 2>/dev/null | grep -E "\.(sh|ps1)$")
    
    printf '%s\n' "${scripts[@]}"
}

# Generate new configuration
generate_config() {
    local discovered_benches
    mapfile -t discovered_benches < <(discover_benches)
    
    echo -e "${BLUE}📝 Generating configuration...${NC}"
    
    # Start with infrastructure (preserved from existing config or default)
    local infrastructure='{
  "specKit": {
    "install": "uv tool install specify-cli --from git+https://github.com/github/spec-kit.git",
    "run": "uvx --from git+https://github.com/github/spec-kit.git specify init --here",
    "description": "GitHub Spec Kit - installed via uvx (always fetches latest)"
  }
}'
    
    # Try to preserve existing infrastructure config
    if [ -f "$CONFIG_FILE" ]; then
        local existing_infra
        existing_infra=$(jq -r '.infrastructure // {}' "$CONFIG_FILE" 2>/dev/null)
        if [ "$existing_infra" != "null" ] && [ "$existing_infra" != "{}" ]; then
            infrastructure="$existing_infra"
        fi
    fi
    
    # Build benches configuration
    local benches_config="{"
    local first_bench=true
    
    for bench_info in "${discovered_benches[@]}"; do
        local bench_path="${bench_info%%|*}"
        local remote_url="${bench_info##*|}"
        local bench_name="$(basename "$bench_path")"
        
        if [ "$first_bench" = true ]; then
            first_bench=false
        else
            benches_config+=","
        fi
        
        benches_config+="
    \"$bench_name\": {
      \"url\": \"$remote_url\",
      \"path\": \"$bench_path\",
      \"description\": \"$(get_bench_description "$bench_name")\""
        
        # Check for project scripts
        local project_scripts
        mapfile -t project_scripts < <(discover_project_scripts "$bench_path")
        
        if [ ${#project_scripts[@]} -gt 0 ]; then
            benches_config+=",
      \"project_scripts\": ["
            
            local first_script=true
            for script_info in "${project_scripts[@]}"; do
                IFS='|' read -r script_type script_path script_desc includes_speckit <<< "$script_info"
                
                if [ "$first_script" = true ]; then
                    first_script=false
                else
                    benches_config+=","
                fi
                
                benches_config+="
        {
          \"name\": \"$script_type\",
          \"script\": \"$script_path\",
          \"description\": \"$script_desc\",
          \"includes_speckit\": $includes_speckit
        }"
            done
            
            benches_config+="
      ]"
        fi
        
        benches_config+="
    }"
    done
    
    benches_config+="
  }"
    
    # Combine into final config
    local final_config="{
  \"infrastructure\": $infrastructure,
  \"benches\": $benches_config
}"
    
    echo "$final_config"
}

# Get description for a bench
get_bench_description() {
    local bench_name="$1"
    case "$bench_name" in
        adminBenches) echo "Administrative tools and utilities bench" ;;
        pythonBench) echo "Python development environment and tools" ;;
        javaBench) echo "Java development environment and tools" ;;
        dotNetBench) echo ".NET development environment and tools" ;;
        flutterBench) echo "Flutter/Dart development environment and tools" ;;
        cppBench) echo "C++ development environment and tools" ;;
        *) echo "Development tools and utilities" ;;
    esac
}

# Main execution
main() {
    echo -e "${YELLOW}This will auto-discover benches and update bench-config.json${NC}"
    echo "Current benches will be scanned for project creation scripts."
    echo ""
    
    if [ -f "$CONFIG_FILE" ]; then
        echo -e "${YELLOW}⚠️  This will overwrite your existing configuration!${NC}"
        echo "A backup will be saved to: $BACKUP_FILE"
        echo ""
        read -p "Continue? [y/N]: " confirm
        case $confirm in
            [Yy]* ) ;;
            * ) echo "Cancelled."; exit 0 ;;
        esac
        echo ""
    fi
    
    # Generate new configuration
    local new_config
    new_config=$(generate_config)
    
    # Validate JSON
    if echo "$new_config" | jq . >/dev/null 2>&1; then
        echo "$new_config" | jq . > "$CONFIG_FILE"
        echo -e "${GREEN}✅ Configuration updated successfully!${NC}"
        echo ""
        echo -e "${BLUE}Summary:${NC}"
        echo "  Infrastructure: $(jq -r '.infrastructure | keys | length' "$CONFIG_FILE") components"
        echo "  Benches: $(jq -r '.benches | keys | length' "$CONFIG_FILE") benches"
        echo "  Project Scripts: $(jq -r '[.benches[].project_scripts[]?] | length' "$CONFIG_FILE") scripts"
        echo ""
        echo "Run './setup-workbenches.sh' to install missing benches"
        echo "Run './new-project.sh' to create projects using discovered scripts"
    else
        echo -e "${RED}❌ Generated configuration is invalid JSON${NC}"
        if [ -f "$BACKUP_FILE" ]; then
            cp "$BACKUP_FILE" "$CONFIG_FILE"
            echo "Restored backup configuration"
        fi
        exit 1
    fi
}

main "$@"