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
- ✅ Claude profile lane default and SessionStart hook
  (lane-collision-protocol Amendment 8(c) and 8(e))

Four suites in this directory are **host-run** rather than container-run,
because they read the repository's own `scripts/`, `base-image/` and
`devBenches/base-image/`, which are not mounted in the container. All four run
in CI (`.github/workflows/speckit-git-bash.yml`), and all four are run from the
repository root:

```bash
bash devcontainer.test/test-setup-estate-commands.sh
bash devcontainer.test/test-claude-profile-skill-install.sh
bash devcontainer.test/test-base-image-dockerfile.sh
bash devcontainer.test/test-claude-profile-name-guard-hook.sh
```

- `test-setup-estate-commands.sh` — `scripts/setup-estate-commands.sh` on a
  host, and the container-start step that mirrors it
  (`devBenches/base-image/files/estate/`, opensoft/workBenches#90).
- `test-claude-profile-skill-install.sh` — that `openRepoTools --install` is
  the sole writer of the skills, command files and hook entries
  (lane-collision-protocol Amendment 9 adoption act 4b).
- `test-base-image-dockerfile.sh` — the source-only wiring check on BOTH
  Dockerfiles. It never runs `docker build`, which is the point: nothing else
  here can, so this is what catches a launcher dependency or a container-start
  step that is referenced but never copied into the image.
- `test-claude-profile-name-guard-hook.sh` — the launcher's `UserPromptSubmit`
  name guard, including the downgrade that removes it and the line it prints
  when it does (Amendment 12 adoption act 3).

## When to Use

Run these tests:
- After rebuilding Layer 0: `cd workBenches/base-image && ./build.sh`
- Before making changes that affect all bench types
- To validate base system functionality
- When troubleshooting tool availability issues

## Layer Architecture

```
Layer 0: workbench-base (THIS LAYER)
    ├─→ Layer 1a: dev-bench-base (Python, Node.js, AI CLIs)
    ├─→ Layer 1b: sys-bench-base (Ansible, Terraform)
    └─→ Layer 1c: bio-bench-base (Bioinformatics tools)
```

## Exit Codes

- `0` - All tests passed
- `1` - One or more tests failed

## Notes

- This container uses the pre-built `workbench-base:latest` image
- No building occurs during testing
- Tests run quickly (<10 seconds)
- User must match host UID/GID in .env
