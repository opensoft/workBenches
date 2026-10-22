# Eagle fleet execution

## Purpose

Route compatible GitHub jobs to Eagle during the hosted-runner billing block while retaining coverage, controls and isolation.

## ADDED Requirements

### Requirement: Complete and truthful routing

The system SHALL inventory active workflows across authorized repositories and route compatible hosted jobs to explicit Eagle selectors without a hosted fallback.

#### Scenario: Eagle is busy

- **WHEN** an eligible Linux job is queued while Eagle capacity is occupied
- **THEN** the job waits for compatible Eagle capacity instead of requesting a billed hosted runner.

#### Scenario: Native platform is unavailable

- **WHEN** a job requires Windows, macOS, ARM or unavailable hardware
- **THEN** its actual requirement remains visible and it is not mislabeled or omitted to produce a passing result.

### Requirement: Isolated compatible execution

The system SHALL provide disposable rootless execution with the tool, Docker action and service-container behavior required by migrated jobs, without host files, shared host daemon or host credentials.

#### Scenario: Package setup needs sudo

- **WHEN** a migrated Linux job installs packages
- **THEN** elevation is limited to its disposable user namespace and cannot elevate on Eagle.

#### Scenario: Container action needs workspace

- **WHEN** an action mounts the job workspace
- **THEN** that workspace belongs only to the private backend and is deleted after the job.

### Requirement: Preserve controls and assertions

The system SHALL preserve tests, platform matrix coverage, permissions, public-fork approval controls, deployment environments and release triggers.

#### Scenario: Protected publication

- **WHEN** a routed publishing job requires human environment approval
- **THEN** it receives no deployment execution or credentials before that approval.

### Requirement: Bounded capacity and verified cleanup

The system SHALL bound aggregate execution resources, preserve busy jobs on controller recovery, journal uncertain creations and verify cleanup before replenishment.

#### Scenario: Controller restart during work

- **WHEN** the controller restarts while a job is active
- **THEN** it preserves that job and reconciles exact resources before dispatching another worker.