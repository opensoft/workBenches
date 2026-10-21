# Performance Checklist: Guided setup wizard

**Purpose**: Release-gate unit tests for the performance requirements: the 100 ms key-response budget, first paint without discovery, partial redraw and metadata ingestion.
**Created**: 2026-10-21
**Feature**: [spec.md](../spec.md) · OpenSpec change [`setup-guided-wizard`](../../../openspec/changes/setup-guided-wizard/) (delta `setup-wizard-layout`)
**Depth**: release gate, maximum coverage (no item cap) · **Audience**: reviewers before `/speckit-plan`
**Scenario classes**: Primary, Alternate, Exception/Error, Recovery, Non-Functional

**Legend**: `[x]` satisfied, with a pointer · `[x] … Fixed:` gap closed by wording (spec and delta updated) · `[x] … Resolved:` closed by Brett's decision (NB-n, [README](README.md) › Needs Brett) · `[ ]` open

## Requirement Clarity and Measurability — Key response

- [x] CHK001 - Is the key-response budget quantified? [Clarity, Spec §FR-060] — FR-060 (100 ms); Q15.
- [x] CHK002 - Is the statistic unambiguous, rather than "each key press within 100 ms, measured as the median"? [Conflict, Spec §FR-060, §SC-006] — **Fixed**: FR-060, SC-006 and delta › Key response time now say "the median time from a key press to the completed redraw MUST be at most 100 ms".
- [x] CHK003 - Is the measurement reproducible: start and end points, statistic, frame size, step, workload and keys? [Measurability, Spec §FR-060, §US6-6] — FR-060; US6-6 (Benches, 87×40, 12 benches, long About text, ↑ ↓ Tab PgDn replayed); design D19.
- [x] CHK004 - Is the measurement environment stated, including whether the test is a CI gate? [Assumption] — Assumptions › Key-response budget (developer workstation; local, not a hard CI gate); Q15.
- [x] CHK005 - Is the absence of a tail-latency bound (p95 or maximum) a decision rather than an omission? [Clarity] — Q15 chose the median.
- [x] CHK006 - Is the choice of the Benches step at 87×40 as the measured frame justified as the worst case? [Assumption, Spec §FR-060] — FR-060; design D19 ("the most expensive frame").
- [x] CHK007 - Is the scope of the budget clear (key-driven redraws, not full repaints after a resize or helper)? [Clarity, Spec §FR-060, §FR-039] — FR-060 ("key-driven redraws"); FR-039 limits full clears to first paint, helper return and size changes.
- [x] CHK008 - Is "never feel slower than 1.7" (US6) expressed through measurable criteria? [Measurability] — FR-060, FR-038, FR-039; SC-005, SC-006.

## Requirement Completeness — First paint and rendering cost

- [x] CHK009 - Is first paint specified measurably (drawn before any slow probe returns)? [Measurability, Spec §FR-038] — FR-038; SC-005; US6-1.
- [x] CHK010 - Are the tools that must not run before first paint or during rendering enumerated? [Completeness, Spec §FR-038] — FR-038; US6-2 (`jq`, `python3`, `docker`, `git` recorded).
- [x] CHK011 - Is partial redraw measurable (bytes written; no clear; nothing written when unchanged)? [Measurability, Spec §FR-039] — FR-039; US6-3, US6-4.
- [x] CHK012 - Are the only clear-screen triggers enumerated? [Completeness, Spec §FR-039] — FR-039.
- [x] CHK013 - Must foreground metadata ingestion avoid external tools? [Completeness, Spec §FR-048] — FR-048 (no external tools; Bash builtins in the delta).
- [x] CHK014 - Is synchronous metadata loading limited to the modes that need it? [Completeness, Spec §Edge Cases] — Edge Cases › Keys piped without a terminal (apply-plan and dependencies-plan never load it).
- [x] CHK015 - Is Q's exit time bounded? [Measurability, Spec §FR-027] — FR-027; SC-007 (two seconds).
- [x] CHK016 - Is the latency from a status or metadata change to the screen specified, or explicitly kept as in 1.7? [Gap] — **Fixed**: Assumptions › Unchanged now lists the status polling cadence.

## Scenario Coverage

- [x] CHK017 - Primary: is navigation on the heaviest step covered by the timing scenario? [Coverage, Primary] — US6-6.
- [x] CHK018 - Alternate: are runs without a terminal (piped keys) kept out of the interactive budget? [Coverage, Alternate] — FR-060 applies at 87×40; unknown-height, piped runs load synchronously (Edge Cases) and are not timed.
- [x] CHK019 - Exception: is first paint covered when the Docker probe blocks? [Coverage, Exception] — US6-1; SC-005.
- [x] CHK020 - Recovery: is a full repaint (resize, helper return) accepted outside the key budget? [Coverage, Recovery] — FR-039; FR-060 scope (CHK007).
- [x] CHK021 - Non-functional: are 1.7's async and first-paint tests kept as regression guards? [Coverage, Non-Functional] — SC-010; design D2 (`test-tools-runtime.py`, `test-setup-async.py`).

## Notes

- 21 items: 21 satisfied — 19 as written, 2 closed by wording in this pass — and none open.
