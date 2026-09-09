## 1. Layer 3 Codex Overlay

- [x] 1.1 Configure a user-owned npm prefix and PATH precedence in `user-layer/Dockerfile`, then verify the inherited system prefix is not modified.
- [x] 1.2 Install a pinned Codex version into the Layer 3 user prefix as the runtime user, then verify the installed package is user-owned.
- [x] 1.3 Fingerprint the Layer 3 build recipe and rebuild an existing user image whenever its recorded recipe fingerprint differs.
- [x] 1.4 Remove only stopped containers configured for the user-image tag when their immutable image ID is stale, preserving running or racing containers.

## 2. Image Validation

- [x] 2.1 Build a disposable `dotnet-bench:brett` Layer 3 image and verify `codex` resolves from `$HOME/.npm-global/bin`.
- [x] 2.2 Verify the resolved Codex package is writable by `brett`, the base image's shared Codex package (located with its root npm global prefix) remains root-owned, and OpenSpec validation passes.
- [x] 2.3 Verify the Layer 3 freshness check rebuilds a stale recipe fingerprint, preserves the fast path for an exact fingerprint match, and reconciles a stopped stale container.
