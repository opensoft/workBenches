## ADDED Requirements

### Requirement: Probe WSL process creation with a deadline
The watchdog SHALL test process creation in the configured WSL distribution by
running a minimal guest command with a bounded timeout.

#### Scenario: Probe succeeds
- **WHEN** WSL starts the guest command and it exits successfully before the deadline
- **THEN** the watchdog records a healthy result and its measured latency

#### Scenario: Probe times out
- **WHEN** the watchdog-owned probe remains active past the deadline
- **THEN** the watchdog terminates only that probe and records the timeout outcome

### Requirement: Classify health from consecutive observations
The watchdog SHALL require the configured number of consecutive failed probes
before it reports the transport as stuck.

#### Scenario: One transient failure occurs
- **WHEN** a failed probe is followed by a successful probe before the threshold
- **THEN** the consecutive-failure count resets and health remains or returns healthy

#### Scenario: Failure threshold is reached
- **WHEN** consecutive failed probes reach the configured threshold
- **THEN** health transitions to stuck and one bounded evidence snapshot is created

### Requirement: Preserve unrelated WSL workloads
The watchdog MUST NOT restart WSL services, terminate or shut down a
distribution, or signal processes it did not create for its own bounded probe
and evidence operations.

#### Scenario: Transport is stuck
- **WHEN** the watchdog classifies the configured distribution as stuck
- **THEN** existing WSL sessions, containers, relays, and host processes remain untouched

### Requirement: Bound and sanitize diagnostic state
The watchdog SHALL atomically write current state, rotate its event log at a
fixed limit, and restrict evidence to bounded operational metadata.

#### Scenario: Event log reaches its limit
- **WHEN** the event log exceeds the configured maximum size
- **THEN** the watchdog rotates only its own bounded log files before appending new events

#### Scenario: Failure evidence is captured
- **WHEN** health changes to stuck
- **THEN** the evidence omits process environments and unrestricted command lines while recording diagnostic success or error fields

### Requirement: Installation is explicit and reversible
The installer SHALL create a limited per-user scheduled task only when invoked
with the install action and SHALL support status, start, stop, and uninstall
without requiring WSL lifecycle changes.

#### Scenario: Source is merely merged
- **WHEN** the repository change lands without an install action
- **THEN** no scheduled task or background watchdog is created

#### Scenario: User uninstalls the watchdog
- **WHEN** the uninstall action is invoked
- **THEN** only the named scheduled task and installed script are removed while diagnostic state is preserved
