# Feature Specification: Separate Claude profile and lane commands

**Feature Branch**: `011-separate-claude-lane-launch`  
**Created**: 2026-09-23  
**Status**: Ready for implementation  
**Input**: Make `pclaude` profile-only and introduce `lclaude` for lane-aware profile launches.

## User Scenarios & Testing

### User Story 1 - Start a profile without a lane (Priority: P1)

An operator starts a Claude profile with `pclaude` and gets a profile session without any lane prompt or registration, even inside a window that names a lane.

**Independent Test**: Run a profile launch with fake lane tools and assert none are called and no lane identity reaches Claude.

**Acceptance Scenarios**:

1. **Given** an existing lane window, **When** the operator runs `pclaude <profile>`, **Then** Claude starts under the requested profile without lane resolution or `lane-start`.
2. **Given** inherited lane variables, **When** the operator runs `pclaude <profile>`, **Then** Claude does not claim the inherited lane.

### User Story 2 - Start or resume a lane (Priority: P1)

An operator starts `lclaude` and retains the existing lane resolution and safe restart behavior.

**Independent Test**: Invoke `lclaude` with explicit and inferred lane fixtures and assert the established lane handoff path is used.

**Acceptance Scenarios**:

1. **Given** an explicit lane, **When** the operator runs `lclaude --lane <lane> <profile>`, **Then** `lane-start` receives the selected profile's binary and arguments.
2. **Given** a lane-named window, **When** the operator runs `lclaude <profile>`, **Then** the existing window lane is resumed.
3. **Given** an interactive launch outside tmux, **When** `lclaude` relaunches in tmux, **Then** the child remains lane-aware.

### User Story 3 - Migrate existing callers (Priority: P2)

Existing explicit lane invocations continue to work while restart instructions move to `lclaude`.

**Independent Test**: Verify `pclaude --lane` and `lclaude` routes, plus installed command and handoff output.

**Acceptance Scenarios**:

1. **Given** an existing `pclaude --lane` caller, **When** it launches, **Then** the lane handoff remains available.
2. **Given** a handoff on an updated installation, **When** it prints a restart, **Then** it names `lclaude`.

### Edge Cases

- `--no-lane` wins over an explicit lane option on either entry point.
- A noninteractive subcommand does not start a lane or picker.
- A missing `lane-start` keeps the existing refusal behavior for an explicit lane.
- A mixed installation without `lclaude` uses an explicit lane fallback for restarts.

## Requirements

### Functional Requirements

- **FR-001**: Bare `pclaude` MUST not discover, select, or take a lane.
- **FR-002**: `lclaude` MUST use the existing lane resolution and refusal rules.
- **FR-003**: `lclaude` MUST share profile and binary selection with `pclaude`.
- **FR-004**: Interactive tmux relaunch MUST preserve the selected lane mode and binary.
- **FR-005**: Explicit `pclaude --lane` MUST retain compatibility during migration.
- **FR-006**: Profile-only sessions MUST clear inherited lane identity used by hooks.
- **FR-007**: Host and image installation MUST place `lclaude` beside `pclaude`.
- **FR-008**: Lane restart instructions MUST use `lclaude` when installed.

## Success Criteria

### Measurable Outcomes

- **SC-001**: All profile-only regression scenarios start without a lane tool call.
- **SC-002**: All existing lane resolution regression scenarios pass through `lclaude`.
- **SC-003**: A tmux parent-to-child regression preserves lane mode and binary selection.
- **SC-004**: Both host and bench installation checks find executable `pclaude` and `lclaude`.

## Assumptions

- Interactive `pclaude` keeps its existing tmux behavior; only lane behavior changes.
- Explicit `pclaude --lane` remains available until a separate removal change.
