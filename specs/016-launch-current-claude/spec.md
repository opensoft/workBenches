# Feature Specification: Launch Only the Newest Published Claude Code

**Feature Branch**: `016-launch-current-claude`
**Created**: 2026-09-29
**Status**: Implemented, in review
**Input**: opensoft/workBenches#119. Every profile or lane launch runs the update check before it starts a session, starts the absolute path of the Claude Code copy whose version equals npm's published one, and says what it started; Layer 3 carries a user-owned copy at npm latest; a running session is told to restart when its binary moves.
**Governs it**: the OpenSpec change `launch-current-claude` (opensoft/workBenches#120), ratified by Brett Heap on 2026-09-29 and merged at `c2403eb`; this feature is that change's task 1.2.

## Clarifications

None are open. The rulings this feature implements are Brett Heap's, 2026-09-29, on #119:

- **Home** (comment 5891571111): the resolver, `lane-start`'s use of it and the restart check live in `opensoft/openRepoTools`. This repository keeps `claude-profile` calling that command, with the native ordering as the fallback when it is absent.
- **Point 1, the image install** (comment 5893687866): keep the base image install as the floor, and install Claude Code at npm latest in the user's own npm prefix at the per-user build.
- **Point 2** (comment 5893706470), verbatim: "for 2, we can run update on every start, this ensures we have the latest models".
- **Added scope** (comment 5891361098): a running session gets a green restart notice in the status line, and it only warns.
- **The CLI's auto-updater stays on** (comment 5891339280).

Held for the ratifier and **not in force**: R1 to R5 (RULING NEEDED on #119, comments 5894243795 and 5894338733). This feature implements the ratified text as it stands. In particular, a host with no `/proc` gets no restart line (the ratified "No process table" scenario), and the status line adds no version-only fallback.

## User Scenarios & Testing

### User Story 1 - Every new session starts on the newest published client (Priority: P1)

As a bench user, I want every profile or lane launch to start on the Claude Code version npm publishes, updating my own copy first when every copy is behind, so newer models appear without my checking versions.

**Why this priority**: This is the #119 failure: a lane ran 2.1.283 for 20+ hours, and its `/model` picker lacked Sonnet 5.5.

**Independent Test**: A stub resolver reports verified, ahead, unverified and stale outcomes. Inspect which absolute path starts, what the launch prints, and what `lane-start` is handed.

**Acceptance Scenarios**:

1. **Given** the resolver verifies a copy at npm's version while the image copy is first on `PATH`, **When** I start a session, **Then** that copy starts by its absolute path, and the launch prints `claude <version> (verified against npm <published>)`.
2. **Given** a lane launch, **When** it is handed to `lane-start`, **Then** `lane-start` receives the same path as `CLAUDE_BIN`, the `CLAUDE_RESOLVED_BIN` marker, and `CLAUDE_VERIFIED_VERSION` set to that version.
3. **Given** a copy newer than npm's, **When** I start a session, **Then** it starts, and the launch says it is ahead.
4. **Given** npm cannot be read, **When** I start a session, **Then** the highest installed copy starts, and the launch prints `UNVERIFIED: could not reach npm`.
5. **Given** every copy is still behind after the update attempt, **When** I start a session, **Then** the launch refuses, naming both versions and the fix. With `CLAUDE_ALLOW_STALE=1` it starts and says it is stale.

### User Story 2 - Pins, inherited choices and hosts without the resolver (Priority: P2)

As a bench operator, I want an explicit executable to stay mine, a choice the launcher made earlier never to be mistaken for mine, and a host without the resolver still to launch.

**Why this priority**: It keeps operator control and availability while the update check becomes mandatory.

**Independent Test**: Launch with a pin, with an inherited pair, with no resolver installed, and with commands that start no session. Read the resolver's call log.

**Acceptance Scenarios**:

1. **Given** an operator `CLAUDE_BIN`, **When** I launch, **Then** it starts verbatim, and the resolver is never asked.
2. **Given** a `CLAUDE_BIN` equal to `CLAUDE_RESOLVED_BIN`, inherited from a session an earlier launch started, **When** I launch, **Then** the launcher resolves again.
3. **Given** no `claude-current` installed, **When** I launch, **Then** the newest native version starts, else the first `claude` on `PATH`, with one notice that the launch is not verified against npm, naming `openRepoTools --install`.
4. **Given** a command that starts no session (`login`, `status`, `mcp`, `--version`), **When** I run it, **Then** it resolves offline and never waits on npm.

### User Story 3 - A running session is told to restart (Priority: P2)

As a bench user, I want a session whose binary was replaced on disk to tell me to restart, without anything interrupting it.

**Why this priority**: Updating the disk at one launch makes every other running session stale.

**Independent Test**: Render the panel with a stub restart check that prints a line, prints nothing, or is absent.

**Acceptance Scenarios**:

1. **Given** the check reports that the binary moved, **When** the status line renders, **Then** its first line is the check's green `RESTART NEEDED` line, and the four panel lines follow unchanged.
2. **Given** no check installed, or one that prints nothing, **When** the status line renders, **Then** the panel is byte-identical to before this feature.
3. **Given** the restart line is shown, **When** the session keeps working, **Then** nothing stops, restarts or clears it.

### User Story 4 - Layer 3 carries a user-owned copy at npm latest (Priority: P3)

As a bench user, I want a fresh personal image to already carry Claude Code at npm latest in my own npm prefix, so the launch-time update is usually a no-op.

**Why this priority**: It makes the common launch fast. The launch-time check alone already keeps sessions current.

**Independent Test**: Run `user-layer/build.sh` against mocked Docker, and run the Dockerfile's install step against fake npm, node and claude.

**Acceptance Scenarios**:

1. **Given** a Layer 3 build, **When** it runs, **Then** `claude` resolves under the user's npm prefix at npm latest, verified by `--version`, and the base image's copy stays in place, root-owned and runnable.
2. **Given** `--claude-version VERSION`, **When** the build runs, **Then** that version is installed, and npm is not asked.
3. **Given** npm's latest cannot be read, **When** the build runs, **Then** it fails and names the version lookup.

### Edge Cases

- The resolver answers outside its contract, with another exit status or no absolute executable path: the launch refuses and names what it got.
- A tmux server carries an earlier session's marker equal to an operator's pin: the pin is still honored.
- A launch from outside tmux: the parent only wraps tmux, and the child resolves, once.
- A refusal in a pane whose only command is the launcher keeps the pane, so its reason stays readable.
- The status line JSON has no `version` (an older Claude): the check is asked without `--running`.
- The host has no `/proc`: the check prints nothing, and the panel is unchanged.
- npm skips the package's native-binary hook at the Layer 3 build: the build runs it, then verifies the version.

## Requirements

### Functional Requirements

- **FR-001**: A profile or lane launch that starts a session MUST obtain the executable from `claude-current` when it is installed and `CLAUDE_BIN` is not an operator pin, and MUST start exactly the absolute path it returns.
- **FR-002**: The launcher MUST refuse a launch the resolver refuses as stale, and MUST report `Claude CLI not found.` when the resolver finds no candidate. `CLAUDE_ALLOW_STALE=1` reaches the resolver unchanged.
- **FR-003**: An operator `CLAUDE_BIN` MUST start verbatim, with no update check. A `CLAUDE_BIN` equal to `CLAUDE_RESOLVED_BIN` MUST be resolved again.
- **FR-004**: With no `claude-current`, the launcher MUST use the #109 native ordering, then the `PATH` lookup, and print one notice naming `openRepoTools --install`.
- **FR-005**: A launch MUST hand `lane-start` the path as `CLAUDE_BIN`, with `CLAUDE_RESOLVED_BIN` and, when the resolver gave one, `CLAUDE_VERIFIED_VERSION`. `CLAUDE_VERIFIED_VERSION` MUST NOT reach a running session.
- **FR-006**: A command that starts no session MUST resolve offline.
- **FR-007**: The executable MUST be resolved once per launch, by the process that starts Claude.
- **FR-008**: The status line MUST print `claude-restart-check`'s line first when it prints one, MUST pass it the JSON's running version and its parent's pid, and MUST render exactly as before when the check is absent or silent. It MUST NOT stop, restart or clear the session.
- **FR-009**: The Layer 3 build MUST install Claude Code at npm latest, or at an exact `--claude-version`, into the runtime user's npm prefix. It MUST run the package hook when npm skipped it, MUST verify `command -v claude` and `claude --version`, and MUST fail closed, naming the lookup, when the version cannot be read.
- **FR-010**: The Layer 3 build MUST NOT change the base image's Claude Code installation.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Every claude-profile, status line and Layer 3 suite passes locally, with exact counts recorded (#105: the claude-profile suites have no CI of their own).
- **SC-002**: Each resolution outcome and hand-off rule is shown to be tested by a mutant of the new code that fails its suite.
- **SC-003**: With the restart check absent or silent, the panel is byte-identical to `main`'s for the same input.

## Assumptions

- `opensoft/openRepoTools#134` ships `claude-current` and `claude-restart-check` to the contract this feature calls. Until it lands and `openRepoTools --install` places them, launches take the fallback with its notice, and the status line prints no restart line.
- `CLAUDE_VERIFIED_VERSION` is handed for every resolver outcome, which the ratified "The launch says what launched" scenario allows. It requires it for a verified launch and forbids it for no other.
- The Layer 3 build host can reach the npm registry, as the Codex overlay already requires.
