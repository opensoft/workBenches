#!/bin/bash

# WorkBenches Setup Script
# Clones infrastructure and selected benches based on user input

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/bench-config.json"
INSTALLED_FILE="$SCRIPT_DIR/.installed-benches.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if required tools are available
check_dependencies() {
    local missing_deps=()
    
    if ! command -v git &> /dev/null; then
        missing_deps+=("git")
    fi
    
    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo -e "${RED}Error: Missing required dependencies: ${missing_deps[*]}${NC}"
        echo "Please install the missing dependencies and run again."
        exit 1
    fi
}

# Load configuration
load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}Error: Configuration file not found: $CONFIG_FILE${NC}"
        exit 1
    fi
}

# Initialize installed benches tracking file
init_installed_file() {
    if [ ! -f "$INSTALLED_FILE" ]; then
        echo '{"installed": [], "last_updated": ""}' > "$INSTALLED_FILE"
    fi
}

# Check if a bench is already installed
is_installed() {
    local bench_name="$1"
    local bench_path
    bench_path=$(jq -r ".benches.${bench_name}.path // .infrastructure.${bench_name}.path" "$CONFIG_FILE" 2>/dev/null)
    
    if [ "$bench_path" != "null" ] && [ -d "$SCRIPT_DIR/$bench_path" ]; then
        return 0
    fi
    return 1
}

# Clone a repository
clone_repo() {
    local name="$1"
    local url="$2"
    local path="$3"
    local description="$4"
    
    echo -e "${BLUE}Cloning $name: $description${NC}"
    
    # Create parent directory if needed
    local parent_dir
    parent_dir=$(dirname "$SCRIPT_DIR/$path")
    if [ "$parent_dir" != "$SCRIPT_DIR" ]; then
        mkdir -p "$parent_dir"
    fi
    
    if git clone "$url" "$SCRIPT_DIR/$path"; then
        echo -e "${GREEN}✓ Successfully cloned $name${NC}"
        # Update installed tracking
        local current_time
        current_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        jq --arg bench "$name" --arg time "$current_time" \
           '.installed += [$bench] | .installed |= unique | .last_updated = $time' \
           "$INSTALLED_FILE" > "$INSTALLED_FILE.tmp" && mv "$INSTALLED_FILE.tmp" "$INSTALLED_FILE"
        return 0
    else
        echo -e "${RED}✗ Failed to clone $name${NC}"
        return 1
    fi
}

# Setup infrastructure (always installed)
setup_infrastructure() {
    echo -e "${YELLOW}Setting up infrastructure...${NC}"
    echo "Infrastructure components are always installed."
    echo ""
    
    while IFS= read -r infra_name; do
        if is_installed "$infra_name"; then
            echo -e "${GREEN}✓ $infra_name is already installed${NC}"
        else
            local url description path
            url=$(jq -r ".infrastructure.${infra_name}.url" "$CONFIG_FILE")
            description=$(jq -r ".infrastructure.${infra_name}.description" "$CONFIG_FILE")
            path=$(jq -r ".infrastructure.${infra_name}.path" "$CONFIG_FILE")
            
            clone_repo "$infra_name" "$url" "$path" "$description"
        fi
    done < <(jq -r '.infrastructure | keys[]' "$CONFIG_FILE")
    
    echo ""
}

# Prompt for bench selection
prompt_bench_selection() {
    local bench_names
    mapfile -t bench_names < <(jq -r '.benches | keys[]' "$CONFIG_FILE")
    
    echo -e "${YELLOW}Available benches to install:${NC}"
    
    # Show available benches with descriptions
    for bench in "${bench_names[@]}"; do
        local description status
        description=$(jq -r ".benches.${bench}.description" "$CONFIG_FILE")
        
        if is_installed "$bench"; then
            status="${GREEN}[INSTALLED]${NC}"
        else
            status="${RED}[NOT INSTALLED]${NC}"
        fi
        
        echo -e "  - ${BLUE}$bench${NC}: $description $status"
    done
    
    echo ""
    echo "Choose installation option:"
    echo "  1) Install all benches"
    echo "  2) Select benches individually"
    echo "  3) Skip bench installation"
    echo ""
    
    while true; do
        read -p "Enter your choice (1-3): " choice
        case $choice in
            1)
                install_all_benches "${bench_names[@]}"
                break
                ;;
            2)
                select_benches_individually "${bench_names[@]}"
                break
                ;;
            3)
                echo -e "${YELLOW}Skipping bench installation.${NC}"
                break
                ;;
            *)
                echo -e "${RED}Invalid choice. Please enter 1, 2, or 3.${NC}"
                ;;
        esac
    done
}

# Install all benches
install_all_benches() {
    local benches=("$@")
    echo -e "${YELLOW}Installing all benches...${NC}"
    echo ""
    
    for bench in "${benches[@]}"; do
        if is_installed "$bench"; then
            echo -e "${GREEN}✓ $bench is already installed${NC}"
        else
            local url description path
            url=$(jq -r ".benches.${bench}.url" "$CONFIG_FILE")
            description=$(jq -r ".benches.${bench}.description" "$CONFIG_FILE")
            path=$(jq -r ".benches.${bench}.path" "$CONFIG_FILE")
            
            clone_repo "$bench" "$url" "$path" "$description"
        fi
    done
}

# Select benches individually
select_benches_individually() {
    local benches=("$@")
    echo -e "${YELLOW}Select benches to install:${NC}"
    echo ""
    
    for bench in "${benches[@]}"; do
        if is_installed "$bench"; then
            echo -e "${GREEN}✓ $bench is already installed (skipping)${NC}"
            continue
        fi
        
        local description
        description=$(jq -r ".benches.${bench}.description" "$CONFIG_FILE")
        
        while true; do
            read -p "Install $bench ($description)? [y/N]: " answer
            case $answer in
                [Yy]* )
                    local url path
                    url=$(jq -r ".benches.${bench}.url" "$CONFIG_FILE")
                    path=$(jq -r ".benches.${bench}.path" "$CONFIG_FILE")
                    clone_repo "$bench" "$url" "$path" "$description"
                    break
                    ;;
                [Nn]* | "" )
                    echo -e "${YELLOW}Skipping $bench${NC}"
                    break
                    ;;
                * )
                    echo "Please answer yes or no."
                    ;;
            esac
        done
    done
}

# Show summary
show_summary() {
    echo ""
    echo -e "${YELLOW}=== Installation Summary ===${NC}"
    
    local installed_count=0
    local total_count=0
    
    # Check infrastructure
    echo -e "${BLUE}Infrastructure:${NC}"
    while IFS= read -r infra_name; do
        ((total_count++))
        if is_installed "$infra_name"; then
            echo -e "  ✓ $infra_name ${GREEN}[INSTALLED]${NC}"
            ((installed_count++))
        else
            echo -e "  ✗ $infra_name ${RED}[NOT INSTALLED]${NC}"
        fi
    done < <(jq -r '.infrastructure | keys[]' "$CONFIG_FILE")
    
    # Check benches
    echo -e "${BLUE}Benches:${NC}"
    while IFS= read -r bench_name; do
        ((total_count++))
        if is_installed "$bench_name"; then
            echo -e "  ✓ $bench_name ${GREEN}[INSTALLED]${NC}"
            ((installed_count++))
        else
            echo -e "  ✗ $bench_name ${RED}[NOT INSTALLED]${NC}"
        fi
    done < <(jq -r '.benches | keys[]' "$CONFIG_FILE")
    
    echo ""
    echo -e "${BLUE}Total: $installed_count/$total_count components installed${NC}"
}

# Main function
main() {
    echo -e "${BLUE}WorkBenches Setup Script${NC}"
    echo "=========================="
    echo ""
    
    check_dependencies
    load_config
    init_installed_file
    
    setup_infrastructure
    prompt_bench_selection
    show_summary
    
    echo ""
    echo -e "${GREEN}Setup complete!${NC}"
    echo "You can re-run this script at any time to install additional benches."
}

# Run main function
main "$@"