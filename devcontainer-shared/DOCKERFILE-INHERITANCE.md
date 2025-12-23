# Dockerfile Inheritance Strategy

## Challenge

Unlike `docker-compose.override.yml` (which can be symlinked), Dockerfiles cannot be symlinked because they must be in the Docker build context. However, we still want a single source of truth for AI CLI installations.

## Solution: Shared Installation Script

We use a **shared installation script** that all Dockerfiles reference. This maintains a single source of truth while working within Docker's constraints.

## Architecture

```
workBenches/
├── devcontainer-shared/
│   ├── install-ai-clis.sh              ← SOURCE OF TRUTH for AI CLI installations
│   └── docker-compose.override.yml     ← SOURCE OF TRUTH for AI credential mounts
│
├── devcontainer.example/
│   └── Dockerfile                       ← References ../devcontainer-shared/install-ai-clis.sh
│
└── devBenches/
    ├── frappeBench/devcontainer.example/
    │   └── Dockerfile                   ← References ../../../devcontainer-shared/install-ai-clis.sh
    ├── dotNetBench/.devcontainer/
    │   └── Dockerfile                   ← References ../../../devcontainer-shared/install-ai-clis.sh
    └── flutterBench/.devcontainer/
        └── Dockerfile                   ← References ../../../devcontainer-shared/install-ai-clis.sh
```

## Usage in Dockerfiles

### In Any Bench's Dockerfile

Replace the AI CLI installation section with:

```dockerfile
# USERNAME: Installing AI CLI tools from shared script
# This maintains a single source of truth for AI CLI installations
# See: devcontainer-shared/install-ai-clis.sh for the full list
COPY --chown=$USERNAME:$USERNAME ../devcontainer-shared/install-ai-clis.sh /tmp/
RUN bash /tmp/install-ai-clis.sh && rm /tmp/install-ai-clis.sh
```

**Path variations by location:**
- `workBenches/devcontainer.example/`: `../devcontainer-shared/`
- `devBenches/frappeBench/`: `../../../devcontainer-shared/`
- `devBenches/dotNetBench/`: `../../../devcontainer-shared/`
- `devBenches/flutterBench/`: `../../../devcontainer-shared/`

## Installed AI CLIs

The shared script installs:

| Tool | CLI Command | Package | Purpose |
|------|-------------|---------|---------|
| OpenSpec | `openspec` | `@fission-ai/openspec` | API spec generation |
| Claude Code | `claude` | `@anthropic-ai/claude-code` | Claude AI coding assistant |
| Codex | `codex` | `@openai/codex` | OpenAI Codex coding |
| Gemini | `gemini` | `@google/gemini-cli` | Google Gemini AI |
| Copilot | `copilot` | `@githubnext/github-copilot-cli` | GitHub Copilot |
| Grok | `grok` | `@xai-org/grok-cli` | xAI Grok |
| OpenCode | `opencode` | `opencode-ai` | Open source AI agent |
| Letta Code | `letta` | `@letta-ai/letta-code` | Memory-first agent |

## Credential Mounts

The shared `docker-compose.override.yml` automatically mounts:

- `~/.claude/` - Claude config and sessions
- `~/.codex/` - Codex OAuth tokens
- `~/.grok/` - Grok API keys
- `~/.gemini/` - Gemini OAuth
- `~/.copilot-cli/` - Copilot sessions
- `~/.letta/` - Letta memory and config
- `~/.opencode/` - OpenCode config
- `~/.config/gh/` - GitHub CLI (for Copilot)

## Adding New AI Tools

### Step 1: Update Installation Script

Edit `devcontainer-shared/install-ai-clis.sh`:

```bash
echo "Installing NewAI CLI..."
npm install -g @newai/cli
```

### Step 2: Update Credential Mounts

Edit `devcontainer-shared/docker-compose.override.yml`:

```yaml
# NewAI
- ~/.newai:/home/${USER:-vscode}/.newai:ro
```

### Step 3: Rebuild Containers

```bash
cd your-project/devcontainer.example/
docker-compose build
docker-compose up -d
```

**That's it!** All projects now have the new AI tool.

## Benefits

### ✅ Single Source of Truth
- Edit `install-ai-clis.sh` once
- All Dockerfiles reference the same script
- No duplication of installation commands

### ✅ Easy Updates
```bash
# Add new AI tool
vim devcontainer-shared/install-ai-clis.sh

# Rebuild affected containers
docker-compose build
```

### ✅ Version Control
- Script is tracked in git
- Changes are visible in diffs
- Easy to roll back if needed

### ✅ Works with Docker Build Context
- COPY command brings script into context
- No symlink issues
- Standard Docker pattern

## Comparison: Override vs. Installation

| Aspect | docker-compose.override.yml | install-ai-clis.sh |
|--------|----------------------------|---------------------|
| **Type** | Configuration mounts | Software installation |
| **Inheritance** | Symlink | COPY in Dockerfile |
| **Update Trigger** | Restart container | Rebuild image |
| **Changes Take Effect** | Immediately | After rebuild |
| **Best For** | Credentials, configs | Installing tools |

## Migration Guide

### For Existing Dockerfiles

**Before:**
```dockerfile
RUN npm install -g @anthropic-ai/claude-code
RUN npm install -g @openai/codex
RUN npm install -g @google/gemini-cli
# ... many more lines
```

**After:**
```dockerfile
COPY --chown=$USERNAME:$USERNAME ../devcontainer-shared/install-ai-clis.sh /tmp/
RUN bash /tmp/install-ai-clis.sh && rm /tmp/install-ai-clis.sh
```

**Result:** 15+ lines → 2 lines

### Step-by-Step Migration

1. **Locate AI installation section** in your Dockerfile
2. **Replace with COPY + RUN** (adjust path as needed)
3. **Test build**: `docker-compose build`
4. **Verify tools installed**: `docker-compose run service claude --version`

## Troubleshooting

### Script Not Found During Build

**Error**: `COPY failed: file not found`

**Fix**: Check relative path from Dockerfile location:
```bash
# From Dockerfile location, verify:
ls -la ../devcontainer-shared/install-ai-clis.sh
# or
ls -la ../../../devcontainer-shared/install-ai-clis.sh
```

### Permission Denied

**Error**: `/tmp/install-ai-clis.sh: Permission denied`

**Fix**: Script is executable:
```bash
chmod +x workBenches/devcontainer-shared/install-ai-clis.sh
```

### npm Install Fails

**Error**: `npm ERR! code E404`

**Cause**: Package doesn't exist or name changed

**Fix**: Update package name in `install-ai-clis.sh`

### Tool Not in PATH

**Symptom**: `command not found` for AI CLI

**Check**: Verify PATH includes `~/.npm-global/bin`:
```bash
echo $PATH | grep npm-global
```

**Fix**: Dockerfile should have:
```dockerfile
RUN echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> ~/.zshrc
```

## Examples

### frappeBench Dockerfile

```dockerfile
# ... earlier sections ...

USER $USERNAME

# Configure npm
RUN mkdir -p $HOME/.npm-global && npm config set prefix $HOME/.npm-global

# Install AI CLIs from shared script
COPY --chown=$USERNAME:$USERNAME ../../../devcontainer-shared/install-ai-clis.sh /tmp/
RUN bash /tmp/install-ai-clis.sh && rm /tmp/install-ai-clis.sh

# ... rest of Dockerfile ...
```

### Testing New AI Tool

```bash
# 1. Add to installation script
echo 'npm install -g @example/ai-tool' >> devcontainer-shared/install-ai-clis.sh

# 2. Add credential mount
echo '- ~/.example-ai:/home/${USER:-vscode}/.example-ai:ro' \
  >> devcontainer-shared/docker-compose.override.yml

# 3. Test in one project
cd workBenches/devcontainer.example/
docker-compose build
docker-compose up -d
docker-compose exec service example-ai --version

# 4. If successful, commit changes
git add devcontainer-shared/
git commit -m "Add Example AI tool"
```

## Related Documentation

- [Symlink Architecture](./SYMLINK-ARCHITECTURE.md) - For docker-compose.override.yml
- [Implementation Guide](./IMPLEMENTATION-GUIDE.md) - Quick start
- [AI Provider Setup](../scripts/AI-PROVIDER-SETUP.md) - AI detection and priority
