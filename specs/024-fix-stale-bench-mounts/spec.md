# Feature Specification: Stale Bench Mount Recovery

**Feature Branch**: `024-fix-stale-bench-mounts`
**Created**: 2026-10-08
**Status**: Approved for implementation
**Input**: Implement the discussed durable shared-launcher fix, keeping recreation explicit.

## User Scenarios & Testing

### User Story 1 - Understand a failed start (Priority: P1)

A user opening a stopped bench sees whether the real host source is missing or Docker's stored mount mapping is unusable.

**Independent Test**: Simulate missing, wrong-type, and stale sources and inspect diagnostics and mutation logs.

**Acceptance Scenarios**:

1. Given a missing real credential file, startup refuses without creating an empty replacement or deleting the container.
2. Given valid real sources and a missing staged mapping, one startup attempt produces explicit repair guidance without replacement.
3. Given an unrelated runtime error, it is reported without misleading stale-mount guidance.

### User Story 2 - Repair safely when requested (Priority: P1)

A user explicitly requesting recreation retains persistent storage and the bench's declared startup configuration.

**Independent Test**: Exercise stopped repair, concurrent start, foreign ownership, repeated failure, and Dev Containers/Compose paths.

**Acceptance Scenarios**:

1. A stopped owned container is recreated once using non-force removal and the existing lifecycle.
2. A container that starts concurrently is not force-removed.
3. A foreign container or invalid host source is refused before replacement.

### Edge Cases

Broken source symlinks, valid symlinked files, wrong-type directories, unavailable Docker, start timeout, changed sources between checks, and a failed explicit repair.

## Requirements

### Functional Requirements

- **FR-001**: Validate stopped-container bind sources and known source types without reading their contents.
- **FR-002**: Refuse missing Claude configuration rather than silently creating an empty file.
- **FR-003**: Classify only the specific missing Docker Desktop staged-source startup failure.
- **FR-004**: Preserve normal reuse and all running containers unless live replacement was explicitly requested.
- **FR-005**: Verify declared ownership, use non-force stopped removal, retain lifecycle overlays, and recreate at most once per invocation.
- **FR-006**: Preserve unrelated startup errors and return failure after unsuccessful explicit repair.

## Success Criteria

### Measurable Outcomes

- **SC-001**: All missing/wrong-type credential fixtures fail before any preparation or destructive action.
- **SC-002**: All normal stale-mount fixtures retain their container and identify the explicit recovery action.
- **SC-003**: All concurrent-start and foreign-container fixtures preserve existing workloads.
- **SC-004**: Every explicit recovery fixture performs no more than one recreation and retains declared persistent storage.

## Assumptions

This is a shared launcher source change. The user separately approved opening and landing its tested PR after checks and review pass, not replacing a live bench or merging unrelated pending work. The Docker Desktop initiating defect remains unproven. Existing first-install credential bootstrap is a separate operation.
