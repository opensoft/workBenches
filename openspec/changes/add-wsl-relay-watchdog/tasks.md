## 1. Isolated Implementation Setup

- [x] 1.1 Create a clean Speckit feature worktree without modifying or discarding the unrelated dirty root checkout
- [x] 1.2 Confirm no active lane owns the proposed watchdog paths and record the implementation boundary
- [x] 1.3 Add the watchdog, installer, test, and documentation file skeletons in new non-overlapping paths

## 2. Strict Relay Inspection Engine

- [x] 2.1 Implement procfs readers for exact process name, parent PID, start-time identity, command-line arguments, elapsed age, and child relationships
- [x] 2.2 Implement the fail-closed strict orphan predicate and explicit protected classifications for named relays and SessionLeaders
- [x] 2.3 Implement consecutive observation tracking keyed by PID and start-time ticks, clearing state on predicate failure or identity change
- [x] 2.4 Implement oldest-first eligibility selection with validated configurable age, observation, interval, grace, and batch bounds

## 3. Revalidated Cleanup and Daemon Lifecycle

- [x] 3.1 Implement immediate full identity revalidation before TERM and before any KILL
- [x] 3.2 Implement bounded TERM, grace-period, survivor revalidation, and KILL handling with structured outcomes
- [x] 3.3 Implement singleton daemon startup using fixed paths, a non-blocking flock, and atomic runtime state updates
- [x] 3.4 Implement scan, status, daemon, and explicitly activated run-once modes without shell-evaluated configuration
- [x] 3.5 Implement bounded secret-free event logging and fixed log rotation

## 4. Installation and Rollback

- [x] 4.1 Implement prerequisite, root-authority, ownership, path, and configuration validation
- [x] 4.2 Implement root-owned file installation and a detached WSL boot launcher compatible with `systemd=false`
- [x] 4.3 Implement surgical `wsl.conf` backup and boot-command registration that refuses unmanaged command conflicts
- [x] 4.4 Implement immediate watchdog startup without WSL restart and verify the daemon PID plus start-time identity
- [x] 4.5 Implement uninstall that stops only the verified watchdog identity and removes only watchdog-owned files and configuration

## 5. Automated Safety Tests

- [x] 5.1 Add synthetic procfs fixtures covering strict orphans, named relays, SessionLeaders, child-bearing relays, recent relays, and malformed metadata
- [x] 5.2 Add tests for consecutive observations, interrupted observations, PID reuse, disappearing processes, and child races
- [x] 5.3 Add signal-order and revalidation tests proving TERM-before-KILL and no signal after identity or predicate changes
- [x] 5.4 Add batch-limit, configuration rejection, singleton lock, bounded logging, install-conflict, and rollback-preservation tests
- [x] 5.5 Add missing-identity lock, fresh-start status, and absent-configuration rollback coverage
- [x] 5.6 Add target-scoped pre-signal child revalidation and daemon lock-release waiting
- [x] 5.5 Run focused tests and shell syntax/static checks, fixing only watchdog-related failures

## 6. Live Dry-Run Qualification

- [x] 6.1 Compare non-mutating live scan counts with the established strict manual predicate
- [x] 6.2 Verify live named relays and SessionLeaders are reported as protected and absent from all signal sets
- [x] 6.3 Install in inactive mode, verify root ownership, singleton status, bounded logs, and preserved `systemd=false` without restarting WSL
- [x] 6.4 Enable active cleanup with approved production defaults and verify multiple cycles remain healthy without terminating protected processes
- [x] 6.5 Document operation, status inspection, tuning bounds, conflict recovery, and no-WSL-shutdown rollback
