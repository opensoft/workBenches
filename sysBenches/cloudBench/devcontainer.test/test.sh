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
echo "Layer 2 Cloud Bench Test Suite"
echo "=========================================="
echo

echo "Infrastructure as Code:"
check "Terragrunt" "terragrunt --version"
check "Pulumi" "pulumi version"

echo
echo "Cost & FinOps:"
check "Infracost" "infracost --version"

echo
echo "Security & Compliance:"
check "Trivy" "trivy --version"
check "Vault" "vault --version"

echo
echo "Cluster Management:"
check "Helm" "helm version"
check "Velero" "velero version --client-only"

echo
echo "Observability & Access:"
check "Teleport tsh" "tsh version"
check "Teleport tctl" "tctl version"

echo
echo "Layer 1b Tools (from adminbench-base):"
check "Terraform" "terraform version"
check "kubectl" "kubectl version --client"
check "AWS CLI" "aws --version"
check "Azure CLI" "az version"
check "gcloud" "gcloud version"

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
