# Design

## Context

See proposal.md for motivation. The shared Wave Compose override is appended last during pyBench creation and repair. The personalized image's entrypoint executes the keepalive command; the running container has no init and retains orphaned zsh children. Normal launches intentionally reuse live containers.

## Goals / Non-Goals

**Goals:** Ensure Wave Compose-created containers reap orphaned children; retain image, user, project/profile mounts and shared-container reuse.

**Non-Goals:** Rebuild images, change Powerlevel10k, replace unrelated live benches, alter the Dev Containers CLI lifecycle, or silently replace a running container on normal launch.

## Decisions

Add `init: true` to the existing generated Compose service override. Docker supplies the runtime init/reaper; no image dependency or custom supervisor is needed. A prompt-only change would hide one producer without addressing other orphaned tools. An ordinary restart does not change the container's creation configuration, so activation requires an explicitly authorized repair.

Extend the existing mock launcher tests to inspect generated override content before fixture cleanup. Cover first creation, explicit repair, stopped repair and explicit Compose creation, while preserving running-container and foreign-container safeguards.

## Risks / Trade-offs

- Container replacement closes attached terminals and discards unmounted writable-layer data -> inspect Docker diff and retain recovery material if present before repair; retain named volumes and host binds.
- Source in a feature worktree is not yet used by the normal Wave launcher -> use the changed launcher with the canonical workBenches root for this activation; report publication status separately.
- Init does not repair a still-live parent that fails to wait for its own children -> verify the diagnosed orphaned prompt-helper case in the real interactive shell.

## Migration Plan

Run regression tests inside py-bench before replacement. Inspect the merged Compose configuration without displaying credentials. Invoke the changed launcher with canonical source/mount root and `--repair --check` for py-bench only. Verify runtime init, identity, mount retention, repeated shell exits, zero zombies, and unchanged cloud-bench/m365-bench identities. If activation fails, use the canonical declared lifecycle with preserved volumes; no image rollback is required.
