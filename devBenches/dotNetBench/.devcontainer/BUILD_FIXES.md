# DevContainer Build Fixes - October 2, 2025 (Legacy)

This document applies to the **legacy monolithic .devcontainer** build and is deprecated. The current standard is the layered image system (`workbench-base` → `devbench-base` → `dotnet-bench`). Keep this for historical reference only.

## Issues Fixed

### 1. Package Installation Conflicts
**Problem**: The Dockerfile had a massive single `RUN apt-get install` command with 80+ packages, causing:
- Package dependency conflicts
- Build timeouts
- nodejs/npm conflicts from different repositories

**Solution**: Split the installation into logical phases:
- Phase 2a: Core development tools
- Phase 2b: .NET SDK and runtime
- Phase 2c: Node.js (separately, as it includes npm)
- Phase 2c2: Python, Go, and other languages
- Phase 2d: Java JDKs (each version separately)
- Phase 2e-2p: Other tools in logical groups

### 2. User Configuration Issues
**Problem**: Environment variables (USER, UID, GID) were not being properly set, causing:
- Build warnings about empty variables
- Container startup failures
- Permission issues

**Solution**: 
- Hardcoded values in docker-compose.yml: `brett`, UID `1000`, GID `1000`
- Updated devcontainer.json to use `"remoteUser": "brett"` directly
- Fixed volume mounts to use `/home/brett` instead of `/home/${USER}`

### 3. Docker Compose Configuration
**Problem**: 
- Obsolete `version: '3.8'` attribute causing warnings
- Environment variable interpolation not working properly

**Solution**:
- Removed obsolete `version` attribute
- Used direct values instead of environment variable references

## Files Modified

1. **Dockerfile**: Split package installations into 17 separate phases
2. **docker-compose.yml**: 
   - Hardcoded user values
   - Removed version attribute
   - Fixed volume mount paths
3. **devcontainer.json**: Set `remoteUser` to "brett"
4. **.env**: Created with default values (USER=brett, UID=1000, GID=1000)

## Container Configuration

The container is configured with:
- **Command**: `sleep infinity` (keeps container running indefinitely)
- **User**: brett (UID 1000, GID 1000)
- **Workspace**: `/workspace` (mounted from parent directory)
- **Ports**: 5000, 5001, 7071, 8080, 3000, 4200
- **Docker access**: Privileged mode with docker socket mounted
- **Network**: Connected to shared `dev_bench` network

## Build Progress

The container build now successfully progresses through all phases:
- ✅ System foundation & repositories (Phase 1)
- ✅ Package installations split into chunks (Phase 2a-2p)
- ✅ User management (Phase 3)
- ✅ Additional configurations
