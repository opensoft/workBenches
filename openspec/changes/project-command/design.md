## Context

See proposal.md. Generic creation now has an independent upstream executable.
The older onp setup path copies a script; the global installer generates wrappers.

## Goals / Non-Goals

Preserve both legacy installation paths and argument boundaries. Keep bench
generators and estate command distribution under their existing owners.

## Decisions

Install a single executable with a commit/SHA-256 pin, API-first fetching,
offline source option and atomic replacement. Stage only verified bytes.
Use the existing host-local .workbenches-path convention for discovery.
Legacy scripts forward to the executable; generic logic exists only upstream.

## Risks / Trade-offs

Upstream must be published before installation can fetch it. A squash merge
changes source identity, so re-pin to main before landing this integration.
Python 3.10+ is required. YAML inspection additionally needs PyYAML in the bench.
