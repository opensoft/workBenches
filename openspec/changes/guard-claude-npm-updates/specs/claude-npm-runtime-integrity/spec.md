# Spec Delta

## Purpose

Keep user-owned Claude npm installations runnable after updates in every
workBench, without changing native installs or provider credentials.

## ADDED Requirements

### Requirement: Scoped runtime npm policy
Every personalized bench SHALL approve Claude's lifecycle script and include
optional dependencies while preserving other npm settings and approvals.
Explicit script-disabling overrides SHALL be reported as errors.

#### Scenario: Runtime npm update
- **WHEN** the user updates the global Claude package with npm 12
- **THEN** Claude's postinstall is approved without approving all packages

#### Scenario: Mounted home
- **WHEN** a Wave launch mounts a home over the image defaults
- **THEN** the effective runtime user's npm policy is configured idempotently

### Requirement: Local repair verifies the actual package
Repair SHALL run as the install owner, serialize its own mutations, and verify
the npm executable against the installed package version. Missing payloads or
wrong versions SHALL fail. Healthy native installations SHALL remain untouched.

#### Scenario: Placeholder despite success
- **WHEN** npm returned success but the installed executable is a placeholder
- **THEN** repair runs the installed package hook and accepts only the matching executable

#### Scenario: Missing optional native package
- **WHEN** the hook cannot produce the installed package's exact version
- **THEN** repair fails with a targeted reinstall instruction

#### Scenario: Native installation
- **WHEN** the selected Claude is native and no user npm Claude package exists
- **THEN** its version is checked without installing another copy

### Requirement: Build and live boundaries
Every shared Layer 3 build SHALL include the safeguard. Live repair SHALL NOT
replace containers, kill sessions, reset credentials, or claim an untested bench
as verified.

#### Scenario: Shared rebuild
- **WHEN** any bench's Layer 3 is built
- **THEN** its npm policy and exact installed Claude version are verified
