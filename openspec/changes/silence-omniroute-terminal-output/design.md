## Context

OpenCode loads the local `@omniroute/opencode-plugin` alongside a separately governed static `omniroute` provider. The plugin successfully reads `/v1/models`, but its default `combos`, `autoCombos`, and enrichment features call management endpoints using the inference key. Those calls return `403 Forbidden`. Its five-minute background sync writes the warning, stack trace, and catalog-change diagnostics directly to the interactive terminal, corrupting OpenCode's Wave display.

The installed plugin explicitly supports `autoSyncIntervalMs: 0`, individual feature switches, and `features.logLevel`. The governed OMO roster uses the static provider IDs, so its inference paths do not depend on background combo discovery.

## Goals / Non-Goals

**Goals:**

- Stop periodic OmniRoute plugin text from appearing inside OpenCode's interactive terminal.
- Preserve live `/v1/models` discovery, the cached catalog, and all governed inference routes.
- Avoid granting an inference client broader OmniRoute management permissions merely to quiet expected authorization failures.

**Non-Goals:**

- Removing OmniRoute from OpenCode.
- Changing the OmniRoute API key or creating a management token.
- Hiding genuine inference errors.
- Changing OMO model assignments, account selection, or session storage.

## Decisions

### Disable background sync

Set `autoSyncIntervalMs` to `0`, the plugin's documented off value. The live catalog can still refresh through its on-demand TTL and the explicit `omniroute_sync_models` tool.

Alternative considered: retain five-minute polling and redirect stderr. This would hide all OpenCode/plugin diagnostics indiscriminately and leave repeated unauthorized network calls running.

### Disable management-only discovery features

Set `features.combos`, `features.autoCombos`, and `features.enrichment` to `false`. Also leave compression metadata and usable-provider filtering off because they depend on management endpoints. Keep `diskCache` enabled and ordinary `/v1/models` discovery intact.

Alternative considered: provide `managementReadToken`. The user has not requested combo administration, and broadening credential scope is unnecessary for the active roster.

### Log only actionable plugin errors

Set `features.logLevel` to `error` while keeping `debugLog` and `startupDebug` false. This suppresses startup/catalog chatter and expected management warnings but preserves genuine errors from inference-safe paths.

Consumer testing revealed two defects in the installed plugin build: initialization uses an unconditional `logger.always` call before applying the configured level, and the backward-compatible config shim fetches `/api/combos` without checking `features.combos`. Apply a narrow local patch that changes initialization to level-aware `info` logging after the level is set and gives the config-shim fetch the same `wantCombos` guard already used by the provider and force-sync paths.

Alternative considered: remove the dynamic plugin. This would be quieter but would discard the full `/v1/models` catalog and leave only the small governed static roster. The narrow patch preserves more functionality.

## Risks / Trade-offs

- [New models do not appear immediately during a long-running session] -> Use `/omni-sync` when an immediate catalog refresh is needed, or restart OpenCode; normal on-demand TTL refresh remains available.
- [OmniRoute combos disappear from the dynamic picker] -> The current inference key cannot read them, and the governed OMO roster does not use them.
- [A genuine plugin error is still printed] -> Intentional; `error` logging remains enabled so real failures are not silently hidden.
- [A plugin package update overwrites the local defect patch] -> Keep the exact patch documented in this OpenSpec change and repeat the consumer-level quiet test after updating the package.

## Migration Plan

1. Update only the OmniRoute plugin options in `~/.config/opencode/opencode.json`.
2. Parse the resulting JSON.
3. Launch a fresh profile-aware OpenCode command and capture output to confirm no OmniRoute startup or combo warnings appear.
4. Run a governed OmniRoute model call to verify inference is unchanged.
5. Restart the already-running Wave/OpenCode process once to load the new options.

Rollback by restoring `autoSyncIntervalMs: 300000` and removing the explicit feature overrides.

## Open Questions

None.
