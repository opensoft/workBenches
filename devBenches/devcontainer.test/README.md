# Layer 1a Test Environment

Test harness for `devbench-base:$USER` - the developer tools layer extending Layer 0.

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

# 2. Ensure Layer 1 image exists
cd ../../base-image && ./build.sh --user brett && cd ../../devcontainer.test

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
- After rebuilding Layer 1: `cd devBenches/base-image && ./build.sh --user brett`
- Before making changes to developer tools
- To validate AI CLI installations
- When troubleshooting development tool issues
- After updating OpenCode plugin configuration

## Layer Architecture

```
Layer 0: workbench-base (system tools)
    └─→ Layer 1a: devbench-base (THIS LAYER)
            ├─→ Layer 2: frappe-bench
            ├─→ Layer 2: java-bench
            └─→ Layer 2: flutter-bench
```

## Exit Codes

- `0` - All tests passed
- `1` - One or more tests failed

## Notes

- This container uses the pre-built `devbench-base:$USER` image
- No building occurs during testing
- Tests run quickly (<15 seconds)
- User must match host UID/GID in .env
- Tests inherit all Layer 0 functionality (not re-tested here)
