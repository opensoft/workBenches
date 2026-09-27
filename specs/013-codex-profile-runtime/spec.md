# Feature Specification: Codex Profile Runtime

**Feature Branch**: `013-codex-profile-runtime`

**Created**: 2026-09-27

**Status**: Ready

**Input**: User description: "Make the verified standalone Codex profile runtime repair durable, governed, committed, and pushed without disturbing credentials, sessions, containers, or the existing npm installation."

## User Scenarios & Testing

### User Story 1 - Launch a profile with the supported runtime (Priority: P1)

As a Codex profile user, I want a profile launch to use the supported standalone installation when it is available, so the CLI and its daemon package agree on one runtime.

**Why this priority**: A profile that selects an incompatible or incomplete runtime cannot reliably start or expose its session history.

**Independent Test**: Launch a fixture profile with both a path-resolved command and a standalone command present; verify the standalone command is selected unless an explicit override is supplied.

**Acceptance Scenarios**:

1. **Given** a standalone command is installed, **When** a profile starts without an explicit override, **Then** that standalone command is used.
2. **Given** an explicit executable override, **When** a profile starts, **Then** the override is used.
3. **Given** no standalone command, **When** a profile starts, **Then** the available command from the normal command path is used.
4. **Given** a bench mounts the canonical standalone package but not the host's local bin directory, **When** a profile starts, **Then** the executable inside the mounted package is used.

### User Story 2 - Expose the daemon package to every profile (Priority: P1)

As a Codex profile user, I want every isolated profile home to see the canonical standalone package cache, so app-server daemon startup does not depend on copying runtime packages into each account profile.

**Why this priority**: Every profile changes the runtime home, and therefore every profile needs the same package visibility contract.

**Independent Test**: Run profile setup against a temporary manifest and canonical package cache; verify each profile receives a link to the canonical cache without copying profile data.

**Acceptance Scenarios**:

1. **Given** the canonical cache exists, **When** profile setup runs, **Then** each manifest-backed profile exposes that cache below its own profile home.
2. **Given** the canonical cache does not exist, **When** setup runs, **Then** profile setup still succeeds without inventing package content.

### Edge Cases

- An explicit runtime override remains authoritative even when the standalone command exists.
- A profile with existing credentials, sessions, or history is not rewritten by runtime-link setup.
- A machine without the standalone package cache remains compatible with a command found on its normal path.
- An existing non-directory or symbolic-link `packages` path is preserved and the cache link is skipped.

## Requirements

### Functional Requirements

- **FR-001**: Profile launch MUST honor an explicit runtime executable selection.
- **FR-002**: Without an explicit selection, profile launch MUST prefer the supported standalone executable when available.
- **FR-003**: Profile launch MUST retain a normal-path fallback when the standalone executable is absent.
- **FR-004**: Profile setup MUST expose one canonical standalone package cache to every manifest-backed profile when that cache exists.
- **FR-005**: Profile setup MUST NOT copy or rewrite credentials, sessions, history, or package payloads.
- **FR-006**: The runtime behavior MUST have an isolated automated regression test.

## Success Criteria

### Measurable Outcomes

- **SC-001**: All tested binary-selection scenarios choose the expected executable on the first launch attempt.
- **SC-002**: Every manifest-backed fixture profile exposes exactly one canonical standalone package cache after setup.
- **SC-003**: The focused profile runtime test completes with zero credential, session, or history changes.
- **SC-004**: Existing installations without the standalone cache continue to create and launch profiles successfully.

## Assumptions

- The official standalone installer owns the canonical executable and package cache.
- Profiles remain isolated through their existing profile-specific runtime homes.
- Existing npm installations remain available as a fallback and are not removed by this feature.
