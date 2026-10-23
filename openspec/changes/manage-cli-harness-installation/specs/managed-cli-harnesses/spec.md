## ADDED Requirements

### Requirement: Source-qualified terminal installers
Each terminal catalog entry SHALL have an audited upstream distribution identity
and platform-aware recipe, or an explicit unavailable/needs-source reason.
Only verified recipes SHALL become actionable managed selection keys. A similarly
named registry package SHALL NOT establish product identity.

#### Scenario: A terminal product becomes managed
- **WHEN** a verified CLI is selected for installation/update/removal
- **THEN** Review shows the exact product, action and workstation/bench targets
- **AND** Apply performs the action and reports runnable installation separately from authentication

### Requirement: Transactional installation and preservation
Installers SHALL use owned prefixes and receipts, preserve existing defaults,
credentials and projects, retain the previous runnable install on failure, refuse
foreign launcher replacement and delete only validated owned artifacts.

#### Scenario: An update fails
- **GIVEN** an installed managed harness and unrelated account data
- **WHEN** downloading, building or verifying a replacement fails
- **THEN** the prior runnable harness and account data remain intact
- **AND** the failure is reported without a successful installation status

### Requirement: Workstation and selected bench scope
Installers SHALL target the workstation and only reviewed selected benches.
Bench changes SHALL use validated local Docker resources without stopping live
sessions. Desired tools SHALL survive personalized image recreation; missing,
stopped and foreign targets SHALL have explicit outcomes.

#### Scenario: A selected bench is recreated
- **GIVEN** a reviewed desired harness list for that bench
- **WHEN** its personalized image is rebuilt and its container recreated
- **THEN** the requested harnesses are available in that bench
- **AND** unselected benches, projects and credential stores are preserved

### Requirement: Compatible wizard behavior
Catalog filters, scrolling, selection persistence, immediate first paint and
fork-free rendering SHALL remain intact. GUI/editor/extension inventory and
existing managed CLI behavior SHALL remain separate and compatible.

#### Scenario: Filter an already queued harness
- **WHEN** filters hide a selected terminal harness and the user opens Review
- **THEN** its queued action and reviewed targets remain visible and correct
