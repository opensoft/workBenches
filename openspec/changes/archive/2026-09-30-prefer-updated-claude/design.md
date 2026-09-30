## Context

The shared profile launcher resolves `claude` from `PATH` first. In bench images that finds the fixed, root-owned `/usr/local/bin/claude`, while the native updater installs newer per-user executables under `~/.local/share/claude/versions/`. The user's `~/.local/bin/claude` can also be a compatibility symlink to the old system copy.

## Goals / Non-Goals

**Goals:** Use the newest already-installed native executable for profile and lane starts, without network startup delay. Preserve explicit `CLAUDE_BIN` and a PATH fallback.

**Non-Goals:** Change profile model defaults, force an update on launch, delete old binaries, or restart live sessions.

## Decisions

- Resolve once at launcher startup, then pass the selected absolute path through `CLAUDE_BIN` to `lane-start`. This keeps direct and lane launches consistent.
- Inspect regular executable files with numeric three-component version names in the native versions directory. Compare components numerically using portable shell logic, not timestamps or GNU-only `sort -V`.
- When `CLAUDE_BIN` is nonempty, preserve it verbatim. When no valid native version exists, retain the current PATH-first fallback.
- Leave update acquisition to Claude Code's native background updater. A newly installed version becomes available on the next launch; no synchronous network check occurs.

## Risks / Trade-offs

- [A newer version is incompatible with the profile or environment] → Operators can pin a known executable with `CLAUDE_BIN`.
- [Updater leaves old versions on disk] → Selection ignores old versions; cleanup is outside this change.
- [Native install uses a different layout] → PATH fallback remains available.

## Migration Plan

Ship the launcher through the normal workBenches image or bench synchronization path. Existing sessions continue on their current executable; new sessions use the selected installed version. Rollback is a launcher revert or an explicit `CLAUDE_BIN` override.
