## Why

Wave bench shortcuts currently trust a Docker container name before verifying
that the container belongs to the requested workBench. A different workload
using `py-bench` can be started and modified by the shortcut, then fails when
the launcher assumes the workBench user exists.

## What Changes

- Make every shipped Wave bench shortcut select the `brett` Layer 3 account
  explicitly.
- Make the shared Wave launcher verify a pre-existing container's configured
  image before it starts, recreates, or bootstraps that container.
- Refuse a name collision with a clear recovery message and no mutation of the
  foreign container.
- Cover the expected Layer 3 and foreign-container cases with regression tests.

## Capabilities

### New Capabilities

- `wave-bench-identity-guard`: Safe, deterministic Wave shortcut startup for
  user-specific workBench containers.

### Modified Capabilities

- None.

## Impact

- `scripts/wave-container-shell.sh`
- Wave user widget configuration
- Wave launcher regression tests
- No Docker image or running container is changed by the guard itself.
