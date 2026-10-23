## ADDED Requirements

### Requirement: Four combinable harness columns
The CLI harness screen SHALL display exactly four filter columns: Type, Region, Access and Native, above live results. Each SHALL select one value; dimensions SHALL combine with AND. Type SHALL default to curated Frontier lab membership on a new session, with other columns All. Type SHALL also offer Open, Closed, All and Unknown. Open/Closed SHALL describe qualified supported open-weight/closed models independently from the harness license and Frontier ownership; a harness may match both. Unknown SHALL remain explicit. Native and routed capabilities SHALL retain separate qualified metadata in About; Via and Group SHALL NOT appear as additional filters.

#### Scenario: Default and combine
- **WHEN** a new wizard session visits CLI harnesses
- **THEN** Type is Frontier and the other three columns are All
- **AND WHEN** Region China, Access API and Native Video are selected
- **THEN** only entries satisfying every selected column remain
- **AND** routed-only video does not satisfy Native Video

### Requirement: Cycling columns and safe results
F SHALL move focus between filters and results. In filter focus Left/Right or Tab/Shift+Tab SHALL wrap between columns; Up/Down SHALL wrap values and immediately update results. Space SHALL advance the current value and D SHALL do nothing. Outside filter focus Left/Right SHALL retain step navigation; Enter SHALL retain Review. C SHALL clear all four columns to All without changing queues. Empty results SHALL have a clear explanation and no stale product action or About.

#### Scenario: Cycle and clear an empty result
- **WHEN** the user cycles Native to Classifier and no entries match
- **THEN** the result list is empty and hidden installation actions cannot change
- **AND WHEN** the user presses C
- **THEN** all 77 entries return and queued changes remain

### Requirement: State and rendering compatibility
P/G and refresh SHALL preserve column values/focus and product/result/About state. Ordinary step navigation SHALL retain filter values. All four headings/current values and filter focus SHALL remain visible within existing locale/size bounds. Matching/rendering SHALL use cached Bash data and no subprocesses. Qualified model-weight evidence SHALL validate and compile deterministically; installation/credential-plan contracts SHALL remain unchanged.

#### Scenario: Return to a filtered product
- **WHEN** the user pages About after setting filters, visits Profiles or Workstation and returns
- **THEN** column values/focus, selected product, list/About offsets and queue return intact
