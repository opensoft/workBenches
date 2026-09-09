## Context

See proposal.md for motivation. Layer 0 deliberately installs shared npm
packages as root. Layer 3 creates the runtime user but currently inherits the
system-wide Codex binary without a writable npm prefix.

## Goals / Non-Goals

**Goals:**

- Make the Layer 3 `codex` executable and its npm package writable by the
  runtime user.
- Preserve the shared Layer 0 Codex package and its ownership.

**Non-Goals:**

- Do not change Layer 0 or Layer 2 images.
- Do not replace or restart a running bench.
- Do not make arbitrary system npm packages user-writable.

## Decisions

- Install a second Codex copy into the runtime user's `$HOME/.npm-global` after Layer 3
  switches to the runtime user. This isolates user updates from the shared
  root-owned package.
- Set the npm global prefix and prepend its bin directory through Layer 3
  environment configuration. The resolved `codex` and the updater therefore
  use the same writable location.
- Retain the Layer 0 copy as a base-image fallback. Chowning the shared npm
  directory was rejected because it would weaken the user-agnostic ownership
  boundary; requiring `sudo` was rejected because it leaves untracked
  container drift.

## Risks / Trade-offs

- [User-updated Codex can differ from the baked baseline] → The image build
  supplies an initial known package and version checks will report the resolved
  user copy.
- [Two Codex installations increase image size] → The additional package is
  small relative to the bench image and preserves the shared baseline.

## Migration Plan

1. Build the target Layer 3 image from its existing Layer 2 base.
2. Verify the resolved Codex path, ownership, writable npm prefix, and version
   in a disposable container.
3. Keep the running bench unchanged until an explicit managed close/reopen is
   authorized.
