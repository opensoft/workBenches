# workBenches

A layered Docker-based development environment system. Each "bench" is a self-contained devcontainer for a specific tech stack (Flutter, Java, .NET, Python, Frappe, C++, etc.) built on shared base images.

## Quick Start

```bash
./setup.sh
```

This single command:
1. Configures your shell (zsh + Oh My Zsh + Powerlevel10k)
2. Checks workstation VPN clients and patches 0dcloud TUN MTU for large Git/Docker transfers
3. Installs or updates Wave Terminal widgets for workBenches
4. Ensures Docker is running and Layer 0 base image exists
5. Opens an interactive TUI to select benches, AI tools, and workstation tools
6. Builds Docker images for selected benches
7. Installs AI coding CLIs and workstation tools (Claude, Copilot, Codex, Pi, etc.)

After setup, open any bench in VS Code → "Reopen in Container" to start developing.

### Re-running setup.sh

Safe to run repeatedly. Installed benches show `✓ up to date` and are skipped. Only new selections or missing images trigger builds.

## Docker Image Layers

```
Layer 0: workbench-base:latest          — Ubuntu 24.04 + git, zsh, curl, shared AI CLIs, bun
  ├─ Layer 1a: dev-bench-base:latest    — Python, Node.js LTS, npm, dev tools, OpenSpec, spec-kit, testing tools, Playwright Chromium
  │    ├─ Layer 2: cpp-bench:latest     — GCC, CMake, vcpkg
  │    ├─ Layer 2: dotnet-bench:latest  — .NET SDK 8/9
  │    ├─ Layer 2: flutter-bench:latest — Flutter SDK, Dart, Android tools
  │    ├─ Layer 2: frappe-bench:latest  — MariaDB client, Redis, Nginx, bench CLI (Node.js 20)
  │    ├─ Layer 2: java-bench:latest    — OpenJDK 21, Maven, Gradle, Spring CLI
  │    ├─ Layer 2: php-bench:latest     — PHP 8.3, Composer, PHPUnit, Xdebug
  │    ├─ Layer 2: py-bench:latest      — Python dev tools (thin layer on 1a)
  │    └─ Layer 2: go-bench:latest      — Go toolchain
  ├─ Layer 1b: sys-bench-base:latest    — Kubernetes, Terraform, cloud CLIs
  │    └─ Layer 2: cloud-bench:latest   — Cloud admin tools
  └─ Layer 1c: bio-bench-base:latest    — Miniconda, Node.js, bioinformatics base
       ├─ Layer 2: gentec-bench:latest  — BaseSpace CLI, bcftools, samtools, nextflow
       └─ Layer 2: sim-bench:latest     — ESMFold, AlphaFold, molecular dynamics
```

**Layer 3 (`:<username>`)**: A thin user-personalization layer built on any Layer 2 image. Creates your user (matching host UID/GID) and copies shell configs from `/etc/skel`. Tagged as `<bench>:<username>` (e.g., `java-bench:brett`).

### Image Naming

| Tag | Purpose | Example |
|-----|---------|--------|
| `:latest` | Layer 2, user-agnostic bench tools | `java-bench:latest` |
| `:<username>` | Layer 3, user-personalized | `java-bench:brett` |
| `<project>-<service>:latest` | Docker-compose built (bioBenches) | `sim-bench-gene_bench:latest` |

Family base images use the canonical kebab-case repos `dev-bench-base`, `sys-bench-base`, and `bio-bench-base`. Legacy local aliases `devbench-base`, `sysbench-base`, and `biobench-base` are still tagged during the migration window.

### Building Layer 3

Built automatically by `ensure-layer3.sh` (called from devcontainer `initializeCommand`) or manually:

```bash
bash scripts/ensure-layer3.sh --base java-bench:latest
```

## setup.sh Flow

```
setup.sh
  ├── Shell setup (zsh + Oh My Zsh + Powerlevel10k)
  ├── VPN setup (AmneziaVPN + 0dcloud checks, 0dcloud MTU patch)
  ├── Wave Terminal widgets (terminal, projects, and workBench containers)
  ├── Docker check (is daemon running?)
  ├── Layer 0 check (build workbench-base:latest if missing)
  ├── Interactive TUI (scripts/interactive-setup.sh)
  │     ├── 3-column selection: Benches | AI Assistants | Tools
  │     ├── Status: ✓ installed  ⚠ needs setup  ✗ not installed
  │     ├── Installed benches: check Docker images (Layer 2 + Layer 3)
  │     ├── New benches: clone repo → run setup.sh or build-layer.sh
  │     └── AI tools: install/update via npm
  ├── Layer 1 builds (dev-bench-base, sys-bench-base, bio-bench-base)
  └── Summary + log file path
```

## Wave Terminal Widgets

`setup.sh` runs the Wave Terminal installer as a best-effort host setup step so
all workBenches checkouts get the same desktop shortcuts. The installer comes
from `opensoft/Install-Wave-Terminal`; setup prefers a sibling
`../Install-Wave-Terminal` checkout when present, then falls back to cloning it
into `~/.cache/workbenches/Install-Wave-Terminal`.

Installed widgets include:

| Widget | Behavior |
|--------|----------|
| `terminal` | Overrides Wave's built-in terminal to open `wsl://Ubuntu-24.04` instead of PowerShell |
| `projects` | Opens the Wave files view at `$HOME/projects` on the WSL connection |
| `pyBench` | Starts or repairs `py-bench`, then opens an interactive shell |
| `flutterBench` | Starts or repairs `flutter-bench`, then opens an interactive shell |
| `C++Bench` | Starts or repairs `cpp-bench`, then opens an interactive shell |
| `cloudBench` | Starts or repairs `cloud-bench`, then opens an interactive shell |

Multi-account Claude Code setups are supported through a portable profile
manifest. See [Claude multi-account profiles](docs/claude-multi-account-profiles.md).

The WSL connection defaults to `wsl://Ubuntu-24.04` and the projects widget
defaults to `$HOME/projects`. Override them with `WAVE_WSL_CONNECTION` and
`WAVE_PROJECTS_ROOT`. Set `WORKBENCHES_SKIP_WAVE_WIDGETS=1` to skip this step.

### Bench Processing Logic

| State | Action |
|-------|--------|
| Installed + images exist | `✓ up to date` — skipped |
| Installed + Layer 3 missing | `⚠ Layer 3 missing` — hint to run ensure-layer3.sh |
| Needs setup (repo exists, no infra) | Runs `setup.sh` or `build-layer.sh` |
| Not installed | Clones repo, then runs setup |
| No setup.sh or build-layer.sh | Marks as ready for VS Code |

## Directory Structure

```
workBenches/
├── setup.sh                    ← Main entry point
├── base-image/                 ← Layer 0: workbench-base Dockerfile
├── user-layer/                 ← Layer 3: User personalization Dockerfile
├── config/
│   └── bench-config.json       ← Bench registry (URLs, paths, descriptions)
├── scripts/
│   ├── interactive-setup.sh    ← Bash TUI for bench/tool selection
│   ├── ensure-layer3.sh        ← Build Layer 3 user image if needed
│   ├── setup-vpn.sh            ← VPN client checks and 0dcloud MTU patch
│   ├── setup-shell.sh          ← Shell environment (zsh, p10k, plugins)
│   └── setup-ui/               ← OpenTUI TypeScript TUI (disabled, needs Bun upgrade)
├── devBenches/
│   ├── base-image/             ← Layer 1a: dev-bench-base Dockerfile
│   ├── cppBench/               ← C++ bench (opensoft/cppBench)
│   ├── dotNetBench/            ← .NET bench (opensoft/dotNetBench)
│   ├── flutterBench/           ← Flutter bench (opensoft/flutterBench)
│   ├── frappeBench/            ← Frappe/ERPNext bench (opensoft/frappeBench)
│   ├── goBench/                ← Go bench (opensoft/goBench)
│   ├── javaBench/              ← Java bench (opensoft/javaBench)
│   ├── phpBench/               ← PHP bench (opensoft/phpBench)
│   └── pyBench/                ← Python bench (opensoft/pyBench)
├── sysBenches/
│   ├── base-image/             ← Layer 1b: sys-bench-base Dockerfile
│   ├── cloudBench/             ← Cloud admin bench (opensoft/cloudBench)
│   └── opsBench/               ← Ops bench (deployment, CI/CD, security)
├── bioBenches/
│   ├── base-image/             ← Layer 1c: bio-bench-base Dockerfile
│   ├── gentecBench/            ← Genetics/genomics bench (opensoft/gentecBench)
│   └── simBench/               ← Molecular simulation bench (opensoft/simBench)
├── logs/                       ← Setup logs (gitignored)
└── docs/
    ├── amnezia-vpn-architecture.md
    ├── setup-input-troubleshooting.md
    └── vpn-setup.md
```

## VPN Setup

`setup.sh` offers VPN setup from the TUI Tools column. Users can select
**AmneziaVPN** and **0dcloud VPN** independently; selecting 0dcloud also patches
the 0dcloud TUN MTU/GSO settings to `1400` to avoid large Git pack transfer
stalls on routed hotel/VPN networks.

See `docs/vpn-setup.md` for manual install steps, 0dcloud routing guidance, and
troubleshooting commands.

## OpenSoft Azure

See `docs/opensoft-aks-prod-test-plan.md` for the AKS production-candidate test
plan, including the current PlanA1 node-pool shape, costs, validation findings,
and build/test/destroy loop. See `docs/nopcommerce-aks-install-research.md` for
the nopCommerce-on-AKS install research, including SQL connectivity, Redis, Blob
storage, and disk strategy. See `docs/opensoft-nopcommerce-dr-runbook.md` for
the cross-tenant disaster-recovery test plan, and
`docs/opensoft-nopcommerce-backup-system-design.md` for the backup system that
feeds that restore.

## Bench Configuration

Benches are registered in `config/bench-config.json`:

```json
{
  "benches": {
    "flutterBench": {
      "url": "git@github.com:opensoft/flutterBench.git",
      "path": "devBenches/flutterBench",
      "description": "Flutter/Dart development environment and tools"
    }
  }
}
```

Each bench repo typically contains:
- `Dockerfile.layer2` — Bench-specific Docker image
- `setup.sh` — Setup script (builds image, starts container)
- `scripts/build-layer.sh` or `build-layer.sh` — Full bench build (Layer 2 + Layer 3)
- `scripts/build-layer2.sh` or `build-layer2.sh` — Layer 2 only
- `.devcontainer/` or `devcontainer.example/` — VS Code devcontainer config

## AI Coding Tools

Installed and updated via the setup TUI:

| Tool | Install Method | Auth |
|------|---------------|------|
| Claude Code CLI | Native installer | `claude login` |
| GitHub Copilot CLI | npm | `copilot auth login` |
| OpenAI Codex CLI | npm | `OPENAI_API_KEY` or `codex login` |
| Google Gemini CLI | npm | Google login (free tier: 60 req/min) |
| OpenCode CLI | Manual | Additional setup required |
| spec-kit | uv (pip) | None |
| OpenSpec | npm | None |

npm global packages install to `~/.npm-global` (no sudo required).

## Workstation Tools

The TUI Tools column includes editor, terminal, and local agent tooling:

| Tool | Install Method | Notes |
|------|---------------|-------|
| Visual Studio Code | Windows/WSL winget, Linux/manual fallback | Dev Containers and WSL extension checks |
| Warp Terminal | Windows/WSL winget, Linux/manual fallback | Windows terminal |
| Wave Terminal | Windows/WSL winget, Linux/manual fallback | AI terminal |
| Pi Terminal | Windows npm from WSL, WSL/Linux npm fallback | `npm install -g --ignore-scripts @earendil-works/pi-coding-agent`; run `pi` then `/login` |
| AmneziaVPN | Windows/WSL winget | Amnezia/AmneziaWG client access |
| 0dcloud VPN | local installer/manual + local patch | 0dcloud detection and MTU fix |

On a Windows workstation running setup from WSL, the TUI calls
`scripts/setup-windows-tools.sh` so Windows apps are installed into Windows
rather than into the Linux distro.

## Amnezia Endpoint Wrapper

The shared host-side Amnezia endpoint wrapper lives at
`scripts/amnezia-endpoint`. It fetches the CloudBench-published endpoint
manifest, keeps host-local state under `~/.workbenches/amnezia-endpoint/`,
selects usable VPN endpoints, and can patch exported WireGuard/Amnezia-style
configs.

```bash
scripts/amnezia-endpoint list
scripts/amnezia-endpoint select --strategy round-robin --format env
scripts/amnezia-endpoint patch --config ~/vpn/amnezia.conf
```

See `docs/amnezia-endpoint-wrapper.md` for the full workflow.

For GL.iNet/LuCI router setup, see `docs/glinet-luci-amnezia-router.md`.

Server-side Amnezia rebuild and operations docs are owned by the cloudBench
submodule:

```text
sysBenches/cloudBench/docs/amnezia-server-rebuild.md
sysBenches/cloudBench/docs/amnezia-server-runbook.md
```

## Logging

- Logs written to `logs/setup-YYYYMMDD-HHMMSS.log`
- Section headers: `[SHELL SETUP]`, `[DOCKER CHECK]`, `[LAYER 0 BUILD]`, `[INTERACTIVE SETUP]`, `[LAYER 1 BUILDS]`
- Last 10 logs kept, older auto-cleaned
- `interactive-setup.sh` writes its own detailed log with per-bench status

## Known Issues

- **frappeBench**: Requires Node.js 20 (not 24). Dockerfile.layer2 pins it via nodesource. Uses `COREPACK_HOME=/tmp/corepack` during build to avoid permission errors.
- **OpenTUI**: TypeScript TUI (`scripts/setup-ui/`) disabled due to Bun 1.3.5 compatibility and keyboard bugs. Bash TUI used instead. See `docs/setup-input-troubleshooting.md`.
- **WSL Enter key**: Bash TUI handles `\r`, `\n`, and empty string for Enter detection.

## Repositories

| Bench | Repository |
|-------|----------|
| workBenches (this repo) | [opensoft/workBenches](https://github.com/opensoft/workBenches) |
| cloudBench | [opensoft/cloudBench](https://github.com/opensoft/cloudBench) |
| cppBench | [opensoft/cppBench](https://github.com/opensoft/cppBench) |
| dotNetBench | [opensoft/dotNetBench](https://github.com/opensoft/dotNetBench) |
| flutterBench | [opensoft/flutterBench](https://github.com/opensoft/flutterBench) |
| frappeBench | [opensoft/frappeBench](https://github.com/opensoft/frappeBench) |
| goBench | [opensoft/goBench](https://github.com/opensoft/goBench) |
| javaBench | [opensoft/javaBench](https://github.com/opensoft/javaBench) |
| phpBench | [opensoft/phpBench](https://github.com/opensoft/phpBench) |
| pyBench | [opensoft/pyBench](https://github.com/opensoft/pyBench) |
| gentecBench | [opensoft/gentecBench](https://github.com/opensoft/gentecBench) |
| simBench | [opensoft/simBench](https://github.com/opensoft/simBench) |
