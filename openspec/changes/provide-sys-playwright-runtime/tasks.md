## 1. Shared browser runtime

- [x] 1.1 Install pinned Playwright Chromium and supported dependencies in the shared sys-bench image.
- [x] 1.2 Fail the build when Chromium has unresolved shared libraries.

## 2. Verification

- [x] 2.1 Add a source regression guard for shared cache, version alignment, dependency installation, and shared-library verification.
- [x] 2.2 Build and smoke-test the shared sys and cloud images without recreating the running cloud bench.
