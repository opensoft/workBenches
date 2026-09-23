# Implementation Plan: Prefer Updated Claude Code

**Branch**: `010-prefer-updated-claude` | **Date**: 2026-09-22 | **Spec**: [spec.md](spec.md)

**Input**: Use the newest already-installed native Claude Code version for new workBenches profile launches without a synchronous update.

## Summary

At each profile-launcher invocation, resolve a nonempty explicit `CLAUDE_BIN` first, then the newest executable in the native per-user versions directory, then the existing PATH fallback. Carry that resolved path through direct and lane starts. Cover numeric version ordering, invalid entries, overrides, fallback, and lane handoff with local fixture binaries.

## Technical Context

**Language/Version**: Bash 3.2-compatible shell
**Primary Dependencies**: Existing Bash and core utilities
**Storage**: None; read-only inspection of installed executables
**Testing**: Focused Bash regression test in `devcontainer.test/`
**Target Platform**: Linux workBenches containers; keep selection logic portable to Bash 3.2
**Project Type**: Shared CLI launcher
**Performance Goals**: Local scan only; no network wait on startup
**Constraints**: Preserve `CLAUDE_BIN` and PATH fallback; no running-session mutation
**Scale/Scope**: One launcher and one focused test file

## Constitution Check

The repository constitution is still an unfilled template, so it imposes no additional concrete gate. Repo-local and user-global instructions apply: isolated feature worktree, no host-specific paths in committed files, declared bench validation, and preservation of unrelated work. Rechecked after design: no exception is needed.

## Project Structure

### Documentation

```text
specs/010-prefer-updated-claude/
├── spec.md
├── checklists/requirements.md
├── plan.md
├── research.md
├── quickstart.md
└── tasks.md
```

### Source Code

```text
base-image/files/claude-profile
devcontainer.test/test-claude-profile-binary-selection.sh
devcontainer.test/test.sh
```

**Structure Decision**: Keep selection in the shared launcher so every profile path, including `lane-start`, receives the same executable; add a focused test alongside existing launcher tests.
