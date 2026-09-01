## Why

The OmniRoute OpenCode plugin is polling management-only combo endpoints with an inference API key. The resulting periodic `403 Forbidden` warnings and stack traces are written into OpenCode's interactive terminal UI, obscuring prompts and responses in Wave.

## What Changes

- Disable background OmniRoute model-catalog polling inside OpenCode.
- Disable combo, automatic-combo, and management enrichment discovery that the current key cannot authorize.
- Retain the live `/v1/models` catalog, disk cache, the governed static `omniroute` provider, and all inference routes.
- Reduce plugin logging to errors and validate that a fresh OpenCode process produces no OmniRoute startup or background warning output.

## Capabilities

### New Capabilities

- `quiet-omniroute-plugin`: Defines quiet, inference-safe OmniRoute plugin behavior for interactive OpenCode terminals.

### Modified Capabilities

None.

## Impact

- Updates `~/.config/opencode/opencode.json` plugin options.
- Does not change OmniRoute or OpenAI credentials, model assignments, provider endpoints, or OpenCode sessions.
- Already-running OpenCode processes require one restart to load the new plugin options.
