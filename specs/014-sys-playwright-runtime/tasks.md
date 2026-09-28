# Tasks: Sys Playwright Runtime

## Phase 1: Shared runtime

- [x] T001 [US1] Add the pinned shared Playwright cache and Chromium dependency installation to `sysBenches/base-image/Dockerfile`
- [x] T002 [US1] Add a build-time Chromium shared-library gate to `sysBenches/base-image/Dockerfile`

## Phase 2: Version and inheritance guard

- [x] T003 [US2] Add source assertions and developer/sys Playwright version alignment to `devcontainer.test/test-base-image-dockerfile.sh`

## Phase 3: Verification

- [x] T004 Validate `openspec/changes/provide-sys-playwright-runtime/` strictly and run source checks
- [x] T005 Build and smoke-test shared sys and derived cloud images without recreating active containers

## Dependencies

- T002 depends on T001.
- T004 and T005 depend on all source changes.

## Implementation Strategy

Land the shared runtime and its build gate together, then verify source and disposable images. Keep live activation out of this feature.
