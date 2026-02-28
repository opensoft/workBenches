#!/bin/bash

# Check installed tool versions across workBench container layers
# Compares installed versions against upstream latest
# Usage: ./check-versions.sh [--layer 0|1a|1b|1c|all] [--json]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
USERNAME="${USERNAME:-$(whoami)}"
LAYER="all"
JSON_OUTPUT=false
MANIFEST_FILE="$REPO_DIR/config/version-manifest.json"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --layer) LAYER="$2"; shift 2 ;;
        --json) JSON_OUTPUT=true; shift ;;
        --user) USERNAME="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# JSON accumulator
declare -a JSON_ENTRIES=()

# ========================================
# HELPERS
# ========================================

# Get latest npm package version
npm_latest() {
    local pkg="$1"
    curl -s "https://registry.npmjs.org/$pkg/latest" 2>/dev/null | jq -r '.version // empty' 2>/dev/null || echo "unknown"
}

# Get latest GitHub release version (strips leading 'v')
github_latest() {
    local repo="$1"
    curl -s "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null | jq -r '.tag_name // empty' 2>/dev/null | sed 's/^v//'
}

# Get version from inside a container
container_version() {
    local image="$1"
    local cmd="$2"
    docker run --rm --entrypoint="" "$image" sh -c "$cmd" 2>/dev/null | head -1 || echo "not installed"
}

# Extract just the version number from a version string
extract_version() {
    echo "$1" | grep -oE '[0-9]+\.[0-9]+[0-9.]*' | head -1
}

# Compare and print versions
report_tool() {
    local tool="$1"
    local installed_raw="$2"
    local latest_raw="$3"
    local layer="$4"

    local installed=$(extract_version "$installed_raw")
    local latest=$(extract_version "$latest_raw")

    if [ -z "$installed" ] || [ "$installed" = "not installed" ]; then
        installed="n/a"
    fi
    if [ -z "$latest" ]; then
        latest="unknown"
    fi

    local status="✓"
    local color="$GREEN"
    if [ "$installed" = "n/a" ]; then
        status="✗"
        color="$RED"
    elif [ "$latest" != "unknown" ] && [ "$installed" != "$latest" ]; then
        status="⬆"
        color="$YELLOW"
    fi

    if [ "$JSON_OUTPUT" = false ]; then
        printf "  ${color}%-3s${NC} %-25s %-18s %-18s\n" "$status" "$tool" "$installed" "$latest"
    fi

    # Accumulate JSON
    JSON_ENTRIES+=("{\"tool\":\"$tool\",\"layer\":\"$layer\",\"installed\":\"$installed\",\"latest\":\"$latest\",\"status\":\"$([ "$status" = "✓" ] && echo "current" || ([ "$status" = "⬆" ] && echo "outdated" || echo "missing"))\"}")
}

print_layer_header() {
    local name="$1"
    local image="$2"
    if [ "$JSON_OUTPUT" = false ]; then
        echo ""
        echo -e "${BOLD}${CYAN}═══ $name ($image) ═══${NC}"
        printf "  %-3s %-25s %-18s %-18s\n" "" "Tool" "Installed" "Latest"
        printf "  %-3s %-25s %-18s %-18s\n" "" "----" "---------" "------"
    fi
}

# ========================================
# LAYER 0: workbench-base
# ========================================

check_layer0() {
    local image="workbench-base:$USERNAME"

    if ! docker image inspect "$image" >/dev/null 2>&1; then
        echo "  Layer 0 image ($image) not found — skipping"
        return
    fi

    print_layer_header "Layer 0: System Base" "$image"

    report_tool "git" \
        "$(container_version "$image" "git --version")" \
        "$(github_latest "git/git")" \
        "0"

    report_tool "gh" \
        "$(container_version "$image" "gh --version")" \
        "$(github_latest "cli/cli")" \
        "0"

    report_tool "vim" \
        "$(container_version "$image" "vim --version | head -1")" \
        "$(github_latest "vim/vim")" \
        "0"

    report_tool "neovim" \
        "$(container_version "$image" "nvim --version | head -1")" \
        "$(github_latest "neovim/neovim")" \
        "0"

    report_tool "yq" \
        "$(container_version "$image" "yq --version")" \
        "$(github_latest "mikefarah/yq")" \
        "0"

    report_tool "zoxide" \
        "$(container_version "$image" "zoxide --version")" \
        "$(github_latest "ajeetdsouza/zoxide")" \
        "0"

    report_tool "uv" \
        "$(container_version "$image" "\$HOME/.local/bin/uv --version 2>/dev/null || uv --version")" \
        "$(github_latest "astral-sh/uv")" \
        "0"

    report_tool "spec-kit" \
        "$(container_version "$image" "\$HOME/.local/bin/uv tool list 2>/dev/null | grep specify-cli | head -1 || echo n/a")" \
        "$(github_latest "github/spec-kit")" \
        "0"

    report_tool "fzf" \
        "$(container_version "$image" "fzf --version")" \
        "$(github_latest "junegunn/fzf")" \
        "0"

    report_tool "jq" \
        "$(container_version "$image" "jq --version")" \
        "$(github_latest "jqlang/jq")" \
        "0"

    report_tool "tldr" \
        "$(container_version "$image" "tldr --version 2>/dev/null || echo n/a")" \
        "$(npm_latest "tldr")" \
        "0"

    # AI CLIs (installed in Layer 0 for all benches)
    report_tool "claude-code" \
        "$(container_version "$image" "\$HOME/.local/bin/claude --version 2>/dev/null || \$HOME/.npm-global/bin/claude --version 2>/dev/null || claude --version 2>/dev/null || echo n/a")" \
        "$(npm_latest "@anthropic-ai/claude-code")" \
        "0"

    report_tool "codex" \
        "$(container_version "$image" "\$HOME/.npm-global/bin/codex --version 2>/dev/null || codex --version 2>/dev/null || echo n/a")" \
        "$(npm_latest "@openai/codex")" \
        "0"

    report_tool "gemini" \
        "$(container_version "$image" "\$HOME/.npm-global/bin/gemini --version 2>/dev/null || gemini --version 2>/dev/null || echo n/a")" \
        "$(npm_latest "@google/gemini-cli")" \
        "0"

    report_tool "copilot" \
        "$(container_version "$image" "\$HOME/.npm-global/bin/github-copilot-cli --version 2>/dev/null || echo n/a")" \
        "$(npm_latest "@githubnext/github-copilot-cli")" \
        "0"

    report_tool "openspec" \
        "$(container_version "$image" "\$HOME/.npm-global/bin/openspec --version 2>/dev/null || echo n/a")" \
        "$(npm_latest "@fission-ai/openspec")" \
        "0"

    report_tool "letta-code" \
        "$(container_version "$image" "\$HOME/.npm-global/bin/letta --version 2>/dev/null || echo n/a")" \
        "$(npm_latest "@letta-ai/letta-code")" \
        "0"
}

# ========================================
# LAYER 1a: devbench-base
# ========================================

check_layer1a() {
    local image="devbench-base:$USERNAME"

    if ! docker image inspect "$image" >/dev/null 2>&1; then
        echo "  Layer 1a image ($image) not found — skipping"
        return
    fi

    print_layer_header "Layer 1a: Developer Base" "$image"

    # AI CLIs are inherited from Layer 0, only check dev-specific tools here

    report_tool "python3" \
        "$(container_version "$image" "python3 --version")" \
        "$(github_latest "python/cpython")" \
        "1a"

    report_tool "node" \
        "$(container_version "$image" "node --version")" \
        "$(curl -s https://nodejs.org/dist/index.json 2>/dev/null | jq -r '[.[] | select(.lts != false)][0].version // empty' 2>/dev/null)" \
        "1a"

    report_tool "npm" \
        "$(container_version "$image" "npm --version")" \
        "$(npm_latest "npm")" \
        "1a"

    report_tool "bun" \
        "$(container_version "$image" "\$HOME/.bun/bin/bun --version 2>/dev/null || bun --version")" \
        "$(github_latest "oven-sh/bun")" \
        "1a"

    report_tool "yarn" \
        "$(container_version "$image" "yarn --version 2>/dev/null || echo n/a")" \
        "$(npm_latest "yarn")" \
        "1a"
}

# ========================================
# LAYER 1b: adminbench-base
# ========================================

check_layer1b() {
    local image="adminbench-base:$USERNAME"

    if ! docker image inspect "$image" >/dev/null 2>&1; then
        echo "  Layer 1b image ($image) not found — skipping"
        return
    fi

    print_layer_header "Layer 1b: Admin/DevOps Base" "$image"

    report_tool "terraform" \
        "$(container_version "$image" "terraform version | head -1")" \
        "$(github_latest "hashicorp/terraform")" \
        "1b"

    report_tool "tofu" \
        "$(container_version "$image" "tofu version | head -1")" \
        "$(github_latest "opentofu/opentofu")" \
        "1b"

    report_tool "kubectl" \
        "$(container_version "$image" "kubectl version --client 2>/dev/null | head -1")" \
        "$(curl -sL https://dl.k8s.io/release/stable.txt 2>/dev/null | sed 's/^v//')" \
        "1b"

    report_tool "helm" \
        "$(container_version "$image" "helm version --short")" \
        "$(github_latest "helm/helm")" \
        "1b"

    report_tool "k9s" \
        "$(container_version "$image" "k9s version --short 2>/dev/null || k9s version | head -1")" \
        "$(github_latest "derailed/k9s")" \
        "1b"

    report_tool "stern" \
        "$(container_version "$image" "stern --version")" \
        "$(github_latest "stern/stern")" \
        "1b"

    report_tool "aws-cli" \
        "$(container_version "$image" "aws --version")" \
        "$(github_latest "aws/aws-cli")" \
        "1b"

    report_tool "az" \
        "$(container_version "$image" "az version 2>/dev/null | jq -r '.\"azure-cli\"' 2>/dev/null || echo n/a")" \
        "$(github_latest "Azure/azure-cli")" \
        "1b"

    report_tool "gcloud" \
        "$(container_version "$image" "gcloud version 2>/dev/null | head -1")" \
        "unknown" \
        "1b"

    report_tool "ansible" \
        "$(container_version "$image" "ansible --version | head -1")" \
        "$(pip index versions ansible 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo unknown)" \
        "1b"

    report_tool "promtool" \
        "$(container_version "$image" "promtool --version 2>&1 | head -1")" \
        "$(github_latest "prometheus/prometheus")" \
        "1b"

    report_tool "lazydocker" \
        "$(container_version "$image" "lazydocker --version")" \
        "$(github_latest "jesseduffield/lazydocker")" \
        "1b"
}

# ========================================
# LAYER 1c: biobench-base
# ========================================

check_layer1c() {
    local image="biobench-base:$USERNAME"

    if ! docker image inspect "$image" >/dev/null 2>&1; then
        echo "  Layer 1c image ($image) not found — skipping"
        return
    fi

    print_layer_header "Layer 1c: Bio Base" "$image"

    report_tool "conda" \
        "$(container_version "$image" "conda --version")" \
        "$(github_latest "conda/conda")" \
        "1c"
}

# ========================================
# MAIN
# ========================================

echo "=========================================="
echo "workBenches Version Check"
echo "=========================================="
echo "User: $USERNAME"
echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"

case "$LAYER" in
    0)   check_layer0 ;;
    1a)  check_layer1a ;;
    1b)  check_layer1b ;;
    1c)  check_layer1c ;;
    all)
        check_layer0
        check_layer1a
        check_layer1b
        check_layer1c
        ;;
    *)
        echo "Unknown layer: $LAYER"
        echo "Usage: $0 [--layer 0|1a|1b|1c|all]"
        exit 1
        ;;
esac

echo ""

# Count outdated
outdated_count=0
for entry in "${JSON_ENTRIES[@]}"; do
    if echo "$entry" | grep -q '"status":"outdated"'; then
        outdated_count=$((outdated_count + 1))
    fi
done

if [ "$JSON_OUTPUT" = false ]; then
    echo -e "${BOLD}Summary:${NC} ${#JSON_ENTRIES[@]} tools checked, ${outdated_count} outdated"
    if [ "$outdated_count" -gt 0 ]; then
        echo -e "${YELLOW}Run scripts/update-and-rebuild.sh to update outdated layers${NC}"
    fi
fi

# Write manifest
echo "{" > "$MANIFEST_FILE"
echo "  \"checked_at\": \"$(date -u '+%Y-%m-%dT%H:%M:%SZ')\"," >> "$MANIFEST_FILE"
echo "  \"user\": \"$USERNAME\"," >> "$MANIFEST_FILE"
echo "  \"tools\": [" >> "$MANIFEST_FILE"
for i in "${!JSON_ENTRIES[@]}"; do
    if [ $i -lt $((${#JSON_ENTRIES[@]} - 1)) ]; then
        echo "    ${JSON_ENTRIES[$i]}," >> "$MANIFEST_FILE"
    else
        echo "    ${JSON_ENTRIES[$i]}" >> "$MANIFEST_FILE"
    fi
done
echo "  ]" >> "$MANIFEST_FILE"
echo "}" >> "$MANIFEST_FILE"

if [ "$JSON_OUTPUT" = true ]; then
    cat "$MANIFEST_FILE"
fi

echo ""
echo "Version manifest written to config/version-manifest.json"
