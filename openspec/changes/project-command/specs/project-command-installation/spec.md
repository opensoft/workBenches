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

#### Scenario: Installation status with a collision
- **WHEN** status encounters an unrelated or digest-tampered project command
- **THEN** it reports the command as unowned or tampered rather than installed.

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
