# WSL Relay Watchdog

The watchdog prevents Wave relay exhaustion by removing only relays that repeatedly satisfy the complete strict orphan predicate. It does not stop or restart WSL.

## Safety Boundary

A process is eligible only when all of these remain true:

- `/proc/<pid>/comm` is exactly `Relay`.
- Parent PID is exactly 1.
- The command line is exactly the single argument `/init`.
- The kernel child lists aggregated across every relay thread are empty.
- The process is at least 300 seconds old.
- The same PID and start-time identity passes three scans, 30 seconds apart.
- The identity and complete predicate pass again immediately before each signal.

Signals use a Linux pidfd so PID reuse cannot redirect them. Named `Relay(<pid>)` processes, `SessionLeader` processes, relays with children, recent relays, and processes with ambiguous metadata are excluded.

## Repository Dry Run

From the feature checkout:

```bash
python3 scripts/wsl-relay-watchdog/wsl_relay_watchdog.py scan
```

This command never sends signals. Its JSON output includes strict, named-relay, and SessionLeader counts and identities without environment data or unrelated command lines.

## Install Inactive

Run from a WSL shell at the repository root. `sudo` elevates only the installer
and does not place a password or token in command arguments:

```bash
sudo python3 scripts/wsl-relay-watchdog/install.py install --inactive
```

The installer:

- Refuses a pre-existing unmanaged `[boot] command`.
- Preserves `systemd=false` and every unrelated `/etc/wsl.conf` setting.
- Installs root-owned files under `/usr/local`.
- Creates a timestamped `/etc/wsl.conf` backup under `/var/lib/wsl-relay-watchdog/backups`.
- Registers `/usr/local/sbin/wsl-relay-watchdog-boot` and starts the watchdog immediately without restarting WSL.

## Status And Scan

```bash
/usr/local/sbin/wsl-relay-watchdog status
/usr/local/sbin/wsl-relay-watchdog scan
```

`status` verifies the daemon PID plus start-time identity instead of trusting a stale PID file.

The bounded log is `/var/log/wsl-relay-watchdog/watchdog.log`. Runtime identity and status files are under `/run/wsl-relay-watchdog`.

## Activate

After the inactive scan proves that named relays and SessionLeaders are protected:

```bash
sudo python3 scripts/wsl-relay-watchdog/install.py install --active
```

Reinstallation stops only the verified watchdog daemon, updates the root-owned configuration, and starts a fresh active daemon. It does not immediately signal a relay: candidates must first pass three consecutive observations.

## Defaults

The root-owned `/etc/wsl-relay-watchdog.conf` file uses these validated bounds:

| Setting | Default | Accepted range |
| --- | ---: | ---: |
| `MIN_AGE_SECONDS` | 300 | 60-86400 |
| `CONFIRMATIONS` | 3 | 3-20 |
| `INTERVAL_SECONDS` | 30 | 5-3600 |
| `BATCH_LIMIT` | 32 | 1-128 |
| `TERM_GRACE_SECONDS` | 3 | 1-30 |
| `LOG_MAX_BYTES` | 1048576 | 65536-10485760 |
| `LOG_BACKUPS` | 3 | 1-10 |

Unknown keys and out-of-range values make the watchdog refuse active operation.

## Rollback

```bash
sudo python3 scripts/wsl-relay-watchdog/install.py uninstall
```

Rollback verifies and stops only the watchdog PID/start-time identity, removes only the managed boot command and installed files, and preserves unrelated WSL configuration. Logs and timestamped backups remain for audit. It never invokes `wsl --shutdown`.

## Boot-Command Conflict

If installation reports a conflicting `[boot] command`, do not overwrite it. Inspect `/etc/wsl.conf` and decide how to compose the existing boot action with the watchdog launcher; the installer deliberately makes no changes in this state.
