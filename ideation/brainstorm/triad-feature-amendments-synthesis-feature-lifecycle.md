# Synthesis: Feature Amendment Lifecycle — Brainstorm

Status: brainstorm
Kind: process
Summary: Bounded local decisions and one final docs reconciliation allow a feature to evolve without losing its governing baseline or duplicating implementation tasks.
Topics: triad-feature-amendments, feature-lifecycle, feature-amendment, as-built-reconciliation, synthesis, doc-workflow
Repository context: workBenches shared workflow across triad docs, code and assembly repositories.
Captured: 2026-10-04

## Possible feats

- **Workflow integration** — Route amendment and full proposal commands to their intended roots and carry one reconciliation obligation through feature landing.

## Members and their joints

Atomic members: [local records](triad-feature-amendments-local-records.md) and [final reconciliation](triad-feature-amendments-final-reconciliation.md).

### Immediate instructions and deferred governing reconciliation

An accepted amendment changes the working feature spec and tasks immediately, so implementation uses current instructions. The final reconciliation consumes the records and tested code once, excluding inactive deltas. Keeping these two times distinct enables the user's desired batch without stale feature instructions.

### Shared identity and existing authority

Proposal ID, baseline commit and feature ID join code-local records to docs governance. Decision authority remains explicit. Larger current scope exits the shortcut into full governance; future ideas are linked but excluded. One issue tracks the accumulated obligation while Speckit remains the only executable task list.

### Root routing and project advancement

Each OpenSpec operation has an intended owner. A nearest local root can shadow a docs pointer, so neither implicit cwd nor local archive proves final reconciliation. Existing assembly pin tooling connects the reconciled docs commit to the delivered code commit.

## Emergent behavior

Agents can explain why tested behavior departed from the original proposal, while reviewers can inspect one final net change and its supporting history. The same records support recovery after a hard stop without claiming unfinished work is complete.

## Tensions to hold

Manual adoption is available before tooling delivery, but distribution and placement checks need their own implementation. A small amendment is defined by boundary impact rather than implementation size. The adopted manual workflow lives in [its separate decision record](../../docs/triad-feature-amendments.md); this synthesis remains non-normative.

## Recombination opportunities

Future `project` diagnostics could reuse these records to report reconciliation readiness. Lane recovery could use requirement/task references to identify what needs review. Neither integration is delivered here.
