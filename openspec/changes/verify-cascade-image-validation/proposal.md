## Why

A cascade rebuild can report success after rebuilding the shared bases even
when a rebuilt bench image cannot run a required inherited CLI. Operators need
evidence from the Layer 2 images they consume, and a safe indication of whether
their personalized Layer 3 image has been activated.

## What Changes

- Verify every Layer 2 image selected by a cascade rebuild through disposable,
  noninteractive command probes.
- Report the state of the corresponding Layer 3 user image without rebuilding,
  replacing, or restarting a running bench.
- Record verification results with the exact image references and immutable
  image identifiers used for the probes.
- Make version-manifest output opt-in so a routine verification does not alter
  the source checkout.

## Capabilities

### New Capabilities

- `cascade-image-validation`: Verifies cascade-targeted bench images and
  safely reports personalized-image activation state.

### Modified Capabilities

None.

## Impact

- Affects `scripts/update-and-rebuild.sh` and `scripts/check-versions.sh`.
- Adds focused script-level tests for image selection, probe results, and
  manifest behavior.
- Does not rebuild Layer 3 images or change live containers.
