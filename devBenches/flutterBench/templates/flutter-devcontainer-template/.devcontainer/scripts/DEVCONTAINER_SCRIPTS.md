# DevContainer Scripts

This directory contains scripts that enhance the Flutter development experience within the devcontainer.

## Scripts Overview

### 🚀 `setup-flutter-project.sh`
**Used by**: `onCreateCommand` in devcontainer.json
**Purpose**: Robust Flutter project initialization with automatic updates and error handling

**Features**:
- ✅ **Automatic Flutter Updates**: Detects and applies Flutter updates without user interaction
- ✅ **Dependency Installation**: Runs `flutter pub get` and `flutter precache` safely
- ✅ **Error Logging**: Comprehensive logging with separate error and success logs
- ✅ **User-Friendly Reports**: Clear error summaries and debugging instructions
- ✅ **Graceful Failures**: Continues on non-critical errors, fails fast on critical ones

**Logs Location**:
- Main log: `/tmp/flutter-setup.log`
- Error log: `/tmp/flutter-setup-errors.log`
- Success log: `/tmp/flutter-setup-success.log`

### 📊 `flutter-status.sh`
**Used by**: `postStartCommand` in devcontainer.json
**Purpose**: Comprehensive development environment status check

**Features**:
- ✅ **Setup Status**: Reports on previous setup success/failures
- ✅ **Flutter Environment**: Checks Flutter installation and version
- ✅ **Project Status**: Analyzes current Flutter project state
- ✅ **Android Development**: ADB connection and device status
- ✅ **Port Status**: Reports on development port availability
- ✅ **Development Commands**: Lists helpful commands for development

### ⚡ `ready-check.sh`
**Used by**: `postAttachCommand` in devcontainer.json
**Purpose**: Quick status check when attaching to the container

**Features**:
- ✅ **Brief Status**: Quick project and device overview
- ✅ **Setup Status**: Reports setup completion status
- ✅ **Quick Commands**: Lists most common development commands
- ✅ **Dartwing Integration**: Shows service-specific commands when available

## Error Handling Strategy

### Automatic Updates
The `setup-flutter-project.sh` script addresses the common issue where Flutter needs updates during container initialization:

```bash
# Before (caused exit code 66):
flutter pub get && flutter precache

# After (robust handling):
flutter upgrade  # if needed
flutter pub get  # with error handling
flutter precache # non-critical, continues on failure
```

### Logging Strategy
1. **All operations** → Main log (`/tmp/flutter-setup.log`)
2. **Errors only** → Error log (`/tmp/flutter-setup-errors.log`)
3. **Success operations** → Success log (`/tmp/flutter-setup-success.log`)

### Failure Recovery
- **Critical failures**: Stop execution, show clear error message
- **Non-critical failures**: Log warning, continue execution
- **User guidance**: Provide specific commands to debug/fix issues

## Usage in DevContainer

### onCreateCommand (Container Creation)
Runs once when container is created - handles heavy setup:
```json
"onCreateCommand": {
  "setup-flutter-project": ".devcontainer/scripts/setup-flutter-project.sh"
}
```

### postStartCommand (Container Start)
Runs each time container starts - comprehensive status:
```json
"postStartCommand": {
  "flutter-status": ".devcontainer/scripts/flutter-status.sh"
}
```

### postAttachCommand (IDE Attach)
Runs when VS Code attaches - quick status:
```json
"postAttachCommand": ".devcontainer/scripts/ready-check.sh"
```

## Manual Usage

You can run these scripts manually at any time:

```bash
# Full setup (typically not needed after container creation)
.devcontainer/scripts/setup-flutter-project.sh

# Comprehensive status check
.devcontainer/scripts/flutter-status.sh

# Quick status check
.devcontainer/scripts/ready-check.sh
```

## Troubleshooting

### Setup Issues
If container creation fails:
1. Check main log: `cat /tmp/flutter-setup.log`
2. Check error log: `cat /tmp/flutter-setup-errors.log`
3. Re-run setup manually: `.devcontainer/scripts/setup-flutter-project.sh`

### Update Issues
If Flutter needs manual updates:
```bash
flutter upgrade
flutter pub get
flutter doctor
```

### Device Connection Issues
If Android devices aren't detected:
```bash
adb devices
adb kill-server
adb start-server
```

## Integration with Dartwing

These scripts are aware of Dartwing-specific configurations:
- **Service Commands**: Shows Docker Compose commands when `docker-compose.override.yml` exists
- **Port Awareness**: Checks .NET service ports (5000, 5001)
- **Multi-Service Status**: Reports on both Flutter and .NET service status

This ensures seamless development in the multi-container Dartwing environment.