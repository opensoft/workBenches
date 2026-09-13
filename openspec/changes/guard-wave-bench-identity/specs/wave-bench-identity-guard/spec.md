## ADDED Requirements

### Requirement: Wave widgets select the Brett Layer 3 account
Each shipped Wave bench widget SHALL pass `--user brett` to the shared bench
launcher.

#### Scenario: Widget starts a personal bench
- **WHEN** Brett opens any shipped Wave bench widget
- **THEN** the launcher SHALL select that bench's `:brett` Layer 3 image.

### Requirement: Existing containers are identity-checked before startup
The shared Wave launcher MUST verify that an existing named container resolves
to the expected Layer 3 image for the selected user before it starts,
recreates, or bootstraps that container.

#### Scenario: Existing expected Layer 3 container
- **WHEN** a stopped container uses the expected `:brett` Layer 3 image
- **THEN** the launcher SHALL continue with its normal startup path.

#### Scenario: Existing foreign container name collision
- **WHEN** a container uses the requested bench name but a different image
- **THEN** the launcher SHALL exit non-zero without starting, removing,
  recreating, copying into, or executing inside that container.
