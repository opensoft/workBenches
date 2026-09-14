## Purpose

Distribute the project command from its authoritative repository while preserving
existing workBenches entrypoints for creating projects.

## ADDED Requirements

### Requirement: Verified installation
The installer SHALL verify commit identity and SHA-256 before replacing project.

#### Scenario: Corrupt download
- **WHEN** downloaded bytes differ from the pin
- **THEN** the installer refuses and preserves the installed executable.

#### Scenario: Existing unowned command
- **WHEN** the target contains a command not owned by this installer
- **THEN** automatic installation and uninstall preserve it unless replacement is explicitly requested.

#### Scenario: Command installation explicitly skips project
- **WHEN** project installation is skipped and no verified owned project exists
- **THEN** global installation omits both the project success count and the dependent onp wrapper.

#### Scenario: Installation status with a collision
- **WHEN** status encounters an unrelated or digest-tampered project command
- **THEN** it reports the command as unowned or tampered rather than installed.

#### Scenario: Concurrent install or removal
- **WHEN** project installation, replacement, removal, status, or execution overlap
- **THEN** a persistent per-directory lock serializes writers and protects readers from partial publication.

#### Scenario: Target changes during a guarded operation
- **WHEN** the executable or ownership marker changes after initial inspection
- **THEN** installation or removal refuses before overwriting or unlinking the changed target.

#### Scenario: Direct command execution
- **WHEN** a user invokes the PATH-facing project command directly
- **THEN** its verifier launcher executes only a separately stored payload whose ownership record and digest verify.

### Requirement: Legacy forwarding
onp and new-project.sh SHALL forward name and parent arguments to project new.

#### Scenario: Quoted parent
- **WHEN** the parent directory contains spaces
- **THEN** it reaches project new as one argument.

#### Scenario: Unowned executable collision
- **WHEN** a legacy entrypoint resolves an unrelated project executable
- **THEN** forwarding is refused unless the installer ownership marker and digest verify.

#### Scenario: Alternate install directory
- **WHEN** command installation selects a directory other than the user-local default
- **THEN** the legacy entrypoint verifies and executes project from that selected directory.

#### Scenario: Executable path changes after verification
- **WHEN** a project pathname is replaced while a legacy launch is being resolved
- **THEN** the launcher executes only the verified byte snapshot while holding a shared project lock.
