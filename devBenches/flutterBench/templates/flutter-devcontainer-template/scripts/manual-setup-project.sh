#!/bin/bash
# ====================================
# Flutter DevContainer Manual Setup Validation
# ====================================
# This script validates and sets up the .env file for Flutter DevContainer projects
# when using manual template setup (not automated new-flutter-project.sh)

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

echo "🔍 Flutter DevContainer Environment Setup"
echo "========================================"

# ====================================
# Step 1: Check if .env file exists
# ====================================
if [ ! -f .env ]; then
    echo "⚠️  .env file not found!"
    
    if [ -f .env.example ]; then
        echo "📋 Creating .env from .env.example..."
        cp .env.example .env
        echo "✅ Created .env file"
        echo ""
        echo "📝 Please edit .env and set the following variables:"
        echo "   - PROJECT_NAME (currently: myproject)"
        echo "   - USER_UID (currently: 1000)"  
        echo "   - USER_GID (currently: 1000)"
        echo ""
        echo "💡 Tip: Run 'id' to check your current UID and GID"
        echo "💡 Tip: Run this script again after editing .env"
        exit 1
    else
        echo "❌ Error: Neither .env nor .env.example found!"
        echo "This script should be run from a Flutter DevContainer project directory"
        exit 1
    fi
fi

echo "✅ Found .env file"

# ====================================
# Step 2: Validate required variables
# ====================================
echo "🔍 Validating environment variables..."

REQUIRED_VARS=(
    "PROJECT_NAME"
    "USER_NAME" 
    "USER_UID"
    "USER_GID"
    "FLUTTER_VERSION"
)

MISSING=()
WARNINGS=()

for VAR in "${REQUIRED_VARS[@]}"; do
    if ! grep -q "^${VAR}=" .env 2>/dev/null; then
        MISSING+=("$VAR")
    else
        VALUE=$(grep "^${VAR}=" .env | cut -d'=' -f2)
        if [ -z "$VALUE" ] || [ "$VALUE" = "myproject" ]; then
            if [ "$VAR" = "PROJECT_NAME" ] && [ "$VALUE" = "myproject" ]; then
                WARNINGS+=("$VAR is still set to default value: $VALUE")
            elif [ -z "$VALUE" ]; then
                MISSING+=("$VAR (empty value)")
            fi
        fi
    fi
done

# ====================================
# Step 3: Report validation results
# ====================================
if [ ${#MISSING[@]} -gt 0 ]; then
    echo "❌ Missing or empty required variables in .env:"
    printf '   - %s\n' "${MISSING[@]}"
    echo ""
    echo "📝 Please edit .env and set these variables"
    exit 1
fi

if [ ${#WARNINGS[@]} -gt 0 ]; then
    echo "⚠️  Warnings:"
    printf '   - %s\n' "${WARNINGS[@]}"
    echo ""
fi

echo "✅ All required variables found in .env"

# ====================================
# Step 4: Validate specific values
# ====================================
echo "🔍 Validating variable values..."

# Get values from .env
PROJECT_NAME=$(grep '^PROJECT_NAME=' .env | cut -d'=' -f2)
USER_NAME=$(grep '^USER_NAME=' .env | cut -d'=' -f2)
USER_UID=$(grep '^USER_UID=' .env | cut -d'=' -f2)
USER_GID=$(grep '^USER_GID=' .env | cut -d'=' -f2)
FLUTTER_VERSION=$(grep '^FLUTTER_VERSION=' .env | cut -d'=' -f2)

# Validate PROJECT_NAME (no spaces, no special chars)
if [[ ! "$PROJECT_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "❌ PROJECT_NAME contains invalid characters"
    echo "   Current: $PROJECT_NAME"
    echo "   Must contain only letters, numbers, underscores, and hyphens"
    exit 1
fi

# Validate USER_UID and USER_GID are numbers
if ! [[ "$USER_UID" =~ ^[0-9]+$ ]]; then
    echo "❌ USER_UID must be a number"
    echo "   Current: $USER_UID"
    exit 1
fi

if ! [[ "$USER_GID" =~ ^[0-9]+$ ]]; then
    echo "❌ USER_GID must be a number"  
    echo "   Current: $USER_GID"
    exit 1
fi

# Check if UID/GID match current user (recommended)
CURRENT_UID=$(id -u)
CURRENT_GID=$(id -g)

if [ "$USER_UID" != "$CURRENT_UID" ] || [ "$USER_GID" != "$CURRENT_GID" ]; then
    echo "⚠️  User ID mismatch detected:"
    echo "   .env UID:GID = $USER_UID:$USER_GID"
    echo "   Your UID:GID = $CURRENT_UID:$CURRENT_GID" 
    echo ""
    echo "💡 For best file permissions, consider updating .env:"
    echo "   USER_UID=$CURRENT_UID"
    echo "   USER_GID=$CURRENT_GID"
    echo ""
fi

echo "✅ Variable values validated"

# ====================================
# Step 5: Check infrastructure path
# ====================================
echo "🔍 Validating infrastructure path..."

INFRA_PATH="../../../infrastructure/mobile/android/adb/scripts/start-adb-if-needed.sh"
if [ -f "$INFRA_PATH" ]; then
    echo "✅ Infrastructure script found: $INFRA_PATH"
else
    echo "⚠️  Infrastructure script not found: $INFRA_PATH"
    echo "   This may be normal if infrastructure is not set up yet"
    echo "   or if project is at a different directory depth"
fi

# ====================================
# Step 6: Check Docker requirements
# ====================================
echo "🔍 Checking Docker environment..."

if ! command -v docker &> /dev/null; then
    echo "❌ Docker not found"
    echo "   Docker is required for DevContainer development"
    exit 1
fi

if ! docker info &> /dev/null; then
    echo "❌ Docker daemon not running"
    echo "   Please start Docker Desktop or Docker service"
    exit 1
fi

if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    echo "❌ Docker Compose not found"
    echo "   Docker Compose is required for this project"
    exit 1
fi

echo "✅ Docker environment ready"

# ====================================
# Step 7: Test configuration
# ====================================
echo "🔍 Testing Docker Compose configuration..."

if docker-compose config &> /dev/null; then
    echo "✅ Docker Compose configuration valid"
else
    echo "❌ Docker Compose configuration has errors"
    echo ""
    echo "🔧 Debug information:"
    docker-compose config
    exit 1
fi

# ====================================
# Summary
# ====================================
echo ""
echo "🎉 Environment validation complete!"
echo ""
echo "📋 Configuration Summary:"
echo "   Project Name: $PROJECT_NAME"
echo "   User: $USER_NAME ($USER_UID:$USER_GID)"
echo "   Flutter Version: $FLUTTER_VERSION"
echo "   Container Name: $PROJECT_NAME-dev"
echo ""
echo "✅ Your Flutter DevContainer environment is ready!"
echo ""
echo "🚀 Next steps:"
echo "   1. Open this project in VS Code: code ."
echo "   2. Click 'Reopen in Container' when prompted"
echo "   3. Wait for container to build and start"
echo "   4. Start coding!"
echo ""
echo "🔧 If you need to change configuration:"
echo "   1. Edit .env file"
echo "   2. Run this script again to validate"
echo "   3. Rebuild container: docker-compose build --no-cache"
echo ""