# Layer 1a Test Environment

Test harness for `dev-bench-base:$USER` - the Layer 3 user image built on top of the developer tools layer.

## What This Tests

Layer 1a adds developer tools on top of Layer 0:
- Python 3.x with pip and development tools (black, flake8, isort, pylint, pytest, ipython)
- Node.js LTS with npm and yarn
- Python package managers (uv)
- Spec-driven tools (`specify`, `openspec`)
- Speckit worktree bootstrap (`speckit-worktree-enable`)
- Speckit worktree helpers (`ct`, `ctp`, `ctlist`, `cta`, `ctc`, `ctg`, `cts`)
- AI CLI tools (claude, codex, gemini, opencode)
- Code quality and PR workflow tools (`sonar-scanner`, `sonar`, `sonar-env`, `gt`)
- OpenCode configuration with plugins (oh-my-opencode, opencode-openai-codex-auth)
- Zsh and oh-my-zsh with plugins
- PATH configuration for all dev tools

The Layer 3 user image adds the effective-user Corepack cache exercised by the
unprivileged pnpm checks in this harness, including shells that place
`/usr/bin` before `/usr/local/bin`.

## Quick Start

```bash
# 1. Create .env file
cp .env.example .env

# 2. Ensure the Layer 3 test image exists
cd ../../base-image && ./build.sh
bash ../../scripts/ensure-layer3.sh --base dev-bench-base:latest
cd ../devcontainer.test

# 3. Start test container
docker compose up -d

# 4. Run tests
docker compose exec test ./test.sh

# 5. Clean up
docker compose down
```

## PowerShell Regression Suite

Run the full 28-scenario Speckit Git PowerShell suite from a Linux checkout
when PowerShell 7, Git, and Bash are installed:

```bash
pwsh -NoLogo -NoProfile -File ./devBenches/devcontainer.test/test-speckit-git-powershell.ps1
```

On Windows, run the five selected native state scenarios. This subset covers
the structural contract, held-reader replacement, primary-failure cleanup,
temporary-leaf replacement attack, and authenticated-parent swap without
invoking the Unix-only FIFO and Bash reservation helpers:

```powershell
pwsh -NoLogo -NoProfile -File ./devBenches/devcontainer.test/test-speckit-git-powershell.ps1 -WindowsStateOnly
```

To exercise the same `/test` mount used by this devcontainer while resolving
the Git extension from its installed template location, run:

```bash
docker run --rm \
  --entrypoint bash \
  -v "$PWD/devBenches/devcontainer.test:/test:ro" \
  -v "$PWD/devBenches/base-image/files/speckit-worktree/templates:/usr/local/share/speckit-worktree/templates:ro" \
  -w /test \
  mcr.microsoft.com/powershell:latest \
  -lc 'apt-get update >/dev/null && apt-get install -y --no-install-recommends git >/dev/null && pwsh -NoLogo -NoProfile -File /test/test-speckit-git-powershell.ps1'
```

The PowerShell suite is intentionally separate from `test.sh`: the Layer 3
Linux test image does not include `pwsh`.

## Test Script

The `test.sh` script validates:
- ✅ Python development tools
- ✅ Node.js development tools and unprivileged pnpm/Corepack operation
- ✅ Python package managers (uv)
- ✅ Spec-driven tools (`specify`, `openspec`)
- ✅ Worktree-mode Speckit bootstrap installation
- ✅ Global `ct*` helper availability in interactive zsh
- ✅ Clean failure from non-Speckit directories
- ✅ AI CLI tools (claude, codex, gemini, opencode)
- ✅ SonarScanner CLI, SonarQube CLI, Sonar environment helper, and Graphite CLI availability
- ✅ OpenCode configuration and plugins
- ✅ Shell environment (zsh, oh-my-zsh, plugins)
- ✅ PATH configuration
- ✅ Git credential helper

## When to Use

Run these tests:
- After rebuilding Layer 1a: `cd devBenches/base-image && ./build.sh`
- After rebuilding the user test layer: `bash scripts/ensure-layer3.sh --base dev-bench-base:latest`
- Before making changes to developer tools
- To validate AI CLI installations
- When troubleshooting development tool issues
- After updating OpenCode plugin configuration

## Layer Architecture

```
Layer 0: workbench-base (system tools)
    └─→ Layer 1a: dev-bench-base (THIS LAYER)
            ├─→ Layer 2: frappe-bench
            ├─→ Layer 2: java-bench
            └─→ Layer 2: flutter-bench
```

## Exit Codes

- `0` - All tests passed
- `1` - One or more tests failed

## Notes

- This container uses the pre-built `dev-bench-base:$USER` image
- No building occurs during testing
- Tests run quickly (<15 seconds)
- User must match host UID/GID in .env
- Tests inherit all Layer 0 functionality (not re-tested here)
