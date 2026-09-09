## Why

Codex is installed in the shared Layer 0 image as root, so its built-in npm
updater fails for the non-root user in a running bench. Users need a writable
Codex installation without weakening ownership of the shared baseline.

## What Changes

- Add a user-owned Codex npm installation to Layer 3 after the runtime user is
  created.
- Prepend that user-owned npm bin directory to the Layer 3 `PATH`.
- Keep the existing root-owned Layer 0 Codex installation unchanged as the
  shared baseline.

## Capabilities

### New Capabilities

- `user-managed-codex-updates`: Layer 3 user images provide a writable Codex
  installation that supports the Codex npm update workflow.

### Modified Capabilities

- None.

## Impact

- [user-layer/Dockerfile](../../../user-layer/Dockerfile): installs and
  prioritizes the user-owned Codex overlay.
- Layer 3 images must be rebuilt to include the behavior; no live container is
  replaced by this change.
