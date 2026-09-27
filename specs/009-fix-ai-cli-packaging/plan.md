# Implementation Plan: Shared AI CLI Image Refresh

**Branch**: `009-fix-ai-cli-packaging` | **Date**: 2026-09-22 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification for refreshing shared AI CLI tooling and fixing MiniMax Code/Grok image packaging.

## Summary

Refresh supported AI CLIs through the image's existing official stable-channel installers, repair MiniMax Code by placing its launcher and versioned runtime together in a world-readable shared install, add `mcode` to the required CLI contract, and expose Grok through the shared image `PATH`. Validate the source and disposable images without replacing active bench containers.

## Technical Context

**Language/Version**: Bash, Dockerfile; Linux images
**Primary Dependencies**: Docker/Compose, image installer scripts, upstream AI CLI installers
**Storage**: Docker images and containers; no new persistent data
**Testing**: Installer contract and `--version` smoke checks across refreshed Layer 2/Layer 3 images; cascade's version checker
**Target Platform**: WSL2 Ubuntu 24.04 with Docker Desktop
**Project Type**: Container build and shell tooling
**Constraints**: Preserve user-owned changes in the original checkout; build in the isolated feature worktree; do not embed credentials; keep image rebuilds separate from live activation; do not replace active benches during this feature.
**Scale/Scope**: Shared Layer 0 source plus declared downstream image validation

## Constitution Check

The repository constitution file is still the uninitialized template, so it defines no enforceable project-specific gates. Follow repository instructions: run Docker/image operations only through declared bench tooling, preserve unrelated parent/submodule changes, keep credentials out of images, and verify direct runtime behavior after activation.

## Project Structure

```text
base-image/Dockerfile                 # shared environment and PATH
base-image/ai-cli-contract.sh         # required CLI command contract
base-image/install-ai-clis.sh         # upstream installers and runtime checks
scripts/update-and-rebuild.sh         # managed cascade build
scripts/ensure-layer3.sh              # personalized image build
scripts/wave-container-shell.sh       # managed bench replacement/startup
specs/009-fix-ai-cli-packaging/        # feature design and execution record
```

**Structure Decision**: This is an existing container-image/tooling repository; no new application modules or data models are needed.

## Complexity Tracking

No constitution violations or new architectural complexity.
