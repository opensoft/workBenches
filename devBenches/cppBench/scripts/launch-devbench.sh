#!/bin/bash

# C++ Heavy Development Environment Launcher
# Launches the devcontainer for C++ development

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    print_error "Docker is not running. Please start Docker first."
    exit 1
fi

# Check if VS Code is installed
if ! command -v code &> /dev/null; then
    print_error "VS Code is not installed or not in PATH."
    print_info "Please install VS Code and the Dev Containers extension."
    exit 1
fi

# Check for Dev Containers extension
print_info "Checking for VS Code Dev Containers extension..."

# Get the script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

print_info "🚀 Launching C++ Heavy Development Environment..."
print_info "This will build and start the devcontainer if needed."

# Change to the bench directory (parent of scripts)
BENCH_DIR="$(dirname "$SCRIPT_DIR")"
cd "$BENCH_DIR"

# Launch VS Code with devcontainer
print_info "Opening VS Code devcontainer..."
code .

print_success "C++ Heavy Development Environment launched!"
print_info "VS Code should open the devcontainer automatically."
print_info ""
print_info "📚 Quick Start:"
print_info "  1. Wait for the container to build (first time only)"
print_info "  2. Open terminal in VS Code"
print_info "  3. Navigate to sample project: cd /workspace/projects/sample-cpp"
print_info "  4. Build sample project: ./build.sh"
print_info ""
print_info "🔧 Environment Features:"
print_info "  • GCC 12 and Clang 15 compilers"
print_info "  • CMake and Ninja build systems"
print_info "  • vcpkg and Conan package managers"
print_info "  • GDB, Valgrind, and static analysis tools"
print_info "  • Google Test framework"
print_info "  • Full VS Code C++ extension suite"
print_info ""
print_info "📖 For troubleshooting, see .devcontainer/BUILD_FIXES.md"