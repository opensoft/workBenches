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
    
    if ! command -v curl &> /dev/null; then
        missing_deps+=("curl")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo -e "${RED}Error: Missing required dependencies: ${missing_deps[*]}${NC}"
        echo "Please install the missing dependencies and run this script again."
        echo ""
        echo -e "${YELLOW}Installation commands:${NC}"
        echo "  Ubuntu/Debian: sudo apt update && sudo apt install ${missing_deps[*]}"
        echo "  macOS:         brew install ${missing_deps[*]}"
        echo "  Alpine:        apk add ${missing_deps[*]}"
        echo "  CentOS/RHEL:   sudo yum install ${missing_deps[*]}"
        echo ""
        echo "After installation, re-run: ./setup-workbenches.sh"
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

# Install onp command
install_onp_command() {
    echo -e "${BLUE}Installing onp (Opensoft New Project) command...${NC}"
    
    # Ensure ~/.local/bin exists
    mkdir -p "$HOME/.local/bin"
    
    # Copy and make executable
    if cp "$SCRIPT_DIR/onp" "$HOME/.local/bin/onp" && chmod +x "$HOME/.local/bin/onp"; then
        echo -e "${GREEN}✓ onp command installed to ~/.local/bin/onp${NC}"
        echo "You can now run 'onp' from anywhere to create new projects."
    else
        echo -e "${YELLOW}⚠ Failed to install onp command${NC}"
        echo "You can manually copy it later: cp onp ~/.local/bin/ && chmod +x ~/.local/bin/onp"
    fi
    echo ""
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

# Setup AI features (optional)
setup_ai_features() {
    echo -e "${YELLOW}AI-Powered Features Setup${NC}"
    echo "workBenches supports AI-powered bench creation with current tech stack information."
    echo ""
    echo -e "${BLUE}AI Features include:${NC}"
    echo "• Current technology and framework discovery"
    echo "• Up-to-date best practices and tools"
    echo "• Smart bench generation with latest versions"
    echo ""
    
    while true; do
        read -p "Would you like to enable AI-powered features? [y/N]: " ai_choice
        case $ai_choice in
            [Yy]* )
                setup_ai_api_keys
                break
                ;;
            [Nn]* | "" )
                echo -e "${YELLOW}Skipping AI setup. You can enable AI features later by setting environment variables.${NC}"
                echo -e "${BLUE}To enable later:${NC}"
                echo "  export OPENAI_API_KEY='your-openai-key'"
                echo "  # OR"
                echo "  export ANTHROPIC_API_KEY='your-claude-key'"
                break
                ;;
            * )
                echo "Please answer yes or no."
                ;;
        esac
    done
    echo ""
}

# Setup AI API keys
setup_ai_api_keys() {
    echo -e "${BLUE}AI API Key Setup${NC}"
    echo "Choose your preferred AI service:"
    echo "  1) OpenAI (GPT-4) - Requires OpenAI API key"
    echo "  2) Anthropic (Claude) - Requires Anthropic API key"
    echo "  3) Both - Set up both services"
    echo "  4) Skip - I'll set up manually later"
    echo ""
    
    while true; do
        read -p "Enter your choice (1-4): " api_choice
        case $api_choice in
            1)
                setup_openai_key
                break
                ;;
            2)
                setup_anthropic_key
                break
                ;;
            3)
                setup_openai_key
                setup_anthropic_key
                break
                ;;
            4)
                echo -e "${YELLOW}Skipping API key setup.${NC}"
                break
                ;;
            *)
                echo -e "${RED}Invalid choice. Please enter 1-4.${NC}"
                ;;
        esac
    done
}

# Setup OpenAI API key
setup_openai_key() {
    echo ""
    echo -e "${BLUE}OpenAI API Key Setup${NC}"
    echo "Get your API key from: https://platform.openai.com/api-keys"
    echo ""
    
    while true; do
        read -p "Enter your OpenAI API key (or 'skip' to skip): " openai_key
        if [ "$openai_key" = "skip" ]; then
            echo -e "${YELLOW}Skipping OpenAI setup.${NC}"
            break
        elif [ -z "$openai_key" ]; then
            echo -e "${RED}API key cannot be empty. Enter 'skip' to skip this step.${NC}"
        elif [[ ! "$openai_key" =~ ^sk- ]]; then
            echo -e "${RED}Invalid OpenAI API key format. Keys should start with 'sk-'${NC}"
        else
            # Test the API key
            echo -e "${YELLOW}Testing API key...${NC}"
            local test_response
            test_response=$(curl -s -X POST "https://api.openai.com/v1/chat/completions" \
                -H "Authorization: Bearer $openai_key" \
                -H "Content-Type: application/json" \
                -d '{
                    "model": "gpt-4o-mini",
                    "messages": [{"role": "user", "content": "Hi"}],
                    "max_tokens": 5
                }' 2>/dev/null)
            
            if echo "$test_response" | jq -e '.choices[0].message.content' >/dev/null 2>&1; then
                echo -e "${GREEN}✓ OpenAI API key validated successfully!${NC}"
                save_api_key "OPENAI_API_KEY" "$openai_key"
                export OPENAI_API_KEY="$openai_key"
                break
            else
                echo -e "${RED}✗ API key validation failed. Please check your key.${NC}"
                echo "Error response: $(echo "$test_response" | jq -r '.error.message // "Unknown error"' 2>/dev/null || echo "Network/parsing error")"
            fi
        fi
    done
}

# Setup Anthropic API key
setup_anthropic_key() {
    echo ""
    echo -e "${BLUE}Anthropic (Claude) API Key Setup${NC}"
    echo "Get your API key from: https://console.anthropic.com/account/keys"
    echo ""
    
    while true; do
        read -p "Enter your Anthropic API key (or 'skip' to skip): " anthropic_key
        if [ "$anthropic_key" = "skip" ]; then
            echo -e "${YELLOW}Skipping Anthropic setup.${NC}"
            break
        elif [ -z "$anthropic_key" ]; then
            echo -e "${RED}API key cannot be empty. Enter 'skip' to skip this step.${NC}"
        elif [[ ! "$anthropic_key" =~ ^sk- ]]; then
            echo -e "${RED}Invalid Anthropic API key format. Keys should start with 'sk-'${NC}"
        else
            # Test the API key
            echo -e "${YELLOW}Testing API key...${NC}"
            local test_response
            test_response=$(curl -s -X POST "https://api.anthropic.com/v1/messages" \
                -H "x-api-key: $anthropic_key" \
                -H "Content-Type: application/json" \
                -H "anthropic-version: 2023-06-01" \
                -d '{
                    "model": "claude-3-haiku-20240307",
                    "max_tokens": 5,
                    "messages": [{"role": "user", "content": "Hi"}]
                }' 2>/dev/null)
            
            if echo "$test_response" | jq -e '.content[0].text' >/dev/null 2>&1; then
                echo -e "${GREEN}✓ Anthropic API key validated successfully!${NC}"
                save_api_key "ANTHROPIC_API_KEY" "$anthropic_key"
                export ANTHROPIC_API_KEY="$anthropic_key"
                break
            else
                echo -e "${RED}✗ API key validation failed. Please check your key.${NC}"
                echo "Error response: $(echo "$test_response" | jq -r '.error.message // "Unknown error"' 2>/dev/null || echo "Network/parsing error")"
            fi
        fi
    done
}

# Save API key to shell profile
save_api_key() {
    local key_name="$1"
    local key_value="$2"
    local shell_profile
    
    # Determine shell profile file
    if [ -n "$ZSH_VERSION" ]; then
        shell_profile="$HOME/.zshrc"
    elif [ -n "$BASH_VERSION" ]; then
        shell_profile="$HOME/.bashrc"
    else
        shell_profile="$HOME/.profile"
    fi
    
    # Check if key already exists in profile
    if grep -q "^export $key_name=" "$shell_profile" 2>/dev/null; then
        echo -e "${YELLOW}Updating existing $key_name in $shell_profile${NC}"
        # Use sed to update the existing line
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS
            sed -i "" "s/^export $key_name=.*/export $key_name='$key_value'/" "$shell_profile"
        else
            # Linux
            sed -i "s/^export $key_name=.*/export $key_name='$key_value'/" "$shell_profile"
        fi
    else
        echo -e "${GREEN}Adding $key_name to $shell_profile${NC}"
        echo "" >> "$shell_profile"
        echo "# workBenches AI API Key" >> "$shell_profile"
        echo "export $key_name='$key_value'" >> "$shell_profile"
    fi
    
    echo -e "${BLUE}API key saved to $shell_profile${NC}"
    echo -e "${YELLOW}Note: Restart your terminal or run 'source $shell_profile' to use the key in new sessions.${NC}"
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
    setup_ai_features
    install_onp_command
    show_summary
    
    echo ""
    echo -e "${GREEN}Setup complete!${NC}"
    echo "You can re-run this script at any time to install additional benches."
    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo "• Create projects: onp (or ./new-project.sh)"
    if [ -n "$OPENAI_API_KEY" ] || [ -n "$ANTHROPIC_API_KEY" ]; then
        echo "• Create AI-powered benches: ./new-bench.sh"
    else
        echo "• Create benches: ./new-bench.sh (basic mode)"
    fi
    echo "• Update configuration: ./update-bench-config.sh"
}

# Run main function
main "$@"