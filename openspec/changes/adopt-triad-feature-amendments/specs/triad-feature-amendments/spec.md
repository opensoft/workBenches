# Triad Feature Amendments

## Purpose

Allow bounded specification adjustments during an active feature while retaining docs-repository governance, a single implementation task list and a reproducible final reconciliation.

## ADDED Requirements

### Requirement: Canonical docs and bounded local amendments

The workflow SHALL keep full OpenSpec proposals, canonical capability specifications and Speckit feature files in the declared docs/spec leg of a triad. It SHALL permit only feature-scoped amendment records, deltas and evidence references in the code feature amendment folder. This placement SHALL preserve the existing decision authority and SHALL NOT confer approval authority on a repository or a local amendment.

#### Scenario: Small adjustment during a triad feature

- **WHEN** implementation discovers a requirement refinement within approved feature boundaries
- **THEN** the amendment is recorded beside the code and the working Speckit files are updated in the paired docs worktree
- **AND** the canonical product specifications retain their docs-repository home

#### Scenario: Single repository consumer

- **WHEN** the same workflow is used in a single repository
- **THEN** full proposals and Speckit feature files retain their established repository roots
- **AND** the feature amendment folder remains a bounded record layer

### Requirement: Amendment provenance and current instructions

Every accepted feature amendment MUST identify its feature, governing proposal, immutable approved docs baseline, affected requirements/contracts and Speckit tasks, decision authority and source, verification impact and final disposition. The working feature specification and affected plan, acceptance criteria and tasks MUST reflect accepted amendments before dependent implementation. Superseded, reverted and deferred records MUST remain traceable. The workflow MUST retain Speckit as the only executable implementation task list.

#### Scenario: Several successive refinements

- **WHEN** a feature accumulates multiple accepted amendments and one later supersedes another
- **THEN** the working feature files describe the latest accepted behavior
- **AND** both amendment records remain linked with explicit dispositions
- **AND** executable implementation work exists only in Speckit tasks

#### Scenario: Proposed change lacks authority

- **WHEN** an amendment records a proposed change without an applicable authorization
- **THEN** it remains proposed and is not applied to the current feature requirements

### Requirement: Change classification and escalation

The workflow SHALL use ordinary feature edits for editorial or implementation-only changes preserving specified behavior. It SHALL use feature amendments for bounded changes within approved scope. Larger scope, capability, runtime, authority or external contract changes MUST enter full docs governance before dependent implementation, or be deferred into a linked future-proposal issue and excluded from the current deliverable. Changes to shipped features MUST use normal full OpenSpec governance.

#### Scenario: Larger idea discovered during implementation

- **WHEN** a feature discovers a new capability unnecessary for its current deliverable
- **THEN** the idea is linked to a future full-proposal issue
- **AND** current feature requirements and tasks exclude that deferred capability

#### Scenario: Mandatory new runtime dependency

- **WHEN** completing a feature requires a runtime boundary outside its approved proposal
- **THEN** the full docs proposal is amended or a new full proposal is approved before dependent implementation

### Requirement: One final docs reconciliation

The workflow MUST collect amendments under one reconciliation issue in the docs repository, created at the first amendment. After implementation and verification, it MUST reconcile their net effect in one final docs batch against the actual tested code. The reconciliation MUST cover every amendment disposition, preserve approved history, update governing specs/contracts/design, identify the corresponding landed code commit and link verification and deferred work. An issue MUST NOT replace durable Git records or duplicate executable tasks.

#### Scenario: Amendment is later reversed

- **WHEN** the final reconciliation encounters an implemented change that was subsequently reverted
- **THEN** the reversal remains visible in the reconciliation history
- **AND** the inactive delta is excluded from the final governing behavior

#### Scenario: Archived original proposal

- **WHEN** the governing proposal is already archived
- **THEN** reconciliation uses a linked change or record and preserves the archived approval history

### Requirement: Reconciled project landing and closure

The docs reconciliation and corresponding code MUST land before the assembly advances the completed feature to that code. The assembly MUST pin the matching leg commits through its existing pin mechanism. The governing change MUST NOT archive before implementation and the assembly pin update land. Behavior changes after reconciliation MUST reopen reconciliation. Cancellation MUST record abandonment rather than claim an as-built implementation.

#### Scenario: Code lands before docs reconciliation

- **WHEN** the code PR lands while the reconciliation PR is still open
- **THEN** the assembly does not advance the completed feature to that code
- **AND** the docs record is updated to the landed code identity before project advancement

#### Scenario: Feature is abandoned

- **WHEN** the feature is cancelled before delivery
- **THEN** its records identify abandonment and amendment dispositions
- **AND** no completed implementation is claimed

### Requirement: Explicit OpenSpec root routing

Full proposal operations MUST select the intended docs checkout. Local amendment operations MUST select the feature amendment root. Root selection and archival MUST NOT implicitly promote local deltas into canonical specs or treat local archival as docs reconciliation. A registered store selection MUST resolve to the intended feature checkout and branch. A local amendment schema MUST NOT create a second executable task list. Until the schema and routing are qualified, agents SHALL maintain records manually.

#### Scenario: Nested local root overrides a store pointer

- **WHEN** a code feature has a local planning root and its repository also declares a docs store
- **THEN** the agent explicitly selects and verifies the intended root for each operation
- **AND** a local archive does not satisfy the docs reconciliation or project landing requirements

### Requirement: Single repository migration preserves artifact roles and provenance

A single-repository-to-triad migration MUST place full proposals, archives, canonical capability specs and Speckit feature files in the docs/spec leg, and genuine bounded feature amendment records in the code leg. It MUST retain existing migration approval, history and per-path verification mechanics. It MUST preserve the original approved baseline identity and record verified correspondence where extraction changes repository paths or commit identities. Open branches/worktrees MUST be preserved and explicitly planned; migration of the selected source commit MUST NOT imply they have all migrated.

#### Scenario: Existing proposal was authored on a feature branch

- **WHEN** the source repository contains a full governing proposal created on a feature branch
- **THEN** its role remains a full docs proposal after migration
- **AND** it is not reclassified as a bounded local amendment solely because of its branch

#### Scenario: Amendment folder exists before migration

- **WHEN** the adoption plan includes genuine feature-local amendment records
- **THEN** they are assigned to the code leg by the qualified exception or an explicit reviewed plan resolution
- **AND** the docs baseline correspondence and cross-leg references are verified after extraction

### Requirement: Adoption and automation are distinct delivery states

Documentation MUST distinguish the adopted manual workflow from delivered automation. Protocol distribution, managed command/skill guidance, shape placement checks and reconciliation diagnostics MUST remain recorded as pending until implemented and verified by their owning repositories. Consumers MUST NOT modify pinned shape copies or adjust pin digests to accommodate the new folder.

#### Scenario: Current workstation uses the new manual default

- **WHEN** the installed shared protocol is amended following the user's adoption instruction
- **THEN** agents can follow the manual workflow immediately
- **AND** the record does not claim that new installations or automated gates already implement it
