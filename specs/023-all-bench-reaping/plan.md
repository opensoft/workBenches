# Implementation Plan: All-bench process reaping

**Branch**: `023-all-bench-reaping` | **Date**: 2026-10-07 | **Spec**: [spec.md](spec.md)

## Summary

Extend the shipped Wave-only protection to canonical child Compose definitions and distributed bench templates. See the [governed design](../../openspec/changes/add-all-bench-reaping/design.md).

## Technical Context

**Language/Version**: Compose YAML, Bash, Python 3 standard library.
**Primary Dependencies**: Docker Compose configuration parser, existing Wave fixture tests.
**Storage**: Existing persistent volumes and bind mounts unchanged.
**Testing**: Positive and negative checker fixtures, effective Compose configuration checks, Wave lifecycle regression.
**Target Platform**: Docker Desktop/WSL and Linux Docker hosts.
**Project Type**: Cross-repository bench configuration.
**Constraints**: No live replacement, secret output, new host-absolute paths or unrelated edits.
**Scale/Scope**: Fourteen child repositories plus parent family/test definitions.

## Constitution Check

The checked-in constitution is an unfilled scaffold, not an additional gate. Global workflow and repository AGENTS rules apply: external linked worktrees, one executable task list, native Git, bench-routed tests, preserved active work and child publication before pins.

## Project Structure

- Parent: `scripts/check-bench-init.py`, `devcontainer.test/test-bench-init.py`, family/test Compose files, CI and this feature's governance.
- Child slices: each bench's tracked canonical Compose, templates and tests in external linked feature worktrees.
- No child project restructuring or duplicate Speckit task lists.

## Verification and Rollout

Resolve startup configurations without starting containers. Record red/green results, all covered services and current live container identities. Publish and land only after checks and exact-head Codex reviews; advance the eight registered gitlinks afterward. Leave six setup-cloned repositories separate. Preserve the parent default active-plan selector when preparing publication.
