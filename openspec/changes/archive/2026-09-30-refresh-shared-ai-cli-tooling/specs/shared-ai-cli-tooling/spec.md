## ADDED Requirements

### Requirement: Shared image owns the CLI baseline
The Layer 0 image build SHALL install supported shared AI CLIs into system-owned
locations without embedding provider credentials.

#### Scenario: Bench inherits the baseline
- **WHEN** a Layer 2 or Layer 3 bench is built from the refreshed shared image
- **THEN** every required CLI command resolves from the inherited image-managed installation

#### Scenario: Build has no provider credentials
- **WHEN** the shared image is inspected after construction
- **THEN** no provider login bundle or user profile is present in an image layer

### Requirement: Native installation scripts are explicitly bounded
The installer SHALL allow package installation scripts only for the enumerated
packages that require them and SHALL avoid overwriting an existing ambiguous
command name.

#### Scenario: Required native package installs
- **WHEN** npm installs a CLI whose published package requires a post-install script
- **THEN** the package is included in the explicit allow list and its expected command is verified

#### Scenario: Cursor command does not collide
- **WHEN** Cursor CLI and another tool both publish a generic `agent` command
- **THEN** the shared image exposes Cursor as `cursor-agent` without replacing the existing `agent`

### Requirement: Required and best-effort tools are distinguished
The image build SHALL fail when a required CLI command is absent and SHALL
report a non-critical preview or best-effort tool as skipped or failed without
misrepresenting it as installed.

#### Scenario: Required command is missing
- **WHEN** installation completes without one of the required CLI commands
- **THEN** the image build exits unsuccessfully and identifies the missing command

#### Scenario: Preview tool is unavailable
- **WHEN** a preview or best-effort upstream installer fails
- **THEN** the build reports that status and continues only if the tool is outside the required command contract

### Requirement: Profile routing names the correct tool family
The account adapter SHALL recognize the documented Qwen, Kimi Code, and MiniMax
families and SHALL inspect the matching command and profile directory for each.

#### Scenario: Kimi profile is inspected
- **WHEN** the adapter evaluates a Kimi Code account
- **THEN** it checks the `kimi` command and the Kimi Code profile directory

#### Scenario: Qwen and MiniMax profiles are inspected
- **WHEN** the adapter evaluates Qwen or MiniMax accounts
- **THEN** it checks the documented command and profile directory for the selected family

### Requirement: Claude profile initialization preserves host boundaries
The Claude profile launcher SHALL initialize new profiles with the configured
Fable 5.1 default and SHALL NOT create the host native-install compatibility
link while running inside a container.

#### Scenario: New Claude profile is created
- **WHEN** a profile has no existing model selection
- **THEN** the launcher writes the Fable 5.1 model identifier as its default

#### Scenario: Launcher runs in a bench container
- **WHEN** the launcher detects the container filesystem marker
- **THEN** it leaves the host native Claude compatibility link unchanged

### Requirement: Source and live activation remain separate
Merging or rebuilding the shared image SHALL NOT be represented as updating an
already-running bench container.

#### Scenario: Refreshed image is built
- **WHEN** the no-cache shared image build succeeds
- **THEN** existing running benches remain untouched until a separately authorized managed recreation
