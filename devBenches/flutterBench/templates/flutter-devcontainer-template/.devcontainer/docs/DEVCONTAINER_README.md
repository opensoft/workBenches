# Flutter DevContainer Template

This template provides a **lightweight Flutter project container** with shared ADB infrastructure support.

## 🎯 Container Philosophy

This container is designed for **individual Flutter projects** and follows the principle:
- **FlutterBench** = Heavy development workbench with all tools (~2GB+, 10+ minute build)
- **Project Containers** = Lightweight debugging/running environment (~500MB, 2-3 minute build)

**Use this for**: Debugging, testing, light edits, running your app  
**Use FlutterBench for**: Heavy development, code generation, complex builds, polyglot work

## 🚀 Quick Start

### Option A: Manual Setup

1. **Create your Flutter project**:
   ```bash
   cd Dartwingers  # or your desired project group
   flutter create your_project_name
   cd your_project_name
   ```

2. **Copy template files**:
   ```bash
   cp -r ../../DevBench/FlutterBench/templates/flutter-devcontainer-template/.devcontainer .
   cp -r ../../DevBench/FlutterBench/templates/flutter-devcontainer-template/.vscode .
   cp -r ../../DevBench/FlutterBench/templates/flutter-devcontainer-template/scripts .
   cp ../../DevBench/FlutterBench/templates/flutter-devcontainer-template/docker-compose.yml .
   cp ../../DevBench/FlutterBench/templates/flutter-devcontainer-template/Dockerfile .
   cp ../../DevBench/FlutterBench/templates/flutter-devcontainer-template/.env.example .
   cp ../../DevBench/FlutterBench/templates/flutter-devcontainer-template/.gitignore .
   ```

3. **Set up environment configuration**:
   ```bash
   cp .env.example .env
   # Edit .env and set PROJECT_NAME, USER_UID, USER_GID, etc.
   # Run 'id' to check your UID and GID
   ```

4. **Validate configuration** (required for manual setup):
   ```bash
   ./scripts/manual-setup-project.sh
   ```

5. **Open in VS Code**:
   ```bash
   code .
   ```

6. **Reopen in container** when prompted by VS Code

### Option B: Automated Setup

Use the provided script:

```bash
cd Bench/DevBench/FlutterBench/scripts
./new-flutter-project.sh your_project_name ../../Dartwingers
```

## 📁 What This Template Includes

### DevContainer Configuration (`.devcontainer/devcontainer.json`)
- ✅ Automatic ADB infrastructure startup via `initializeCommand`
- ✅ Flutter pub get and precache on container creation
- ✅ Flutter doctor and device check on startup
- ✅ VS Code extensions for Flutter/Dart development
- ✅ Optimized settings for Flutter development

### VS Code Configuration (`.vscode/`)
- **`tasks.json`**: Pre-configured tasks for:
  - 🔌 ADB connection management
  - 🩺 Flutter doctor, clean, test, analyze
  - 📱 Flutter run (debug/release)
  - 🔧 Pub get/upgrade
- **`launch.json`**: Debug configurations for Flutter apps and tests
- **`settings.json`**: Optimized Flutter development settings

### Docker Configuration
- **`docker-compose.yml`**: 
  - **Environment-driven configuration** using `.env` file
  - Connects to shared `${NETWORK_NAME}` network (default: dartnet)
  - Configured for shared ADB server with customizable host/port
  - Persistent pub and gradle caches per project
  - Resource limits configurable via `.env`
  - Port mappings for hot reload and DevTools
- **`Dockerfile`**: 
  - **Lightweight Ubuntu 24.04** base (much smaller than FlutterBench)
  - **Configurable Flutter SDK** version via `FLUTTER_VERSION` in `.env`
  - **Minimal Android SDK** - only platform-tools for debugging
  - **Essential tools only** - git, curl, nano, jq, tree, zsh
  - **User creation** matching host UID/GID for proper file permissions
  - **~300MB smaller** than the FlutterBench monster container

### Environment Configuration (`.env`)
- **`.env.example`**: Template with all available configuration options
- **`.env`**: Your project-specific configuration (auto-created, not in git)
- **Key variables**:
  - `PROJECT_NAME`: Container and volume names
  - `USER_UID`/`USER_GID`: Match your host user for file permissions
  - `FLUTTER_VERSION`: Specify Flutter SDK version
  - `CONTAINER_MEMORY`/`CONTAINER_CPUS`: Resource limits
  - `ADB_SERVER_HOST`/`ADB_SERVER_PORT`: Shared ADB configuration

## ⚙️ Environment Variables Configuration

This template uses **environment variables** via `.env` files for flexible, per-project configuration.

### Quick Setup
```bash
# 1. Copy template
cp .env.example .env

# 2. Edit key variables
# PROJECT_NAME=myproject
# USER_UID=1000  # Run 'id -u' to check
# USER_GID=1000  # Run 'id -g' to check

# 3. Validate (required for manual setup)
./scripts/manual-setup-project.sh
```

### Key Variables

#### **Project Configuration**
- `PROJECT_NAME`: Container name, volume names (e.g., `myapp-dev`)
- `NETWORK_NAME`: Docker network (default: `dartnet`)

#### **User Configuration**
- `USER_NAME`: Username in container (default: `vscode`)
- `USER_UID`: User ID - **should match your host UID** (`id -u`)
- `USER_GID`: Group ID - **should match your host GID** (`id -g`)

#### **Flutter Configuration**
- `FLUTTER_VERSION`: SDK version (e.g., `3.24.0`, `3.19.6`, `stable`)
- `ANDROID_HOME`: Android SDK path in container

#### **Resource Limits**
- `CONTAINER_MEMORY`: RAM limit (e.g., `4g`, `8g`)
- `CONTAINER_CPUS`: CPU limit (e.g., `2`, `4`)

#### **Development Ports**
- `HOT_RELOAD_PORT`: Flutter hot reload (default: `8080`)
- `DEVTOOLS_PORT`: Flutter DevTools (default: `9100`)

#### **ADB Configuration**
- `ADB_SERVER_HOST`: Shared ADB server hostname (default: `shared-adb-server`)
- `ADB_SERVER_PORT`: ADB port (default: `5037`)

### Environment File Rules

✅ **DO:**
- Copy `.env.example` to `.env` for each project
- Set `PROJECT_NAME` to something unique
- Match `USER_UID`/`USER_GID` to your host user
- Keep `.env.example` in git as template

❌ **DON'T:**
- Commit `.env` to git (contains user-specific config)
- Use spaces around `=` (e.g., `KEY = value`)
- Use quotes around values (e.g., `KEY="value"`)
- Leave `PROJECT_NAME` as default `myproject`

### Validation Script

Use the included validation script to check your configuration:

```bash
./scripts/manual-setup-project.sh
```

This script will:
- ✅ Check if `.env` exists (creates from `.env.example` if missing)
- ✅ Validate all required variables are set
- ✅ Check variable formats (PROJECT_NAME, UID/GID)
- ✅ Verify Docker environment
- ✅ Test Docker Compose configuration
- ✅ Check infrastructure path

📖 **For detailed script usage**, see [`scripts/README.md`](scripts/README.md)

## 🔧 Configuration Details

### Infrastructure Path Requirements

The template assumes your project structure follows this pattern:

```
projects/
├── infrastructure/           ← Shared ADB infrastructure
├── Dartwingers/             ← Flutter projects (2 levels deep)
│   └── your_project/        ← Your project here
├── DavinciDesigner/         ← Multi-tech projects (2 levels deep)  
│   └── flutter-app/         ← Your project here
└── SomeOther/               ← Other project groups
    └── nested/              ← 3 levels deep = '../../../infrastructure'
        └── flutter-app/
```

**Path Adjustment**: If your project is at a different depth, update the path in `.devcontainer/devcontainer.json`:

- 3 levels deep: `../../../infrastructure/mobile/android/adb/scripts/start-adb-if-needed.sh`
- 4 levels deep: `../../../../infrastructure/mobile/android/adb/scripts/start-adb-if-needed.sh`

### Customization Placeholders

Before using, replace these placeholders:

- **`PROJECT_NAME`** in `devcontainer.json` → Your project display name
- **`PROJECT_NAME`** in `docker-compose.yml` → Your container and volume names

## 🎯 Features Included

### Automatic Infrastructure Management
- ✅ Shared ADB server starts automatically when container opens
- ✅ No port conflicts between multiple Flutter projects
- ✅ Connects to Android emulators on Windows host

### Development Tools (Lightweight)
- ✅ **Flutter SDK 3.24.0** (stable channel only)
- ✅ **Minimal Android SDK** (platform-tools for ADB debugging)
- ✅ **Java 17 JDK** (OpenJDK)
- ✅ **Essential tools only**: git, curl, nano, jq, tree, zsh, Oh My Zsh
- ✅ **Pre-configured VS Code extensions** for Flutter/Dart
- ✅ **Optimized for project debugging** - not heavy development
- ✅ **Fast container startup** (~2-3 minutes vs 10+ for FlutterBench)

### VS Code Integration
- ✅ 14 pre-configured tasks for common Flutter operations
- ✅ Debug configurations for app and test debugging
- ✅ Auto-format on save
- ✅ Import organization
- ✅ Flutter-specific file associations

### Performance Optimizations
- ✅ Persistent pub cache volume (faster dependency downloads)
- ✅ Persistent gradle cache volume (faster Android builds)
- ✅ Flutter precache during container creation
- ✅ Optimized Dockerfile layers

## 🚀 Getting Started

1. **Prerequisites**:
   - Shared ADB infrastructure must be set up at `projects/infrastructure/mobile/android/adb/`
   - Docker Desktop running
   - VS Code with Dev Containers extension

2. **First Time Setup**:
   - Use Option A (manual) or Option B (script) above
   - Wait for container build (first time takes ~5-10 minutes)
   - Container will automatically run `flutter doctor` and `adb devices`

3. **Development Workflow**:
   - Start Android emulator on Windows host
   - Open project in VS Code
   - Container auto-starts with ADB connectivity
   - Use Command Palette → Tasks to run Flutter commands
   - Use F5 to debug, or Run/Debug buttons in VS Code

## 🔍 Troubleshooting

### Container Build Issues
```bash
# Clean and rebuild
docker-compose build --no-cache
```

### ADB Connection Issues
```bash
# Inside container terminal
adb devices
# Should show connected emulator

# Or use VS Code task: "🔌 Check ADB Connection"
```

### Infrastructure Path Issues
```bash
# From your project directory, verify path
ls -la ../../infrastructure/mobile/android/adb/scripts/start-adb-if-needed.sh
# Should show the script file
```

### Flutter Doctor Issues
```bash
# Inside container terminal
flutter doctor -v
# Or use VS Code task: "🩺 Flutter Doctor"
```

## 📝 Template Maintenance

This template is maintained in:
- **Source**: `Bench/DevBench/FlutterBench/templates/flutter-devcontainer-template/`
- **Script**: `Bench/DevBench/FlutterBench/scripts/new-flutter-project.sh`

To update all projects with template changes, manually copy updated files or re-run the script.

---

**Happy Flutter Development!** 🎯