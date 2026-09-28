## ADDED Requirements

### Requirement: Profile launcher selects the supported Codex executable
The Codex profile launcher SHALL honor an explicit `CODEX_BIN`; otherwise it
SHALL prefer the installer-managed `$HOME/.local/bin/codex` executable, then
the executable in the mounted standalone package cache, before falling back to
a command resolved from `PATH`.

#### Scenario: Explicit binary override
- **WHEN** a caller supplies an executable through `CODEX_BIN`
- **THEN** the profile launcher invokes that exact executable

#### Scenario: Standalone executable is installed
- **WHEN** `CODEX_BIN` is unset and `$HOME/.local/bin/codex` is executable
- **THEN** the profile launcher uses the standalone executable even when another `codex` appears earlier on `PATH`

#### Scenario: Standalone package is mounted in a bench
- **WHEN** `CODEX_BIN` and `$HOME/.local/bin/codex` are unavailable but the canonical standalone package contains its executable
- **THEN** the profile launcher uses the executable from the mounted standalone package

#### Scenario: Standalone executable is absent
- **WHEN** `CODEX_BIN` is unset and neither standalone executable path is available
- **THEN** the profile launcher falls back to the `codex` command resolved from `PATH`

### Requirement: Profile homes expose the canonical standalone package cache
Profile setup SHALL make the installer-managed standalone package cache visible
at `packages/standalone` below each profile-specific `CODEX_HOME` without
copying credentials or package payloads.

#### Scenario: Canonical cache exists
- **WHEN** profile setup runs and `$HOME/.codex/packages/standalone` exists
- **THEN** every manifest-backed profile exposes that canonical cache through its own `packages/standalone` path

#### Scenario: Canonical cache is absent
- **WHEN** profile setup runs before the standalone package cache is installed
- **THEN** profile creation succeeds without inventing or copying a package cache

#### Scenario: Profile packages parent conflicts
- **WHEN** an existing profile has a non-directory or symbolic-link `packages` path
- **THEN** setup preserves that path and skips the standalone cache link

### Requirement: Runtime repair preserves profile data
The runtime repair SHALL NOT rewrite Codex credentials, sessions, history, or
the existing npm installation.

#### Scenario: Existing profile is repaired
- **WHEN** setup adds standalone runtime visibility to an existing profile
- **THEN** the profile's credentials, sessions, and history remain unchanged
