# claude-session-restart-notice Specification

## Purpose
Tell a running Claude Code session, at its next status line render, that the
executable it was started from has been replaced or superseded on disk.

## Requirements

### Requirement: A running session is told when its binary moved
The shared Claude status line SHALL print one green line, `RESTART NEEDED: running <old>, installed <new>; /ctx at your next breakpoint`, at the top of its panel whenever the restart check can read the process it renders for, and that process was started from an executable since replaced on disk or runs an older version than the one installed.

#### Scenario: The binary was replaced under a running session
- **WHEN** a launch's update or the CLI's auto-updater replaces the executable a running session started from
- **THEN** that session's next status line render shows the restart line naming both versions

#### Scenario: A current session
- **WHEN** the running executable is still on disk and no newer version is installed
- **THEN** the status line shows no restart line

### Requirement: The restart notice never acts
The status line SHALL only display the restart notice, and SHALL NOT stop, restart or clear the session it renders for.

#### Scenario: A working session sees the notice
- **WHEN** the restart line is shown
- **THEN** the session keeps running until its operator restarts it

### Requirement: The restart notice degrades silently
The status line SHALL render its panel without a restart line, and without an error, when the restart check is not installed or cannot read the process table.

#### Scenario: Restart check not installed
- **WHEN** `claude-restart-check` is not on `PATH`
- **THEN** the panel renders exactly as it did before this change

#### Scenario: No process table
- **WHEN** the host has no `/proc`, for example macOS
- **THEN** the panel renders with no restart line
