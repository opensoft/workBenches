# Questions & Answers: Infrastructure Setup

## Q1: Does initializeCommand go in each Flutter project's compose file?

**Answer: NO** - `initializeCommand` goes in **`.devcontainer/devcontainer.json`**, NOT in `docker-compose.yml`.

### Where Each Configuration Lives:

**`.devcontainer/devcontainer.json`** (per project):
- `initializeCommand` - Runs on HOST before container creation
- `onCreateCommand` - Runs INSIDE container on first creation
- `postStartCommand` - Runs INSIDE container on every start
- `postAttachCommand` - Runs INSIDE container when VS Code attaches
- VS Code extensions and settings

**`docker-compose.yml`** (per project):
- Container definition (build, image)
- Environment variables (like ADB_SERVER_SOCKET)
- Network configuration (dartnet)
- Volume mounts
- Container name

**Correct Setup**:

```
ledgerlinc/
├── .devcontainer/
│   └── devcontainer.json          ← initializeCommand HERE
│       {
│         "initializeCommand": { ... },
│         "onCreateCommand": "...",
│         "postStartCommand": "...",
│         "postAttachCommand": "..."
│       }
│
└── docker-compose.yml              ← NO lifecycle commands here
    services:
      flutter-dev:
        build: .
        environment:
          - ADB_SERVER_SOCKET=tcp:shared-adb-server:5037
```

---

## Q2: How do I easily add tasks to all new Flutter projects?

**Answer**: Use a **template folder** with pre-configured files that you copy to new projects.

### Template Structure

Create in `DevBench/FlutterBench/`:

```
DevBench/FlutterBench/
└── templates/
    └── flutter-devcontainer-template/
        ├── .devcontainer/
        │   └── devcontainer.json
        ├── .vscode/
        │   ├── tasks.json           ← Pre-configured ADB tasks
        │   ├── launch.json          ← Flutter debug configs
        │   └── settings.json        ← Project settings
        ├── docker-compose.yml
        ├── Dockerfile
        └── README.md                ← Template usage instructions
```

### Using the Template

**Option A: Manual Copy (Simple)**
```bash
cd Dartwingers
flutter create mynewapp
cd mynewapp
cp -r ../../DevBench/FlutterBench/templates/flutter-devcontainer-template/.devcontainer .
cp -r ../../DevBench/FlutterBench/templates/flutter-devcontainer-template/.vscode .
cp ../../DevBench/FlutterBench/templates/flutter-devcontainer-template/docker-compose.yml .
# Edit files to replace PROJECT_NAME placeholders
```

**Option B: Script (Automated)**

Create `DevBench/FlutterBench/scripts/new-flutter-project.sh`:

```bash
#!/bin/bash

PROJECT_NAME=$1
TARGET_DIR=$2

if [ -z "$PROJECT_NAME" ] || [ -z "$TARGET_DIR" ]; then
    echo "Usage: ./new-flutter-project.sh <project-name> <target-directory>"
    echo "Example: ./new-flutter-project.sh myapp ../../Dartwingers"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/../templates/flutter-devcontainer-template"

echo "📦 Creating Flutter project: $PROJECT_NAME"

# Create Flutter project
cd "$TARGET_DIR"
flutter create "$PROJECT_NAME"
cd "$PROJECT_NAME"

# Copy template files
echo "📋 Copying devcontainer configuration..."
cp -r "$TEMPLATE_DIR/.devcontainer" .
cp -r "$TEMPLATE_DIR/.vscode" .
cp "$TEMPLATE_DIR/docker-compose.yml" .
cp "$TEMPLATE_DIR/Dockerfile" .

# Replace placeholders
echo "🔧 Configuring project..."
# Replace PROJECT_NAME in devcontainer.json
sed -i "s/PROJECT_NAME/$PROJECT_NAME/g" .devcontainer/devcontainer.json
# Replace container name in docker-compose.yml
sed -i "s/PROJECT_NAME/$PROJECT_NAME/g" docker-compose.yml

echo "✅ Project created: $TARGET_DIR/$PROJECT_NAME"
echo "📝 Next steps:"
echo "   1. cd $TARGET_DIR/$PROJECT_NAME"
echo "   2. code ."
echo "   3. Reopen in container when prompted"
```

**Usage**:
```bash
cd DevBench/FlutterBench/scripts
./new-flutter-project.sh mynewapp ../../Dartwingers
```

**Option C: VS Code Snippet (Quick)**

Create `.vscode/global-snippets/flutter-devcontainer.code-snippets` in your user settings:

```json
{
  "Flutter DevContainer Config": {
    "scope": "json",
    "prefix": "flutter-devcontainer",
    "body": [
      "{",
      "  \"name\": \"${1:ProjectName} Flutter Dev\",",
      "  \"dockerComposeFile\": \"../docker-compose.yml\",",
      "  \"service\": \"flutter-dev\",",
      "  \"workspaceFolder\": \"/workspace\",",
      "  ",
      "  \"initializeCommand\": {",
      "    \"adb\": \"\\${localWorkspaceFolder}/../../infrastructure/mobile/android/adb/scripts/start-adb-if-needed.sh\"",
      "  },",
      "  ",
      "  \"onCreateCommand\": \"flutter pub get\",",
      "  \"postStartCommand\": \"flutter doctor\",",
      "  \"postAttachCommand\": \"adb devices\",",
      "  ",
      "  \"customizations\": {",
      "    \"vscode\": {",
      "      \"extensions\": [",
      "        \"Dart-Code.dart-code\",",
      "        \"Dart-Code.flutter\",",
      "        \"ms-azuretools.vscode-docker\"",
      "      ],",
      "      \"settings\": {",
      "        \"dart.flutterSdkPath\": \"/flutter\"",
      "      }",
      "    }",
      "  }",
      "}"
    ],
    "description": "Insert Flutter devcontainer.json configuration"
  }
}
```

Then just type `flutter-devcontainer` in any JSON file and it auto-completes!

---

## Q3: Where do lifecycle tasks go?

**Answer**: Lifecycle configurations go in **`.devcontainer/devcontainer.json`**. Manual tasks go in **`.vscode/tasks.json`**.

### Lifecycle Commands (devcontainer.json)

```json
{
  "name": "LedgerLinc Flutter Dev",
  
  // Runs on HOST before container creation
  "initializeCommand": {
    "adb": "${localWorkspaceFolder}/../../infrastructure/mobile/android/adb/scripts/start-adb-if-needed.sh"
  },
  
  // Runs INSIDE container, only on first creation
  "onCreateCommand": {
    "dependencies": "flutter pub get",
    "precache": "flutter precache"
  },
  
  // Runs INSIDE container, every time container starts
  "postStartCommand": {
    "doctor": "flutter doctor",
    "devices": "adb devices"
  },
  
  // Runs INSIDE container, when VS Code attaches
  "postAttachCommand": "echo '✅ Ready to develop!' && adb devices"
}
```

### Manual Tasks (tasks.json)

For developer-triggered actions:

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "🔌 Check ADB Connection",
      "type": "shell",
      "command": "adb devices -l"
    }
  ]
}
```

---

## Q4: Will we need to pin the infrastructure folder location/path?

**Answer: YES** - The path to infrastructure is **pinned using relative paths** from each project.

### Path Pinning Strategy

#### Fixed Infrastructure Location
```
projects/infrastructure/mobile/android/adb/
         ↑ This location is FIXED
```

#### Relative Paths from Projects

**From Dartwingers projects** (2 levels up):
```json
{
  "initializeCommand": {
    "adb": "${localWorkspaceFolder}/../../infrastructure/mobile/android/adb/scripts/start-adb-if-needed.sh"
  }
}
```

**From DavinciDesigner/flutter-app** (2 levels up):
```json
{
  "initializeCommand": {
    "adb": "${localWorkspaceFolder}/../../infrastructure/mobile/android/adb/scripts/start-adb-if-needed.sh"
  }
}
```

**From deeper nesting** (3 levels up):
```json
{
  "initializeCommand": {
    "adb": "${localWorkspaceFolder}/../../../infrastructure/mobile/android/adb/scripts/start-adb-if-needed.sh"
  }
}
```

### Path Calculation Formula

```
Number of ../ = (Project depth from 'projects/') 
```

Examples:
- `projects/Dartwingers/ledgerlinc/` → 2 levels → `../../`
- `projects/DavinciDesigner/flutter-app/` → 2 levels → `../../`
- `projects/SomeProject/mobile/flutter-app/` → 3 levels → `../../../`

### Environment Variable Alternative (Optional)

If you want more flexibility, use environment variables:

**Set in `.bashrc` or `.zshrc` (Windows Git Bash / WSL):**
```bash
export FLUTTER_INFRASTRUCTURE_PATH="/c/projects/infrastructure"
```

**Then in devcontainer.json:**
```json
{
  "initializeCommand": {
    "adb": "$FLUTTER_INFRASTRUCTURE_PATH/mobile/android/adb/scripts/start-adb-if-needed.sh"
  }
}
```

**Pros**: Flexible if you move infrastructure  
**Cons**: Requires environment setup on each machine  

**Recommendation**: Use **relative paths** (simpler, more portable)

### Verification

To verify paths are correct:

```bash
# From any Flutter project directory
cd Dartwingers/ledgerlinc
ls -la ../../infrastructure/mobile/android/adb/scripts/start-adb-if-needed.sh
# Should show the file

cd ../../DavinciDesigner/flutter-app
ls -la ../../infrastructure/mobile/android/adb/scripts/start-adb-if-needed.sh
# Should show the file
```

---

## Summary: Configuration Checklist

### ✅ For Each New Flutter Project

**1. Copy template files**:
```bash
cp -r DevBench/FlutterBench/templates/flutter-devcontainer-template/.devcontainer .
cp -r DevBench/FlutterBench/templates/flutter-devcontainer-template/.vscode .
```

**2. Update devcontainer.json**:
- Change project name: `"name": "YourApp Flutter Dev"`
- Verify path to infrastructure (count `../` levels)
- Keep lifecycle commands as-is

**3. Update docker-compose.yml**:
- Change container name: `container_name: yourapp-dev`
- Keep network as `dartnet` (external: true)
- Keep environment variable: `ADB_SERVER_SOCKET=tcp:shared-adb-server:5037`

**4. Update tasks.json**:
- Keep as-is (tasks use relative paths that auto-adjust)

**5. Test**:
```bash
code .
# Reopen in container
# Should auto-start ADB and connect
```

### ✅ Infrastructure Location (Fixed)

```
projects/infrastructure/mobile/android/adb/
    ├── docker/
    │   └── Dockerfile
    ├── compose/
    │   └── docker-compose.yml
    └── scripts/
        ├── start-adb-if-needed.sh
        ├── stop-adb.sh
        └── check-adb.sh
```

**This location never changes** - all projects reference it with relative paths.

---

## Best Practices

### DO ✅
- Use relative paths from project to infrastructure
- Keep infrastructure at fixed location: `projects/infrastructure/`
- Use templates for new projects
- Pin paths in devcontainer.json with `../../` notation
- Make scripts executable: `chmod +x *.sh`

### DON'T ❌
- Don't put lifecycle commands in docker-compose.yml
- Don't use absolute paths (they break on other machines)
- Don't duplicate infrastructure per project
- Don't hardcode container IPs
- Don't skip the initializeCommand (ADB won't auto-start)

### Troubleshooting

**Path not found**:
```bash
# Check from project directory
ls -la ../../infrastructure/mobile/android/adb/scripts/
# If not found, count directory levels again
```

**Script not executable**:
```bash
chmod +x projects/infrastructure/mobile/android/adb/scripts/*.sh
```

**ADB not starting**:
```bash
# Manual start
cd projects/infrastructure/mobile/android/adb/scripts
./start-adb-if-needed.sh
# Check logs
docker logs shared-adb-server
```
