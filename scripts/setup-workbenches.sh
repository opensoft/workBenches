#!/bin/bash

# WorkBenches Setup Script
# Clones infrastructure and selected benches based on user input

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../config/bench-config.json"
INSTALLED_FILE="$SCRIPT_DIR/../.installed-benches.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Auto-install missing dependencies
auto_install_dependencies() {
    local deps=("$@")
    
    echo -e "${CYAN}Attempting to install missing dependencies: ${deps[*]}${NC}"
    echo ""
    
    # Detect OS and package manager
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        OS=$(uname -s)
    fi
    
    case "$OS" in
        ubuntu|debian|pop)
            echo "Detected Ubuntu/Debian-based system"
            echo "Running: sudo apt update && sudo apt install -y ${deps[*]}"
            if sudo apt update && sudo apt install -y "${deps[@]}"; then
                echo -e "${GREEN}✓ Successfully installed dependencies${NC}"
                return 0
            else
                echo -e "${RED}✗ Failed to install dependencies${NC}"
                return 1
            fi
            ;;
        fedora|rhel|centos)
            echo "Detected Red Hat-based system"
            echo "Running: sudo yum install -y ${deps[*]}"
            if sudo yum install -y "${deps[@]}"; then
                echo -e "${GREEN}✓ Successfully installed dependencies${NC}"
                return 0
            else
                echo -e "${RED}✗ Failed to install dependencies${NC}"
                return 1
            fi
            ;;
        alpine)
            echo "Detected Alpine Linux"
            echo "Running: apk add ${deps[*]}"
            if sudo apk add "${deps[@]}"; then
                echo -e "${GREEN}✓ Successfully installed dependencies${NC}"
                return 0
            else
                echo -e "${RED}✗ Failed to install dependencies${NC}"
                return 1
            fi
            ;;
        Darwin|darwin|macos)
            echo "Detected macOS"
            if command -v brew &> /dev/null; then
                echo "Running: brew install ${deps[*]}"
                if brew install "${deps[@]}"; then
                    echo -e "${GREEN}✓ Successfully installed dependencies${NC}"
                    return 0
                else
                    echo -e "${RED}✗ Failed to install dependencies${NC}"
                    return 1
                fi
            else
                echo -e "${RED}Homebrew not found. Please install Homebrew first:${NC}"
                echo "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
                return 1
            fi
            ;;
        *)
            echo -e "${YELLOW}Unknown OS: $OS${NC}"
            echo "Please install manually: ${deps[*]}"
            return 1
            ;;
    esac
}

# Check if required tools are available
check_dependencies() {
    echo -e "${YELLOW}Checking Required Dependencies${NC}"
    echo ""
    
    local missing_deps=()
    local installed_deps=()
    
    # Check git
    if command -v git &> /dev/null; then
        local git_version=$(git --version | awk '{print $3}')
        echo -e "  ${GREEN}✓ git${NC} - installed (version: $git_version)"
        installed_deps+=("git")
    else
        echo -e "  ${RED}✗ git${NC} - not installed"
        missing_deps+=("git")
    fi
    
    # Check jq
    if command -v jq &> /dev/null; then
        local jq_version=$(jq --version 2>&1 | sed 's/jq-//')
        echo -e "  ${GREEN}✓ jq${NC} - installed (version: $jq_version)"
        installed_deps+=("jq")
    else
        echo -e "  ${RED}✗ jq${NC} - not installed"
        missing_deps+=("jq")
    fi
    
    # Check curl
    if command -v curl &> /dev/null; then
        local curl_version=$(curl --version | head -n1 | awk '{print $2}')
        echo -e "  ${GREEN}✓ curl${NC} - installed (version: $curl_version)"
        installed_deps+=("curl")
    else
        echo -e "  ${RED}✗ curl${NC} - not installed"
        missing_deps+=("curl")
    fi
    
    # Check Node.js (recommended for AI CLI tools)
    if command -v node &> /dev/null; then
        local node_version=$(node --version | sed 's/v//')
        local node_major=$(echo $node_version | cut -d'.' -f1)
        if [ "$node_major" -ge 18 ]; then
            echo -e "  ${GREEN}✓ node${NC} - installed (version: v$node_version)"
            installed_deps+=("node")
        else
            echo -e "  ${YELLOW}⚠ node${NC} - installed but outdated (version: v$node_version, recommended: 22+)"
        fi
    else
        echo -e "  ${YELLOW}⚠ node${NC} - not installed (recommended for Codex, Copilot, OpenSpec)"
        echo -e "     Install from: ${BLUE}https://nodejs.org/${NC}"
    fi
    
    # Check npm (comes with Node.js)
    if command -v npm &> /dev/null; then
        local npm_version=$(npm --version)
        echo -e "  ${GREEN}✓ npm${NC} - installed (version: $npm_version)"
        installed_deps+=("npm")
    fi
    
    echo ""
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo -e "${RED}⚠️  Missing required dependencies: ${missing_deps[*]}${NC}"
        echo -e "${YELLOW}These tools are required to run workBenches setup.${NC}"
        echo ""
        
        # Ask user if they want to auto-install
        while true; do
            read -p "Would you like to attempt automatic installation? [Y/n]: " install_choice
            case $install_choice in
                [Yy]* | "" )
                    echo ""
                    if auto_install_dependencies "${missing_deps[@]}"; then
                        echo ""
                        echo -e "${GREEN}Dependencies installed successfully!${NC}"
                        echo "Continuing with setup..."
                        echo ""
                        sleep 1
                        return 0
                    else
                        echo ""
                        echo -e "${RED}Automatic installation failed.${NC}"
                        echo ""
                        echo -e "${YELLOW}Please install manually:${NC}"
                        echo "  Ubuntu/Debian: sudo apt update && sudo apt install ${missing_deps[*]}"
                        echo "  macOS:         brew install ${missing_deps[*]}"
                        echo "  Alpine:        apk add ${missing_deps[*]}"
                        echo "  CentOS/RHEL:   sudo yum install ${missing_deps[*]}"
                        echo ""
                        echo "After installation, re-run: ./setup-workbenches.sh"
                        exit 1
                    fi
                    ;;
                [Nn]* )
                    echo ""
                    echo -e "${YELLOW}Manual installation required:${NC}"
                    echo "  Ubuntu/Debian: sudo apt update && sudo apt install ${missing_deps[*]}"
                    echo "  macOS:         brew install ${missing_deps[*]}"
                    echo "  Alpine:        apk add ${missing_deps[*]}"
                    echo "  CentOS/RHEL:   sudo yum install ${missing_deps[*]}"
                    echo ""
                    echo "After installation, re-run: ./setup-workbenches.sh"
                    exit 1
                    ;;
                * )
                    echo "Please answer yes or no."
                    ;;
            esac
        done
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
    
    if [ "$bench_path" != "null" ] && [ -d "$SCRIPT_DIR/../$bench_path" ]; then
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
    parent_dir=$(dirname "$SCRIPT_DIR/../$path")
    if [ "$parent_dir" != "$SCRIPT_DIR/.." ]; then
        mkdir -p "$parent_dir"
    fi
    
    if git clone "$url" "$SCRIPT_DIR/../$path"; then
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

# Install workBenches commands globally
install_workbench_commands() {
    echo -e "${YELLOW}Global Commands Installation${NC}"
    echo "Install key workBenches commands globally for easy access?"
    echo ""
    echo -e "${BLUE}Commands to be installed:${NC}"
    echo "• launchBench     - Universal bench launcher with AI routing"
    echo "• onp             - Quick project creation"
    echo "• setup-workbenches - WorkBenches setup and configuration"
    echo "• update-bench-config - Auto-discover and update configuration"
    echo "• new-bench       - Create new development benches"
    echo ""
    
    while true; do
        read -p "Install workBenches commands globally? [Y/n]: " install_choice
        case $install_choice in
            [Yy]* | "" )
                if [ -f "$SCRIPT_DIR/install-workbench-commands.sh" ]; then
                    "$SCRIPT_DIR/install-workbench-commands.sh" --install
                    if [ $? -eq 0 ]; then
                        echo -e "${GREEN}✓ WorkBenches commands installed successfully!${NC}"
                        echo "You can now use these commands from anywhere:"
                        echo "  • launchBench"
                        echo "  • onp"
                        echo "  • setup-workbenches"
                        echo "  • update-bench-config"
                        echo "  • new-bench"
                    else
                        echo -e "${YELLOW}⚠ Some commands may not have been installed correctly${NC}"
                    fi
                else
                    echo -e "${RED}✗ install-workbench-commands.sh not found${NC}"
                fi
                break
                ;;
            [Nn]* )
                echo -e "${YELLOW}Skipping global commands installation${NC}"
                echo "You can install them later with: ./install-workbench-commands.sh --install"
                break
                ;;
            * )
                echo "Please answer yes or no."
                ;;
        esac
    done
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

# Show AI credentials status
show_ai_credentials_status() {
    echo -e "${YELLOW}AI Credentials Status${NC}"
    
    # Check OpenAI
    if [ -n "$OPENAI_API_KEY" ]; then
        echo -e "  ${GREEN}✓ OpenAI API Key${NC} - configured"
    else
        echo -e "  ${RED}✗ OpenAI API Key${NC} - not configured"
    fi
    
    # Check Anthropic
    if [ -n "$ANTHROPIC_API_KEY" ]; then
        echo -e "  ${GREEN}✓ Anthropic API Key${NC} - configured"
    else
        echo -e "  ${RED}✗ Anthropic API Key${NC} - not configured"
    fi
    
    # Check Claude Session
    if [ -f "$HOME/.claude/config.json" ]; then
        echo -e "  ${GREEN}✓ Claude Session Token${NC} - configured"
    else
        echo -e "  ${RED}✗ Claude Session Token${NC} - not configured"
    fi
    
    echo ""
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
        read -p "Would you like to setup or update AI credentials now? [y/N]: " ai_choice
        case $ai_choice in
            [Yy]* )
                setup_ai_api_keys
                break
                ;;
            [Nn]* | "" )
                echo -e "${YELLOW}Skipping AI setup.${NC}"
                echo "You can setup credentials later:"
                echo "  - Run: ./scripts/check-ai-credentials.sh --interactive"
                echo "  - Or manually set environment variables"
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
    echo "  2) Anthropic Claude API - Requires Anthropic API key"
    echo "  3) Claude Session Token - For Claude CLI access"
    echo "  4) All services - Set up all available services"
    echo "  5) Skip - I'll set up manually later"
    echo ""
    
    while true; do
        read -p "Enter your choice (1-5): " api_choice
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
                setup_claude_session
                break
                ;;
            4)
                setup_openai_key
                setup_anthropic_key
                setup_claude_session
                break
                ;;
            5)
                echo -e "${YELLOW}Skipping API key setup.${NC}"
                break
                ;;
            *)
                echo -e "${RED}Invalid choice. Please enter 1-5.${NC}"
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

# Setup Claude session token
setup_claude_session() {
    echo ""
    echo -e "${BLUE}Claude Session Token Setup${NC}"
    echo -e "${CYAN}This will set up Claude CLI session access for all your projects.${NC}"
    echo ""
    echo -e "${YELLOW}📋 Instructions:${NC}"
    echo "  1. Visit: https://claude.ai/"
    echo "  2. Log in to your Claude account"
    echo "  3. Open browser DevTools (F12 or Right-click → Inspect)"
    echo "  4. Go to Application/Storage → Cookies → https://claude.ai"
    echo "  5. Find the 'sessionKey' cookie and copy its value"
    echo ""
    echo -e "${BLUE}Alternative method:${NC}"
    echo "  1. In DevTools Console, run: document.cookie"
    echo "  2. Find and copy the sessionKey value"
    echo ""
    
    # Ask if user wants to proceed or get help
    while true; do
        echo -e "${YELLOW}Options:${NC}"
        echo "  1) I have my session key ready - let me paste it"
        echo "  2) Open browser instructions in a new window (if available)"
        echo "  3) Skip - I'll set this up later"
        echo ""
        read -p "Enter your choice (1-3): " session_choice
        
        case $session_choice in
            1)
                # Proceed to get session key
                break
                ;;
            2)
                # Try to open browser with instructions
                echo -e "${CYAN}Opening Claude login page...${NC}"
                if command -v xdg-open &> /dev/null; then
                    xdg-open "https://claude.ai/" &>/dev/null &
                elif command -v open &> /dev/null; then
                    open "https://claude.ai/" &>/dev/null &
                else
                    echo -e "${YELLOW}Could not auto-open browser. Please manually visit: https://claude.ai/${NC}"
                fi
                echo ""
                echo -e "${YELLOW}Press Enter when you have your session key ready...${NC}"
                read
                break
                ;;
            3)
                echo -e "${YELLOW}Skipping Claude session setup.${NC}"
                return 0
                ;;
            *)
                echo -e "${RED}Invalid choice. Please enter 1-3.${NC}"
                ;;
        esac
    done
    
    # Get session key from user
    echo ""
    echo -e "${BLUE}Enter your Claude session key:${NC}"
    echo -e "${CYAN}(It should be a long alphanumeric string starting with 'sk-ant-sid')${NC}"
    echo ""
    
    local session_key
    while true; do
        read -p "Session key (or 'skip' to skip): " session_key
        
        if [ "$session_key" = "skip" ]; then
            echo -e "${YELLOW}Skipping Claude session setup.${NC}"
            return 0
        elif [ -z "$session_key" ]; then
            echo -e "${RED}Session key cannot be empty. Enter 'skip' to skip this step.${NC}"
        elif [[ ! "$session_key" =~ ^sk-ant-sid ]]; then
            echo -e "${YELLOW}⚠️  Warning: Session key format doesn't match expected pattern (sk-ant-sid...).${NC}"
            read -p "Continue anyway? [y/N]: " continue_anyway
            if [[ "$continue_anyway" =~ ^[Yy] ]]; then
                break
            fi
        else
            break
        fi
    done
    
    # Create .claude directory structure
    echo -e "${CYAN}Setting up ~/.claude directory...${NC}"
    mkdir -p "$HOME/.claude"
    
    # Save session key to config file
    cat > "$HOME/.claude/config.json" << EOF
{
  "sessionKey": "$session_key",
  "createdAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "createdBy": "workBenches setup"
}
EOF
    
    # Set appropriate permissions (readable only by user)
    chmod 600 "$HOME/.claude/config.json"
    
    echo -e "${GREEN}✓ Claude session key saved to ~/.claude/config.json${NC}"
    echo -e "${BLUE}Session key is accessible to all projects on this machine.${NC}"
    echo ""
    echo -e "${YELLOW}📝 Note:${NC}"
    echo "  - Session keys may expire after a period of inactivity"
    echo "  - You can update the key anytime by re-running this setup"
    echo "  - The config file has restricted permissions (600) for security"
    echo ""
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

# Show AI coding assistants CLI status (no prompts)
show_ai_assistants_status() {
    echo -e "${YELLOW}AI Coding Assistant CLIs${NC}"
    
    # Check if Claude Code CLI is installed
    if command -v claude &> /dev/null; then
        local claude_version=$(claude --version 2>/dev/null | head -n1 || echo "unknown")
        echo -e "  ${GREEN}✓ Claude Code CLI${NC} - installed (version: $claude_version)"
    else
        echo -e "  ${RED}✗ Claude Code CLI${NC} - not installed"
    fi
    
    # Check if GitHub Copilot CLI is installed
    if command -v copilot &> /dev/null; then
        local copilot_version=$(copilot --version 2>/dev/null || echo "unknown")
        echo -e "  ${GREEN}✓ GitHub Copilot CLI${NC} - installed (version: $copilot_version)"
    else
        echo -e "  ${RED}✗ GitHub Copilot CLI${NC} - not installed"
    fi
    
    # Check if Codex CLI is installed
    if command -v codex &> /dev/null; then
        local codex_version=$(codex --version 2>/dev/null || echo "unknown")
        echo -e "  ${GREEN}✓ Codex CLI${NC} - installed (version: $codex_version)"
    else
        echo -e "  ${RED}✗ Codex CLI${NC} - not installed"
    fi
    
    # Check if Gemini CLI is installed
    if command -v gemini &> /dev/null; then
        local gemini_version=$(gemini --version 2>/dev/null || echo "unknown")
        echo -e "  ${GREEN}✓ Gemini CLI${NC} - installed (version: $gemini_version)"
    else
        echo -e "  ${RED}✗ Gemini CLI${NC} - not installed"
    fi
    
    # Check if OpenCode CLI is installed
    if command -v opencode &> /dev/null; then
        local opencode_version=$(opencode --version 2>/dev/null || echo "unknown")
        echo -e "  ${GREEN}✓ OpenCode CLI${NC} - installed (version: $opencode_version)"
    else
        echo -e "  ${RED}✗ OpenCode CLI${NC} - not installed"
    fi
    
    echo ""
}

# Show spec-driven development tools status (no prompts)
show_spec_tools_status() {
    echo -e "${YELLOW}Spec-Driven Development Tools${NC}"
    
    # Check if spec-kit is installed
    if command -v specify &> /dev/null; then
        local spec_kit_version=$(specify --version 2>/dev/null || echo "unknown")
        echo -e "  ${GREEN}✓ spec-kit${NC} (GitHub Spec Kit) - installed (version: $spec_kit_version)"
    else
        echo -e "  ${RED}✗ spec-kit${NC} (GitHub Spec Kit) - not installed"
    fi
    
    # Check if OpenSpec is installed
    if command -v openspec &> /dev/null; then
        local openspec_version=$(openspec --version 2>/dev/null || echo "unknown")
        echo -e "  ${GREEN}✓ OpenSpec${NC} - installed (version: $openspec_version)"
    else
        echo -e "  ${RED}✗ OpenSpec${NC} - not installed"
    fi
    
    echo ""
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

# Check and install spec-driven development tools
check_spec_tools() {
    echo -e "${YELLOW}Spec-Driven Development Tools${NC}"
    echo "WorkBenches supports spec-driven development with spec-kit and OpenSpec."
    echo ""
    
    local spec_kit_installed=false
    local openspec_installed=false
    
    # Check if spec-kit is installed
    if command -v specify &> /dev/null; then
        spec_kit_installed=true
        local spec_kit_version=$(specify --version 2>/dev/null || echo "unknown")
        echo -e "  ${GREEN}✓ spec-kit${NC} (GitHub Spec Kit) - installed (version: $spec_kit_version)"
    else
        echo -e "  ${RED}✗ spec-kit${NC} (GitHub Spec Kit) - not installed"
    fi
    
    # Check if OpenSpec is installed
    if command -v openspec &> /dev/null; then
        openspec_installed=true
        local openspec_version=$(openspec --version 2>/dev/null || echo "unknown")
        echo -e "  ${GREEN}✓ OpenSpec${NC} - installed (version: $openspec_version)"
    else
        echo -e "  ${RED}✗ OpenSpec${NC} - not installed"
    fi
    
    echo ""
    
    # If both are installed, no need to prompt
    if [ "$spec_kit_installed" = true ] && [ "$openspec_installed" = true ]; then
        echo -e "${GREEN}Both spec-driven development tools are installed.${NC}"
        echo ""
        return 0
    fi
    
    # Ask if user wants to install missing tools
    while true; do
        read -p "Would you like to install the missing spec-driven development tools? [Y/n]: " install_choice
        case $install_choice in
            [Yy]* | "" )
                echo ""
                install_spec_tools "$spec_kit_installed" "$openspec_installed"
                break
                ;;
            [Nn]* )
                echo -e "${YELLOW}Skipping spec-driven development tools installation.${NC}"
                echo "You can install them later:"
                if [ "$spec_kit_installed" = false ]; then
                    echo "  spec-kit: uvx --from git+https://github.com/github/spec-kit.git specify --help"
                fi
                if [ "$openspec_installed" = false ]; then
                    echo "  OpenSpec: npm install -g @fission-ai/openspec@latest"
                fi
                break
                ;;
            * )
                echo "Please answer yes or no."
                ;;
        esac
    done
    echo ""
}

# Install spec-driven development tools
install_spec_tools() {
    local spec_kit_installed="$1"
    local openspec_installed="$2"
    local success_count=0
    local total_count=0
    
    # Install spec-kit if needed
    if [ "$spec_kit_installed" = false ]; then
        ((total_count++))
        echo -e "${CYAN}Installing spec-kit (GitHub Spec Kit)...${NC}"
        echo "This requires Python 3.11+ and uv package manager."
        echo ""
        
        # Check if uv is installed
        if ! command -v uvx &> /dev/null; then
            echo -e "${YELLOW}uv package manager not found. Installing uv...${NC}"
            if curl -LsSf https://astral.sh/uv/install.sh | sh; then
                echo -e "${GREEN}✓ uv installed successfully${NC}"
                # Source the environment to make uvx available
                export PATH="$HOME/.cargo/bin:$PATH"
            else
                echo -e "${RED}✗ Failed to install uv${NC}"
                echo "Please install uv manually: https://docs.astral.sh/uv/"
            fi
        fi
        
        # Try to install spec-kit
        if command -v uvx &> /dev/null; then
            echo "Installing spec-kit via uvx..."
            if uvx --from git+https://github.com/github/spec-kit.git specify --help &> /dev/null; then
                echo -e "${GREEN}✓ spec-kit installed successfully${NC}"
                ((success_count++))
            else
                echo -e "${RED}✗ Failed to install spec-kit${NC}"
                echo "You can try manually: uvx --from git+https://github.com/github/spec-kit.git specify init <project>"
            fi
        fi
        echo ""
    fi
    
    # Install OpenSpec if needed
    if [ "$openspec_installed" = false ]; then
        ((total_count++))
        echo -e "${CYAN}Installing OpenSpec...${NC}"
        echo "This requires Node.js and npm."
        echo ""
        
        # Check if npm is installed
        if ! command -v npm &> /dev/null; then
            echo -e "${RED}✗ npm not found${NC}"
            echo "Please install Node.js and npm first: https://nodejs.org/"
        else
            echo "Installing OpenSpec via npm..."
            if npm install -g @fission-ai/openspec@latest; then
                echo -e "${GREEN}✓ OpenSpec installed successfully${NC}"
                ((success_count++))
            else
                echo -e "${RED}✗ Failed to install OpenSpec${NC}"
                echo "You can try manually: npm install -g @fission-ai/openspec@latest"
            fi
        fi
        echo ""
    fi
    
    # Summary
    if [ $total_count -gt 0 ]; then
        if [ $success_count -eq $total_count ]; then
            echo -e "${GREEN}All spec-driven development tools installed successfully!${NC}"
        elif [ $success_count -gt 0 ]; then
            echo -e "${YELLOW}$success_count of $total_count tools installed successfully.${NC}"
        else
            echo -e "${RED}Installation failed for all tools.${NC}"
        fi
    fi
}

# Show setup menu
show_setup_menu() {
    while true; do
        echo ""
        echo -e "${BLUE}=== WorkBenches Setup Menu ===${NC}"
        echo "1) Interactive Selection (TUI) - Select multiple components"
        echo "2) Install/update benches"
        echo "3) Setup/update AI credentials"
        echo "4) Install spec-driven development tools"
        echo "5) Install commands (onp, launchBench, workbench)"
        echo "6) View setup summary"
        echo "7) Exit setup"
        echo ""
        read -p "Enter your choice (1-7): " menu_choice
        
        case $menu_choice in
            1)
                echo ""
                # Launch interactive TUI
                if [ -f "$SCRIPT_DIR/interactive-setup.sh" ]; then
                    "$SCRIPT_DIR/interactive-setup.sh"
                else
                    echo -e "${RED}Interactive setup not found at: $SCRIPT_DIR/interactive-setup.sh${NC}"
                fi
                ;;
            2)
                echo ""
                setup_infrastructure
                prompt_bench_selection
                ;;
            3)
                echo ""
                show_ai_credentials_status
                setup_ai_features
                ;;
            4)
                echo ""
                check_spec_tools
                ;;
            5)
                echo ""
                install_onp_command
                install_workbench_commands
                ;;
            6)
                echo ""
                show_summary
                ;;
            7)
                echo ""
                echo -e "${GREEN}Exiting setup.${NC}"
                break
                ;;
            *)
                echo -e "${RED}Invalid choice. Please enter 1-7.${NC}"
                ;;
        esac
    done
}

# Main function
main() {
    echo -e "${BLUE}WorkBenches Setup Script${NC}"
    echo "=========================="
    echo ""
    
    check_dependencies
    show_ai_credentials_status
    show_ai_assistants_status
    show_spec_tools_status
    
    load_config
    init_installed_file
    
    # Show interactive menu
    show_setup_menu
    
    echo ""
    echo -e "${GREEN}Setup complete!${NC}"
    echo "You can re-run this script at any time to make changes."
    echo ""
    echo -e "${BLUE}Available commands:${NC}"
    echo "• launchBench - Launch benches with AI routing"
    echo "• onp - Quick project creation"
    echo "• new-bench - Create new development benches"
    echo "• update-bench-config - Update configuration"
    echo "• check-ai-credentials - Manage AI credentials"
    echo ""
    echo -e "${YELLOW}Note:${NC} If commands aren't available globally, restart your shell or run:"
    echo "  source ~/.zshrc  # or ~/.bashrc"
}

# Run main function
main "$@"