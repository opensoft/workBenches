# Code Snippets: VS Code Tasks and Configurations

## Complete tasks.json for Flutter Projects

Copy this file to `.vscode/tasks.json` in each Flutter project:

```json
{
  "version": "2.0.0",
  "tasks": [
    // ========================================
    // ADB Infrastructure Management
    // ========================================
    {
      "label": "🔌 Check ADB Connection",
      "type": "shell",
      "command": "adb devices -l",
      "problemMatcher": [],
      "presentation": {
        "reveal": "always",
        "panel": "shared",
        "focus": false
      },
      "group": {
        "kind": "test",
        "isDefault": false
      }
    },
    {
      "label": "🔄 Restart ADB Server",
      "type": "shell",
      "command": "docker restart shared-adb-server && sleep 2 && adb devices",
      "problemMatcher": [],
      "presentation": {
        "reveal": "always",
        "panel": "shared"
      }
    },
    {
      "label": "📋 View ADB Logs",
      "type": "shell",
      "command": "docker logs -f shared-adb-server",
      "isBackground": true,
      "problemMatcher": {
        "pattern": {
          "regexp": "^(.*)$",
          "file": 1,
          "location": 2,
          "message": 3
        },
        "background": {
          "activeOnStart": true,
          "beginsPattern": ".*",
          "endsPattern": ".*"
        }
      },
      "presentation": {
        "reveal": "always",
        "panel": "dedicated"
      }
    },
    {
      "label": "🚀 Start ADB Infrastructure",
      "type": "shell",
      "command": "${workspaceFolder}/../../infrastructure/mobile/android/adb/scripts/start-adb-if-needed.sh",
      "problemMatcher": [],
      "presentation": {
        "reveal": "always",
        "panel": "shared"
      }
    },
    {
      "label": "🛑 Stop ADB Infrastructure",
      "type": "shell",
      "command": "${workspaceFolder}/../../infrastructure/mobile/android/adb/scripts/stop-adb.sh",
      "problemMatcher": [],
      "presentation": {
        "reveal": "always",
        "panel": "shared"
      }
    },
    {
      "label": "📊 ADB Status Report",
      "type": "shell",
      "command": "${workspaceFolder}/../../infrastructure/mobile/android/adb/scripts/check-adb.sh",
      "problemMatcher": [],
      "presentation": {
        "reveal": "always",
        "panel": "shared"
      }
    },
    
    // ========================================
    // Flutter Development Tasks
    // ========================================
    {
      "label": "🔧 Flutter Doctor",
      "type": "shell",
      "command": "flutter doctor -v",
      "problemMatcher": [],
      "presentation": {
        "reveal": "always",
        "panel": "shared"
      }
    },
    {
      "label": "📦 Flutter Pub Get",
      "type": "shell",
      "command": "flutter pub get",
      "problemMatcher": [],
      "presentation": {
        "reveal": "always",
        "panel": "shared"
      },
      "group": {
        "kind": "build",
        "isDefault": false
      }
    },
    {
      "label": "🧹 Flutter Clean",
      "type": "shell",
      "command": "flutter clean && flutter pub get",
      "problemMatcher": [],
      "presentation": {
        "reveal": "always",
        "panel": "shared"
      }
    },
    {
      "label": "🏗️ Flutter Build APK",
      "type": "shell",
      "command": "flutter build apk --debug",
      "problemMatcher": [],
      "presentation": {
        "reveal": "always",
        "panel": "dedicated"
      },
      "group": {
        "kind": "build",
        "isDefault": true
      }
    },
    {
      "label": "📱 Flutter Run (Debug)",
      "type": "shell",
      "command": "flutter run",
      "problemMatcher": [],
      "isBackground": true,
      "presentation": {
        "reveal": "always",
        "panel": "dedicated"
      }
    },
    
    // ========================================
    // Docker Container Management
    // ========================================
    {
      "label": "🐳 View Container Logs",
      "type": "shell",
      "command": "docker logs -f $(docker ps --filter name=${workspaceFolderBasename}-dev --format '{{.Names}}')",
      "isBackground": true,
      "problemMatcher": [],
      "presentation": {
        "reveal": "always",
        "panel": "dedicated"
      }
    },
    {
      "label": "🔍 Inspect dartnet Network",
      "type": "shell",
      "command": "docker network inspect dartnet --format='Container: {{range .Containers}}{{.Name}} | IP: {{.IPv4Address}}{{println}}{{end}}'",
      "problemMatcher": [],
      "presentation": {
        "reveal": "always",
        "panel": "shared"
      }
    },
    {
      "label": "📋 List All Flutter Containers",
      "type": "shell",
      "command": "docker ps --filter network=dartnet --format 'table {{.Names}}\\t{{.Status}}\\t{{.Ports}}'",
      "problemMatcher": [],
      "presentation": {
        "reveal": "always",
        "panel": "shared"
      }
    },
    
    // ========================================
    // Diagnostic & Troubleshooting
    // ========================================
    {
      "label": "🐛 Debug: Full Environment Check",
      "type": "shell",
      "command": "echo '=== Environment ===' && env | grep -E 'ADB|FLUTTER|DART' && echo '\n=== ADB Devices ===' && adb devices -l && echo '\n=== Docker Containers ===' && docker ps && echo '\n=== dartnet Network ===' && docker network inspect dartnet --format='{{range .Containers}}{{.Name}} {{println}}{{end}}'",
      "problemMatcher": [],
      "presentation": {
        "reveal": "always",
        "panel": "dedicated"
      }
    },
    {
      "label": "🔗 Debug: Test ADB Connection",
      "type": "shell",
      "command": "echo 'Testing ADB connection...' && echo 'ADB_SERVER_SOCKET=' $ADB_SERVER_SOCKET && echo '\nFrom container:' && adb devices -l && echo '\nFrom ADB server:' && docker exec shared-adb-server adb devices -l",
      "problemMatcher": [],
      "presentation": {
        "reveal": "always",
        "panel": "shared"
      }
    },
    {
      "label": "🌐 Debug: Network Connectivity",
      "type": "shell",
      "command": "echo 'Ping ADB server:' && ping -c 3 shared-adb-server && echo '\nResolve ADB server:' && nslookup shared-adb-server",
      "problemMatcher": [],
      "presentation": {
        "reveal": "always",
        "panel": "shared"
      }
    },
    
    // ========================================
    // Quick Actions (Composite Tasks)
    // ========================================
    {
      "label": "⚡ Quick Start: Clean Build & Run",
      "dependsOrder": "sequence",
      "dependsOn": [
        "🧹 Flutter Clean",
        "📦 Flutter Pub Get",
        "🔌 Check ADB Connection",
        "📱 Flutter Run (Debug)"
      ],
      "problemMatcher": []
    },
    {
      "label": "🔄 Full Reset & Restart",
      "dependsOrder": "sequence",
      "dependsOn": [
        "🛑 Stop ADB Infrastructure",
        "🚀 Start ADB Infrastructure",
        "🔌 Check ADB Connection"
      ],
      "problemMatcher": []
    }
  ]
}
```

---

## Complete devcontainer.json Template

Copy this to `.devcontainer/devcontainer.json` in each Flutter project (adjust PROJECT_NAME):

```json
{
  "name": "PROJECT_NAME Flutter Dev",
  "dockerComposeFile": "../docker-compose.yml",
  "service": "flutter-dev",
  "workspaceFolder": "/workspace",

  // ========================================
  // Lifecycle Commands
  // ========================================
  
  // Runs on HOST (Windows) before container creation
  "initializeCommand": {
    "adb": "${localWorkspaceFolder}/../../infrastructure/mobile/android/adb/scripts/start-adb-if-needed.sh"
  },

  // Runs INSIDE container, only once on creation
  "onCreateCommand": {
    "dependencies": "flutter pub get",
    "precache": "flutter precache --android"
  },

  // Runs INSIDE container, every time it starts
  "postStartCommand": {
    "doctor": "flutter doctor",
    "devices": "adb devices"
  },

  // Runs INSIDE container, when VS Code attaches
  "postAttachCommand": "echo '✅ Container ready! ADB Status:' && adb devices",

  // ========================================
  // VS Code Customizations
  // ========================================
  
  "customizations": {
    "vscode": {
      "extensions": [
        // Flutter & Dart
        "Dart-Code.dart-code",
        "Dart-Code.flutter",
        
        // Docker & Containers
        "ms-azuretools.vscode-docker",
        "ms-vscode-remote.remote-containers",
        
        // Git & Version Control
        "mhutchie.git-graph",
        "eamodio.gitlens",
        
        // Code Quality
        "usernamehw.errorlens",
        "streetsidesoftware.code-spell-checker",
        
        // Productivity
        "formulahendry.auto-close-tag",
        "formulahendry.auto-rename-tag",
        "christian-kohler.path-intellisense"
      ],
      
      "settings": {
        // Flutter & Dart
        "dart.flutterSdkPath": "/flutter",
        "dart.previewFlutterUiGuides": true,
        "dart.previewFlutterUiGuidesCustomTracking": true,
        
        // Terminal
        "terminal.integrated.defaultProfile.linux": "bash",
        "terminal.integrated.profiles.linux": {
          "bash": {
            "path": "/bin/bash",
            "icon": "terminal-bash"
          }
        },
        
        // Editor
        "editor.formatOnSave": true,
        "editor.codeActionsOnSave": {
          "source.fixAll": true,
          "source.organizeImports": true
        },
        
        // Files
        "files.watcherExclude": {
          "**/.git/objects/**": true,
          "**/.git/subtree-cache/**": true,
          "**/node_modules/*/**": true,
          "**/.dart_tool/**": true,
          "**/build/**": true
        },
        
        // Git
        "git.autofetch": true,
        "git.confirmSync": false
      }
    }
  },

  // ========================================
  // Container Features
  // ========================================
  
  "features": {
    "ghcr.io/devcontainers/features/git:1": {
      "version": "latest"
    },
    "ghcr.io/devcontainers/features/github-cli:1": {
      "version": "latest"
    }
  },

  // ========================================
  // Port Forwarding
  // ========================================
  
  "forwardPorts": [
    8080,  // Flutter web dev server (if needed)
    35729  // Hot reload port (if needed)
  ],

  // ========================================
  // Remote Settings
  // ========================================
  
  "remoteUser": "root",
  
  // Mounts (if you need additional host folders)
  "mounts": [
    // Uncomment to persist Pub cache across rebuilds
    // "source=flutter-pub-cache,target=/root/.pub-cache,type=volume"
  ]
}
```

---

## Complete docker-compose.yml Template

Copy this to `docker-compose.yml` in each Flutter project (adjust container name):

```yaml
version: '3.8'

services:
  flutter-dev:
    build:
      context: .
      dockerfile: Dockerfile
    
    # Change to your project name: projectname-dev
    container_name: PROJECT_NAME-dev
    
    # Environment variables
    environment:
      # ADB server connection
      - ADB_SERVER_SOCKET=tcp:shared-adb-server:5037
      
      # Flutter/Dart settings
      - PUB_CACHE=/root/.pub-cache
      - FLUTTER_ROOT=/flutter
      
      # Display settings (for GUI apps if needed)
      - DISPLAY=:0
    
    # Network configuration
    networks:
      - dartnet
    
    # Volume mounts
    volumes:
      - .:/workspace
      # Persist pub cache (optional)
      # - flutter-pub-cache:/root/.pub-cache
    
    # Working directory
    working_dir: /workspace
    
    # Keep container running
    command: sleep infinity
    
    # Restart policy
    restart: unless-stopped

# External network (created by infrastructure)
networks:
  dartnet:
    external: true
    name: dartnet

# Optional: Persistent volumes
# volumes:
#   flutter-pub-cache:
#     name: flutter-pub-cache-PROJECT_NAME
```

---

## Complete Dockerfile Template

Copy this to `Dockerfile` in each Flutter project:

```dockerfile
FROM ubuntu:22.04

# Prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    git \
    unzip \
    xz-utils \
    zip \
    libglu1-mesa \
    openjdk-17-jdk \
    android-tools-adb \
    && rm -rf /var/lib/apt/lists/*

# Set up Android SDK environment
ENV ANDROID_SDK_ROOT=/android-sdk
ENV PATH=$PATH:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools

# Install Flutter
ENV FLUTTER_VERSION=3.24.0
ENV FLUTTER_ROOT=/flutter
RUN git clone --depth 1 --branch ${FLUTTER_VERSION} https://github.com/flutter/flutter.git ${FLUTTER_ROOT}
ENV PATH=$PATH:${FLUTTER_ROOT}/bin

# Pre-download Flutter dependencies
RUN flutter precache --android
RUN flutter doctor

# Set working directory
WORKDIR /workspace

# Default command
CMD ["bash"]
```

---

## Shell Script Snippets

### start-adb-if-needed.sh

Already created in main document. Here's enhanced version with logging:

```bash
#!/bin/bash

set -e

CONTAINER_NAME="shared-adb-server"
NETWORK_NAME="dartnet"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="$SCRIPT_DIR/../compose"
LOG_FILE="/tmp/adb-infrastructure.log"

# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "🔍 Checking ADB infrastructure..."

# Check if network exists
if ! docker network inspect $NETWORK_NAME >/dev/null 2>&1; then
    log "📡 Creating network: $NETWORK_NAME"
    docker network create $NETWORK_NAME
    log "✅ Network created: $NETWORK_NAME"
else
    log "✅ Network exists: $NETWORK_NAME"
fi

# Check if ADB server is running
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    log "✅ ADB server already running: $CONTAINER_NAME"
    docker exec $CONTAINER_NAME adb devices 2>/dev/null | tee -a "$LOG_FILE" || true
    exit 0
fi

# Check if container exists but is stopped
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    log "▶️  Starting existing ADB server: $CONTAINER_NAME"
    docker start $CONTAINER_NAME
    sleep 2
else
    log "🚀 Creating and starting ADB server: $CONTAINER_NAME"
    cd "$COMPOSE_DIR"
    docker-compose up -d 2>&1 | tee -a "$LOG_FILE"
    sleep 2
fi

# Wait and verify
log "⏳ Waiting for ADB server to be ready..."
sleep 1

if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    log "✅ ADB server is running"
    docker exec $CONTAINER_NAME adb devices 2>/dev/null | tee -a "$LOG_FILE" || log "⚠️  No devices connected yet"
else
    log "❌ Failed to start ADB server"
    log "📋 Recent logs:"
    docker logs --tail 20 $CONTAINER_NAME 2>&1 | tee -a "$LOG_FILE"
    exit 1
fi

log "✅ ADB infrastructure ready"
```

---

## VS Code Keybindings (Optional)

Add to `.vscode/keybindings.json` or user keybindings:

```json
[
  {
    "key": "ctrl+shift+a ctrl+shift+c",
    "command": "workbench.action.tasks.runTask",
    "args": "🔌 Check ADB Connection"
  },
  {
    "key": "ctrl+shift+a ctrl+shift+r",
    "command": "workbench.action.tasks.runTask",
    "args": "🔄 Restart ADB Server"
  },
  {
    "key": "ctrl+shift+a ctrl+shift+l",
    "command": "workbench.action.tasks.runTask",
    "args": "📋 View ADB Logs"
  },
  {
    "key": "ctrl+shift+f ctrl+shift+r",
    "command": "workbench.action.tasks.runTask",
    "args": "📱 Flutter Run (Debug)"
  },
  {
    "key": "ctrl+shift+f ctrl+shift+d",
    "command": "workbench.action.tasks.runTask",
    "args": "🔧 Flutter Doctor"
  }
]
```

---

## Quick Reference Card

### Common Task Shortcuts

| Task | Command | When to Use |
|------|---------|-------------|
| **🔌 Check ADB** | `Ctrl+Shift+P` → Check ADB | Verify emulator connected |
| **🔄 Restart ADB** | `Ctrl+Shift+P` → Restart ADB | ADB issues, reconnect devices |
| **📋 View Logs** | `Ctrl+Shift+P` → View ADB Logs | Debug ADB problems |
| **🚀 Start Infra** | `Ctrl+Shift+P` → Start ADB | Manual infrastructure start |
| **🛑 Stop Infra** | `Ctrl+Shift+P` → Stop ADB | Clean shutdown |
| **📊 Status Report** | `Ctrl+Shift+P` → ADB Status | Full diagnostic check |
| **⚡ Quick Start** | `Ctrl+Shift+P` → Quick Start | Clean build and run |

### Lifecycle Command Reference

| Command | Location | Runs | Purpose |
|---------|----------|------|---------|
| `initializeCommand` | devcontainer.json | HOST (Windows) | Start ADB infrastructure |
| `onCreateCommand` | devcontainer.json | Container (once) | Initial setup (pub get) |
| `postStartCommand` | devcontainer.json | Container (every start) | Verify environment |
| `postAttachCommand` | devcontainer.json | Container (on attach) | Final checks |

### Path Reference

From any Flutter project to infrastructure:

```
Dartwingers/ledgerlinc/        → ../../infrastructure/
Dartwingers/lablinc/           → ../../infrastructure/
DavinciDesigner/flutter-app/   → ../../infrastructure/
SomeProject/deep/nested/app/   → ../../../../infrastructure/
```

Formula: Count levels from `projects/`, use that many `../`

---

## Testing Your Configuration

### 1. Test Path Resolution

```bash
# From your Flutter project
cd Dartwingers/ledgerlinc
ls -la ../../infrastructure/mobile/android/adb/scripts/start-adb-if-needed.sh
# Should list the file
```

### 2. Test Manual ADB Start

```bash
../../infrastructure/mobile/android/adb/scripts/start-adb-if-needed.sh
# Should start ADB server
```

### 3. Test VS Code Tasks

```bash
# Open project in VS Code
code .
# Press Ctrl+Shift+P
# Type: "Tasks: Run Task"
# Should see all your ADB tasks listed
```

### 4. Test Full Lifecycle

```bash
# Close VS Code
# Reopen project
code Dartwingers/ledgerlinc
# Click "Reopen in Container"
# Watch output - should see:
# - initializeCommand starting ADB
# - Container creation
# - onCreateCommand running
# - postAttachCommand showing devices
```

---

## Troubleshooting Snippets

### Fix: Script Not Executable

```bash
chmod +x infrastructure/mobile/android/adb/scripts/*.sh
```

### Fix: Path Not Found

```bash
# Verify structure
ls -la infrastructure/mobile/android/adb/scripts/
# Should show all .sh files
```

### Fix: ADB Server Not Starting

```bash
# Manual diagnostic
cd infrastructure/mobile/android/adb/compose
docker-compose up
# Watch for errors
```

### Fix: Container Can't Reach ADB

```bash
# From inside container
docker exec -it ledgerlinc-dev bash
ping shared-adb-server
nslookup shared-adb-server
echo $ADB_SERVER_SOCKET
adb devices
```

---

## Template File Locations Summary

```
DevBench/FlutterBench/templates/flutter-devcontainer-template/
├── .devcontainer/
│   └── devcontainer.json       # ← Complete config with all lifecycle hooks
├── .vscode/
│   ├── tasks.json              # ← All ADB and Flutter tasks
│   ├── launch.json             # ← Flutter debug configurations
│   └── settings.json           # ← Editor settings
├── docker-compose.yml          # ← Container definition
├── Dockerfile                  # ← Image with Flutter + ADB client
└── README.md                   # ← Usage instructions
```

Copy these files to new projects and update:
1. Project name in devcontainer.json
2. Container name in docker-compose.yml
3. Path levels (`../../` vs `../../../`) if nested differently
