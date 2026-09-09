# WSL transport watchdog

The WSL transport watchdog checks the Windows-to-Linux process creation path independently of the Linux relay watchdog.

## Failure boundary

The probe runs:

```powershell
wsl.exe --distribution Ubuntu-24.04 --exec /bin/true
```

Each probe has an eight-second deadline. Two consecutive failures classify the channel as `stuck`. The watchdog terminates only the `wsl.exe` process that it created for the timed-out probe.

It never:

- restarts `WSLService`;
- runs `wsl --terminate`;
- runs `wsl --shutdown`;
- signals existing `wsl.exe` or `wslhost.exe` processes;
- signals Linux named relays or `SessionLeader` processes.

The separate Linux relay watchdog remains responsible only for repeatedly confirmed strict orphan relays.

## Install and operate

Run from Windows PowerShell:

```powershell
& .\scripts\install-wsl-transport-watchdog.ps1 -Action Install
& .\scripts\install-wsl-transport-watchdog.ps1 -Action Status
& .\scripts\install-wsl-transport-watchdog.ps1 -Action Stop
& .\scripts\install-wsl-transport-watchdog.ps1 -Action Start
& .\scripts\install-wsl-transport-watchdog.ps1 -Action Uninstall
```

The per-user scheduled task starts at logon and is named `workBenches WSL Transport Watchdog`.

Runtime files are stored under:

```text
%LOCALAPPDATA%\workBenches\wsl-transport-watchdog\
```

- `status.json` contains current health and the last probe.
- `events.jsonl` contains transitions and ten-minute heartbeats.
- `evidence\wsl-transport-*.json` contains bounded Windows and Linux snapshots captured when health changes to `stuck`.

## Diagnosis and recovery

The evidence distinguishes these cases:

1. **Strict orphan relays present**: the Linux relay watchdog confirms and removes only strict orphan `/init` relays.
2. **Guest filesystem alive but process creation stuck**: the WSL session hvsocket or `WslCorePort` is wedged. The Windows watchdog records host process counts, WSL service identity, memory, Linux pressure, relay-watchdog status, and recent HNS/Hyper-V events.
3. **Guest filesystem and process creation both unavailable**: the failure is broader than the session channel and requires controlled maintenance.

There is no supported non-disruptive command that reconstructs a dead WSL VM/session hvsocket on WSL 2.6.1. Restarting `WSLService`, terminating the distribution, or shutting down WSL can interrupt all active workloads and is intentionally outside the watchdog's authority.

Microsoft's WSL releases include a later fix for a broken `WslCorePort` channel after a receive timeout. Upgrade WSL during a controlled maintenance window, then let this watchdog verify that subsequent timeouts recover without accumulating probes.

For root-cause ETW evidence, run Microsoft's official WSL log collector from an elevated PowerShell before reproducing the issue:

```powershell
.\collect-wsl-logs.ps1 -LogProfile hvsocket
```

The watchdog evidence timestamp identifies the exact interval to inspect in the resulting ETL trace.
