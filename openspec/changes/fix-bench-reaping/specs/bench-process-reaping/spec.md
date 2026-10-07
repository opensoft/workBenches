# Spec Delta

## Purpose

Keep Wave Compose-created bench containers free of accumulated orphaned child processes while preserving user identity, persistent state and explicit replacement control.

## ADDED Requirements

### Requirement: Reap orphaned bench children

Wave Compose creation and repair SHALL enable runtime reaping of terminated orphaned child processes without requiring a personalized image rebuild.

#### Scenario: First creation
- **WHEN** Wave creates a bench using its Compose path
- **THEN** the resulting creation configuration enables runtime process reaping

#### Scenario: Explicit repair
- **WHEN** the user authorizes replacing py-bench and repeated interactive shell checks complete
- **THEN** orphaned prompt helpers are reaped and no zombies remain

### Requirement: Preserve lifecycle safety

Normal Wave launches MUST reuse an existing running container; process-reaping support MUST NOT authorize automatic replacement of live containers or changes to unrelated benches.

#### Scenario: Repeated starts
- **WHEN** a user launches the same running pyBench repeatedly without repair
- **THEN** the same container is used and its mounted persistent state is retained

#### Scenario: Scoped activation
- **WHEN** py-bench is explicitly repaired
- **THEN** cloud-bench and m365-bench retain their existing container identities and start times
