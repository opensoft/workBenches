# DevContainer Documentation

This directory contains documentation for the DevContainer development environment setup and configuration.

## 📚 Documentation Files

### Android Development Setup
- **[ANDROID-SDK-HYBRID-SETUP.md](ANDROID-SDK-HYBRID-SETUP.md)** - Hybrid Android SDK setup guide
- **[HYBRID-ANDROID-SETUP.md](HYBRID-ANDROID-SETUP.md)** - Complete hybrid Android development setup

### Emulator Setup & Testing
- **[README-Emulator.md](README-Emulator.md)** - Android emulator setup and configuration
- **[EMULATOR-TESTING-GUIDE.md](EMULATOR-TESTING-GUIDE.md)** - Comprehensive emulator testing guide

### Template & Networking Documentation
- **[DEVCONTAINER_README.md](DEVCONTAINER_README.md)** - Flutter DevContainer template documentation
- **[flutter-devcontainer-networking-guide.md](flutter-devcontainer-networking-guide.md)** - Networking architecture guide

## 🎯 Current Active Configuration

The current DevContainer uses:
- **Shared ADB Infrastructure** (not individual ADB services)
- **Root-level container files** (docker-compose.yml, Dockerfile)
- **Template-managed scripts** (scripts/ folder)

These documentation files are primarily for reference and troubleshooting legacy configurations or alternative setups.

**Note**: Outdated documentation referencing removed components (adb-service containers, docker-compose-with-adb.yml) has been cleaned up as of October 2025.

## 🔧 Active DevContainer Files

The active DevContainer configuration consists of:
- `.devcontainer/devcontainer.json` - VS Code DevContainer configuration
- `docker-compose.yml` - Flutter container definition
- `docker-compose.override.yml` - Dartwing .NET service addition  
- `Dockerfile` - Container build instructions
- `scripts/` - Template-managed setup and status scripts

## 📖 Usage

These documentation files are preserved for:
- **Reference**: Understanding alternative setup approaches
- **Troubleshooting**: Debugging DevContainer issues
- **Legacy Support**: Projects using older configurations
- **Learning**: Understanding the evolution of the development environment

For current setup procedures, use the template-managed scripts in the `scripts/` folder.