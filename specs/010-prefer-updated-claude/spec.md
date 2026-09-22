# Feature Specification: Prefer Updated Claude Code

**Feature Branch**: `010-prefer-updated-claude`
**Created**: 2026-09-22
**Status**: Draft
**Input**: Use the newest already-installed Claude Code version for every new workBenches profile launch without waiting for a network update.

## User Scenarios & Testing

### User Story 1 - Launch with the latest installed client (Priority: P1)

As a bench user, I want a newly started profile or lane to use the newest Claude Code client already installed for me, so a stale image copy does not hide newer models or features.

**Why this priority**: This is the failure observed after profile swaps.

**Independent Test**: Provide a stale default client and two installed user versions; start a profile and a lane and inspect which executable receives the launch.

**Acceptance Scenarios**:

1. **Given** an older default client and a newer installed user client, **When** I start a profile, **Then** the newer client runs.
2. **Given** multiple installed user clients, **When** I start a lane, **Then** the highest numeric version is passed to the lane launcher.
3. **Given** a new version installed after my previous session started, **When** I start another session, **Then** that new version is selected without modifying the running session.

### User Story 2 - Keep launch control and availability (Priority: P2)

As a bench operator, I want explicit client overrides and fallback behavior to remain reliable so I can pin a client or launch without a native install.

**Why this priority**: It protects existing operator workflows.

**Independent Test**: Start with an override, then with no valid user install; inspect the executable used in each case.

**Acceptance Scenarios**:

1. **Given** an explicit executable override, **When** I launch a profile, **Then** that executable is used even if a newer native one exists.
2. **Given** no valid installed user client, **When** I launch a profile, **Then** the default client is used.

### Edge Cases

- Non-executable, non-version, and directory entries are ignored.
- Version comparison is numeric, so `2.1.10` wins over `2.1.9` regardless of modification time.
- A missing or unreadable native versions directory does not prevent fallback.

## Requirements

### Functional Requirements

- **FR-001**: New profile and lane starts MUST select the highest valid installed user-client version when no explicit override is supplied.
- **FR-002**: An explicit client override MUST take precedence.
- **FR-003**: When no valid user-client version exists, existing default-client resolution MUST remain available.
- **FR-004**: Starting a session MUST NOT synchronously check the network for an update.
- **FR-005**: Selection MUST be repeated for each new launcher invocation; it MUST NOT alter running sessions.

## Success Criteria

### Measurable Outcomes

- **SC-001**: All executable-version ordering, override, and fallback acceptance cases pass in automated tests.
- **SC-002**: Every new launch selects the latest already-installed version without performing an update check.
- **SC-003**: Starting a profile remains usable when the update service or network is unavailable.

## Assumptions

- Native Claude Code installs versioned executables under the current user's standard installation directory.
- Acquisition of newer versions remains the native updater's responsibility.
- A profile's configured model is independent of the executable-selection policy.
