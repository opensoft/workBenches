# Creating a New Bench

Instructions for creating a new development bench in the workBenches system.
This document is the authoritative reference — any AI agent or developer creating
a new bench MUST follow these instructions.

## Architecture

All benches use a layered Docker image system with runtime user mounts:

```
Layer 0: workbench-base:latest     — Ubuntu 24.04, system tools, AI CLIs
Layer 1: dev-bench-base:latest     — Python, Node.js, dev tools
Layer 2: {name}-bench:latest       — Bench-specific tools (user-agnostic)
Layer 3: {name}-bench:{username}   — User creation (built automatically)
Runtime: devcontainer.json mounts  — User credentials, shell config, AI auth
```

Layer 3 has two parts:
- **Image** (`user-layer/Dockerfile`) — creates the user account matching host UID/GID
- **Runtime** (`devcontainer.json` mounts) — bind mounts for user-specific credentials

Related docs:
- `CONTAINER-ARCHITECTURE.md` — full layer architecture details
- `MOUNTS-README.md` — canonical mount reference

## Required Files

```
devBenches/{yourBench}/
├── .devcontainer/
│   └── devcontainer.json     # Runtime config (mounts, extensions, ports)
├── Dockerfile.layer2         # Bench-specific tools (user-agnostic)
└── README.md                 # What this bench is and how to use it
```

Shared infrastructure — do NOT duplicate these:
- `scripts/ensure-layer3.sh` — builds Layer 3 user image automatically
- `user-layer/Dockerfile` — Layer 3 user creation template
- `MOUNTS-README.md` — mount reference

---

## Step 1: Create Dockerfile.layer2

Location: `devBenches/{yourBench}/Dockerfile.layer2`

```dockerfile
# Layer 2: {Your} Bench Image
# Extends Layer 1 (dev-bench-base) with {your}-specific tools
FROM dev-bench-base:latest

# Container version labels
LABEL layer="2"
LABEL layer.name="{name}-bench"
LABEL layer.version="1.0.0"
LABEL layer.description="{Your} development tools (user-agnostic)"
LABEL bench.type="{name}"

USER root

# ========================================
# {YOUR} TOOLS
# ========================================

RUN apt-get update && apt-get install -y \
    # your packages here \
    && rm -rf /var/lib/apt/lists/*

# ========================================
# SHELL CONFIGURATION (into /etc/skel)
# ========================================

# Add aliases to /etc/skel so Layer 3 user gets them via useradd -m
RUN echo '' >> /etc/skel/.zshrc && \
    echo '# {Your} Development aliases' >> /etc/skel/.zshrc && \
    echo 'alias youralias="yourcommand"' >> /etc/skel/.zshrc

# Default command
CMD ["sleep", "infinity"]
```

Rules:
- **No user creation** — Layer 3 handles that
- **No hardcoded usernames** — put config into `/etc/skel/`, not `/home/someone/`
- Everything runs as `USER root`
- Include version labels for tracking

## Step 2: Build Layer 2

```bash
docker build -t {name}-bench:latest -f devBenches/{yourBench}/Dockerfile.layer2 devBenches/{yourBench}/
```

## Step 3: Create devcontainer.json

Location: `devBenches/{yourBench}/.devcontainer/devcontainer.json`

### CRITICAL: You MUST include ALL standard mounts

The runtime mounts provide user-specific credentials, shell configuration, and AI tool
authentication. Omitting any mount will break functionality inside the container.

Copy the complete template below — do not remove any standard mount:

```jsonc
{
    "name": "{Your} Development Bench",
    "initializeCommand": "bash ${localWorkspaceFolder}/../../scripts/ensure-layer3.sh --base {name}-bench:latest",
    "image": "{name}-bench:${localEnv:USER}",
    "customizations": {
        "vscode": {
            "settings": {
                "terminal.integrated.defaultProfile.linux": "zsh"
            },
            "extensions": [
                "github.copilot",
                "eamodio.gitlens"
                // Add bench-specific extensions here
            ]
        }
    },
    "containerEnv": {
        "SHELL": "/bin/zsh"
    },
    "remoteUser": "${localEnv:USER}",
    "updateRemoteUserUID": false,
    "workspaceFolder": "/workspace",
    "mounts": [
        // =============================================
        // STANDARD MOUNT SET — REQUIRED FOR ALL BENCHES
        // Do NOT remove any of these.
        // Source of truth: MOUNTS-README.md
        // =============================================

        // Workspace & history
        "source={namebench}-zshhistory,target=/home/${localEnv:USER}/.zsh_history,type=volume",
        "source=${localEnv:HOME}/projects,target=/workspace/projects,type=bind",

        // Shell configurations (bind, readonly)
        "source=${localEnv:HOME}/.zshrc,target=/home/${localEnv:USER}/.zshrc,type=bind,readonly",
        "source=${localEnv:HOME}/.oh-my-zsh,target=/home/${localEnv:USER}/.oh-my-zsh,type=bind,readonly",
        "source=${localEnv:HOME}/.p10k.zsh,target=/home/${localEnv:USER}/.p10k.zsh,type=bind,readonly",
        "source=${localEnv:HOME}/.bashrc,target=/home/${localEnv:USER}/.bashrc,type=bind,readonly",

        // Development credentials (bind, readonly)
        "source=${localEnv:HOME}/.gitconfig,target=/home/${localEnv:USER}/.gitconfig,type=bind,readonly",
        "source=${localEnv:HOME}/.ssh,target=/home/${localEnv:USER}/.ssh,type=bind,readonly",
        "source=${localEnv:HOME}/.config/gh,target=/home/${localEnv:USER}/.config/gh,type=bind,readonly",

        // AI Agent Credentials
        // Claude (Anthropic) — native installer
        "source=${localEnv:HOME}/.claude,target=/home/${localEnv:USER}/.claude,type=bind,consistency=cached",
        "source=${localEnv:HOME}/.claude.json,target=/home/${localEnv:USER}/.claude.json,type=bind,consistency=cached",
        // Codex (OpenAI)
        "source=${localEnv:HOME}/.codex,target=/home/${localEnv:USER}/.codex,type=bind,consistency=cached",
        // Gemini (Google)
        "source=${localEnv:HOME}/.gemini,target=/home/${localEnv:USER}/.gemini,type=bind,consistency=cached",
        // Grok (xAI)
        "source=${localEnv:HOME}/.grok,target=/home/${localEnv:USER}/.grok,type=bind,readonly",
        // GitHub Copilot CLI
        "source=${localEnv:HOME}/.copilot-cli,target=/home/${localEnv:USER}/.copilot-cli,type=bind,readonly",
        // NotebookLM (auth tokens from host browser)
        "source=${localEnv:HOME}/.notebooklm,target=/home/${localEnv:USER}/.notebooklm,type=bind,consistency=cached",
        "source=${localEnv:HOME}/.notebooklm-mcp-cli,target=/home/${localEnv:USER}/.notebooklm-mcp-cli,type=bind,consistency=cached"

        // =============================================
        // BENCH-SPECIFIC MOUNTS — add yours below
        // =============================================
        // Docker socket (only if bench has Docker CLI):
        // ,"source=/var/run/docker.sock,target=/var/run/docker.sock,type=bind"
        // Tool caches (named volumes):
        // ,"source={namebench}-somecache,target=/path/to/cache,type=volume"
    ],
    "forwardPorts": [],
    "portsAttributes": {}
}
```

If the bench installs Docker CLI, also add to `containerEnv`:
```jsonc
"DOCKER_HOST": "unix:///var/run/docker.sock"
```

If the bench needs `--chown` for directories (e.g., `/opt/something`), add to `initializeCommand`:
```jsonc
"initializeCommand": "bash ${localWorkspaceFolder}/../../scripts/ensure-layer3.sh --base {name}-bench:latest --chown /opt/something"
```

## Step 4: Create README.md

Location: `devBenches/{yourBench}/README.md`

Include:
- Purpose of the bench
- Tools installed in Layer 2 (with versions)
- How to build: `docker build -t {name}-bench:latest -f Dockerfile.layer2 .`
- How to open: open the bench folder in VS Code, "Reopen in Container"
- Forwarded ports and what they're for

## Step 5: Verify

1. Build Layer 2: `docker build -t {name}-bench:latest -f Dockerfile.layer2 .`
2. Open in VS Code — Layer 3 builds automatically via `ensure-layer3.sh`
3. Inside container, verify:
   - `claude --version` — AI CLI from Layer 0
   - `ls ~/.claude` — credential mount working
   - `python3 --version` — Layer 1 tools
   - Your bench-specific tools are present and working

---

## Rules Summary

1. **Never create users in Layer 2** — Layer 3 handles user creation
2. **Never hardcode usernames** — use `${localEnv:USER}` in devcontainer.json, `/etc/skel/` in Dockerfiles
3. **Always include ALL standard mounts** — missing mounts break AI tools and credentials
4. **Never use docker-compose for single-service benches** — use `image` + `mounts` pattern
5. **Always include `initializeCommand`** — this triggers Layer 3 build
6. **Always match host user** — `remoteUser` must be `${localEnv:USER}`
7. **Always disable VS Code UID rewriting** — set `"updateRemoteUserUID": false` when using Layer 3
7. **Put shell config in /etc/skel/** — Layer 3's `useradd -m` copies it to user home

## Common Mistakes

- ❌ Omitting AI credential mounts → AI tools can't authenticate inside container
- ❌ Omitting shell config mounts → user gets generic /etc/skel defaults instead of their customized shell
- ❌ Forgetting `initializeCommand` → Layer 3 image never built, container won't start
- ❌ Using `USER someuser` in Layer 2 Dockerfile → breaks Layer 3 user creation
- ❌ Installing tools to `/home/username/` in Layer 2 → that user doesn't exist yet

## Reference Implementations

- **cppBench** — complete mount set, good devcontainer.json reference
- **javaBench** — bench-specific tool caches (Maven/Gradle named volumes), SDKMAN usage
- **dotNetBench** — .NET global tools, Docker socket mount
- **frappeBench** — exception: uses docker-compose (multi-service with MariaDB, Redis, Nginx)
