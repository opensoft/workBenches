# Security and Safety Checklist: Guided setup wizard

**Purpose**: Release-gate unit tests for the safety requirements: name-safe catalog lookups, fail-closed bench paths, hostile catalog text, input validation, selection-file and status-file protection, and the gates that stop unreviewed changes.
**Created**: 2026-10-21
**Feature**: [spec.md](../spec.md) · OpenSpec change [`setup-guided-wizard`](../../../openspec/changes/setup-guided-wizard/) (deltas `bench-catalog`, `setup-bench-browser`, `setup-wizard-flow`)
**Depth**: release gate, maximum coverage (no item cap) · **Audience**: reviewers before `/speckit-plan`
**Scenario classes**: Primary, Alternate, Exception/Error, Recovery, Non-Functional

**Legend**: `[x]` satisfied, with a pointer · `[x] … Fixed:` gap closed by wording (spec and delta updated) · `[x] … Resolved:` closed by Brett's decision (NB-n, [README](README.md) › Needs Brett) · `[ ]` open

## Requirement Completeness — Name-safe lookups

- [x] CHK001 - Is the safe-lookup rule specified for every shell consumer and for both catalog sections (benches and infrastructure)? [Completeness, Spec §FR-056] — FR-056; delta › Name-safe catalog lookups.
- [x] CHK002 - Are the affected consumers enumerated, with a rule covering consumers found later? [Coverage, Spec §FR-056] — FR-056 names four consumers and says "every script"; OpenSpec `tasks.md` 2.1 adds "any other shell consumer found".
- [x] CHK003 - Is the static guard precise enough to fail on a reintroduced interpolation? [Measurability, Spec §FR-057] — FR-057; delta scenario (no jq filter builds a `.benches.` or `.infrastructure.` path from a shell variable).
- [x] CHK004 - Is a behavioural proof required for each shell consumer? [Measurability, Spec §FR-057, §SC-004] — FR-057; SC-004 (4 of 4); US5-6.
- [x] CHK005 - Is digit-leading coverage extended to the Python consumers, or the assumption that they already index by name explicitly accepted? [Assumption, Spec §Assumptions] — **Resolved** (NB-8 A, Brett Heap, 2026-10-21): FR-057 and delta › Name-safe catalog lookups extend the fixture test to the four Python consumers; SC-004 counts 8 of 8; US5-6.
- [x] CHK006 - Is it required that the safe lookups land with or before the new benches are offered? [Dependency] — US5 priority note; design › Risks; OpenSpec `tasks.md` § 2 heading.

## Requirement Completeness — Fail-closed bench paths

- [x] CHK007 - Is the fail-closed trigger defined precisely (what counts as a path under a bench root)? [Clarity, Spec §FR-058] — **Fixed**: FR-058 and delta › Unresolved bench paths fail closed: a relative path that starts with `devBenches/`, `sysBenches/` or `bioBenches/` and has no `..` segment, the rule `setup_selection.py` already applies (design D13).
- [x] CHK008 - Are the forbidden actions on failure enumerated? [Completeness, Spec §FR-058] — FR-058 (git, clone, setup script, the root as a bench directory); US5-8.
- [x] CHK009 - Is the failure reported to the user and reflected in the run's result? [Gap, Spec §FR-058] — **Fixed**: FR-058 and delta: reported as failed "like any other failed component" (1.7's apply summary and exit status).
- [x] CHK010 - Is the protection measurable? [Measurability, Spec §SC-004] — SC-004 (zero git, clone or setup-script runs in the root).

## Requirement Completeness — Untrusted display text

- [x] CHK011 - Is catalog text treated as untrusted for the terminal, with the reason stated? [Completeness, Spec §FR-048] — US7 priority note; FR-048; Edge Cases.
- [x] CHK012 - Is "control characters" defined, including C1 controls that some terminals act on? [Clarity, Spec §FR-048, §FR-053] — **Fixed**: FR-048 and delta › Metadata delivery: U+0000–U+001F and U+007F–U+009F, including ESC and tab; FR-053 and delta › Bench presentation fields use the same definition.
- [x] CHK013 - Is sanitising required both in the catalog test (reject) and at display (replace)? [Completeness, Spec §FR-053, §FR-048] — FR-053, FR-048.
- [x] CHK014 - Is the escape-sequence outcome measurable? [Measurability, Spec §SC-011] — US7-2; SC-011 (never cleared or restyled).
- [x] CHK015 - Is the sanitising rule's scope decided for other external text the TUI shows (status details from the worker, the identities summary)? [Gap, Spec §FR-048] — **Resolved** (NB-7 A, Brett Heap, 2026-10-21): FR-048, SC-011 and delta › Metadata delivery: every text the TUI did not write; US7-7.
- [x] CHK016 - Are wide, combining, zero-width and bidi characters addressed (misaligned or misleading display)? [Gap, Spec §FR-053] — **Resolved** (NB-6 A, Brett Heap, 2026-10-21): FR-053 and delta › Bench presentation fields: the catalog test rejects them.
- [x] CHK017 - Are validation rules for bench names and category ids specified? [Clarity, Spec §FR-048] — FR-048; patterns in design D12.
- [x] CHK018 - Is it specified that the foreground never evaluates catalog text? [Completeness, Spec §FR-048] — FR-048 (read without external tools); design D12 (read into arrays; renderer reads only those).

## Requirement Completeness — Data integrity and provenance

- [x] CHK019 - Do clone URLs come only from locked repositories? [Completeness, Spec §FR-054] — FR-054 (catalog path and URL must match the release lock); US5-3.
- [x] CHK020 - Is the selection file's write protection specified (private, never through a symlink)? [Gap, Spec §FR-015] — **Fixed**: FR-015 and delta › Setup contracts unchanged now keep how the file is written (1.7 writes it 0600 with `O_NOFOLLOW`).
- [x] CHK021 - Is validation of selection files naming the new benches specified? [Completeness, Spec §FR-054] — US5-4; `setup_selection.py` applies the bench-root path rule.
- [x] CHK022 - Are private status files and their removal specified? [Completeness, Spec §FR-027] — FR-027.

## Requirement Completeness — Safety gates

- [x] CHK023 - Is Apply gated on readiness and on Review? [Completeness, Spec §FR-013, §SC-001] — FR-013; SC-001.
- [x] CHK024 - Are risky optional changes flagged before Apply? [Completeness, Spec §FR-010] — FR-010; US1-8.
- [x] CHK025 - Are removals shown before Apply, with what they keep? [Completeness, Spec §FR-009] — FR-009 (REMOVE note added in [ux.md](ux.md) CHK021).
- [x] CHK026 - Is Profiles access gated on readiness? [Completeness, Spec §FR-020] — FR-020; US1-17.
- [x] CHK027 - Are credential flows (Vault Connect, Profiles internals) left unchanged? [Scope] — Assumptions › Unchanged and › Out of scope.

## Scenario Coverage

- [x] CHK028 - Exception: is a hostile catalog (escape sequences, invalid names and ids) covered? [Coverage, Exception] — US7 Independent Test; SC-011.
- [x] CHK029 - Recovery: is the outcome defined after a bench fails closed (other components continue; the run reports the failure)? [Coverage, Recovery] — FR-058 ("like any other failed component"); FR-015.
- [x] CHK030 - Are the trust assumptions for each input stated where they matter (catalog text, worker output, selection file, bench paths)? [Traceability] — FR-048, FR-015, FR-058; US7.

## Notes

- 30 items, all satisfied: 23 as written, 4 closed by wording, 3 resolved by Brett's decisions (NB-6, NB-7, NB-8); none open.
- Fixes recorded in other checklists and only referenced here: CHK025.
