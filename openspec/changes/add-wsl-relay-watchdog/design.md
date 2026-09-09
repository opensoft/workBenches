## Context

Wave can leave hundreds of root-owned processes with the narrow signature `Relay`, parent PID 1, exact `/init` command line, no children, and substantial age. Named `Relay(<pid>)` processes attached to live `SessionLeader` processes are valid and must remain untouched. Ubuntu 24.04 intentionally has `systemd=false`, and the root checkout contains unrelated work that this change must not overlap.

## Goals / Non-Goals

**Goals:**

- Prevent strict orphan relays from exhausting WSL session creation.
- Preserve every live, recent, named, child-bearing, or ambiguous relay.
- Run with root authority without enabling systemd or stopping WSL.
- Provide bounded logs, verified status, dry-run qualification, and reversible installation.

**Non-Goals:**

- Restarting or reconfiguring WSL itself.
- Editing Wave launchers or Docker bench lifecycle scripts.
- Killing generic `/init`, parent-PID-1, or name-matched processes.

## Decisions

### WSL boot watchdog

The installer adds a root-owned Python engine and wrappers under `/usr/local`. The existing `[boot]` section registers a short detached launcher, and `flock` prevents duplicate daemon instances. The installer preserves all settings, backs up `wsl.conf`, refuses unmanaged boot-command conflicts and occupied reserved paths, records digests for every managed file, starts immediately, and never restarts WSL.
Installer lifecycle operations also refuse a held singleton lock without
verifiable PID metadata, clear stale status before startup, and restore an
originally absent `wsl.conf` to absence on uninstall.
Immediately before each signal, the cleanup engine reads only the target
process and all of its task children instead of relying on a cached full-table
scan. Replacement startup waits for both verified process exit and singleton
lock release after TERM or KILL.
Procfs names and command lines are validated as raw bytes with their exact
newline and NUL delimiters, and stale identity metadata is never discarded
while the singleton lock is held.

Systemd was rejected because it is intentionally disabled and would require a WSL restart. Windows polling was rejected because it would repeatedly cross the same WSL session boundary that becomes exhausted. Cron is not guaranteed to run, and Wave-launcher edits would not protect other creation paths.

### Exact fail-closed classification

A strict candidate requires exact `Relay` process name, PPID 1, a single `/init` argument, empty kernel child lists across every relay thread, and at least 300 seconds of age. Missing or malformed metadata makes the process ineligible. Exact naming excludes `Relay(<pid>)` and `SessionLeader`.

### Consecutive identity confirmation

The identity tuple is PID plus procfs start-time ticks. It must pass three scans, 30 seconds apart. Any failed scan or PID reuse clears confirmation state.

### Pidfd signaling with repeated revalidation

The daemon opens a Linux pidfd, revalidates the identity and complete predicate, sends `TERM` through the pidfd, waits three seconds, and revalidates before any pidfd `KILL`. Pidfds prevent PID reuse from redirecting a signal. Each cycle handles at most 32 oldest confirmed candidates.

### Bounded observability and strict configuration

Scan mode never signals. Active daemon mode requires root and `ACTIVE=true`. Unknown or out-of-range configuration refuses operation. Rotating logs contain only decision metadata, and atomic status includes strict/protected counts and signal results.

## Risks / Trade-offs

- **Valid relay temporarily resembles an orphan** → Minimum age, three observations, kernel child list, identity checks, pidfd, and pre-signal revalidation.
- **Large backlog pressures WSL** → Drain only 32 oldest per cycle.
- **Daemon keeps the distro active** → Use a sleeping process with negligible steady-state work.
- **Boot command conflicts** → Refuse installation without mutation and report the exact conflict.
- **Root implementation defect** → Root-owned fixed files, no shell-evaluated configuration, dry-run gate, and synthetic procfs tests.

## Migration Plan

1. Implement and test in an isolated worktree.
2. Compare a live non-mutating scan with the established manual predicate.
3. Install inactive and verify ownership, `systemd=false`, singleton identity, status, and logs.
4. Activate only after protected-process verification, then observe multiple cycles.
5. Roll back by stopping only the verified watchdog identity and removing only managed files and configuration; never stop WSL.

## Open Questions

- Qualify the production defaults against the first live dry-run and active cycles.
