# Tasks: Separate Claude profile and lane commands

**Input**: [spec.md](spec.md), [plan.md](plan.md), [research.md](research.md)

## Phase 1: Profile-only entry point

- [x] T001 [US1] Make bare `pclaude` skip lane resolution, lane exports, and lane-start in `base-image/files/claude-profile`.
- [x] T002 [US1] Add regression coverage for lane-named windows and inherited lane identity in `devcontainer.test/`.

## Phase 2: Lane-aware entry point

- [x] T003 [US2] Add `lclaude` wrapper and preserve lane mode through tmux child launch in `base-image/files/`.
- [x] T004 [US2] Install `lclaude` in host and bench paths and verify command availability.
- [x] T005 [US2] Run existing lane resolution suites through `lclaude` and add a tmux mode regression.

## Phase 3: Migration and verification

- [x] T006 [US3] Preserve explicit `pclaude --lane` compatibility and `--no-lane` precedence.
- [x] T007 [US3] Update docs, usage guard restart text, openRepoTools pin, and installed command tests.
- [ ] T008 [US3] Validate OpenSpec, focused shell tests, Bash 3.2, lint, and PR checks.
