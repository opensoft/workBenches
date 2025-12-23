#!/bin/bash
# Apply docker-compose.override.yml to all bench devcontainers
# Version: 1.0.0

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKBENCHES_ROOT="$(cd "$SHARED_DIR/.." && pwd)"
OVERRIDE_FILE="$SHARED_DIR/docker-compose.override.yml"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════${NC}"
echo -e "${BLUE}  Apply Override to All Benches${NC}"
echo -e "${BLUE}═══════════════════════════════════════════${NC}"
echo ""

if [ ! -f "$OVERRIDE_FILE" ]; then
    echo -e "${RED}✗ Override file not found: $OVERRIDE_FILE${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} Found override file: $OVERRIDE_FILE"
echo ""

# Find all bench devcontainer directories
BENCH_DIRS=(
    "$WORKBENCHES_ROOT/devBenches/frappeBench/devcontainer.example"
    "$WORKBENCHES_ROOT/devBenches/dotNetBench/.devcontainer"
    "$WORKBENCHES_ROOT/devBenches/flutterBench/.devcontainer"
    "$WORKBENCHES_ROOT/devBenches/cppBench/.devcontainer"
)

echo "Found bench directories:"
for dir in "${BENCH_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        echo -e "  ${GREEN}✓${NC} $(basename $(dirname $dir))"
    else
        echo -e "  ${YELLOW}⚠${NC} $(basename $(dirname $dir)) (not found)"
    fi
done
echo ""

read -p "Apply override to all found benches? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "Applying override files..."
echo ""

for bench_dir in "${BENCH_DIRS[@]}"; do
    if [ ! -d "$bench_dir" ]; then
        continue
    fi
    
    bench_name=$(basename $(dirname $bench_dir))
    target="$bench_dir/docker-compose.override.yml"
    
    echo -ne "  Processing ${bench_name}... "
    
    # Create backup if file exists
    if [ -f "$target" ]; then
        cp "$target" "${target}.backup.$(date +%Y%m%d-%H%M%S)"
        echo -ne "(backed up) "
    fi
    
    # Copy override file
    cp "$OVERRIDE_FILE" "$target"
    
    echo -e "${GREEN}✓${NC}"
done

echo ""
echo -e "${GREEN}✓ Override files applied!${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Edit each bench's override file to match service names"
echo "2. Test with: cd <bench>/.devcontainer && docker-compose config"
echo "3. Rebuild containers: docker-compose up -d --build"
echo ""
