## Context

Wave widgets enter benches through one shared launcher. The launcher currently
uses a container name as proof of identity, so a stopped foreign container can
be started and then receive workBench-specific bootstrap commands.

## Goals / Non-Goals

**Goals:**

- Bind each Wave widget to the `brett` Layer 3 account explicitly.
- Verify a named existing container uses the expected Layer 3 image before any
  lifecycle or bootstrap operation.
- Preserve a foreign container unchanged and provide an actionable diagnostic.

**Non-Goals:**

- Rename, remove, or otherwise take ownership of foreign containers.
- Rebuild shared Layers 0-2 or force-refresh a running Layer 3 image.

## Decisions

- Compute the expected image from the resolved Layer 2 base and selected user,
  then compare it with a pre-existing container's configured image and image
  ID. Image identity, rather than the container name or numeric UID, prevents
  collisions with unrelated workloads.
- Perform this comparison before the existing start/recreate/bootstrap paths.
  Refusing early prevents a stopped foreign container from being revived.
- Make the shipped Wave shortcuts pass `--user brett`. This makes the
  user-specific Layer 3 selection deterministic while retaining the launcher's
  general `--user` option for other callers.

## Risks / Trade-offs

- [A legitimate container uses an equivalent image reference] → compare both
  configured reference and immutable image ID, and accept either expected form
  only when it resolves to the expected Layer 3 image.
- [A foreign container blocks a bench name] → report the exact configured and
  expected image, with no destructive automatic recovery.
- [User-specific widgets become less portable] → scope the explicit `brett`
  selection to Brett's local Wave configuration.
