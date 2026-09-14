# Feature Specification: Cascade Image Validation

**Feature Branch**: `002-cascade-image-validation`

**Created**: 2026-09-10

**Status**: Draft

**Input**: User description: "Update the cascade rebuild verification so it proves the Layer 2/3 images that users consume."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Prove Rebuilt Bench Images (Priority: P1)

An operator who runs a cascade rebuild can see whether each rebuilt bench image
actually exposes the shared command contract.

**Why this priority**: A successful parent-image build is not sufficient proof
that the bench image users consume is usable.

**Independent Test**: Run verification against named disposable images with a
known required command and confirm each image has a distinct result.

**Acceptance Scenarios**:

1. **Given** a list of rebuilt bench images, **When** verification runs, **Then** it reports a command result for every image.
2. **Given** one bench image lacks a required command, **When** verification runs, **Then** it fails and names that image and command.

---

### User Story 2 - Preserve Live Activation Boundary (Priority: P2)

An operator can determine whether a personalized bench image needs activation
without the verification changing a running bench.

**Why this priority**: Image refresh and live-container replacement require
separate authorization.

**Independent Test**: Inspect a personalized image configured by a running
container and confirm the command returns a deferred state without Docker
mutation commands.

**Acceptance Scenarios**:

1. **Given** a running personalized bench, **When** Layer 3 inspection runs, **Then** it reports deferred activation and does not change the container.

---

### User Story 3 - Avoid Incidental Source Changes (Priority: P3)

An operator can run ordinary verification without a timestamped file changing
the source checkout.

**Why this priority**: Read-only evidence should not create unrelated version-control work.

**Independent Test**: Run verification without a manifest option and confirm no manifest write occurs.

**Acceptance Scenarios**:

1. **Given** no manifest-write option, **When** verification finishes, **Then** it does not create or overwrite a manifest.

### Edge Cases

- A cascade selects no downstream bench images for a family.
- A requested image is absent after a failed build.
- A Layer 3 image exists but predates its Layer 2 base.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST verify every image selected by a cascade rebuild.
- **FR-002**: The system MUST fail verification when a selected image lacks a required command.
- **FR-003**: The system MUST report an existing Layer 3 image's current, stale, missing, or deferred state without changing Docker state.
- **FR-004**: The system MUST persist a manifest only after the operator explicitly requests one.
- **FR-005**: Each persisted image record MUST identify both the image reference and immutable image identifier.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A cascade verification produces one result for 100% of its selected Layer 2 images.
- **SC-002**: A missing required command causes a non-zero verification outcome in the same run.
- **SC-003**: Layer 3 inspection performs zero image-build, container-stop, container-restart, or container-removal operations.
- **SC-004**: Ordinary verification produces zero tracked-file changes.

## Assumptions

- The existing shared command contract remains the source of required CLI names.
- A command presence/version probe validates image inheritance but does not validate provider authentication.
- Layer 3 activation remains an explicitly authorized, separate workflow.
