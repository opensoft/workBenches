# Feature Specification: Bench Process Reaping

**Feature Branch**: `021-fix-bench-reaping`

**Created**: 2026-10-07

**Status**: Ready for implementation

**Input**: User description: "fix it" after diagnosis of two orphaned pyBench prompt-helper zombies.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Exit shells cleanly (Priority: P1)

Brett can open and close interactive pyBench shells without accumulating defunct background helpers.

**Why this priority**: A long-lived shared bench must clean up terminated helper processes.

**Independent Test**: Repeatedly open and exit interactive shells, then count defunct processes after cleanup.

**Acceptance Scenarios**:

1. **Given** the repaired pyBench, **When** ten interactive shell checks finish, **Then** no defunct orphaned helper remains.
2. **Given** a new Wave Compose-created bench, **When** a child exits after its parent, **Then** it is collected by the container's process supervisor.

### User Story 2 - Keep one shared bench (Priority: P2)

Repeated Wave link starts continue connecting to the same running personalized bench.

**Why this priority**: A process fix must not disrupt the established shared-container workflow.

**Independent Test**: Run the Wave check twice and compare container identities.

**Acceptance Scenarios**:

1. **Given** a running pyBench, **When** ordinary Wave checks run, **Then** its identity and persistent mounts do not change.
2. **Given** running cloudBench and 365Bench, **When** pyBench is explicitly replaced, **Then** the other two benches remain unchanged.

### Edge Cases

- Existing live containers without reaping retain their identity until explicit replacement is authorized.
- A container name owned by an unrelated image remains protected by the existing foreign-container guard.
- User files outside persistent mounts must be reviewed before replacement.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Wave Compose-created benches MUST collect terminated orphaned children.
- **FR-002**: Normal launches MUST reuse the current running bench.
- **FR-003**: pyBench repair MUST retain the personalized user and persistent project/profile/history storage.
- **FR-004**: This activation MUST replace only py-bench, preserving unrelated live benches.
- **FR-005**: Verification MUST separately establish source-test results and live-container behavior.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Zero defunct processes remain after ten interactive shell exits and cleanup.
- **SC-002**: Two normal Wave checks retain the same pyBench identity.
- **SC-003**: The unrelated cloudBench and 365Bench identities and start times are unchanged.
- **SC-004**: The user remains brett with numeric user and group identity 1000.

## Assumptions

- User approval covers pyBench replacement and its attached terminal interruption only.
- No image refresh is necessary for this runtime lifecycle fix.
- Changes to the normal launcher require publication; this request does not itself authorize unrelated container replacement.
