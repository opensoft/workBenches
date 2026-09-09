## ADDED Requirements

### Requirement: Strict orphan classification
The watchdog SHALL classify a process as a strict orphan relay only when its process name is exactly `Relay`, its parent PID is 1, its command line is exactly the single argument `/init`, the aggregated kernel child lists for every relay thread are empty, and its age meets the configured minimum.

#### Scenario: Plain childless relay qualifies
- **WHEN** a process satisfies every strict predicate field and meets the minimum age
- **THEN** the watchdog records it as a strict orphan candidate

#### Scenario: Named relay is preserved
- **WHEN** a process name is `Relay(<pid>)` or any value other than exactly `Relay`
- **THEN** the watchdog excludes it from candidate and signal sets

#### Scenario: SessionLeader is preserved
- **WHEN** a process name is `SessionLeader`
- **THEN** the watchdog excludes it from candidate and signal sets regardless of age or parent

#### Scenario: Relay with a child is preserved
- **WHEN** an otherwise matching relay has at least one current child process owned by any of its threads
- **THEN** the watchdog excludes it from candidate and signal sets

#### Scenario: Ambiguous metadata fails closed
- **WHEN** any required procfs value is missing, malformed, unreadable, truncated, or contradictory
- **THEN** the watchdog excludes the process and records a non-fatal inspection error

### Requirement: Consecutive identity confirmation
The watchdog SHALL require the same PID and procfs start-time ticks to satisfy the complete predicate in at least three consecutive scans before cleanup eligibility.

#### Scenario: Candidate remains strict across scans
- **WHEN** the same identity satisfies the predicate for the configured consecutive scans
- **THEN** the watchdog marks that identity eligible

#### Scenario: Predicate becomes false
- **WHEN** a candidate fails any predicate during confirmation
- **THEN** the watchdog discards its observation count

#### Scenario: PID is reused
- **WHEN** a PID reappears with different start-time ticks
- **THEN** it receives no inherited observations

### Requirement: Revalidated pidfd signal sequence
The watchdog SHALL open a pidfd, revalidate identity and the complete predicate before every signal, send `TERM` before `KILL`, and preserve a process whenever revalidation fails.

#### Scenario: Candidate exits after TERM
- **WHEN** a revalidated candidate exits during the TERM grace period
- **THEN** the watchdog records it resolved and sends no KILL

#### Scenario: Candidate survives TERM
- **WHEN** a candidate survives TERM and passes a second full revalidation
- **THEN** the watchdog sends KILL through the same pidfd

#### Scenario: Identity or predicate changes
- **WHEN** identity or any predicate changes before TERM or KILL
- **THEN** no further signal is sent

### Requirement: Bounded cleanup cycles
The watchdog SHALL process no more than the configured limit per cycle, oldest first, and SHALL reject invalid limits.

#### Scenario: Backlog exceeds limit
- **WHEN** confirmed candidates exceed the limit
- **THEN** only the oldest limited set is processed

#### Scenario: Limit is invalid
- **WHEN** the limit is missing, zero, negative, non-numeric, or excessive
- **THEN** active mode is refused without signals

### Requirement: Singleton root watchdog
The installed watchdog SHALL run as root, allow one daemon instance, and operate without systemd.

#### Scenario: Distro starts
- **WHEN** WSL executes the managed boot command
- **THEN** one detached root daemon begins scanning without blocking startup

#### Scenario: Duplicate launch
- **WHEN** another daemon starts while the lock is held
- **THEN** it exits without scanning or signaling

#### Scenario: Systemd remains disabled
- **WHEN** the watchdog is installed or runs
- **THEN** it does not change systemd or invoke WSL shutdown or restart

### Requirement: Safe modes and reporting
The watchdog SHALL provide non-mutating scan and verified status commands, require explicit valid active configuration, and maintain bounded secret-free reporting.

#### Scenario: Scan runs
- **WHEN** scan mode is invoked
- **THEN** it reports strict and protected processes without signals

#### Scenario: Active setting is absent
- **WHEN** `ACTIVE=true` is absent
- **THEN** the daemon sends no signals and reports inactive mode

#### Scenario: Cycle completes
- **WHEN** a monitoring cycle finishes
- **THEN** atomic status and bounded logs report counts and decisions without environment values or unrelated command lines

### Requirement: Reversible non-destructive installation
The installer SHALL preserve unrelated WSL configuration, refuse unmanaged boot conflicts, refuse existing reserved files without matching recorded digests, use root-owned components, and roll back without stopping WSL.

#### Scenario: Compatible installation
- **WHEN** validation passes and no boot command conflicts
- **THEN** the installer backs up configuration, installs files, registers boot, and starts without WSL restart

#### Scenario: Boot command conflicts
- **WHEN** a non-watchdog boot command exists
- **THEN** installation makes no configuration change and reports the conflict

#### Scenario: A reserved install path is already occupied
- **WHEN** a first install finds an existing engine, command, boot-wrapper, or configuration file without managed install state
- **THEN** installation preserves the file, makes no managed-file change, and reports the conflict

#### Scenario: A managed file changed after installation
- **WHEN** an upgrade finds a reserved file whose digest differs from the recorded install state
- **THEN** installation preserves the changed file and refuses to overwrite it

#### Scenario: Uninstall runs
- **WHEN** uninstall is invoked
- **THEN** only the verified watchdog identity and watchdog-owned files and configuration are removed
