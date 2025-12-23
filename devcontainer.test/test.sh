#!/bin/bash
# Layer 0 Test Script
# Tests workbench-base:latest image for system tools and user configuration

set -e

echo "=========================================="
echo "Testing Layer 0: WorkBench Base"
echo "=========================================="
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

test_count=0
pass_count=0
fail_count=0

# Test function
test_tool() {
    local name="$1"
    local command="$2"
    test_count=$((test_count + 1))
    
    if eval "$command" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} $name"
        pass_count=$((pass_count + 1))
        return 0
    else
        echo -e "${RED}✗${NC} $name"
        fail_count=$((fail_count + 1))
        return 1
    fi
}

# Test function with output
test_tool_output() {
    local name="$1"
    local command="$2"
    test_count=$((test_count + 1))
    
    if output=$(eval "$command" 2>&1); then
        echo -e "${GREEN}✓${NC} $name: $output"
        pass_count=$((pass_count + 1))
        return 0
    else
        echo -e "${RED}✗${NC} $name"
        fail_count=$((fail_count + 1))
        return 1
    fi
}

echo "=== Version Control ==="
test_tool_output "Git" "git --version"
test_tool "Git config" "git config --global --list | head -1"

echo ""
echo "=== Network Tools ==="
test_tool_output "curl" "curl --version | head -1"
test_tool_output "wget" "wget --version | head -1"
test_tool "ping" "command -v ping"
test_tool "netstat" "command -v netstat"

echo ""
echo "=== Utilities ==="
test_tool_output "jq" "jq --version"
test_tool "vim" "command -v vim"
test_tool "neovim" "command -v nvim"
test_tool "nano" "command -v nano"
test_tool "tmux" "command -v tmux"
test_tool "fzf" "command -v fzf"
test_tool "bat" "command -v batcat"

echo ""
echo "=== Modern CLI Tools ==="
test_tool_output "yq" "yq --version"
test_tool_output "zoxide" "zoxide --version"
test_tool_output "tldr" "tldr --version"

echo ""
echo "=== GitHub CLI ==="
test_tool_output "gh" "gh --version"

echo ""
echo "=== Build Tools ==="
test_tool_output "gcc" "gcc --version | head -1"
test_tool_output "make" "make --version | head -1"
test_tool "build-essential" "dpkg -l | grep build-essential"
test_tool "pkg-config" "command -v pkg-config"

echo ""
echo "=== System Tools ==="
test_tool_output "zsh" "zsh --version"
test_tool "Oh-My-Zsh" "test -d ~/.oh-my-zsh"
test_tool "screen" "command -v screen"
test_tool "ssh" "command -v ssh"
test_tool "cron" "command -v cron"

echo ""
echo "=== User Configuration ==="
test_tool_output "Current user" "whoami"
test_tool_output "User ID" "id -u"
test_tool_output "Group ID" "id -g"

echo ""
echo "=========================================="
echo "Test Results"
echo "=========================================="
echo -e "Total: $test_count"
echo -e "${GREEN}Passed: $pass_count${NC}"
echo -e "${RED}Failed: $fail_count${NC}"
echo ""

if [ $fail_count -eq 0 ]; then
    echo -e "${GREEN}✓ All Layer 0 tests passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ Some tests failed${NC}"
    exit 1
fi
