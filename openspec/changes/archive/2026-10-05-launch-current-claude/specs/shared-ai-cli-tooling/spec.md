## MODIFIED Requirements

### Requirement: Shared image owns the CLI baseline
The Layer 0 image build SHALL install supported shared AI CLIs into system-owned
locations without embedding provider credentials, and every required launcher's
runtime files SHALL remain resolvable by the non-root bench user.

#### Scenario: Bench inherits the baseline
- **WHEN** a Layer 2 or Layer 3 bench is built from the refreshed shared image
- **THEN** every required CLI command is present and runnable from the inherited image-managed installation, and in Layer 3 a user-owned copy of `claude` or `codex` may resolve first on `PATH`

#### Scenario: MiniMax launcher resolves its runtime
- **WHEN** the normal UID/GID 1000 bench user invokes `mcode --version` and `mcode-tools --version`
- **THEN** both commands resolve their versioned runtime from the shared MiniMax install tree and exit successfully

#### Scenario: Build has no provider credentials
- **WHEN** the shared image is inspected after construction
- **THEN** no provider login bundle or user profile is present in an image layer
