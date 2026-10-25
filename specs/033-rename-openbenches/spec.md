# Feature Specification: Rename workBenches to openBenches

**Feature Branch**: `033-rename-openbenches`

**Created**: 2026-10-24

**Status**: Approved for staged implementation

**Input**: User description: "Implement the staged plan to rename workBenches to openBenches while preserving existing workstations and dependent contracts."

## User Scenarios & Testing

### User Story 1 - Repository administrator completes a safe cutover (Priority: P1)

An administrator renames the repository after safeguards are merged, pauses affected release activity, updates direct consumers, and verifies that old and new GitHub entrypoints continue to work.

**Why this priority**: An uncoordinated slug change can interrupt fresh installs, bench CI, and release publication across multiple repositories.

**Independent Test**: Using repository and workflow fixtures plus the controlled cutover checklist, demonstrate the publisher's exact old/new allowlist, migrate the five bench checkout references without changing their checker commit, and validate old/new Git and release URLs.

**Acceptance Scenarios**:

1. **Given** the target name is available and dependent safeguards are green, **When** the administrator performs the approved cutover, **Then** `opensoft/openBenches` is canonical and `opensoft/workBenches` is not recreated.
2. **Given** an active release line, **When** it publishes during the transition, **Then** only the exact intended old or new repository identity passes the publication guard.
3. **Given** an old release or issue URL, **When** it is used after cutover, **Then** the documented redirect or compatibility path continues to resolve.

---

### User Story 2 - Existing workstation upgrades without losing identity or state (Priority: P2)

A user with an existing `workBenches` checkout, legacy environment, profiles, credentials, and installed commands upgrades without moving directories or merging configuration trees.

**Why this priority**: Existing workstations carry irreplaceable credentials, histories, sessions, and generated launchers.

**Independent Test**: In an isolated HOME with legacy checkout/configuration fixtures, run the upgrade and verify old commands, environment, checkout discovery, profile manifests, credential-sync singleton behavior, and file contents/modes remain valid.

**Acceptance Scenarios**:

1. **Given** only legacy roots and variables, **When** the upgraded tooling runs, **Then** legacy-root behavior continues without mandatory migration.
2. **Given** both configuration roots, **When** no explicit selection resolves the intended state, **Then** the tooling follows its documented selection or refuses without merging.
3. **Given** conflicting sensitive old/new values, **When** an affected operation starts, **Then** it refuses with an actionable conflict error.

---

### User Story 3 - New user installs through the canonical openBenches identity (Priority: P3)

A new user follows canonical instructions, clones to the new default directory, and uses new commands, environment names, and fresh configuration roots.

**Why this priority**: New installations should not need to learn the old identity once compatibility has been established.

**Independent Test**: In a clean disposable environment, run canonical bootstrap/setup and verify the new checkout default, command aliases, environment precedence, fresh roots, and profile discovery.

**Acceptance Scenarios**:

1. **Given** no existing checkout or configuration, **When** the user follows current instructions, **Then** installation selects `openBenches` and fresh `openbenches` roots.
2. **Given** either old or new command/environment forms, **When** equivalent operations run, **Then** they resolve the same implementation and selected state.

---

### Edge Cases

- Both old and new checkout directories exist, including one explicit root override.
- Both old and new configuration roots exist with different profiles or active credential-sync state.
- Old and new environment values are equal, differ safely, or conflict for credential/path/release settings.
- A legacy command name already belongs to an unrelated executable.
- A supported 1.5, 1.6, or 1.7 candidate requires an entrypoint or release asset that current automation still exposes.
- An old GHCR manifest or OCI label is encountered alongside newly built images.
- Native and WSL openProfiler discovery encounter different manifest roots.
- The repository is renamed while publication or protected QA is active; cutover must wait.
- The separate `openWorkBenches*` family is present and must not be confused with the renamed current product.

## Requirements

### Functional Requirements

- **FR-001**: The system SHALL make `opensoft/openBenches` the canonical repository identity only after the governed cutover gate passes.
- **FR-002**: The system SHALL preserve old GitHub and ordinary Git compatibility during migration and SHALL NOT recreate `opensoft/workBenches`.
- **FR-003**: Publication guards SHALL allow only the exact authorized old and new repository identities during the transition.
- **FR-004**: The five affected bench workflows SHALL update their checkout repository without changing their immutable checker commit.
- **FR-005**: Direct dependents SHALL migrate references and pins in consumer-first order using each repository's normal governance and release process.
- **FR-006**: New installations SHALL default to `openBenches`, `~/Projects/openBenches`, and fresh `openbenches` roots only after dependent compatibility is released.
- **FR-007**: Existing checkout basenames and legacy configuration roots SHALL remain valid without automatic relocation.
- **FR-008**: Environment consumers SHALL resolve `OPENBENCHES_*`, then established legacy names, then defaults; dangerous conflicting dual configuration SHALL fail explicitly.
- **FR-009**: New and old command/flag aliases SHALL reach one implementation and preserve foreign-command collision and ownership checks.
- **FR-010**: Tools forwarding, subprocess scrubbing, and launcher/handoff contracts SHALL support both environment forms during mixed-version operation.
- **FR-011**: Configuration consumers SHALL select one root per contract and SHALL NOT merge old/new credential or profile trees.
- **FR-012**: Credential synchronization SHALL retain one agent, lock, and lease root; explicit state migration requires a stopped and drained old agent.
- **FR-013**: openProfiler SHALL use deterministic new-first/legacy-fallback manifest discovery in native and WSL paths without duplicating profiles or changing manifest v1.
- **FR-014**: Existing GHCR repositories, old release manifests, schema-v1 identifiers, OCI label keys, Docker history, identity-provider configuration, secret metadata, and installer locks SHALL remain valid.
- **FR-015**: New source images MAY use the new standard OCI source URL; old images and release assets SHALL NOT be rewritten.
- **FR-016**: Historical releases, tags, archived records, issue references, and lane history SHALL NOT be rewritten for cosmetic renaming.
- **FR-017**: The separate `openWorkBenches*` extraction family and future architecture repository names SHALL require their own explicit naming decisions.
- **FR-018**: Legacy removal, GHCR namespace migration, credential rotation, and `openWorkBenches*` consolidation are outside this feature.
- **FR-019**: Non-legacy credential composition SHALL require `openbenches-config-root-v1` from selected workBenches and AI-Credentials tooling, pass the selected root and preflighted identity explicitly, and refuse before manifest writes when unsupported; legacy-default composition SHALL NOT require either capability.

### Key Entities

- **Product identity**: canonical and legacy repository, display, command, environment, and path names.
- **Checkout discovery**: explicit override, installed marker, new/old directory candidates, and ancestor fallback.
- **State root**: selected configuration/cache/data location with legacy, new, or ambiguous status.
- **Dependent contract**: a repository, workflow, mount, schema, pin, launcher, or artifact that consumes an identity.
- **Cutover gate**: evidence and approval required before administrative or release operations.
- **Compatibility window**: the period during which old and new aliases are tested and supported.

## Success Criteria

- **SC-001**: All planned old/new/both checkout and configuration-root cases pass without duplicated profiles or merged state.
- **SC-002**: Legacy upgrade fixtures preserve credential contents, file modes, history, sessions, and one credential-sync agent.
- **SC-003**: Every affected bench workflow and required repository/dependent check passes on the exact final head.
- **SC-004**: Fresh canonical installation and each supported historical frozen-install path pass in disposable environments.
- **SC-005**: Old GHCR manifests and new source artifacts pass digest/registry validation, while unapproved registries remain rejected.
- **SC-006**: No direct current reference to the old slug remains outside the approved compatibility/history allowlist after the dependent sweep.
- **SC-007**: The first `openBenches` release passes the full applicable release gate and protected QA before publication; old releases remain unchanged.

## Assumptions

- `openBenches` names only the current product/repository; the separate `openWorkBenches*` family is not consolidated by this feature.
- The target slug remains available and is rechecked immediately before cutover.
- An org owner/repository admin and the required dependent owners perform their respective administrative and release actions at the gated steps.
- Existing credentials and provider accounts are not rotated or rewritten for this feature.
- The initial implementation performs no forced checkout or runtime-state migration.
- A later explicit deprecation or artifact-namespace proposal is required before removing durable legacy interfaces.
