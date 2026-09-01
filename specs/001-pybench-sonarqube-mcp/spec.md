# Feature Specification: pyBench SonarQube MCP Routing

**Feature Branch**: `001-pybench-sonarqube-mcp`

**Created**: 2026-07-27

**Status**: Draft

**Input**: User description: "Make SonarQube MCP startup reliable inside py-bench with a runtime-specific route while preserving the shared host profile and private proxy boundary."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Use SonarQube MCP Inside py-bench (Priority: P1)

A developer starts Codex through the existing profile launcher inside py-bench
and can list and initialize the SonarQube MCP server without editing their shared
profile.

**Why this priority**: The current failure prevents the primary container-side
Codex workflow from using SonarQube MCP at all.

**Independent Test**: Start Codex through the profile launcher inside py-bench,
list MCP servers, and send an initialization request to the resolved SonarQube
endpoint. The server is usable when the listing shows the private container
route and initialization succeeds.

**Acceptance Scenarios**:

1. **Given** py-bench and the shared SonarQube services are running, **When** the developer lists MCP servers through the profile launcher, **Then** SonarQube resolves to the private shared-service route.
2. **Given** the private route is configured, **When** py-bench sends a valid MCP initialization request, **Then** the proxy returns a successful protocol response.
3. **Given** the runtime-specific setting is absent, **When** the profile launcher starts Codex, **Then** no SonarQube URL override is added.

---

### User Story 2 - Preserve Host and Proxy Security Boundaries (Priority: P2)

A developer can continue using the same profile from the host, and the
token-injecting proxy remains private to its existing boundary.

**Why this priority**: Fixing container reachability must not break host-side
Codex or broaden access to SonarQube credentials.

**Independent Test**: Inspect the shared profile and proxy publication after the
container route is enabled. The profile still uses its host loopback address,
the proxy is not published on all interfaces, and no credential appears in
launcher output or configuration arguments.

**Acceptance Scenarios**:

1. **Given** the py-bench route is active, **When** the shared host profile is inspected, **Then** its SonarQube MCP URL remains the host loopback route.
2. **Given** the container route is active, **When** proxy network exposure is inspected, **Then** the token-injecting listener is not published on all host interfaces.
3. **Given** Codex is launched through the profile launcher, **When** process arguments and output are inspected, **Then** no SonarQube token is exposed and unrelated MCP settings are unchanged.

---

### User Story 3 - Retain the Fix Through Container Lifecycle (Priority: P3)

A developer can restart or recreate py-bench through supported repository
tooling without manually reconnecting networks or patching configuration inside
the container.

**Why this priority**: A live-only repair would regress at the next normal
container lifecycle event.

**Independent Test**: Run the same DNS, initialization, and profile-launcher
checks before and after a restart and again after a source-driven recreation.

**Acceptance Scenarios**:

1. **Given** a working py-bench container, **When** it is restarted, **Then** the private route and launcher behavior remain functional.
2. **Given** the repository sources contain the fix, **When** py-bench is recreated using supported tooling, **Then** it automatically receives both required network attachments and the runtime-specific route.

### Edge Cases

- If the private shared-service network does not exist at startup, the supported
  initialization flow must create or verify it before py-bench is started.
- If the runtime-specific URL is empty or unset, the launcher must not emit a
  malformed or blank configuration override.
- If the URL contains characters requiring quoting, it must still be passed as
  one configuration value and never evaluated as shell input.
- If the shared profile contains multiple MCP servers, only the SonarQube URL may
  be replaced for the launched process.
- If the container is attached to the shared network more than once through
  repeated reconciliation, the operation must remain idempotent.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: py-bench MUST retain its existing default network attachment.
- **FR-002**: py-bench MUST also join the existing private shared-service network.
- **FR-003**: py-bench MUST receive a configurable runtime-specific SonarQube MCP URL whose default targets the existing private proxy service.
- **FR-004**: The profile launcher MUST translate a non-empty runtime-specific URL into exactly one launched-process configuration override for the SonarQube MCP server URL.
- **FR-005**: The profile launcher MUST add no SonarQube MCP URL override when the runtime-specific value is unset or empty.
- **FR-006**: The profile launcher MUST preserve the selected profile, authentication configuration, user-supplied Codex arguments, and unrelated MCP settings.
- **FR-007**: The shared host profile MUST remain unchanged and continue to contain its host loopback SonarQube MCP URL.
- **FR-008**: The solution MUST NOT publish the token-injecting proxy on all host interfaces, print SonarQube tokens, or place a token in launcher arguments.
- **FR-009**: Repository source MUST be the authority for both launcher behavior and py-bench runtime configuration; an installed-container-only patch is insufficient.
- **FR-010**: The solution MUST remain functional after both a container restart and a source-driven recreation.
- **FR-011**: Automated coverage MUST verify launcher override presence, absence, quoting, and preservation of user arguments.
- **FR-012**: Validation MUST verify private service-name resolution, a successful protocol-level MCP initialization, launched Codex MCP listing, unchanged host profile content, and lifecycle durability.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of protocol initialization checks from py-bench return a successful response before and after restart and recreation.
- **SC-002**: 100% of profile-launcher MCP listings inside py-bench show the private runtime route, while the shared host profile retains the host route.
- **SC-003**: All launcher and runtime-configuration regression tests pass with both the override-present and override-absent cases covered.
- **SC-004**: Zero SonarQube tokens appear in validation output, process configuration overrides, or changed repository files.
- **SC-005**: A standard restart and a supported recreation each require zero manual network or in-container configuration repairs.

## Assumptions

- The shared SonarQube MCP backend and proxy continue to be managed separately
  and already join the private shared-service network.
- The proxy's service name and MCP path are stable inputs supplied by the
  operator.
- The existing py-bench initialization flow runs before the runtime is created
  and can ensure the external network exists.
- The profile launcher remains the supported entry point for selecting a Codex
  account profile.
- Rebuilding layered images is acceptable when required to make the launcher
  durable for recreation paths that rely on image contents.
