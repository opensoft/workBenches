#!/bin/bash

# C++ Heavy Development Environment Launcher (Shell Script)
# Alternative launcher for systems without VS Code or for advanced users

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

print_header() {
    echo -e "${CYAN}$1${NC}"
}

# Help function
show_help() {
    print_header "🚀 C++ Heavy Development Environment Launcher"
    print_header "=============================================="
    echo ""
    echo "Usage:"
    echo "  $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -r, --rebuild  Rebuild the container before launching"
    echo "  -s, --shell    Launch container with shell instead of VS Code"
    echo "  -d, --daemon   Run container in daemon mode"
    echo ""
    echo "Examples:"
    echo "  $0                    # Launch with VS Code"
    echo "  $0 --shell            # Launch container with bash shell"
    echo "  $0 --rebuild --shell  # Rebuild and launch with shell"
    echo ""
}

# Parse arguments
REBUILD=false
SHELL_MODE=false
DAEMON_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -r|--rebuild)
            REBUILD=true
            shift
            ;;
        -s|--shell)
            SHELL_MODE=true
            shift
            ;;
        -d|--daemon)
            DAEMON_MODE=true
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

print_header "🚀 C++ Heavy Development Environment"
print_header "===================================="

# Check if Docker is running
print_info "Checking Docker status..."
if ! docker info > /dev/null 2>&1; then
    print_error "Docker is not running. Please start Docker first."
    exit 1
fi
print_success "Docker is running"

# Get script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd "$SCRIPT_DIR"

# Rebuild if requested
if [ "$REBUILD" = true ]; then
    print_info "Rebuilding container..."
    docker-compose -f .devcontainer/docker-compose.yml build --no-cache
    print_success "Container rebuilt successfully"
fi

# Launch based on mode
if [ "$SHELL_MODE" = true ]; then
    print_info "🐚 Launching container with bash shell..."
    
    # Start container if not running
    docker-compose -f .devcontainer/docker-compose.yml up -d
    
    # Execute bash in the container
    print_success "Container started. Entering bash shell..."
    print_info "Type 'exit' to leave the container"
    print_info ""
    print_info "📚 Quick commands inside container:"
    print_info "  cd /workspace/projects/sample-cpp  # Go to sample project"
    print_info "  ./build.sh                         # Build sample project"
    print_info "  htop                               # System monitor"
    print_info "  gcc --version                      # Check compiler version"
    print_info ""
    
    docker-compose -f .devcontainer/docker-compose.yml exec cppbench bash
    
elif [ "$DAEMON_MODE" = true ]; then
    print_info "🔄 Starting container in daemon mode..."
    docker-compose -f .devcontainer/docker-compose.yml up -d
    print_success "Container is running in the background"
    print_info "Connect with: docker-compose -f .devcontainer/docker-compose.yml exec cppbench bash"
    
else
    # Default VS Code mode
    if ! command -v code &> /dev/null; then
        print_warning "VS Code not found. Falling back to shell mode..."
        SHELL_MODE=true
        exec "$0" --shell
    fi
    
    print_info "🚀 Launching VS Code devcontainer..."
    code .
    print_success "VS Code launched!"
fi

print_success "C++ Heavy Development Environment ready! 🛠️"

if [ "$SHELL_MODE" != true ]; then
    echo ""
    print_header "📚 Quick Start Guide:"
    echo "  1. Wait for container to build (first time only)"
    echo "  2. Open terminal in VS Code"
    echo "  3. Navigate to sample: cd /workspace/projects/sample-cpp"
    echo "  4. Build sample: ./build.sh"
    echo ""
    print_header "🔧 Environment Features:"
    echo "  • GCC 12 and Clang 15 compilers"
    echo "  • CMake and Ninja build systems"
    echo "  • vcpkg and Conan package managers"
    echo "  • Debugging and profiling tools"
    echo "  • Static analysis tools"
    echo "  • Google Test framework"
    echo ""
    print_warning "For troubleshooting, see .devcontainer/BUILD_FIXES.md"
fi