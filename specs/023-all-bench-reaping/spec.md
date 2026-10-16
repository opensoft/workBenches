# Feature Specification: Process reaping across all benches

**Feature Branch**: `023-all-bench-reaping`

**Created**: 2026-10-07

**Status**: Approved for implementation

**Input**: User description: "add to all the benches"

## User Scenarios & Testing

### User Story 1 - Consistent bench startup (Priority: P1)

Brett can start any bench using its supported launcher without accumulating terminated orphan helpers.

**Why this priority**: The existing Wave-only fix leaves other launch paths exposed.

**Independent Test**: Check every canonical bench startup definition and confirm orphan reaping is enabled.

**Acceptance Scenarios**:

1. **Given** any of the fourteen supported benches, **When** its canonical startup is resolved, **Then** runtime process reaping is enabled.
2. **Given** Frappe worker profiles, **When** their bench-based services are resolved, **Then** they have the same protection.

### User Story 2 - Durable templates and safe rollout (Priority: P2)

New projects and test benches inherit the protection without interrupting existing work.

**Independent Test**: Verify tracked project templates and test definitions and compare live container identities before and after source edits.

**Acceptance Scenarios**:

1. **Given** a distributed project template, **When** its startup configuration is resolved, **Then** the consuming bench service enables reaping.
2. **Given** running benches, **When** these source changes are implemented, **Then** their container identities and start times remain unchanged.

### Edge Cases

- Optional Frappe workers are checked even when their profiles are not running.
- GPU/user-map overrides must inherit the canonical setting, not negate it.
- Unrelated database, Redis, reverse-proxy and application services are not altered.
- Existing containers do not acquire new creation settings through a restart.
- Some child repositories are setup clones rather than parent gitlinks.

## Requirements

### Functional Requirements

- **FR-001**: Every canonical bench startup MUST enable runtime orphan reaping.
- **FR-002**: Distributed bench templates, tracked workspace examples and test stacks MUST inherit the same setting.
- **FR-003**: The change MUST preserve existing commands, identities, image references and persistent mounts.
- **FR-004**: Source implementation MUST NOT replace or restart live containers without separate authorization.
- **FR-005**: Validation MUST detect a missing or disabled reaping setting and invalid startup definitions without exposing resolved secrets.
- **FR-006**: Child repositories MUST be published before parent pins advance to their implementation commits.

## Success Criteria

### Measurable Outcomes

- **SC-001**: All fourteen benches pass canonical configuration validation.
- **SC-002**: All tracked bench templates and test definitions in scope pass validation.
- **SC-003**: Zero existing live container identities or start times change without separate user authorization.
- **SC-004**: A regression removing or disabling reaping is rejected by automated checks.

## Assumptions

- Supported startup uses each bench's declared Compose definitions; the existing Wave override remains.
- The parent feature governs this cross-repository change and owns the single implementation task list. Child worktrees carry configuration-only implementation slices, not duplicate task systems.
- Image rebuilding and live activation are out of scope.
