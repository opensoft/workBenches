# Tasks: Prefer Updated Claude Code

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md)

## Phase 1: Setup

No new dependencies or project structure are needed.

## Phase 2: Foundational

The existing `claude-profile` launcher and test harness provide the foundation.

## Phase 3: User Story 1 - Latest installed client (P1)

**Goal**: New direct and lane launches choose the newest valid native executable.

**Independent Test**: A stale PATH client loses to a newer native install in direct and lane fixtures.

- [x] T001 [US1] Add numeric native-version and lane-handoff fixtures in `devcontainer.test/test-claude-profile-binary-selection.sh`.
- [x] T002 [US1] Resolve newest installed executable at each launcher invocation in `base-image/files/claude-profile`.

## Phase 4: User Story 2 - Override and fallback (P2)

**Goal**: Explicit overrides and existing fallback continue working.

**Independent Test**: Override wins; missing or unusable native entries use PATH.

- [x] T003 [US2] Extend `devcontainer.test/test-claude-profile-binary-selection.sh` with override, malformed-entry, and missing-directory cases.

## Phase 5: Polish and validation

- [x] T004 Validate `base-image/files/claude-profile` and `devcontainer.test/test-claude-profile-binary-selection.sh` through the declared bench test path and inspect the diff for unrelated changes.

## Dependencies & Execution Order

T001 precedes T002 for red/green verification. T003 follows T002. T004 follows all implementation tasks. User Story 1 is the MVP; User Story 2 protects operator compatibility.

## Parallel Opportunities

None: both stories share the launcher and one focused test file.

## Implementation Strategy

Implement and validate the local selection first, then confirm override/fallback behavior and run the focused regression suite.
