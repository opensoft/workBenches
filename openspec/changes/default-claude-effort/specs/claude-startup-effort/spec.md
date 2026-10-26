## ADDED Requirements

### Requirement: Explicit conversation startup fallback

The shared profile launcher SHALL add `--effort xhigh` to conversation startup when no explicit CLI or environment effort is supplied, without rewriting profile effort or model settings.

#### Scenario: Default start and resume

- **WHEN** a profile conversation starts or resumes without an override
- **THEN** Claude receives exactly one xhigh fallback and the original arguments

#### Scenario: Print-mode inference

- **WHEN** a profile launches with `-p` or `--print` without an override
- **THEN** the fallback is added without turning print mode into interactive routing

### Requirement: Preserve explicit effort and utility behavior

The launcher SHALL preserve both effort CLI forms and nonempty inherited/profile effort environment values, and SHALL NOT add effort to non-conversation commands.

#### Scenario: CLI choice

- **WHEN** startup includes `--effort VALUE` or `--effort=VALUE` before standalone `--`
- **THEN** the launcher adds no effort fallback

#### Scenario: Environment choice

- **WHEN** inherited environment or profile settings env supplies nonempty `CLAUDE_CODE_EFFORT_LEVEL`
- **THEN** the launcher adds no effort fallback

#### Scenario: Utility command

- **WHEN** login, status, help, version, MCP, plugin, doctor, install, or update is invoked
- **THEN** the launcher adds no effort option

#### Scenario: Prompt boundary

- **WHEN** a prompt after standalone `--` contains `--effort`
- **THEN** the prompt is preserved and does not suppress the fallback
