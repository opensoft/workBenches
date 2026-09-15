# workBenches

## Project command

Generic project creation now lives in
[openRepoProject](https://github.com/opensoft/openRepoProject). workBenches
installs its `project` executable during setup and command installation:

```sh
python3 scripts/setup-project-command.py
project benches
project new MyApp --bench flutterBench --type flutter --dry-run
project status MyApp
project doctor MyApp
project update MyApp
```

`onp NAME [PARENT]` and `scripts/new-project.sh NAME [PARENT]` forward to
`project new` and accept its flags. The forwarders resolve the directory chosen
by command installation (including `/usr/local/bin`) and execute only a
`project` whose ownership marker and digest verify. Bench-specific generators
remain owned by their bench repositories. The creation list excludes update
scripts and reports configured scripts that are not installed.

`config/openrepoproject-pin.json` identifies an exact source commit and executable
SHA-256. The PATH-facing `project` command is a verifier launcher; the pinned
upstream executable is stored separately as `.workbenches-project.payload`, so
normal direct invocations perform the same ownership and digest check as legacy
forwarders. The launcher embeds the pinned source identity, not checkout or pin
file paths; it uses `WORKBENCHES_ROOT` or the local discovery marker only after
the executable payload verifies. The installer tries the authenticated GitHub API before raw download,
verifies bytes before replacing anything, journals publication so an
interrupted upgrade can resume, and rolls back ordinary partial multi-file
replacement failures. A persistent per-directory lock serializes installation,
removal, status, and legacy snapshot capture; launchers release it before
running the verified private snapshot so delegated setup operations can acquire
the writer lock. A failed download/digest
check preserves the existing executable. A symlink, directory,
read-only target, or unrelated existing `project` command refuses. After
reviewing a name collision, use `--replace-existing` to take ownership;
uninstall removes only an artifact whose ownership record and digest agree.
The user-writable PATH entry is not itself an integrity root: status and legacy
forwarders authenticate it against the installer template, while protection
against hostile same-user replacement before direct execution depends on host
filesystem permissions.
Python 3.10+ is required; YAML inspection needs PyYAML, available in the
development bench.

Use `--source /path/to/openRepoProject/project` for offline installation of the
same pinned bytes, `--bin-dir PATH` for another command directory, or
`WORKBENCHES_SKIP_PROJECT_COMMAND=1` to skip. The installer records this checkout
in the host-local `.workbenches-path` beside the command and records the selected
command directory in `~/.config/workbenches/project-bin`. Checkout legacy
entrypoints use that verified pointer when the custom directory is no longer on
`PATH`; `WORKBENCHES_ROOT` overrides checkout discovery at runtime.

When advancing the pin, first copy the current `commit` and `sha256` pair into
the `trusted_previous` array. Then publish the tested source commit, obtain
`project` from that commit, compute its SHA-256, and update the top-level
`commit` and `sha256` fields in the same change. Retain each previous pair only
for the upgrade window in which an existing installer-owned payload must be
recognized. If the source PR will squash-merge, re-pin to the resulting main
commit before landing the workBenches integration. Never adjust a digest to
accept drift.

Offline integration tests: `python3 devcontainer.test/test-project-command.py`
inside a Python workBench. Command behavior and migration notes live in
openRepoProject's README and `docs/migration-review.md`.

A layered Docker-based development environment system. Each "bench" is a self-contained devcontainer for a specific tech stack (Flutter, Java, .NET, Python, Frappe, C++, etc.) built on shared base images.

## Quick Start

```bash
./setup.sh
```

This single command:
1. Configures your shell (zsh + Oh My Zsh + Powerlevel10k)
2. Installs the estate commands from workBenches' own pin (`openRepoShape`, `openRepoTools`, `park`, `resume`, `status`, and the lane tools `lanes-edit.sh`, `lane-start`, `lane-end`, `link-estates` with the shipped `repos.tsv`)
3. Creates your workspace repository, if you have none, with `openRepoTools wip init` — it asks you nothing
4. Checks workstation VPN clients and patches 0dcloud TUN MTU for large Git/Docker transfers
5. Installs or updates Wave Terminal widgets for workBenches
6. Ensures Docker is running and Layer 0 base image exists
7. Opens an interactive TUI to select benches, AI tools, and workstation tools
8. Builds Docker images for selected benches
9. Installs AI coding CLIs and workstation tools (Claude, Copilot, Codex, Pi, etc.)

After setup, open any bench in VS Code → "Reopen in Container" to start developing.

### Re-running setup.sh

Safe to run repeatedly. Installed benches show `✓ up to date` and are skipped. Only new selections or missing images trigger builds. The estate commands (`openRepoShape`, `openRepoTools`, `park`, `resume`, `status` and the five lane tools) are checked against workBenches' pin on every run and are re-placed only when a host copy differs from it. The workspace repository step does nothing at all once you have one: it is a file test on `~/.agents/workspace.yaml`, so a second `./setup.sh` neither asks you anything nor touches the network for it.

## Docker Image Layers

```
Layer 0: workbench-base:latest          — Ubuntu 24.04 + git, zsh, curl, shared AI CLIs, bun
  ├─ Layer 1a: dev-bench-base:latest    — Python, Node.js LTS, npm, dev tools, OpenSpec, spec-kit, testing tools, Playwright Chromium
  │    ├─ Layer 2: cpp-bench:latest     — GCC, CMake, vcpkg
  │    ├─ Layer 2: dotnet-bench:latest  — .NET SDK 8/9
  │    ├─ Layer 2: flutter-bench:latest — Flutter SDK, Dart, Android tools
  │    ├─ Layer 2: frappe-bench:latest  — MariaDB client, Redis, Nginx, bench CLI (Node.js 20)
  │    ├─ Layer 2: java-bench:latest    — OpenJDK 25, Maven, Gradle, Spring CLI
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
  ├── Estate commands (scripts/setup-estate-commands.sh — openRepoTools --install)
  ├── Workspace repository (scripts/setup-workspace-repo.sh — openRepoTools wip init)
  │     └── strictly after the estate commands: `wip init` is their subcommand
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

Your host's `openRepoShape`, `openRepoTools`, `park`, `resume`, `status`, `restart`, `lanes`, `lanes-edit.sh`, `lane-start`, `lane-end`, `link-estates` and `repos.tsv` come from workBenches' own pin (`devBenches/base-image/upstream-pin.yaml`). `setup.sh` places them from the vendored copies in `devBenches/base-image/files/openreposhape/` and `devBenches/base-image/files/openrepotools/`, and re-places them whenever a host copy differs from the pin, in either direction — behind, ahead, or hand-edited. To move them to a new upstream commit, move the pin with `update-upstream.py apply` and re-run `setup.sh`; do not edit the vendored files or the installed commands directly. The step refuses to run over a symlinked, non-regular, or read-only target, and verifies the twelve placed files against the vendored copies before it reports success. Set `WORKBENCHES_SKIP_ESTATE_COMMANDS=1` to skip this step.

## Your Workspace Repository

After the estate commands are installed, `setup.sh` runs `openRepoTools wip init` — the fourth link in the onboarding chain of lane-collision-protocol Amendment 9(e):

```text
gh repo clone opensoft/workBenches && cd workBenches && ./setup.sh   # the host, and the estate commands
openRepoTools --install                            # (setup.sh already did this for you)
openRepoTools wip init                             # your workspace repository
pclaude <profile>
lane-start <repo> <n>
```

`pclaude <profile>` alone starts the lane: the launcher binds by the tmux window — its name, else the swap record for that window — so the normal path needs no lane named at all, and `--lane <repo>-<n>` / `--dir <path>` remain leading options for the cases that still do.

The workspace repository (`<org>/<login>-wip`) holds your lane register, your handoffs and your workspace manifests. It holds **no code**: the lane tooling is installed from `opensoft/openRepoTools`.

**`openRepoTools --install` is the single writer of everything it places** (lane-collision-protocol Amendment 9(b), adoption act 4b). It places eleven files into `${OPENREPOTOOLS_BIN_DIR:-~/.local/bin}` at 755 — `openRepoTools`, `park`, `resume`, `status`, `restart`, `lanes`, `lanes-edit.sh`, `lane-start`, `lane-end`, `link-estates` and the shipped alias table `repos.tsv` — plus five artifacts that are not in that directory: the `/lane-swap` and `/restart` skills at `${CLAUDE_PROFILES_HOME:-~/.claude-profiles}/shared/skills/<name>/SKILL.md`, a copy of each at `~/.claude/skills/<name>/SKILL.md` for a bare `claude` outside the launcher, and one merged `SessionStart` entry in `~/.claude/settings.json`. **None of those counts is written by hand:** they are what the pinned shim's own `INSTALLABLES` and `SKILLS` arrays say, and `scripts/setup-estate-commands.sh` derives its pre-flight and verify lists from the same read, so a shim that grows cannot leave this paragraph or that script behind. Nothing else in this repository writes any of those sixteen: `scripts/setup-claude-profiles.sh` used to install the skill and ensure that hook entry, and adoption act 4b deleted both. The one `SessionStart` ensure that is NOT `--install`'s is the launcher's own, in each *profile's* `settings.json` — a different file for a different run. That merge refuses — placing nothing at all, exit 2, bin directory untouched — on one condition only: a `SessionStart` entry that itself runs `session-start` under a different command string, which is a second program running the same hook verb and would fire it twice (R-A9-8, narrowed from `lanes-edit.sh` to the verb by R-A9-14). An unrelated `SessionStart` entry is merged beside it and the install exits 0.

**This step asks you nothing.** The login comes from `gh api user -q .login`, lowercased; the organisation is your home organisation (`opensoft` in this estate). There is no prompt in it in any path — where nothing can be derived it prints the one command that fixes that (`gh auth login`) and continues rather than asking you for what it could not read.

**It does nothing on a host that already has one.** `~/.agents/workspace.yaml` naming a repository and a checkout of it is the whole of the idempotence, and it is a file test, not a network call. Re-run `./setup.sh` as often as you like.

**It never fails setup.** `setup.sh` treats it as best-effort, exactly as it treats the estate command step above it. Run directly, `scripts/setup-workspace-repo.sh` exits `0` (done, or already done, or degraded and printed), `1` (`openRepoTools wip init` itself ran and refused — its own output above says why), or `2` (nothing was attempted: either no openRepoTools is installed, or a precondition `wip init` would refuse on — no `gh`, an unauthenticated `gh`, or a login that cannot form `<login>-wip` — is already known here and named instead of relayed from a doomed call).

**Two things it cannot do for you, and says so rather than attempting.** Where your account cannot create a repository in the organisation, `wip init` prints the exact `gh repo create` and the team-permission `gh api --method PUT` for an administrator; and a newly created workspace repository must be excluded from the organisation's PR-only ruleset before the lane register can be written at all. Both are administrator acts. This step never captures or summarises that output — it relays every byte of it to your terminal. Because that block can still scroll off screen under the headers that follow it, a non-zero exit here also leaves `$AGENT_PROTOCOL_ROOT/.workspace-step-needs-attention` behind; `setup.sh`'s own SETUP COMPLETE summary checks for it and points back at this step's slice of the log, and a later clean run removes it.

**`wip init` is live from the pin this repository carries.** It arrived with Amendment 9's adoption act 3 in `opensoft/openRepoTools`, and adoption act 4b moved the pin to it. Against an `openRepoTools` that does not carry the subcommand the step still degrades rather than failing: it prints what you would run and continues, and capability is read from `openRepoTools --help`, never from an exit code.

| Variable | Effect |
|----------|--------|
| `WORKBENCHES_SKIP_WORKSPACE_REPO=1` | Skip this step entirely |
| `WORKBENCHES_WORKSPACE_ORG=<org>` | The organisation (default: `opensoft`); passed through to `wip init` |
| `AGENT_PROTOCOL_ROOT=<dir>` | Where `workspace.yaml` lives (default: `~/.agents`) |

Tests: `devcontainer.test/test-setup-workspace-repo.sh` (110 checks; fakes `openRepoTools` and `gh`, and also runs the real vendored `openRepoTools` to prove the degradation is live). Wired into CI in `.github/workflows/speckit-git-bash.yml`, alongside the sibling estate-commands suite.

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
| `rustBench` | Starts or repairs `rust-bench`, then opens an interactive shell |
| `cloudBench` | Starts or repairs `cloud-bench`, then opens an interactive shell |

Opening a widget never recreates an already-running bench when mount
requirements drift. The launcher warns and preserves the live container. Use
`scripts/wave-container-shell.sh --repair <bench>` only when it is safe to
recreate that container; stopped containers with missing mounts are repaired
automatically.

First-run setup offers consent-based work and personal AI profile onboarding,
including GitHub credential-registry discovery and a local manual fallback.
See [Shared AI provider profiles](docs/multi-provider-profiles.md).
Multi-account Claude details remain in
[Claude multi-account profiles](docs/claude-multi-account-profiles.md).
OpenCode users who switch between OpenAI ChatGPT accounts while retaining the
same project sessions should read
[OpenCode multi-account OpenAI profiles](docs/opencode-openai-multi-account-profiles.md).
The cross-provider ownership and composition model is documented in
[AI credential ownership and profile composition](docs/ai-credential-ownership.md).

The WSL connection defaults to `wsl://Ubuntu-24.04` and the projects widget
defaults to `$HOME/projects`. Override them with `WAVE_WSL_CONNECTION` and
`WAVE_PROJECTS_ROOT`. Widget font size defaults to `16`; override it with
`WAVE_WIDGET_FONT_SIZE`. Set `WORKBENCHES_SKIP_WAVE_WIDGETS=1` to skip this
step.

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
| OpenAI Codex CLI | npm | `OPENAI_API_KEY`, `codex login`, or isolated `pcodex PROFILE` logins |
| Google Gemini CLI | npm | Google login or isolated `pgemini PROFILE` login |
| Grok Build | Native installer | Isolated `pgrok PROFILE` login |
| OpenCode CLI with Z.AI GLM | Manual | Isolated `pglm PROFILE` Z.AI Coding Plan key |
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
| Pi Terminal | Windows and WSL/Linux npm | `npm install -g --ignore-scripts @earendil-works/pi-coding-agent`; use isolated `ppi PROFILE` or standard `pi` |
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
