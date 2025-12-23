#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

PASS_COUNT=0
FAIL_COUNT=0

check() {
    local name="$1"
    local command="$2"
    
    if eval "$command" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} $name"
        ((PASS_COUNT++))
    else
        echo -e "${RED}✗${NC} $name"
        ((FAIL_COUNT++))
    fi
}

echo "=========================================="
echo "Layer 1b Admin Bench Test Suite"
echo "=========================================="
echo

echo "Infrastructure as Code:"
check "Terraform" "terraform version"
check "OpenTofu" "tofu version"
check "Ansible" "ansible --version"

echo
echo "Kubernetes Tools:"
check "kubectl" "kubectl version --client"
check "Helm" "helm version"
check "k9s" "k9s version"
check "stern" "stern --version"

echo
echo "Cloud Provider CLIs:"
check "AWS CLI" "aws --version"
check "Azure CLI" "az version"
check "gcloud CLI" "gcloud version"

echo
echo "Monitoring & Utilities:"
check "promtool" "promtool --version"
check "yq" "yq --version"
check "lazydocker" "lazydocker --version"
check "jq" "jq --version"

echo
echo "User & Environment:"
check "User is brett" "[ \"\$(whoami)\" = 'brett' ]"
check "Home directory exists" "[ -d '/home/brett' ]"
check "Zsh shell" "[ -f '/bin/zsh' ]"
check "Workspace directory" "[ -d '/workspace' ]"

echo
echo "=========================================="
echo "Results: ${GREEN}${PASS_COUNT} passed${NC}, ${RED}${FAIL_COUNT} failed${NC}"
echo "=========================================="

exit $FAIL_COUNT
