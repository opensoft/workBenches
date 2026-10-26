# Tasks: Default Claude startup effort

## Phase 1: Setup

- [x] T001 Record accepted requirements and isolated worktree in `openspec/changes/default-claude-effort/` and `specs/020-default-claude-effort/spec.md`.

## Phase 2: Foundation

- [x] T002 Identify shared launch flags and safe argument boundaries in `base-image/files/claude-profile`.

## Phase 3: User Story 1 - Startup default

**Independent test:** Mock Claude observes one xhigh fallback for ordinary, resume, and print-mode startup.

- [x] T003 [US1] Add failing startup argument regressions in `devcontainer.test/test-claude-profile-effort.sh`.
- [x] T004 [US1] Implement default effort selection in `base-image/files/claude-profile`.

## Phase 4: User Story 2 - Overrides and utilities

**Independent test:** Explicit CLI/environment choices and non-conversation commands receive no added effort argument.

- [x] T005 [US2] Cover CLI forms, environment choices, prompt boundary, and utility exclusions in `devcontainer.test/test-claude-profile-effort.sh`.
- [x] T006 [US2] Preserve overrides and utility behavior in `base-image/files/claude-profile`.

## Phase 5: Verification and delivery

- [x] T007 Document precedence in `docs/claude-multi-account-profiles.md`.
- [x] T008 Run focused and existing launcher suites, recording results in `specs/020-default-claude-effort/verification.md`.
- [x] T009 Record source versus live deployment status and recovery path in `specs/020-default-claude-effort/verification.md`.

## Dependencies and execution strategy

T001 -> T002 -> T003 -> T004 -> T005 -> T006 -> T007 -> T008 -> T009. US1 provides the MVP; US2 prevents override regressions before delivery. No parallel agent work needed for this small shared-file change; documentation can be checked independently after implementation.
