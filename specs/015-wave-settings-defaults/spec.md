# Feature Specification: Wave Settings Defaults

**Feature Branch**: `015-wave-settings-defaults`

**Created**: 2026-09-27

**Status**: Ready

**Input**: User description: "Keep the Wave clipboard defaults helper as a safe, documented, explicit setup utility that preserves user choices."

## User Scenarios & Testing

### User Story 1 - Apply missing defaults safely (Priority: P1)

As a Wave user, I want a command that adds missing clipboard defaults without changing settings I already chose.

**Why this priority**: Workstation setup should be repeatable without destroying personal terminal preferences.

**Independent Test**: Run the helper against a temporary settings file containing custom and conflicting values, then verify only absent keys are added.

**Acceptance Scenarios**:

1. **Given** no settings file, **When** the helper runs, **Then** it creates a valid object with the documented defaults.
2. **Given** existing settings and an explicit value, **When** the helper runs, **Then** that value and all unrelated keys remain unchanged.

### User Story 2 - Target the correct Wave installation (Priority: P1)

As a WSL workstation user, I want the helper to target the Windows Wave profile by default, so it updates the settings consumed by the actual application.

**Why this priority**: Writing a Linux-side file that Wave never reads gives a false success.

**Independent Test**: Verify path resolution can use an explicit test directory and that the documented WSL default resolves through the Windows user profile.

**Acceptance Scenarios**:

1. **Given** an explicit configuration directory, **When** the helper runs, **Then** it updates only that directory.
2. **Given** WSL with Windows profile tools available, **When** no override is supplied, **Then** the helper resolves the Windows Wave configuration directory.

### Edge Cases

- Malformed settings are reported and preserved rather than overwritten.
- Existing false values are preserved just as existing true values are.
- Missing Python causes an explicit skip rather than a partial write.

## Requirements

### Functional Requirements

- **FR-001**: The helper MUST be opt-in.
- **FR-002**: The helper MUST preserve existing settings and unrelated keys.
- **FR-003**: The helper MUST add documented values only when their keys are absent.
- **FR-004**: The helper MUST use an atomic replacement for settings updates.
- **FR-005**: The helper MUST preserve the existing settings file mode.
- **FR-006**: The helper MUST accept an explicit configuration directory.
- **FR-007**: Tests MUST run without reading or modifying the user's actual Wave settings.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Existing fixture keys retain 100% of their original values after the helper runs.
- **SC-002**: A fresh fixture receives exactly the documented default keys.
- **SC-003**: All settings tests complete without accessing the real user configuration directory.
- **SC-004**: Malformed input produces zero replacement writes.

## Assumptions

- Wave continues to store user settings in a JSON object named `settings.json`.
- Python 3 is available on configured workBenches workstations.
- The helper supplements diagnosis and is not proof that an application-level clipboard bug is fixed.
