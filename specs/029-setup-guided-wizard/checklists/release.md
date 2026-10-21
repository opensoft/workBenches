# Documentation, Release and Rollback Checklist: Guided setup wizard

**Purpose**: Release-gate unit tests for the release target, merge gates, documentation and release notes, rollback and post-merge steps.
**Created**: 2026-10-21
**Feature**: [spec.md](../spec.md) · OpenSpec change [`setup-guided-wizard`](../../../openspec/changes/setup-guided-wizard/) (proposal › Release Target and Handoff; design › Migration Plan; `tasks.md` §§ 1, 6, 7)
**Depth**: release gate, maximum coverage (no item cap) · **Audience**: reviewers before `/speckit-plan`
**Scenario classes**: Primary, Alternate, Exception/Error, Recovery, Non-Functional

**Legend**: `[x]` satisfied, with a pointer · `[x] … Fixed:` gap closed by wording (spec and delta updated) · `[x] … Resolved:` closed by Brett's decision (NB-n, [README](README.md) › Needs Brett) · `[ ]` open

## Requirement Completeness — Target and landing

- [x] CHK001 - Are the release target and the retarget rule specified? [Completeness] — Assumptions › Release target; proposal › Release Target.
- [x] CHK002 - Is landing in a single pull request, carrying both the OpenSpec change and this feature, specified? [Completeness] — spec header; design › Migration Plan 1; OpenSpec `tasks.md` 7.3.
- [x] CHK003 - Are all merge gates listed (copy approval, Brett's word, real-host acceptance, full regression, validate, analyze)? [Completeness] — FR-053; OpenSpec `tasks.md` 1.3, 5.2, 5.3, 7.1–7.3.
- [x] CHK004 - Is the copy-approval record specified? [Clarity, Spec §SC-013] — SC-013 (fixed in [catalog.md](catalog.md) CHK013).
- [x] CHK005 - Is Brett's approval of the OpenSpec change itself recorded, as `tasks.md` 1.1 asks? [Gap] — **Resolved** (NB-15 A, Brett Heap, 2026-10-21): OpenSpec `tasks.md` 1.1 ticked "approved by Brett Heap, 2026-10-21"; spec › Clarifications › Session 2026-10-21 (checklist decisions).
- [x] CHK006 - Is the 1.6 boundary stated? [Scope] — Assumptions › Release target.
- [x] CHK007 - Is the version shown in the head line during this release specified? [Clarity, Spec §FR-029] — FR-029; Assumptions (`VERSION` `1.7.0-dev.1`).

## Requirement Completeness — Documentation and notes

- [x] CHK008 - Are the documentation deliverables listed? [Completeness] — proposal › Impact (Docs); OpenSpec `tasks.md` 6.1.
- [x] CHK009 - Is the Agents naming required in the docs? [Consistency, Spec §FR-001] — FR-001; OpenSpec `tasks.md` 6.1.
- [x] CHK010 - Must the changelog and release notes call out the user-visible changes (Enter now opens Review; three newly offered benches)? [Gap] — **Fixed**: OpenSpec `tasks.md` 6.2 now requires both call-outs (the proposal marks the Enter change BREAKING).
- [x] CHK011 - Is the credential-requirements documentation update specified? [Completeness] — OpenSpec `tasks.md` 2.4.
- [x] CHK012 - Is the location of the release-scope note specified, including the 1.8 fallback? [Completeness] — OpenSpec `tasks.md` 6.2; design › Migration Plan 3.
- [x] CHK013 - Is the risk of users' Enter habit addressed in hints and docs? [Coverage] — design › Risks ("Enter Review" and "Enter Apply"); FR-009; FR-022.

## Requirement Completeness — Rollback and after merge

- [x] CHK014 - Is rollback defined, with what remains on workstations? [Recovery] — Assumptions › Rollback; design › Migration Plan 4.
- [x] CHK015 - Is "no data migration" justified? [Completeness] — Assumptions › No data migration; design › Migration Plan 2.
- [x] CHK016 - Is archiving the OpenSpec change after merge specified? [Completeness] — OpenSpec `tasks.md` 7.4.
- [x] CHK017 - Is keeping bench copy accurate after release documented? [Completeness] — design › Risks ("Copy drifts from bench images"); FR-055.
- [x] CHK018 - Are the release QA steps and where their evidence goes specified? [Completeness] — OpenSpec `tasks.md` 5.3 (now including the glyph check and the SC-012 walkthrough; fixed in [testing.md](testing.md) CHK003, CHK022).

## Notes

- 18 items, all satisfied: 16 as written, 1 closed by wording, 1 resolved by Brett's decision (NB-15); none open.
- Fixes recorded in other checklists and only referenced here: CHK004, CHK018.
