# PowerShell script to start the Flutter DevBench Monster Container
# For Windows users who want to run from PowerShell

Write-Host "🚀 Starting the Flutter DevBench Monster Container" -ForegroundColor Green

# Check if we're in WSL context or need to use WSL
if ($env:WSL_DISTRO_NAME) {
    # We're already in WSL
    Write-Host "   Running in WSL: $env:WSL_DISTRO_NAME" -ForegroundColor Cyan
    
    # Get user info using bash
    $userInfo = bash -c 'echo "$(whoami):$(id -u):$(id -g)"'
    $parts = $userInfo.Split(':')
    $env:USER = $parts[0]
    $env:UID = $parts[1] 
    $env:GID = $parts[2]
} else {
    # We're in Windows PowerShell, need to use WSL
    Write-Host "   Using WSL to get user info..." -ForegroundColor Cyan
    
    try {
        $userInfo = wsl bash -c 'echo "$(whoami):$(id -u):$(id -g)"'
        $parts = $userInfo.Split(':')
        $env:USER = $parts[0]
        $env:UID = $parts[1]
        $env:GID = $parts[2]
    } catch {
        Write-Host "❌ Error: Could not get user info from WSL" -ForegroundColor Red
        Write-Host "   Make sure WSL is installed and working" -ForegroundColor Yellow
        exit 1
    }
}

Write-Host "   User: $env:USER (UID: $env:UID, GID: $env:GID)" -ForegroundColor Cyan

# Validate we have the required info
if (-not $env:USER -or -not $env:UID -or -not $env:GID) {
    Write-Host "❌ Error: Could not determine user info" -ForegroundColor Red
    Write-Host "   USER=$env:USER, UID=$env:UID, GID=$env:GID" -ForegroundColor Yellow
    exit 1
}

Write-Host "🔧 Building container with user mapping..." -ForegroundColor Yellow

# Change to the correct directory
Push-Location -Path ".devcontainer"

try {
    # Start the container with proper user mapping
    if ($env:WSL_DISTRO_NAME) {
        # Already in WSL
        & docker-compose up -d --build
    } else {
        # Use WSL to run docker-compose
        & wsl docker-compose up -d --build
    }
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Container started successfully!" -ForegroundColor Green
        Write-Host ""
        Write-Host "🎯 Next steps:" -ForegroundColor Cyan
        Write-Host "   - Open VS Code and select 'Reopen in Container'" -ForegroundColor White
        Write-Host "   - Or run: docker exec -it flutter_bench zsh" -ForegroundColor White
        Write-Host ""
        Write-Host "🔍 To check container status:" -ForegroundColor Cyan
        Write-Host "   docker ps | grep flutter_bench" -ForegroundColor White
        Write-Host ""
        Write-Host "📱 Flutter Development Ready:" -ForegroundColor Magenta
        Write-Host "   - Flutter SDK installed at /opt/flutter" -ForegroundColor White
        Write-Host "   - Android SDK with emulator support" -ForegroundColor White
        Write-Host "   - 15+ Flutter development tools" -ForegroundColor White
        Write-Host "   - Firebase, Fastlane, Shorebird ready" -ForegroundColor White
        Write-Host "   - Design workflow with Figma integration" -ForegroundColor White
    } else {
        Write-Host "❌ Container failed to start. Check Docker logs:" -ForegroundColor Red
        Write-Host "   docker-compose logs" -ForegroundColor Yellow
    }
} catch {
    Write-Host "❌ Error running docker-compose: $_" -ForegroundColor Red
} finally {
    Pop-Location
}