## ADDED Requirements

### Requirement: Combined metadata-only report
workBenches MUST provide one command that accepts one or more authorized private registry roots and reports account and credential coverage grouped by normalized provider and owner.

#### Scenario: Combined owner report
- **WHEN** the command receives valid Opensoft and Brett registries
- **THEN** it prints deterministic provider/owner counts for total accounts, active accounts, credentials, configured escrow, and missing escrow

### Requirement: Duplicate detection
The combined validator MUST reject duplicate stable account IDs, duplicate credential IDs, duplicate profile keys within an owner registry, and conflicting provider definitions.

#### Scenario: Cross-owner identifier collision
- **WHEN** two owner registries declare the same account ID or credential ID
- **THEN** validation reports the identifier class and both owning registries without displaying credential data

### Requirement: Ownership consistency
The combined validator MUST verify that catalog owners, profile owners, account references, and credential references agree with each containing registry's declared owner.

#### Scenario: Mis-owned account
- **WHEN** a Brett registry account declares Opensoft ownership or an Opensoft profile references a Brett account
- **THEN** validation reports an ownership inconsistency and returns a failing result

### Requirement: Escrow coverage validation
The report MUST classify active credentials as configured for escrow or missing escrow using only the registry's approved non-secret custody metadata.

#### Scenario: Active credential lacks durable custody
- **WHEN** an active profile has no enabled company vault mapping or no available personal SOPS ciphertext reference
- **THEN** the report counts and identifies the credential as missing escrow

### Requirement: No secret access or output
The command MUST NOT decrypt ciphertext, retrieve Azure secret values, read provider credential payloads, or print token-like values.

#### Scenario: Report runs without secret authority
- **WHEN** the command runs with read access to only the private metadata repositories
- **THEN** it completes validation and reporting without Azure login, SOPS identity, or provider credentials

### Requirement: Machine-readable and human-readable output
The command MUST support a stable machine-readable result in addition to its default human-readable summary, with a strict mode that fails on validation errors or missing active escrow.

#### Scenario: Automation consumes report
- **WHEN** the command is run with machine-readable output and strict validation
- **THEN** it emits structured counts and findings and returns nonzero when any blocking finding exists
