# Setup-Contract Compatibility Checklist: Guided setup wizard

**Purpose**: Release-gate unit tests for the contracts the wizard must keep or extend: `setup.sh` modes, the selection file, exit statuses, the worker file contract, catalog consumers, credential requirements and the markers acceptance suites rely on.
**Created**: 2026-10-21
**Feature**: [spec.md](../spec.md) · OpenSpec change [`setup-guided-wizard`](../../../openspec/changes/setup-guided-wizard/) (deltas `setup-wizard-flow` › Setup contracts unchanged, `bench-catalog`)
**Depth**: release gate, maximum coverage (no item cap) · **Audience**: reviewers before `/speckit-plan`
**Scenario classes**: Primary, Alternate, Exception/Error, Recovery, Non-Functional

**Legend**: `[x]` satisfied, with a pointer · `[x] … Fixed:` gap closed by wording in this pass (spec and delta updated) · `[ ]` open, needs a decision → [README](README.md) › Needs Brett (NB-n)

## Requirement Completeness — Setup modes and the selection file

- [x] CHK001 - Are all `setup.sh` modes named and declared unchanged? [Completeness, Spec §FR-015] — FR-015; delta › Setup contracts unchanged.
- [x] CHK002 - Is the selection-file schema specified? [Completeness, Spec §FR-015] — FR-015; Key Entities › Selection file.
- [x] CHK003 - Is equivalence with the 1.7 TUI's selection file measurable? [Measurability, Spec §SC-009] — SC-009; US1-13; delta scenario "Same selection, same file".
- [x] CHK004 - Is the selection-only outcome specified when nothing is queued? [Gap, Spec §FR-014] — **Fixed**: FR-014 and delta › Apply from Review: a selection file with no components is written, as 1.7's `save_selection` does.
- [x] CHK005 - Is "no wizard frame in non-interactive modes" specified and testable? [Measurability, Spec §FR-015] — FR-015; US1-19; SC-009.
- [x] CHK006 - Is metadata loading specified per mode? [Completeness, Spec §Edge Cases] — Edge Cases › Keys piped without a terminal; design D12.
- [x] CHK007 - Is the selection file's write protection kept? [Completeness, Spec §FR-015] — FR-015 (fixed in [security.md](security.md) CHK020).
- [x] CHK008 - Are exit statuses specified for every way out (0 for an empty finish, 130 for Q or Ctrl+C, 143 for termination, failures as before)? [Completeness, Spec §FR-014, §FR-027] — FR-014, FR-027, FR-015; Assumptions › Unchanged (fixed in [reliability.md](reliability.md) CHK026).
- [x] CHK009 - Is behaviour for a selection file naming an unknown bench kept? [Consistency, Spec §FR-015] — FR-015 (validation unchanged).
- [x] CHK010 - Are existing selection files guaranteed to stay valid? [Compatibility] — Assumptions › No data migration.

## Requirement Completeness — Catalog consumers and data

- [x] CHK011 - Are additive catalog fields guaranteed not to break existing consumers? [Compatibility] — Assumptions › No data migration; design D11 (proof for Python consumers: [security.md](security.md) CHK005).
- [x] CHK012 - Are the consumers' outputs for a digit-leading bench specified (path, description, URL)? [Completeness, Spec §FR-056] — US5-6; delta scenario.
- [x] CHK013 - Is the infrastructure section's lookup contract covered? [Coverage, Spec §FR-056] — FR-056.
- [x] CHK014 - Are `setup_selection.py`'s acceptance of the new keys and its `benches` output specified? [Completeness, Spec §FR-054] — US5-4.
- [x] CHK015 - Is the credential-requirements change specified and verified? [Completeness, Spec §FR-054] — FR-054; US5-4; OpenSpec `tasks.md` 2.4.
- [x] CHK016 - Is the release lock named as the source of truth, so frozen apply (`release-workbenches.py prepare`) covers the new benches? [Dependency, Spec §FR-054] — FR-054; Assumptions › Dependencies; the lock already records all 12.

## Requirement Completeness — Internal contracts

- [x] CHK017 - Is the worker-to-foreground file contract specified (file names, atomic publish, format)? [Completeness, Spec §FR-048] — FR-048; design D12 and › Data Flow.
- [x] CHK018 - Is the Profiles summary contract specified (`setup-profiles.py --summary`, not parsed)? [Completeness, Spec §FR-030] — FR-030; design D14.
- [x] CHK019 - Is the section numbering that unit tests rely on documented? [Compatibility] — design D1 (sections 0–4 unchanged; Review is 5).
- [x] CHK020 - Is the source of the head line's version and OS label specified? [Completeness, Spec §FR-029] — FR-029 (`workBenches v<VERSION>` with the OS label, as 1.7 draws them).

## Requirement Completeness — Markers acceptance suites rely on

- [x] CHK021 - Are the markers acceptance suites wait on specified (`Navigation:`, the nav's `✓ Workstation`, the context-line formats)? [Compatibility, Spec §FR-022, §FR-006, §FR-021] — FR-022 (`Navigation:`, fixed in [ux.md](ux.md) CHK060), FR-006, FR-021; design › Acceptance-suite impact and D16.
- [x] CHK022 - Are the suites' new keystroke sequences documented? [Compatibility, Spec §SC-010] — SC-010; design › Acceptance-suite impact.

## Scenario Coverage

- [x] CHK023 - Alternate: are interactive runs without a terminal (piped keys) covered? [Coverage, Alternate] — Edge Cases › Keys piped without a terminal.
- [x] CHK024 - Exception: is handling of an invalid selection file unchanged? [Coverage, Exception] — FR-015.
- [x] CHK025 - Recovery: is compatibility after a rollback addressed (a reverted TUI stops offering the new benches)? [Coverage, Recovery] — design › Migration Plan 4; Assumptions › Rollback.

## Notes

- 25 items: 25 satisfied — 24 as written, 1 closed by wording in this pass — and none open.
- Fixes recorded in other checklists and only referenced here: CHK007, CHK008, CHK021.
