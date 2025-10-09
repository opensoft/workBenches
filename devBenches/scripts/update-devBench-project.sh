#!/bin/bash

# ====================================
# DevBench Project Type Detection & Update Script
# ====================================
# Uses AI analysis to determine specific devBench project types and delegates to appropriate bench-specific update scripts
#
# Usage: ./update-devBench-project.sh <project-path>

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVBENCHES_DIR="$(dirname "$SCRIPT_DIR")"
WORKBENCHES_ROOT="$(dirname "$DEVBENCHES_DIR")"
CONFIG_FILE="$WORKBENCHES_ROOT/config/bench-config.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Project path (required)
PROJECT_PATH="${1:-}"
if [ -z "$PROJECT_PATH" ]; then
    echo -e "${RED}Error: Project path is required${NC}"
    echo "Usage: $0 <project-path>"
    exit 1
fi

PROJECT_NAME=$(basename "$PROJECT_PATH")

# ====================================
# Utility Functions
# ====================================

log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

log_section() {
    echo ""
    echo -e "${CYAN}🔄 $1${NC}"
    echo "$(printf '=%.0s' {1..50})"
}

# ====================================
# Metadata Detection Functions
# ====================================

# Check for workbenches metadata in project
detect_bench_metadata() {
    local project_path="$1"
    log_section "🔍 Checking for Bench Metadata"
    
    # Look for common metadata files
    local metadata_files=(
        ".workbench"
        ".devbench"
        ".bench-info"
        ".workbench-metadata.json"
        ".devcontainer/workbench-metadata.json"
    )
    
    for metadata_file in "${metadata_files[@]}"; do
        local full_path="$project_path/$metadata_file"
        if [ -f "$full_path" ]; then
            log_success "Found metadata file: $metadata_file"
            
            # Try to extract bench type from metadata
            if [[ "$metadata_file" =~ \.json$ ]]; then
                # JSON metadata
                if command -v jq >/dev/null 2>&1; then
                    local bench_type=$(jq -r '.bench_type // .benchType // .type // empty' "$full_path" 2>/dev/null)
                    if [ -n "$bench_type" ] && [ "$bench_type" != "null" ]; then
                        log_success "Detected bench type from metadata: $bench_type"
                        echo "$bench_type"
                        return 0
                    fi
                fi
            else
                # Plain text metadata
                local bench_type=$(grep -i "bench_type\|benchType\|type" "$full_path" 2>/dev/null | head -1 | cut -d'=' -f2 | tr -d ' "')
                if [ -n "$bench_type" ]; then
                    log_success "Detected bench type from metadata: $bench_type"
                    echo "$bench_type"
                    return 0
                fi
            fi
        fi
    done
    
    log_info "No bench metadata found - proceeding with AI analysis"
    echo ""
}

# ====================================
# AI-Powered Project Analysis
# ====================================

# Analyze project structure to determine devBench type
analyze_project_structure() {
    local project_path="$1"
    
    log_section "🤖 AI-Enhanced Project Structure Analysis"
    
    # Check for specific project indicators with confidence scores
    local flutter_confidence=0
    local python_confidence=0
    local java_confidence=0
    local dotnet_confidence=0
    local cpp_confidence=0
    
    # Flutter/Dart indicators
    if [ -f "$project_path/pubspec.yaml" ]; then
        if grep -q "flutter:" "$project_path/pubspec.yaml" 2>/dev/null; then
            flutter_confidence=95
            log_info "🎯 Flutter project detected (pubspec.yaml with flutter dependency): 95% confidence"
        else
            flutter_confidence=85
            log_info "🎯 Dart project detected (pubspec.yaml): 85% confidence"
        fi
    fi
    
    if [ -d "$project_path/lib" ] && find "$project_path/lib" -name "*.dart" -type f | head -1 >/dev/null 2>&1; then
        flutter_confidence=$((flutter_confidence + 20))
        log_info "   📁 Dart lib directory found: +20 confidence"
    fi
    
    if [ -f "$project_path/android/app/build.gradle" ] || [ -f "$project_path/ios/Runner.xcodeproj/project.pbxproj" ]; then
        flutter_confidence=$((flutter_confidence + 15))
        log_info "   📱 Mobile platform directories found: +15 confidence"
    fi
    
    # Python indicators
    if [ -f "$project_path/requirements.txt" ] || [ -f "$project_path/pyproject.toml" ] || [ -f "$project_path/setup.py" ] || [ -f "$project_path/Pipfile" ]; then
        python_confidence=90
        log_info "🐍 Python project detected (requirements/setup files): 90% confidence"
    fi
    
    if [ -d "$project_path/src" ] && [ -d "$project_path/tests" ] && find "$project_path" -name "*.py" -type f | head -1 >/dev/null 2>&1; then
        python_confidence=$((python_confidence + 15))
        log_info "   📁 Python project structure found: +15 confidence"
    fi
    
    if [ -f "$project_path/manage.py" ] || [ -f "$project_path/wsgi.py" ]; then
        python_confidence=$((python_confidence + 20))
        log_info "   🌐 Django/Flask indicators found: +20 confidence"
    fi
    
    # Java indicators
    if [ -f "$project_path/pom.xml" ]; then
        java_confidence=95
        log_info "☕ Java Maven project detected: 95% confidence"
    elif [ -f "$project_path/build.gradle" ] || [ -f "$project_path/build.gradle.kts" ]; then
        java_confidence=90
        log_info "☕ Java Gradle project detected: 90% confidence"
    fi
    
    if [ -d "$project_path/src/main/java" ]; then
        java_confidence=$((java_confidence + 15))
        log_info "   📁 Java source structure found: +15 confidence"
    fi
    
    # .NET indicators
    if find "$project_path" -name "*.csproj" -o -name "*.sln" -o -name "*.fsproj" -o -name "*.vbproj" | head -1 >/dev/null 2>&1; then
        dotnet_confidence=95
        log_info "🔷 .NET project detected (project files): 95% confidence"
    fi
    
    if [ -f "$project_path/Program.cs" ] || [ -f "$project_path/Startup.cs" ]; then
        dotnet_confidence=$((dotnet_confidence + 10))
        log_info "   🚀 .NET application files found: +10 confidence"
    fi
    
    # C++ indicators
    if [ -f "$project_path/CMakeLists.txt" ]; then
        cpp_confidence=90
        log_info "⚙️ C++ CMake project detected: 90% confidence"
    elif [ -f "$project_path/Makefile" ]; then
        cpp_confidence=85
        log_info "⚙️ C++ Make project detected: 85% confidence"
    elif [ -f "$project_path/meson.build" ]; then
        cpp_confidence=80
        log_info "⚙️ C++ Meson project detected: 80% confidence"
    fi
    
    if [ -d "$project_path/src" ] && [ -d "$project_path/include" ] && find "$project_path" -name "*.cpp" -o -name "*.hpp" -o -name "*.h" | head -1 >/dev/null 2>&1; then
        cpp_confidence=$((cpp_confidence + 15))
        log_info "   📁 C++ project structure found: +15 confidence"
    fi
    
    # Determine the best match
    local max_confidence=0
    local best_bench=""
    
    if [ $flutter_confidence -gt $max_confidence ]; then
        max_confidence=$flutter_confidence
        best_bench="flutterBench"
    fi
    
    if [ $python_confidence -gt $max_confidence ]; then
        max_confidence=$python_confidence
        best_bench="pythonBench"
    fi
    
    if [ $java_confidence -gt $max_confidence ]; then
        max_confidence=$java_confidence
        best_bench="javaBench"
    fi
    
    if [ $dotnet_confidence -gt $max_confidence ]; then
        max_confidence=$dotnet_confidence
        best_bench="dotNetBench"
    fi
    
    if [ $cpp_confidence -gt $max_confidence ]; then
        max_confidence=$cpp_confidence
        best_bench="cppBench"
    fi
    
    # Report results
    echo ""
    log_section "📊 Analysis Results"
    echo "   🎯 Flutter/Dart: ${flutter_confidence}%"
    echo "   🐍 Python: ${python_confidence}%"
    echo "   ☕ Java: ${java_confidence}%"
    echo "   🔷 .NET: ${dotnet_confidence}%"
    echo "   ⚙️ C++: ${cpp_confidence}%"
    echo ""
    
    if [ $max_confidence -ge 70 ]; then
        log_success "🎉 Detected project type: $best_bench (${max_confidence}% confidence)"
        echo "$best_bench"
    else
        log_warning "🤔 Uncertain project type (max confidence: ${max_confidence}%)"
        echo "UNCERTAIN"
    fi
}

# ====================================
# DevBench Delegation Functions
# ====================================

# Find and execute the appropriate bench-specific update script
delegate_to_bench_script() {
    local bench_type="$1"
    local project_path="$2"
    
    log_section "🚀 Delegating to $bench_type Update Script"
    
    # Map bench types to script patterns
    local bench_name="${bench_type%Bench}"  # Remove 'Bench' suffix if present
    local script_patterns=(
        "$DEVBENCHES_DIR/${bench_type}/scripts/update-${bench_name}-project.sh"
        "$DEVBENCHES_DIR/${bench_type}/scripts/update-project.sh"
        "$DEVBENCHES_DIR/${bench_type}/update-${bench_name}-project.sh"
        "$DEVBENCHES_DIR/${bench_type}/update-project.sh"
    )
    
    log_info "🔍 Looking for update script for $bench_type..."
    for script_path in "${script_patterns[@]}"; do
        log_info "   Checking: $(basename "$script_path")"
        if [ -f "$script_path" ]; then
            log_success "✅ Found update script: $script_path"
            
            # Make script executable if needed
            if [ ! -x "$script_path" ]; then
                log_info "🔧 Making script executable..."
                chmod +x "$script_path"
            fi
            
            echo ""
            log_info "🎯 Executing: $script_path $project_path"
            echo ""
            
            # Execute the bench-specific update script
            if "$script_path" "$project_path"; then
                log_success "✅ $bench_type project update completed successfully!"
                return 0
            else
                local exit_code=$?
                log_error "❌ $bench_type project update failed with exit code: $exit_code"
                return $exit_code
            fi
        fi
    done
    
    # No script found
    log_error "❌ No update script found for $bench_type"
    echo ""
    echo "Searched for:"
    for pattern in "${script_patterns[@]}"; do
        echo "  - $(basename "$pattern")"
    done
    echo ""
    echo "Please ensure the $bench_type has an update script available."
    return 1
}

# ====================================
# Main Workflow
# ====================================

main() {
    echo -e "${BLUE}DevBench Project Type Detection & Update Script${NC}"
    echo "=================================================="
    echo ""
    
    # Validate project path
    if [ ! -d "$PROJECT_PATH" ]; then
        log_error "Project directory not found: $PROJECT_PATH"
        exit 1
    fi
    
    cd "$PROJECT_PATH"
    
    log_info "🎯 Project: $PROJECT_NAME"
    log_info "📁 Path: $PROJECT_PATH"
    echo ""
    
    # Step 1: Check for existing bench metadata
    local detected_bench
    detected_bench=$(detect_bench_metadata "$PROJECT_PATH")
    
    # Step 2: If no metadata found, use AI analysis
    if [ -z "$detected_bench" ] || [ "$detected_bench" = "UNCERTAIN" ]; then
        log_info "🧠 Running AI analysis to determine project type..."
        detected_bench=$(analyze_project_structure "$PROJECT_PATH")
    fi
    
    # Step 3: Validate detection result
    if [ -z "$detected_bench" ] || [ "$detected_bench" = "UNCERTAIN" ]; then
        log_error "Could not determine devBench project type"
        echo ""
        echo "💡 To help with detection, you can:"
        echo "   1. Add a .workbench file with: bench_type=flutterBench"
        echo "   2. Ensure your project has standard structure files"
        echo "   3. Run the specific bench update script directly"
        exit 1
    fi
    
    # Step 4: Delegate to the appropriate bench-specific update script
    echo ""
    delegate_to_bench_script "$detected_bench" "$PROJECT_PATH"
}

# ====================================
# Script Execution
# ====================================

# Show usage if help requested
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    echo "Usage: $0 <project-path>"
    echo ""
    echo "AI-powered devBench project type detection and update delegation script."
    echo ""
    echo "This script:"
    echo "  1. Checks for bench metadata in the project"
    echo "  2. Uses AI analysis to determine project type if no metadata found"
    echo "  3. Delegates to the appropriate bench-specific update script"
    echo ""
    echo "Supported project types:"
    echo "  - flutterBench: Flutter/Dart projects"
    echo "  - pythonBench: Python projects"
    echo "  - javaBench: Java/Maven/Gradle projects"
    echo "  - dotNetBench: .NET/C# projects"
    echo "  - cppBench: C++/CMake projects"
    echo ""
    echo "Project metadata files (optional):"
    echo "  - .workbench"
    echo "  - .devbench"
    echo "  - .bench-info"
    echo "  - .workbench-metadata.json"
    echo "  - .devcontainer/workbench-metadata.json"
    echo ""
    exit 0
fi

# Run main function
main "$@"