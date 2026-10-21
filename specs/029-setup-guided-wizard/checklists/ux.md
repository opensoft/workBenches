# Interaction and UX Flow Checklist: Guided setup wizard

**Purpose**: Release-gate unit tests for the wizard's interaction requirements: step model, nav bar, Enter → Review → Apply, step content, Benches zones, jumps and global keys, footer and hints.
**Created**: 2026-10-21
**Feature**: [spec.md](../spec.md) · OpenSpec change [`setup-guided-wizard`](../../../openspec/changes/setup-guided-wizard/) (deltas `setup-wizard-flow`, `setup-bench-browser`)
**Depth**: release gate, maximum coverage (no item cap) · **Audience**: reviewers before `/speckit-plan`
**Scenario classes**: Primary, Alternate, Exception/Error, Recovery, Non-Functional

**Legend**: `[x]` satisfied, with a pointer · `[x] … Fixed:` gap closed by wording (spec and delta updated) · `[x] … Resolved:` closed by Brett's decision (NB-n, [README](README.md) › Needs Brett) · `[ ]` open

## Requirement Completeness — Steps and navigation

- [x] CHK001 - Are the full step set and its fixed order specified, including the name used for the former "AI assistants" step wherever a step is named? [Completeness, Spec §FR-001] — FR-001; Clarifications Q1.
- [x] CHK002 - Is the opening step specified? [Completeness, Spec §FR-002] — FR-002; Q2.
- [x] CHK003 - Is ←/→ behaviour at both ends of the step sequence specified? [Completeness, Spec §FR-003] — FR-003 (no wrap); US1-3.
- [x] CHK004 - Is ↑/↓ behaviour at the first and last row of a step specified (stop or wrap)? [Gap, Spec §FR-003] — **Fixed**: FR-003 and delta › Step navigation now say ↑/↓ stop at the first and last rows without wrapping, as 1.7 does (`handle_input`), except where the Benches zones define otherwise; matches the delta scenario "stops at the last row".
- [x] CHK005 - Is separator skipping specified for steps that have separators? [Completeness, Spec §FR-003] — FR-003; delta scenario "Vertical keys stay within the step".
- [x] CHK006 - Is the focus on arrival by ← or → specified for every step, including the Benches zone and category? [Completeness, Spec §FR-004] — FR-004; Q8.
- [x] CHK007 - Is the focus on arrival by P (Workstation) and by G (Profiles) specified? [Gap, Spec §FR-023, §FR-024] — **Fixed**: FR-023/FR-024 and both jump deltas now focus the first row, as 1.7's P and G do.
- [x] CHK008 - Is Review's starting scroll position specified when Review is reached by Enter or by a P/G return? [Gap, Spec §FR-004, §FR-012] — **Resolved** (NB-14 A, Brett Heap, 2026-10-21): FR-012 and delta › Review: opens at the first item by Enter or ←/→; a P or G return restores the position; US1-21.
- [x] CHK009 - Is a focus indicator specified for the focused row on every step that has rows? [Gap, Spec §FR-004, §FR-044] — Fixed in [accessibility.md](accessibility.md) CHK005 (FR-004 now requires `›`).

## Requirement Completeness — Nav bar

- [x] CHK010 - Are the nav marks for earlier, current and later steps and the count rule defined for every step? [Completeness, Spec §FR-005] — FR-005; US1-4.
- [x] CHK011 - Is it specified, with a reason, that Profiles never shows a count? [Completeness, Spec §FR-005] — FR-005; Q19.
- [x] CHK012 - Is the Workstation readiness mark defined for all three readiness states? [Completeness, Spec §FR-006] — FR-006; US1-5.
- [x] CHK013 - Is the Workstation item's look specified when Workstation is itself the current step (current-step highlight or readiness mark)? [Clarity, Spec §FR-005, §FR-006] — **Fixed**: FR-006 and delta › Top nav bar: the item takes the highlight and keeps the readiness mark (design D5 measures the nav with the highlight; Workstation mockup).
- [x] CHK014 - Is "every required item" (the services that decide readiness) defined? [Clarity, Spec §Key Entities] — Key Entities › Workstation readiness (WSL 2 on WSL, Docker, Tools; Vault optional).
- [x] CHK015 - Is the switch between the full and compact nav defined by a measurable condition? [Measurability, Spec §FR-007] — FR-007 ("whenever it fits the frame"; 79 columns with three single-digit counts, 80 with a two-digit count); SC-002; US4-15.
- [x] CHK016 - Does the compact nav say whether queued counts appear in it? [Gap, Spec §FR-007] — **Resolved** (NB-3 A, Brett Heap, 2026-10-21): FR-007 and delta › Top nav bar: no counts; the footer keeps the total; US4-13.

## Requirement Completeness — Enter, Review and Apply

- [x] CHK017 - Is Enter's meaning defined for every step and Benches zone (row action, open Review, apply)? [Completeness, Spec §FR-008, §FR-013] — FR-008, FR-013; design › Key Map.
- [x] CHK018 - Is it explicit that Enter on a Workstation or Profiles row leaves queued changes unchanged and does not open Review? [Clarity, Spec §FR-008] — FR-008; US1-15.
- [x] CHK019 - Are Review's grouping, per-item step names and its "Nothing has changed yet" statement specified? [Completeness, Spec §FR-009] — FR-009; US1-7.
- [x] CHK020 - Is the order of items inside each Review group specified? [Gap, Spec §FR-009] — **Fixed**: FR-009 and delta › Review lists every queued change: "in step order" (design D15).
- [x] CHK021 - Does Review say what a removal keeps? [Gap, Spec §FR-009] — **Fixed**: FR-009 and delta: the REMOVE group notes that projects and credentials are kept (design D15).
- [x] CHK022 - Are the risky-change warnings specified with their triggers and wording? [Completeness, Spec §FR-010] — FR-010; US1-8.
- [x] CHK023 - Is the empty Review state specified? [Completeness, Spec §FR-011] — FR-011; US1-14.
- [x] CHK024 - Is Review's behaviour specified when the list is taller than its rows, so every item can be displayed? [Coverage, Spec §FR-012] — FR-012; Q4; design D15.
- [x] CHK025 - Is Review explicitly read-only, naming where the queue is changed instead? [Clarity, Spec §FR-012] — FR-012; Q4.
- [x] CHK026 - Are both Apply blockers and their messaging specified, including whether the blocker shows before Enter is pressed? [Clarity, Spec §FR-013] — **Fixed**: FR-013 and delta › Apply from Review: a yellow blocker line shows while Apply is blocked (design D15).
- [x] CHK027 - Is it specified whether the readiness gate also applies to Enter on an empty Review? [Ambiguity, Spec §FR-013, §FR-014] — **Fixed**: FR-014 and delta: same gate, as 1.7's empty Enter (gated before it returns to apply).
- [x] CHK028 - Is what happens after a successful Apply defined? [Completeness, Spec §FR-013, §FR-015] — FR-013 ("as Enter did before this change"), FR-015 (apply semantics unchanged); US1-11.

## Requirement Completeness — Step content

- [x] CHK029 - Are Workstation's panels, rows, state/action format, explanation placement and `G Profiles` pointer specified? [Completeness, Spec §FR-016] — FR-016; Q9, Q18.
- [x] CHK030 - Are Space, Enter and D defined on Workstation rows? [Completeness, Spec §FR-017] — FR-017.
- [x] CHK031 - Is a Workstation row action specified while that row is still Loading? [Gap, Spec §FR-017] — **Fixed**: FR-017 and delta › Workstation step: no action runs and the step says checks are still loading, as 1.7's `activate_requirement` does.
- [x] CHK032 - Are the Agents and Tools items, order and selection rules specified, including the configure-only items? [Completeness, Spec §FR-018] — FR-018; US1-10.
- [x] CHK033 - Is the effect of Space on an item queued for removal (and D on one queued for install or update) specified? [Clarity, Spec §FR-018, §FR-043] — By reference: "the same … selection rules as before this change" (1.7 replaces the queued action, and pressing the same key again unqueues it); SC-010 keeps the suites that assert it.
- [x] CHK034 - Are the Profiles selector line, rows and About panel specified? [Completeness, Spec §FR-019, §FR-030] — FR-019, FR-030; design D14.
- [x] CHK035 - Are the Profiles About panel's size and scrolling specified? [Gap, Spec §FR-019] — **Fixed**: FR-019 and delta › Profiles step: fixed text, two to eight lines with a known height, FR-046's keys, markers and reset (design › Key Map and Layout and Height Rules).
- [x] CHK036 - Are all Profiles action outcomes and their notices specified, including failure? [Completeness, Spec §FR-020] — **Fixed**: FR-020 adds "Profile action needs attention. Open it to retry.", 1.7's notice for a failed action.
- [x] CHK037 - Is the Profiles readiness gate specified with its notice? [Completeness, Spec §FR-020] — FR-020; US1-17.

## Requirement Completeness — Benches zones and About

- [x] CHK038 - Are all category-zone keys specified (↑/↓, Tab, Shift+Tab, Space, D, Enter)? [Completeness, Spec §FR-042, §FR-008] — FR-042, FR-008; US2-2, US2-4.
- [x] CHK039 - Is ↑ on the first focusable category specified? [Gap, Spec §FR-042] — **Fixed**: by FR-003's new stop rule (the category zone is part of the step and only ↓ on the last category is defined otherwise).
- [x] CHK040 - Are the bench-zone keys, including both ways back to the category zone, specified? [Completeness, Spec §FR-043] — FR-043; US2-5.
- [x] CHK041 - Is Space in the category zone defined so it can never queue? [Clarity, Spec §FR-042] — FR-042; delta scenario "Space does not queue in the category zone".
- [x] CHK042 - Are the focus rules for coming-soon categories specified? [Completeness, Spec §FR-041] — FR-041; US2-3.
- [x] CHK043 - Is the About panel's content defined for both zones? [Completeness, Spec §FR-045] — FR-045; US2-8.
- [x] CHK044 - Are About's scroll keys, step size, clamping, markers and reset triggers specified? [Completeness, Spec §FR-046] — FR-046; US2-9, US2-10.
- [x] CHK045 - Is it specified whether About keeps its scroll offset when the same bench's details are refreshed? [Gap, Spec §FR-046, §FR-051] — **Resolved** (NB-5 A, Brett Heap, 2026-10-21): FR-046 and delta › About scrolling: the offset is kept, clamped to the new text.

## Requirement Completeness — Jumps and global keys

- [x] CHK046 - Are P's writes and reads of its return target fully specified, including the default? [Completeness, Spec §FR-023] — FR-023; Key Entities › Return target; US3-1 to US3-3.
- [x] CHK047 - Is every transition that writes the G return target specified? [Completeness, Spec §FR-024] — FR-024 (G, → from Tools, ← from Review); US3-4.
- [x] CHK048 - Are the readiness jump's trigger, destination, focus and notice specified? [Completeness, Spec §FR-028] — FR-028; Q16; US3-5.
- [x] CHK049 - Is the readiness jump specified when Workstation is already shown? [Gap, Spec §FR-028] — **Fixed**: FR-028 and delta › Readiness jump: the remembered P target is kept, as 1.7's `poll_status_loader` does.
- [x] CHK050 - Is V specified from every step, while loading, and for its result notice? [Completeness, Spec §FR-025] — FR-025; US3-6, US3-7.
- [x] CHK051 - Is it specified that V is advertised only on Workstation while working on every step? [Consistency, Spec §FR-022, §FR-025] — FR-022, FR-025; US3-8.
- [x] CHK052 - Is R's effect on step, focus and queue specified? [Completeness, Spec §FR-026] — FR-026; US3-9.
- [x] CHK053 - Is Q specified from every step, including while checks run? [Completeness, Spec §FR-027] — FR-027; US3-10.
- [x] CHK054 - Is a notice's lifetime specified (does it follow the user to another step, and what clears it)? [Ambiguity, Spec §FR-032] — **Fixed**: FR-032 and delta › Notices: as in 1.7, a notice stays on whichever step is current until a later notice replaces it, a service action starts or R clears it.
- [x] CHK055 - Are keys with no meaning specified for each step (D on Workstation, the category zone and Profiles; Space on Review; Tab outside Benches; PgUp/PgDn without an About panel)? [Coverage, Spec §Edge Cases] — Edge Cases › Keys with no meaning; design › Key Map (`—` cells).

## Requirement Completeness — Footer and hints

- [x] CHK056 - Is the context-line format specified for a focused item with and without a queued action? [Completeness, Spec §FR-021] — FR-021; US1-18.
- [x] CHK057 - Is the context line specified where nothing is focused or the focused row has no state (Review, Profiles rows, Benches while `Loading benches…`)? [Gap, Spec §FR-021] — **Resolved** (NB-1 A, Brett Heap, 2026-10-21): FR-021 and delta › Footer: `Review · Nothing applied yet`, the Profiles row name, `Loading benches…`; total at the right; US1-21, delta scenario "Context without a focused item".
- [x] CHK058 - Is "the category summary" on the context line unambiguous (the counts shown in the category block, or the catalog's `summary` text)? [Ambiguity, Spec §FR-021 vs §FR-052] — **Resolved** (NB-2 A, Brett Heap, 2026-10-21): FR-021 and delta › Footer: the category name and its counts as in the block (`Science · 2 benches · 1 installed`); delta scenario "Context in the category zone".
- [x] CHK059 - Is the queued-total label specified for both width bands, with the cut marker? [Completeness, Spec §FR-021] — FR-021; Q20; US4-16.
- [x] CHK060 - Is the hints' leading label, which acceptance suites wait on, specified? [Gap, Spec §FR-022] — **Fixed**: FR-022 and delta › Footer: hints begin with `Navigation:` on every step, as in 1.7 (design › Acceptance-suite impact).
- [x] CHK061 - Are the hints specified per step and per width band (60+ columns vs below 60)? [Completeness, Spec §FR-022] — FR-022; Q7; design D16 and mockups for the full lists.
- [x] CHK062 - Is the number of hint lines specified between 60 and 79 columns? [Gap, Spec §FR-022] — **Resolved** (NB-4 A, Brett Heap, 2026-10-21): FR-022 and delta › Footer: the full list, wrapped over as many lines as it needs, within SC-002's height bounds; design D16 and layout table.

## Requirement Consistency

- [x] CHK063 - Do Enter's semantics agree across FR-008, FR-017, FR-020, the Key Map and US1-15/US2-4? [Consistency] — Agree.
- [x] CHK064 - Do the default return targets agree across FR-023, FR-024 and Key Entities › Return target? [Consistency] — **Fixed**: FR-024 ("Benches category zone") and Key Entities ("its first category") now read, with FR-023, "the first category that has benches" (FR-004's arrival rule).
- [x] CHK065 - Is the step name Agents used consistently, with the Profiles row "AI accounts" kept on purpose? [Consistency, Spec §FR-001] — FR-001; Assumptions › Naming.
- [x] CHK066 - Do the queued-change actions in Key Entities agree with Review's three groups? [Conflict, Spec §Key Entities vs §FR-009] — **Fixed**: Key Entities › Queued change listed a "configure" action; it now says Shell setup and Org workspace are configured through an install action and listed under INSTALL (1.7 queues them as `install`; Review mockup).
- [x] CHK067 - Is the different status vocabulary on rows (`Installed`) and in the context line (`Ready`) intentional and traceable? [Consistency, Spec §US1-18 vs §US2-7] — Intentional: the context line keeps 1.7's format, which acceptance suites wait on (design D16).
- [x] CHK068 - Does FR-049 (nothing queueable until details arrive) agree with FR-050 (benches selectable when checks finish without details)? [Conflict, Spec §FR-049 vs §FR-050] — **Fixed**: FR-049 and delta › Metadata delivery: "or checks have finished without the details".

## Acceptance Criteria Quality

- [x] CHK069 - Can "only Enter on Review applies" be verified objectively? [Measurability, Spec §SC-001] — SC-001.
- [x] CHK070 - Can P/G round-trip restoration be measured? [Measurability, Spec §SC-008] — SC-008; US3-1 to US3-4.
- [x] CHK071 - Can the hint and context-line rules be checked from a rendered frame? [Measurability, Spec §FR-021, §FR-022] — Yes: exact strings and line caps (US1-18, US3-8, US4-16).

## Scenario Coverage

- [x] CHK072 - Primary: is the end-to-end path from Workstation through Review to Apply covered? [Coverage, Primary] — US1 Independent Test; SC-012.
- [x] CHK073 - Alternate: are non-linear paths covered (P/G jumps, Enter from any step, ← from Review)? [Coverage, Alternate] — US3; FR-008; FR-024.
- [x] CHK074 - Exception: are a blocked Apply, a refused Profiles action, V while loading and cancelled helpers covered? [Coverage, Exception] — US1-12, US1-17, US3-6, US3-7.
- [x] CHK075 - Recovery: is the way back after a readiness jump defined and tested? [Coverage, Recovery] — FR-028; US3-5.
- [x] CHK076 - Recovery: are step, focus and queue restored after a cancelled Vault Connect or Profiles action? [Coverage, Recovery] — FR-020, FR-025; US3-6; Edge Cases.
- [x] CHK077 - Non-functional: is navigation responsiveness bounded? [Coverage, Non-Functional] — FR-060 (see [performance.md](performance.md)).

## Edge Case Coverage

- [x] CHK078 - Are "Enter twice with nothing queued" and "more changes than rows" covered? [Edge Case] — Edge Cases; US1-9, US1-14.
- [x] CHK079 - Is the behaviour decided when the focused or remembered bench leaves a refreshed catalog? [Assumption, Spec §Edge Cases] — **Resolved** (NB-5 A, Brett Heap, 2026-10-21): FR-051 and delta › Focus survives: fall back to the category zone on the same category (or the first with benches) and drop that bench's queued change; Edge Cases; US7-10.
- [x] CHK080 - Is it accepted that the readiness jump can take the user off Review after R? [Edge Case, Spec §FR-028] — Q16; Assumptions › The readiness jump.
- [x] CHK081 - Is the TUI's state on return from an interactive helper specified? [Edge Case, Spec §FR-020, §FR-025, §FR-039] — Focus and queue kept (FR-020, FR-025); whole-frame repaint (FR-039).

## Dependencies & Assumptions

- [x] CHK082 - Is reliance on 1.7 behaviour ("as before this change") pinned by tests? [Assumption] — SC-010 (zero asserted outcomes removed); baseline `release/1.7.0` at `ccc9eac` (proposal › Handoff).
- [x] CHK083 - Is the prototype's status stated so its behaviour is not taken as a requirement? [Assumption] — Assumptions › The prototype.

## Notes

- 83 items, all satisfied: 59 as written, 17 closed by wording, 7 resolved by Brett's decisions (NB-1, NB-2, NB-3, NB-4, NB-5 ×2, NB-14); none open.
- Fixes recorded in other checklists and only referenced here: CHK009 ([accessibility.md](accessibility.md) CHK005).
