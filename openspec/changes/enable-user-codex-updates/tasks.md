## 1. Layer 3 Codex Overlay

- [x] 1.1 Configure a user-owned npm prefix and PATH precedence in `user-layer/Dockerfile`, then verify the inherited system prefix is not modified.
- [x] 1.2 Install Codex into the Layer 3 user prefix as the runtime user, then verify the installed package is user-owned.

## 2. Image Validation

- [x] 2.1 Build a disposable `dotnet-bench:brett` Layer 3 image and verify `codex` resolves from `$HOME/.npm-global/bin`.
- [x] 2.2 Verify the resolved Codex package is writable by `brett`, the shared `/usr/lib/node_modules/@openai/codex` remains root-owned, and OpenSpec validation passes.
