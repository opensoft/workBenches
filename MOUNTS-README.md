# Centralized Mount Configuration System

## Overview

This system provides a standardized way to mount AI credentials, SSH keys, and other shared resources across all workbench containers using the layered image architecture.

## Architecture

```
workBenches/
├── docker-compose.mounts.yml    # Master mount configuration
├── base-image/                   # Layer 0: AI CLIs installed here
├── devBenches/
│   ├── base-image/              # Layer 1a: Dev tools
│   ├── cppBench/                # Layer 2: Uses standard mounts
│   ├── frappeBench/             # Layer 2: Uses standard mounts
│   └── ...
└── adminBenches/
    ├── base-image/              # Layer 1b: Admin tools
    └── ...
```

## What Gets Mounted

### AI Coding Assistants (from Layer 0)
All AI tools are installed in Layer 0 (`workbench-base`), but credentials are stored on the host and mounted:

- `~/.claude` - Anthropic Claude Code
- `~/.codex` - OpenAI Codex
- `~/.gemini` - Google Gemini
- `~/.cursor` - Cursor AI
- `~/.copilot` - GitHub Copilot
- `~/.opencode` - OpenCode AI
- `~/.letta` - Letta Code
- `~/.config/opencode` - OpenCode configuration

### Development Credentials
- `~/.config/gh` - GitHub CLI (read-only)
- `~/.gitconfig` - Git configuration (read-only)
- `~/.git-credentials` - Git credentials (read-only)
- `~/.ssh` - SSH keys (read-only for security)

### Container-Specific Persistence
Each bench gets its own named volumes:
- `{bench}-vscode-server` - VSCode server files
- `{bench}-bash-history` - Command history
- Bench-specific tool caches (e.g., `cppbench-conan`)

## Using in Your Bench

### Option 1: Copy Standard Mounts (Current Approach)

Copy the mount configuration from `docker-compose.mounts.yml` into your bench's `docker-compose.yml`:

```yaml
services:
  your-bench:
    volumes:
      # Standard mounts (copy from docker-compose.mounts.yml)
      - ../..:/workspace:cached
      - ~/.claude:/home/${USER}/.claude:cached
      # ... etc
      
      # Add bench-specific volumes
      - yourbench-custom:/home/${USER}/.custom
```

### Option 2: Use Multiple Compose Files

Reference both files when starting:

```bash
docker-compose -f docker-compose.yml -f ../../docker-compose.mounts.yml up
```

### Option 3: Use YAML Merge (Advanced)

Use YAML anchors in a combined file (requires merging).

## Environment Variables

The mount configuration uses these variables:

- `${USER}` - Your username (e.g., `brett`)
- `${BENCH_NAME}` - Bench-specific prefix for volumes (optional)

Set these in your `.env` file:

```bash
USER=brett
BENCH_NAME=cppbench
```

## Security Notes

### Read-Only Mounts
Credentials and configs are mounted read-only (`:ro`) for security:
- Git config (`.gitconfig`, `.git-credentials`)
- GitHub CLI (`.config/gh`)
- SSH keys (`.ssh`)

### AI Credentials (Cached)
AI tool credentials use `:cached` for performance since they're frequently accessed but rarely modified.

## Adding New AI Tools

When new AI tools are added to Layer 0:

1. Update `workBenches/base-image/install-ai-clis.sh`
2. Add the mount to `workBenches/docker-compose.mounts.yml`
3. Update this README with the new tool
4. Rebuild Layer 0: `cd base-image && ./build.sh`
5. Update each bench's docker-compose.yml with the new mount

## Migration Guide

To migrate an existing bench to use standard mounts:

1. **Backup** your current `docker-compose.yml`
2. **Remove** the full home mount: `- ~:/home/${USER}:cached`
3. **Add** standard mounts from `docker-compose.mounts.yml`
4. **Add** bench-specific volumes (e.g., Conan, pip cache)
5. **Test** that AI tools and credentials work
6. **Rebuild** the container

Example migration:

```yaml
# BEFORE (problematic)
volumes:
  - ~:/home/brett:cached
  - ../..:/workspace:cached

# AFTER (selective)
volumes:
  - ../..:/workspace:cached
  - ~/.claude:/home/${USER}/.claude:cached
  - ~/.codex:/home/${USER}/.codex:cached
  # ... (all standard mounts)
  - benchname-vscode-server:/home/${USER}/.vscode-server
```

## Troubleshooting

### AI Tool Says "Not Authenticated"

**Problem:** AI extension asks for login inside container

**Solution:**
1. Verify credentials exist on host: `ls ~/.claude ~/.codex ~/.gemini`
2. Check mount in docker-compose.yml includes the credential directory
3. Rebuild container to apply mount changes
4. Verify inside container: `ls ~/.claude` should show files

### Permission Denied on Mounted Directories

**Problem:** Cannot access mounted directories inside container

**Solution:**
1. Check host directory permissions: `ls -la ~/.claude`
2. Ensure directory is readable by your user
3. For read-only mounts, this is expected and correct
4. Check UID/GID matches: `id` on host vs `id` in container

### Missing SSH Keys

**Problem:** Git push fails with "Permission denied (publickey)"

**Solution:**
1. Verify SSH keys exist: `ls ~/.ssh/id_*`
2. Check mount is present: `- ~/.ssh:/home/${USER}/.ssh:ro`
3. Inside container: `ssh-add -l` to verify keys are accessible
4. May need to start ssh-agent inside container

## Bench-Specific Volumes

Each bench should add its own tool-specific volumes:

### C++ Bench (cppBench)
```yaml
- cppbench-conan:/home/${USER}/.conan2
```

### Python Bench
```yaml
- pythonbench-pip-cache:/home/${USER}/.cache/pip
- pythonbench-venv:/home/${USER}/.local/venvs
```

### Frappe Bench
```yaml
- frappebench-frappe:/home/${USER}/frappe-bench
- frappebench-node-modules:/workspace/node_modules
```

## Maintenance

### When to Update

Update `docker-compose.mounts.yml` when:
- New AI coding assistant is added to Layer 0
- New shared credential type is needed
- Security policy changes (e.g., making more mounts read-only)

### Versioning

Consider versioning the mount configuration:
- Tag major changes with git
- Document breaking changes in this README
- Announce updates to all bench maintainers

## References

- Layer 0 AI CLI installation: `workBenches/base-image/install-ai-clis.sh`
- Container architecture: `workBenches/CONTAINER-ARCHITECTURE.md`
- AI setup guide: `.devcontainer/AI_SETUP.md` (in each bench)
