# Tasks: Codex Profile Runtime

## Phase 1: Runtime selection

**Goal**: Make profile launches use the supported standalone executable without removing fallbacks.

**Independent Test**: A fixture with explicit, standalone, and normal-path commands selects the expected command in each scenario.

- [x] T001 [US1] Add standalone executable precedence to `base-image/files/codex-profile`
- [x] T002 [US1] Extend executable-selection coverage in `devcontainer.test/test-codex-profile.sh`

## Phase 2: Profile package visibility

**Goal**: Expose one canonical standalone package cache to every profile home.

**Independent Test**: Temporary manifest-backed profiles resolve `packages/standalone` to the fixture canonical cache without profile-data changes.

- [x] T003 [US2] Link the canonical standalone cache during setup in `scripts/setup-codex-profiles.sh`
- [x] T004 [US2] Add isolated cache-link coverage in `devcontainer.test/test-codex-profile.sh`

## Phase 3: Verification and governance

- [x] T005 Validate `openspec/changes/expose-codex-profile-runtime/` with strict OpenSpec validation
- [x] T006 Run `devcontainer.test/test-codex-profile.sh`, shell syntax checks, and `git diff --check`

## Dependencies

- T002 depends on T001.
- T004 depends on T003.
- T005 and T006 depend on all implementation tasks.

## Implementation Strategy

Implement executable precedence first, then package-cache visibility, and finish with isolated validation. No task restarts a daemon or container or reads real credentials.
