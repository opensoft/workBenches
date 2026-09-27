# Feature Specification: Shared AI CLI Image Refresh

**Feature Branch**: `009-fix-ai-cli-packaging`

**Created**: 2026-09-22

**Status**: Draft

**Input**: User description: "Refresh AI CLI versions in workBench images; repair the MiniMax Code system installation and expose Grok on the shared bench PATH."

## User Scenarios & Testing

### User Story 1 - Use Current Shared AI CLIs (Priority: P1)

As a bench operator, I want a no-cache cascade to install the latest stable versions available from each supported AI CLI's normal upstream channel, so newly built benches start with current tools.

**Why this priority**: The shared image is the baseline for every bench, so stale common tooling affects all users.

**Independent Test**: Build the Layer 0 image without cache and inspect each supported CLI's version against its upstream stable channel at build time.

**Acceptance Scenarios**:

1. **Given** upstream stable AI CLI releases are available, **When** the no-cache cascade completes, **Then** the shared base reports the resolved release versions from that build.
2. **Given** the refreshed shared base, **When** a consuming Layer 2 or Layer 3 image starts, **Then** it exposes the same inherited AI CLI versions unless the bench explicitly overrides them.

### User Story 2 - Run MiniMax Code as the Bench User (Priority: P1)

As Brett, I want MiniMax Code to run from a personalized bench image under my normal UID 1000 account, so its versioned install can be used from Wave without a root-only path.

**Why this priority**: A launcher that cannot resolve its installed release is unusable even when its command exists on `PATH`.

**Independent Test**: Run `mcode --version` in a disposable refreshed image as UID/GID 1000.

**Acceptance Scenarios**:

1. **Given** a refreshed Layer 3 image running as `brett` UID/GID 1000, **When** `mcode --version` is invoked, **Then** it prints the installed version and exits successfully.
2. **Given** the MiniMax Code installer cannot create its stable launcher or release pointer, **When** Layer 0 is built, **Then** the build fails with an actionable missing or unrunnable CLI indication.

### User Story 3 - Resolve Grok in All Bench Shells (Priority: P1)

As a bench user, I want Grok to resolve without editing my shell profile, so it works in Wave shells and noninteractive scripts alike.

**Why this priority**: Grok is already installed in the shared image but currently depends on user startup-file edits that do not affect every process.

**Independent Test**: Start a noninteractive shell in a refreshed Layer 2 and Layer 3 image and run `command -v grok` and `grok --version`.

**Acceptance Scenarios**:

1. **Given** a refreshed Layer 2 or Layer 3 image, **When** a noninteractive command runs `grok --version`, **Then** the command resolves from the image's installed Grok binary directory and exits successfully.
2. **Given** a Wave terminal using an existing user profile, **When** Grok is invoked without manually changing `PATH`, **Then** the command is available.

### Edge Cases

- If the upstream installer fails to install a required CLI, the base image build reports failure instead of silently publishing an incomplete image.
- Existing user-specific shell profiles remain usable; the default image path works even when those profiles predate the image refresh.
- No provider credentials or login state are copied into the shared image.

## Requirements

### Functional Requirements

- **FR-001**: A no-cache shared image refresh MUST resolve the supported AI CLIs from their configured upstream stable channels.
- **FR-002**: MiniMax Code MUST use one shared install location whose release pointer and launchers resolve together.
- **FR-003**: The shared image MUST allow the personalized `brett` UID/GID 1000 user to run `mcode --version` successfully.
- **FR-004**: The required shared CLI contract MUST include MiniMax Code and fail the image build when its command is missing or not runnable.
- **FR-005**: The default bench command path MUST include the installed Grok binary directory for interactive and noninteractive processes.
- **FR-006**: Refreshed Layer 2 and Layer 3 images MUST inherit the refreshed shared CLI versions and resolve `mcode` and `grok`.
- **FR-007**: Shared images MUST NOT contain provider credentials or authenticated account profiles.
- **FR-008**: Rebuilding an image MUST remain distinct from activating it in an already-running bench container.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Every refreshed Layer 2 and personalized Layer 3 image resolves both `mcode` and `grok` successfully.
- **SC-002**: `mcode --version` succeeds under UID/GID 1000 in every refreshed Layer 3 image.
- **SC-003**: Each supported AI CLI in the refreshed shared image is at the latest stable version resolved by its configured upstream channel during that build.
- **SC-004**: Every active Wave bench replaced during the refresh reports the new Layer 3 image and can invoke `mcode` and `grok` as `brett`.
- **SC-005**: No provider credential or account profile is added to a rebuilt image.

## Assumptions

- The existing image-managed CLI installers are the source of truth for supported AI CLIs and their official stable channels.
- The personalized bench user is `brett` with UID/GID 1000.
- Layer 2 and Layer 3 images inherit the shared Layer 0 CLI baseline unless a bench explicitly overrides a tool.
- User-specific credentials remain mounted or stored outside image layers.
