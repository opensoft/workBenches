# Shared DevContainer Configuration Fragments

## Overview

This directory contains reusable YAML fragments for Docker Compose configurations used across all bench types (frappeBench, dotNetBench, flutterBench, etc.).

## Purpose

- **Single Source of Truth**: Update volume mounts in one place, apply to all benches
- **Consistency**: Ensure all benches have the same AI credentials and common mounts
- **Maintainability**: Easy to add new AI providers or configurations
- **Version Control**: Track changes to shared configurations

## Available Fragments

### 1. `volumes-common.yml`
Common volume mounts needed by all benches:
- Docker socket
- Shell configurations (zsh, bash, oh-my-zsh)
- Git configuration
- SSH keys and configuration
- GitHub CLI configuration

### 2. `volumes-ai-credentials.yml`
AI agent credential mounts:
- Claude (Anthropic) - OAuth and configs
- Grok (xAI) - API keys and memory
- Codex (OpenAI) - OAuth session
- GitHub Copilot CLI - OAuth sessions

## Usage Methods

### Method 1: Docker Compose Override (Recommended)

Use `docker-compose.override.yml` to add AI credentials without modifying main config:

**Step 1**: Copy or symlink the shared override:
```bash
cd devBenches/yourBench/.devcontainer/
cp ../../devcontainer-shared/docker-compose.override.yml .
```

**Step 2**: Update service name to match your `docker-compose.yml`:
```yaml
# docker-compose.override.yml
services:
  your-service-name:  # Change this to match docker-compose.yml
    volumes:
      # AI credentials and common mounts
      - ~/.claude:/home/${USER}/.claude:ro
      # ... (all mounts included)
```

**Step 3**: Docker Compose automatically merges both files:
```bash
docker-compose config  # See merged result
docker-compose up -d   # Use merged configuration
```

**Benefits:**
- ✅ Clean separation of base config and user mounts
- ✅ Easy to update: just replace override file
- ✅ Can be in .gitignore for user-specific settings
- ✅ No merge conflicts with main docker-compose.yml
- ✅ Standard Docker Compose feature

### Method 2: Script-Based Merge

Use the provided script to automatically merge fragments:

```bash
# From a bench directory
../../devcontainer-shared/scripts/merge-shared-volumes.sh docker-compose.yml
```

This will:
1. Detect existing `docker-compose.yml`
2. Merge shared volume fragments
3. Create backup of original
4. Write updated file

### Method 3: Manual Copy-Paste

For one-time setup or customization:

1. Copy volume definitions from fragment files
2. Paste into your `docker-compose.yml`
3. Update manually as needed

**Not recommended** - loses benefit of shared maintenance.

## File Structure

```
devcontainer-shared/
├── README.md                      # This file
├── volumes-common.yml             # Common mounts (shell, git, SSH)
├── volumes-ai-credentials.yml     # AI credential mounts
└── scripts/
    ├── merge-shared-volumes.sh    # Helper script to merge fragments
    └── validate-mounts.sh         # Validate mounts exist on host
```

## Adding New Shared Mounts

### To Add a New AI Provider

1. Edit `volumes-ai-credentials.yml`
2. Add mount following existing pattern:
   ```yaml
   # NewAI Provider
   - ~/.newai:/home/${USER:-vscode}/.newai:ro
   ```
3. Update this README
4. Notify bench maintainers to pull changes

### To Add Common Configuration

1. Edit `volumes-common.yml`
2. Add mount following existing pattern
3. Update this README
4. Test with one bench first

## Version Control

Each fragment file has a version comment at the top:
```yaml
# Version: 1.0.0
```

Update version when making changes:
- **Major (X.0.0)**: Breaking changes, requires bench updates
- **Minor (1.X.0)**: New mounts added, backward compatible
- **Patch (1.0.X)**: Documentation or comment updates

## Applying to Existing Benches

### Quick Update All Benches

```bash
# From workBenches root
./devcontainer-shared/scripts/apply-to-all-benches.sh
```

### Manual Update Per Bench

For each bench type:

1. **frappeBench**:
   ```bash
   cd devBenches/frappeBench/devcontainer.example
   # Add or update volumes to include shared fragments
   ```

2. **dotNetBench**:
   ```bash
   cd devBenches/dotNetBench/.devcontainer
   # Add or update volumes to include shared fragments
   ```

3. **flutterBench**:
   ```bash
   cd devBenches/flutterBench/.devcontainer
   # Add or update volumes to include shared fragments
   ```

## Validation

Test that mounts work after updating:

```bash
# Build and start container
docker-compose up -d

# Verify AI credentials accessible
docker-compose exec your-service bash -c "ls -la ~/.claude ~/.codex ~/.grok"

# Test AI CLI tools
docker-compose exec your-service claude --version
docker-compose exec your-service codex --version
```

## Troubleshooting

### Mounts Not Working

**Symptom**: Files/directories not visible in container

**Solutions**:
1. Check paths exist on host: `ls -la ~/.claude`
2. Verify docker-compose syntax: `docker-compose config`
3. Rebuild container: `docker-compose up -d --build`

### Permission Errors

**Symptom**: Permission denied accessing mounted files

**Solutions**:
1. Check container user matches host: `${UID}:${GID}`
2. Verify file permissions on host: `ls -la ~/.claude`
3. Ensure read-only mount appropriate: `:ro`

### Path Not Found

**Symptom**: Docker complains mount source doesn't exist

**Solutions**:
1. Some mounts are optional (e.g., `~/.copilot-cli/`)
2. Comment out mounts for tools not installed
3. Or create empty directory: `mkdir -p ~/.copilot-cli`

## Best Practices

1. **Always Use Read-Only** (`:ro`) for credentials
2. **Test in One Bench First** before applying to all
3. **Document Changes** in commit messages
4. **Version Bump** when modifying fragments
5. **Validate** after each change

## Related Documentation

- [AI Provider Setup](../scripts/AI-PROVIDER-SETUP.md)
- [AI Credentials Reference](./AI-CREDENTIALS-REFERENCE.md)
- [DevContainer Best Practices](../docs/DEVCONTAINER-BEST-PRACTICES.md)

## Maintenance Schedule

- **Weekly**: Check for new AI providers
- **Monthly**: Review and update documentation
- **Quarterly**: Validate all benches use latest version
- **As Needed**: When adding new tools or credentials

## Support

For issues or questions:
1. Check this README first
2. Review related documentation
3. Test with validation scripts
4. Ask in team chat if still stuck
