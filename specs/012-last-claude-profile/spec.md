# Feature Specification: Remember Last Claude Profile

**Feature Branch**: `012-last-claude-profile`

**Created**: 2026-09-26

**Status**: Draft

**Input**: User description: "Make pclaude alone use the last known profile without a lane; lclaude can use the last known profile with a lane."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Restart the last profile quickly (Priority: P1)

An operator who has already launched a Claude profile can type `pclaude` later and return to that profile without remembering or retyping its name. The launch remains profile-only and never selects a lane.

**Why this priority**: This is the requested daily workflow and removes the most frequent repeated input without changing lane state.

**Independent Test**: Launch one configured profile explicitly, stop it, run bare `pclaude`, and observe that the same canonical profile is selected without any lane lookup or lane process.

**Acceptance Scenarios**:

1. **Given** a valid profile was last launched explicitly, **When** the operator runs bare `pclaude`, **Then** that profile launches without lane resolution.
2. **Given** no profile has ever been remembered, **When** the operator runs bare `pclaude`, **Then** no Claude process starts and the command explains how to select a profile.
3. **Given** the remembered profile is no longer configured, **When** the operator runs bare `pclaude`, **Then** no Claude process starts and the stale profile name is reported.

---

### User Story 2 - Resume the last profile with lane support (Priority: P1)

An operator can type `lclaude` to use the same remembered profile while retaining the existing lane-aware behavior.

**Why this priority**: The two short commands must differ only in lane behavior; otherwise remembering the profile would create inconsistent or unsafe shortcuts.

**Independent Test**: After remembering a profile, run bare `lclaude` in a known lane window and observe that the remembered profile and normal lane resolution are both used.

**Acceptance Scenarios**:

1. **Given** a valid profile is remembered, **When** the operator runs bare `lclaude`, **Then** the profile launches through normal lane resolution.
2. **Given** a valid profile is remembered, **When** the operator supplies a different valid profile to either command, **Then** the explicit profile wins and becomes the new remembered profile.

---

### User Story 3 - Keep profile-only prompts unblocked (Priority: P1)

An operator using profile-only `pclaude` can submit prompts from any project directory without being blocked by the lane-name guard, while lane-aware sessions remain protected.

**Why this priority**: A remembered profile is not useful if the first prompt is refused by protection intended for a different launch mode.

**Independent Test**: Configure the same profile once, submit a prompt in profile-only mode and lane-aware mode, and verify that only the lane-aware process invokes blocking lane enforcement.

**Acceptance Scenarios**:

1. **Given** a profile-only `pclaude` process, **When** a prompt is submitted, **Then** the managed lane-name guard permits it without evaluating lane identity.
2. **Given** an `lclaude` or explicit-lane process, **When** a prompt is submitted, **Then** the existing lane-name guard continues to enforce lane identity.
3. **Given** a profile settings file with the old unconditional managed guard, **When** the profile runtime is configured, **Then** only that managed command is upgraded and foreign hooks remain intact.

### Edge Cases

- The remembered value was written using an alias rather than the canonical profile name.
- The remembered-state path is a symlink, directory, device, empty file, or multi-line file.
- The state directory exists but its permissions or ownership prevent an atomic update.
- A status or login command targets a profile different from the remembered run profile.
- A profile-only launch creates or reuses a tmux session and must carry its no-lane identity into the child process.
- A legacy managed hook shares one outer hook entry with unrelated commands and custom metadata.
- Multiple launchers update the same remembered profile near-simultaneously.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST remember the canonical profile name for every valid `run` launch after profile and runtime preflight succeeds.
- **FR-002**: The system MUST NOT change the remembered profile during list, login, status, invalid-profile, or failed-preflight operations.
- **FR-003**: Bare `pclaude` MUST launch the remembered profile with lane resolution and lane inheritance disabled.
- **FR-004**: Bare `lclaude` MUST launch the remembered profile through the existing lane-aware path.
- **FR-005**: An explicit valid profile MUST take precedence over remembered selection and MUST become the new remembered profile for subsequent runs.
- **FR-006**: A missing, stale, malformed, or unsafe remembered-profile record MUST stop the launch with a deterministic, actionable error.
- **FR-007**: Remembered-profile state MUST contain only one canonical profile name, be private to the owning user, and be replaced atomically.
- **FR-008**: Profile-only processes MUST expose a launch-mode identity that survives any tmux child handoff.
- **FR-009**: The managed lane-name guard MUST return success without lane evaluation in a profile-only process.
- **FR-010**: The managed lane-name guard MUST retain its existing blocking behavior in lane-aware and explicit-lane processes.
- **FR-011**: Runtime migration MUST replace the legacy unconditional managed guard without removing, duplicating, or changing unrelated hooks or their metadata.
- **FR-012**: Existing explicit actions, profile aliases, Claude arguments, permission flags, credentials, transcripts, and lane resolution precedence MUST remain compatible.

### Key Entities

- **Remembered profile record**: A user-scoped non-secret pointer containing one canonical configured profile name.
- **Launch mode**: Either profile-only or lane-aware; determines whether lane resolution and the lane-name guard apply.
- **Canonical profile**: The resolved profile identity used for its configuration directory regardless of the alias entered by the operator.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After one explicit valid profile launch, both bare commands select that same profile in 100% of automated launch scenarios.
- **SC-002**: Bare `pclaude` performs zero lane-selection or lane-start actions in all focused tests.
- **SC-003**: Bare `lclaude` retains all existing lane-resolution behavior in the complete focused lane suite.
- **SC-004**: Profile-only prompt submissions are never blocked by the managed lane-name guard, while every existing lane-aware guard scenario continues to pass.
- **SC-005**: Legacy hook migration preserves 100% of unrelated commands and custom metadata across grouped and standalone hook fixtures.
- **SC-006**: Missing, stale, and unsafe state scenarios fail before Claude starts and produce one actionable diagnostic each.

## Assumptions

- The last profile is scoped to the operating-system user and the selected Claude profile home, not to a repository, lane, terminal, or workstation fleet.
- A launch is considered accepted once profile resolution and runtime preflight succeed; an interactive process that later exits immediately can still be the remembered launch.
- Remembered-profile state is not a credential and is not synchronized to Key Vault.
- `pclaude` remains the profile-only command and `lclaude` remains the lane-aware command established by feature 011.
