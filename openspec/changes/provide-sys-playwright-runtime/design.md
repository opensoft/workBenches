## Context

System administration benches increasingly use browser-backed automation. The
shared sys image currently provides cloud and infrastructure tools but no
guaranteed Chromium runtime. A browser downloaded into a user's cache can also
outlive or disagree with its system library set.

## Goals / Non-Goals

**Goals:**

- Provide one pinned Playwright/Chromium runtime in the shared sys image.
- Install the complete supported dependency set during image construction.
- Detect missing shared libraries before an image is published.
- Make browser binaries available to every derived sys bench user.

**Non-Goals:**

- Automate browser logins or store browser credentials in the image.
- Recreate running sys benches.
- Add a second browser family.

## Decisions

- Pin Playwright to the same version used by the developer-bench testing tools
  to avoid two unmanaged browser revisions.
- Use Playwright's `install --with-deps chromium` path instead of maintaining a
  partial hand-written apt package list.
- Store browsers under `/ms-playwright` with a shared sticky directory rather
  than a root or user cache.
- Resolve the installed Chromium executable, normalize shared-cache permissions,
  run `ldd`, and perform a bounded headless page launch during the build;
  unresolved libraries or browser startup failure fail the layer immediately.

## Risks / Trade-offs

- [Image size increases] → Install only Chromium and clean package metadata.
- [Upstream dependency list changes] → Rebuilding the pinned Playwright release
  uses its supported dependency installer and the shared-library gate.
- [Running benches remain old] → Report image success separately; recreation
  remains an explicit operational action.
