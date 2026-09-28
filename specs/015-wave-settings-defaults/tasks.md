# Tasks: Wave Settings Defaults

## Phase 1: Safe helper

- [x] T001 [US1] Implement preserve-existing and atomic JSON behavior in `scripts/configure-wave-settings.sh`
- [x] T002 [US2] Implement WSL Windows-profile resolution and explicit path override in `scripts/configure-wave-settings.sh`

## Phase 2: Verification and documentation

- [x] T003 [US1] Add fresh and existing settings fixtures in `devcontainer.test/test-configure-wave-settings.sh`
- [x] T004 Document opt-in usage and limitations in `docs/WAVE-SETTINGS.md`
- [x] T005 Validate `openspec/changes/add-wave-settings-defaults/`, run the isolated test, syntax checks, and `git diff --check`

## Dependencies

- T003 depends on T001 and T002.
- T005 depends on every source and documentation task.

## Implementation Strategy

Implement the non-destructive write path first, then path resolution, tests, and documentation. Do not wire the helper into automatic setup.
