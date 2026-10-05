# claude-profile-binary-selection Specification

## Purpose
Defines which Claude Code executable profile and lane launches start: the copy the claude-current resolver verifies against npm's published version, updating the user-owned installation first and refusing a stale launch unless explicitly allowed; an operator-set CLAUDE_BIN pin, passed through untouched; and, where no resolver is installed, the newest installed native version with a notice that the launch was not verified.

## Requirements

### Requirement: Profile launches select the newest installed native Claude Code executable
The profile launcher SHALL select the highest numeric three-component version among executable native Claude Code files installed for the current user when `CLAUDE_BIN` is not an operator pin and the `claude-current` resolver is not installed.

#### Scenario: Native update is newer than image binary
- **WHEN** `claude-current` is not installed, the native versions directory contains an executable newer version, and `PATH` resolves an older image-managed `claude`
- **THEN** a new profile launch uses the newer native executable

#### Scenario: Multiple native versions exist
- **WHEN** `claude-current` is not installed and multiple executable native versions are present
- **THEN** the highest version is selected numerically, independent of file modification times

### Requirement: Selection preserves overrides and fallback
The profile launcher SHALL honor a nonempty `CLAUDE_BIN` that the operator set as a pin, and SHALL NOT resolve `claude` through `PATH` while the `claude-current` resolver is installed.

#### Scenario: Explicit binary override
- **WHEN** the operator sets `CLAUDE_BIN` to an executable
- **THEN** the launcher passes that value through to direct and lane starts without replacing it and without running the update check

#### Scenario: Inherited resolution is not a pin
- **WHEN** a launch inherits the `CLAUDE_BIN` value that an earlier launch exported from its own resolution
- **THEN** the launcher resolves the executable again instead of reusing that value

#### Scenario: Two installs compete on PATH
- **WHEN** `PATH` resolves the image's copy first and the user's npm copy is the one whose version equals npm's published version
- **THEN** the launcher starts the user's copy by its absolute path

#### Scenario: No usable native version
- **WHEN** `claude-current` is not installed and the native versions directory is absent or has no valid executable version
- **THEN** the launcher resolves `claude` using its prior PATH-first fallback
- **AND** it prints one notice that the launch was not verified against npm, naming the command that installs the resolver

### Requirement: Every launch runs the update check before starting a session
The profile launcher SHALL obtain the executable from `claude-current` before it starts a session whenever `CLAUDE_BIN` is not an operator pin and the resolver is installed, and SHALL start exactly the absolute path the resolver returns.

#### Scenario: New session launch
- **WHEN** a user starts a profile or lane session while an installed candidate's `--version` equals npm's published version
- **THEN** the launcher runs the resolver's bounded check of npm's published version before the session starts
- **AND** the session starts on that candidate's absolute path, the one the resolver returned

#### Scenario: Installed copies are behind
- **WHEN** every installed candidate is older than npm's published version
- **THEN** the user-writable installation is updated to the published version under a lock before the session starts
- **AND** the session starts on the updated path

#### Scenario: An installed copy is ahead of npm
- **WHEN** no installed candidate equals npm's published version and one is newer
- **THEN** the session starts on the newer candidate and the launch says it is ahead of npm

#### Scenario: npm is unreachable
- **WHEN** npm's published version cannot be read within the bounded timeout
- **THEN** the session starts on the highest installed version and the launch prints `UNVERIFIED: could not reach npm`

#### Scenario: The launch says what launched
- **WHEN** a launch the resolver answered starts, whether verified, ahead, unverified or stale
- **THEN** it prints the version it started and how that compares with npm, as `claude <version> (verified against npm <published>)` when they are equal
- **AND** it hands `lane-start` the same path as `CLAUDE_BIN`, with `CLAUDE_VERIFIED_VERSION` set to the version the resolver read from it

### Requirement: A stale launch is refused with one escape
The profile launcher SHALL refuse to start a session when no installed candidate is at or above npm's published version after the update attempt, unless `CLAUDE_ALLOW_STALE=1` is set.

#### Scenario: Update fails and nothing is current
- **WHEN** every candidate is still behind npm's published version after the update attempt
- **THEN** the launcher exits unsuccessfully, printing the installed and published versions and the one command that fixes it

#### Scenario: The operator accepts a stale launch
- **WHEN** the same condition holds and `CLAUDE_ALLOW_STALE=1` is set
- **THEN** the launcher starts the highest installed version and says that it is stale
