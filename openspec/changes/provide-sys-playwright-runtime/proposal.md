## Why

Browser-backed administration in sys benches can fail before launch when the
image lacks Chromium's Linux runtime libraries. Repairing individual live
containers is temporary and leaves new workstations and rebuilt benches broken.

## What Changes

- Install a pinned Playwright CLI and Chromium browser in the shared sys-bench
  image.
- Install Chromium's complete supported Linux dependency set during the image
  build.
- Store browser binaries in a shared image-owned cache usable by derived sys
  benches.
- Fail the build when Chromium has unresolved shared libraries.
- Add a source regression guard aligned with the developer-bench Playwright
  version.

## Capabilities

### New Capabilities

- `sys-playwright-runtime`: Defines the browser binary, dependency, cache, and verification contract inherited by system administration benches.

### Modified Capabilities

None.

## Impact

- `sysBenches/base-image/Dockerfile`
- `devcontainer.test/test-base-image-dockerfile.sh`
- Rebuilt `sys-bench-base` and derived sys-bench images grow by the Chromium
  browser and runtime packages; active containers remain unchanged until a
  separately authorized recreation.
