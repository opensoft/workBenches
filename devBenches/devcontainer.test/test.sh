#!/bin/bash
# Layer 1a Test Script
# Tests devbench-base image for developer tools

set -e

echo "=========================================="
echo "Testing Layer 1a: DevBench Base"
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

echo "=== Python Development ==="
test_tool_output "Python" "python3 --version"
test_tool_output "pip" "pip --version"
test_tool "black" "command -v black"
test_tool "flake8" "command -v flake8"
test_tool "isort" "command -v isort"
test_tool "pylint" "command -v pylint"
test_tool "pytest" "command -v pytest"
test_tool "ipython" "command -v ipython"

echo ""
echo "=== Node.js Development ==="
test_tool_output "Node.js" "node --version"
test_tool_output "npm" "npm --version"
test_tool_output "yarn" "yarn --version"
test_tool "npm-global" "test -d ~/.npm-global"

echo ""
echo "=== Python Package Managers ==="
test_tool_output "uv" "uv --version"

echo ""
echo "=== AI CLI Tools ==="
test_tool "claude" "command -v claude"
test_tool "codex" "command -v codex"
test_tool "gemini" "command -v gemini"
test_tool_output "opencode" "opencode --version"

echo ""
echo "=== OpenCode Configuration ==="
test_tool "OpenCode config exists" "test -f ~/.config/opencode/opencode.json"
test_tool "oh-my-opencode plugin configured" "grep -q 'oh-my-opencode' ~/.config/opencode/opencode.json"
test_tool "opencode-openai-codex-auth plugin configured" "grep -q 'opencode-openai-codex-auth' ~/.config/opencode/opencode.json"

echo ""
echo "=== Shell Environment ==="
test_tool_output "zsh" "zsh --version"
test_tool "oh-my-zsh" "test -d ~/.oh-my-zsh"
test_tool "zsh-autosuggestions" "test -d ~/.oh-my-zsh/plugins/zsh-autosuggestions"
test_tool "zsh-syntax-highlighting" "test -d ~/.oh-my-zsh/plugins/zsh-syntax-highlighting"

echo ""
echo "=== PATH Configuration ==="
test_tool "~/.local/bin in PATH" "echo \$PATH | grep -q '.local/bin'"
test_tool "~/.npm-global/bin in PATH" "echo \$PATH | grep -q '.npm-global/bin'"
test_tool "~/.bun/bin in PATH" "echo \$PATH | grep -q '.bun/bin'"

echo ""
echo "=== Git Configuration ==="
test_tool "git credential helper" "git config --global credential.helper | grep -q 'gh'"

echo ""
echo "=========================================="
echo "Test Results"
echo "=========================================="
echo -e "Total: $test_count"
echo -e "${GREEN}Passed: $pass_count${NC}"
echo -e "${RED}Failed: $fail_count${NC}"
echo ""

if [ $fail_count -eq 0 ]; then
    echo -e "${GREEN}✓ All Layer 1a tests passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ Some tests failed${NC}"
    exit 1
fi
