## ADDED Requirements

### Requirement: Validate real host sources
The launcher SHALL validate existing stopped-container bind sources and known source types before preparation or recreation, without reading credential contents or silently creating a missing Claude configuration file.

#### Scenario: Missing or wrong-type source
- **WHEN** a required source is absent or a known file destination has a directory source
- **THEN** startup fails with a source-specific diagnostic before image preparation, container removal, or container start

### Requirement: Diagnose stale Docker Desktop mappings
The launcher SHALL distinguish a missing Docker Desktop WSL staged mount source from unrelated startup failures and SHALL offer explicit repair only when the real bind sources are valid.

#### Scenario: Valid real source and missing staged source
- **WHEN** a stopped managed container fails startup with the specific missing WSL staged-source OCI error
- **THEN** the launcher reports the stale-mapping recovery and preserves the original container

#### Scenario: Unrelated failure
- **WHEN** startup fails with an unrelated runtime error
- **THEN** its error and exit status remain visible and no stale-mount recovery is offered

### Requirement: Preserve explicit recovery boundaries
The launcher SHALL require explicit replacement consent, verify declared container ownership, preserve a stopped container that starts during removal, retain the declared lifecycle and persistent mounts, and perform at most one recreation per invocation.

#### Scenario: Explicit stopped-container repair
- **WHEN** the user invokes repair for a stopped managed container with valid sources
- **THEN** it is removed without force and recreated once through its declared lifecycle

#### Scenario: Concurrent start
- **WHEN** the stopped container starts while repair checks or non-force removal run
- **THEN** the live container is preserved instead of force-removed

#### Scenario: Failed repaired startup
- **WHEN** the recreated container encounters the same startup failure
- **THEN** the launcher stops with diagnostics instead of recreating again
