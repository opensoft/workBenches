# Layer 1a Test Environment

Test harness for `dev-bench-base:$USER` - the Layer 3 user image built on top of the developer tools layer.

## What This Tests

Layer 1a adds developer tools on top of Layer 0:
- Python 3.x with pip and development tools (black, flake8, isort, pylint, pytest, ipython)
- Node.js LTS with npm and yarn
- Python package managers (uv)
- AI CLI tools (claude, codex, gemini, opencode)
- OpenCode configuration with plugins (oh-my-opencode, opencode-openai-codex-auth)
- Zsh and oh-my-zsh with plugins
- PATH configuration for all dev tools

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

## Test Script

The `test.sh` script validates:
- ✅ Python development tools
- ✅ Node.js development tools
- ✅ Python package managers (uv)
- ✅ AI CLI tools (claude, codex, gemini, opencode)
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
