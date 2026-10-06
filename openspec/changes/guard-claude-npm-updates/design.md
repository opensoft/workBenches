# Design

## Context

See proposal.md. Layer 0 and Layer 3 already attempt postinstall repair.
Runtime npm updates do not inherit that command. npm 12 blocks unapproved
scripts with exit zero. cloudBench can mount an entire home, hiding image
defaults; other benches use image-owned homes.

## Goals / Non-Goals

Goals: scoped persistent policy, offline local repair, exact-path checks, and
common activation for every Wave bench. Non-goals: replacing openRepoTools'
claude-current resolver or its update lock, a second update manager, disabling
native auto-update, changes to authentication, and container replacement.

## Decisions

- A shared Layer 3 helper configures only Claude's script approval and optional
  inclusion. Existing config entries and private values are preserved and
  never printed. The config write is atomic under a per-user flock.
- The helper can configure without repair during build, or repair an installed
  user package offline. Exact-path version probes have bounded timeouts.
  A successful hook without the correct executable is still failure.
- Layer 0 and Layer 3 installs explicitly include optional packages. Strict
  script policy is scoped to the managed build install, not imposed on every
  unrelated project npm install.
- Wave distributes the helper in its existing launcher bundle and invokes it
  as the bench user after mounts. A mounted home is therefore protected too.
- Existing native installs are checked but not converted or shadowed. The
  already-governed resolver remains owned by openRepoTools.

## Risks / Trade-offs

- Explicit npm environment overrides can defeat user config -> verify effective
  policy and fail with a specific explanation.
- Another arbitrary npm command does not honor our repair lock -> no claim
  of universal update serialization; openRepoTools retains its own lock.
- A stopped container cannot execute checks -> deploy the helper while stopped,
  then start the existing container for verification where safe; report failures.
- The helper does not download a missing payload -> require an explicit
  optional-inclusive reinstall and never silently fall back to an older binary.

## Migration Plan

Test in the feature worktree; deploy the helper to existing managed benches
without recreation; verify as brett. Future rebuilds inherit the recipe once
the feature lands. Rollback removes only the added policy approval/optional
inclusion and reverts source integration; preserve all pre-existing settings.
