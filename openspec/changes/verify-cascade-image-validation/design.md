## Context

`update-and-rebuild.sh --all --cascade` rebuilds the shared base images and
discovers the Layer 2 benches that depend on each family base. Its final
version check currently inspects only the shared bases and unconditionally
writes a timestamped manifest in the source tree. A running `:<user>` bench
must remain untouched by image refresh automation.

## Goals / Non-Goals

**Goals:**

- Treat the cascade discovery result as the authoritative Layer 2 verification
  set.
- Probe required commands from each rebuilt Layer 2 image in a disposable
  container.
- Inspect an existing Layer 3 image without building, retagging, stopping, or
  restarting a container, and report whether it is current relative to Layer
  2.
- Produce a manifest only when explicitly requested and include immutable image
  identifiers in its records.

**Non-Goals:**

- Change the Layer 0-to-Layer 2 rebuild order or bench build scripts.
- Create, refresh, or activate a Layer 3 image.
- Authenticate providers or execute interactive CLI operations.

## Decisions

- Add a `--images` input to the version checker so the rebuild controller can
  pass its exact cascade targets instead of duplicating discovery logic.
  This keeps one source of truth for the rebuild set.
- Reuse the existing disposable `docker run --rm --entrypoint=""` probe
  pattern for commands that must be available in consumed images. A command
  presence/version probe is sufficient for inheritance and PATH validation;
  provider authentication remains outside image validation.
- Make Layer 3 checking opt-in through `--check-layer3`. It reports missing,
  stale, current, and running-container-deferred states without invoking
  `ensure-layer3.sh`.
- Gate manifest persistence behind `--write-manifest`; normal verification
  remains read-only with respect to the checkout.

## Risks / Trade-offs

- [A broad CLI matrix can make a cascade slow] -> Use short bounded disposable
  probes and limit the new bench checks to the shared required-command contract.
- [A Layer 3 image can be intentionally absent or deferred] -> Report a clear
  non-passing activation status without treating it as a Layer 2 build failure.
- [Manifest consumers may rely on the old implicit write] -> Preserve the path
  and format when `--write-manifest` is explicitly supplied.

## Migration Plan

1. Add focused tests for input parsing, selected-image probes, Layer 3 status,
   and manifest gating.
2. Update the rebuild controller to request verification for its cascade set.
3. Validate script syntax and focused tests without rebuilding or restarting a
   live bench.
4. On the next authorized cascade, use `--write-manifest` when a durable
   version snapshot is required.

## Open Questions

None.
