## Purpose

Preserve existing workstation state and durable artifact contracts throughout the rename.

## ADDED Requirements

### Requirement: Existing checkout and state preservation

Upgrades SHALL NOT automatically move existing checkouts, credentials, sessions, persistent Docker state, or live agent state.

#### Scenario: Legacy workstation upgrade

- **WHEN** an existing workstation upgrades from a checkout named `workBenches` with legacy configuration and credentials
- **THEN** the same checkout and legacy roots remain usable and no credential tree is copied, merged, or deleted by the rename.

#### Scenario: Optional later checkout move

- **WHEN** an operator explicitly chooses to move a checkout after dependent discovery supports both names
- **THEN** the move follows park/fresh-clone and worktree-repair procedures and regenerates trusted path markers and launchers rather than blindly moving an active worktree layout.

### Requirement: Deterministic configuration-root selection

Consumers SHALL select one configuration/state root per contract and SHALL NOT merge old and new trees.

#### Scenario: Only one root exists

- **WHEN** only a legacy or only a new root exists
- **THEN** the consumer uses that root in legacy-root or new-root mode respectively.

#### Scenario: Both roots exist

- **WHEN** both roots exist and no explicit selection resolves the intended state
- **THEN** stateful startup either follows a documented deterministic selection or refuses with an actionable ambiguity error, without merging contents.

#### Scenario: Credential synchronization

- **WHEN** credential synchronization is installed or started during mixed-version operation
- **THEN** one agent, one lock, and one lease root remain authoritative; a later explicit state migration first stops and drains the old agent.

### Requirement: Durable artifact and identity preservation

Existing schema-v1 identifiers, published release assets, GHCR repositories, OCI label keys, Docker history volumes, identity-provider configuration, secret metadata, and installer ownership locks SHALL remain valid unless a separate versioned migration changes them.

#### Scenario: Old release resolution

- **WHEN** a user installs a supported historical release or resolves its shared-image manifest
- **THEN** old registry/digest and schema checks continue to work and unapproved registries remain rejected.

#### Scenario: New image publication

- **WHEN** a new source image is built after the repository rename
- **THEN** its standard OCI source may name `opensoft/openBenches`, while old images, labels, and release assets remain unchanged.

#### Scenario: Mixed-version installer operation

- **WHEN** old and new installers or commands coexist
- **THEN** they share each ownership lock and do not create independent payload, journal, credential-agent, or lease writers.
