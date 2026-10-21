# Accessibility and Terminal Usability Checklist: Guided setup wizard

**Purpose**: Release-gate unit tests for keyboard operability, cues that do not rely on colour or blinking, focus indication, discoverability of keys, readable sizes and terminal compatibility.
**Created**: 2026-10-21
**Feature**: [spec.md](../spec.md) · OpenSpec change [`setup-guided-wizard`](../../../openspec/changes/setup-guided-wizard/) (deltas `setup-wizard-flow`, `setup-wizard-layout`)
**Depth**: release gate, maximum coverage (no item cap) · **Audience**: reviewers before `/speckit-plan`
**Scenario classes**: Primary, Alternate, Exception/Error, Recovery, Non-Functional

**Legend**: `[x]` satisfied, with a pointer · `[x] … Fixed:` gap closed by wording (spec and delta updated) · `[x] … Resolved:` closed by Brett's decision (NB-n, [README](README.md) › Needs Brett) · `[ ]` open

## Requirement Completeness

- [x] CHK001 - Is every action reachable from the keyboard alone, through a listed or documented key? [Completeness] — FR-003 to FR-028; design › Key Map.
- [x] CHK002 - Does every colour-coded state also carry a glyph or text? [Coverage] — Readiness `✓`/`⚠`/`…` (FR-006); strip states as text (FR-031); warnings and blocker as text (FR-010, FR-013); `coming soon` (FR-041).
- [x] CHK003 - Is blinking never the only carrier of meaning? [Coverage, Spec §FR-040] — FR-040 (the word `Loading`); FR-006 (the `…` glyph).
- [x] CHK004 - Is the use of blinking bounded? [Non-Functional] — Assumptions › Unchanged (blinking Loading as in 1.7); only while state is unknown (FR-040).
- [x] CHK005 - Is a focus indicator specified for the focused row on every step that has rows? [Gap, Spec §FR-004] — **Fixed**: FR-004 and delta › Step navigation: the focused row is marked `›` on every step that has rows (on Benches only in the bench zone), as every design mockup shows; FR-044 already required it for bench rows.
- [x] CHK006 - Do dimmed elements also carry text? [Coverage, Spec §FR-041] — FR-041 (`coming soon`).
- [x] CHK007 - Are alternatives given for keys some keyboards lack (PgUp/PgDn)? [Coverage, Spec §FR-046] — FR-046 (`[` and `]`).
- [x] CHK008 - Is the discoverability of keys not listed below 60 columns addressed? [Clarity, Spec §FR-022] — FR-022; Q7 trade-off; About's border still shows `PgUp/PgDn scroll` (design D16).
- [x] CHK009 - Do on-screen messages name the next action in plain language? [Clarity] — "Resolve workstation requirements to continue." (FR-028); "Profile action needs attention. Open it to retry." (FR-020); "Connection cancelled." (FR-025).
- [x] CHK010 - Is the smallest readable size specified for side panes and zoomed terminals? [Completeness, Spec §FR-033] — FR-033 (36×24 minimum); Q6.
- [x] CHK011 - Is glyph-width compatibility specified for the supported terminals and checked? [Completeness] — Assumptions › Users and terminals (check placed in release QA by [testing.md](testing.md) CHK022).
- [x] CHK012 - Is a UTF-8 terminal assumed explicitly? [Assumption] — Assumptions › Users and terminals.

## Requirement Consistency

- [x] CHK013 - Do keys mean the same on every step, with the exceptions documented (Enter on Workstation and Profiles rows)? [Consistency, Spec §FR-008] — FR-008; Q3; design › Risks.
- [x] CHK014 - Is hidden content always signalled (`…`, `▲/▼ N more`, `▼ more`)? [Consistency] — FR-021, FR-030, FR-035, FR-046.
- [x] CHK015 - Is the reuse of `✓` for both earlier steps and readiness intentional? [Ambiguity, Spec §FR-005, §FR-006] — Approved nav design (design D5; approved mockup); the readiness `✓` appears only on the Workstation item, which never shows a step mark (FR-006).

## Notes

- 15 items: 15 satisfied — 14 as written, 1 closed by wording in this pass — and none open.
- Screen-reader support is not claimed by 1.7 or by this change (approved scope "look only, same behaviour"), so no item asks for it.
