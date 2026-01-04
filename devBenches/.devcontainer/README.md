# DevBench Base Generic Container

A fast-launching generic development environment using the pre-built `devbench-base` image.

## What's Included

**Pre-installed in devbench-base image:**
- Python 3 with development tools (black, flake8, pytest, etc.)
- Node.js LTS with npm and yarn
- AI CLI tools (OpenCode, Claude Code, Codex, Gemini, Copilot)
- oh-my-opencode plugin with built-in agents
- Zsh with Oh-My-Zsh
- Git, vim, modern CLI tools

**Mounted from host:**
- AI credentials (`~/.config/opencode`, `~/.anthropic`, `~/.openai`, `~/.google`)
- Git config and SSH keys
- Shell history (persistent)

## Quick Start

### Prerequisites

1. Build the base image (if not already built):
   ```bash
   cd ..
   ./setup.sh
   ```

2. Open in VS Code:
   ```bash
   code .
   ```

3. VS Code will prompt: "Reopen in Container" - click it

## Usage

Once inside the container:

```bash
# Test OpenCode installation
opencode --version

# Use AI assistants
opencode "explain this codebase"

# Python development
python3 --version
pip install <package>

# Node.js development
node --version
npm install <package>
```

## AI Credentials

OpenCode will use your host AI credentials automatically. To authenticate:

```bash
# Anthropic (Claude)
opencode auth login

# Follow prompts to authenticate with your provider
```

## Customization

To customize for your use case:
- Edit `devcontainer.json` to add VS Code extensions
- Edit `docker-compose.yml` to mount additional volumes
- No need to rebuild the image - it's pre-built!

## Benefits

- ⚡ **Fast startup** - Uses pre-built image (no build time)
- 🔧 **Full-featured** - Python, Node, AI tools ready to go
- 🔐 **Secure** - Uses your existing AI credentials
- 💾 **Persistent** - Shell history and configs saved
- 🎯 **Generic** - No language-specific bloat, add what you need
