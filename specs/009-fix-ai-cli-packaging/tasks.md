# Tasks: Shared AI CLI Image Refresh

**Input**: Design documents from this feature directory.

## Phase 1: Shared image corrections

- [x] T001 Update shared PATH and remove conflicting inherited UID/GID 1000 Ubuntu identity in `base-image/Dockerfile`.
- [x] T002 Add `mcode` to the required CLI contract in `base-image/ai-cli-contract.sh`.
- [x] T003 Install MiniMax Code to `/opt/minimax-code`, expose both launchers, set shared permissions, and enforce runnable validation in `base-image/install-ai-clis.sh`.

## Phase 2: Source and image validation

- [x] T004 Run focused installer, contract, Dockerfile, and cascade-selection tests for the feature source.
- [x] T005 Verify a disposable image exposes runnable `mcode` and `grok` as the normal bench user, or record the final no-cache cascade as the integration gate when upstream downloads prevent a bounded feature build.

## Phase 3: Runtime verification

- [x] T006 Verify the source requires `mcode`, exposes Grok image-wide, and leaves credentials outside image layers.
- [x] T007 Inspect diff hygiene and generated build state while leaving active containers untouched.
