# Testing and Acceptance Checklist: Guided setup wizard

**Purpose**: Release-gate unit tests for the quality of the acceptance criteria and the test strategy the requirements imply: scenario coverage per FR, measurable success criteria, fixtures, regression suites, real-host and manual checks.
**Created**: 2026-10-21
**Feature**: [spec.md](../spec.md) · OpenSpec change [`setup-guided-wizard`](../../../openspec/changes/setup-guided-wizard/) (`tasks.md` §§ 2–5, 7; design › Acceptance-suite impact)
**Depth**: release gate, maximum coverage (no item cap) · **Audience**: reviewers before `/speckit-plan`
**Scenario classes**: Primary, Alternate, Exception/Error, Recovery, Non-Functional

**Legend**: `[x]` satisfied, with a pointer · `[x] … Fixed:` gap closed by wording (spec and delta updated) · `[x] … Resolved:` closed by Brett's decision (NB-n, [README](README.md) › Needs Brett) · `[ ]` open

## Acceptance Criteria Quality

- [x] CHK001 - Does every FR have at least one acceptance scenario, including the Profiles About panel? [Coverage, Spec §FR-019] — **Fixed**: US1-20 added for FR-019's identities line, rows and About panel; every other FR already had one (`requirements.md` notes).
- [x] CHK002 - Is every success criterion objectively measurable, with its method stated? [Measurability, Spec §SC-001–SC-013] — SC-001 to SC-013 (counts, exit codes, timings, recorded approvals).
- [x] CHK003 - Is the subjective walkthrough (SC-012) given an owner and a recorded result? [Measurability, Spec §SC-012] — **Fixed**: SC-012 records it with the real-host results; OpenSpec `tasks.md` 5.3 now includes the walkthrough.
- [x] CHK004 - Are acceptance scenarios written as Given/When/Then with observable outcomes? [Clarity] — US1 to US7.
- [x] CHK005 - Is traceability kept between FRs, OpenSpec requirements and scenarios? [Traceability] — spec › OpenSpec Traceability (45/45).
- [x] CHK006 - Is the width-matrix assertion objective whatever names the fixture uses? [Measurability, Spec §US4-1] — The assertion is "no line wider than the terminal"; "long names" only chooses the fixture.

## Test Strategy Completeness

- [x] CHK007 - Is the render matrix specified (widths, heights, catalog size, statuses)? [Completeness, Spec §SC-002] — SC-002; US4 Independent Test.
- [x] CHK008 - Are fixtures named for each independent test (fixture workstation, fixture catalogs, recording stubs, blocking probe)? [Completeness] — US1 to US7 Independent Tests.
- [x] CHK009 - Are the timing test's status (local, not a CI gate) and its workload stated? [Clarity, Spec §FR-060] — Assumptions › Key-response budget; US6-6; OpenSpec `tasks.md` 4.5.
- [x] CHK010 - Are negative catalog tests specified (36-character tagline, version token) along with the allow-list case? [Coverage, Spec §FR-053] — US5-2.
- [x] CHK011 - Is the static check's failure mode testable? [Measurability, Spec §FR-057] — FR-057; OpenSpec `tasks.md` 2.1.
- [x] CHK012 - Is the per-consumer digit-leading behaviour test specified? [Completeness, Spec §FR-057] — FR-057; US5-6; SC-004.
- [x] CHK013 - Are maintenance-script fixture tests specified? [Completeness, Spec §FR-059] — US5-9; OpenSpec `tasks.md` 2.5.
- [x] CHK014 - Are tests for "no discovery during render" specified? [Completeness, Spec §FR-038] — US6-2; SC-005.
- [x] CHK015 - Are partial-redraw tests specified (no clear, nothing written when unchanged, full repaint on resize)? [Completeness, Spec §FR-039] — US6-3, US6-4.
- [x] CHK016 - Is Q clean-up testable (status, time, no processes)? [Measurability, Spec §SC-007] — SC-007; US3-10.
- [x] CHK017 - Are degraded-metadata scenarios testable with fixtures? [Completeness] — US7 Independent Test.
- [x] CHK018 - Is the full nav at 80 columns with three single-digit counts tested? [Coverage, Spec §FR-007] — US4-15; OpenSpec `tasks.md` 4.1.

## Regression and Release Verification

- [x] CHK019 - Is keeping every existing suite outcome a measurable criterion? [Measurability, Spec §SC-010] — SC-010 ("zero asserted outcomes removed").
- [x] CHK020 - Are the suites to update listed with their new keystrokes? [Completeness] — SC-010; design › Acceptance-suite impact; OpenSpec `tasks.md` 5.1.
- [x] CHK021 - Are the real-host acceptance runs specified (native, WSL, a TUI install of 365Bench)? [Completeness, Spec §SC-010] — SC-010; OpenSpec `tasks.md` 5.3.
- [x] CHK022 - Are manual checks (glyph widths in Windows Terminal and the VS Code terminal) placed in a phase with a recorded result? [Gap, Spec §Assumptions] — **Fixed**: Assumptions › Users and terminals and OpenSpec `tasks.md` 5.3: checked by hand during release QA and recorded with the real-host results.
- [x] CHK023 - Is the copy-approval gate verifiable? [Measurability, Spec §SC-013] — SC-013 (who, date and commit, fixed in [catalog.md](catalog.md) CHK013).
- [x] CHK024 - Are `/speckit-analyze` and `openspec validate --strict` required before build and merge? [Completeness] — OpenSpec `tasks.md` 1.3, 7.1.

## Scenario Class Coverage

- [x] CHK025 - Does each story cover exception and recovery paths in at least one scenario, where they apply? [Coverage] — US1-12/14, US3-5/6/10, US5-8, US7-2 to US7-5.

## Notes

- 25 items: 25 satisfied — 22 as written, 3 closed by wording in this pass — and none open.
- Fixes recorded in other checklists and only referenced here: CHK023.
