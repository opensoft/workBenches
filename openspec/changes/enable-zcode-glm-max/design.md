## Context

OmniRoute 16.3.1 publishes a local `zc/glm-5.3-max` alias and expects a `zcode app-server` child process. The official ZCode 3.10.1 Linux package contains desktop 3.10.1 and CLI 0.16.5. The CLI authenticates independently and stores its protected configuration in `~/.zcode`, but its current NDJSON protocol is not the legacy binary channel protocol implemented by this OmniRoute release.

ZCode desktop's authenticated Z.ai Coding Plan catalog defines `GLM-5.3` with reasoning variants `low`, `high`, and `max`, with `max` as the default. The CLI catalog was stale and initially exposed only GLM-5.1 and GLM-4.7. After synchronizing the desktop model definition, the native CLI accepted `{ providerId: "zai", modelId: "glm-5.3", variant: "max" }` and completed a live prompt as GLM-5.3 with Max effort.

## Goals / Non-Goals

**Goals:**

- Keep an official, user-local ZCode installation and protected Z.ai login available in WSL.
- Enable the route only after ZCode advertises GLM-5.3, accepts the `max` reasoning variant, and completes a live prompt.
- Prevent an unverified alias from entering the OpenCode catalog or agent roster.
- Preserve all unrelated provider credentials, account profiles, and sessions.

**Non-Goals:**

- Treat `max` as a separate model identifier or silently resolve the route to GLM-5.1.
- Patch OmniRoute's installed package or replay ZCode credentials through OmniRoute.
- Claim GLM-5.3 Max based on a plan/account name or marketing page rather than the consuming runtime's catalog.

## Decisions

1. Install ZCode under `~/.local/opt/zcode` and expose its bundled official CLI through `~/.local/bin/zcode`. This avoids requiring system-wide sudo and places the executable on OmniRoute's existing PATH.
2. Keep the ZCode desktop protocol handler pointed to the desktop executable while the shell command points to the CLI. The browser callback and headless CLI therefore use their intended entry points.
3. Treat ZCode's authenticated native catalog, native `session/setModel`, and a live completion as the source of truth. The verified selection is model `zai/glm-5.3` plus thought level `max`; `glm-5.3-max` is only an external convenience alias.
4. Leave OmniRoute's existing `zai/glm-5.3` API-key route separate from the ZCode Coding Plan route. Success on one does not prove that the other is Max.
5. Do not add the ZCode route to OpenCode while OmniRoute 16.3.1 times out against ZCode CLI 0.16.5's NDJSON app-server handshake.

## Risks / Trade-offs

- [ZCode catalog rollout changes by account or region] → Re-query the authenticated native catalog and record both model and thought level before enabling the route.
- [OmniRoute and ZCode app-server protocols remain incompatible] → Upgrade to a compatible OmniRoute/ZCode pair or use an upstream-supported adapter; do not retain an experimental local shim.
- [The `main` alias changes over time] → Record the resolved model ID in every verification and never infer that `main` means Max.

## Migration Plan

1. Retain the official ZCode installation, CLI configuration, and credentials with mode `0600`.
2. Retain the synchronized GLM-5.3 CLI model definition and its Max default.
3. Keep the current OpenCode roster unchanged while the OmniRoute handshake fails.
4. Upgrade OmniRoute or use an upstream-supported adapter for ZCode CLI 0.16.5, then repeat the exact completion through OmniRoute.
5. Only after that test passes, add the static OpenCode model entry and update the roster.

Rollback is removal of the user-local ZCode installation and desktop handler; no other provider state is coupled to it.

## Open Questions

- Which OmniRoute release officially supports ZCode CLI 0.16.5's NDJSON app-server protocol?
