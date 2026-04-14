# WorkBenches Container Architecture

## Overview

WorkBenches uses a **4-layer logical Docker image architecture** to minimize build times, maximize reusability, and maintain clear separation of concerns. Layers 0-2 are shared, user-agnostic images tagged `:latest`. Layer 3 is a thin per-user image built on top of any Layer 2 bench.

```
┌─────────────────────────────────────────────────────────────┐
│ Layer 3: User Personalization                              │
│ (<bench>:<username>)                                       │
│ - Host-matched user account (UID/GID)                      │
│ - Home directory from /etc/skel                            │
│ - User-specific ownership fixes                            │
│ Base Image: Specific Layer 2 image                         │
└─────────────────────────────────────────────────────────────┘
                          │
┌─────────────────────────────────────────────────────────────┐
│ Layer 2: Specific Bench Tools                              │
│ (frappeBench, cloudBench, etc.)                             │
│ - Technology-specific tools                                 │
│ - Diagnostic utilities                                      │
│ - Workspace-specific configurations                         │
│ Base Image: Layer 1a, 1b, or 1c                             │
└─────────────────────────────────────────────────────────────┘
                          │
┌─────────────────────────────────────────────────────────────┐
│ Layer 1: Category Base Images                              │
│ ┌──────────────────────┐ ┌──────────────────────────────┐  │
│ │ Layer 1a: devBench   │ │ Layer 1b: sysBench           │  │
│ │ - Python & Node.js   │ │ - Admin & DevOps tools       │  │
│ │ - Dev tools          │ │ - Read-only inspection       │  │
│ │ - Yarn, Corepack     │ │ - "Discovery & Connection"   │  │
│ └──────────────────────┘ ┌──────────────────────────────┐  │
│                          │ Layer 1c: bioBench           │  │
│                          │ - Bioinformatics base tools  │  │
│                          │ - Miniconda + Node.js        │  │
│                          └──────────────────────────────┘  │
│ Base Image: Layer 0                                         │
└─────────────────────────────────────────────────────────────┘
                          │
┌─────────────────────────────────────────────────────────────┐
│ Layer 0: System Base (workbench-base)                      │
│ - Ubuntu 24.04                                              │
│ - System utilities (git, vim, curl)                        │
│ - Modern CLI tools (zoxide, fzf, bat)                      │
│ - AI coding CLIs (Claude, Codex, Gemini, Copilot, etc.)   │
│ - Shell defaults staged into /etc/skel                     │
│ - Zsh with Oh-My-Zsh                                        │
│ Base Image: ubuntu:24.04                                    │
└─────────────────────────────────────────────────────────────┘
```

---

## Layer 0: System Base (`workbench-base`)

**Purpose**: Universal system foundation for all workbenches
**Location**: `workBenches/base-image/`
**Image**: `workbench-base:latest`
**Base**: `ubuntu:24.04`
**Size**: ~5GB

### What Belongs Here

✅ **System utilities** that every developer needs:
- Version control: `git`, `gh` (GitHub CLI)
- Editors: `vim`, `neovim`, `nano`
- Network tools: `curl`, `wget`, `iputils-ping`, `net-tools`
- Shell utilities: `zsh`, `tmux`, `screen`, `fzf`, `openssh-client`
- Search tools: `ripgrep`, `fd-find`
- Data tools: `jq`, `yq`
- Modern CLI enhancements: `zoxide`, `bat`, `tldr`
- Build tools: `build-essential`, `pkg-config`
- System: `sudo`, `cron`, `unzip`, `gpg`, `ca-certificates`

✅ **Runtimes & package tools** (system-wide):
- `npm` (from apt, used to install AI CLIs)
- `bun` runtime (`/opt/bun`)
- `uv` (fast Python package installer, `/usr/local/bin`)
- `spec-kit` / `specify-cli` (via uv)

✅ **AI coding assistants** (shared across ALL benches):
- Claude Code (native installer → `/usr/local/bin/claude`)
- OpenAI Codex (`@openai/codex` via npm)
- Google Gemini (`@google/gemini-cli` via npm)
- GitHub Copilot CLI (`@githubnext/github-copilot-cli` via npm)
- Grok (`@xai-org/grok-cli` via npm)
- OpenCode (built from source, Opensoft/opencode fork → `/usr/local/bin/opencode`)
- oh-my-opencode (darrenhinde fork, plugin at `/opt/opencode/plugin`)
- opencode-gemini-auth & opencode-openai-codex-auth (auth plugins)
- Letta Code (`@letta-ai/letta-code` via npm)
- OpenSpec (`@fission-ai/openspec` via npm)
- NotebookLM CLI (`notebooklm-py` via uv → `/usr/local/bin/notebooklm`)
- NotebookLM MCP CLI (`notebooklm-mcp-cli` via uv → `/usr/local/bin/nlm`, `/usr/local/bin/notebooklm-mcp`)

✅ **Shell & user configuration** (into `/etc/skel` for Layer 3):
- Oh-My-Zsh with Powerlevel10k theme
- zoxide, bat aliases
- OpenCode agent configs (`/etc/skel/.config/opencode/`)
- Default shell: zsh
- User creation deferred to Layer 3 (user-agnostic)

### What Does NOT Belong Here

❌ Programming languages (Python, Node.js LTS, Go, etc.)  
❌ Language-specific tools (pip, cargo)  
❌ Admin/DevOps tools  
❌ Technology-specific utilities

### Building Layer 0

```bash
cd workBenches/base-image
./build.sh
```

**Build Once**: This image rarely changes. Rebuild only when:
- Adding new system utilities or AI CLIs
- Upgrading base OS version
- Updating AI coding assistants to latest versions
- Changing user configuration approach

---

## Layer 1: Category Base Images

Layer 1 splits into two branches based on use case:

### Layer 1a: Development Base (`dev-bench-base`)

**Purpose**: Tools for software development  
**Location**: `workBenches/devBenches/base-image/`  
**Image**: `dev-bench-base:latest`
**Base**: `workbench-base:latest`
**Size**: ~5.8GB

#### What Belongs Here

✅ **Programming languages & runtimes**:
- Python 3 (with pip, venv, dev headers)
- Node.js LTS (with npm, Yarn via corepack)

✅ **Development tools**:
- Python: black, flake8, isort, pylint, pytest, ipython
- Node: Global package manager setup
- uv (fast Python package installer)
- Git credential helper integration
- Shared Playwright Chromium cache at `/ms-playwright`

✅ **Shell enhancements**:
- Force zsh when bash is requested

Note: AI coding assistants are inherited from Layer 0 (workbench-base) and available in all benches.

#### What Does NOT Belong Here

❌ Framework-specific tools (Django, Frappe, Flutter SDK)  
❌ Database clients (MariaDB, PostgreSQL, Redis)  
❌ Admin/infrastructure tools (kubectl, terraform)  
❌ Specialized diagnostic tools

#### Building Layer 1a

```bash
cd workBenches/devBenches/base-image
./build.sh
```

**Rebuild When**:
- Updating Python or Node.js versions
- Adding universal dev tools

---

### Layer 1b: Sys Base (`sys-bench-base`)

**Purpose**: Administrative and DevOps visibility tools  
**Philosophy**: **"Discovery & Connection"** - Read-only troubleshooting at 2 AM  
**Location**: `workBenches/sysBenches/base-image/`
**Image**: `sys-bench-base:latest`
**Base**: `workbench-base:latest`
**Size**: ~4.5GB

#### What Belongs Here

✅ **Infrastructure inspection tools** (read-only/query-only):
- **Terraform & OpenTofu** - View infrastructure state (`terraform show`, `terraform plan`)
- **Kubernetes CLI** (`kubectl`) - Query cluster state (`kubectl get`, `kubectl describe`)
- **Helm** - List releases, inspect charts
- **K9s** - Interactive Kubernetes TUI (read-only mode)
- **stern** - Kubernetes log streaming
- **Cloud CLIs** - AWS CLI, Azure CLI, Google Cloud SDK (query/list commands)
- **Ansible** - Inventory inspection (no playbook execution)
- **promtool** - Prometheus query tool
- **yq** - YAML/JSON querying
- **lazydocker** - Docker TUI for inspection

#### Philosophy: Discovery vs. Action

**Discovery (Layer 1b)**: "What's the current state?"
- `terraform show` ✅ (read current state)
- `kubectl get pods` ✅ (query status)
- `aws s3 ls` ✅ (list resources)
- `helm list` ✅ (see deployed releases)

**Action (Layer 2)**: "Let's change something!"
- `terraform apply` ⚠️ (modifies infrastructure)
- `kubectl apply` ⚠️ (changes cluster)
- `aws s3 rm` ⚠️ (deletes resources)
- `helm install` ⚠️ (deploys application)

**Security Benefit**: Layer 1b containers can run with read-only credentials. Only Layer 2 specialized benches get write access when explicitly needed.

#### What Does NOT Belong Here

❌ Action-oriented tools (Terragrunt, Pulumi, ArgoCD CLI)  
❌ Security scanning tools (Trivy, Checkov)  
❌ Cost optimization tools (Infracost)  
❌ Deployment tools (Spinnaker, Flux)

#### Building Layer 1b

```bash
cd workBenches/sysBenches/base-image
./build.sh
```

**Rebuild When**:
- Adding new cloud provider CLI
- Updating Kubernetes tools
- Adding infrastructure inspection utilities

---

## Layer 2: Specialized Bench Tools

**Purpose**: Technology-specific and diagnostic tools  
**Builds On**: Layer 1a (dev) or Layer 1b (sys/ops)  
**Size**: Adds ~200-500MB to base image

### Development Benches (Layer 1a + Layer 2)

#### frappeBench Example

**Location**: `workBenches/devBenches/frappeBench/`
**Image**: `frappe-bench:latest`
**Base**: `dev-bench-base:latest`
**Adds**:

```dockerfile
# Database clients
mariadb-client, libmysqlclient-dev

# Web server
nginx, openssl

# Caching
redis-tools (redis-cli)

# Python debugging & profiling
py-spy          # Performance profiler
web-pdb         # Web-based debugger
frappe-bench    # Frappe CLI

# Network diagnostics
dnsutils (dig), netcat-openbsd (nc)

# Log viewing
multitail       # Multi-file log tailing

# Diagnostic aliases
nginx-debug, frappe-doctor, redis-monitor, check-workers
```

**Why Layer 2?** These are specific to Frappe's polyglot stack (Python + Node + MariaDB + Redis + Nginx). Not useful for Flutter, .NET, or other dev benches.

#### Other Dev Bench Examples

**flutterBench**:
- Flutter SDK
- Android SDK
- Dart analyzer
- Flutter DevTools

**dotNetBench**:
- .NET SDK
- Entity Framework tools
- SQL Server client tools

---

### Admin Benches (Layer 1b + Layer 2)

#### cloudBench Example

**Location**: `workBenches/sysBenches/cloudBench/`
**Image**: `cloud-bench:latest`
**Base**: `sys-bench-base:latest`
**Philosophy**: **"Action & Change"** - Tools that modify infrastructure  
**Adds**:

```dockerfile
# Infrastructure as Code (action tools)
Terragrunt      # Terraform wrapper with DRY configs
Pulumi          # Modern IaC with real programming languages

# Cost & Security
Infracost       # Cost estimation for IaC
Trivy           # Security scanner (containers, IaC)

# Secrets Management
Vault CLI       # HashiCorp Vault client (read/write)

# Disaster Recovery
Velero          # Kubernetes backup/restore

# Access Management
Teleport (tsh/tctl)  # Infrastructure access gateway
```

**Why Layer 2?** These tools make changes to infrastructure. Separate from read-only Layer 1b for:
- **Security**: Different permission levels
- **Audit**: Clear separation of query vs. modify
- **Responsibility**: cloudBench requires elevated privileges

---

## Decision Tree: Where Does My Tool Go?

```
Is it a system utility everyone needs?
(git, vim, curl, jq, yq, zsh, tmux)
    ↓ YES
    Layer 0: workbench-base

Is it an AI coding CLI?
(Claude, Codex, Gemini, Copilot, etc.)
    ↓ YES
    Layer 0: workbench-base

Is it for software development?
    ↓ YES
    Is it a language/runtime?
    (Python, Node.js)
        ↓ YES
        Layer 1a: dev-bench-base
    
    Is it specific to one tech stack?
    (Frappe, Flutter, .NET tools)
        ↓ YES
        Layer 2: Specific bench (frappeBench, flutterBench, etc.)

Is it for infrastructure/DevOps?
    ↓ YES
    Is it read-only inspection?
    (kubectl get, terraform show, aws s3 ls)
        ↓ YES
        Layer 1b: sys-bench-base
    
    Does it modify infrastructure?
    (terraform apply, kubectl apply, helm install)
        ↓ YES
        Layer 2: Specific bench (cloudBench, etc.)
```

User-specific accounts, home directories, and UID/GID matching do not belong in Layers 0-2. Those are handled by Layer 3.

---

## Layer 3: User Personalization

**Purpose**: Thin user-specific wrapper for any Layer 2 bench
**Location**: `workBenches/user-layer/`
**Image**: `<bench>:<username>`
**Base**: `<bench>:latest`
**Size**: Adds ~100-300MB

### What Belongs Here

✅ Host-matched user and group creation (`UID`, `GID`, username)
✅ Home directory creation and shell defaults copied from `/etc/skel`
✅ User-specific shell home and ownership fixes
✅ Optional ownership fixes for bench-specific directories

### Build Layer 3

```bash
cd workBenches
bash scripts/ensure-layer3.sh --base frappe-bench:latest --user "$(whoami)"
```

---

## Building Images

### Order Matters!

Images must be built in dependency order:

```bash
# 1. Build Layer 0 (once)
cd workBenches/base-image
./build.sh

# 2. Build Layer 1a OR 1b (based on need)
# For development:
cd workBenches/devBenches/base-image
./build.sh

# For sys benches:
cd workBenches/sysBenches/base-image
./build.sh

# 3. Build your bench
cd workBenches/devBenches/frappeBench
./build-layer.sh      # builds Layer 2 and ensures Layer 3

# Or rebuild only Layer 2 when you do not need a user-layer refresh
./build-layer2.sh
```

### Image Tags

Layers 0-2 are shared images tagged `:latest`. Layer 3 uses `:<username>`:

```bash
workbench-base:latest       # Layer 0
dev-bench-base:latest       # Layer 1a
sys-bench-base:latest       # Layer 1b
frappe-bench:latest         # Layer 2
cloud-bench:latest          # Layer 2
frappe-bench:brett          # Layer 3
cloud-bench:brett           # Layer 3
```

**Why Layer 3 username tags?**
- Multiple developers can share the same Layer 2 image while keeping separate users and home directories
- User-specific ownership stays correct without duplicating the heavier Layers 0-2
- Devcontainers can rebuild only the thin user layer when the host user changes

---

## Maintenance

### When to Rebuild

**Layer 0** (rare → occasional):
- Ubuntu security updates
- Adding system utilities
- AI CLI version updates
- Changing user setup approach

**Layer 1a/1b** (occasional):
- Language version updates (Python, Node.js)
- New sys/ops tools

**Layer 2** (frequent):
- Framework updates
- New diagnostic tools
- Bench-specific improvements

### Efficient Rebuilds

Docker caches layers, so rebuilding is fast:

```bash
# Only Layer 2 rebuilds if base hasn't changed
cd workBenches/devBenches/frappeBench
./build-layer2.sh  # ~2-3 minutes

# Full bench rebuild (Layer 2 + Layer 3)
./build-layer.sh

# Full stack rebuild
cd workBenches/base-image && ./build.sh
cd ../devBenches/base-image && ./build.sh
cd ../frappeBench && ./build-layer.sh
```

---

## Testing

Each layer has a test suite:

```bash
# Test Layer 0
cd workBenches/devcontainer.test
./test-base-image.sh

# Test Layer 1a
cd workBenches/devBenches/devcontainer.test
./test-layer1.sh

# Test Layer 1b
cd workBenches/sysBenches/devcontainer.test
./test-layer1.sh

# Test Layer 2 (example)
cd workBenches/devBenches/frappeBench/devcontainer.test
./test-layer2.sh
```

Tests verify:
- ✅ All expected tools are installed
- ✅ Tools are in PATH and executable
- ✅ Versions meet minimum requirements
- ✅ User permissions are correct

---

## Adding New Tools

### Example: Adding a New AI CLI (Layer 0)

```bash
# 1. Edit installation script
vim workBenches/base-image/install-ai-clis.sh

# Add:
echo "Installing NewAI CLI..."
npm install -g @newai/cli

# 2. Rebuild Layer 0, then dependent layers
cd workBenches/base-image
./build.sh
cd ../devBenches/base-image
./build.sh

# 3. Test
docker run --rm workbench-base:latest newai --version

# 4. Rebuild any Layer 2 images that should inherit it
cd ../frappeBench
./build-layer2.sh  # Now includes NewAI CLI
```

### Example: Adding Database Tool (Layer 2 - frappeBench only)

```bash
# 1. Edit Dockerfile.layer2
vim workBenches/devBenches/frappeBench/Dockerfile.layer2

# Add to RUN apt-get install:
    postgresql-client \

# 2. Rebuild only Layer 2
./build-layer2.sh

# 3. Test
docker run --rm frappe-bench:latest psql --version
```

---

## Best Practices

### ✅ DO

- Put universal tools in lower layers (Layer 0/1)
- Put specialized tools in Layer 2
- Use `:<username>` only for Layer 3 user images
- Test each layer independently
- Document new tools in layer-specific README

### ❌ DON'T

- Install framework-specific tools in Layer 0
- Mix dev and sys/ops tools in same layer
- Skip testing after rebuilds
- Modify lower layers frequently (causes cascading rebuilds)
- Use `latest` tags in production

---

## Related Documentation

- [frappeBench Architecture](devBenches/frappeBench/docs/ARCHITECTURE.md) - Layer 2 Frappe-specific docs
- [Sys Tools Philosophy](sysBenches/README.md) - Discovery vs. Action

---

## Quick Reference

| Layer | Purpose | Build Frequency | Typical Size |
|-------|---------|----------------|--------------|
| Layer 0 | System base + AI CLIs | Occasional (weeks) | ~5GB |
| Layer 1a | Dev tools | Occasional (weeks) | +1GB = ~6GB |
| Layer 1b | Admin tools | Occasional (weeks) | +2.7GB = ~4.5GB |
| Layer 2 | Specialized | Frequent (days) | +0.3GB = ~6.1GB |
| Layer 3 | User personalization | Frequent (seconds/minutes) | +0.1GB = ~6.2GB |

**Total workspace startup**: < 10 seconds (using pre-built images)  
**Build from scratch**: ~15-20 minutes (all layers)  
**Incremental Layer 2 rebuild**: ~2-3 minutes
