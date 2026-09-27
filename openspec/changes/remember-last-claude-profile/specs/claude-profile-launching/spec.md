# Spec Delta

## Purpose

Defines predictable profile selection and lane behavior for repeated Claude launches across workstations and bench environments.

## ADDED Requirements

### Requirement: Explicit runs remember the canonical profile
The launcher SHALL record the canonical profile name when a valid `run` action is accepted, including when the operator supplied an alias. Login, status, list, invalid-profile, and failed preflight actions MUST NOT replace the remembered profile.

#### Scenario: Explicit canonical profile is launched
- **WHEN** an operator runs `pclaude team-01a` and the profile passes launch preflight
- **THEN** `team-01a` becomes the remembered profile

#### Scenario: Profile alias is launched
- **WHEN** an operator runs a valid alias for a configured profile
- **THEN** the corresponding canonical profile name becomes the remembered profile

#### Scenario: Non-run action is used
- **WHEN** an operator lists profiles, checks status, or performs login
- **THEN** the remembered profile remains unchanged

### Requirement: Bare pclaude uses the remembered profile without a lane
The launcher SHALL make `pclaude` with no arguments run the remembered profile in profile-only mode. It MUST NOT resolve, select, start, or inherit a lane for that launch.

#### Scenario: Remembered profile exists
- **WHEN** an operator runs bare `pclaude` after a profile has been remembered
- **THEN** Claude launches under that profile without lane resolution

#### Scenario: No profile has been remembered
- **WHEN** an operator runs bare `pclaude` before any profile has been remembered
- **THEN** the command exits without launching Claude and explains how to select a profile

#### Scenario: Profile home has not been created
- **WHEN** an operator runs bare `pclaude` on a first-use installation whose profile home does not exist
- **THEN** the command reports missing remembered state without creating the profile home

#### Scenario: Remembered profile is stale
- **WHEN** the remembered name no longer resolves to a configured profile
- **THEN** the command exits without launching Claude and identifies the stale remembered profile

### Requirement: Bare lclaude uses the remembered profile with lane resolution
The launcher SHALL make `lclaude` with no arguments run the same remembered profile through the normal lane-aware resolution path. Explicit profile arguments MUST continue to override remembered selection for both commands.

#### Scenario: Bare lclaude has a remembered profile
- **WHEN** an operator runs bare `lclaude`
- **THEN** the remembered profile launches and normal lane resolution remains enabled

#### Scenario: Explicit lclaude profile is supplied
- **WHEN** an operator runs `lclaude team-02b`
- **THEN** `team-02b` launches with lane resolution and becomes the remembered profile

### Requirement: Profile-only launches cannot be blocked by the lane-name guard
The profile runtime SHALL preserve lane-name protection for lane-aware launches while making that guard return success for profile-only launches. Other user hooks and the advisory usage guard MUST remain unchanged.

#### Scenario: Profile-only prompt is submitted
- **WHEN** Claude runs through profile-only `pclaude`
- **THEN** the lane-name guard permits the prompt without consulting lane identity

#### Scenario: Lane-aware prompt is submitted
- **WHEN** Claude runs through `lclaude` or an explicit lane launch
- **THEN** the lane-name guard continues to enforce the configured lane identity

#### Scenario: Existing profile settings are upgraded
- **WHEN** a profile still contains the legacy unconditional lane-name guard command
- **THEN** the next profile runtime configuration replaces only that managed command and preserves unrelated hooks and metadata

### Requirement: Remembered-profile state is private and robust
The remembered-profile record SHALL contain only the canonical profile name, SHALL be readable only by the owning user, and SHALL be replaced atomically. An unsafe or malformed record MUST cause a deterministic error instead of being executed or silently ignored.

#### Scenario: State is recorded
- **WHEN** a valid profile run reaches launch
- **THEN** the state record contains one canonical profile name and is restricted to its owning user

#### Scenario: State path is unsafe
- **WHEN** the state path is a symbolic link, non-regular object, empty record, or multi-line record
- **THEN** the launcher exits with an error and does not launch Claude

#### Scenario: Previous writer terminated while holding the lock
- **WHEN** the private lock records a process that no longer exists
- **THEN** the next writer safely removes that unchanged stale lock and records the new canonical profile
