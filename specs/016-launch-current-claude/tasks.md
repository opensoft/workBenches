# Tasks: Launch Only the Newest Published Claude Code

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md); the ratified OpenSpec change `launch-current-claude`, task 1.2

## Phase 1: Setup

No new dependencies. `claude-current` and `claude-restart-check` are `opensoft/openRepoTools` commands (#134), called from `PATH`; the suites use stubs at their contract.

## Phase 2: Foundational

- [x] T001 Harden `devcontainer.test/test-claude-profile-binary-selection.sh`: unset `CLAUDE_BIN` and the three hand-off names, take the checkout physically, make the launcher argument absolute, keep the #109 cases on the fallback through `WORKBENCHES_CLAUDE_CURRENT_BIN`, and log what the fake `lane-start` and the fake tmux server hand on.

## Phase 3: User Story 1 - Newest published client (P1)

**Goal**: A session launch starts the absolute path `claude-current` verified, and hands it to `lane-start`.

**Independent Test**: A stub resolver's verified, ahead, unverified, stale and allowed-stale outcomes, direct and through `lane-start`.

- [x] T002 [US1] Add resolver fixtures and cases (verified, ahead, unverified, stale refused, stale allowed, no candidate, outside the contract, lane-start hand-off, refused hand-off) in `devcontainer.test/test-claude-profile-binary-selection.sh`.
- [x] T003 [US1] Replace the resolution block after `latest_installed_claude()` in `base-image/files/claude-profile` with Decision 4's precedence, `require_claude_bin`, and the `CLAUDE_VERIFIED_VERSION` prefix on the `lane-start` call.

## Phase 4: User Story 2 - Pins, inherited choices, no resolver (P2)

**Goal**: A pin is untouched, an inherited pair is resolved again, a host without the resolver still launches, and a launch that starts no session never waits on npm.

**Independent Test**: The resolver's call log across pin, inherited, offline, fallback and tmux-wrapped launches.

- [x] T004 [US2] Add pin, inherited, offline (`--version`, `status`, `mcp`), fallback-with-notice and tmux cases (the child resolves once; a stale server marker equal to a pin; a refused pane is kept) in `devcontainer.test/test-claude-profile-binary-selection.sh`.
- [x] T005 [US2] Thread only a pin into the tmux child, clearing the marker and the version; resolve `login` and `status` offline; move the home-link check into `ensure_claude_home_link` in `base-image/files/claude-profile`.

## Phase 5: User Story 3 - Restart notice (P2)

**Goal**: The status line prints `claude-restart-check`'s line first, and is unchanged without it.

**Independent Test**: A stub check that prints a line, prints nothing, or is absent; a JSON with and without `version`.

- [x] T006 [US3] Add the restart cases to `devcontainer.test/test-claude-tmux-statusline.sh`, and name no check in the existing panel renders there and in `devcontainer.test/test-claude-statusline-snapshots.sh`.
- [x] T007 [US3] Add `(.version // "")` as the last `jq` field and the check call in `base-image/files/claude-statusline-command.sh`.

## Phase 6: User Story 4 - Layer 3 user copy (P3)

**Goal**: A Layer 3 image carries Claude Code at npm latest in the runtime user's prefix.

**Independent Test**: `user-layer/build.sh` under mocked Docker; the Dockerfile's `RUN` against fake npm, node and claude.

- [x] T008 [US4] Add `devcontainer.test/test-layer3-claude-version.sh` and register it in `.github/workflows/ai-cli-layer3.yml`; teach the mocks in `devcontainer.test/test-layer3-codex-version.sh` and `devcontainer.test/test-ensure-layer3-freshness.sh` the new lookup.
- [x] T009 [US4] Add `--claude-version`, the bounded lookup and `CLAUDE_CODE_VERSION` in `user-layer/build.sh`, and the install step in `user-layer/Dockerfile`.

## Phase 7: Polish and validation

- [x] T010 Run every claude-profile suite in `devcontainer.test/test.sh`, the status line suites and the Layer 3 suites locally, and record the counts (#105).
- [x] T011 Show each rule is tested: the old launcher, status line and Layer 3 files from `main`, and a mutant per rule, each fail their suite.
- [x] T012 Test-merge against `origin/012-last-claude-profile` (#114) and record the conflicting paths.
- [x] T013 Update `.specify/feature.json` and the `AGENTS.md` Speckit block, and add the ambient hand-off names to the binary-selection CI step in `.github/workflows/speckit-git-bash.yml`.
- [x] T014 Spell the resolver's install act once, as `claude_current_install_act`, in `base-image/files/claude-profile`, and name its one assignment as the second exclusion from `R-A11-13`'s spelling count in `devcontainer.test/test-claude-profile-amendment-11.sh` (found by T010: the notice's two literal spellings failed that suite).

## Dependencies & Execution Order

T001 precedes the cases that rely on its isolation. Each test task precedes its implementation task for red/green (T002 before T003, T004 before T005, T006 before T007, T008 before T009). T010 to T012 and T014 follow all implementation. User Story 1 is the MVP. User Stories 2 and 3 are independent of each other, and User Story 4 is independent of both.

## Parallel Opportunities

User Story 3 (the status line) and User Story 4 (Layer 3) touch disjoint files and can proceed beside User Stories 1 and 2, which share the launcher and its suite.

## Implementation Strategy

Land the launcher precedence first, because it alone makes every new session current wherever `claude-current` is installed. The status line and Layer 3 follow, and each degrades to today's behavior until `opensoft/openRepoTools#134` lands and a Layer 3 image is rebuilt.
