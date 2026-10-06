# Triad Feature Amendments Overview — Brainstorm

Status: brainstorm
Kind: reference
Summary: Full docs proposals, code-local feature amendments and one final reconciliation preserve governance while allowing small implementation-time specification updates.
Topics: triad-feature-amendments, doc-workflow, openspec, speckit, triad, project-workflow
Repository context: workBenches shared agent protocols with openRepoShape and openRepoProject consumers.
Captured: 2026-10-04

## Possible feats

- **Triad amendment support** — Deliver the schema, protocol distribution, placement exception and reconciliation diagnostics through their existing owners.

## Motivation

Brett observed that full proposals must live in the docs repository, while small feature-spec changes often arise during implementation. He proposed a second local layer, multiple retained updates and one backward reconciliation into the original proposal after implementation. Larger ideas can become future-proposal issues.

## Goals

- Preserve an identifiable governing baseline and the reasons for changes.
- Keep working feature instructions current.
- Keep full proposals and canonical specs in docs.
- Review the tested net result in one final reconciliation.
- Deliver matching docs and code through the assembly's existing pins.

## Non-goals

Moving canonical Speckit files into code, replacing approval authority, generating a second executable backlog or implementing lane swap/broker mechanics is outside this packet.

## What the system delivers

The intended workflow supplies bounded local amendment records, one reconciliation obligation, a clear larger-scope path and an as-built docs record. Manual use was subsequently adopted by Brett's instruction; this brainstorm packet records the reasoning and remains non-normative. The actual operating decision and its delivery limits are in [the workflow](../../docs/triad-feature-amendments.md).

## System model

```text
Docs proposal + approved baseline
  -> working Speckit feature + code implementation
  -> bounded code-local amendments; current feature files updated in docs
  -> one final docs reconciliation against tested code
  -> matching assembly pins
  -> governing-change archive
```

## Cluster map

- [Feature lifecycle synthesis](triad-feature-amendments-synthesis-feature-lifecycle.md) joins immediate working-spec updates, amendment provenance and final project landing.

## How it fits

workBenches ships shared agent protocols. openRepoShape owns the placement exception and pin mechanics. OpenSpec provides root/store selection and customizable schemas; Speckit owns executable tasks. openRepoProject can later coordinate diagnostics through these owners. The lane-swap feature remains a consumer with its existing outstanding tasks.

For a single-to-triad migration, the discussion adds placement review and reconciliation follow-ups to the existing adoption process. Full proposals and Speckit files go to docs, genuine local amendments go to code, and baseline/link/root identities are repaired with verified provenance. Existing history extraction and migration approvals continue through openRepoShape.

## Key decisions and delivery limits

The docs/spec leg retains both full proposals and canonical Speckit feature files. The optional code amendment folder contains deltas, not complete competing specs. Impact determines whether a change stays local or needs full governance. Working specs update immediately; full reconciliation batches once at completion. Automated schema, routing, placement checks and diagnostics remain pending, with manual instructions adopted now.

## Document map

- Synthesis: [feature lifecycle](triad-feature-amendments-synthesis-feature-lifecycle.md).
- Atomic: [local amendment records](triad-feature-amendments-local-records.md).
- Atomic: [final docs reconciliation](triad-feature-amendments-final-reconciliation.md).
- Operating decision: [workflow](../../docs/triad-feature-amendments.md).
- Manual starting points: [templates](../../docs/triad-feature-amendment-templates.md).
- Governance: [full workflow change](../../openspec/changes/adopt-triad-feature-amendments/proposal.md).
