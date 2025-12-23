# Layer 0 Test Environment

Test harness for `workbench-base:latest` - the foundation image for all bench types.

## What This Tests

Layer 0 provides the system foundation used by ALL bench types:
- System tools (git, curl, wget, jq)
- GitHub CLI (gh)
- Build tools (gcc, make, build-essential)
- Network utilities
- User configuration
- Basic shell environment (zsh)

Note: sudo is NOT included - use root user via Dockerfile or docker exec when needed.

## Quick Start

```bash
# 1. Create .env file
cp .env.example .env

# 2. Start test container
docker compose up -d

# 3. Run tests
docker compose exec test ./test.sh

# 4. Clean up
docker compose down
```

## Test Script

The `test.sh` script validates:
- ✅ Version control tools (git)
- ✅ Network tools (curl, wget, ping, netstat)
- ✅ Utilities (jq, vim, nano)
- ✅ GitHub CLI (gh)
- ✅ Build tools (gcc, make, pkg-config)
- ✅ System tools (zsh, screen, ssh, cron)
- ✅ User configuration (correct UID/GID)

## When to Use

Run these tests:
- After rebuilding Layer 0: `cd workBenches/base-image && ./build.sh`
- Before making changes that affect all bench types
- To validate base system functionality
- When troubleshooting tool availability issues

## Layer Architecture

```
Layer 0: workbench-base (THIS LAYER)
    ├─→ Layer 1a: devbench-base (Python, Node.js, AI CLIs)
    ├─→ Layer 1b: adminbench-base (Ansible, Terraform)
    └─→ Layer 1c: designbench-base (Design tools)
```

## Exit Codes

- `0` - All tests passed
- `1` - One or more tests failed

## Notes

- This container uses the pre-built `workbench-base:latest` image
- No building occurs during testing
- Tests run quickly (<10 seconds)
- User must match host UID/GID in .env
