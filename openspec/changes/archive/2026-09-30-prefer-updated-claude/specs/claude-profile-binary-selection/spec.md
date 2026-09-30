## ADDED Requirements

### Requirement: Profile launches select the newest installed native Claude Code executable
The profile launcher SHALL select the highest numeric three-component version among executable native Claude Code files installed for the current user when `CLAUDE_BIN` is not set.

#### Scenario: Native update is newer than image binary
- **WHEN** the native versions directory contains an executable newer version and `PATH` resolves an older image-managed `claude`
- **THEN** a new profile launch uses the newer native executable

#### Scenario: Multiple native versions exist
- **WHEN** multiple executable native versions are present
- **THEN** the highest version is selected numerically, independent of file modification times

### Requirement: Selection preserves overrides and fallback
The profile launcher SHALL honor a nonempty explicit `CLAUDE_BIN` and SHALL use its prior PATH-based resolution when no valid native executable is found.

#### Scenario: Explicit binary override
- **WHEN** `CLAUDE_BIN` names an executable
- **THEN** the launcher passes that value through to direct and lane starts without replacing it

#### Scenario: No usable native version
- **WHEN** the native versions directory is absent or has no valid executable version
- **THEN** the launcher resolves `claude` using its existing PATH-first fallback

### Requirement: Startup does not wait for an update check
The profile launcher SHALL NOT run a synchronous network update command before starting a session.

#### Scenario: New session launch
- **WHEN** a user starts a profile session
- **THEN** binary selection uses only locally installed files and starts without an updater command
