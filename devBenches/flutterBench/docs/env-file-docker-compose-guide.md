# Environment Variables with Docker Compose
## Complete Guide for Flutter DevContainers

---

## Table of Contents

1. [Overview](#overview)
2. [How .env Files Work](#how-env-files-work)
3. [Complete Lifecycle](#complete-lifecycle)
4. [Variable Types & Availability](#variable-types--availability)
5. [Template Setup](#template-setup)
6. [Configuration Examples](#configuration-examples)
7. [Debugging & Troubleshooting](#debugging--troubleshooting)
8. [Best Practices](#best-practices)
9. [Common Pitfalls](#common-pitfalls)

---

## Overview

### ⚙️ Centralized Configuration Architecture

**Key Philosophy**: The `.env` file is now the **single source of truth** for ALL project and user-specific configuration.

#### What This Means:
- 🚫 **Template files are NEVER modified** - `devcontainer.json`, `docker-compose.yml`, etc. remain untouched
- ✅ **All customization via environment variables** - container names, user settings, versions, ports
- ✅ **Perfect template reusability** - same template works for all projects
- ✅ **Conflict-free updates** - template improvements never conflict with your settings

### What is a .env File?

A `.env` file is a simple text file that contains environment variables used by Docker Compose to configure your containers. In our architecture, it serves as the **complete configuration center** for your project. It allows you to:

- ✅ Centralize ALL project-specific settings in one place
- ✅ Separate configuration from template code
- ✅ Use different values per project without modifying templates
- ✅ Keep sensitive data out of version control
- ✅ Make configuration explicit and readable
- ✅ Customize container names, versions, and behavior per project

### Why Use .env Files for Flutter DevContainers?

**Problem Without .env**:
```yaml
# Hard-coded values everywhere
services:
  flutter-dev:
    container_name: ledgerlinc-dev    # ← Hard to reuse
    build:
      args:
        USER_UID: 1000                 # ← Hard-coded
        FLUTTER_VERSION: 3.24.0        # ← Hard-coded
```

**Solution With .env**:
```yaml
# Flexible, reusable configuration
services:
  flutter-dev:
    container_name: ${PROJECT_NAME}-dev  # ← From .env
    build:
      args:
        USER_UID: ${USER_UID}            # ← From .env
        FLUTTER_VERSION: ${FLUTTER_VERSION}  # ← From .env
```

**Benefits**:
- Change project name in one place
- Different Flutter versions per project
- Template can be copied and customized easily

---

## How .env Files Work

### Automatic Discovery

Docker Compose **automatically** looks for a `.env` file:

```
Project Directory/
├── .env                    ← Docker Compose finds this automatically
├── docker-compose.yml      ← Uses variables from .env
└── Dockerfile
```

**Location Rules**:
1. Must be named exactly `.env` (not `.env.txt` or `env`)
2. Must be in the same directory as `docker-compose.yml`
3. Is read automatically by ALL `docker-compose` commands

### Loading Process

```
┌─────────────────────────────────────────────────────────────┐
│  Developer runs: docker-compose up                          │
└─────────────────────────┬───────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│  Docker Compose automatically reads .env file               │
│  Location: Same directory as docker-compose.yml             │
└─────────────────────────┬───────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│  Loads all KEY=VALUE pairs into memory                      │
└─────────────────────────┬───────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│  Parses docker-compose.yml                                  │
│  Replaces ${VARIABLE_NAME} with values from .env            │
└─────────────────────────┬───────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│  Executes commands with resolved configuration              │
└─────────────────────────────────────────────────────────────┘
```

### Variable Substitution

**Before (in docker-compose.yml)**:
```yaml
services:
  flutter-dev:
    container_name: ${PROJECT_NAME}-dev
    build:
      args:
        USER_UID: ${USER_UID}
```

**What .env contains**:
```bash
PROJECT_NAME=ledgerlinc
USER_UID=1000
```

**After substitution (what Docker Compose uses)**:
```yaml
services:
  flutter-dev:
    container_name: ledgerlinc-dev
    build:
      args:
        USER_UID: 1000
```

---

## Complete Lifecycle

### Step-by-Step Execution Flow

#### Step 1: VS Code Opens Project

```
User: Opens Dartwingers/ledgerlinc in VS Code
Action: Clicks "Reopen in Container"
```

#### Step 2: initializeCommand (Before Docker)

```
┌─────────────────────────────────────────────────────────────┐
│  Runs: start-adb-if-needed.sh                              │
│  When: On HOST (Windows/WSL2)                               │
│  Note: Does NOT use .env (runs before Docker Compose)      │
└─────────────────────────────────────────────────────────────┘
```

#### Step 3: Docker Compose Starts

```
┌─────────────────────────────────────────────────────────────┐
│  VS Code executes:                                          │
│  $ cd Dartwingers/ledgerlinc                                │
│  $ docker-compose -f docker-compose.yml up -d               │
└─────────────────────────┬───────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│  Docker Compose reads:                                      │
│  1. ./docker-compose.yml                                    │
│  2. ./.env (automatically, if exists)                       │
└─────────────────────────┬───────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│  Loads .env variables:                                      │
│  PROJECT_NAME=ledgerlinc                                    │
│  USER_NAME=developer                                        │
│  USER_UID=1000                                              │
│  USER_GID=1000                                              │
│  FLUTTER_VERSION=3.24.0                                     │
└─────────────────────────┬───────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│  Substitutes all ${VARIABLES} in docker-compose.yml:        │
│  container_name: ledgerlinc-dev                             │
│  user: "1000:1000"                                          │
│  args: USER_UID=1000, USER_GID=1000, etc.                   │
└─────────────────────────┬───────────────────────────────────┘
                          ↓
                    ┌─────┴─────┐
                    │ Image     │
                    │ exists?   │
                    └─────┬─────┘
                          │
        ┌─────────────────┼─────────────────┐
        │ NO                                │ YES
        ↓                                   ↓
┌───────────────────────┐         ┌────────────────────────┐
│ BUILD PHASE           │         │ Skip build             │
└───────┬───────────────┘         └────────┬───────────────┘
        │                                   │
        ↓                                   │
┌───────────────────────────────────────────┴─────────────────┐
│  Pass build args to Dockerfile:                             │
│  - USER_NAME=developer                                      │
│  - USER_UID=1000                                            │
│  - USER_GID=1000                                            │
│  - FLUTTER_VERSION=3.24.0                                   │
└─────────────────────────┬───────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│  Dockerfile receives ARGs:                                  │
│                                                             │
│  ARG USER_UID=1000      # ← From .env via compose           │
│  ARG FLUTTER_VERSION    # ← From .env via compose           │
│                                                             │
│  RUN useradd -u ${USER_UID} ...                             │
│  RUN git clone --branch ${FLUTTER_VERSION} ...              │
└─────────────────────────┬───────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│  Image built with configuration baked in                    │
│  ARG variables are now GONE (not in image)                  │
└─────────────────────────┬───────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│  RUN PHASE: Create and start container                      │
│  - Name: ledgerlinc-dev                                     │
│  - User: 1000:1000                                          │
│  - Environment: ADB_SERVER_SOCKET=tcp:shared-adb-server:5037│
│  - Network: dartnet                                         │
│  - Volumes: .:/workspace                                    │
└─────────────────────────┬───────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│  Container running, ready for VS Code to attach             │
└─────────────────────────────────────────────────────────────┘
```

#### Step 4: Post-Start Commands

```
┌─────────────────────────────────────────────────────────────┐
│  VS Code attaches to container                              │
│  Runs: onCreateCommand, postStartCommand, postAttachCommand │
│  Note: .env values already applied, not re-read             │
└─────────────────────────────────────────────────────────────┘
```

---

## Variable Types & Availability

### Three Types of Variables

#### 1. Build Arguments (ARG) - Build Time Only

**Where**: Dockerfile  
**When**: During `docker build`  
**Lifetime**: Gone after build completes  

```dockerfile
ARG USER_UID=1000
ARG FLUTTER_VERSION=3.24.0

# Available here during build
RUN useradd -u ${USER_UID} developer
RUN git clone --branch ${FLUTTER_VERSION} https://github.com/flutter/flutter.git

# NOT available in running container!
```

**Use for**: Installing software, creating users, setting up environment

#### 2. Environment Variables (ENV) - Runtime

**Where**: Dockerfile or docker-compose.yml  
**When**: In running container  
**Lifetime**: Available as long as container runs  

**In Dockerfile**:
```dockerfile
ENV FLUTTER_ROOT=/flutter
ENV PATH=$PATH:${FLUTTER_ROOT}/bin

# Available in running container
```

**In docker-compose.yml**:
```yaml
services:
  flutter-dev:
    environment:
      - ADB_SERVER_SOCKET=tcp:shared-adb-server:5037
      - MY_CONFIG=${MY_VALUE}  # From .env
```

**Use for**: Configuration that apps need at runtime

#### 3. Compose Variables - Compose Configuration

**Where**: docker-compose.yml  
**When**: While parsing compose file  
**Lifetime**: Used to configure container, not passed to container  

```yaml
services:
  flutter-dev:
    container_name: ${PROJECT_NAME}-dev  # ← Configures container name
    user: "${USER_UID}:${USER_GID}"      # ← Configures user
```

### Availability Timeline

```
┌────────────────────────────────────────────────────────────────┐
│                    VARIABLE LIFECYCLE                          │
├────────────────────────────────────────────────────────────────┤
│                                                                │
│  .env file           ●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●      │
│  (disk file)         Read once                          Done   │
│                      ↓                                         │
│                                                                │
│  Compose parsing     ●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━●      │
│  Variables           ${VAR} → value                      Done   │
│                      ↓                                         │
│                                                                │
│  Build Phase                                                   │
│  ARG variables       ●━━━━━━━━━━●                             │
│                      Available    Gone                         │
│                      ↓                                         │
│                                                                │
│  Container Running                                             │
│  ENV variables       ●━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━→ │
│                      Available forever                         │
│                                                                │
└────────────────────────────────────────────────────────────────┘
```

### Availability Matrix

| Variable Type | .env File | docker-compose.yml | Dockerfile Build | Running Container |
|---------------|-----------|-------------------|------------------|-------------------|
| **ARG** | ✅ Defined | ✅ Passed as arg | ✅ Available | ❌ Gone |
| **ENV (Dockerfile)** | ✅ Via ARG | ✅ Via arg | ✅ Available | ✅ Available |
| **ENV (compose)** | ✅ Defined | ✅ Set directly | ❌ N/A | ✅ Available |
| **Compose config** | ✅ Defined | ✅ Substituted | ❌ N/A | ❌ Used for config only |

---

## Template Setup

### Directory Structure

```
DevBench/FlutterBench/templates/flutter-devcontainer-template/
├── .devcontainer/
│   ├── devcontainer.json
│   ├── docker-compose.yml       # Uses ${VARIABLES}
│   ├── docker-compose.override.yml
│   ├── Dockerfile               # Receives ARGs
│   ├── .env.base                # Template (checked into git)
│   ├── .env                     # Created from .env.base (NOT in git)
│   ├── docs/                    # Documentation
│   ├── scripts/                 # Startup and helper scripts
│   └── adb-service/             # ADB service configuration
├── .vscode/
│   └── tasks.json
├── .github/                     # GitHub workflows
├── .gitignore                   # Excludes .env
├── scripts/                     # Project-level scripts
├── README.md
└── WARP.md
```

### Template Files

#### `.env.example` (or `.env.base` in template)

```bash
# ====================================
# Flutter DevContainer Base Configuration
# Version: 2.0.0
# Template: flutter-devcontainer-2.0.0
# Architecture: Centralized Configuration
# ====================================
# This is the base configuration template for Flutter DevContainer projects
# Copy this file to .env and customize for your project
# IMPORTANT: Never commit .env to git - it may contain sensitive information

# ====================================
# Project Configuration
# ====================================
# PROJECT_NAME: Used for container name, volume names, and identification
# Must be unique across all projects on this machine
# Examples: ledgerlinc, lablinc, dartwing, davincidesigner
PROJECT_NAME=myproject

# APP_CONTAINER_SUFFIX: Suffix for app container name
# Default: app (results in PROJECT_NAME-app)
APP_CONTAINER_SUFFIX=app

# COMPOSE_PROJECT_NAME: Docker Compose stack name (groups containers in Docker Desktop)
# Values: dartwingers (for dartwingers projects), flutter (for other Flutter projects)
# This is auto-detected based on parent folder name
COMPOSE_PROJECT_NAME=flutter

# ====================================
# User Configuration
# ====================================
# These should match your host user for proper file permissions
# Run 'id' in your terminal to check your current values

# USER_NAME: Username inside the container (should match host user)
USER_NAME=$(whoami)

# USER_UID: User ID - should match your host UID for file permission consistency
# Run 'id -u' to check your UID
USER_UID=$(id -u)

# USER_GID: Group ID - should match your host GID for file permission consistency  
# Run 'id -g' to check your GID
USER_GID=$(id -g)

# ====================================
# Flutter Configuration
# ====================================
# FLUTTER_VERSION: Flutter SDK version to install
# Examples: 3.27.0, 3.24.0, stable, beta, dev
# Note: Using 'stable' to get the latest stable Flutter with recent Dart SDK
# Specific versions: Flutter 3.27+ includes Dart 3.6+, need 3.7+ for mobile_scanner ^7.0
FLUTTER_VERSION=stable

# ====================================
# Container Resources (Optional)
# ====================================
# CONTAINER_MEMORY: Memory limit for the container
# Examples: 2g, 4g, 8g, 512m
# Default: 4g (4 gigabytes)
CONTAINER_MEMORY=4g

# CONTAINER_CPUS: CPU limit for the container
# Examples: 1, 2, 4, 0.5
# Default: 2 cores
CONTAINER_CPUS=2

# ====================================
# ADB Configuration
# ====================================
# ADB_SERVER_HOST: Hostname of shared ADB server
# Default: shared-adb-server (from shared infrastructure)
ADB_SERVER_HOST=shared-adb-server

# ADB_SERVER_PORT: Port of shared ADB server
# Default: 5037 (standard ADB port)
ADB_SERVER_PORT=5037

# ADB_INFRASTRUCTURE_PROJECT_NAME: Docker stack name for ADB infrastructure
# Values: dartwingers, infrastructure, shared-adb-infrastructure, custom
# This controls which Docker stack the shared ADB server runs under
# Default: infrastructure (centralized infrastructure stack)
ADB_INFRASTRUCTURE_PROJECT_NAME=infrastructure

# ====================================
# Development Environment (Optional)
# ====================================
# WORKSPACE_PATH: Path inside container where code is mounted
# Default: /workspace
WORKSPACE_PATH=/workspace

# FLUTTER_PUB_CACHE: Path for Flutter pub cache inside container
# Updated to use correct user home directory
FLUTTER_PUB_CACHE=/home/$(whoami)/.pub-cache

# ANDROID_HOME: Android SDK location inside container
# Updated to use correct user home directory
ANDROID_HOME=/home/$(whoami)/android-sdk

# ====================================
# Shell Configuration (Built-in)
# ====================================
# The devcontainer is configured to use zsh as the default shell:
# - Container environment variable: SHELL=/bin/zsh
# - VS Code terminal settings force zsh for all terminal types
# - Bash profile override redirects bash calls to zsh
# - User shell is explicitly set to zsh via chsh
# This ensures consistent zsh experience across all terminal usage

# ====================================
# Network Configuration (Advanced)
# ====================================
# NETWORK_NAME: Docker network name for shared infrastructure
# Default: dartnet (created by shared infrastructure)
NETWORK_NAME=dartnet

# ====================================
# Debugging & Development (Optional)
# ====================================
# DEBUG_MODE: Enable verbose output and debugging tools
# Values: true, false
# Default: false
DEBUG_MODE=false

# HOT_RELOAD_PORT: Port for Flutter hot reload
# Default: 8080
HOT_RELOAD_PORT=8080

# DEVTOOLS_PORT: Port for Flutter DevTools
# Default: 9100
DEVTOOLS_PORT=9100

# ====================================
# .NET Service Configuration (Dartwingers Only)
# ====================================
# SERVICE_CONTAINER_SUFFIX: Suffix for service container name
# Default: service (results in PROJECT_NAME-service)
# For Dartwing projects: gateway (results in PROJECT_NAME-gateway)
SERVICE_CONTAINER_SUFFIX=service

# SERVICE_PORT: Port for .NET Web API service
# Default: 5000
SERVICE_PORT=5000

# SERVICE_DEBUG_PORT: Port for .NET HTTPS debugging
# Default: 5001
SERVICE_DEBUG_PORT=5001

# SERVICE_MEMORY: Memory limit for .NET service container
# Default: 2g
SERVICE_MEMORY=2g

# SERVICE_CPUS: CPU limit for .NET service container
# Default: 1
SERVICE_CPUS=1
```

#### `docker-compose.yml`

```yaml
# ====================================
# Flutter DevContainer Docker Compose Configuration
# Version: 2.0.1
# Template: flutter-devcontainer-2.0.1
# Architecture: Centralized Configuration (.env only)
# ====================================
# Compose project name for Docker Desktop grouping (set in .env)
# This groups all containers under the same stack name
name: ${COMPOSE_PROJECT_NAME:-flutter}

services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
      args:
        # Build-time arguments from .env with readable defaults
        USER_NAME: ${USER_NAME:-vscode}
        USER_UID: ${USER_UID:-1000}
        USER_GID: ${USER_GID:-1000}
        FLUTTER_VERSION: ${FLUTTER_VERSION:-3.24.0}
        ANDROID_HOME: ${ANDROID_HOME:-/home/vscode/android-sdk}
        DEBUG_MODE: ${DEBUG_MODE:-false}
    
    # Container configuration from .env
    container_name: ${PROJECT_NAME:-Flutter-Dev}-${APP_CONTAINER_SUFFIX:-app}
    
    # Labels for devcontainer metadata
    labels:
      - "devcontainer.metadata.project_name=${PROJECT_NAME:-Flutter-Dev}"
    
    # Run as user specified in .env with defaults
    user: "${USER_UID:-1000}:${USER_GID:-1000}"
    
    # Runtime environment variables
    environment:
      - PROJECT_NAME=${PROJECT_NAME:-Flutter-Dev}
      - ADB_SERVER_SOCKET=tcp:${ADB_SERVER_HOST:-shared-adb-server}:${ADB_SERVER_PORT:-5037}
      - FLUTTER_VERSION=${FLUTTER_VERSION:-3.24.0}
      - ANDROID_HOME=${ANDROID_HOME:-/home/${USER_NAME:-vscode}/android-sdk}
      - FLUTTER_PUB_CACHE=${FLUTTER_PUB_CACHE:-/home/${USER_NAME:-vscode}/.pub-cache}
      - DEBUG_MODE=${DEBUG_MODE:-false}
    
    # Network configuration
    networks:
      - dartnet
    
    # Volume mounts
    volumes:
      - ../:${WORKSPACE_PATH:-/workspace}
      # Persist pub cache per project
      - flutter-pub-cache:${FLUTTER_PUB_CACHE:-/home/${USER_NAME:-vscode}/.pub-cache}
      # Persist gradle cache per project
      - flutter-gradle-cache:/home/${USER_NAME:-vscode}/.gradle
    
    # Port mappings for development
    ports:
      - "${HOT_RELOAD_PORT:-8080}:8080"     # Hot reload
      - "${DEVTOOLS_PORT:-9100}:9100"       # Flutter DevTools
    
    # Resource limits (optional)
    deploy:
      resources:
        limits:
          memory: ${CONTAINER_MEMORY:-4g}
          cpus: '${CONTAINER_CPUS:-2}'
    
    # Working directory
    working_dir: ${WORKSPACE_PATH:-/workspace}
    
    # Keep container running
    command: sleep infinity
    
    # Restart policy
    restart: unless-stopped

# External network (managed by shared infrastructure)
networks:
  dartnet:
    external: true
    name: ${NETWORK_NAME:-dartnet}

# Named volumes for caching
# Note: Volume keys cannot use variable substitution, but names can
volumes:
  flutter-pub-cache:
    name: flutter-pub-cache-${PROJECT_NAME:-myproject}
  flutter-gradle-cache:
    name: flutter-gradle-cache-${PROJECT_NAME:-myproject}
```

#### `Dockerfile`

```dockerfile
FROM ubuntu:22.04

# ====================================
# Build Arguments (from .env via docker-compose)
# ====================================
ARG USER_NAME=developer
ARG USER_UID=1000
ARG USER_GID=1000
ARG FLUTTER_VERSION=3.24.0

# Prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# ====================================
# System Dependencies
# ====================================
RUN apt-get update && apt-get install -y \
    # Essential build tools
    curl \
    git \
    unzip \
    xz-utils \
    zip \
    wget \
    # Flutter dependencies
    libglu1-mesa \
    # Java for Android development
    openjdk-17-jdk \
    # ADB client
    android-tools-adb \
    # User utilities
    sudo \
    # Helpful tools
    vim \
    nano \
    && rm -rf /var/lib/apt/lists/*

# ====================================
# Create User
# ====================================
# Create group and user with specific UID/GID for file permission matching
RUN groupadd -g ${USER_GID} ${USER_NAME} 2>/dev/null || true && \
    useradd -m -u ${USER_UID} -g ${USER_GID} -s /bin/bash ${USER_NAME} 2>/dev/null || true && \
    echo "${USER_NAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# ====================================
# Install Flutter (as user)
# ====================================
USER ${USER_NAME}
WORKDIR /home/${USER_NAME}

# Clone Flutter at specified version
ENV FLUTTER_ROOT=/home/${USER_NAME}/flutter
RUN git clone --depth 1 --branch ${FLUTTER_VERSION} \
    https://github.com/flutter/flutter.git ${FLUTTER_ROOT}

# Add Flutter to PATH
ENV PATH=$PATH:${FLUTTER_ROOT}/bin

# Pre-download Flutter dependencies and verify installation
RUN flutter precache --android && \
    flutter config --no-analytics && \
    flutter doctor

# ====================================
# Setup Workspace
# ====================================
WORKDIR /workspace

CMD ["bash"]
```

#### `.gitignore`

```gitignore
# Environment variables (contains user-specific and potentially sensitive info)
.env

# Flutter
.dart_tool/
.flutter-plugins
.flutter-plugins-dependencies
.packages
.pub-cache/
.pub/
build/

# IDE
.vscode/
.idea/
*.swp
*.swo
*~

# Logs
*.log

# OS
.DS_Store
Thumbs.db
```

---

## Configuration Examples

### Example 1: Standard Configuration

**Project**: `Dartwingers/ledgerlinc`

**`.env`**
```bash
PROJECT_NAME=ledgerlinc
USER_NAME=developer
USER_UID=1000
USER_GID=1000
FLUTTER_VERSION=3.24.0
```

**Result**:
- Container name: `ledgerlinc-dev`
- User: `developer` (UID 1000, GID 1000)
- Flutter: version 3.24.0
- Pub cache: `flutter-pub-cache-ledgerlinc`

### Example 2: Different Flutter Version

**Project**: `Dartwingers/lablinc`

**`.env`**
```bash
PROJECT_NAME=lablinc
USER_NAME=developer
USER_UID=1000
USER_GID=1000
FLUTTER_VERSION=3.19.0  # ← Older version for compatibility
```

**Result**:
- Container name: `lablinc-dev`
- Flutter: version 3.19.0 (different from ledgerlinc!)
- Both projects run independently

### Example 3: Custom User Configuration

**Project**: `DavinciDesigner/flutter-app`

**`.env`**
```bash
PROJECT_NAME=davincidesigner
USER_NAME=davinci  # ← Custom username
USER_UID=1500      # ← Custom UID
USER_GID=1500      # ← Custom GID
FLUTTER_VERSION=3.24.0
```

**Result**:
- Container name: `davincidesigner-dev`
- User: `davinci` (UID 1500, GID 1500)
- Files created by container owned by UID 1500

### Example 4: Resource Limits

**Project**: Large project needing more resources

**`.env`**
```bash
PROJECT_NAME=bigproject
USER_NAME=developer
USER_UID=1000
USER_GID=1000
FLUTTER_VERSION=3.24.0
CONTAINER_MEMORY=8g    # ← More memory
CONTAINER_CPUS=4       # ← More CPUs
```

**Result**:
- Container limited to 8GB RAM and 4 CPUs
- Better performance for large builds

---

## Debugging & Troubleshooting

### Check What Docker Compose Sees

```bash
# Navigate to project
cd Dartwingers/ledgerlinc

# Show resolved configuration (with all variables substituted)
docker-compose config

# Expected output shows resolved values:
# services:
#   flutter-dev:
#     container_name: ledgerlinc-dev  # ← ${PROJECT_NAME} replaced
#     user: "1000:1000"                # ← ${USER_UID}:${USER_GID} replaced
#     build:
#       args:
#         USER_UID: 1000                # ← ${USER_UID} replaced
```

### Verify .env Is Being Read

#### Test 1: Check Variables

```bash
# Create test .env
cat > .env << EOF
PROJECT_NAME=testproject
TEST_VAR=hello
EOF

# View resolved config
docker-compose config | grep container_name
# Should show: container_name: testproject-dev
```

#### Test 2: Compare With and Without .env

```bash
# Without .env (uses defaults)
mv .env .env.backup
docker-compose config | grep container_name
# Shows: container_name: myproject-dev (default)

# With .env
mv .env.backup .env
docker-compose config | grep container_name
# Shows: container_name: ledgerlinc-dev (from .env)
```

### Common Issues and Solutions

#### Issue 1: Variables Not Substituted

**Symptom**: Container name is literally `${PROJECT_NAME}-dev`

**Cause**: .env file not found or wrong location

**Solution**:
```bash
# Check location
ls -la .env
ls -la docker-compose.yml
# Both should be in same directory

# Check file name
# Must be exactly ".env", not "env.txt" or ".env.local"
```

#### Issue 2: Wrong Values Used

**Symptom**: Container uses default values, not .env values

**Cause**: Syntax error in .env file

**Solution**:
```bash
# Check .env syntax
cat .env

# Common mistakes:
# ❌ PROJECT_NAME = ledgerlinc    # Spaces around =
# ❌ PROJECT_NAME="ledgerlinc"    # Quotes (become part of value)
# ❌ PROJECT NAME=ledgerlinc      # Space in key

# ✅ Correct:
# PROJECT_NAME=ledgerlinc
```

#### Issue 3: Variables Not Available in Container

**Symptom**: `echo $MY_VAR` in container shows nothing

**Cause**: Variable only used for compose config, not passed to container

**Solution**:
```yaml
# To make available in container, add to environment:
services:
  flutter-dev:
    environment:
      - MY_VAR=${MY_VAR}  # Now available at runtime
```

#### Issue 4: Build Not Using New .env Values

**Symptom**: Changed .env but container still uses old values

**Cause**: Docker cached the build

**Solution**:
```bash
# Rebuild without cache
docker-compose build --no-cache

# Or force rebuild when starting
docker-compose up --build --force-recreate
```

### Debug Commands

```bash
# Show all environment variables Docker Compose sees
docker-compose config --environment

# Show only specific service
docker-compose config --services

# Validate compose file
docker-compose config --quiet
# No output = valid, errors = invalid

# Show what variables are set in running container
docker-compose exec flutter-dev env

# Check .env file format
cat .env | grep -v '^#' | grep -v '^$'
# Should show only KEY=VALUE lines
```

---

## Best Practices

### 1. Use .env.example for Templates

```bash
# Checked into git (safe, no secrets)
.env.example

# Not in git (user-specific, may contain secrets)
.env
```

**In .gitignore**:
```gitignore
# Never commit actual .env files
.env
.env.local
.env.*.local
```

### 2. Provide Defaults in docker-compose.yml

```yaml
# Good: Has fallback if .env missing
USER_UID: ${USER_UID:-1000}

# Bad: Fails if .env missing
USER_UID: ${USER_UID}
```

**Syntax**: `${VARIABLE:-default}`
- If `VARIABLE` is set in .env: uses that value
- If `VARIABLE` is not set: uses `default`

### 3. Document All Variables

```bash
# .env.example

# ====================================
# Project Configuration
# ====================================

# PROJECT_NAME: Used for container name and volume names
# Must be unique across all projects
# Example: ledgerlinc, lablinc, dartwing
PROJECT_NAME=myproject

# USER_UID: User ID inside container
# Should match your WSL2 user ID (run 'id -u' to check)
# Default: 1000
USER_UID=1000
```

### 4. Validate .env on Project Setup

Create a setup script:

**`scripts/manual-setup-project.sh`**
```bash
#!/bin/bash

if [ ! -f .env ]; then
    echo "⚠️  .env file not found!"
    echo "Creating from .env.example..."
    cp .env.example .env
    echo "✅ Created .env file"
    echo "📝 Please edit .env and set PROJECT_NAME"
    exit 1
fi

# Validate required variables
REQUIRED_VARS=("PROJECT_NAME" "USER_NAME" "USER_UID" "USER_GID")
MISSING=()

for VAR in "${REQUIRED_VARS[@]}"; do
    if ! grep -q "^${VAR}=" .env; then
        MISSING+=("$VAR")
    fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
    echo "❌ Missing required variables in .env:"
    printf '   - %s\n' "${MISSING[@]}"
    exit 1
fi

echo "✅ .env file validated"
```

### 5. Use Descriptive Variable Names

```bash
# Good: Clear what it's for
FLUTTER_VERSION=3.24.0
ADB_SERVER_HOST=shared-adb-server
CONTAINER_MEMORY=4g

# Bad: Unclear
VERSION=3.24.0
HOST=server
MEM=4g
```

### 6. Group Related Variables

```bash
# ====================================
# Project Configuration
# ====================================
PROJECT_NAME=myproject

# ====================================
# User Configuration  
# ====================================
USER_NAME=developer
USER_UID=1000
USER_GID=1000

# ====================================
# Flutter Configuration
# ====================================
FLUTTER_VERSION=3.24.0
```

### 7. Test Configuration Before Committing

```bash
# Always test compose config
docker-compose config

# Test build
docker-compose build

# Test run
docker-compose up -d
docker-compose exec flutter-dev flutter --version
docker-compose down
```

---

## Common Pitfalls

### ❌ Pitfall 1: Wrong File Location

```bash
# WRONG - .env in parent directory
Dartwingers/
├── .env                    # ← Won't be found!
└── ledgerlinc/
    └── docker-compose.yml

# CORRECT - .env next to docker-compose.yml
Dartwingers/
└── ledgerlinc/
    ├── .env                # ← Here!
    └── docker-compose.yml
```

### ❌ Pitfall 2: Quotes in Values

```bash
# WRONG - Quotes become part of value
PROJECT_NAME="ledgerlinc"   
# Result: container name is "ledgerlinc"-dev (with quotes!)

# CORRECT - No quotes
PROJECT_NAME=ledgerlinc
```

### ❌ Pitfall 3: Spaces Around Equals

```bash
# WRONG
PROJECT_NAME = ledgerlinc   # Spaces cause parsing errors

# CORRECT
PROJECT_NAME=ledgerlinc     # No spaces
```

### ❌ Pitfall 4: Expecting .env in Container

```bash
# .env is NOT copied into the container
# It's only read by Docker Compose on the HOST

# Won't work:
docker exec my-container cat .env  # File doesn't exist
```

### ❌ Pitfall 5: Using .env for Runtime Configuration

```bash
# WRONG - Trying to use .env for app config
# File: app.py
from dotenv import load_dotenv
load_dotenv()  # Won't find .env (not in container!)

# CORRECT - Use environment variables passed by compose
# File: docker-compose.yml
environment:
  - MY_CONFIG=${MY_VALUE}  # From .env, passed to container

# File: app.py
import os
config = os.environ.get('MY_CONFIG')  # Works!
```

### ❌ Pitfall 6: Forgetting to Rebuild After Changes

```bash
# Change .env
echo "FLUTTER_VERSION=3.19.0" >> .env

# Won't take effect automatically
docker-compose up  # Still uses old version!

# CORRECT - Rebuild
docker-compose up --build
```

### ❌ Pitfall 7: Committing .env to Git

```bash
# NEVER commit .env - it may contain:
# - User-specific paths
# - API keys
# - Passwords
# - Machine-specific configuration

# Always in .gitignore:
.env
.env.local
.env.*.local

# Only commit:
.env.example
```

### ❌ Pitfall 8: Multiline Values

```bash
# WRONG - Docker Compose doesn't support multiline in .env
MY_VALUE=line1
line2
line3

# CORRECT - Use quotes and \n or put in file and mount
MY_VALUE="line1\nline2\nline3"

# Or better - mount a file:
volumes:
  - ./config.txt:/app/config.txt
```

---

## When Each File Is Used

### Complete Timeline Summary

| Step | File | Action | .env Used? |
|------|------|--------|-----------|
| 1 | `.devcontainer/devcontainer.json` | initializeCommand runs | ❌ No |
| 2 | `.env` | Docker Compose starts | ✅ Read automatically |
| 3 | `docker-compose.yml` | Parse and substitute | ✅ Variables replaced |
| 4 | `Dockerfile` | Build image (if needed) | ✅ Via build args |
| 5 | Container | Start container | ✅ Via environment vars |
| 6 | Container | Running | ❌ Values already applied |

### File Dependencies

```
.env.example (template in git)
    ↓
    Copy to
    ↓
.env (user's local config)
    ↓
    Read by
    ↓
docker-compose.yml (substitutes ${VARS})
    ↓
    Passes args to
    ↓
Dockerfile (receives ARGs, builds image)
    ↓
    Creates
    ↓
Container (runs with ENV vars)
```

---

## Quick Reference

### .env File Format

```bash
# Comments start with #
KEY=value
KEY_TWO=value_two

# No spaces around =
# No quotes needed
# One variable per line
# Empty lines ignored
```

### Docker Compose Commands That Use .env

```bash
docker-compose config      # ✅ Uses .env
docker-compose build       # ✅ Uses .env
docker-compose up          # ✅ Uses .env
docker-compose down        # ✅ Uses .env
docker-compose restart     # ✅ Uses .env
docker-compose exec        # ✅ Container has ENV vars from .env
```

### Variable Substitution Syntax

```yaml
# Basic
${VARIABLE}

# With default
${VARIABLE:-default}

# Must be set (error if missing)
${VARIABLE?error message}

# Use value or empty
${VARIABLE-default}
```

### Checking Your Setup

```bash
# 1. Verify .env exists
ls -la .env

# 2. Check .env syntax
cat .env | grep -v '^#' | grep -v '^$'

# 3. See what compose will use
docker-compose config

# 4. Test build
docker-compose build

# 5. Verify in running container
docker-compose up -d
docker-compose exec flutter-dev env | grep MY_VAR
```

---

## Conclusion

### Key Takeaways

✅ **Automatic**: Docker Compose reads `.env` automatically from the same directory  
✅ **Parse Time**: Variables substituted before anything else happens  
✅ **Build Args**: Passed to Dockerfile during image build  
✅ **Runtime ENV**: Available in running containers  
✅ **Per Project**: Each project has its own `.env` for custom configuration  
✅ **Git Safe**: `.env` in .gitignore, `.env.example` in git  

### For Flutter DevContainer Templates

When copying the template to a new project:

1. ✅ Copy `.env.example` to `.env`
2. ✅ Edit `PROJECT_NAME` in `.env`
3. ✅ Adjust other values if needed (USER_UID, FLUTTER_VERSION, etc.)
4. ✅ Open in VS Code → Reopen in Container
5. ✅ Docker Compose automatically uses `.env`
6. ✅ Container built and configured correctly

**That's it!** The `.env` file makes each project independently configurable while using the same template structure.

---

## Additional Resources

### Template Location
```
DevBench/FlutterBench/templates/flutter-devcontainer-template/
```

### Related Documentation
- `flutter-infrastructure-architecture.md` - Overall architecture
- `vscode-tasks-snippets.md` - Tasks and configuration snippets
- `path-pinning-verification.md` - Infrastructure paths

### Support
For issues with `.env` files in Flutter DevContainers, check:
1. This guide's troubleshooting section
2. Run `docker-compose config` to see resolved values
3. Validate `.env` syntax (no spaces, no quotes)
4. Ensure `.env` is in same directory as `docker-compose.yml`
