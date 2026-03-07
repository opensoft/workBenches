# Mount Configuration Reference

## Overview

**This is the canonical reference** for all volume mounts used across workBench containers.

Every bench's `devcontainer.json` should include the **Standard Mount Set** below, plus any bench-specific mounts. When adding a new AI CLI to Layer 0, update this file, `docker-compose.mounts.yml`, and all bench `devcontainer.json` files.

All mounts use devcontainer.json `mounts` syntax with `${localEnv:USER}` and `${localEnv:HOME}` variables.

---

## Standard Mount Set (All Benches)

Every bench must include these mounts. Copy this block into new bench `devcontainer.json` files.

### Workspace & History

```jsonc
// Projects directory
"source=${localEnv:HOME}/projects,target=/workspace/projects,type=bind",
// Zsh history (named volume per bench)
"source={benchname}-zshhistory,target=/home/${localEnv:USER}/.zsh_history,type=volume",
```

### Shell Configuration (bind, readonly)

Overrides the /etc/skel defaults from Layer 0 with the host user's actual shell config.

```jsonc
"source=${localEnv:HOME}/.zshrc,target=/home/${localEnv:USER}/.zshrc,type=bind,readonly",
"source=${localEnv:HOME}/.oh-my-zsh,target=/home/${localEnv:USER}/.oh-my-zsh,type=bind,readonly",
"source=${localEnv:HOME}/.p10k.zsh,target=/home/${localEnv:USER}/.p10k.zsh,type=bind,readonly",
"source=${localEnv:HOME}/.bashrc,target=/home/${localEnv:USER}/.bashrc,type=bind,readonly",
```

### Development Credentials (bind, readonly)

```jsonc
// Git configuration
"source=${localEnv:HOME}/.gitconfig,target=/home/${localEnv:USER}/.gitconfig,type=bind,readonly",
// SSH keys and configuration
"source=${localEnv:HOME}/.ssh,target=/home/${localEnv:USER}/.ssh,type=bind,readonly",
// GitHub CLI configuration
"source=${localEnv:HOME}/.config/gh,target=/home/${localEnv:USER}/.config/gh,type=bind,readonly",
```

### AI Credential Mounts

Each AI CLI is installed in Layer 0 but stores credentials on the host. These mounts provide authentication inside the container.

```jsonc
// Claude Code (Anthropic) — native installer
// Auth: ~/.claude/ (session, config), ~/.claude.json (legacy config)
"source=${localEnv:HOME}/.claude,target=/home/${localEnv:USER}/.claude,type=bind,consistency=cached",
"source=${localEnv:HOME}/.claude.json,target=/home/${localEnv:USER}/.claude.json,type=bind,consistency=cached",

// OpenAI Codex — @openai/codex (npm)
"source=${localEnv:HOME}/.codex,target=/home/${localEnv:USER}/.codex,type=bind,consistency=cached",

// Google Gemini — @google/gemini-cli (npm)
"source=${localEnv:HOME}/.gemini,target=/home/${localEnv:USER}/.gemini,type=bind,consistency=cached",

// Grok (xAI) — @xai-org/grok-cli (npm)
"source=${localEnv:HOME}/.grok,target=/home/${localEnv:USER}/.grok,type=bind,readonly",

// GitHub Copilot — @githubnext/github-copilot-cli (npm)
"source=${localEnv:HOME}/.copilot-cli,target=/home/${localEnv:USER}/.copilot-cli,type=bind,readonly",

// NotebookLM CLI — notebooklm-py (uv), auth via host browser
"source=${localEnv:HOME}/.notebooklm,target=/home/${localEnv:USER}/.notebooklm,type=bind,consistency=cached",

// NotebookLM MCP CLI — notebooklm-mcp-cli (uv), auth via host browser
"source=${localEnv:HOME}/.notebooklm-mcp-cli,target=/home/${localEnv:USER}/.notebooklm-mcp-cli,type=bind,consistency=cached",
```

### Infrastructure Mounts (conditional)

```jsonc
// Docker socket (only for benches with Docker CLI installed)
"source=/var/run/docker.sock,target=/var/run/docker.sock,type=bind",
```

> **Note:** Only include the Docker socket mount in benches that have Docker CLI installed (e.g., javaBench, dotNetBench). Not needed for benches without container tooling.

---

## AI Credential Summary

Reference mapping each Layer 0 AI CLI to its credential path and mount type.

**CLI** → **Install Method** → **Credential Path** → **Mount Type**

- Claude Code → native installer → `~/.claude/`, `~/.claude.json` → cached
- OpenAI Codex → npm (`@openai/codex`) → `~/.codex/` → cached
- Google Gemini → npm (`@google/gemini-cli`) → `~/.gemini/` → cached
- Grok → npm (`@xai-org/grok-cli`) → `~/.grok/` → readonly
- GitHub Copilot → npm (`@githubnext/github-copilot-cli`) → `~/.copilot-cli/` → readonly
- OpenCode → built from source (Opensoft/opencode fork) → config baked into image via `/etc/skel` → no mount needed
- oh-my-opencode → built from source (darrenhinde fork) → plugin at `/opt/opencode/plugin` → no mount needed
- Letta Code → npm (`@letta-ai/letta-code`) → uses env vars or interactive auth → no mount needed
- OpenSpec → npm (`@fission-ai/openspec`) → no credential mount needed
- spec-kit → uv (`specify-cli`) → no credential mount needed
- NotebookLM CLI → uv (`notebooklm-py`) → `~/.notebooklm/` → cached (auth on host via browser)
- NotebookLM MCP → uv (`notebooklm-mcp-cli`) → `~/.notebooklm-mcp-cli/` → cached (auth on host via browser)

### Tools with No Credential Mount Required

These tools are fully installed in the image and either use API keys from environment variables or have config baked into `/etc/skel`:

- **OpenCode** — config copied to `/etc/skel/.config/opencode/` during build
- **oh-my-opencode** — plugin installed at `/opt/opencode/plugin/`
- **Letta Code** — uses environment variable or interactive auth
- **OpenSpec** — no persistent credentials
- **spec-kit** — no persistent credentials

### Environment Variable Auth (inherited from host shell profile)

Some tools authenticate via environment variables rather than config files. These are inherited from the host shell via the `.zshrc`/`.bashrc` bind mounts:

- `ANTHROPIC_API_KEY` — Claude API fallback
- `OPENAI_API_KEY` — Codex API fallback
- `GOOGLE_API_KEY` — Gemini API fallback
- `GITHUB_TOKEN` — Copilot / GH CLI fallback

---

## Bench-Specific Mounts

Add these alongside the standard mount set in each bench's `devcontainer.json`.

### javaBench
```jsonc
"source=javabench-m2cache,target=/workspace/m2repo,type=volume",
"source=javabench-gradlecache,target=/workspace/.gradle,type=volume",
```

### dotNetBench
```jsonc
// Docker socket (has Docker CLI)
"source=/var/run/docker.sock,target=/var/run/docker.sock,type=bind",
```
Also sets `containerEnv`: `"DOCKER_HOST": "unix:///var/run/docker.sock"`

### frappeBench
Uses docker-compose (multi-service architecture with MariaDB, Redis, Nginx). Mounts defined in `docker-compose.yml`.

### cppBench, goBench, pythonBench, flutterBench, gentecBench
No additional bench-specific mounts beyond the standard set.

---

## Security Notes

### Read-Only Mounts
Credentials and configs that should never be written from inside the container:
- Git config (`.gitconfig`)
- SSH keys (`.ssh`)
- GitHub CLI (`.config/gh`)
- Grok credentials (`.grok`)
- Copilot credentials (`.copilot-cli`)
- Shell configs (`.zshrc`, `.oh-my-zsh`, `.p10k.zsh`, `.bashrc`)

### Cached Mounts
AI tool credentials use `consistency=cached` for performance — frequently accessed, rarely modified:
- Claude (`.claude/`, `.claude.json`)
- Codex (`.codex/`)
- Gemini (`.gemini/`)
- NotebookLM (`.notebooklm/`, `.notebooklm-mcp-cli/`)

---

## Adding a New AI CLI

When a new AI CLI is added to Layer 0 (`base-image/install-ai-clis.sh`):

1. **Install** the CLI in `install-ai-clis.sh`
2. **Determine** if it needs a credential mount (check where it stores auth)
3. **Update this file** — add to AI Credential Summary and Standard Mount Set
4. **Update** `docker-compose.mounts.yml` (reference template)
5. **Update** every bench `devcontainer.json` with the new mount
6. **Update** `CONTAINER-ARCHITECTURE.md` Layer 0 section

---

## Troubleshooting

### AI Tool Says "Not Authenticated"
1. Verify credentials exist on host: `ls ~/.claude ~/.codex ~/.gemini`
2. Check mount in `devcontainer.json` includes the credential directory
3. Rebuild container to apply mount changes
4. Verify inside container: `ls ~/.claude` should show files

### Permission Denied on Mounted Directories
1. Check host directory permissions: `ls -la ~/.claude`
2. Ensure UID/GID matches: `id` on host vs `id` in container
3. For read-only mounts, write failure is expected and correct

### Missing SSH Keys
1. Verify SSH keys exist: `ls ~/.ssh/id_*`
2. Inside container: `ssh-add -l` to verify keys are accessible
3. May need to start ssh-agent inside container

### Mount Target Doesn't Exist on Host
If a host credential directory doesn't exist yet (e.g. you haven't used an AI tool), create it first:
```bash
mkdir -p ~/.notebooklm ~/.notebooklm-mcp-cli
```
Otherwise the container may fail to start with a file-not-found error.

---

## Related Documentation

- `CONTAINER-ARCHITECTURE.md` — Layer 0 tool inventory and overall architecture
- `ai-credentials-management.md` — Credential setup and rotation
- `scripts/AI-PROVIDER-SETUP.md` — AI provider priority configuration
- `base-image/install-ai-clis.sh` — AI CLI installation script (source of truth for what's installed)
