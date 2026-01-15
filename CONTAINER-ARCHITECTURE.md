# WorkBenches Container Architecture

## Overview

WorkBenches uses a **3-layer Docker image architecture** to minimize build times, maximize reusability, and maintain clear separation of concerns. Each layer builds upon the previous one, creating a dependency chain from system tools → category-specific tools → specialized bench tools.

```
┌─────────────────────────────────────────────────────────────┐
│ Layer 2: Specific Bench Tools                              │
│ (frappeBench, cloudBench, etc.)                             │
│ - Technology-specific tools                                 │
│ - Diagnostic utilities                                      │
│ - Workspace-specific configurations                         │
│ Base Image: Layer 1a or 1b                                  │
└─────────────────────────────────────────────────────────────┘
                          │
┌─────────────────────────────────────────────────────────────┐
│ Layer 1: Category Base Images                              │
│ ┌──────────────────────┐ ┌──────────────────────────────┐  │
│ │ Layer 1a: devBench   │ │ Layer 1b: adminBench         │  │
│ │ - Python & Node.js   │ │ - Admin & DevOps tools       │  │
│ │ - AI coding CLIs     │ │ - Read-only inspection       │  │
│ │ - Dev tools          │ │ - "Discovery & Connection"   │  │
│ └──────────────────────┘ └──────────────────────────────┘  │
│ Base Image: Layer 0                                         │
└─────────────────────────────────────────────────────────────┘
                          │
┌─────────────────────────────────────────────────────────────┐
│ Layer 0: System Base (workbench-base)                      │
│ - Ubuntu 24.04                                              │
│ - System utilities (git, vim, curl)                        │
│ - Modern CLI tools (zoxide, fzf, bat)                      │
│ - User setup (matched UID/GID)                             │
│ - Zsh with Oh-My-Zsh                                        │
│ Base Image: ubuntu:24.04                                    │
└─────────────────────────────────────────────────────────────┘
```

---

## Layer 0: System Base (`workbench-base`)

**Purpose**: Universal system foundation for all workbenches  
**Location**: `workBenches/base-image/`  
**Image**: `workbench-base:{USERNAME}`  
**Base**: `ubuntu:24.04`  
**Size**: ~1.8GB

### What Belongs Here

✅ **System utilities** that every developer needs:
- Version control: `git`, `gh` (GitHub CLI)
- Editors: `vim`, `neovim`, `nano`
- Network tools: `curl`, `wget`, `ping`, `netstat`
- Shell utilities: `zsh`, `tmux`, `screen`, `fzf`
- Data tools: `jq`, `yq`
- Modern CLI enhancements: `zoxide`, `bat`, `tldr`

✅ **User configuration**:
- Match host UID/GID for seamless file permissions
- Oh-My-Zsh with plugins (autosuggestions, syntax highlighting)
- Default shell: zsh

### What Does NOT Belong Here

❌ Programming languages (Python, Node.js, Go, etc.)  
❌ Language-specific tools (pip, npm, cargo)  
❌ AI coding assistants  
❌ Admin/DevOps tools  
❌ Technology-specific utilities

### Building Layer 0

```bash
cd workBenches/base-image
./build.sh brett  # Replace with your username
```

**Build Once**: This image rarely changes. Rebuild only when:
- Adding new system utilities
- Upgrading base OS version
- Changing user configuration approach

---

## Layer 1: Category Base Images

Layer 1 splits into two branches based on use case:

### Layer 1a: Development Base (`devbench-base`)

**Purpose**: Tools for software development  
**Location**: `workBenches/devBenches/base-image/`  
**Image**: `devbench-base:{USERNAME}`  
**Base**: `workbench-base:{USERNAME}`  
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

✅ **AI coding assistants** (shared across all dev benches):
- Claude Code CLI (`@anthropic-ai/claude-code`)
- OpenAI Codex (`@openai/codex`)
- GitHub Copilot CLI (`@githubnext/github-copilot-cli`)
- Google Gemini CLI (`@google/gemini-cli`)
- OpenCode AI (`opencode-ai`)
- Letta Code (`@letta-ai/letta-code`)
- OpenSpec (`@fission-ai/openspec`)
Note: WorkBenches exclusively uses the layered architecture for AI CLI installation. Alternative approaches have been deprecated.

✅ **Shell enhancements**:
- PATH configuration for `~/.npm-global/bin`, `~/.local/bin`, `~/.cargo/bin`
- Force zsh when bash is requested

#### What Does NOT Belong Here

❌ Framework-specific tools (Django, Frappe, Flutter SDK)  
❌ Database clients (MariaDB, PostgreSQL, Redis)  
❌ Admin/infrastructure tools (kubectl, terraform)  
❌ Specialized diagnostic tools

#### Building Layer 1a

```bash
cd workBenches/devBenches/base-image
./build.sh brett  # Replace with your username
```

**Rebuild When**:
- Adding new AI coding assistant
- Updating Python or Node.js versions
- Adding universal dev tools

---

### Layer 1b: Admin Base (`adminbench-base`)

**Purpose**: Administrative and DevOps visibility tools  
**Philosophy**: **"Discovery & Connection"** - Read-only troubleshooting at 2 AM  
**Location**: `workBenches/adminBenches/base-image/`  
**Image**: `adminbench-base:{USERNAME}`  
**Base**: `workbench-base:{USERNAME}`  
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
cd workBenches/adminBenches/base-image
./build.sh brett  # Replace with your username
```

**Rebuild When**:
- Adding new cloud provider CLI
- Updating Kubernetes tools
- Adding infrastructure inspection utilities

---

## Layer 2: Specialized Bench Tools

**Purpose**: Technology-specific and diagnostic tools  
**Builds On**: Layer 1a (dev) or Layer 1b (admin)  
**Size**: Adds ~200-500MB to base image

### Development Benches (Layer 1a + Layer 2)

#### frappeBench Example

**Location**: `workBenches/devBenches/frappeBench/`  
**Image**: `frappe-bench:{USERNAME}`  
**Base**: `devbench-base:{USERNAME}`  
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

**Location**: `workBenches/adminBenches/cloudBench/`  
**Image**: `cloud-bench:{USERNAME}`  
**Base**: `adminbench-base:{USERNAME}`  
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

Is it for software development?
    ↓ YES
    Is it language/runtime/AI CLI?
    (Python, Node.js, Claude, Copilot)
        ↓ YES
        Layer 1a: devbench-base
    
    Is it specific to one tech stack?
    (Frappe, Flutter, .NET tools)
        ↓ YES
        Layer 2: Specific bench (frappeBench, flutterBench, etc.)

Is it for infrastructure/DevOps?
    ↓ YES
    Is it read-only inspection?
    (kubectl get, terraform show, aws s3 ls)
        ↓ YES
        Layer 1b: adminbench-base
    
    Does it modify infrastructure?
    (terraform apply, kubectl apply, helm install)
        ↓ YES
        Layer 2: Specific bench (cloudBench, etc.)
```

---

## Building Images

### Order Matters!

Images must be built in dependency order:

```bash
# 1. Build Layer 0 (once)
cd workBenches/base-image
./build.sh brett

# 2. Build Layer 1a OR 1b (based on need)
# For development:
cd workBenches/devBenches/base-image
./build.sh brett

# For admin:
cd workBenches/adminBenches/base-image
./build.sh brett

# 3. Build Layer 2 (your specific bench)
cd workBenches/devBenches/frappeBench
./build-layer2.sh
```

### Image Tags

All images are tagged with your username to allow parallel development:

```bash
workbench-base:brett        # Layer 0
devbench-base:brett         # Layer 1a
adminbench-base:brett       # Layer 1b
frappe-bench:brett          # Layer 2
cloud-bench:brett           # Layer 2
```

**Why username tags?**
- Multiple developers can work on different image versions
- Test changes without affecting teammates
- Easy to identify who built what

---

## Maintenance

### When to Rebuild

**Layer 0** (rare):
- Ubuntu security updates
- Adding system utilities
- Changing user setup approach

**Layer 1a/1b** (occasional):
- New AI coding assistant
- Language version updates
- New admin tools

**Layer 2** (frequent):
- Framework updates
- New diagnostic tools
- Bench-specific improvements

### Efficient Rebuilds

Docker caches layers, so rebuilding is fast:

```bash
# Only Layer 2 rebuilds if base hasn't changed
cd frappeBench
./build-layer2.sh  # ~2-3 minutes

# Full stack rebuild
cd ../../base-image && ./build.sh brett      # ~8 minutes
cd ../devBenches/base-image && ./build.sh brett  # ~5 minutes
cd ../frappeBench && ./build-layer2.sh       # ~2 minutes
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
cd workBenches/adminBenches/devcontainer.test
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

### Example: Adding a New AI CLI (Layer 1a)

```bash
# 1. Edit installation script
vim workBenches/devBenches/base-image/install-ai-clis.sh

# Add:
echo "Installing NewAI CLI..."
npm install -g @newai/cli

# 2. Rebuild Layer 1a
cd workBenches/devBenches/base-image
./build.sh brett

# 3. Test
docker run --rm devbench-base:brett newai --version

# 4. All Layer 2 images inherit it automatically
cd ../../frappeBench
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
docker run --rm frappe-bench:brett psql --version
```

---

## Best Practices

### ✅ DO

- Put universal tools in lower layers (Layer 0/1)
- Put specialized tools in Layer 2
- Use username tags for parallel development
- Test each layer independently
- Document new tools in layer-specific README

### ❌ DON'T

- Install framework-specific tools in Layer 0
- Mix dev and admin tools in same layer
- Skip testing after rebuilds
- Modify lower layers frequently (causes cascading rebuilds)
- Use `latest` tags in production

---

## Related Documentation

- [frappeBench Architecture](devBenches/frappeBench/docs/ARCHITECTURE.md) - Layer 2 Frappe-specific docs
- [Admin Tools Philosophy](adminBenches/README.md) - Discovery vs. Action

---

## Quick Reference

| Layer | Purpose | Build Frequency | Typical Size |
|-------|---------|----------------|--------------|
| Layer 0 | System base | Rare (months) | ~1.8GB |
| Layer 1a | Dev tools | Occasional (weeks) | +4GB = ~5.8GB |
| Layer 1b | Admin tools | Occasional (weeks) | +2.7GB = ~4.5GB |
| Layer 2 | Specialized | Frequent (days) | +0.3GB = ~6.1GB |

**Total workspace startup**: < 10 seconds (using pre-built images)  
**Build from scratch**: ~15-20 minutes (all layers)  
**Incremental Layer 2 rebuild**: ~2-3 minutes
