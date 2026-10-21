# Reliability, Degraded Metadata and Recovery Checklist: Guided setup wizard

**Purpose**: Release-gate unit tests for loading states, late or missing metadata, refresh and state preservation, failures, recovery paths and idempotency.
**Created**: 2026-10-21
**Feature**: [spec.md](../spec.md) · OpenSpec change [`setup-guided-wizard`](../../../openspec/changes/setup-guided-wizard/) (deltas `setup-bench-browser`, `setup-wizard-flow`, `setup-wizard-layout`)
**Depth**: release gate, maximum coverage (no item cap) · **Audience**: reviewers before `/speckit-plan`
**Scenario classes**: Primary, Alternate, Exception/Error, Recovery, Non-Functional

**Legend**: `[x]` satisfied, with a pointer · `[x] … Fixed:` gap closed by wording (spec and delta updated) · `[x] … Resolved:` closed by Brett's decision (NB-n, [README](README.md) › Needs Brett) · `[ ]` open

## Requirement Completeness — Loading and arrival

- [x] CHK001 - Is a Loading state specified for every item whose state is unknown? [Completeness, Spec §FR-040] — FR-040; US1-5.
- [x] CHK002 - Is the final state of an item whose check ends without reporting specified? [Gap, Spec §FR-040] — **Fixed**: FR-040 and delta › Loading indicators: treated as needing a check and not selectable, as 1.7's `poll_status_loader` does.
- [x] CHK003 - Is the Benches step specified before the bench list and its details arrive? [Completeness, Spec §FR-049] — FR-049; US7-3.
- [x] CHK004 - Is "details complete" defined so a half-written file is never read? [Clarity, Spec §FR-048] — FR-048 (each file complete before it becomes visible); design D12 (categories first; `bench-meta` marks completion).
- [x] CHK005 - Is focus specified when the bench list first arrives while Benches shows `Loading benches…`? [Gap, Spec §FR-051] — **Fixed**: FR-051 and delta › Focus survives catalog updates: the category zone on the first category that has benches, as on arrival (FR-004).
- [x] CHK006 - Is the Benches step specified when checks finish, or fail to start, without publishing a bench list at all? [Gap, Spec §FR-049] — **Resolved** (NB-13 A, Brett Heap, 2026-10-21): FR-049 and delta › Metadata delivery: the step says the bench list could not be loaded and that R retries; nothing queueable; US7-8.

## Requirement Completeness — Degraded metadata

- [x] CHK007 - Is placement specified for a bench without a category under each bench root? [Completeness, Spec §FR-050] — FR-050; US7-4.
- [x] CHK008 - Is the label rule for an unknown category id ("derived from its id") and the order among several unknown ids specified? [Clarity, Spec §FR-050] — **Resolved** (NB-10 A, Brett Heap, 2026-10-21): FR-050 and delta › Degraded metadata: title-cased hyphen-separated words, ordered by id; US7-9.
- [x] CHK009 - Is placement specified for a bench without a category whose path is outside the three bench roots? [Gap, Spec §FR-050] — **Resolved** (NB-10 A, Brett Heap, 2026-10-21): FR-050 and delta: `Other benches`.
- [x] CHK010 - Is the no-details fallback specified (group name, About text, selectability)? [Completeness, Spec §FR-050] — FR-050; US7-5.
- [x] CHK011 - Is behaviour specified when categories arrive without per-bench details, or a bench lacks only some fields? [Gap, Spec §FR-050] — **Resolved** (NB-10 A, Brett Heap, 2026-10-21): FR-050 and delta: benches still placed by path; present fields shown; `No details for this bench yet.` when description, uses and contents are all missing; `Other benches` About lists its benches; US7-9; delta scenario "Categories without bench details".
- [x] CHK012 - Is "no bench queueable until details arrive" consistent with "selectable without details"? [Consistency, Spec §FR-049, §FR-050] — FR-049 now ends the wait when checks finish without details (fixed in [ux.md](ux.md) CHK068).
- [x] CHK013 - Is handling of invalid bench names and category ids specified? [Completeness, Spec §FR-048] — FR-048 (ignored); Edge Cases.

## Requirement Completeness — Refresh and state preservation

- [x] CHK014 - Is state preserved across R (step, focus, zone, category, bench, queue)? [Completeness, Spec §FR-026] — FR-026; SC-008; US3-9.
- [x] CHK015 - Is state preserved across catalog and details arrival? [Completeness, Spec §FR-051] — FR-051; US7-6.
- [x] CHK016 - Are the P and G return targets preserved by bench name across a refresh? [Gap, Spec §FR-023, §FR-051] — **Fixed**: FR-051 and delta: a remembered bench is kept by name the same way (FR-023 remembers the bench, not a list position).
- [x] CHK017 - Is behaviour decided when a focused or remembered bench, or a bench with a queued change, leaves the catalog, and does it agree with SC-008's "100% of queued changes"? [Conflict, Spec §Edge Cases vs §SC-008] — **Resolved** (NB-5 A, Brett Heap, 2026-10-21): FR-051, FR-026 and deltas › Focus survives, Refresh keeps state: focus falls back and the change is dropped; SC-008 now counts "queued changes for benches still catalogued"; US7-10.

## Exception and Error Flows

- [x] CHK018 - Are Vault action failures and cancellations specified with notices and preserved state? [Exception, Spec §FR-025] — FR-025; US3-6, US3-7.
- [x] CHK019 - Are Profiles action failures and cancellations specified? [Exception, Spec §FR-020] — FR-020 (failure notice added in [ux.md](ux.md) CHK036).
- [x] CHK020 - Is messaging for a failed Workstation service action specified? [Exception] — Service behaviour unchanged from 1.7 (Assumptions › Unchanged); shown as a notice on the current step (FR-032).
- [x] CHK021 - Is fail-closed handling of an unresolved bench path specified, including how the failure is reported? [Exception, Spec §FR-058] — FR-058 (fixed in [security.md](security.md) CHK007, CHK009).
- [x] CHK022 - Is behaviour specified while a Docker probe blocks (paint, Q)? [Exception, Spec §FR-038, §FR-027] — FR-038, FR-027; US6-1.
- [x] CHK023 - Is the outcome when checks end unresolved specified, with the way back? [Exception, Spec §FR-028] — FR-028; US3-5.

## Recovery Flows

- [x] CHK024 - Is R defined as the recovery from failed or stale checks? [Recovery, Spec §FR-026] — FR-026; 1.7's "R retries" notices are kept (FR-032).
- [x] CHK025 - Is Q's clean-up specified and measurable (pending checks stopped, private status files removed, no stray process)? [Recovery, Spec §FR-027] — FR-027; SC-007.
- [x] CHK026 - Is interruption other than Q (Ctrl+C, termination) specified? [Gap] — **Fixed**: Assumptions › Unchanged: interrupt handling as in 1.7 (Ctrl+C exits 130, termination 143).
- [x] CHK027 - Is the repaint after an interactive helper returns specified? [Recovery, Spec §FR-039] — FR-039.
- [x] CHK028 - Is rollback of the whole change defined, including what stays on workstations? [Recovery] — Assumptions › Rollback; design › Migration Plan 4.
- [x] CHK029 - Are partial Apply failures handled as before? [Recovery, Spec §FR-015] — FR-015 (apply semantics unchanged).

## Idempotency

- [x] CHK030 - Is repeated R, or R while checks run, safe for the queue and focus? [Idempotency, Spec §FR-026] — FR-026 applies to every R.
- [x] CHK031 - Are repeated P/P and G/G round trips idempotent? [Idempotency, Spec §SC-008] — SC-008.
- [x] CHK032 - Is re-running a selection-only session safe (file replaced, never written through a symlink)? [Idempotency, Spec §FR-015] — FR-015 (fixed in [security.md](security.md) CHK020).
- [x] CHK033 - Does a readiness jump while already on Workstation leave the return target intact? [Idempotency, Spec §FR-028] — FR-028 (fixed in [ux.md](ux.md) CHK049).

## Non-Functional and Dependencies

- [x] CHK034 - Do the layout and timing bounds also hold in degraded states? [Non-Functional] — FR-033 to FR-036 and FR-060 apply to every frame.
- [x] CHK035 - Is untrusted text prevented from changing terminal state in degraded cases? [Non-Functional, Spec §FR-048] — FR-048; SC-011.
- [x] CHK036 - Is the dependency on the status worker running inside Tools stated? [Dependency] — Assumptions › Dependencies; design D12. Its failure case is CHK006 (NB-13, resolved).

## Notes

- 36 items, all satisfied: 27 as written, 4 closed by wording, 5 resolved by Brett's decisions (NB-5, NB-10 ×3, NB-13); none open.
- Fixes recorded in other checklists and only referenced here: CHK012, CHK019, CHK021, CHK032, CHK033.
