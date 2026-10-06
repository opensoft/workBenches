# Feature Amendment Records — Brainstorm

Status: brainstorm
Kind: process
Summary: A feature-local amendment record preserves bounded specification decisions beside the implementation while the working feature files remain in docs.
Topics: triad-feature-amendments, feature-amendment, doc-workflow, openspec, speckit
Repository context: workBenches shared agent workflow, consumed by triad projects.
Captured: 2026-10-04

## Possible feats

- **Small amendment schema** — Generate the decision, requirement deltas and evidence references without another implementation task list.

## Focus

An agent implementing a feature needs to record small adjustments without repeating a complete proposal cycle. Brett suggested a second proposal layer inside the code feature folder, with several updates retained for one reconciliation at the end.

## Captured model

The full docs proposal establishes the scope. The code feature contains `features/<NNN-feature>/openspec/`, with a manifest and individually identified amendment records. Each record names the docs proposal and immutable baseline, affected requirements/contracts and Speckit tasks, the reason and revised interpretation, decision authority/source, verification impact and final disposition.

Accepted amendments update the working Speckit files in the paired docs worktree immediately. Requirement deltas stay local until full reconciliation; canonical product specs remain in docs. Proposed and deferred changes are not current feature requirements. Git preserves superseded and reverted records.

## Interfaces and boundaries

One reconciliation issue is shared by all amendments in the feature. Speckit retains executable tasks. The code folder is an explicit narrow placement exception and gains no independent approval authority. Larger current scope goes through full docs governance; larger future ideas receive a future-proposal issue. The shortcut applies to an active feature, not later changes to shipped behavior.

## Alternatives and tensions

Repeating the full proposal for every small change provides more repeated review but slows implementation. Unrecorded feature edits are cheap immediately and costly during later review. Copying complete specs into code introduces two writable baselines; retaining the working Speckit files in docs avoids that ambiguity.

## Delivery distinction

This file captures the discussion and remains non-normative. Brett subsequently directed adoption in this conversation; [the separate operating workflow](../../docs/triad-feature-amendments.md) records that decision. A custom schema and distribution changes remain pending.

## Relationships

- [Final reconciliation](triad-feature-amendments-final-reconciliation.md) consumes the records and final dispositions.
- [Synthesis](triad-feature-amendments-synthesis-feature-lifecycle.md) explains their joint lifecycle.
