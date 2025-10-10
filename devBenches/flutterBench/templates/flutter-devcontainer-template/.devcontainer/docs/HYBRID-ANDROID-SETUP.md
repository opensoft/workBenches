# Android SDK Hybrid Setup Guide

This document explains the hybrid Android development setup in this dev container, which combines network connectivity to Windows host emulators with a complete Linux Android SDK installation.

## Overview

The hybrid setup provides the best of both worlds:

- **High-performance emulator**: Uses Windows host emulator for optimal graphics and performance
- **Complete toolchain**: Full Android SDK installed in Linux container for all development needs
- **Network connectivity**: ADB server socket connection bridges container to host emulator
- **Self-contained**: Can work independently when Windows host is not available

## Architecture

### Network Connection to Windows Emulator

The container connects to Android emulators running on the Windows host via network ADB:

```
Windows Host                    WSL2 Container
├── Android Emulator            ├── Flutter App
├── ADB Server (port 5037)  ←→  ├── ADB Client
└── Emulator (port 5555)        └── Development Tools
```

**Connection method**: `ADB_SERVER_SOCKET=tcp:host.docker.internal:5037`

### Full Linux Android SDK

Complete official Google Android SDK installed at `/opt/android-sdk/`:

```
/opt/android-sdk/
├── cmdline-tools/latest/
│   ├── sdkmanager           # Package manager
│   ├── avdmanager          # Virtual device manager
│   └── ...
├── platform-tools/
│   ├── adb                 # Android Debug Bridge
│   ├── fastboot           # Bootloader tool
│   └── ...
├── build-tools/34.0.0/
│   ├── aapt               # Android Asset Packaging Tool
│   ├── zipalign           # APK optimization
│   └── ...
├── platforms/android-34/   # Android API 34
├── emulator/               # Android emulator (Linux)
└── system-images/          # Emulator system images
```

## Directory Structure

### Primary SDK Location

- **Path**: `/opt/android-sdk/`
- **Source**: Official Google Android SDK
- **Components**: Complete development toolchain
- **Environment**: `ANDROID_HOME`, `ANDROID_SDK_ROOT`

### Flutter Compatibility Layer

- **Path**: `/home/brett/Android/Sdk/platform-tools/`
- **Source**: Symlinks to `/opt/android-sdk/platform-tools/`
- **Purpose**: Flutter expects tools at this location
- **Tools**: `adb`, `fastboot`

### System Fallback Tools

- **Path**: `/usr/bin/`
- **Source**: Ubuntu package manager (`android-tools-adb`)
- **Purpose**: Backup tools if SDK tools fail
- **Usage**: Lower priority in PATH

## Available Tools and Commands

### SDK Management

```bash
# List available packages
sdkmanager --list

# Install additional packages
sdkmanager "platforms;android-35" "build-tools;35.0.0"

# Update all installed packages
sdkmanager --update

# List installed packages
sdkmanager --list_installed
```

### Virtual Device Management

```bash
# List available system images
avdmanager list target

# Create new AVD
avdmanager create avd -n "MyEmulator" -k "system-images;android-34;google_apis;x86_64"

# List created AVDs
avdmanager list avd

# Start Linux emulator (headless)
emulator @MyEmulator -no-audio -no-window
```

### Development Tools

```bash
# Check connected devices
adb devices -l

# Install APK
adb install app.apk

# Debug application
adb logcat

# Build tools
aapt dump badging app.apk
zipalign -v 4 input.apk output.apk
```

## Usage Scenarios

### Primary Workflow: Windows Emulator

1. **Start emulator on Windows host**
2. **Deploy from container**:
   ```bash
   flutter run                    # Auto-detects Windows emulator
   flutter run -d emulator-5556   # Specific device
   ```

### Alternative Workflow: Linux Container Emulator

1. **Create AVD in container**:
   ```bash
   avdmanager create avd -n "ContainerEmulator" -k "system-images;android-34;google_apis;x86_64"
   ```

2. **Start headless emulator**:
   ```bash
   emulator @ContainerEmulator -no-audio -no-window &
   ```

3. **Deploy application**:
   ```bash
   flutter run
   ```

### CI/CD Workflow: Automated Testing

```bash
# Create test emulator
avdmanager create avd -n "TestEmulator" -k "system-images;android-34;google_apis;x86_64"

# Start headless emulator
emulator @TestEmulator -no-audio -no-window -no-boot-anim &

# Wait for boot
adb wait-for-device

# Run tests
flutter test integration_test/
```

## Environment Configuration

### Container Environment Variables

```bash
ANDROID_HOME="/opt/android-sdk"
ANDROID_SDK_ROOT="/opt/android-sdk"  
ADB_SERVER_SOCKET="tcp:host.docker.internal:5037"
FLUTTER_ROOT="/opt/flutter"
```

### PATH Configuration

```bash
/opt/flutter/bin
/opt/flutter/bin/cache/dart-sdk/bin
/usr/bin                              # System tools (fallback)
/opt/android-sdk/platform-tools       # Primary Android tools
/opt/android-sdk/emulator             # Android emulator
/opt/android-sdk/cmdline-tools/latest/bin  # SDK management tools
```

## VS Code Integration

### Extensions

- `dart-code.flutter` - Flutter development
- `adelphes.android-dev-ext` - Android debugging
- `yovelovadia.device-android-ios-launcher` - Device management

### Settings

```json
{
  "emulator.emulatorPath": "/opt/android-sdk/emulator/emulator",
  "emulator.adbPath": "/opt/android-sdk/platform-tools/adb"
}
```

### Available Tasks

- **Android: Verify Emulator Connection** - Check setup
- **Launch Android Emulator** - Start Windows emulator
- **Emulator: Connect to Host Emulator** - Network connection
- **Flutter: Run**, **Flutter: Build APK** - Development tasks

## Troubleshooting

### Windows Emulator Not Detected

1. **Check ADB server connection**:
   ```bash
   echo $ADB_SERVER_SOCKET  # Should show: tcp:host.docker.internal:5037
   adb devices -l           # Should list Windows emulator
   ```

2. **Verify Windows ADB server**:
   ```cmd
   # On Windows Command Prompt
   adb devices
   adb -s emulator-5556 tcpip 5555
   ```

3. **Run verification script**:
   ```bash
   /workspace/.devcontainer/verify-emulator-connection.sh
   ```

### SDK Tools Not Found

1. **Check SDK installation**:
   ```bash
   ls -la /opt/android-sdk/
   which adb
   ```

2. **Verify environment**:
   ```bash
   echo $ANDROID_HOME        # Should show: /opt/android-sdk
   echo $PATH | grep android # Should include SDK paths
   ```

3. **Run Flutter doctor**:
   ```bash
   flutter doctor -v
   ```

### Container Emulator Issues

1. **Check available system images**:
   ```bash
   sdkmanager --list | grep system-images
   ```

2. **Create AVD with verbose output**:
   ```bash
   avdmanager create avd -n test -k "system-images;android-34;google_apis;x86_64" -v
   ```

3. **Start emulator with debugging**:
   ```bash
   emulator @test -verbose -no-audio -no-window
   ```

## Benefits

### Performance
- ✅ Windows emulator: Hardware-accelerated graphics
- ✅ Network ADB: Low-latency device communication
- ✅ Native tools: Optimized for container environment

### Flexibility
- ✅ Dual emulator support: Windows host + Linux container
- ✅ Complete SDK: All Android development tools available
- ✅ Offline capability: Works without Windows host

### Development Experience
- ✅ VS Code integration: Extensions work seamlessly
- ✅ Flutter compatibility: Auto-detects all emulators
- ✅ Modern toolchain: Latest official Google tools

### CI/CD Ready
- ✅ Self-contained: No external dependencies
- ✅ Automated testing: Headless emulator support
- ✅ Reproducible: Consistent environment across teams

## Container Size Impact

- **Base container**: ~1GB
- **Android SDK**: ~2GB additional
- **Total size**: ~3GB
- **Build time**: +5-10 minutes (one-time download)
- **Runtime**: No performance impact

## Maintenance

### Updating SDK

```bash
# Update all SDK components
sdkmanager --update

# Install specific updates
sdkmanager "platform-tools" "build-tools;35.0.0"
```

### Adding System Images

```bash
# List available images
sdkmanager --list | grep system-images

# Install additional system image
sdkmanager "system-images;android-35;google_apis;x86_64"
```

### Container Updates

To update the container with new SDK versions:

1. Modify `Dockerfile` SDK component versions
2. Rebuild container: `Ctrl+Shift+P` → "Dev Containers: Rebuild Container"
3. Verify setup: Run verification script

This hybrid setup provides a robust, flexible, and high-performance Android development environment that works both with and without Windows host connectivity.