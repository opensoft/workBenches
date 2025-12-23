# DevContainer Symlink Architecture

## Overview

The devcontainer configuration uses a hierarchical symlink structure to maintain a single source of truth while allowing project-specific customization.

## Architecture Diagram

```
workBenches/
├── devcontainer-shared/
│   └── docker-compose.override.yml  ← SOURCE OF TRUTH for AI credentials
│
├── devcontainer.example/            ← Workspace template (connects to existing infra)
│   ├── docker-compose.yml
│   ├── docker-compose.override.yml  → SYMLINK to ../devcontainer-shared/
│   ├── Dockerfile
│   └── devcontainer.json
│
└── devBenches/
    └── frappeBench/
        └── devcontainer.example/    ← Full infrastructure template
            ├── docker-compose.yml
            ├── docker-compose.override.yml  → SYMLINK to ../../../devcontainer-shared/
            ├── Dockerfile
            └── devcontainer.json

dartwing/frappe/
└── devcontainer.example/            → SYMLINK to ../../workBenches/devcontainer.example/
```

## Hierarchy Levels

### Level 1: Source of Truth
**Location**: `workBenches/devcontainer-shared/docker-compose.override.yml`
- Contains all AI credential mounts
- Contains all common configuration mounts (shell, git, SSH, etc.)
- **Update here** to propagate changes to all templates

### Level 2: Bench Templates
**Locations**:
- `workBenches/devcontainer.example/` - Workspace template (lightweight)
- `workBenches/devBenches/frappeBench/devcontainer.example/` - Full infrastructure

**Each contains**:
- Own `docker-compose.yml` (bench-specific configuration)
- **Symlink** `docker-compose.override.yml` → points to `devcontainer-shared/`
- Own `Dockerfile`, `devcontainer.json`, etc.

### Level 3: Project Instances
**Example**: `dartwing/frappe/devcontainer.example/`
- **Entire directory is a symlink** → points to appropriate bench template
- Inherits everything from template automatically
- No customization needed at this level

## Benefits

### 1. Single Update Point
```bash
# Update AI credentials for EVERYONE:
vim workBenches/devcontainer-shared/docker-compose.override.yml
# That's it! All projects automatically inherit the change.
```

### 2. Bench-Specific Configuration
Each bench type can have its own `docker-compose.yml`:
- **Workspace template**: Lightweight, connects to existing infra
- **frappeBench template**: Full stack (mariadb, redis, workers)
- **dotNetBench template**: .NET-specific services
- **flutterBench template**: Flutter-specific services

### 3. Automatic Propagation
```
Edit devcontainer-shared/
    ↓
Symlink in workBenches/devcontainer.example/
    ↓
Symlink in dartwing/frappe/devcontainer.example/
    ↓
Changes automatically available!
```

## Template Types

### Workspace Template (workBenches/devcontainer.example/)
**Used for**: Projects that connect to existing Frappe infrastructure
**Characteristics**:
- Single service container
- No database or redis services
- Connects to external `frappe-network`
- Lightweight and fast

**Projects using this**:
- `dartwing/frappe/`
- Any workspace in `workBenches/devBenches/frappeBench/workspaces/*/`

### Infrastructure Template (frappeBench/devcontainer.example/)
**Used for**: Full Frappe development environment
**Characteristics**:
- Multiple services (frappe, mariadb, redis, workers)
- Complete infrastructure
- Self-contained development environment

**Projects using this**:
- New standalone Frappe projects
- Full infrastructure deployments

## Creating New Projects

### Using Workspace Template

```bash
cd your-project/
ln -s ../../workBenches/devcontainer.example .

# That's it! You now have:
# - Latest docker-compose.yml
# - Latest AI credential mounts (via symlink)
# - Latest Dockerfile and configs
```

### Using Infrastructure Template

```bash
cd your-project/
cp -r ../../workBenches/devBenches/frappeBench/devcontainer.example .

# Edit docker-compose.yml for project-specific settings
# The override (AI credentials) is still a symlink, so you get updates
```

## Updating AI Credentials

### Add New AI Provider

1. **Edit source**:
   ```bash
   vim workBenches/devcontainer-shared/docker-compose.override.yml
   ```

2. **Add mount**:
   ```yaml
   # New AI Provider
   - ~/.newai:/home/${USER:-vscode}/.newai:ro
   ```

3. **Done!** All projects inherit automatically via symlinks

### Verify Change Propagated

```bash
# Check workspace template
cat workBenches/devcontainer.example/docker-compose.override.yml | grep newai

# Check project
cat dartwing/frappe/devcontainer.example/docker-compose.override.yml | grep newai

# Both should show the new mount!
```

## Symlink Verification

### Check Symlink Chain

```bash
# From dartwing project
cd dartwing/frappe/

# Check first-level symlink
ls -la devcontainer.example
# Output: devcontainer.example -> ../../workBenches/devcontainer.example

# Check second-level symlink
ls -la devcontainer.example/docker-compose.override.yml
# Output: docker-compose.override.yml -> ../devcontainer-shared/docker-compose.override.yml

# Verify it resolves
readlink -f devcontainer.example/docker-compose.override.yml
# Output: /home/brett/projects/workBenches/devcontainer-shared/docker-compose.override.yml
```

### Test Configuration Merge

```bash
cd dartwing/frappe/devcontainer.example/
docker-compose config | grep -A 5 "claude"
# Should show all AI credential mounts from shared override
```

## Maintenance

### When to Update Templates

**Update shared override** (`devcontainer-shared/docker-compose.override.yml`):
- Adding new AI providers
- Changing common mount paths
- Adding new common configurations (shell, git, etc.)

**Update bench template** (`workBenches/devcontainer.example/docker-compose.yml`):
- Changing service configuration
- Updating port mappings
- Modifying network settings

**Never update** project symlinks - they inherit automatically!

### Backup Before Major Changes

```bash
# Backup source of truth
cp workBenches/devcontainer-shared/docker-compose.override.yml \
   workBenches/devcontainer-shared/docker-compose.override.yml.backup
```

## Troubleshooting

### Symlink Broken

**Symptom**: `No such file or directory` when accessing devcontainer.example

**Fix**:
```bash
cd your-project/
rm devcontainer.example
ln -s ../../workBenches/devcontainer.example .
```

### Override Not Found

**Symptom**: Docker Compose can't find override file

**Fix**:
```bash
cd workBenches/devcontainer.example/
ls -la docker-compose.override.yml
# If it's not a symlink, recreate it:
rm docker-compose.override.yml
ln -s ../devcontainer-shared/docker-compose.override.yml .
```

### Changes Not Appearing

**Symptom**: Updated shared override but project doesn't see changes

**Verify symlink chain**:
```bash
cd your-project/devcontainer.example/
readlink -f docker-compose.override.yml
# Should point to: workBenches/devcontainer-shared/docker-compose.override.yml
```

## Current Status

### ✅ Implemented

- `workBenches/devcontainer-shared/docker-compose.override.yml` - Source
- `workBenches/devcontainer.example/docker-compose.override.yml` - Symlink ✓
- `workBenches/devBenches/frappeBench/devcontainer.example/docker-compose.override.yml` - Symlink ✓
- `dartwing/frappe/devcontainer.example/` - Symlink to entire template ✓

### 📋 To Apply to Other Projects

Any project needing the workspace template:
```bash
cd project-directory/
ln -s ../../workBenches/devcontainer.example .
```

## Related Documentation

- [AI Provider Setup](../scripts/AI-PROVIDER-SETUP.md)
- [Implementation Guide](./IMPLEMENTATION-GUIDE.md)
- [Shared Volumes README](./README.md)
