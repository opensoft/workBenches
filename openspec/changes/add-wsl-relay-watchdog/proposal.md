## Why

Wave terminal relays can accumulate as root-owned, childless `/init` processes until WSL session creation fails or the workstation becomes unresponsive. Manual cleanup requires an already-open privileged shell, so prevention must happen automatically while preserving every live or ambiguous relay.

## What Changes

- Add a root-owned WSL relay watchdog that detects only strict orphan relays: plain `Relay`, parent PID 1, exact `/init` command, no children, and older than a configured minimum age.
- Require the same process identity to satisfy the strict predicate across multiple observations before it becomes eligible for cleanup.
- Revalidate every eligible process immediately before `TERM`, wait a bounded grace period, and revalidate survivors before `KILL`.
- Limit cleanup work per cycle, serialize watchdog instances, and fail closed when process metadata is missing, malformed, or ambiguous.
- Preserve all named `Relay(<pid>)` processes, all `SessionLeader` processes, relays with children, and relays below the minimum age.
- Provide audit logging, dry-run inspection, status output, and reversible install/uninstall commands.
- Register the watchdog without enabling systemd and without shutting down WSL.

## Capabilities

### New Capabilities

- `wsl-relay-watchdog`: Safely identify, confirm, clean, report, install, and remove strict orphan WSL relays.

### Modified Capabilities

None.

## Impact

- Adds focused scripts and tests under the workBenches repository.
- Installation places a root-owned watchdog entry point and state/log directories inside Ubuntu 24.04, and updates only the WSL boot command while preserving the existing `wsl.conf` settings.
- Uses Python 3, Linux procfs, pidfds, standard process signals, and `flock`; it does not require systemd, modify Wave launchers, recycle Docker benches, or stop WSL.
