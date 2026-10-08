# Implementation Plan: Stale Bench Mount Recovery

**Branch**: `024-fix-stale-bench-mounts` | **Date**: 2026-10-08 | **Spec**: [spec.md](spec.md)

## Summary

Add credential-safe source preflight and targeted missing-staging diagnostics to the shared launcher. Keep recreation behind `--repair`, using the existing lifecycle and non-force removal for stopped containers.

## Technical Context

**Language**: Bash.
**Dependencies**: Existing Docker/Dev Containers CLI tooling, shared helpers' jq dependency for staged-source resolution, standard filesystem predicates, optional GNU timeout.
**Testing**: Existing mocked Wave lifecycle suite, related helper-safety suites, Bash syntax, OpenSpec strict validation.
**Platform**: Shared workBenches host launcher, including Docker Desktop WSL.
**Constraints**: No credential reads, daemon restarts, new dependencies, unrelated gitlink changes, or live replacement.

## Constitution Check

The repository constitution is an unfilled template and adds no adopted rules. Repository/global instructions govern: linked worktree, no host-specific committed paths, declared bench execution, preserved user changes, and one executable task list.

## Project Structure

- `scripts/wave-container-shell.sh`: source validation, explicit repair fencing, bounded startup diagnostic.
- `devcontainer.test/test-wave-container-shell.sh`: new failure and preservation fixtures.
- `docs/bench-mount-recovery.md`: recovery and activation boundaries.
- `specs/024-fix-stale-bench-mounts/tasks.md`: only executable checklist.

## Verification and Deployment

Run mocked tests in the already-running bench; no live stale-mount experiments. Record exact results and deployment status. The user approved opening and landing the tested source PR after checks and review pass. py-bench replacement remains a separate operation and is not authorized by that approval.
