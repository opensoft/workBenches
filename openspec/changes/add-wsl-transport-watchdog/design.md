## Context

The Linux relay watchdog can identify strict orphan `/init` relay processes,
but it cannot prove that Windows can still create a new process inside the WSL
distribution. The complementary transport watchdog therefore runs in the
Windows user session, owns each probe process it starts, and records evidence
without gaining authority over WSL services or existing workloads.

## Goals / Non-Goals

**Goals:**

- Detect repeated Windows-to-WSL process-creation failures with bounded probes.
- Kill only a timed-out probe owned by the watchdog.
- Record compact health state, transition events, and diagnostic evidence.
- Provide reversible, limited-user scheduled-task installation.

**Non-Goals:**

- Do not restart `WSLService`, terminate a distribution, or shut down WSL.
- Do not signal existing Windows WSL processes or Linux relay processes.
- Do not automatically repair a broken transport channel.
- Do not expose process environments, credentials, or unrestricted command
  lines in diagnostic output.

## Decisions

- Probe with `wsl.exe --distribution <name> --exec /bin/true`. This tests the
  exact process-creation path while keeping guest-side work minimal.
- Create the probe through `System.Diagnostics.Process`, retain its object and
  PID, and terminate only that object after the configured deadline. Broad
  process-name cleanup is explicitly rejected.
- Require consecutive failures before entering the `stuck` state so a single
  slow launch does not create a false incident.
- Write current state atomically, rotate the append-only event log at a bounded
  size, and retain at most 20 failure snapshots. Evidence is captured only on
  transition to `stuck`; diagnostic query failures are recorded without
  terminating the daemon.
- Gather guest filesystem evidence through the distribution's UNC filesystem
  in a separately bounded PowerShell child. This can still work when guest
  process creation is unavailable and can itself time out safely.
- Register a per-user, limited-privilege scheduled task at logon. The installer
  copies the script to a user-owned local application-data directory and
  exposes explicit lifecycle actions.
- Treat Windows event-log access as best effort. Missing providers or access
  errors are recorded as evidence fields rather than escalating privileges.

## Risks / Trade-offs

- [A slow but healthy WSL launch can time out] -> Require multiple consecutive
  failures and make timeout, interval, and threshold bounded parameters.
- [Guest filesystem inspection can block] -> Run it in a separate child with a
  five-second deadline and terminate only that owned child.
- [A stale status file can resemble a live daemon] -> Record and verify both
  the daemon PID and process start time.
- [Diagnostic logs can grow or include sensitive data] -> Rotate at a fixed
  size and collect only bounded process identity, memory, service, pressure,
  and event summaries.

## Migration Plan

1. Parse the scripts and run one probe against a temporary state directory.
2. Merge the source without installing or starting a scheduled task.
3. When explicitly requested, run the installer as the target Windows user and
   verify task state plus daemon PID/start-time identity.
4. Roll back with the uninstall action, which removes only the scheduled task
   and installed script while preserving diagnostic state for audit.

## Open Questions

None.
