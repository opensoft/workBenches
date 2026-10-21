# Terminal Layout and Rendering Bounds Checklist: Guided setup wizard

**Purpose**: Release-gate unit tests for the frame composition, width and height bounds, banner, scrolling and redraw requirements.
**Created**: 2026-10-21
**Feature**: [spec.md](../spec.md) · OpenSpec change [`setup-guided-wizard`](../../../openspec/changes/setup-guided-wizard/) (deltas `setup-wizard-layout`, `setup-bench-browser`)
**Depth**: release gate, maximum coverage (no item cap) · **Audience**: reviewers before `/speckit-plan`
**Scenario classes**: Primary, Alternate, Exception/Error, Recovery, Non-Functional

**Legend**: `[x]` satisfied, with a pointer · `[x] … Fixed:` gap closed by wording in this pass (spec and delta updated) · `[ ]` open, needs a decision → [README](README.md) › Needs Brett (NB-n)

## Requirement Completeness — Frame head, selector area and notices

- [x] CHK001 - Are the head's parts and their order specified for every step? [Completeness, Spec §FR-029] — FR-029; US4-14.
- [x] CHK002 - Is the removal of per-step title and description lines specified? [Completeness, Spec §FR-029] — FR-029; delta scenario "No step titles".
- [x] CHK003 - Is each step's selector area defined, including the steps that have none? [Completeness, Spec §FR-030] — FR-030 (Agents and Tools start with their panels; Review with its instruction line).
- [x] CHK004 - Is the identities line's truncation specified? [Clarity, Spec §FR-030] — FR-030 (cut with `…`).
- [x] CHK005 - Are the requirements strip's content, colours and loading form specified? [Completeness, Spec §FR-031] — FR-031; US4-11.
- [x] CHK006 - Is the strip's `N/N ready` notation defined (what is counted, and whether Vault counts)? [Clarity, Spec §FR-031] — **Fixed**: FR-031 and delta › Requirements strip now read `R/N ready`: R of the N required services Up, optional Vault not counted, as 1.7 counts them.
- [x] CHK007 - Is the strip's wrapping rule specified so Vault's action is never split? [Completeness, Spec §FR-031] — FR-031; US4-11.
- [x] CHK008 - Are notice placement and width specified? [Completeness, Spec §FR-032] — FR-032; US3-7.

## Requirement Completeness — Width

- [x] CHK009 - Is the frame width specified as a function of the terminal width? [Gap, Spec §FR-033 vs §FR-007] — **Fixed**: FR-033 and delta › Width bounds: one column narrower than the terminal, clamped to 36–87 (1.7's rule; design › Layout and Height Rules). FR-007's "79-column frame" at 80 columns relied on it.
- [x] CHK010 - Is the maximum frame width specified and tested on a wide terminal? [Measurability, Spec §FR-033] — FR-033; US4-2.
- [x] CHK011 - Is the minimum supported size specified, with behaviour below it? [Completeness, Spec §FR-033] — FR-033; Q6; Edge Cases.
- [x] CHK012 - Is character-based (not byte-based) alignment specified and tested with multibyte text? [Completeness, Spec §FR-033] — FR-033; US4-3; design D10.
- [x] CHK013 - Is the single-column glyph assumption for the TUI's own glyphs stated? [Assumption] — Assumptions › Users and terminals; design D10.
- [ ] CHK014 - Is alignment protected against wide, combining or zero-width characters arriving in catalog text? [Gap, Spec §FR-033, §FR-053] — **Open**: the catalog test rejects control characters only. → NB-6.
- [x] CHK015 - Are the width thresholds for bench rows specified (tagline below 70 columns, status label below 50)? [Completeness, Spec §FR-044] — FR-044; US4-12.
- [x] CHK016 - Are the width thresholds for Agents and Tools rows specified? [Completeness] — design D16 and › Layout and Height Rules (status label at 60+ columns); FR-018 keeps 1.7's items and rules.
- [x] CHK017 - Is truncation specified for every variable-length text (names, panel titles, notices, identities line, context line)? [Completeness, Spec §FR-033] — Every line is bounded by FR-033; `…` is required where the user must know text is cut (context line FR-021, identities FR-030); panel titles drop their right-hand label before the title is cut (design › Layout and Height Rules); notices are cut to the frame (FR-032).
- [x] CHK018 - Is the compact nav guaranteed to fit the 36-column frame with the longest step name? [Coverage, Spec §FR-007, §FR-033] — FR-033's bound applies to the nav like any line; the exact compact format is left to the plan.
- [x] CHK019 - Is the full nav's width budget documented with measured figures? [Clarity, Spec §FR-007] — FR-007; design D5 (73, 79 and 80 columns).

## Requirement Completeness — Height

- [x] CHK020 - Is the rule "never taller than a known terminal height" specified? [Completeness, Spec §FR-034] — FR-034; SC-002.
- [x] CHK021 - Is the tight layout defined (what changes) and when it applies? [Clarity, Spec §FR-034] — FR-034 (no blank spacers, one-line banner; at 24 rows or fewer or when roomy does not fit).
- [x] CHK022 - Is the roomy layout defined? [Clarity, Spec §FR-034, §FR-037] — FR-034, FR-037; design › Layout and Height Rules.
- [x] CHK023 - Is the wordmark rule consistent with the tight layout when a terminal of 40+ rows cannot fit the roomy layout? [Conflict, Spec §FR-034 vs §FR-037] — **Fixed**: FR-037 and delta › Banner collapse: the wordmark is drawn only in the roomy layout (design D9 gives up the wordmark first).
- [x] CHK024 - Is in-panel scrolling specified with its markers and focus visibility? [Completeness, Spec §FR-035] — FR-035; US4-7.
- [x] CHK025 - Is unknown-height behaviour specified, including when the height counts as unknown? [Clarity, Spec §FR-036] — FR-036; US4-8 ("cannot be read").
- [x] CHK026 - Is behaviour below the tight layout's height specified? [Exception, Spec §FR-036] — FR-036; US4-9.
- [x] CHK027 - Is what every 24-row frame must still show specified? [Measurability, Spec §SC-002] — US4-4; SC-002 (nav bar, focused row, whole footer).
- [x] CHK028 - Is the Benches height budget specified with its priorities and minimums? [Completeness, Spec §FR-047] — FR-047; design D9.
- [ ] CHK029 - Is the use of rows beyond the minimums specified (more bench rows or more About lines first)? [Gap, Spec §FR-047] — **Open**: at 80×24 the 11 spare rows can go either way. → NB-12.
- [x] CHK030 - Is the collapsed category-block format specified? [Clarity, Spec §FR-047] — FR-047; US4-5; design D9 example line.
- [x] CHK031 - Is Review's layout under height pressure specified? [Completeness, Spec §FR-012] — FR-012; design D15 (grouped panels, then one CHANGES list, then scrolling).
- [x] CHK032 - Is About's two-line minimum (FR-047) consistent with the design's "otherwise hidden"? [Consistency, Spec §FR-047] — Consistent: at supported sizes the budget leaves About at least two lines; hiding happens only below the supported size, where FR-036 drops lines from the top (design D9 steps 4–5).
- [x] CHK033 - Is the banner choice specified with measurable thresholds? [Measurability, Spec §FR-037] — FR-037; US4-10 (88×40 vs 88×39).

## Requirement Completeness — Rendering

- [x] CHK034 - Is a whole-frame repaint specified on a width or height change? [Completeness, Spec §FR-039] — FR-039; US6-4.
- [x] CHK035 - Is it specified when the repaint happens after a resize with no other input? [Clarity, Spec §Edge Cases] — Edge Cases › Terminal resized ("the next draw"), as in 1.7, which has no resize signal handler.
- [x] CHK036 - Is the `Loading` style specified? [Completeness, Spec §FR-040] — FR-040; delta scenario "First frame while loading" (`ESC [5m`).
- [x] CHK037 - Are the panel-border formats specified (`I of N installed`, `a–b of n`, `PgUp/PgDn scroll`)? [Completeness, Spec §FR-044, §FR-046] — FR-044, FR-046; US2-9.
- [ ] CHK038 - Is "installed" defined for `I of N installed` and the category counts (do `needs creds` or `image only` count)? [Gap, Spec §FR-041, §FR-044] — **Open**: these counts are new in the wizard. → NB-11.

## Requirement Consistency

- [x] CHK039 - Are the width thresholds (36, 42, 50, 60, 70, 80, 87) consistent across FRs, edge cases and design? [Consistency] — FR-021/FR-022 (60), FR-044 (70, 50), FR-037 (42), FR-033 (36, 87), FR-007 (80); design › Layout and Height Rules.
- [x] CHK040 - Are the height thresholds (24, 40) consistent across FR-034, FR-037 and SC-002? [Consistency] — Yes.
- [x] CHK041 - Is SC-002's render matrix consistent with US4's Independent Test? [Consistency, Spec §SC-002] — SC-002 is a subset; US4 adds 88×39, 88×40 and 120 columns.

## Scenario Coverage

- [x] CHK042 - Primary: are the standard 80×24 and roomy 88×40 layouts covered? [Coverage, Primary] — US4-4, US4-5, US4-6.
- [x] CHK043 - Alternate: are 36-, 40- and 60-column frames and unknown height covered? [Coverage, Alternate] — US4-8, US4-12, US4-13, US4-16.
- [x] CHK044 - Exception: are terminals below the supported size covered? [Coverage, Exception] — FR-033, FR-036; US4-9.
- [x] CHK045 - Recovery: is a mid-session resize covered? [Coverage, Recovery] — Edge Cases; US6-4.
- [x] CHK046 - Non-functional: is layout work bounded by the key budget? [Coverage, Non-Functional] — FR-060 (height budgeting and About wrapping are named in SC-006).

## Notes

- 46 items: 43 satisfied — 40 as written, 3 closed by wording in this pass — and 3 open (NB-6, NB-11, NB-12).
- The hint-line count between 60 and 79 columns also affects the height budget; it is tracked once, in [ux.md](ux.md) CHK062 (NB-4).
