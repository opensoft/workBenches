# Implementation Plan: Sys Playwright Runtime

**Branch**: `014-sys-playwright-runtime` | **Date**: 2026-09-27 | **Spec**: [spec.md](spec.md)

## Summary

Install a pinned Playwright Chromium runtime and its supported Linux
dependencies in Layer 1b, store the browser in an image-owned shared cache, and
fail the build if `ldd` finds an unresolved library. Verify source, shared image,
and derived cloud image behavior without replacing the active cloud container.

## Technical Context

**Language/Version**: Dockerfile and Bash on Ubuntu 24.04

**Primary Dependencies**: Node/npm, Playwright 1.61.1, Chromium, Linux shared libraries

**Storage**: Immutable image layers under `/ms-playwright`

**Testing**: Source regression script, no-cache image builds, `ldd`, and a direct headless launch

**Target Platform**: `sys-bench-base` and derived Linux sys benches

**Project Type**: Layered container image tooling

**Performance Goals**: No per-user browser download during normal bench use

**Constraints**: Keep credentials out of images and do not restart or recreate active benches

**Scale/Scope**: Shared Layer 1b plus all downstream sys-bench images

## Constitution Check

The repository constitution remains an uninitialized template. Repository rules
require source/image/live separation, canonical build tooling, and preservation
of active workloads. The design uses those boundaries and adds no credential or
startup mutation.

## Project Structure

```text
openspec/changes/provide-sys-playwright-runtime/
specs/014-sys-playwright-runtime/
sysBenches/base-image/Dockerfile
devcontainer.test/test-base-image-dockerfile.sh
```

**Structure Decision**: Extend the existing sys family base rather than adding
browser packages independently to each Layer 2 bench.

## Complexity Tracking

No constitution violations or unnecessary components.
