## 1. Verification Contract

- [x] 1.1 Add explicit selected-image, Layer 3 inspection, and manifest-write options to the version checker.
- [x] 1.2 Probe the shared required-command contract in each selected Layer 2 image and record immutable image identity.
- [x] 1.3 Report Layer 3 current, stale, missing, or running-deferred state without Docker mutation.

## 2. Cascade Integration

- [x] 2.1 Retain successful cascade target image references and pass them to the version checker.
- [x] 2.2 Make manifest persistence opt-in from the rebuild controller.

## 3. Verification

- [x] 3.1 Add focused fake-Docker regression coverage for Layer 2 probes, Layer 3 reporting, and manifest gating.
- [x] 3.2 Run syntax, focused regression, and diff-hygiene checks without rebuilding or restarting a live bench.
