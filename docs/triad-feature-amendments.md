# Triad Feature Amendment Workflow

Status: adopted manual workflow
Kind: process
Decision: Brett Heap, 2026-10-04, in the triad/project workflow discussion.
Governance: [adopt-triad-feature-amendments](../openspec/changes/adopt-triad-feature-amendments/proposal.md).
Owner: workBenches distributes the shared agent protocols; openRepoShape owns placement mechanics; product decisions retain their existing approval authority.

## Purpose

Keep full proposals in the docs/spec repository while allowing bounded specification adjustments during feature implementation. Record each adjustment beside the code, keep the working feature specification current, and reconcile the accumulated changes into the governing documents once implementation finishes.

This is the preferred default for triad project work. Manual use is adopted. The automatic amendment schema, routing helpers, placement checks and reconciliation checks are not delivered by this documentation change.

## Placement and authority

| Artifact | Location in a triad |
|---|---|
| Full proposal, governing capability specs, contracts and proposal archive | Declared docs/spec leg, `openspec/` and its existing document paths |
| Working Speckit spec, plan, acceptance criteria and the single executable task list | Feature's docs worktree, `specs/<NNN-feature>/` |
| Lightweight amendments, local requirement deltas and evidence references | Feature's code worktree, `features/<NNN-feature>/openspec/` |
| Reconciliation record and updated governing documents | Feature's docs worktree; land in the docs repository |
| Manifest, tools, pins and project advancement | Assembly root |

The local amendment folder is a narrowly scoped placement exception. It holds changes relative to a named docs baseline, not an independently authoritative copy of product specs. Keep canonical Speckit feature files in the docs leg. Moving those files into code requires a separate placement decision.

In a single repository, keep full proposals and Speckit feature files at their established roots. The same optional `features/<NNN-feature>/openspec/` amendment folder can separate implementation-time records. Do not turn a single-repository project into a triad solely to use this workflow.

All paths are relative to their owning checkout. Resolve the actual leg mount paths from `project.yaml`; do not assume their names or store workstation paths in tracked records.

## Choose the change path

| Change discovered during implementation | Action |
|---|---|
| Editorial fix or implementation detail that preserves specified behavior | Ordinary feature edit; explain it in Git |
| Clarification or requirement adjustment within the approved feature boundaries | Create a feature amendment and update the working Speckit files |
| New capability, substantial scope, mandatory runtime dependency, authority/security change or cross-project contract change | Full docs proposal or explicit amendment to the full proposal before dependent implementation |
| Larger idea that is unnecessary for the current deliverable | Future-proposal issue, linked from the feature and excluded from its current requirements/tasks |
| Change to an already shipped feature | Normal full OpenSpec change; the active-feature shortcut has ended |

Classification follows impact, not line count. Existing user authorization and delegated decision authority continue to apply. A local record cannot supply approval that the decision maker has not given. A small contract refinement within already approved boundaries can use an amendment; a new external obligation escalates to the full docs proposal.

For example, a mandatory Omnigent launch dependency changes a runtime boundary and belongs in full governance. A separate broker mode deferred beyond swap belongs in a future proposal. Neither becomes a small amendment merely because it was discovered on the swap branch.

## Start the feature

Record the governing docs repository, change ID/path and approved baseline commit in the feature. Identify the paired docs and code branches/worktrees and the Speckit feature ID. Feature-local records inherit their scope from that baseline and any subsequently approved full-proposal amendments.

Illustrative layout, with the default leg mount names:

```text
worktrees/NNN-feature/
  spec/
    openspec/changes/governing-change/
    specs/NNN-feature/
  code/
    features/NNN-feature/openspec/
      manifest.yaml
      changes/001-refine-acceptance/
        amendment.md
        specs/affected-capability/spec.md
```

The local `specs/` under a change holds requirement deltas. It is not a second complete baseline. An evidence section can link existing test reports and implementation commits; separate evidence files are optional.

## Record a bounded amendment

1. Assign an amendment ID unique within the feature and link the proposal baseline. Preserve older amendments when a later one supersedes them.
2. Record the reason, previous and revised interpretation, affected requirement/contract identifiers, Speckit task IDs, decision authority and source, and verification impact.
3. Apply the accepted change to the working feature spec, plan, acceptance criteria and tasks in the paired docs worktree before dependent implementation. Full governing-proposal reconciliation is deferred to the final batch; working instructions stay current now.
4. Commit the amendment with its implementation concern, using separate docs and code commits where the triad requires them. Record corresponding commit references when known.
5. Link it to the feature's one reconciliation issue in the docs repository. Create that issue at the first amendment; append subsequent amendment references to it.

The [record templates](triad-feature-amendment-templates.md) provide the manual starting point. Existing templates are not a measured custom OpenSpec schema.

Track dispositions explicitly: `proposed`, `accepted`, `implemented`, `superseded`, `reverted` or `deferred`. Record decision authority separately from implementation status; a completed edit is not evidence of approval. A proposed or deferred delta is not applied to the current feature spec.

Git holds the durable records. The issue tracks reconciliation work; it neither replaces the records nor becomes a second task backlog. Speckit owns every executable implementation task.

## One final reconciliation

Perform one batch after implementation and verification are complete. Read all amendments, the final working feature files and the actual tested code; compute their net semantic effect. Preserve reverted, superseded and deferred records as history, and exclude their inactive deltas from the final behavior.

The docs reconciliation PR must:

- update the governing specs, contracts and design to describe the tested implementation;
- reconcile the original active proposal through dated amendments and an as-built record, preserving its approved baseline and the reasons for departures;
- list every feature amendment and its final disposition;
- link verification evidence and the corresponding code commit, updating the reference to the landed code commit when merge changes its identity;
- identify any larger ideas left in future-proposal issues.

An archived proposal is historical evidence. Use a new linked change or reconciliation record instead of silently rewriting archived approval history.

Prepare docs and code PRs together. The code PR may land first, but the completed project cannot advance to that code until the reconciliation lands and the assembly pins the matching docs and code. Close the reconciliation issue after the docs PR lands; the Speckit landing record tracks the assembly PR. Archive the governing change only after implementation and the assembly pin update have landed. Publish any subsequent archive commit through the ordinary docs-leg pin process.

If behavior changes after reconciliation, reopen the reconciliation issue and refresh the affected records. A cancelled feature records abandonment and amendment dispositions; it does not claim an as-built result.

## Operate the two OpenSpec roots explicitly

The full proposal lifecycle acts on the feature's docs checkout. The local amendment lifecycle acts on the code feature folder. Resolve and verify the root for every operation, especially archive. A registered store can provide explicit docs selection through `--store`; ordinary cwd selection remains available.

A local planning root takes precedence over a `store:` pointer. References provide context, not scope inheritance or cross-repository synchronization. Store selection must name the intended docs checkout/branch, not accidentally edit its pinned base mount. OpenSpec does not perform our final reconciliation automatically. See [stores](https://openspec.dev/docs/stores) and [schemas](https://openspec.dev/docs/schemas).

Until the small amendment schema and archive routing are qualified, maintain the local records manually. Do not invoke default local archival as a substitute for docs reconciliation or introduce the default schema's second implementation task list. Final archival preserves the local evidence and explicitly targets the full docs change after the project landing.

## Migrating a single repository to a triad

This decision changes migration placement and workflow follow-ups. Continue using openRepoShape's `adopt-project.py plan`, reviewed plan resolutions, `check`, human-confirmed `execute`, history extraction and per-path blob verification. The migration retains its existing safety rules, clean/default-branch prerequisites and pin tooling.

The migration plan must distinguish these artifacts:

| Source artifact | Triad destination |
|---|---|
| Full `openspec/changes/`, archives and canonical `openspec/specs/` | Docs/spec repository |
| Existing Speckit `specs/<NNN-feature>/` | Docs/spec repository |
| Existing bounded `features/<NNN-feature>/openspec/` records | Code repository, as the narrow amendment exception |
| `.specify/`, project agent entrypoints, manifest and project tooling | Assembly root, subject to existing shape rules |
| Source, tests and build artifacts | Code repository, subject to existing shape rules |

Do not retroactively reclassify an existing full proposal as a local amendment because it was authored on a feature branch. The contents and purpose determine its destination. Existing proposals and archived decisions retain their history; there is no need to manufacture a second proposal cycle for every historical feature.

The current classifier has not gained the amendment exception. Review those paths explicitly in the adoption plan and record a `leg: code` resolution for genuine bounded records, or use the updated upstream rule after it lands. Resolve ambiguous memory, examples and other content through the existing reviewed plan. Do not hand-edit pinned consumer classifier copies.

After the split, update relative links, docs-store/root selection and baseline references that depended on a single checkout. Retain the original proposal repository/commit/path as provenance and record verified correspondence to the extracted docs repository/commit/path; filtering history can change commit IDs. Never substitute a guessed new hash for an approved baseline. Record any changed feature/task locations in the migration handoff.

The adoption tool's selected source commit does not implicitly migrate every open feature branch. Preserve open-feature and worktree state through the existing parking/handoff procedures and follow the adoption prerequisites; do not delete or reset active work to make migration pass. Explicitly plan how retained work resumes in paired docs/code feature worktrees.

Include workflow distribution, root/link repair and placement review in the migration feature's follow-up work. If migration implementation needs bounded spec adjustments, capture them as amendments under that feature's one reconciliation issue. Reconcile the tested migration once at completion, then land matching docs/code and advance assembly pins. Extraction success alone does not prove the project's documents and agents are in sync.

## Distribution and remaining delivery

The installed shared protocol records the adopted manual workflow. `setup-openspeckit` currently creates missing global protocol files and leaves existing files intact; documenting adoption does not distribute it to every workstation. Since workBenches [#131](https://github.com/opensoft/workBenches/pull/131), the workflow-protocol fallback template in `setup-openspeckit` carries the shared protocol's Triad Feature Amendments section, so new installations receive it, and `devBenches/devcontainer.test/test-openspeckit-bootstrap.sh` asserts that content. Existing installations keep their files (`write_text_if_missing`), and the global-entrypoint template, the bootstrap-contract template and the managed command/skill guidance still need a subsequent implementation change. openRepoShape's placement contract needs the narrow amendment-folder exception upstream; never edit a consumer's pinned shape copies or hand-adjust its digest.

Optional `project` diagnostics can report a missing reconciliation record or unresolved amendments after the underlying contract exists. They must reuse the existing Git, shape and workflow owners.

No existing lane-swap task is completed by this record. No PR merge, seat transfer, runtime canary or deployment follows from adopting the workflow.
