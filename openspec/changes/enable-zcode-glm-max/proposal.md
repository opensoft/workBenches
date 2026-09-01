## Why

OmniRoute advertises `zc/glm-5.3-max`, but `Max` is a reasoning-effort variant of the `GLM-5.3` model, not a separate model. The route must select `GLM-5.3` with `variant: max` through the official authenticated ZCode runtime before OpenCode can rely on it.

## What Changes

- Install the official Linux x64 ZCode package in Ubuntu 24.04 under WSL.
- Ensure `zcode` is resolvable from the exact PATH used by the OmniRoute service.
- Complete ZCode onboarding and Z.ai authentication without copying credentials into OmniRoute.
- Synchronize the desktop catalog's `GLM-5.3` definition into the authenticated CLI catalog and verify the `max` thought level natively.
- Verify the ZCode-backed route through OmniRoute after its app-server protocol is compatible.
- Register the verified GLM-5.3-with-Max-effort route in OpenCode and update the local model roster only after end-to-end validation succeeds.

## Capabilities

### New Capabilities

- `zcode-glm-max-routing`: Provide a verified OpenCode-to-OmniRoute-to-ZCode route for GLM-5.3 Max using the local ZCode profile.

### Modified Capabilities

None.

## Impact

This affects the WSL ZCode desktop/runtime installation, the user-local ZCode profile, OmniRoute model execution, OpenCode's custom model catalog, and the documented Oh My OpenCode roster. Existing OpenAI, Alibaba, Z.ai API, Claude, and session credentials remain unchanged.
