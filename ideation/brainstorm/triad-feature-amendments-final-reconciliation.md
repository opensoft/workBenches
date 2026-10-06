# Final Docs Reconciliation — Brainstorm

Status: brainstorm
Kind: process
Summary: One final reconciliation brings the governing docs into agreement with tested code while preserving amendment history and matching assembly pins.
Topics: triad-feature-amendments, as-built-reconciliation, doc-workflow, openspec, project-pins
Repository context: workBenches shared workflow with openRepoShape project landing mechanics.
Captured: 2026-10-04

## Possible feats

- **Reconciliation report** — Summarize all amendment dispositions and compare the working feature against governing docs and tested code.

## Focus

Several local changes can cancel or supersede each other. The governing proposal needs the tested net result rather than a mechanical replay of every historical edit.

## Captured model

At the first amendment, open one reconciliation issue in the docs repository. Append subsequent amendment links. After implementation and verification, prepare one docs reconciliation PR covering every disposition, the final requirements/contracts/design, corresponding code commit and evidence, and any larger ideas deferred to future proposals.

Preserve the original approved baseline. Record departures in dated amendments and an as-built record. An already archived proposal retains its historical content; a new linked change records later work.

## Interfaces and boundaries

The issue coordinates reconciliation; Git retains durable records. The code PR can land first, but the assembly delivers the completed feature only when matching reconciled docs and code are pinned through existing tooling. Archive follows implementation and the assembly update. A later behavioral change reopens reconciliation. Abandonment is explicit and makes no as-built claim.

## Alternatives and tensions

Continuous full reconciliation keeps governing prose current but repeats work for adjustments later reversed. Final-only updates to every document leave implementation instructions stale; the selected combination updates working Speckit files promptly and reconciles the governing proposal once.

## Tooling boundary

OpenSpec supports separate roots/stores, but it does not automatically aggregate our amendment history or coordinate Git landing across the triad. Local default archive can target the wrong store; the routing needs explicit qualification.

## Delivery distinction

This capture remains non-normative. [The operating workflow](../../docs/triad-feature-amendments.md) records the user-directed manual adoption; automatic reconciliation and diagnostics remain future work.

## Relationships

- [Local records](triad-feature-amendments-local-records.md) supply provenance and current instructions.
- [Synthesis](triad-feature-amendments-synthesis-feature-lifecycle.md) connects amendment authority and closure.
