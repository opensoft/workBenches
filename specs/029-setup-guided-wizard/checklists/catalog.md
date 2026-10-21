# Bench Catalog Data Checklist: Guided setup wizard

**Purpose**: Release-gate unit tests for the bench catalog's data requirements: categories, presentation fields and copy, completeness against the release lock, accuracy, ordering, metadata format and maintenance scripts.
**Created**: 2026-10-21
**Feature**: [spec.md](../spec.md) · OpenSpec change [`setup-guided-wizard`](../../../openspec/changes/setup-guided-wizard/) (deltas `bench-catalog`, `setup-bench-browser`) · copy draft [`bench-copy-draft.json`](../bench-copy-draft.json)
**Depth**: release gate, maximum coverage (no item cap) · **Audience**: reviewers before `/speckit-plan`
**Scenario classes**: Primary, Alternate, Exception/Error, Recovery, Non-Functional

**Legend**: `[x]` satisfied, with a pointer · `[x] … Fixed:` gap closed by wording (spec and delta updated) · `[x] … Resolved:` closed by Brett's decision (NB-n, [README](README.md) › Needs Brett) · `[ ]` open

## Requirement Completeness — Categories

- [x] CHK001 - Are the category ids, their fields and the field types specified? [Completeness, Spec §FR-052] — FR-052; delta › Bench categories; US5-1.
- [x] CHK002 - Is the category display order defined, including ties on `order`? [Clarity, Spec §FR-041] — **Fixed**: FR-041 and delta › Category block: by `order`, then id (design D6).
- [x] CHK003 - Is the bench population per category specified (Electrical Engineering empty, the others at least one)? [Completeness, Spec §FR-052] — FR-052; US5-1.
- [x] CHK004 - Is the UI meaning of a category without benches specified? [Completeness, Spec §FR-041] — FR-041 (dim, `coming soon`, never focusable); Q13.
- [x] CHK005 - Are category labels bounded for narrow frames? [Edge Case, Spec §FR-033] — Every line is bounded by FR-033; the four labels are fixed catalog data of at most 22 characters.
- [x] CHK006 - Are Science sub-groups explicitly out of scope? [Scope] — Q17; Assumptions › Out of scope.

## Requirement Completeness — Presentation fields and copy

- [x] CHK007 - Are all per-bench presentation fields, their types and limits specified? [Completeness, Spec §FR-053] — FR-053; US5-2.
- [x] CHK008 - Is "control characters" defined precisely enough to test? [Clarity, Spec §FR-053] — Fixed in [security.md](security.md) CHK012; FR-053 now refers to FR-048's definition.
- [x] CHK009 - Is the version-token rule deterministic and consistent with the approved draft, which contains `ARM64`, `MMseqs2`, `py3Dmol` and `m365`? [Clarity, Conflict, Spec §FR-053] — **Fixed**: FR-053 and delta › Bench presentation fields: a number is standalone when it is not joined to a letter, so those names are accepted (FR-053 also requires building from the draft).
- [x] CHK010 - Is the product-name allow-list specified and closed? [Completeness, Spec §FR-053] — FR-053 (`Microsoft 365`, `Dynamics 365`); US5-2.
- [x] CHK011 - Is the catalog test's failure output specified (bench and token named)? [Measurability, Spec §FR-053] — FR-053; US5-2.
- [x] CHK012 - Is the allowed character repertoire for presentation text specified (single-column only; no combining, zero-width or bidi characters)? [Gap, Spec §FR-053] — **Resolved** (NB-6 A, Brett Heap, 2026-10-21): FR-053 and delta › Bench presentation fields (bench copy and category label and summary); US5-2; delta scenario "Character wider or narrower than one column".
- [x] CHK013 - Are the copy's source, its approval gate and how that approval is recorded specified? [Completeness, Spec §FR-053, §SC-013] — **Fixed**: FR-053 and SC-013 now say the approval records who, date and commit in this feature (OpenSpec `tasks.md` 7.2).
- [x] CHK014 - Is it specified which draft fields enter the catalog (and that `draft` and `evidence` do not)? [Clarity, Spec §FR-053] — FR-053's field list; OpenSpec `tasks.md` 2.3.
- [x] CHK015 - Is the accuracy rule specified with a testable instance? [Measurability, Spec §FR-055] — FR-055; US5-5 (simBench).
- [x] CHK016 - Are the known doubts in the draft (365Bench mailbox migration comes from a bundled skill; pyBench's ROCm item is optional and WSL-only) routed to the approval gate? [Assumption, Spec §FR-053] — `clarify-questions.md` Q5 notes; FR-053 merge gate.
- [x] CHK017 - Is the expectation for keeping copy accurate after bench images change documented? [Completeness] — design › Risks ("Copy drifts from bench images"); FR-055.

## Requirement Completeness — Completeness against the release lock

- [x] CHK018 - Is the catalog ↔ release-lock relation specified in both directions, with matching path and URL? [Completeness, Spec §FR-054] — FR-054; US5-3; SC-003.
- [x] CHK019 - Is "bench repository recorded in the release lock" unambiguous? [Clarity, Spec §FR-054] — `config/release-lock.json` `repositories[]` holds exactly the 12 bench paths under `devBenches/`, `sysBenches/` and `bioBenches/`; FR-058 names the same roots.
- [x] CHK020 - Are the three new entries' paths specified? [Completeness, Spec §FR-054] — FR-054.
- [x] CHK021 - Are the new entries' URL, description and AI keywords sourced? [Completeness] — `bench-copy-draft.json` › `newBenches`; OpenSpec `tasks.md` 2.3.
- [x] CHK022 - Is the exclusion of local-only clones explicit? [Scope, Spec §FR-054] — FR-054; Q10.
- [x] CHK023 - Is propagation to selection files and the credential requirements specified? [Completeness, Spec §FR-054] — FR-054; US5-4.

## Requirement Completeness — Maintenance scripts

- [x] CHK024 - Is preservation of `categories` and every existing per-bench field specified for both scripts? [Completeness, Spec §FR-059] — FR-059; US5-9.
- [x] CHK025 - Is category derivation for an added bench specified for every bench root? [Completeness, Spec §FR-059, §FR-050] — FR-059 with FR-050's path map.
- [x] CHK026 - Is it specified how the scripts meet the lock-only rule (regeneration discovers local clones such as phpBench; `new-bench.sh` adds a bench before it has a lock entry or copy)? [Conflict, Spec §FR-054 vs §FR-059] — **Resolved** (NB-9 A, Brett Heap, 2026-10-21): FR-059 and delta › Maintenance scripts: regeneration skips unlocked benches with a warning; `new-bench.sh` still adds its entry, and the docs say a lock entry and copy come first; US5-9; delta scenario "Regeneration skips unlocked clones".
- [x] CHK027 - Does regeneration preserve `ai_keywords` and `project_scripts`, which it used to drop? [Completeness, Spec §FR-059] — FR-059 ("every existing per-bench field"); US5-9 names `ai_keywords`; design › Risks.

## Requirement Completeness — Data contract

- [x] CHK028 - Are the catalogued bench's fields listed as an entity? [Completeness, Spec §Key Entities] — Key Entities › Catalogued bench.
- [x] CHK029 - Is the bench-name format part of the contract? [Clarity, Spec §FR-048] — FR-048 (names failing validation are ignored); pattern `^[a-zA-Z0-9_+-]+$` in design D12; SC-003 requires all 12 to be offered.
- [x] CHK030 - Is the category-id format part of the contract? [Clarity, Spec §FR-048] — FR-048; pattern `^[a-z0-9][a-z0-9-]*$` in design D12.
- [x] CHK031 - Is additive compatibility stated (existing consumers ignore the new fields)? [Assumption] — Assumptions › No data migration; design D11. The Python consumers' name handling is now proven by test ([security.md](security.md) CHK005, NB-8).
- [x] CHK032 - Is the metadata format published by the worker specified? [Completeness, Spec §FR-048] — FR-048 (atomic, complete before visible); design D12 and › Data Flow (TSV, `-` for empty, `|` between list items).
- [x] CHK033 - Is escaping specified for a `|` inside a list item? [Edge Case] — design D12 (it becomes `/`).
- [x] CHK034 - Is bench order within a category precise (case and digits)? [Clarity, Spec §FR-044] — **Fixed**: FR-044 and delta › Bench panel: code-point order of bench names, as 1.7 lists them, so 365Bench precedes cloudBench (design D6; Q12).
- [x] CHK035 - Is the selection-file entity unchanged and versioned? [Consistency, Spec §FR-015] — FR-015; Key Entities › Selection file.

## Scenario Coverage

- [x] CHK036 - Primary: is a healthy 12-bench catalog covered? [Coverage, Primary] — US2; US5.
- [x] CHK037 - Alternate: are a bench without a category, an unknown category id and missing metadata covered? [Coverage, Alternate] — FR-050; US7-4, US7-5.
- [x] CHK038 - Exception: does an invalid catalog fail the test and name the bench (tagline length, version token, control characters)? [Coverage, Exception] — FR-053; US5-2.
- [x] CHK039 - Recovery: is rollback of the catalog changes defined? [Coverage, Recovery] — Assumptions › Rollback; design › Migration Plan 4.
- [x] CHK040 - Non-functional: is the full catalog with long About text part of the timing workload? [Coverage, Non-Functional] — US6-6; design D19.

## Notes

- 40 items, all satisfied: 34 as written, 4 closed by wording, 2 resolved by Brett's decisions (NB-6, NB-9); none open.
- Fixes recorded in other checklists and only referenced here: CHK008 ([security.md](security.md) CHK012).
