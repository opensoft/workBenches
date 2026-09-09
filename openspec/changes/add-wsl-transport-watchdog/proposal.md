## Why

Wave terminals can fail even when the WSL guest filesystem remains reachable,
because the Windows-to-Linux process-creation channel can become stuck. A
bounded Windows-side probe is needed to detect and capture that failure without
restarting WSL or disturbing unrelated sessions and containers.

## What Changes

- Add a per-user Windows watchdog that probes WSL process creation with a fixed
  deadline and classifies consecutive failures.
- Terminate only the watchdog-owned probe process when that deadline expires.
- Capture bounded, secret-free Windows and guest evidence on health
  transitions.
- Add a reversible scheduled-task installer with install, uninstall, start,
  stop, and status actions.
- Document the boundary between Windows transport diagnosis and the separate
  Linux strict-orphan relay watchdog.

## Capabilities

### New Capabilities

- `wsl-transport-watchdog`: Detects and records WSL process-creation transport
  failures from Windows without broad service, distribution, or workload
  lifecycle actions.

### Modified Capabilities

None.

## Impact

- Adds Windows PowerShell scripts and operator documentation.
- Optional installation creates one limited, per-user scheduled task and local
  state beneath the user's local application-data directory.
- Does not install automatically, change WSL configuration, terminate a
  distribution, restart WSL services, or recreate bench containers.
