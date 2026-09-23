# Spec Delta

## Purpose

Defines separate commands for ordinary Claude profile sessions and lane-managed sessions so each launch follows the operator's chosen workflow.

## ADDED Requirements

### Requirement: Profile-only launch
`pclaude` SHALL launch a selected Claude profile without discovering, prompting for, taking, or recording a lane unless an explicit compatibility lane option is supplied.

#### Scenario: Plain profile launch in a lane window
- **WHEN** an operator runs `pclaude <profile>` inside a tmux window whose name matches an existing lane
- **THEN** the profile starts without calling lane selection or `lane-start`, and the session is not marked as holding that lane

#### Scenario: Plain profile launch with inherited lane input
- **WHEN** an operator runs `pclaude <profile>` with inherited lane variables from a parent session
- **THEN** the new session remains profile-only and does not claim the inherited lane

### Requirement: Lane-aware launch
`lclaude` SHALL launch the selected profile using the established lane resolution and handoff behavior, including explicit lane, current window, recorded window, and interactive picker precedence.

#### Scenario: Explicit lane
- **WHEN** an operator runs `lclaude --lane <lane> <profile>`
- **THEN** the selected profile is handed to `lane-start` for that lane

#### Scenario: Implicit lane
- **WHEN** an operator runs `lclaude <profile>` in a window with a resolvable lane
- **THEN** the existing lane resolution and restart behavior applies

#### Scenario: Tmux relaunch
- **WHEN** an interactive `lclaude` invocation creates or reuses a tmux session
- **THEN** the child invocation retains lane-aware mode and the selected Claude binary

### Requirement: Migration compatibility
Explicit `pclaude --lane <lane> <profile>` SHALL remain lane-aware during the transition, while bare `pclaude` SHALL not implicitly take a lane.

#### Scenario: Existing explicit caller
- **WHEN** an existing caller invokes `pclaude --lane <lane> <profile>`
- **THEN** it retains its lane-start handoff behavior

### Requirement: Lane restart command
Lane handoff and restart instructions SHALL name `lclaude` as the lane-aware command once it is installed, with a compatible fallback for installations that have not yet received it.

#### Scenario: Handoff restart
- **WHEN** a lane handoff prints a restart command on an installation with `lclaude`
- **THEN** that command uses `lclaude` and resumes the intended lane
