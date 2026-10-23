## ADDED Requirements

### Requirement: Stable product catalog and separate surfaces
The wizard SHALL represent the distinct products in Brett's supplied inventory, preserving managed IDs and installer plans. Standalone GUI agents, CLI/TUI agents, IDEs/editors, editor integrations, terminal workspaces and specification/workflow tools SHALL be differentiated. CLI execution modes SHALL be fields, not duplicate products. Distinct Kimi generations, Qoder SKUs/operators and independently shipped GUI/editor integrations SHALL remain separate.

#### Scenario: Distinguish product surfaces
- **WHEN** the user browses Codex GUI, Codex CLI/TUI and its editor extension
- **THEN** each appears in its appropriate category, with distinct installation evidence and no IDE classification for the standalone agent

### Requirement: Ownership groups and qualified capability fields
CLI browsing SHALL provide model-maker groups by USA/China/Other, open/BYOK and commercial/managed combo groups, and specialized/research/minimal products. Relationship, region, model policy, interface modes, execution location, status, lineage and extra surfaces SHALL remain separate metadata. Products spanning roles SHALL have multiple tags. Interoperability SHALL be precise fields, not a top-level interface category. Unknown capabilities SHALL remain unverified, not unavailable. User-provided claims and independently documented claims SHALL be distinguished.

#### Scenario: Provider-flexible model maker
- **WHEN** the user selects Qwen Code
- **THEN** ownership grouping remains model-maker China while model policy independently records provider flexibility

#### Scenario: Distinguish invocation from session transfer
- **WHEN** a product can start another CLI but cross-product session transfer has not been verified
- **THEN** About records subprocess invocation separately from state/session exchange and does not imply session transfer

### Requirement: Private-plan and rendering compatibility
Catalog expansion SHALL NOT add install/apply keys, invoke agents, authenticate, or modify the host. Manual entries SHALL remain unselectable and rejected by existing plan validators. Canonical metadata SHALL validate and generate deterministic runtime snapshots; rendering SHALL use only cached Bash builtins and retain responsive bounds. CLI group selection and scroll/focus state SHALL survive P/G and refresh without changing queues.

#### Scenario: Browse a supplied unverified product
- **WHEN** the user selects a product whose install/ownership or capabilities are unverified
- **THEN** About explicitly qualifies that metadata, status requires manual checking where detection is ambiguous, and Space/D cannot queue it

#### Scenario: Return to a filtered CLI list
- **WHEN** the user selects a CLI ownership group, pages About, visits Profiles or Workstation and returns
- **THEN** group, category, zone, item and scroll state return intact, and every queued managed change remains unchanged
