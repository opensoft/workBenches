## Purpose

Publish Claude's selected launch mode to hooks without changing settings shared by profile and lane sessions.

## ADDED Requirements

### Requirement: Publish no-lane mode to the Claude process

Every launch that starts Claude without a lane SHALL provide `CLAUDE_NO_LANE=1` to the process and its hooks, including direct execution, tmux relaunch and bare fallback after lane refusal.

#### Scenario: Profile launch in a lane window

- **WHEN** `pclaude <profile>` launches inside a lane-named window
- **THEN** Claude receives the marker and no inherited lane identity

#### Scenario: Interactive profile launch outside tmux

- **WHEN** a profile launch creates a tmux child
- **THEN** the child Claude process receives the same no-lane marker

### Requirement: Explicit launch options override inherited mode

An explicit lane request SHALL clear an inherited no-lane marker before lane handoff. Explicit `--no-lane` SHALL override explicit lane requests regardless of option order. Only the exact inherited marker `1` SHALL select no-lane mode.

#### Scenario: Enter a lane from a profile process

- **WHEN** `lclaude` or explicit `pclaude --lane` runs with inherited `CLAUDE_NO_LANE=1`
- **THEN** lane handoff receives no exemption marker

#### Scenario: Explicit opt-out wins

- **WHEN** the same invocation supplies both a lane request and `--no-lane`
- **THEN** Claude launches with the marker and no lane handoff
