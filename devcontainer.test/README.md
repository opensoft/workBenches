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

Seven suites in this directory are **host-run** rather than container-run,
because they read the repository's own `scripts/`, `base-image/` and
`devBenches/base-image/`, or require a fake Docker control surface that is not
mounted in the container. All seven run in CI through
`.github/workflows/speckit-git-bash.yml` or
`.github/workflows/cascade-image-validation.yml`, and all seven are run from
the repository root:

```bash
bash devcontainer.test/test-setup-estate-commands.sh
bash devcontainer.test/test-setup-workspace-repo.sh
bash devcontainer.test/test-claude-profile-skill-install.sh
bash devcontainer.test/test-base-image-dockerfile.sh
bash devcontainer.test/test-claude-profile-name-guard-hook.sh
bash devcontainer.test/test-claude-profile-amendment-11.sh
bash devcontainer.test/test-cascade-image-validation.sh
```

- `test-setup-estate-commands.sh` — `scripts/setup-estate-commands.sh` on a
  host, and the container-start step that mirrors it
  (`devBenches/base-image/files/estate/`, opensoft/workBenches#90).
- `test-setup-workspace-repo.sh` — `scripts/setup-workspace-repo.sh`, the
  workspace-repository step of the onboarding chain (lane-collision-protocol
  Amendment 9(e)).
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
- `test-claude-profile-amendment-11.sh` — lane-collision-protocol Amendment 11
  (the launcher's window reuse, directory and precedence-4 rules) plus the
  vendored handoff/lane-swap skill's mechanics (opensoft/workBenches#93).
- `test-cascade-image-validation.sh` — cascade output discovery, immutable
  Layer 2 image probes, read-only Layer 3 state reporting, and atomic manifest
  behavior against a fake Docker control surface.

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

## Claude npm integrity regression

\`bash devcontainer.test/test-claude-npm-guard.sh\` uses an isolated home/prefix
and a loopback-only fixture registry to exercise npm 12's actual script policy.
It does not read provider credentials, download Claude, or update the operator's
installation. CI pins npm 12.0.2, where the original failure was observed.

The Layer 3 guard also runs after Wave mounts, so a mounted home does not hide
the policy. Existing native installations are not converted to npm.

## Exit Codes

- `0` - All tests passed
- `1` - One or more tests failed

## Notes

- This container uses the pre-built `workbench-base:latest` image
- No building occurs during testing
- Tests run quickly (<10 seconds)
- User must match host UID/GID in .env

## Containerized setup runtime

Run the Docker-only workstation test through the declared service. It removes
Python, jq, Git, and curl from the simulated host PATH, checks host command
routing, service readiness/restart, TUI cancellation, and Vault mount isolation.
It creates and cleans only `workbenches-runtime-test-*` containers/networks.

```bash
export WORKBENCHES_SOURCE_ROOT="$PWD"
export WORKBENCHES_DOCKER_GID="$(stat -c %g /var/run/docker.sock)"
docker compose -p workbenches-runtime-test -f devcontainer.test/docker-compose.yml --profile tools-runtime run --rm --no-deps tools-runtime
docker compose -p workbenches-runtime-test -f devcontainer.test/docker-compose.yml --profile tools-runtime down --remove-orphans
python3 devcontainer.test/test-setup-services.py
```

`WORKBENCHES_SOURCE_ROOT` must be the absolute checkout path, also visible to
the selected local Docker engine. The service shares `/tmp` for private fixture
files and uses the local Docker socket; run it on a trusted development machine.
`WORKBENCHES_TEST_VAULT=0` skips the optional public-CLI image smoke check.
Focused installer unit fixtures use `WORKBENCHES_TEST_NATIVE_TOOLS=1` explicitly;
the service above exercises the production container path without that setting.

The credential-test fixture exercises real persistent helper containers with
fake provider CLIs. It checks Azure payload transfer/device-session cleanup and
Bitwarden/1Password recovery/cancellation without cloud access or real secrets.
