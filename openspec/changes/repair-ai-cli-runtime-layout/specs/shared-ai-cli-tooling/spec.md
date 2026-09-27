## MODIFIED Requirements

### Requirement: Shared image owns the CLI baseline
The Layer 0 image build SHALL install supported shared AI CLIs into system-owned
locations without embedding provider credentials, and every required launcher's
runtime files SHALL remain resolvable by the non-root bench user.

#### Scenario: Bench inherits the baseline
- **WHEN** a Layer 2 or Layer 3 bench is built from the refreshed shared image
- **THEN** every required CLI command resolves from the inherited image-managed installation

#### Scenario: MiniMax launcher resolves its runtime
- **WHEN** the normal UID/GID 1000 bench user invokes `mcode --version` and `mcode-tools --version`
- **THEN** both commands resolve their versioned runtime from the shared MiniMax install tree and exit successfully

#### Scenario: Build has no provider credentials
- **WHEN** the shared image is inspected after construction
- **THEN** no provider login bundle or user profile is present in an image layer

### Requirement: Required and best-effort tools are distinguished
The image build SHALL fail when a required CLI command is absent or unrunnable
and SHALL report a non-critical preview or best-effort tool as skipped or failed
without misrepresenting it as installed.

#### Scenario: Required command is missing
- **WHEN** installation completes without one of the required CLI commands
- **THEN** the image build exits unsuccessfully and identifies the missing command

#### Scenario: Required MiniMax command is unrunnable
- **WHEN** `mcode` or `mcode-tools` exists but cannot resolve or execute its shared runtime
- **THEN** the image build exits unsuccessfully and identifies the affected command as unrunnable

#### Scenario: Preview tool is unavailable
- **WHEN** a preview or best-effort upstream installer fails
- **THEN** the build reports that status and continues only if the tool is outside the required command contract

### Requirement: Source and live activation remain separate
Merging or rebuilding the shared image SHALL NOT be represented as updating an
already-running bench container, and live recreation SHALL require separate
authorization.

#### Scenario: Refreshed image is built
- **WHEN** the no-cache shared image build succeeds
- **THEN** existing running benches remain untouched until a separately authorized managed recreation
