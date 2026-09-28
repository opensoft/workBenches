## Context

The standalone Codex installer owns both `$HOME/.local/bin/codex` and a package
cache under `$HOME/.codex/packages/standalone`. The profile launcher changes
`CODEX_HOME` to an isolated profile directory, so the daemon looks for that
cache below the profile home. A system npm installation can also precede the
standalone launcher on `PATH`.

## Goals / Non-Goals

**Goals:**

- Make every profile use the explicit caller-selected binary when provided,
  otherwise prefer the supported standalone executable.
- Make the canonical standalone package cache visible at the path expected
  below each profile-specific `CODEX_HOME`.
- Preserve profile-specific credentials, sessions, and configuration.

**Non-Goals:**

- Remove or upgrade an existing npm Codex installation.
- Copy package payloads into every profile.
- Restart daemons, containers, or active sessions.

## Decisions

- Use the precedence `CODEX_BIN`, `$HOME/.local/bin/codex`, then `command -v
  codex`. This preserves explicit overrides while avoiding an older npm binary
  when the installer-managed standalone command is available.
- Link each profile's `packages/standalone` to the canonical cache during the
  existing idempotent profile setup. A link keeps one authoritative package
  tree and avoids duplicating large runtime payloads.
- Create links only when the canonical cache exists. This retains compatibility
  on machines that have not installed the standalone distribution.

## Risks / Trade-offs

- [Canonical package cache is removed] → The managed link becomes dangling;
  rerunning the official standalone installer restores the target without
  altering profile data.
- [Caller needs a different Codex binary] → `CODEX_BIN` remains the highest
  precedence override.
- [Existing profile has a conflicting package path] → Reuse the setup helper's
  guarded link function rather than overwriting unrelated regular files.
