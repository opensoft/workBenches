#!/bin/bash

PROJECT_NAME=$1
TARGET_DIR=$2

# Validate project name is provided
if [ -z "$PROJECT_NAME" ]; then
    echo "Usage: ./new-dartwing-project.sh <project-name> [target-directory]"
    echo "Examples:"
    echo "  ./new-dartwing-project.sh myapp                    # Creates ~/projects/dartwingers/myapp"
    echo "  ./new-dartwing-project.sh myapp ~/other/path       # Creates ~/other/path/myapp"
    echo ""
    echo "This script is a wrapper around new-flutter-project.sh with a default"
    echo "target directory of ~/projects/dartwingers/"
    echo ""
    exit 1
fi

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# If no target directory specified, default to ~/projects/dartwingers
if [ -z "$TARGET_DIR" ]; then
    TARGET_DIR="$HOME/projects/dartwingers"
fi

# Call the original new-flutter-project.sh script with the arguments
echo "🎯 Creating Dartwing project: $PROJECT_NAME"
echo "📍 Target directory: $TARGET_DIR"
echo ""

# Call the base Flutter project creation
"$SCRIPT_DIR/new-flutter-project.sh" "$PROJECT_NAME" "$TARGET_DIR"

# Check if the Flutter project creation was successful
if [ $? -ne 0 ]; then
    echo "❌ Error: Flutter project creation failed"
    exit 1
fi

# Post-process for Dartwingers: Add docker-compose.override.yml for .NET service
PROJECT_PATH="$TARGET_DIR/$PROJECT_NAME"
TEMPLATE_DIR="$SCRIPT_DIR/../template"
METADATA_HELPER="$SCRIPT_DIR/../../../scripts/metadata-helper.sh"

echo "🔧 Configuring Dartwingers-specific setup..."
echo "   - Adding .NET service container via docker-compose.override.yml"
echo "   - Base Flutter container remains in docker-compose.yml"

# Load metadata helper if available
if [ -f "$METADATA_HELPER" ]; then
    source "$METADATA_HELPER"
fi

# Add the docker-compose.override.yml for Dartwingers
cp "$TEMPLATE_DIR/.devcontainer/docker-compose.override.yml" "$PROJECT_PATH/.devcontainer/docker-compose.override.yml"

# Update metadata to reflect Dartwing-specific configuration
echo "📊 Updating project metadata for Dartwing configuration..."
if command -v update_project_metadata >/dev/null 2>&1; then
    cd "$PROJECT_PATH"
    
    # Update metadata to indicate this is a Dartwing variant
    if [ -f ".workbench-metadata.json" ] && command -v jq >/dev/null 2>&1; then
        # Add Dartwing-specific metadata
        local temp_file=$(mktemp)
        local updated_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        
        jq --arg date "$updated_date" \
           '.project_info.project_variant = "dartwing" |
            .project_info.multi_service = true |
            .project_info.services = ["flutter_app", "dotnet_service"] |
            .dartwing_config = {
              "has_dotnet_service": true,
              "docker_compose_override": true,
              "service_communication": "http://service:5000",
              "exposed_ports": ["5000", "8080"]
            } |
            .workbench_metadata.last_updated = $date' \
           ".workbench-metadata.json" > "$temp_file" && mv "$temp_file" ".workbench-metadata.json"
        
        echo "✅ Dartwing metadata updated successfully"
    else
        # Update simple .workbench file
        if [ -f ".workbench" ]; then
            echo "project_variant=dartwing" >> .workbench
            echo "multi_service=true" >> .workbench
            echo "has_dotnet_service=true" >> .workbench
            echo "✅ Basic Dartwing metadata updated"
        fi
    fi
else
    echo "⚠️  Warning: Could not update metadata - helper functions not available"
fi

echo ""
echo "✅ Dartwingers project setup complete!"
echo ""
echo "📦 Your project includes:"
echo "   - Flutter app container: ${PROJECT_NAME}_app"
echo "   - .NET service container: ${PROJECT_NAME}_service"
echo "   - Stack name: dartwingers"
echo "   - Shared networking and ADB infrastructure"
echo ""
echo "🚀 Next steps:"
echo "   1. cd $PROJECT_PATH"
echo "   2. code ."
echo "   3. When prompted, click 'Reopen in Container'"
echo "   4. Both containers will start automatically"
echo ""
echo "🔗 Service connectivity:"
echo "   - Flutter app can reach .NET service at: http://service:5000"
echo "   - .NET service exposed on host port: 5000"
echo "   - Flutter hot reload on host port: 8080"
echo ""
echo "📚 For spec-driven development: see README.md and spec-driven.md"
echo "📚 Use /constitution, /specify, /plan, /tasks, /implement commands"
echo ""
echo "🎯 Happy Dartwing Development with Spec-Driven Development!"
