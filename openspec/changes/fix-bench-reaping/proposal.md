# Proposal

## Why

Short-lived interactive pyBench shells leave terminated prompt-helper processes behind because the container's keepalive process does not reap orphaned children. A runtime reaper prevents accumulation without changing the personalized image or disabling the user's prompt.

## What Changes

- Enable process reaping in the shared Wave Compose override used to create or repair benches, including pyBench.
- Add regression coverage for first creation, explicit repair, and safe reuse of running containers.
- Activate only py-bench through its declared repair lifecycle and verify repeated interactive shell exits leave no zombies.

## Capabilities

### New Capabilities

- `bench-process-reaping`: Wave Compose-created benches reap orphaned children while retaining shared-container reuse and explicit replacement authority.

### Modified Capabilities

None.

## Impact

The parent repository's Wave launcher and launcher regression suite change. No Layer 0-3 image recipe, bench submodule, credentials, or unrelated live container changes. Spec Kit feature `022-fix-bench-reaping` owns implementation tasks; source remains in its linked feature worktree pending publication. Repository-wide active-plan selectors remain unchanged.
