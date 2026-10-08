## Context

The shared Wave launcher currently checks image identity and required mount destinations, then starts a stopped container. A Docker Desktop WSL staging source can be missing while the original host file is valid. The canonical checkout also has unrelated pending bench gitlink updates, which this feature must preserve.

## Goals / Non-Goals

**Goals:** Check actual bind sources without reading their contents, identify the specific missing staged-source failure, preserve normal reuse, and keep recreation an explicit bounded operation.

**Non-Goals:** Automatic container replacement, credential relocation, Docker/WSL restarts, image rebuild policy changes, or fixing Docker Desktop internals.

## Decisions

- Preflight stopped containers' actual bind-source metadata, including known file, directory, and socket destinations. Validate before image preparation or explicit deletion. Running normal attaches skip this check because an atomic host-file replacement need not invalidate the active container.
- Resolve Docker Desktop staged-source metadata through read-only declared Compose rendering, including existing Wave/ROCm/WSLg overlays, using the shared helpers' existing jq dependency. Validate original host sources, never internal daemon paths; unresolved sources fail closed before mutation.
- Require a regular host Claude configuration file before creation/recreation. Keep existing bootstrap behavior for non-credential shell files; reject their wrong types. Never read or print credential contents.
- Capture one bounded start attempt. Classify only an OCI mount failure containing the Docker Desktop WSL bind-mount namespace and a missing-source error. Revalidate actual sources before offering repair; unrelated errors retain their exit status.
- Retain `--repair` as consent to replacement. Verify image and declared Compose ownership. For a stopped container, use non-force removal so a concurrent start is preserved. Existing explicit live repair remains a separately requested destructive operation.
- Reuse the existing Compose/Dev Containers lifecycle, including ROCm and other overlays. No second repair is attempted if startup after explicit recreation fails.
- Extend the existing mocked lifecycle suite; do not manufacture a real stale mount or replace live benches for testing.

## Risks / Trade-offs

- Container-only data is lost on explicit recreation -> warn in help, diagnostics, and documentation; normal launches never replace solely because startup failed.
- Missing host credentials are a different incident -> fail clearly instead of creating an empty file or repeatedly recreating.
- Docker Desktop error wording can change -> match narrowly and leave unknown errors untouched.
- A source can change after preflight -> capture the real startup error and revalidate before recommending recovery.

## Migration Plan

Publish the shared-source feature separately from pending bench-pin work. Verify Wave links point to the updated canonical launcher after publication. Rollback is a source revert; no credential, image, or container migration is performed by this implementation.
