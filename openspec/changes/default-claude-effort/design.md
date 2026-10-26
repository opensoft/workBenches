## Context

The shared profile launcher prepares permissions and hands arguments to Claude directly or through lane-start. pclaude and lclaude use this same path. Legacy user settings no longer ensure the intended Opus 5.5 startup effort.

## Goals / Non-Goals

**Goals:** Add an explicit xhigh fallback while preserving CLI and environment overrides, routing classification, and original arguments.

**Non-Goals:** Rewrite profile preferences, change models or authentication, alter live sessions, or rebuild/restart benches.

## Decisions

- Append the fallback to the existing `claude_flags` array after routing decisions. Prepending to positional arguments would change first-argument classification, especially print mode.
- Detect `--effort` and `--effort=...` only before a standalone `--`. Preserve invalid explicit values for Claude's own validation.
- Check nonempty inherited and profile `env.CLAUDE_CODE_EFFORT_LEVEL`. Keep stored settings intact. Legacy top-level settings are not authoritative for this startup fallback.
- Carry the client's effort environment through tmux child startup, clearing any stale server value first. Empty or absent client values retain fallback semantics.
- Exclude utility commands. Include interactive, resume, and print-mode inference.
- Use temporary manifests and a mock executable for tests; no provider usage or live profile credentials.

## Risks / Trade-offs

- Future CLI subcommands may need classification updates -> retain an explicit exclusion list and utility regressions.
- Source changes do not update installed launchers -> report deployment separately; back up and byte-verify any narrow live installation.
- Shared launcher change also affects lclaude -> regression-test lane handoff without changing lane selection.

## Migration Plan

Validate source and existing regressions first. Install only the launcher where authorized through existing setup/deployment mechanisms, preserving previous launchers for rollback. No running processes are restarted. Image-persistent rollout remains separate from live installation.

## Open Questions

None for implementation. Repository landing and image rollout remain distinct delivery actions.
