## Context

See proposal.md. Generic creation now has an independent upstream executable.
The older onp setup path copies a script; the global installer generates wrappers.

## Goals / Non-Goals

Preserve both legacy installation paths and argument boundaries. Keep bench
generators and estate command distribution under their existing owners.

## Decisions

Install a PATH-facing verifier launcher plus a separately stored executable
payload with a commit/SHA-256 pin, API-first fetching, offline source option and
journaled, rollback-protected replacement. Direct and legacy launches both pass
through ownership and digest verification before executing a private payload
snapshot. The generated launcher contains the source pin but no checkout or pin
file path, so a verified install remains owned when workBenches moves. Stage
only verified bytes; a pending ownership record recognizes the
new digest and, only for a verified owned upgrade, the pre-upgrade digest so an
interrupted publish can resume without adopting an unowned command.
Serialize readers and writers through a persistent per-install-directory lock.
Legacy execution captures the verified byte snapshot while holding a shared
lock, then releases the lock before compiling and running that immutable
private snapshot so delegated setup operations cannot deadlock against an upgrade.
Record installer ownership and the installed digest separately; automatic
installation refuses an unowned name collision, and uninstall rechecks both.
Use the existing host-local .workbenches-path convention for discovery.
Legacy scripts forward to the executable; generic logic exists only upstream.

## Risks / Trade-offs

Upstream must be published before installation can fetch it. A squash merge
changes source identity, so re-pin to main before landing this integration.
Python 3.10+ is required. YAML inspection additionally needs PyYAML in the bench.
