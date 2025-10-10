# C++ Heavy Development Environment Launcher (PowerShell)
# Launches the devcontainer for C++ development on Windows

param(
    [switch]$Help,
    [switch]$Rebuild
)

# Color functions
function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Blue
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

# Help text
if ($Help) {
    Write-Host "C++ Heavy Development Environment Launcher" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  .\start-monster.ps1          # Launch the development environment"
    Write-Host "  .\start-monster.ps1 -Rebuild # Rebuild the container before launching"
    Write-Host "  .\start-monster.ps1 -Help    # Show this help message"
    Write-Host ""
    Write-Host "Requirements:"
    Write-Host "  • Docker Desktop for Windows"
    Write-Host "  • VS Code with Dev Containers extension"
    Write-Host "  • WSL 2 (recommended)"
    exit 0
}

Write-Host "🚀 C++ Heavy Development Environment Launcher" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan

# Check if Docker is running
Write-Info "Checking Docker status..."
try {
    docker info | Out-Null
    Write-Success "Docker is running"
}
catch {
    Write-Error "Docker is not running or not accessible"
    Write-Info "Please start Docker Desktop and try again"
    exit 1
}

# Check if VS Code is installed
Write-Info "Checking VS Code installation..."
try {
    $codeVersion = code --version 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Success "VS Code is installed"
    } else {
        throw "VS Code not found"
    }
}
catch {
    Write-Error "VS Code is not installed or not in PATH"
    Write-Info "Please install VS Code and the Dev Containers extension"
    Write-Info "Download from: https://code.visualstudio.com/"
    exit 1
}

# Get script directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptDir

Write-Info "Script directory: $scriptDir"

# Rebuild container if requested
if ($Rebuild) {
    Write-Info "Rebuilding container..."
    try {
        docker-compose -f .devcontainer/docker-compose.yml build --no-cache
        Write-Success "Container rebuilt successfully"
    }
    catch {
        Write-Error "Failed to rebuild container"
        exit 1
    }
}

# Launch VS Code with devcontainer
Write-Info "🚀 Launching C++ Heavy Development Environment..."
Write-Info "This will build and start the devcontainer if needed."

try {
    code .
    Write-Success "VS Code launched successfully!"
}
catch {
    Write-Error "Failed to launch VS Code"
    exit 1
}

Write-Host ""
Write-Host "📚 Quick Start Guide:" -ForegroundColor Cyan
Write-Host "  1. Wait for the container to build (first time only)"
Write-Host "  2. Open terminal in VS Code (Ctrl+``)"
Write-Host "  3. Navigate to sample project: cd /workspace/projects/sample-cpp"
Write-Host "  4. Build sample project: ./build.sh"
Write-Host ""
Write-Host "🔧 Environment Features:" -ForegroundColor Cyan
Write-Host "  • Modern C++ compilers (GCC 12, Clang 15)"
Write-Host "  • Build systems (CMake, Ninja)"
Write-Host "  • Package managers (vcpkg, Conan)"
Write-Host "  • Debugging tools (GDB, Valgrind)"
Write-Host "  • Static analysis (Clang-Tidy, CppCheck)"
Write-Host "  • Testing framework (Google Test)"
Write-Host "  • Complete VS Code C++ extension suite"
Write-Host ""
Write-Host "📖 For troubleshooting:" -ForegroundColor Yellow
Write-Host "  See .devcontainer/BUILD_FIXES.md"
Write-Host ""
Write-Success "Environment ready for heavy C++ development! 🛠️"