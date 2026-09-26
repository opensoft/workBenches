# Tasks: Remember Last Claude Profile

## Phase 1: Setup

- [x] T001 Confirm the isolated branch, active plan pointer, and clean feature worktree baseline in `AGENTS.md` and `specs/012-last-claude-profile/plan.md`
- [x] T002 Inspect existing launcher fixtures and identify reusable fake profile, Claude, jq, tmux, and lane helpers in `devcontainer.test/test-claude-profile-lane-default.sh` and `devcontainer.test/test-claude-profile-name-guard-hook.sh`

## Phase 2: Foundational

- [x] T003 Create a focused remembered-profile test harness with isolated HOME, manifest, profile directories, and fake Claude capture in `devcontainer.test/test-claude-profile-last-profile.sh`
- [x] T004 Add private atomic state validation cases for missing, stale, symlink, non-regular, empty, multiline, and mode behavior in `devcontainer.test/test-claude-profile-last-profile.sh`

## Phase 3: User Story 1 - Restart the last profile quickly (Priority: P1)

**Goal**: Bare `pclaude` reuses the last accepted canonical profile without lane behavior.

**Independent Test**: Explicitly launch an alias, then run bare `pclaude` and verify the canonical config directory is reused while lane tooling is never invoked.

- [x] T005 [US1] Add red tests for explicit canonical and alias launches, bare `pclaude`, unchanged state after non-run actions, and missing/stale diagnostics in `devcontainer.test/test-claude-profile-last-profile.sh`
- [x] T006 [US1] Implement validated remembered-profile reads and private atomic canonical-name writes in `base-image/files/claude-profile`
- [x] T007 [US1] Change empty invocation to a remembered `run` while preserving explicit action and profile precedence in `base-image/files/claude-profile`
- [x] T008 [US1] Verify all User Story 1 assertions pass in `devcontainer.test/test-claude-profile-last-profile.sh`

## Phase 4: User Story 2 - Resume the last profile with lane support (Priority: P1)

**Goal**: Bare `lclaude` uses the same remembered profile and retains normal lane resolution.

**Independent Test**: Run bare `lclaude` with a remembered profile and assert the existing lane-aware path is selected; then supply another profile and assert it wins and becomes remembered.

- [x] T009 [US2] Add red tests for bare `lclaude`, explicit override, and tmux child mode propagation in `devcontainer.test/test-claude-profile-last-profile.sh`
- [x] T010 [US2] Preserve wrapper and child-command lane semantics while threading remembered selection through `base-image/files/pclaude`, `base-image/files/lclaude`, and `base-image/files/claude-profile`
- [x] T011 [US2] Verify User Story 2 assertions and the complete existing lane-default suite pass in `devcontainer.test/test-claude-profile-last-profile.sh` and `devcontainer.test/test-claude-profile-lane-default.sh`

## Phase 5: User Story 3 - Keep profile-only prompts unblocked (Priority: P1)

**Goal**: The shared managed guard is inert only for profile-only processes and remains enforcing for lane-aware processes.

**Independent Test**: Configure one profile, execute its managed hook under both mode environments, and verify profile-only success versus lane-aware guard execution without changing foreign hooks.

- [x] T012 [US3] Add red tests for direct and tmux profile-only markers, lane-aware guard execution, legacy command migration, grouped foreign hooks, metadata preservation, and idempotence in `devcontainer.test/test-claude-profile-name-guard-hook.sh`
- [x] T013 [US3] Export and propagate the profile-only marker and install the gated managed hook command in `base-image/files/claude-profile`
- [x] T014 [US3] Extend managed-hook migration filters to remove the legacy exact command while preserving foreign nested hooks and metadata in `base-image/files/claude-profile`
- [x] T015 [US3] Verify User Story 3 assertions and all existing name-guard scenarios pass in `devcontainer.test/test-claude-profile-name-guard-hook.sh`

## Phase 6: Polish & Cross-Cutting Concerns

- [x] T016 [P] Update command help and operator examples for bare `pclaude` and `lclaude` in `base-image/files/claude-profile`, `docs/claude-multi-account-profiles.md`, and `README.md`
- [x] T017 [P] Run Bash syntax validation for `base-image/files/claude-profile`, `base-image/files/pclaude`, `base-image/files/lclaude`, and changed shell tests
- [x] T018 Run all focused Claude launcher suites in `py-bench` and record zero failures in `specs/012-last-claude-profile/quickstart.md`
- [x] T019 Run `openspec validate remember-last-claude-profile --strict` and repository documentation/contract checks from the feature worktree
- [x] T020 Mark completed OpenSpec and Speckit tasks and verify all implementation checkboxes are complete in `openspec/changes/remember-last-claude-profile/tasks.md` and `specs/012-last-claude-profile/tasks.md`

## Dependencies

- Phase 1 precedes all implementation.
- Phase 2 provides the shared harness and state edge cases for all user stories.
- User Story 1 establishes remembered selection and is required before User Story 2.
- User Story 3 shares launcher code but is independently testable after Phase 2; execute it after User Story 2 to minimize overlapping edits.
- Phase 6 follows all user stories.

## Parallel Opportunities

- T016 documentation and T017 syntax verification can proceed in parallel after implementation settles.
- Test authoring within each user story precedes that story's implementation; tasks that edit `base-image/files/claude-profile` remain sequential.

## Implementation Strategy

1. Deliver User Story 1 as the minimum useful remembered-profile behavior.
2. Reuse the same selection path for lane-aware User Story 2 without duplicating state logic.
3. Complete User Story 3 before release so profile-only launches are usable from project directories.
4. Validate all old launcher suites as the compatibility gate.
