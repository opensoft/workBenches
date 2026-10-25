## Purpose

Define `openBenches` as the canonical product identity without invalidating established command, environment, checkout, and documentation interfaces.

## ADDED Requirements

### Requirement: Canonical identity and legacy aliases

The product SHALL use `openBenches` as its canonical display/repository identity, `openbenches` for new lowercase resources, and `OPENBENCHES_*` for new environment aliases while retaining documented legacy aliases during the support window.

#### Scenario: Fresh installation

- **WHEN** a user performs a fresh installation after dependent compatibility is released
- **THEN** canonical instructions and defaults select `openBenches`, `~/Projects/openBenches`, and fresh `openbenches` roots.

#### Scenario: Existing command or flag

- **WHEN** a user invokes a legacy command or flag such as `setup-workbenches`, `workbenches-mcp-sync`, `--workbenches`, or `--workbenches-root`
- **THEN** it reaches the same implementation as its new alias without silently replacing an unrelated command.

### Requirement: Deterministic environment resolution

Environment consumers SHALL resolve the new name first, the legacy name second, and the documented default last, and SHALL reject dangerous conflicting dual configuration.

#### Scenario: Legacy-only environment

- **WHEN** only `WORKBENCHES_*` or an established `WB_*` value is present
- **THEN** existing behavior continues without requiring immediate operator edits.

#### Scenario: Conflicting sensitive values

- **WHEN** old and new variables specify different paths, endpoints, credential settings, or release configuration
- **THEN** the affected operation refuses with an actionable conflict error rather than guessing.

#### Scenario: Mixed-version handoff

- **WHEN** an updated launcher and an older or newer lane/handoff consumer interoperate
- **THEN** supported `OPENBENCHES_CLAUDE_*` and `WORKBENCHES_CLAUDE_*` forms resolve deterministically without losing the selected lane or directory.

### Requirement: Living and historical identity boundaries

Living documentation and private identifiers MAY adopt the new identity, while historical records and durable opaque identifiers SHALL retain their original meaning.

#### Scenario: Archived material

- **WHEN** archived specifications, old release notes, issue references, ratification records, or lane history contain `workBenches`
- **THEN** they are not rewritten merely to eliminate the old name.

#### Scenario: Separate product family

- **WHEN** documentation discusses `openWorkBenches*`
- **THEN** it remains distinguished as the separate extraction family and is not implicitly renamed or consolidated.
