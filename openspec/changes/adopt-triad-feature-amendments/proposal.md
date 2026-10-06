# Proposal: Triad Feature Amendments

## Why

A feature often needs several small specification adjustments during implementation. Repeating the full proposal lifecycle for each adjustment slows the work, while undocumented edits leave the original proposal behind the tested result.

## What Changes

- Keep full OpenSpec proposals and canonical specifications in the triad's docs/spec repository.
- Add a bounded feature amendment layer in the code feature folder. Each amendment links the governing proposal baseline, affected requirements and Speckit tasks, decision authority, implementation and evidence.
- Update the working Speckit feature specification in the paired docs worktree as each amendment is adopted. Speckit remains the only executable task list.
- Collect amendments under one docs reconciliation issue per feature and perform one final reconciliation of their net effect after implementation.
- Require the reconciled docs and corresponding code to land before the assembly advances the completed feature; archive after the assembly pin update lands.
- Route larger changes to a full docs proposal before dependent implementation, or record them for a future proposal when outside the current deliverable.
- Record the workflow as an adopted manual default; separately track the schema, bootstrap, placement and verification automation needed to support it.

## Capabilities

### New Capabilities

- `triad-feature-amendments`: bounded implementation-time amendments, baseline provenance, one final docs reconciliation and explicit OpenSpec root selection.

### Modified Capabilities

None. Existing shared CLI and profile capabilities do not define this workflow.

## Impact

workBenches owns the shared agent protocol distribution through `setup-openspeckit`. The workflow also affects openRepoShape placement rules, OpenSpec command/skill guidance, Speckit feature records and future openRepoProject inspection. Existing lane-swap implementation is a consumer; this change has its own governance branch and does not expand that feature.

The current repositories owning these tools are single repositories. Their full proposals remain at their own OpenSpec roots; a triad consumer places full proposals in its declared spec leg.

## Decision and delivery state

Brett Heap directed adoption on 2026-10-04: "document this. lets use this for our triad repo and project workflow."

This authorizes the documented workflow and manual use. It does not establish that automation is implemented or tested. The supporting brainstorm packet remains non-normative; the adopted operating instructions are in [the workflow](../../../docs/triad-feature-amendments.md).
