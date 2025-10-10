# Multi-Project Flutter Infrastructure Architecture
## Shared ADB Container for Flutter Development Across Multiple Projects

---

## Executive Summary

This document outlines the architecture for a **shared infrastructure approach** to manage Android Debug Bridge (ADB) services across multiple Flutter projects within a complex, multi-technology workspace. The solution enables:

- **Single ADB server** serving all Flutter projects across different project groups
- **Automatic infrastructure startup** via VS Code devcontainer lifecycle hooks
- **Zero configuration** for developers opening any Flutter project
- **Scalable architecture** supporting future infrastructure containers (databases, caches, etc.)
- **Clean separation** between project code and shared infrastructure

### Key Benefits

✅ **DRY Principle**: One ADB server, not N servers  
✅ **Port Management**: No 5037 conflicts across projects  
✅ **Developer Experience**: Projects "just work" when opened  
✅ **Maintainability**: Infrastructure updates in one place  
✅ **Extensibility**: Pattern works for other shared services  

### Affected Projects

**Flutter Projects** (using shared ADB):
- Dartwingers: ledgerlinc, lablinc, dartwing
- DavinciDesigner: Flutter components

**Infrastructure Location**:
- `projects/infrastructure/mobile/android/adb/`

---

## Table of Contents

1. [Project Structure](#project-structure)
2. [Infrastructure Architecture](#infrastructure-architecture)
3. [Communication Flow](#communication-flow)
4. [Lifecycle Management](#lifecycle-management)
5. [Implementation Guide](#implementation-guide)
6. [Configuration Templates](#configuration-templates)
7. [Troubleshooting](#troubleshooting)

---

## Project Structure

### Complete Directory Hierarchy

```
projects/
│
├── DevBench/                          # Development workbenches
│   ├── JavaBench/
│   ├── dotNetBench/
│   ├── FlutterBench/                 # Meta-container for Flutter dev
│   └── ...
│
├── Dartwingers/                      # Flutter app suite
│   ├── ledgerlinc/
│   │   ├── .devcontainer/
│   │   │   └── devcontainer.json    # ← Uses infrastructure
│   │   ├── .vscode/
│   │   │   └── tasks.json           # ← ADB lifecycle tasks
│   │   ├── docker-compose.yml
│   │   └── lib/
│   │
│   ├── lablinc/
│   │   ├── .devcontainer/
│   │   │   └── devcontainer.json    # ← Uses infrastructure
│   │   ├── .vscode/
│   │   │   └── tasks.json           # ← ADB lifecycle tasks
│   │   ├── docker-compose.yml
│   │   └── lib/
│   │
│   └── dartwing/
│       ├── .devcontainer/
│       │   └── devcontainer.json    # ← Uses infrastructure
│       ├── .vscode/
│       │   └── tasks.json           # ← ADB lifecycle tasks
│       ├── docker-compose.yml
│       └── lib/
│
├── DavinciDesigner/                  # Multi-tech project
│   ├── flutter-app/
│   │   ├── .devcontainer/
│   │   │   └── devcontainer.json    # ← Uses infrastructure
│   │   ├── .vscode/
│   │   │   └── tasks.json           # ← ADB lifecycle tasks
│   │   └── docker-compose.yml
│   └── java-backend/
│
├── nopSetup/                         # .NET projects
│   ├── nopCommerce-site1/
│   ├── nopCommerce-site2/
│   └── ...
│
└── infrastructure/                   # ← SHARED INFRASTRUCTURE
    ├── mobile/
    │   └── android/
    │       └── adb/
    │           ├── docker/
    │           │   └── Dockerfile
    │           ├── compose/
    │           │   └── docker-compose.yml
    │           └── scripts/
    │               ├── start-adb-if-needed.sh
    │               ├── stop-adb.sh
    │               └── check-adb.sh
    │
    ├── database/                     # Future: shared DB containers
    │   └── postgresql/
    │
    └── cache/                        # Future: shared cache containers
        └── redis/
```

### Infrastructure Folder Structure Detail

```
infrastructure/
└── mobile/
    └── android/
        └── adb/
            ├── docker/
            │   └── Dockerfile              # ADB container image definition
            │
            ├── compose/
            │   └── docker-compose.yml      # ADB service orchestration
            │
            └── scripts/
                ├── start-adb-if-needed.sh  # Idempotent startup script
                ├── stop-adb.sh             # Cleanup script
                └── check-adb.sh            # Health check script
```

---

## Infrastructure Architecture

### High-Level System Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│                      Windows 11 Host                              │
│                                                                   │
│  ┌────────────────────┐         ┌──────────────────────┐        │
│  │ Android Emulator   │         │  Docker Desktop      │        │
│  │ localhost:5555     │         │  (Windows GUI)       │        │
│  └────────────────────┘         └──────────┬───────────┘        │
│           ▲                                 │                    │
│           │                                 │ API calls          │
│           │                                 ▼                    │
│  ┌────────┴───────────────────────────────────────────────────┐ │
│  │                    WSL2 (Linux VM)                          │ │
│  │                                                             │ │
│  │  ┌───────────────────────────────────────────────────┐     │ │
│  │  │         Docker Engine (dockerd)                   │     │ │
│  │  │                                                   │     │ │
│  │  │  ┌─────────────────────────────────────────────┐ │     │ │
│  │  │  │  Shared ADB Container                       │ │     │ │
│  │  │  │  (from infrastructure/mobile/android/adb/)  │ │     │ │
│  │  │  │                                             │ │     │ │
│  │  │  │  - Binds to: 0.0.0.0:5037                  │ │     │ │
│  │  │  │  - Connects to: host:5555 (emulator)       │ │     │ │
│  │  │  │  - Network: dartnet                        │ │     │ │
│  │  │  └──────────────┬──────────────────────────────┘ │     │ │
│  │  │                 │                                │     │ │
│  │  │                 │ port 5037                      │     │ │
│  │  │                 │                                │     │ │
│  │  │  ┌──────────────┴────────────────────────────┐  │     │ │
│  │  │  │         dartnet (Docker Network)          │  │     │ │
│  │  │  │                                            │  │     │ │
│  │  │  │  ┌──────────┐  ┌──────────┐  ┌─────────┐ │  │     │ │
│  │  │  │  │ledgerlinc│  │ lablinc  │  │ dartwing│ │  │     │ │
│  │  │  │  │  -dev    │  │  -dev    │  │  -dev   │ │  │     │ │
│  │  │  │  └──────────┘  └──────────┘  └─────────┘ │  │     │ │
│  │  │  │                                            │  │     │ │
│  │  │  │  ┌────────────────────────┐                │  │     │ │
│  │  │  │  │ davincidesigner-dev    │                │  │     │ │
│  │  │  │  └────────────────────────┘                │  │     │ │
│  │  │  │                                            │  │     │ │
│  │  │  │  All connect to: adb-server:5037          │  │     │ │
│  │  │  └────────────────────────────────────────────┘  │     │ │
│  │  │                                                   │     │ │
│  │  └───────────────────────────────────────────────────┘     │ │
│  │                                                             │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                   │
└───────────────────────────────────────────────────────────────────┘
```

### Network Communication Flow

```
Developer opens ledgerlinc in VS Code
        ↓
initializeCommand runs (on Windows host)
        ↓
Executes: projects/infrastructure/mobile/android/adb/scripts/start-adb-if-needed.sh
        ↓
Script checks: Is shared-adb-server running?
        ↓
    ┌───[NO]────────────────────┐
    │                           │
    ↓                           ↓
Creates dartnet network    Already running,
Starts ADB container      skip creation
    │                           │
    └───────────┬───────────────┘
                ↓
docker-compose up -d in infrastructure/mobile/android/adb/compose/
                ↓
ADB server binds to 0.0.0.0:5037
                ↓
ADB server connects to host.docker.internal:5555 (emulator)
                ↓
ledgerlinc devcontainer starts
                ↓
ledgerlinc container joins dartnet
                ↓
ledgerlinc connects to shared-adb-server:5037
                ↓
postAttachCommand: adb devices (verify connection)
                ↓
✅ Developer ready to code!
```

### Multi-Project Scenario

```
Time: 9:00 AM
Developer opens: Dartwingers/ledgerlinc
    → initializeCommand runs
    → ADB server starts (shared-adb-server)
    → ledgerlinc container joins dartnet
    → ✅ Ready

Time: 9:30 AM
Developer opens: Dartwingers/lablinc (different VS Code window)
    → initializeCommand runs
    → Checks ADB server (already running, skips creation)
    → lablinc container joins dartnet
    → ✅ Ready

Time: 10:00 AM
Developer opens: DavinciDesigner/flutter-app
    → initializeCommand runs
    → Checks ADB server (already running, skips creation)
    → davincidesigner container joins dartnet
    → ✅ Ready

All three containers share the SAME ADB server on port 5037
All three containers see the SAME Android emulator
```

---

## Communication Flow

### Port Usage

#### Port 5037: ADB Client ↔ ADB Server
- **Bound by**: shared-adb-server container (ONE listener)
- **Connected by**: ledgerlinc-dev, lablinc-dev, dartwing-dev, davincidesigner-dev (MANY clients)
- **Purpose**: Control channel for ADB commands

#### Port 5555: ADB Server ↔ Android Emulator
- **Bound by**: Android Emulator (adbd) running in Windows
- **Connected by**: shared-adb-server container
- **Purpose**: Device communication channel

### Request Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│  Developer runs: flutter run                                 │
│  (Inside ledgerlinc-dev container)                          │
└─────────────────────────┬───────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│  Flutter CLI executes: adb devices                          │
│  Environment: ADB_SERVER_SOCKET=tcp:shared-adb-server:5037  │
└─────────────────────────┬───────────────────────────────────┘
                          ↓
            ┌─────────────────────────┐
            │  dartnet DNS Resolution │
            │  shared-adb-server →    │
            │  172.18.0.2:5037        │
            └─────────┬───────────────┘
                      ↓
┌─────────────────────────────────────────────────────────────┐
│  TCP connection: ledgerlinc-dev → 172.18.0.2:5037          │
│  (ADB client connects to ADB server)                        │
└─────────────────────────┬───────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│  ADB Server processes command                               │
│  Forwards to: host.docker.internal:5555                     │
└─────────────────────────┬───────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│  Windows Emulator (adbd) receives command                   │
│  Executes and returns response                              │
└─────────────────────────┬───────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│  Response flows back through same path                      │
│  Emulator → ADB Server → ADB Client → Flutter CLI           │
└─────────────────────────────────────────────────────────────┘
```

---

## Lifecycle Management

### initializeCommand Lifecycle

**Where**: `.devcontainer/devcontainer.json` in each Flutter project  
**When**: Runs on the **HOST** (Windows) before container creation  
**Purpose**: Ensure ADB infrastructure exists

```json
{
  "initializeCommand": {
    "adb": "${localWorkspaceFolder}/../../infrastructure/mobile/android/adb/scripts/start-adb-if-needed.sh"
  }
}
```

### Path Resolution Examples

From `Dartwingers/ledgerlinc/`:
```
${localWorkspaceFolder} = C:\projects\Dartwingers\ledgerlinc
../../ = C:\projects\
infrastructure/mobile/android/adb/scripts/start-adb-if-needed.sh
= C:\projects\infrastructure\mobile\android\adb\scripts\start-adb-if-needed.sh
```

From `DavinciDesigner/flutter-app/`:
```
${localWorkspaceFolder} = C:\projects\DavinciDesigner\flutter-app
../../ = C:\projects\
infrastructure/mobile/android/adb/scripts/start-adb-if-needed.sh
= C:\projects\infrastructure\mobile\android\adb\scripts\start-adb-if-needed.sh
```

### Complete Lifecycle Hooks

```
┌─────────────────────────────────────────────────────────────┐
│  VS Code: Open Folder → Dartwingers/ledgerlinc             │
└─────────────────────────┬───────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│  initializeCommand (HOST - Windows)                         │
│  - Runs: start-adb-if-needed.sh                            │
│  - Checks/starts ADB server                                │
│  - Creates dartnet if needed                               │
└─────────────────────────┬───────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│  Container Creation                                         │
│  - Runs: docker-compose up -d (ledgerlinc)                 │
│  - Joins: dartnet network                                  │
└─────────────────────────┬───────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│  onCreateCommand (INSIDE container, once on first create)   │
│  - flutter pub get                                          │
│  - Pre-download dependencies                               │
└─────────────────────────┬───────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│  postStartCommand (INSIDE container, every start)           │
│  - flutter doctor                                           │
│  - Verify Flutter installation                             │
└─────────────────────────┬───────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│  postAttachCommand (INSIDE container, when VS Code attaches)│
│  - adb devices                                              │
│  - Verify emulator connection                              │
└─────────────────────────┬───────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│  ✅ Developer ready to code                                 │
│  - ADB server running                                       │
│  - Container connected                                      │
│  - Emulator accessible                                      │
└─────────────────────────────────────────────────────────────┘
```

---

## Implementation Guide

### Step 1: Create Infrastructure Folder

```bash
cd projects
mkdir -p infrastructure/mobile/android/adb/{docker,compose,scripts}
```

### Step 2: Create ADB Container Files

**`infrastructure/mobile/android/adb/docker/Dockerfile`**
```dockerfile
FROM alpine:3.18

RUN apk add --no-cache \
    android-tools \
    bash

EXPOSE 5037

CMD ["adb", "-a", "-P", "5037", "nodaemon", "server"]
```

**`infrastructure/mobile/android/adb/compose/docker-compose.yml`**
```yaml
version: '3.8'

services:
  adb-server:
    build: ../docker
    container_name: shared-adb-server
    ports:
      - "5037:5037"
    extra_hosts:
      - "host.docker.internal:host-gateway"
    networks:
      - dartnet
    restart: unless-stopped
    command:
      - |
        adb -a -P 5037 nodaemon server &
        sleep 2
        adb connect host.docker.internal:5555
        wait

networks:
  dartnet:
    name: dartnet
    driver: bridge
```

### Step 3: Create Management Scripts

**`infrastructure/mobile/android/adb/scripts/start-adb-if-needed.sh`**
```bash
#!/bin/bash

set -e

CONTAINER_NAME="shared-adb-server"
NETWORK_NAME="dartnet"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="$SCRIPT_DIR/../compose"

echo "🔍 Checking ADB infrastructure..."

# Check if network exists
if ! docker network inspect $NETWORK_NAME >/dev/null 2>&1; then
    echo "📡 Creating network: $NETWORK_NAME"
    docker network create $NETWORK_NAME
else
    echo "✅ Network $NETWORK_NAME exists"
fi

# Check if ADB server is running
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "✅ ADB server already running: $CONTAINER_NAME"
    exit 0
fi

# Check if container exists but is stopped
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "▶️  Starting existing ADB server: $CONTAINER_NAME"
    docker start $CONTAINER_NAME
else
    echo "🚀 Creating and starting ADB server: $CONTAINER_NAME"
    cd "$COMPOSE_DIR"
    docker-compose up -d
fi

echo "⏳ Waiting for ADB server..."
sleep 2

if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "✅ ADB server is running"
else
    echo "❌ Failed to start ADB server"
    exit 1
fi
```

**`infrastructure/mobile/android/adb/scripts/stop-adb.sh`**
```bash
#!/bin/bash

CONTAINER_NAME="shared-adb-server"

if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "🛑 Stopping ADB server: $CONTAINER_NAME"
    docker stop $CONTAINER_NAME
    echo "✅ ADB server stopped"
else
    echo "ℹ️  ADB server not running"
fi
```

**`infrastructure/mobile/android/adb/scripts/check-adb.sh`**
```bash
#!/bin/bash

CONTAINER_NAME="shared-adb-server"

echo "📊 ADB Infrastructure Status"
echo "─────────────────────────────"

# Check container status
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "✅ Container: Running"
    docker exec $CONTAINER_NAME adb devices
else
    echo "❌ Container: Not running"
fi

# Check network
if docker network inspect dartnet >/dev/null 2>&1; then
    echo "✅ Network: dartnet exists"
    echo "   Connected containers:"
    docker network inspect dartnet --format='{{range .Containers}}   - {{.Name}} ({{.IPv4Address}}){{println}}{{end}}'
else
    echo "❌ Network: dartnet does not exist"
fi
```

Make scripts executable:
```bash
chmod +x infrastructure/mobile/android/adb/scripts/*.sh
```

### Step 4: Configure Each Flutter Project

For each Flutter project (`ledgerlinc`, `lablinc`, `dartwing`, `DavinciDesigner/flutter-app`):

**`.devcontainer/devcontainer.json`**
```json
{
  "name": "LedgerLinc Flutter Dev",
  "dockerComposeFile": "../docker-compose.yml",
  "service": "flutter-dev",
  "workspaceFolder": "/workspace",

  "initializeCommand": {
    "adb": "${localWorkspaceFolder}/../../infrastructure/mobile/android/adb/scripts/start-adb-if-needed.sh"
  },

  "onCreateCommand": "flutter pub get",
  "postStartCommand": "flutter doctor",
  "postAttachCommand": "adb devices",

  "customizations": {
    "vscode": {
      "extensions": [
        "Dart-Code.dart-code",
        "Dart-Code.flutter",
        "ms-azuretools.vscode-docker"
      ],
      "settings": {
        "dart.flutterSdkPath": "/flutter"
      }
    }
  }
}
```

**`docker-compose.yml`**
```yaml
version: '3.8'

services:
  flutter-dev:
    build: .
    container_name: ledgerlinc-dev
    environment:
      - ADB_SERVER_SOCKET=tcp:shared-adb-server:5037
    networks:
      - dartnet
    volumes:
      - .:/workspace
    command: sleep infinity

networks:
  dartnet:
    external: true
    name: dartnet
```

### Step 5: Add VS Code Tasks

**`.vscode/tasks.json`** (same for all Flutter projects)
```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "🔌 Check ADB Connection",
      "type": "shell",
      "command": "adb devices -l",
      "problemMatcher": [],
      "presentation": {
        "reveal": "always",
        "panel": "shared"
      }
    },
    {
      "label": "🔄 Restart ADB Server",
      "type": "shell",
      "command": "docker restart shared-adb-server && sleep 2 && adb devices",
      "problemMatcher": []
    },
    {
      "label": "📋 View ADB Logs",
      "type": "shell",
      "command": "docker logs -f shared-adb-server",
      "isBackground": true,
      "problemMatcher": []
    },
    {
      "label": "🚀 Start ADB Infrastructure",
      "type": "shell",
      "command": "${workspaceFolder}/../../infrastructure/mobile/android/adb/scripts/start-adb-if-needed.sh",
      "problemMatcher": []
    },
    {
      "label": "🛑 Stop ADB Infrastructure",
      "type": "shell",
      "command": "${workspaceFolder}/../../infrastructure/mobile/android/adb/scripts/stop-adb.sh",
      "problemMatcher": []
    },
    {
      "label": "📊 ADB Status Report",
      "type": "shell",
      "command": "${workspaceFolder}/../../infrastructure/mobile/android/adb/scripts/check-adb.sh",
      "problemMatcher": []
    }
  ]
}
```

---

## Configuration Templates

### Template for New Flutter Projects

Create reusable templates:

**`DevBench/FlutterBench/templates/flutter-project-template/.devcontainer/devcontainer.json`**
```json
{
  "name": "PROJECT_NAME Flutter Dev",
  "dockerComposeFile": "../docker-compose.yml",
  "service": "flutter-dev",
  "workspaceFolder": "/workspace",

  "initializeCommand": {
    "adb": "${localWorkspaceFolder}/../../infrastructure/mobile/android/adb/scripts/start-adb-if-needed.sh"
  },

  "onCreateCommand": "flutter pub get",
  "postStartCommand": "flutter doctor",
  "postAttachCommand": "adb devices",

  "customizations": {
    "vscode": {
      "extensions": [
        "Dart-Code.dart-code",
        "Dart-Code.flutter",
        "ms-azuretools.vscode-docker"
      ],
      "settings": {
        "dart.flutterSdkPath": "/flutter"
      }
    }
  }
}
```

**To create a new Flutter project:**
```bash
cd Dartwingers
flutter create mynewapp
cd mynewapp
cp -r ../DevBench/FlutterBench/templates/flutter-project-template/.devcontainer .
cp -r ../DevBench/FlutterBench/templates/flutter-project-template/.vscode .
# Edit .devcontainer/devcontainer.json: Replace PROJECT_NAME
# Edit docker-compose.yml: Set container name to mynewapp-dev
```

---

## Troubleshooting

### Issue: ADB server not starting

**Symptoms**: Container starts but ADB not accessible

**Debug Steps**:
```bash
# Check container status
docker ps -a | grep shared-adb-server

# View logs
docker logs shared-adb-server

# Check network
docker network inspect dartnet

# Manually test connection
docker exec shared-adb-server adb devices
```

### Issue: Port 5037 already in use

**Cause**: Another ADB server running on host

**Solution**:
```bash
# On Windows, stop any ADB servers
adb kill-server

# Restart infrastructure
cd projects/infrastructure/mobile/android/adb/scripts
./stop-adb.sh
./start-adb-if-needed.sh
```

### Issue: Cannot reach emulator from container

**Symptoms**: `adb devices` shows no devices

**Debug Steps**:
```bash
# Verify emulator is running and accessible
# From Windows
adb devices

# From inside container
docker exec shared-adb-server ping host.docker.internal

# Manually connect
docker exec shared-adb-server adb connect host.docker.internal:5555
```

### Issue: Path resolution fails in initializeCommand

**Symptoms**: Script not found error

**Debug**:
```bash
# Verify path from project
cd Dartwingers/ledgerlinc
ls ../../infrastructure/mobile/android/adb/scripts/start-adb-if-needed.sh

# Check if scripts are executable
ls -la ../../infrastructure/mobile/android/adb/scripts/
```

**Fix**:
```bash
chmod +x infrastructure/mobile/android/adb/scripts/*.sh
```

---

## Summary

### Architecture Highlights

✅ **Centralized Infrastructure**: Single ADB server at `projects/infrastructure/mobile/android/adb/`  
✅ **Automatic Lifecycle**: `initializeCommand` ensures infrastructure before container starts  
✅ **Path Independence**: Relative paths work from any project depth  
✅ **Zero Configuration**: Developers just open projects, everything works  
✅ **Extensible**: Pattern supports future infrastructure (databases, caches, etc.)  

### Project Coverage

**Currently Configured**:
- Dartwingers/ledgerlinc ✅
- Dartwingers/lablinc ✅
- Dartwingers/dartwing ✅
- DavinciDesigner/flutter-app ✅

**Future Infrastructure**:
- `infrastructure/database/postgresql/`
- `infrastructure/cache/redis/`
- `infrastructure/mobile/ios/` (when needed)

### Developer Workflow

```
1. Open any Flutter project in VS Code
2. initializeCommand checks/starts ADB automatically
3. Container starts and joins dartnet
4. Developer codes, deploys to emulator
5. All projects share same infrastructure
```

**That's it!** No manual infrastructure management needed.

---

## Appendix: Path Resolution Reference

### From Dartwingers Projects

```
Dartwingers/
├── ledgerlinc/
│   └── ${localWorkspaceFolder}/../../infrastructure/
│       = projects/infrastructure/
│
├── lablinc/
│   └── ${localWorkspaceFolder}/../../infrastructure/
│       = projects/infrastructure/
│
└── dartwing/
    └── ${localWorkspaceFolder}/../../infrastructure/
        = projects/infrastructure/
```

### From DavinciDesigner

```
DavinciDesigner/
└── flutter-app/
    └── ${localWorkspaceFolder}/../../infrastructure/
        = projects/infrastructure/
```

### From Nested Projects (if any)

```
SomeProject/
└── mobile/
    └── flutter-app/
        └── ${localWorkspaceFolder}/../../../infrastructure/
            = projects/infrastructure/
```

**Pattern**: Count directory levels from project to `projects/`, then add `infrastructure/`

---

*This architecture provides a scalable, maintainable solution for managing shared infrastructure across multiple Flutter projects in a complex multi-technology workspace.*
