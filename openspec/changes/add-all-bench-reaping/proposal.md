# Proposal

## Why

The shipped Wave override enables orphan reaping only on its direct Compose path. Dev Containers, direct Compose starts, project templates and bench test stacks still create containers without an init process. Brett requested extending the fix to every bench on 2026-10-07.

## What Changes

- Enable runtime init in all canonical bench services, bench-based Frappe workers, distributed project templates and bench test services.
- Retain the Wave override as defense in depth; add repeatable configuration validation.
- Preserve live containers, identities, mounts, commands and Layer 0-3 images. Activation is a separate authorized replacement, not a restart.

## Capabilities

### New Capabilities

- `bench-process-reaping`: Extend the capability introduced by the landed `fix-bench-reaping` change to canonical startup definitions. That change has not yet been archived into the canonical spec store; this delta adds the canonical-startup requirement without rewriting its approved Wave requirement.

### Modified Capabilities

None in the current canonical spec store.

## Impact

Fourteen bench repositories across dev, sys and bio families, the parent family/test Compose definitions, a configuration checker and CI regression coverage. Eight repositories are parent-pinned submodules; six are separately cloned by setup. Child publication must precede any parent gitlink updates. No new runtime dependencies or image builds are required.

Implementation authority: the user's explicit request to add the fix to all benches. Publication and live replacement remain separate decisions.
