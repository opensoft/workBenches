#!/bin/bash

# ====================================
# Quick Ready Status Check
# ====================================
# Brief status check when attaching to the container
# Used by devcontainer.json postAttachCommand

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}✅ Ready to develop!${NC}"
echo ""

# Quick project status
if [ -f "pubspec.yaml" ]; then
    PROJECT_NAME=$(grep "^name:" pubspec.yaml | cut -d: -f2 | xargs || echo "Flutter Project")
    echo -e "${BLUE}📱 Project:${NC} $PROJECT_NAME"
else
    echo -e "${YELLOW}💡 No Flutter project detected - run 'flutter create <app_name>' to get started${NC}"
fi

# Quick device check
if command -v adb >/dev/null 2>&1; then
    DEVICE_COUNT=$(adb devices 2>/dev/null | grep -c "device$" || echo "0")
    if [ "$DEVICE_COUNT" -gt 0 ]; then
        echo -e "${BLUE}📱 Connected devices:${NC} $DEVICE_COUNT"
        adb devices | grep "device$" | sed 's/^/  • /'
    else
        echo -e "${YELLOW}📱 No devices connected${NC} - connect a device or start an emulator"
    fi
else
    echo -e "${YELLOW}📱 ADB not available${NC}"
fi

# Quick setup status
if [ -f "/tmp/flutter-setup-success.log" ]; then
    echo -e "${GREEN}🎯 Setup:${NC} Completed successfully"
elif [ -f "/tmp/flutter-setup-errors.log" ]; then
    echo -e "${YELLOW}🎯 Setup:${NC} Had issues (check: cat /tmp/flutter-setup.log)"
else
    echo -e "${BLUE}🎯 Setup:${NC} Run on container creation"
fi

echo ""
echo -e "${BLUE}💡 Quick commands:${NC}"
echo "  • flutter run          - Start development"
echo "  • flutter doctor        - Check environment"
echo "  • ./.devcontainer/scripts/flutter-status.sh - Full status"
echo "  • ./.devcontainer/scripts/version-check.sh - Check template versions"

if [ -f "docker-compose.override.yml" ]; then
    echo "  • docker-compose up -d service - Start .NET service"
fi
echo ""