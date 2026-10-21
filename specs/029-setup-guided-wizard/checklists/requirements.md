# Specification Quality Checklist: Guided setup wizard

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-10-21
**Feature**: [spec.md](../spec.md)

## Content Quality

- [x] No implementation details (languages, frameworks, APIs)
- [x] Focused on user value and business needs
- [x] Written for non-technical stakeholders
- [x] All mandatory sections completed

## Requirement Completeness

- [x] No [NEEDS CLARIFICATION] markers remain
- [x] Requirements are testable and unambiguous
- [x] Success criteria are measurable
- [x] Success criteria are technology-agnostic (no implementation details)
- [x] All acceptance scenarios are defined
- [x] Edge cases are identified
- [x] Scope is clearly bounded
- [x] Dependencies and assumptions identified

## Feature Readiness

- [x] All functional requirements have clear acceptance criteria
- [x] User scenarios cover primary flows
- [x] Feature meets measurable outcomes defined in Success Criteria
- [x] No implementation details leak into specification

## Notes

- Items marked incomplete require spec updates before `/speckit-clarify` or `/speckit-plan`
- Validation run 2026-10-21 (iteration 1): 15/16 items pass.
- **Open markers (3, the skill's maximum)**: FR-007 six-step nav fit at standard widths → clarify Q1; FR-053 approval of the drafted copy for all 12 benches → clarify Q5 (with Q14); FR-033 minimum supported terminal size → clarify Q6. They are carried, with 17 further questions, into `../clarify-questions.md` and resolve when Brett's answers are encoded.
- **Implementation detail**: the spec names on-screen text, keys, setup modes, the selection-file format and the bench catalog's fields, because those are the user-visible and data contracts the OpenSpec deltas fix. Mechanisms (section numbering, status-file names and formats, lookup syntax, rendering functions) stay in `openspec/changes/setup-guided-wizard/design.md` and the later plan. US6 names `jq`, `python3`, `docker` and `git` only as the commands its test stubs out.
- **Audience**: the repository owner and reviewers; terms follow the TUI's own vocabulary (steps, zones, About panel).
- **Acceptance coverage**: every FR (FR-001–FR-059) is exercised by at least one acceptance scenario in User Stories 1–7.
- **Traceability**: 44/44 OpenSpec requirements map to at least one FR (table in spec.md › OpenSpec Traceability); no FR lacks an OpenSpec source.
- **SC-006** carries an assumed 100 ms key-response budget pending clarify Q15.
- Re-validated 2026-10-21 after the clarify session (20 answers encoded): 15/16 → 16/16. Newly passing: "No [NEEDS CLARIFICATION] markers remain" (FR-007 ← Q1, FR-033 ← Q6, FR-053 ← Q5). No regressions. FR-060 (key response, Q15) and SC-013 (no versions in copy; copy approval recorded before merge) were added; traceability is now 45/45, including the new OpenSpec requirement "Key response time", and SC-006's 100 ms budget is confirmed.

## Release-Gate Cross-Cutting Review

**Added**: 2026-10-21 by `/speckit-checklist` with no argument (maximum coverage). The domain checklists are listed in [README.md](README.md).
**Legend**: `[x]` satisfied, with a pointer · `[x] … Fixed:` gap closed by wording in this pass · `[ ]` open → [README](README.md) › Needs Brett (NB-n)

### Completeness

- [x] CHK001 - Are all OpenSpec requirements mapped to FRs, with no FR lacking a source? [Traceability] — spec › OpenSpec Traceability (45/45).
- [x] CHK002 - Does the requirement count in the spec header match the traceability table? [Consistency] — **Fixed**: the header said 44 requirements; it now says 45 (17 flow, 11 layout, 10 bench browser, 7 catalog).
- [x] CHK003 - Is each of the 20 clarification answers reflected in an FR, SC, edge case or assumption? [Completeness] — Clarifications › Session 2026-10-21 against FR-001, FR-002, FR-004, FR-005, FR-007, FR-008, FR-012, FR-016, FR-021, FR-022, FR-028, FR-033, FR-041, FR-044, FR-053, FR-054, FR-060 and Assumptions › Out of scope.
- [x] CHK004 - Does every user story have a priority, a reason and an independent test? [Completeness] — US1 to US7.
- [x] CHK005 - Are the deliberate behaviour changes listed, as distinct from "look only"? [Scope] — Assumptions › Approved scope.
- [x] CHK006 - Is unchanged behaviour listed, so the plan does not alter it? [Scope] — Assumptions › Unchanged (now also the status polling cadence and interrupt handling).

### Clarity

- [x] CHK007 - Are "as before this change" and "as in 1.7" pinned to a baseline? [Clarity] — proposal › Handoff (cut from `origin/release/1.7.0` at `ccc9eac`); design › Context.
- [x] CHK008 - Are the on-screen strings that tests match quoted exactly? [Clarity] — Quoted throughout the FRs and scenarios.
- [x] CHK009 - Are vague words ("immediately", "sensible category", "long names") backed by measurable FRs? [Clarity] — FR-038 and FR-060; FR-050; FR-033.
- [x] CHK010 - Is MUST/SHALL used consistently between the spec and the deltas? [Consistency] — Yes.

### Consistency

- [x] CHK011 - Do FR wordings match their OpenSpec deltas after this pass? [Consistency] — Deltas updated in the same pass; `openspec validate setup-guided-wizard --strict` passes.
- [ ] CHK012 - Do the success criteria and edge cases agree with the FRs? [Conflict, Spec §SC-008 vs §Edge Cases] — **Open**: SC-006 now matches FR-060, but SC-008 ("100% of queued changes") conflicts with the edge-case assumption for a bench that leaves the catalog. → NB-5.
- [x] CHK013 - Do design decisions agree with the spec where both speak (D5 nav widths, D9 order, D15 Review, D16 footer)? [Consistency] — Yes, after this pass's fixes (see [ux.md](ux.md), [layout.md](layout.md)).

### Acceptance Criteria Quality

- [x] CHK014 - Are the success criteria measurable and free of implementation detail? [Measurability] — SC-001 to SC-013; Content Quality above.
- [x] CHK015 - Does each user story map to at least one success criterion? [Coverage] — US1 → SC-001, SC-009; US2 → SC-003, SC-012; US3 → SC-007, SC-008; US4 → SC-002; US5 → SC-003, SC-004, SC-013; US6 → SC-005, SC-006; US7 → SC-011.

### Dependencies & Assumptions

- [x] CHK016 - Are external dependencies listed? [Dependency] — Assumptions › Dependencies.
- [ ] CHK017 - Is every assumption either validated by a test or explicitly accepted? [Assumption] — **Open**: the vanished-bench fallback (NB-5) and the Python consumers' name-safe indexing (NB-8) are neither.
- [x] CHK018 - Is the dependency on 1.7 freezing first handled? [Dependency] — Assumptions › Release target (retarget to 1.8 without requirement changes).

### Ambiguities & Conflicts

- [x] CHK019 - Are all `[NEEDS CLARIFICATION]` markers resolved? [Ambiguity] — None remain.
- [x] CHK020 - Are the remaining conflicts and ambiguities recorded and routed to a decision? [Traceability] — [README](README.md) › Needs Brett.
- [x] CHK021 - Is the status of each mockup clear, so illustrative details are not read as requirements? [Clarity] — design › Mockups (one approved Benches mockup; the others illustrative).
- [x] CHK022 - Are the TUI's own terms (step, zone, About panel, notice, readiness, return target) used consistently? [Consistency] — Key Entities; FR-032 (notice).

- Cross-cutting review: 22 items, 20 satisfied (19 as written, 1 closed by wording) and 2 open (NB-5, NB-8).
