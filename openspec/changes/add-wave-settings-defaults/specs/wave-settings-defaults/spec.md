## ADDED Requirements

### Requirement: Wave defaults are applied explicitly
The repository SHALL provide an opt-in command that applies documented Wave
Terminal defaults and SHALL NOT run that mutation implicitly during unrelated
setup or bench startup.

#### Scenario: Operator invokes the helper
- **WHEN** an operator explicitly runs the Wave settings helper
- **THEN** the helper evaluates and applies the documented missing defaults

### Requirement: Existing settings remain authoritative
The helper SHALL preserve every existing Wave setting value and unrelated key,
including an existing value that differs from the repository default.

#### Scenario: Existing preference differs
- **WHEN** a documented key already exists with a user-selected value
- **THEN** the helper leaves that value unchanged

#### Scenario: Unrelated settings exist
- **WHEN** the settings object contains unrelated keys
- **THEN** those keys and values remain present after the update

### Requirement: Settings updates are safe
The helper SHALL validate the JSON object, update through an atomic replacement,
and preserve the existing file mode.

#### Scenario: Settings JSON is malformed
- **WHEN** the current settings file cannot be parsed as a JSON object
- **THEN** the helper exits unsuccessfully without replacing the file

#### Scenario: Settings file is a symbolic link
- **WHEN** the settings path is a symbolic link
- **THEN** the helper exits unsuccessfully without replacing the link or its target

#### Scenario: Missing settings file
- **WHEN** the target directory has no settings file
- **THEN** the helper creates a valid settings object containing the documented defaults

#### Scenario: Settings change during the update
- **WHEN** the settings file identity, metadata, or contents change after validation and before replacement
- **THEN** the helper exits unsuccessfully and preserves the newer settings file
