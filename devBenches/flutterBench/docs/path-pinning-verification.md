# Verification & Path Pinning Guide

## Question Verification Summary

### ✅ Q1: Does initializeCommand go in docker-compose.yml?

**Answer: NO**

**Correct Location**: `.devcontainer/devcontainer.json`

```
❌ WRONG:
docker-compose.yml
  services:
    flutter-dev:
      initializeCommand: ...    # ← NO! This doesn't exist here

✅ CORRECT:
.devcontainer/devcontainer.json
  {
    "initializeCommand": {      # ← YES! Goes here
      "adb": "path/to/script.sh"
    }
  }
```

**Why**: Docker Compose doesn't have lifecycle hooks. Only devcontainer.json has `initializeCommand`, `onCreateCommand`, `postStartCommand`, and `postAttachCommand`.

---

### ✅ Q2: How to easily add tasks to new Flutter projects?

**Answer: Use a Template System**

**Three Methods**:

#### Method 1: Template Folder (Recommended)
```
DevBench/FlutterBench/templates/flutter-devcontainer-template/
├── .devcontainer/devcontainer.json
├── .vscode/tasks.json
├── docker-compose.yml
└── Dockerfile
```

**Usage**:
```bash
cd Dartwingers
flutter create mynewapp
cd mynewapp
cp -r ../../DevBench/FlutterBench/templates/flutter-devcontainer-template/.devcontainer .
cp -r ../../DevBench/FlutterBench/templates/flutter-devcontainer-template/.vscode .
# Edit names/paths as needed
```

#### Method 2: Creation Script
```bash
# DevBench/FlutterBench/scripts/new-flutter-project.sh
./new-flutter-project.sh mynewapp ../../Dartwingers
# Auto-creates and configures everything
```

#### Method 3: VS Code Snippets
```json
// User snippets: flutter-devcontainer
// Type "flutter-devcontainer" in JSON files → auto-complete!
```

**Result**: All new projects get consistent configuration automatically.

---

### ✅ Q3: Where do lifecycle tasks go?

**Answer: In `.devcontainer/devcontainer.json`**

**Complete Lifecycle**:

```json
{
  "name": "MyApp Flutter Dev",
  
  // HOST (Windows) - Before container creation
  "initializeCommand": {
    "adb": "${localWorkspaceFolder}/../../infrastructure/mobile/android/adb/scripts/start-adb-if-needed.sh"
  },
  
  // CONTAINER - Once on creation
  "onCreateCommand": {
    "dependencies": "flutter pub get",
    "precache": "flutter precache --android"
  },
  
  // CONTAINER - Every start
  "postStartCommand": {
    "doctor": "flutter doctor",
    "devices": "adb devices"
  },
  
  // CONTAINER - When VS Code attaches
  "postAttachCommand": "echo '✅ Ready!' && adb devices"
}
```

**Not in docker-compose.yml**: Docker Compose has no equivalent lifecycle hooks.

**Manual tasks go in**: `.vscode/tasks.json` (for developer-triggered actions)

---

### ✅ Q4: Do we need to pin the infrastructure folder path?

**Answer: YES - Using Relative Paths**

---

## Path Pinning Strategy

### Fixed Infrastructure Location

```
projects/
└── infrastructure/           # ← FIXED LOCATION (never moves)
    └── mobile/
        └── android/
            └── adb/
                ├── docker/
                ├── compose/
                └── scripts/
```

### Relative Path Resolution

Each project calculates path to infrastructure using relative `../` notation:

#### Path Calculation Formula

```
Number of "../" = (Project depth from 'projects/' directory)
```

#### Examples

**Dartwingers Projects** (2 levels deep):
```
projects/
└── Dartwingers/              # Level 1
    └── ledgerlinc/           # Level 2
        → ../../infrastructure/

Dartwingers/
└── lablinc/                  # Level 2
    → ../../infrastructure/
```

**DavinciDesigner** (2 levels deep):
```
projects/
└── DavinciDesigner/          # Level 1
    └── flutter-app/          # Level 2
        → ../../infrastructure/
```

**Deeply Nested** (3+ levels deep):
```
projects/
└── SomeProject/              # Level 1
    └── mobile/               # Level 2
        └── flutter-app/      # Level 3
            → ../../../infrastructure/
```

### Configuration in devcontainer.json

**2 Levels Deep** (most common):
```json
{
  "initializeCommand": {
    "adb": "${localWorkspaceFolder}/../../infrastructure/mobile/android/adb/scripts/start-adb-if-needed.sh"
  }
}
```

**3 Levels Deep**:
```json
{
  "initializeCommand": {
    "adb": "${localWorkspaceFolder}/../../../infrastructure/mobile/android/adb/scripts/start-adb-if-needed.sh"
  }
}
```

### In tasks.json

Tasks automatically adjust since they use `${workspaceFolder}`:

```json
{
  "label": "🚀 Start ADB Infrastructure",
  "command": "${workspaceFolder}/../../infrastructure/mobile/android/adb/scripts/start-adb-if-needed.sh"
}
```

Change path depth based on project location.

---

## Path Verification Matrix

### Current Project Structure

| Project Path | Depth | Path to Infrastructure |
|--------------|-------|------------------------|
| `Dartwingers/ledgerlinc/` | 2 | `../../infrastructure/` |
| `Dartwingers/lablinc/` | 2 | `../../infrastructure/` |
| `Dartwingers/dartwing/` | 2 | `../../infrastructure/` |
| `DavinciDesigner/flutter-app/` | 2 | `../../infrastructure/` |
| `DevBench/FlutterBench/` | 2 | `../../infrastructure/` |

### Verification Commands

**From ledgerlinc**:
```bash
cd projects/Dartwingers/ledgerlinc
ls -la ../../infrastructure/mobile/android/adb/scripts/
# Should list: start-adb-if-needed.sh, stop-adb.sh, check-adb.sh
```

**From DavinciDesigner**:
```bash
cd projects/DavinciDesigner/flutter-app
ls -la ../../infrastructure/mobile/android/adb/scripts/
# Should list: start-adb-if-needed.sh, stop-adb.sh, check-adb.sh
```

**Test Script Path**:
```bash
cd projects/Dartwingers/ledgerlinc
../../infrastructure/mobile/android/adb/scripts/start-adb-if-needed.sh
# Should execute successfully
```

---

## Why Relative Paths (Not Absolute)?

### ✅ Advantages of Relative Paths

1. **Portable**: Works on any machine, any OS
2. **Version Control**: Same paths in repo for all developers
3. **No Configuration**: No environment variables needed
4. **Relocatable**: Can move entire `projects/` folder

### ❌ Problems with Absolute Paths

```json
// BAD - Hardcoded absolute path
{
  "initializeCommand": {
    "adb": "C:/projects/infrastructure/mobile/android/adb/scripts/start-adb-if-needed.sh"
  }
}
```

**Issues**:
- Breaks on different machines
- Breaks on Linux/Mac
- Breaks if `projects/` moves
- Not in version control friendly

### ❌ Problems with Environment Variables

```json
// BAD - Requires env var setup
{
  "initializeCommand": {
    "adb": "$FLUTTER_INFRA/mobile/android/adb/scripts/start-adb-if-needed.sh"
  }
}
```

**Issues**:
- Every developer must set `FLUTTER_INFRA`
- Different on Windows/Linux/Mac
- Easy to forget
- Setup overhead

### ✅ Relative Paths Win

```json
// GOOD - Works everywhere
{
  "initializeCommand": {
    "adb": "${localWorkspaceFolder}/../../infrastructure/mobile/android/adb/scripts/start-adb-if-needed.sh"
  }
}
```

**Benefits**:
- Just works™
- No setup
- Cross-platform
- Maintainable

---

## Path Pinning Checklist

### ✅ Infrastructure Setup (One Time)

```bash
# 1. Create infrastructure at fixed location
cd projects
mkdir -p infrastructure/mobile/android/adb/{docker,compose,scripts}

# 2. Verify structure
ls -la infrastructure/mobile/android/adb/
# Should show: docker/ compose/ scripts/

# 3. Make scripts executable
chmod +x infrastructure/mobile/android/adb/scripts/*.sh

# 4. Verify from any project
cd Dartwingers/ledgerlinc
ls ../../infrastructure/mobile/android/adb/scripts/
# Should list all scripts
```

### ✅ Project Configuration

For each Flutter project:

```bash
# 1. Count depth from projects/
# Dartwingers/ledgerlinc → 2 levels → ../../

# 2. Set in devcontainer.json
{
  "initializeCommand": {
    "adb": "${localWorkspaceFolder}/../../infrastructure/..."
  }
}

# 3. Set in tasks.json
{
  "command": "${workspaceFolder}/../../infrastructure/..."
}

# 4. Verify
cd Dartwingers/ledgerlinc
ls -la ../../infrastructure/mobile/android/adb/scripts/
# Should work
```

### ✅ Template Configuration

In template files, use placeholder that gets adjusted:

```json
// DevBench/FlutterBench/templates/.../devcontainer.json
{
  "initializeCommand": {
    "adb": "${localWorkspaceFolder}/../../infrastructure/mobile/android/adb/scripts/start-adb-if-needed.sh"
  }
}
```

When copying to new project, adjust `../../` if needed based on depth.

---

## Quick Reference: Path by Project Type

### Standard Projects (2 Levels Deep)

```
projects/
└── ProjectFolder/
    └── app/
```

**Path**: `../../infrastructure/`

**Projects**:
- Dartwingers/* 
- DavinciDesigner/flutter-app
- DevBench/*

### Deep Projects (3+ Levels)

```
projects/
└── ProjectFolder/
    └── mobile/
        └── flutter-app/
```

**Path**: `../../../infrastructure/`

**Count Rule**: One `../` per level to projects/, then add `infrastructure/`

---

## Alternative: Symlinks (Optional)

If you want to avoid counting levels, use symlinks:

```bash
# In each project root
cd Dartwingers/ledgerlinc
ln -s ../../infrastructure .infrastructure

# Then use fixed path
"initializeCommand": {
  "adb": "${localWorkspaceFolder}/.infrastructure/mobile/android/adb/scripts/start-adb-if-needed.sh"
}
```

**Pros**: Always same path  
**Cons**: Symlinks can be problematic on Windows, requires Git configuration

**Recommendation**: Stick with relative paths (simpler, more reliable)

---

## Final Configuration Summary

### File Locations (Fixed)

```
projects/
├── infrastructure/                    # ← PINNED HERE (never moves)
│   └── mobile/
│       └── android/
│           └── adb/
│               ├── docker/
│               ├── compose/
│               └── scripts/
│
├── Dartwingers/
│   ├── ledgerlinc/
│   │   ├── .devcontainer/
│   │   │   └── devcontainer.json    # ← initializeCommand: ../../infrastructure/...
│   │   └── .vscode/
│   │       └── tasks.json           # ← tasks use: ../../infrastructure/...
│   │
│   ├── lablinc/
│   │   ├── .devcontainer/
│   │   │   └── devcontainer.json    # ← initializeCommand: ../../infrastructure/...
│   │   └── .vscode/
│   │       └── tasks.json           # ← tasks use: ../../infrastructure/...
│   │
│   └── dartwing/
│       └── ...
│
└── DavinciDesigner/
    └── flutter-app/
        ├── .devcontainer/
        │   └── devcontainer.json    # ← initializeCommand: ../../infrastructure/...
        └── .vscode/
            └── tasks.json           # ← tasks use: ../../infrastructure/...
```

### Configuration Pattern (All Projects)

**devcontainer.json**:
```json
{
  "initializeCommand": {
    "adb": "${localWorkspaceFolder}/../../infrastructure/mobile/android/adb/scripts/start-adb-if-needed.sh"
  }
}
```

**tasks.json**:
```json
{
  "label": "🚀 Start ADB",
  "command": "${workspaceFolder}/../../infrastructure/mobile/android/adb/scripts/start-adb-if-needed.sh"
}
```

**docker-compose.yml**:
```yaml
networks:
  dartnet:
    external: true
    name: dartnet
```

---

## Verification Checklist

### ✅ Before Committing to Git

- [ ] Infrastructure at: `projects/infrastructure/mobile/android/adb/`
- [ ] Scripts executable: `chmod +x *.sh`
- [ ] Path verified from each project: `ls ../../infrastructure/...`
- [ ] devcontainer.json has correct `../../` count
- [ ] tasks.json has correct `../../` count
- [ ] Template updated in FlutterBench/templates/

### ✅ Testing New Project

- [ ] Copy template files
- [ ] Adjust project name
- [ ] Adjust container name
- [ ] Verify path: `ls ../../infrastructure/mobile/android/adb/scripts/`
- [ ] Open in VS Code
- [ ] Reopen in container
- [ ] Check initializeCommand output
- [ ] Run: `adb devices`

### ✅ Multi-Project Test

- [ ] Open ledgerlinc (starts ADB)
- [ ] Open lablinc (reuses ADB)
- [ ] Both see same devices: `docker exec ledgerlinc-dev adb devices`
- [ ] Network connected: `docker network inspect dartnet`

---

## Troubleshooting Path Issues

### Issue: "Script not found"

**Cause**: Wrong number of `../`

**Fix**:
```bash
# From project directory, test path
cd Dartwingers/ledgerlinc
ls ../../infrastructure/mobile/android/adb/scripts/start-adb-if-needed.sh
# If not found, adjust ../ count
```

### Issue: "Permission denied"

**Cause**: Scripts not executable

**Fix**:
```bash
chmod +x projects/infrastructure/mobile/android/adb/scripts/*.sh
```

### Issue: "No such file or directory" (Windows)

**Cause**: Windows path format

**Fix**: VS Code handles this automatically with `${localWorkspaceFolder}`. If using Git Bash manually, ensure forward slashes:
```bash
# Good (forward slashes)
../../infrastructure/mobile/android/adb/scripts/start-adb-if-needed.sh

# Bad (backslashes)
..\..\infrastructure\mobile\android\adb\scripts\start-adb-if-needed.sh
```

---

## Summary

### ✅ Questions Answered

1. **initializeCommand location**: `.devcontainer/devcontainer.json` ✓
2. **Easy task addition**: Template system + copy script ✓
3. **Lifecycle tasks location**: `.devcontainer/devcontainer.json` ✓
4. **Path pinning**: Yes, using relative paths `../../infrastructure/` ✓

### ✅ Path Strategy

- **Infrastructure**: Fixed at `projects/infrastructure/`
- **Projects**: Use relative paths (`../../`, `../../../`, etc.)
- **Calculation**: Count levels from `projects/`, use that many `../`
- **Verification**: Test `ls ../../infrastructure/...` from each project

### ✅ Implementation

1. Create infrastructure once at `projects/infrastructure/`
2. Each project uses relative path in `devcontainer.json`
3. Tasks automatically work with `${workspaceFolder}/../../`
4. Template ensures consistency for new projects

**Result**: Scalable, maintainable, portable configuration across all Flutter projects!
