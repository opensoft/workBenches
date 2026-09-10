## Purpose

Distribute the project command from its authoritative repository while preserving
existing workBenches entrypoints for creating projects.

## ADDED Requirements

### Requirement: Verified installation
The installer SHALL verify commit identity and SHA-256 before replacing project.

#### Scenario: Corrupt download
- **WHEN** downloaded bytes differ from the pin
- **THEN** the installer refuses and preserves the installed executable.

### Requirement: Legacy forwarding
onp and new-project.sh SHALL forward name and parent arguments to project new.

#### Scenario: Quoted parent
- **WHEN** the parent directory contains spaces
- **THEN** it reaches project new as one argument.
