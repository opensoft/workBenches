# Design: Triad Feature Amendment Workflow

## Context

The current shared protocol puts both OpenSpec and Speckit feature files in a triad's spec leg. workBenches distributes that protocol as text emitted by `devBenches/base-image/files/openspeckit/setup-openspeckit`; installed global files are created when missing and existing files are preserved. openRepoShape owns the placement classifier and copied, pinned shape instructions. OpenSpec supports local roots, registered docs stores and custom artifact schemas, but does not supply this cross-root reconciliation policy.

See [proposal](proposal.md) for the user decision and [capability delta](specs/triad-feature-amendments/spec.md) for required behavior.

## Goals / Non-Goals

**Goals:** Preserve proposal provenance and current implementation instructions; record small changes where agents encounter them; reconcile once after implementation; make root selection and project advancement explicit.

**Non-Goals:** Move canonical Speckit files into code, change existing approval authority, rewrite archived history, introduce another executable backlog, implement a new broker/runtime, or modify pinned consumer shape files.

## Decisions

### Two record layers with one governing baseline

The full docs proposal supplies scope and an immutable approved baseline. Local amendments hold deltas relative to it. Use `features/<NNN-feature>/openspec/` inside the code feature checkout as the narrow amendment home. A manifest names the docs repository, proposal ID/path, baseline commit, Speckit feature and reconciliation issue. It stores repository identities and relative paths, not workstation locations.

The alternative of copying complete feature/product specifications into code creates competing writable baselines. Keep working Speckit files in the paired docs checkout and apply accepted amendments there promptly.

### One final batch, with immediate working-spec updates

The docs proposal may accumulate several implementation-time deviations; the working spec and tasks cannot remain stale during that time. Update the working Speckit files per accepted amendment and defer full proposal/as-built reconciliation to the final batch. Calculate the final net effect from code and evidence, rather than applying every historical delta sequentially.

Use one reconciliation issue per feature. Issue state is coordination; Git records are durable evidence. Cancellation and behavior changes after reconciliation retain explicit records.

### Existing authority and an impact-based boundary

An amendment records a decision under existing user authorization or delegated authority. It does not confer new authority. Larger current scope follows full governance before dependent code; larger future ideas become linked future-proposal issues. Editorial fixes remain ordinary edits. The shortcut ends when a feature ships.

### Explicit root selection and a small future schema

Custom OpenSpec schemas can define an amendment record, deltas and evidence without an implementation task artifact. That schema and its integration remain pending. Manual records work immediately.

The docs and local roots must be explicit in commands and agent guidance. A nearest local planning root overrides a store pointer; references supply context rather than automatic reconciliation. Qualified store registration must target the appropriate docs feature checkout. Default archive behavior must never be mistaken for cross-root promotion.

### Preserve the assembly landing invariant

Prepare both leg PRs, reconcile the tested code and record its landed identity, then use the project's existing pin tooling. The assembly does not deliver the completed feature until it pins reconciled docs and matching code. Governing-change archive follows the landed assembly update; later archive-record pin advancement follows the ordinary process.

### Capture, adoption and automation have separate status

The brainstorm packet captures rationale and alternatives. The operating document records Brett's adoption, with a corresponding amendment to the installed global protocol. This documentation work does not edit the executable bootstrap, install a custom schema, modify classifiers or claim automated checks.

### Extend migration plans through existing owners

Single-to-triad migration retains `adopt-project.py` and its reviewed plan, history extraction and blob verification. Add artifact-role review for bounded amendment folders and explicit follow-up repair of baseline identities, links and root selection. Existing full proposals remain full proposals even when written on implementation branches. Use reviewed plan resolutions until the upstream classifier exception exists. Preserve open work and explicitly arrange paired-worktree continuation; selected-commit extraction does not cover every feature branch.

## Risks / Trade-offs

- [Working spec drifts while final reconciliation is deferred] → Apply accepted changes to Speckit immediately and reconcile the tested final result.
- [Nested root silently changes archive destination] → Explicitly select and inspect roots; maintain manual records until schema/routing qualification.
- [New workstations receive the old default] → Record distribution as pending and update bootstrap templates through a subsequent Speckit feature.
- [Code folder conflicts with current placement policy] → Carry the exact exception upstream in openRepoShape; preserve consumer pins until that change lands. Use a documented project-local override if manual use precedes upstream qualification.
- [Unreviewed scope is labeled small] → Classify by boundary impact and retain the decision source in each record.

## Migration Plan

1. Capture this discussion and adopt the manual instructions in the installed shared protocol.
2. Hand automation to one Speckit feature in workBenches, with cross-repository tasks referring to the owning openRepoShape proposal. Keep executable tasks out of OpenSpec.
3. Distribute protocol/template guidance, qualify the local schema and root routing, and implement the placement exception upstream.
4. Add diagnostics only after the records and invariants are established; openRepoProject can coordinate existing owners without duplicating their mechanics.
5. Apply the manual default to active features when an amendment actually arises. Preserve existing proposal history; do not retroactively invent amendment records or imply lane-swap tasks are done.

## Sources

- [Adopted workflow](../../../docs/triad-feature-amendments.md).
- [Conversation capture](../../../ideation/brainstorm/triad-feature-amendments-overview.md).
- [OpenSpec stores](https://openspec.dev/docs/stores) and [schemas](https://openspec.dev/docs/schemas).
