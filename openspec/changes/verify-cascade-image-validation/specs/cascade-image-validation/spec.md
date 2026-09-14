## ADDED Requirements

### Requirement: Cascade-targeted image verification
The system SHALL verify every Layer 2 image selected by a cascade rebuild using
disposable, noninteractive command probes before reporting that the cascade
verification passed.

#### Scenario: All selected images satisfy the command contract
- **WHEN** a cascade rebuild produces Layer 2 images for one or more bench families
- **THEN** the verification result identifies every selected image and reports a passing probe for each required command

#### Scenario: A selected image is missing a required command
- **WHEN** a required command cannot be invoked in a selected Layer 2 image
- **THEN** the verification exits non-zero and identifies the image and command that failed

### Requirement: Safe Layer 3 activation reporting
The system SHALL inspect an existing personalized image only when requested and
SHALL NOT create, replace, stop, restart, or remove a running container while
performing the inspection.

#### Scenario: Personalized image is current
- **WHEN** the requested personalized image exists and is newer than its Layer 2 base
- **THEN** the verification reports it as current and includes its immutable image identifier

#### Scenario: Personalized image is absent or deferred
- **WHEN** the requested personalized image is missing or is configured by a running container
- **THEN** the verification reports the activation state without changing an image or container

### Requirement: Explicit manifest persistence
The system SHALL leave the source checkout unchanged during ordinary version
verification and SHALL write a version manifest only when explicitly requested.

#### Scenario: Ordinary verification
- **WHEN** version verification runs without a manifest-write option
- **THEN** no version manifest file is created or overwritten

#### Scenario: Requested manifest
- **WHEN** version verification runs with the manifest-write option
- **THEN** the manifest records each verified image reference and immutable image identifier
