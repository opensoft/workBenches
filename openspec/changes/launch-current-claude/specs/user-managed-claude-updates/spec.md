## Purpose

Provide each personalized bench image with a Claude Code installation at npm
latest that its runtime user owns, on top of the shared image baseline.

## ADDED Requirements

### Requirement: Layer 3 provides a user-owned Claude Code installation at npm latest
The Layer 3 image SHALL install Claude Code, at the version npm publishes as `latest` when the image is built, into an npm prefix owned by its runtime user, and SHALL resolve `claude` from that prefix before any system-wide copy.

#### Scenario: Runtime user resolves the writable Claude Code copy
- **WHEN** a user starts a shell in a Layer 3 bench image
- **THEN** `command -v claude` resolves under that user's npm global prefix
- **AND** `claude --version` reports the version the build resolved

#### Scenario: The build takes npm latest, not the base version
- **WHEN** npm publishes a newer Claude Code than the copy the base image carries
- **THEN** the user copy is installed at npm's version while the base copy keeps its own

#### Scenario: A direct caller names the version
- **WHEN** the Layer 3 build is given an exact Claude Code version
- **THEN** that version is installed instead of npm latest

#### Scenario: npm latest cannot be read
- **WHEN** no exact version is given and npm's published version cannot be read within the build's bounded timeout
- **THEN** the build exits unsuccessfully and names the failed version lookup

### Requirement: The Layer 3 install verifies a runnable launcher
The Layer 3 build SHALL fail unless the installed user copy's `claude --version` reports the resolved version, and SHALL run the package's own install hook when npm's install-script policy skipped it.

#### Scenario: npm skips the package hook
- **WHEN** npm installs the package without running its native-binary hook
- **THEN** the build runs that hook itself and then requires `claude --version` to report the resolved version

### Requirement: The shared Claude Code baseline remains in place and root-owned
The Layer 3 image SHALL NOT remove the Claude Code installation inherited from the shared base image, nor change its ownership or permissions.

#### Scenario: Updating the user copy does not write the shared prefix
- **WHEN** the runtime user, or a launch acting for it, updates the resolved Claude Code installation
- **THEN** npm writes only within the user's npm global prefix

#### Scenario: The base copy stays the floor
- **WHEN** a Layer 3 image is inspected
- **THEN** the base image's Claude Code installation is still present, root-owned and runnable
