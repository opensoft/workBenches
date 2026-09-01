## ADDED Requirements

### Requirement: Quiet interactive operation
The OpenCode OmniRoute plugin SHALL NOT run background model-catalog polling and SHALL suppress non-error startup, catalog, and synchronization diagnostics in interactive terminals.

#### Scenario: OpenCode starts in Wave
- **WHEN** a new profile-aware OpenCode process loads the OmniRoute plugin
- **THEN** the terminal receives no OmniRoute initialization, auto-sync, catalog-change, or management-warning output

### Requirement: Plugin feature flags are honored by all catalog paths
The installed plugin's startup and backward-compatible config-shim paths SHALL honor `features.logLevel` and `features.combos` consistently with its provider and force-sync paths.

#### Scenario: Quiet options are active during an inference run
- **WHEN** OpenCode exercises both plugin initialization and the config shim
- **THEN** initialization is filtered by the configured log level and `/api/combos` is not requested when `features.combos` is false

### Requirement: No unauthorized management polling
The plugin MUST NOT request combo, automatic-combo, enrichment, compression-metadata, or usable-provider management data with the current inference-only credential.

#### Scenario: OpenCode remains running beyond five minutes
- **WHEN** the former background synchronization interval elapses
- **THEN** no `/api/combos`, `/api/combos/auto`, pricing, compression, or provider-management request is initiated by background polling

### Requirement: Inference and model discovery remain available
The configuration SHALL retain OmniRoute `/v1/models` discovery, disk caching, the governed static provider, and existing inference routes.

#### Scenario: Governed model is invoked after the quiet configuration loads
- **WHEN** `popencode max001` invokes a configured `omniroute` model
- **THEN** the model returns a successful response without plugin diagnostics corrupting the terminal

### Requirement: Explicit refresh remains available
The configuration SHALL retain the plugin's on-demand catalog TTL and explicit synchronization tool for operator-initiated refreshes.

#### Scenario: Operator needs an immediate catalog refresh
- **WHEN** the operator explicitly invokes `/omni-sync` or restarts OpenCode
- **THEN** the plugin can refresh `/v1/models` without re-enabling periodic background polling
