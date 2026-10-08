## Why

A stopped bench can retain an unusable Docker Desktop WSL bind mapping even when its real host source exists. The shared Wave launcher currently exits on the raw startup error, without identifying the recovery or distinguishing it from missing credentials.

## What Changes

- Validate stopped containers' bind sources and known file/directory types before startup or explicit recreation.
- Recognize the specific missing Docker Desktop WSL mount-source error and explain controlled recovery.
- Preserve normal launch's non-destructive behavior; recreation remains an explicit `--repair` action, with no retry loop or Docker/WSL restart.
- Refuse to silently manufacture a missing Claude configuration file during recreation.
- Add shared-launcher regression coverage and recovery documentation.

## Capabilities

### New Capabilities

- `bench-mount-recovery`: Credential-safe source validation and explicit bounded recovery guidance for stale stopped-container bind mounts.

### Modified Capabilities

None.

## Impact

Shared `scripts/wave-container-shell.sh`, its existing regression suite, and startup documentation. No image recipes, bench submodule pins, credentials, or live containers change. The user approved implementation of the proposed explicit-repair design in this chat; source publication and live replacement are separate operations.
