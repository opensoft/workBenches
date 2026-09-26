# Implementation Plan: Remember Last Claude Profile

**Branch**: `012-last-claude-profile` | **Date**: 2026-09-26 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/012-last-claude-profile/spec.md`

## Summary

Remember the canonical profile selected by a valid Claude run, have the two user-facing wrappers request a run with an omitted profile, and preserve their profile-only versus lane-aware split. Implement one private atomic state record in the Claude profiles home and make the shared lane-name hook conditional on a process marker that survives tmux re-exec.

## Technical Context

**Language/Version**: Portable Bash compatible with the repository's current macOS Bash 3.2 constraints; jq filters for settings migration

**Primary Dependencies**: Existing `jq`, `tmux`, Claude CLI, and optional `lane-start`/`lanes-edit.sh` tooling

**Storage**: One local non-secret state file under the selected Claude profiles home; existing per-profile JSON settings

**Testing**: Repository shell harnesses under `devcontainer.test/`, executed in `py-bench`, plus `bash -n` and strict OpenSpec validation

**Target Platform**: Linux, WSL2, and macOS workBenches environments

**Project Type**: Shared command-line launcher and image/setup source

**Performance Goals**: Remembered selection adds no network requests and no perceptible delay to launch

**Constraints**: Preserve existing explicit syntax, aliases, credentials, sessions, lane precedence, foreign hooks, and dirty main-checkout work; do not require Key Vault for non-secret state

**Scale/Scope**: Hundreds of local profile directories with concurrent terminals and optional tmux re-exec

## Constitution Check

The repository constitution is still an unratified template and contains no enforceable project-specific gates. The applicable repository and user-global rules are satisfied:

- Work is isolated in a Speckit worktree based on `origin/main`.
- OpenSpec proposal, design, capability spec, and trackable tasks exist before implementation.
- Tests are added before launcher behavior changes and run through the declared `py-bench` tooling.
- Existing profile credentials, sessions, bench submodules, and unrelated dirty files remain untouched.
- The design is minimal: one state record and one launch-mode marker, with no new dependency or service.

Post-design re-check: PASS. Phase 1 introduces no new constitutional conflict or unbounded complexity.

## Project Structure

### Documentation (this feature)

```text
specs/012-last-claude-profile/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── cli.md
├── checklists/
│   └── requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
base-image/files/
├── claude-profile
├── pclaude
└── lclaude

devcontainer.test/
├── test-claude-profile-lane-default.sh
├── test-claude-profile-name-guard-hook.sh
└── test-claude-profile-last-profile.sh

docs/
└── claude-multi-account-profiles.md
README.md
```

**Structure Decision**: Extend the existing shared launcher and focused shell-test layout. Add one focused remembered-profile suite instead of creating a new module or dependency, and update the two existing operator entry points.

## Complexity Tracking

No constitution violations or additional architectural layers require justification.
