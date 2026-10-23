## ADDED Requirements

### Requirement: Independent, combinable harness facets
The CLI harness screen SHALL filter by curated Frontier lab membership, region, subscription/API/local access, native LLM/image/video/voice/classifier capabilities, separately routed model/plugin capabilities, and the existing catalog group. Multiple values within a dimension SHALL match with OR; active dimensions SHALL combine with AND. Subscription/API SHALL NOT be mutually exclusive product classifications. Frontier SHALL NOT be inferred from provider access. Unknown SHALL remain explicit. Capability records SHALL qualify input/generation scope and external integration requirements.

#### Scenario: Combine ownership, access and native capability
- **WHEN** the user selects Frontier, USA, API and native Image
- **THEN** results contain only entries matching every active dimension
- **AND** routed-only image support does not satisfy native Image

### Requirement: Filter panel and result safety
F SHALL open/close Filters, Up/Down SHALL choose a row, Tab/Shift+Tab SHALL focus an option, Space SHALL toggle/select it, and C SHALL clear only filters. Counts SHALL update immediately. Left/Right SHALL retain step navigation and Enter SHALL retain Review semantics. Result filtering SHALL preserve queued installation changes. Empty results SHALL have a clear explanation and no action or About for a stale hidden product.

#### Scenario: Clear an empty result
- **WHEN** a filter combination yields no matches and the user presses Space or D
- **THEN** no hidden component action is changed
- **AND WHEN** the user presses C
- **THEN** all entries return and previously queued changes remain

### Requirement: State, rendering and catalog compatibility
P/G and refresh SHALL preserve all facets, group, filter focus/options and result/About offsets. Result lists and filter rows SHALL retain visible focus within the existing locale/size bounds. Matching/rendering SHALL use cached Bash data and no subprocesses. Internal catalog schema 2 SHALL validate facet metadata and generate deterministic snapshots; installation/credential-plan contracts SHALL remain unchanged.

#### Scenario: Return to a filtered product
- **WHEN** the user pages About after setting multiple filters, visits Profiles or Workstation and returns
- **THEN** filter values, selected product, list/About offsets and queue return intact
