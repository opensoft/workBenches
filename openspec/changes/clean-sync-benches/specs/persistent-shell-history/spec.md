# Spec Delta

## Purpose

Preserve shell command history across bench recreation without mounting a directory volume at a path expected to be a regular history file.

## ADDED Requirements

### Requirement: History file resides within the persistent history directory

Affected Compose services SHALL set the shell history file to `.workbenches-history/.zsh_history` in the configured user home and SHALL mount the existing named history volume at its containing directory, preserving the volume's name. The service startup SHALL initialize the mounted directory and existing history file for the runtime user before accepting interactive shells; this behavior SHALL work with plain Compose and Dev Container launches.

#### Scenario: Configuration is resolved for a bench

- **WHEN** an affected primary or example devcontainer configuration and its Compose service are resolved
- **THEN** the history volume target is the `.workbenches-history` directory
- **AND** `HISTFILE` points to `.zsh_history` inside that directory
- **AND** the existing named volume is retained

#### Scenario: Standalone Compose launch

- **WHEN** a service starts through plain Docker Compose with a fresh or root-owned history volume
- **THEN** startup makes the mounted directory and existing history file writable by its runtime user
- **AND** a history entry remains available after container recreation

### Requirement: Landing configuration does not interrupt running benches

The cleanup SHALL NOT stop, recreate, or restart running bench containers solely to commit and synchronize configuration.

#### Scenario: A bench is running during cleanup

- **WHEN** its validated configuration is committed and synchronized
- **THEN** its running container remains uninterrupted
- **AND** live activation is reported as separate from source synchronization
