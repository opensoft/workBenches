# Implementation Guide: Shared Volume Configuration

## Quick Start

The best way to add AI credentials and common mounts is using `docker-compose.override.yml`. This keeps your main `docker-compose.yml` clean and makes updates easy.

## Recommended Approach: Symlink Override File

### For Any Bench (New or Existing)

1. **Navigate to your bench's devcontainer directory:**
   ```bash
   cd devBenches/yourBench/.devcontainer/
   # or
   cd devBenches/yourBench/devcontainer.example/
   ```

2. **Create symlink to shared override:**
   ```bash
   ln -s ../../devcontainer-shared/docker-compose.override.yml .
   ```

3. **Edit the override to match your service name:**
   ```bash
   # If using symlink, copy it first to customize
   cp docker-compose.override.yml docker-compose.override.yml.local
   rm docker-compose.override.yml
   mv docker-compose.override.yml.local docker-compose.override.yml
   
   # Edit service name to match your docker-compose.yml
   # Change 'frappe:' to your service name (e.g., 'main-service:', 'dev:', 'app:')
   nano docker-compose.override.yml
   ```

4. **Test:**
   ```bash
   docker-compose config  # Verify merge worked
   docker-compose up -d
   ```

### Benefits of Override Pattern

- ✅ **Clean separation**: Main config vs. user-specific mounts
- ✅ **Easy updates**: Update shared override, copy to benches
- ✅ **Git-friendly**: Override can be in .gitignore if desired
- ✅ **No merge conflicts**: Override doesn't touch main docker-compose.yml
- ✅ **Standard Docker**: Uses built-in compose merge feature

## Alternative: Copy Override File

If you need bench-specific customizations:

```bash
cd devBenches/yourBench/.devcontainer/
cp ../../devcontainer-shared/docker-compose.override.yml .
# Edit to customize for this bench
```

## Legacy: Inline in docker-compose.yml

If you prefer to keep everything in one file:

```yaml
services:
  main-service:
    volumes:
      # Workspace-specific volumes
      - ../:/workspace:cached
      
      # == SHARED COMMON MOUNTS ==
      # Docker socket
      - /var/run/docker.sock:/var/run/docker.sock:rw
      
      # Shell configurations
      - ~/.zshrc:/home/${USER:-vscode}/.zshrc:ro
      - ~/.bashrc:/home/${USER:-vscode}/.bashrc:ro
      - ~/.oh-my-zsh:/home/${USER:-vscode}/.oh-my-zsh:ro
      - ~/.p10k.zsh:/home/${USER:-vscode}/.p10k.zsh:ro
      
      # Git configuration
      - ~/.gitconfig:/home/${USER:-vscode}/.gitconfig:ro
      
      # SSH keys
      - ~/.ssh/config:/home/${USER:-vscode}/.ssh/config:ro
      - ~/.ssh/id_ed25519:/home/${USER:-vscode}/.ssh/id_ed25519:ro
      - ~/.ssh/id_ed25519.pub:/home/${USER:-vscode}/.ssh/id_ed25519.pub:ro
      - ~/.ssh/id_rsa_ado:/home/${USER:-vscode}/.ssh/id_rsa_ado:ro
      - ~/.ssh/id_rsa_ado.pub:/home/${USER:-vscode}/.ssh/id_rsa_ado.pub:ro
      - ~/.ssh/known_hosts:/home/${USER:-vscode}/.ssh/known_hosts:ro
      
      # GitHub CLI
      - ~/.config/gh:/home/${USER:-vscode}/.config/gh:ro
      
      # == AI CREDENTIALS ==
      # Claude
      - ~/.claude:/home/${USER:-vscode}/.claude:ro
      - ~/.claude.json:/home/${USER:-vscode}/.claude.json:ro
      - ~/.claude/.credentials.json:/home/${USER:-vscode}/.claude/.credentials.json:ro
      
      # Grok
      - ~/.grok:/home/${USER:-vscode}/.grok:ro
      
      # Codex
      - ~/.codex:/home/${USER:-vscode}/.codex:ro
      
      # Copilot
      - ~/.copilot-cli:/home/${USER:-vscode}/.copilot-cli:ro
```

## For Existing Benches

### Option A: Manual Update (Recommended for Now)

1. Open your bench's `docker-compose.yml`
2. Find the `volumes:` section of your main service
3. Add the mounts from the template above (after workspace-specific volumes)
4. Test the container

### Option B: Copy from Reference

```bash
# Use workBenches/devcontainer.example as reference
cd devBenches/yourBench/devcontainer.example
# or
cd devBenches/yourBench/.devcontainer

# Compare with reference
diff docker-compose.yml ../../../devcontainer.example/docker-compose.yml
```

## Current Status

### ✅ Already Updated

- `workBenches/devcontainer.example/` - Main template
- `devBenches/frappeBench/devcontainer.example/` - Frappe bench template

### ⏳ Need Updates

- `devBenches/dotNetBench/.devcontainer/`
- `devBenches/flutterBench/.devcontainer/`
- `devBenches/cppBench/.devcontainer/` (if exists)

## Testing After Update

```bash
# 1. Validate compose file syntax
docker-compose config

# 2. Rebuild container
docker-compose down
docker-compose up -d --build

# 3. Verify mounts accessible
docker-compose exec main-service ls -la ~/.claude ~/.codex ~/.grok

# 4. Test AI CLI
docker-compose exec main-service claude --version
```

## Minimal Required Mounts

If you want to keep it simple, at minimum include:

```yaml
volumes:
  # Workspace
  - ../:/workspace:cached
  
  # Git (needed for version control)
  - ~/.gitconfig:/home/${USER:-vscode}/.gitconfig:ro
  
  # SSH (needed for git operations)
  - ~/.ssh:/home/${USER:-vscode}/.ssh:ro
  
  # AI Credentials (for Claude, Codex, etc.)
  - ~/.claude:/home/${USER:-vscode}/.claude:ro
  - ~/.claude.json:/home/${USER:-vscode}/.claude.json:ro
  - ~/.codex:/home/${USER:-vscode}/.codex:ro
  - ~/.grok:/home/${USER:-vscode}/.grok:ro
  - ~/.config/gh:/home/${USER:-vscode}/.config/gh:ro
```

## Future: YAML Anchors

In the future, we may switch to YAML anchors for easier maintenance. This would look like:

```yaml
# docker-compose.yml with anchors

# Reference shared volumes (future implementation)
x-common-volumes:
  &common-volumes
  - /var/run/docker.sock:/var/run/docker.sock:rw
  - ~/.gitconfig:/home/${USER:-vscode}/.gitconfig:ro
  # ... etc

services:
  main-service:
    volumes:
      - ../:/workspace:cached
      *common-volumes  # Reference anchor
```

## Questions?

- Check [README.md](./README.md) for detailed information
- See reference implementation in `workBenches/devcontainer.example/`
- Compare your config with `frappeBench/devcontainer.example/`
