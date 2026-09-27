# Feature Specification: Sys Playwright Runtime

**Feature Branch**: `014-sys-playwright-runtime`

**Created**: 2026-09-27

**Status**: Ready

**Input**: User description: "Make the missing headless-browser system libraries a durable shared sys-bench capability and verify Chromium works."

## User Scenarios & Testing

### User Story 1 - Run browser-backed administration (Priority: P1)

As a sys-bench operator, I want Chromium and its runtime dependencies already present in the image, so browser-backed administration starts consistently on new and rebuilt workstations.

**Why this priority**: Missing shared libraries prevent the browser from starting at all.

**Independent Test**: Launch the image-provided Chromium headlessly in a disposable sys-derived image and verify successful HTML output.

**Acceptance Scenarios**:

1. **Given** a refreshed sys image, **When** Chromium starts headlessly, **Then** it exits successfully without a missing-library error.
2. **Given** a missing required library, **When** the shared image is built, **Then** the build fails before publishing an incomplete image.

### User Story 2 - Share one browser installation (Priority: P1)

As a bench maintainer, I want derived sys benches to inherit one pinned browser installation, so users do not maintain incompatible per-profile downloads.

**Why this priority**: A single image-owned runtime makes workstation setup repeatable and auditable.

**Independent Test**: Inspect a derived image and verify its browser path resolves from the shared cache without a user-home download.

**Acceptance Scenarios**:

1. **Given** two sys-derived images, **When** each resolves Chromium, **Then** both inherit the same pinned shared browser location.

### Edge Cases

- A browser build with an unresolved indirect library fails even when the executable file exists.
- An active container remains on its existing image after new images are built.
- Browser provisioning adds no saved login state or provider credentials.

## Requirements

### Functional Requirements

- **FR-001**: The shared sys image MUST include a pinned Chromium runtime.
- **FR-002**: The browser installation MUST be usable by non-root derived-bench users.
- **FR-003**: The build MUST install the browser's supported Linux dependency set.
- **FR-004**: The build MUST fail when any Chromium shared library is unresolved.
- **FR-005**: The sys Playwright version MUST remain aligned with the repository's developer-bench Playwright version.
- **FR-006**: Building images MUST remain separate from recreating active containers.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Chromium reports zero unresolved shared libraries in shared and derived image checks.
- **SC-002**: A disposable derived image completes one headless browser launch successfully.
- **SC-003**: All sys-derived images resolve the same pinned image-owned browser cache.
- **SC-004**: Zero active containers are restarted or recreated during source and image verification.

## Assumptions

- Chromium is the browser required by current browser-backed sys tools.
- Developer and system bench images should use the same Playwright release unless an explicit compatibility exception is documented.
- Live container activation remains a separate operational decision.
