#!/bin/bash

PROJECT_NAME=$1
TARGET_DIR=$2

# Validate project name is provided
if [ -z "$PROJECT_NAME" ]; then
    echo "Usage: ./new-flutter-project.sh <project-name> [target-directory]"
    echo "Examples:"
    echo "  ./new-flutter-project.sh myapp                    # Creates ~/projects/myapp"
    echo "  ./new-flutter-project.sh myapp ../../Dartwingers  # Creates ../../Dartwingers/myapp"
    echo ""
    echo "This script will:"
    echo "  1. Create a new Flutter project using 'flutter create'"
    echo "  2. Copy DevContainer and VS Code configurations"
    echo "  3. Replace PROJECT_NAME placeholders with your project name"
    echo "  4. Set up Docker configuration for shared ADB infrastructure"
    echo ""
    exit 1
fi

# If no target directory specified, default to ~/projects/<project-name>
if [ -z "$TARGET_DIR" ]; then
    TARGET_DIR="$HOME/projects"
    PROJECT_PATH="$TARGET_DIR/$PROJECT_NAME"
    
    # Check if project already exists
    if [ -d "$PROJECT_PATH" ]; then
        echo "❌ Error: Project already exists at $PROJECT_PATH"
        echo "Please choose a different project name or remove the existing project."
        exit 1
    fi
    
    # Create the target directory if it doesn't exist
    if [ ! -d "$TARGET_DIR" ]; then
        echo "📁 Creating projects directory: $TARGET_DIR"
        mkdir -p "$TARGET_DIR"
    fi
else
    PROJECT_PATH="$TARGET_DIR/$PROJECT_NAME"
    
    # Check if project already exists in specified directory
    if [ -d "$PROJECT_PATH" ]; then
        echo "❌ Error: Project already exists at $PROJECT_PATH"
        echo "Please choose a different project name or remove the existing project."
        exit 1
    fi
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/../templates/flutter-devcontainer-template"
CONFIG_SCRIPT="$SCRIPT_DIR/../../../scripts/workbench-config.sh"
METADATA_HELPER="$SCRIPT_DIR/../../../scripts/metadata-helper.sh"

# Load metadata helper functions
if [ -f "$METADATA_HELPER" ]; then
    source "$METADATA_HELPER"
else
    echo "⚠️  Warning: Metadata helper not found at $METADATA_HELPER"
    echo "   Project will be created without metadata."
fi

# Validate template directory exists
if [ ! -d "$TEMPLATE_DIR" ]; then
    echo "❌ Error: Template directory not found at $TEMPLATE_DIR"
    echo "Please ensure the flutter-devcontainer-template exists."
    exit 1
fi

# Validate target directory exists (only if explicitly provided)
if [ ! -z "$2" ] && [ ! -d "$TARGET_DIR" ]; then
    echo "❌ Error: Target directory $TARGET_DIR does not exist"
    echo "Please create the directory first or use a valid path."
    exit 1
fi

# Check if Flutter is available
if ! command -v flutter &> /dev/null; then
    echo "❌ Error: Flutter command not found"
    echo "Please install Flutter or run this script from within a Flutter container."
    exit 1
fi

echo "📦 Creating Flutter project: $PROJECT_NAME"
echo "📍 Project path: $PROJECT_PATH"

# Create Flutter project
cd "$TARGET_DIR"
if ! flutter create "$PROJECT_NAME"; then
    echo "❌ Error: Failed to create Flutter project"
    exit 1
fi

cd "$PROJECT_NAME"

# Copy template files
echo "📋 Copying DevContainer configuration..."
cp -r "$TEMPLATE_DIR/.devcontainer" .
cp -r "$TEMPLATE_DIR/.vscode" .
cp "$TEMPLATE_DIR/.gitignore" .

# Copy and setup environment files
echo "⚙️  Setting up environment configuration..."
# Create .env in .devcontainer folder from .env.example
cp "$TEMPLATE_DIR/.devcontainer/.env.example" .devcontainer/.env

# Note: Skip copying template README.md as DEVCONTAINER_README.md
# The devcontainer documentation is already available in .devcontainer/docs/

# Replace placeholders in .env
echo "🔧 Configuring project environment..."

# Get current user UID and GID for proper file permissions
CURRENT_UID=$(id -u)
CURRENT_GID=$(id -g)
CURRENT_USER=$(whoami)

# Prompt user for ADB infrastructure stack preference
echo ""
echo "🎯 ADB Infrastructure Stack Selection:"
echo ""
echo "  1) dartwingers - For Dartwingers organization projects"
echo "  2) flutter - For general Flutter development"
echo "  3) shared-adb-infrastructure - Default fallback"
echo "  4) auto-detect - Based on project path (previous behavior)"
echo ""

# Default based on project path for auto-detect
if [[ "$TARGET_DIR" == *"/dartwingers"* ]] || [[ "$TARGET_DIR" == *"/dartwingers/"* ]]; then
    DEFAULT_STACK="dartwingers"
elif [[ "$(basename "$TARGET_DIR")" == "dartwingers" ]]; then
    DEFAULT_STACK="dartwingers"
else
    DEFAULT_STACK="flutter"
fi

while true; do
    read -p "Choose ADB stack (1-4, or press Enter for auto-detect): " stack_choice
    
    # Default to auto-detect if no choice
    if [ -z "$stack_choice" ]; then
        stack_choice=4
    fi
    
    case $stack_choice in
        1)
            COMPOSE_PROJECT_NAME="dartwingers"
            ADB_INFRASTRUCTURE_PROJECT_NAME="dartwingers"
            echo "📦 Selected: dartwingers stack"
            break
            ;;
        2)
            COMPOSE_PROJECT_NAME="flutter"
            ADB_INFRASTRUCTURE_PROJECT_NAME="flutter"
            echo "📦 Selected: flutter stack"
            break
            ;;
        3)
            COMPOSE_PROJECT_NAME="flutter"
            ADB_INFRASTRUCTURE_PROJECT_NAME="shared-adb-infrastructure"
            echo "📦 Selected: shared-adb-infrastructure stack"
            break
            ;;
        4)
            COMPOSE_PROJECT_NAME="$DEFAULT_STACK"
            ADB_INFRASTRUCTURE_PROJECT_NAME="$DEFAULT_STACK"
            echo "📦 Auto-detected: $DEFAULT_STACK stack (based on path: $TARGET_DIR)"
            break
            ;;
        *)
            echo "❌ Invalid choice. Please enter 1, 2, 3, or 4."
            ;;
    esac
done

# Replace PROJECT_NAME, user settings, and stack naming in .devcontainer/.env
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    sed -i '' "s/PROJECT_NAME=myproject/PROJECT_NAME=$PROJECT_NAME/g" .devcontainer/.env
    sed -i '' "s/USER_UID=1000/USER_UID=$CURRENT_UID/g" .devcontainer/.env
    sed -i '' "s/USER_GID=1000/USER_GID=$CURRENT_GID/g" .devcontainer/.env
    sed -i '' "s/COMPOSE_PROJECT_NAME=flutter/COMPOSE_PROJECT_NAME=$COMPOSE_PROJECT_NAME/g" .devcontainer/.env
else
    # Linux
    sed -i "s/PROJECT_NAME=myproject/PROJECT_NAME=$PROJECT_NAME/g" .devcontainer/.env
    sed -i "s/USER_UID=1000/USER_UID=$CURRENT_UID/g" .devcontainer/.env
    sed -i "s/USER_GID=1000/USER_GID=$CURRENT_GID/g" .devcontainer/.env
    sed -i "s/COMPOSE_PROJECT_NAME=flutter/COMPOSE_PROJECT_NAME=$COMPOSE_PROJECT_NAME/g" .devcontainer/.env
fi

# Add ADB infrastructure project name to .env file
echo "" >> .devcontainer/.env
echo "# ADB Infrastructure Configuration" >> .devcontainer/.env
echo "ADB_INFRASTRUCTURE_PROJECT_NAME=$ADB_INFRASTRUCTURE_PROJECT_NAME" >> .devcontainer/.env

# Replace PROJECT_NAME placeholder in devcontainer.json
echo "🔧 Updating devcontainer display name..."
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    sed -i '' "s/PROJECT_NAME Flutter Dev/${PROJECT_NAME} Flutter Dev/g" .devcontainer/devcontainer.json
else
    # Linux
    sed -i "s/PROJECT_NAME Flutter Dev/${PROJECT_NAME} Flutter Dev/g" .devcontainer/devcontainer.json
fi

echo "✓ Environment configuration created in .devcontainer/.env"

# Note: devcontainer.json no longer needs PROJECT_NAME replacement since it uses .env

# Get dynamic infrastructure path using workbench configuration
if [ -f "$CONFIG_SCRIPT" ]; then
    INFRA_PATH=$("$CONFIG_SCRIPT" --get-infrastructure-path "$PROJECT_PATH" 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$INFRA_PATH" ]; then
        echo "⚠️  Warning: Could not determine infrastructure path from workbench config"
        echo "   Using fallback path: ../../infrastructure/mobile/android/adb/scripts/start-adb-if-needed.sh"
        INFRA_PATH="../../infrastructure/mobile/android/adb/scripts/start-adb-if-needed.sh"
    fi
else
    echo "⚠️  Warning: Workbench configuration not found"
    echo "   Run: $CONFIG_SCRIPT --setup"
    echo "   Using fallback path: ../../infrastructure/mobile/android/adb/scripts/start-adb-if-needed.sh"
    INFRA_PATH="../../infrastructure/mobile/android/adb/scripts/start-adb-if-needed.sh"
fi

# Validate infrastructure path exists (relative to project)
if [ ! -f "$INFRA_PATH" ]; then
    echo "⚠️  Warning: Infrastructure script not found at $INFRA_PATH"
    echo "   You may need to:"
    echo "   1. Run: $CONFIG_SCRIPT --setup"
    echo "   2. Ensure infrastructure is installed in your projects root"
    echo "   3. Manually adjust path in .devcontainer/devcontainer.json"
else
    echo "✅ Infrastructure validated: $INFRA_PATH"
fi

# Copy specKit from workBenches
echo "📋 Copying specKit for spec-driven development..."
WORKBENCHES_DIR="$(dirname "$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")")"
SPECKIT_SOURCE="$WORKBENCHES_DIR/specKit"

if [ -d "$SPECKIT_SOURCE" ]; then
    # Copy specKit contents (excluding .git)
    cp -r "$SPECKIT_SOURCE"/* .
    cp -r "$SPECKIT_SOURCE"/.[^.]* . 2>/dev/null || true  # Copy hidden files, ignore errors
    
    # Remove git-related files if they were copied
    rm -rf .git 2>/dev/null || true
    
    echo "✓ specKit copied successfully"
else
    echo "⚠️  Warning: specKit not found at $SPECKIT_SOURCE"
    echo "   Run setup-workbenches.sh to install specKit"
fi

# Create .gitignore additions for Docker
echo "" >> .gitignore
echo "# DevContainer" >> .gitignore
echo ".devcontainer/.env" >> .gitignore
echo ".devcontainer/docker-compose.override.yml" >> .gitignore

# Initialize project metadata
echo "📊 Initializing project metadata..."
if command -v initialize_project_metadata >/dev/null 2>&1; then
    if initialize_project_metadata "$PROJECT_PATH" "flutterBench" "devBenches"; then
        echo "✅ Project metadata initialized successfully"
    else
        echo "⚠️  Warning: Failed to initialize project metadata"
    fi
else
    echo "⚠️  Warning: Metadata helper functions not available"
    echo "   Creating basic .workbench file..."
    cat > .workbench <<EOF
# WorkBench Project Metadata
bench_category=devBenches
bench_type=flutterBench
created_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
created_by_user=$(whoami)
EOF
    echo "✅ Basic metadata file created"
fi

echo ""
echo "✅ Project created successfully: $PROJECT_PATH"
echo ""
echo "📝 Next steps:"
echo "   1. cd $PROJECT_PATH"
echo "   2. code ."
echo "   3. When prompted, click 'Reopen in Container'"
echo "   4. Wait for container build (first time: ~5-10 minutes)"
echo "   5. Container will automatically:"
echo "      - Start shared ADB infrastructure"
echo "      - Run 'flutter pub get'"
echo "      - Run 'flutter doctor'"
echo "      - Check ADB device connection"
echo ""
echo "🔧 Configuration summary:"
echo "   - Container name: ${PROJECT_NAME}_app"
echo "   - Stack name: $COMPOSE_PROJECT_NAME"
echo "   - ADB infrastructure stack: $ADB_INFRASTRUCTURE_PROJECT_NAME"
echo "   - Network: dartnet (shared)"
echo "   - ADB server: shared-adb-server:5037"
echo "   - Infrastructure path: $INFRA_PATH"
echo "   - User UID/GID: $CURRENT_UID:$CURRENT_GID"
echo "   - Environment file: .devcontainer/.env (customized from .devcontainer/.env.example)"
echo ""
echo "⚙️  Environment configuration:"
echo "   - PROJECT_NAME=$PROJECT_NAME (in .devcontainer/.env)"
echo "   - COMPOSE_PROJECT_NAME=$COMPOSE_PROJECT_NAME (in .devcontainer/.env)"
echo "   - ADB_INFRASTRUCTURE_PROJECT_NAME=$ADB_INFRASTRUCTURE_PROJECT_NAME (in .devcontainer/.env)"
echo "   - USER_UID=$CURRENT_UID (in .devcontainer/.env)"
echo "   - USER_GID=$CURRENT_GID (in .devcontainer/.env)"
echo "   - FLUTTER_VERSION=3.24.0 (in .devcontainer/.env)"
echo ""
echo "📝 Quick start:"
echo "   1. Review and customize .devcontainer/.env file if needed"
echo "   2. cd $PROJECT_PATH"
echo "   3. code ."
echo "   4. When prompted, click 'Reopen in Container'"
echo ""
echo "📚 For detailed information, see: .devcontainer/docs/DEVCONTAINER_README.md"
echo "📚 For environment variables, see: .devcontainer/.env.example"
echo "📚 For spec-driven development, see: README.md and spec-driven.md"
echo ""
echo "🎯 Happy Flutter Development with Spec-Driven Development!"
