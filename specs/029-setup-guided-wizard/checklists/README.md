# Checklists: Guided setup wizard

**Feature**: [`029-setup-guided-wizard`](../spec.md) · **OpenSpec change**: [`setup-guided-wizard`](../../../openspec/changes/setup-guided-wizard/)
**Run**: `/speckit-checklist` with no argument (maximum-coverage mode of the user-global skill), 2026-10-21. Clarifying questions skipped; one checklist per requirement-quality domain at release-gate depth, with no item cap and all five scenario classes (Primary, Alternate, Exception/Error, Recovery, Non-Functional).
**Evaluated against**: `spec.md`, the four OpenSpec deltas, `design.md`, `proposal.md`, `tasks.md`; where a requirement says "as before this change" or "as in 1.7", the 1.7 baseline in `scripts/interactive-setup.sh` and `scripts/lib/setup-status-loader.sh` (`release/1.7.0` at `ccc9eac`).

## Summary

| Checklist | Domain | Items | Passed as written | Fixed by wording | Open |
|---|---|---:|---:|---:|---:|
| [ux.md](ux.md) | Interaction and UX flow | 83 | 59 | 17 | 7 |
| [layout.md](layout.md) | Terminal layout and rendering bounds | 46 | 40 | 3 | 3 |
| [catalog.md](catalog.md) | Bench catalog data | 40 | 34 | 4 | 2 |
| [performance.md](performance.md) | Performance (100 ms budget, first paint, redraw) | 21 | 19 | 2 | 0 |
| [reliability.md](reliability.md) | Reliability, degraded metadata, recovery, idempotency | 36 | 27 | 4 | 5 |
| [security.md](security.md) | Security and safety | 30 | 23 | 4 | 3 |
| [contracts.md](contracts.md) | Setup-contract compatibility | 25 | 24 | 1 | 0 |
| [testing.md](testing.md) | Testing and acceptance | 25 | 22 | 3 | 0 |
| [release.md](release.md) | Documentation, release and rollback | 18 | 16 | 1 | 1 |
| [accessibility.md](accessibility.md) | Accessibility and terminal usability | 15 | 14 | 1 | 0 |
| [requirements.md](requirements.md) | Cross-cutting review (appended) | 22 | 19 | 1 | 2 |
| **Total** | | **361** | **297** | **41** | **23** |

- `requirements.md` also keeps its original spec-quality list (16/16, not counted above).
- "Passed as written" includes items satisfied by a fix recorded in another checklist (each such item says where).
- The 23 open items reduce to **15 decisions** (NB-1 to NB-15 below); several items point at the same decision.
- `openspec validate setup-guided-wizard --strict` passes after the edits.

### Domains skipped or folded in

- **API**: the feature has no network or library API; its machine contracts (selection file, worker files, catalog) are in `contracts.md` and `catalog.md`.
- **Observability**: setup has no telemetry; failure reporting (FR-058) is in `security.md` and `reliability.md`, and logging is unchanged from 1.7.
- **Configuration**: the only configuration is the bench catalog (`catalog.md`) and the terminal size (`layout.md`).
- **Idempotency** and **deployment/rollback** are sections of `reliability.md` and `release.md`.

## Gaps Closed by Wording

Each fix states behaviour that was already decided — by 1.7 under the approved "look only, same behaviour" scope, by the approved design, or by the clarify answers. Spec FRs and their OpenSpec deltas were changed together; the traceability table is unchanged (45/45).

| Where | Change | Checklist items |
|---|---|---|
| spec header | 44 → 45 OpenSpec requirements | requirements CHK002 |
| FR-003, delta › Step navigation | ↑/↓ stop at the first and last rows (1.7) | ux CHK004, CHK039 |
| FR-004, delta › Step navigation | focused row marked `›` on every step with rows (all mockups) | accessibility CHK005 |
| FR-006, delta › Top nav bar | Workstation as current step: highlight plus readiness mark (D5) | ux CHK013 |
| FR-009, delta › Review | items in step order; REMOVE notes projects and credentials are kept (D15) | ux CHK020, CHK021 |
| FR-013, delta › Apply from Review | yellow blocker line while Apply is blocked (D15) | ux CHK026 |
| FR-014, delta › Apply from Review | empty Enter uses the same gate; `--select-only` writes a selection file with no components (1.7) | ux CHK027, contracts CHK004 |
| FR-015, delta › Setup contracts | selection file still written privately, never through a symlink (1.7) | security CHK020 |
| FR-017, delta › Workstation step | a Loading row runs nothing; "checks are still loading" (1.7) | ux CHK031 |
| FR-019, delta › Profiles step | About from fixed text, sized and scrolled like Benches About (design Key Map, layout table) | ux CHK035 |
| FR-020 | failure notice "Profile action needs attention. Open it to retry." (1.7) | ux CHK036 |
| FR-022, delta › Footer | hints begin with `Navigation:` (1.7; suites wait on it) | ux CHK060 |
| FR-023, FR-024, deltas › jumps, Key Entities | P/G focus the first row (1.7); defaults read "first category that has benches" | ux CHK007, CHK064 |
| FR-028, delta › Readiness jump | already on Workstation: P target kept (1.7) | ux CHK049 |
| FR-031, delta › Requirements strip | `R/N ready`, Vault not counted (1.7) | layout CHK006 |
| FR-032, delta › Notices | notice lifetime as in 1.7 | ux CHK054 |
| FR-033, delta › Width bounds | frame = terminal width − 1, clamped to 36–87 (1.7, design) | layout CHK009 |
| FR-037, delta › Banner collapse | wordmark only in the roomy layout (D9) | layout CHK023 |
| FR-040, delta › Loading indicators | check ends without a state → needs check (1.7) | reliability CHK002 |
| FR-041, delta › Category block | order by `order`, then id (D6) | catalog CHK002 |
| FR-044, delta › Bench panel | catalog-name order = code-point order (D6, Q12) | catalog CHK034 |
| FR-048, FR-053, deltas | "control characters" = U+0000–U+001F and U+007F–U+009F | security CHK012 |
| FR-049, delta › Metadata delivery | the loading wait ends when checks finish without details (FR-050) | ux CHK068 |
| FR-051, delta › Focus survives | return targets kept by bench name; focus on first arrival (FR-004) | reliability CHK005, CHK016 |
| FR-053, delta › Presentation fields | "standalone number" = not joined to a letter (draft's `ARM64`, `MMseqs2`, `py3Dmol`, `m365`) | catalog CHK009 |
| FR-053, SC-013 | approval recorded with who, date and commit (`tasks.md` 7.2) | catalog CHK013 |
| FR-058, delta › Fail closed | path rule of `setup_selection.py` (bench root prefix, no `..`); reported like any failed component | security CHK007, CHK009 |
| FR-060, SC-006, delta › Key response time | "median time … at most 100 ms" replaces "each key press … measured as the median" | performance CHK002 |
| Key Entities › Queued change | Shell setup and Org workspace queue an install action and list under INSTALL (1.7) | ux CHK066 |
| Assumptions › Unchanged | status polling cadence; Ctrl+C 130 and termination 143 (1.7) | performance CHK016, reliability CHK026 |
| Assumptions › Users and terminals, `tasks.md` 5.3 | glyph check by hand in release QA, recorded with real-host results | testing CHK022 |
| SC-012, `tasks.md` 5.3 | fresh-workstation walkthrough recorded with real-host results | testing CHK003 |
| US1-20 (new scenario) | Profiles identities line, rows and About panel | testing CHK001 |
| `tasks.md` 6.2 | changelog and notes call out Enter → Review and the three new benches | release CHK010 |

## Needs Brett

Each item below needs a product decision; nothing was assumed. Reply on one line, e.g. `NB-1: A, NB-2: A, …`, or `all recommended`. Answers will be folded into `spec.md`, the matching OpenSpec delta and the checklists, and `openspec validate --strict` re-run.

### NB-1. Context line where nothing is focused or a row has no state

**Items**: ux CHK057 · **Affects**: FR-021; delta › Footer context and hints

FR-021 defines `<Name> · <State>`. Review has no focused row, Profiles rows have no state, and Benches has no focused item while it shows `Loading benches…`.

- **A** — As the illustrative mockups: Review shows `Review · Nothing applied yet`; Profiles shows the row name alone (`Personal & companies`); Benches shows `Loading benches…`; `Changes selected: N` stays at the right everywhere.
- **B** — Leave the left part empty in those cases; keep only the total.
- **C** — Show the step name alone (`Review`, `Profiles`, `Benches`).

**Recommended: A** — it is what `design.md` already shows and keeps the `<Name> · <State>` pattern wherever a state exists.

### NB-2. What "the category summary" on the context line means

**Items**: ux CHK058 · **Affects**: FR-021; delta › Footer context and hints

FR-021 shows "the category summary" when the category zone has focus; FR-045 and FR-052 use "summary" for the catalog's one-line text.

- **A** — The category name and its counts, as in the category block: `Science · 2 benches · 1 installed`.
- **B** — The catalog's one-line `summary`, cut with `…`.
- **C** — The category name alone.

**Recommended: A** — About already shows the catalog summary; the counts fit the `<Name> · <State>` pattern and narrow frames.

### NB-3. Queued counts in the compact nav

**Items**: ux CHK016 · **Affects**: FR-007; delta › Top nav bar

- **A** — No counts: `Step 2 of 6 · Benches` and six marks; the footer keeps the total.
- **B** — The current step's count only: `Step 2 of 6 · Benches 2`.
- **C** — Each step's count beside its mark.

**Recommended: A** — the compact form exists for tight frames, and the footer already carries the total.

### NB-4. Hint lines between 60 and 79 columns

**Items**: ux CHK062 · **Affects**: FR-022; delta › Footer context and hints; FR-047 height budget

Design D16 fixes two hint lines at 80+ columns and FR-022 caps them at two below 60. Between 60 and 79 the full Benches list needs about four lines.

- **A** — Wrap the full per-step list over as many lines as it needs; SC-002 still guarantees the nav, focused row and whole footer at 24 rows (Benches at 60×24 needs about 20 rows with four hint lines).
- **B** — Cap at two lines at every width, dropping the 60+ extras (P, G, R, V, PgUp/PgDn) that do not fit.
- **C** — Cap at three lines between 60 and 79 columns.

**Recommended: A** — Q7 lists those keys "only at 60+ columns", so they are listed in full there, and the budget fits.

### NB-5. A bench that leaves the catalog on refresh

**Items**: ux CHK045, ux CHK079, reliability CHK017, requirements CHK012, CHK017 · **Affects**: FR-046, FR-051, SC-008, Edge Cases; delta › Focus survives catalog updates

The edge case records an *assumed* fallback and keeps queued changes "for benches still catalogued", while SC-008 promises refreshes keep 100% of queued changes. Also open: whether About keeps its scroll offset when the same bench's text is refreshed.

- **A** — Confirm the assumption and write it into FR-051 and the delta: focus and any return target that named the bench fall back to the category zone on the same category (or the first category with benches); a queued change for a bench no longer catalogued is dropped, and SC-008 says "queued changes for benches still catalogued"; About keeps its offset, clamped, on a same-bench refresh.
- **B** — As A, but keep the vanished bench's queued change and list it on Review as unavailable (it would then fail closed at Apply, FR-058).
- **C** — As A, plus a notice naming any dropped change.

**Recommended: A** — Review shows exactly what will apply before Enter, so a dropped change is visible; B queues work that can only fail.

### NB-6. Characters allowed in bench copy

**Items**: layout CHK014, catalog CHK012, security CHK016 · **Affects**: FR-053; delta › Bench presentation fields

The catalog test rejects control characters only. Wide, combining, zero-width or bidi characters would break character-counted alignment (FR-033) or display misleadingly. The current draft is plain ASCII.

- **A** — The catalog test also rejects characters that are not single-column printable characters in `tagline`, `description`, `usedFor`, `contains`, and category `label` and `summary`.
- **B** — Printable ASCII only in those fields.
- **C** — No new rule.

**Recommended: A** — it matches the TUI's single-column assumption without banning accented letters.

### NB-7. Sanitising all outside text, not only catalog text

**Items**: security CHK015 · **Affects**: FR-048, SC-011; delta › Metadata delivery without discovery

- **A** — Apply FR-048's control-character rule to every text the TUI shows but did not write: worker status details, the identities summary from `setup-profiles.py --summary`, and helper results.
- **B** — Keep the rule to bench and category details, as written; other text keeps 1.7's handling.

**Recommended: A** — one rule at no extra cost, and SC-011's guarantee then covers the whole screen.

### NB-8. Digit-leading proof for the Python consumers

**Items**: security CHK005, requirements CHK017 · **Affects**: FR-057, SC-004, Assumptions › No data migration

Only `setup_selection.py` is exercised (US5-4); `setup-components.py`, `release-workbenches.py` and `remove-bench-checkout.py` rest on the assumption that they index by name.

- **A** — Extend the digit-leading fixture test to the four Python consumers; SC-004 becomes "8 of 8 consumers".
- **B** — Accept the assumption, citing US5-4 and the real-host TUI install of 365Bench (SC-010), and say so in Assumptions.

**Recommended: A** — a small fixture test removes the last unproven consumer, and 365Bench is what makes the hazard live.

### NB-9. Catalog maintenance scripts and the lock-only catalog

**Items**: catalog CHK026 · **Affects**: FR-054, FR-059; delta › Maintenance scripts preserve metadata

`update-bench-config.sh` discovers every directory with a `.git` directory, so it would pull local clones such as phpBench and opsBench into the catalog; `new-bench.sh` adds an entry with only a derived category. Either way the catalog test then fails (FR-053, FR-054).

- **A** — `update-bench-config.sh` skips, with a warning, benches the release lock does not record; `new-bench.sh` keeps adding entries, and the docs say a new bench needs a lock entry and copy before the catalog test passes.
- **B** — No script change; the catalog test is the gate, and only the docs explain the workflow.
- **C** — Both scripts refuse benches the lock does not record.

**Recommended: A** — regeneration can no longer bring local clones back in (Q10), and creating a new bench still works.

### NB-10. Degraded details

**Items**: reliability CHK008, CHK009, CHK011 · **Affects**: FR-050; delta › Degraded metadata

Open points: (a) the label "derived from" an unknown category id, and the order of several unknown categories; (b) where an uncategorised bench goes when its path is outside the three bench roots; (c) categories published without per-bench details, or a bench missing only some fields; (d) About for the `Other benches` group.

- **A** — (a) Title-case the id's hyphen-separated words (`quantum-computing` → `Quantum Computing`), unknown categories ordered by id; (b) `Other benches`; (c) place benches by path into the published categories, show the fields that exist, and show `No details for this bench yet.` when description, uses and contents are all missing; (d) About lists the group's bench names.
- **B** — As A, but (b) hides such a bench, since FR-058 would fail it at Apply anyway.
- **C** — Leave all four to the plan; tests assert only that every bench stays listed and selectable (SC-011).

**Recommended: A** — every catalogued bench stays visible and selectable, and each case gets a testable outcome.

### NB-11. What counts as "installed"

**Items**: layout CHK038 · **Affects**: FR-041, FR-044; deltas › Category block, Bench panel

`I of N installed` and the category counts are new in the wizard.

- **A** — A bench counts as installed when Space would queue an update rather than an install (1.7 treats `installed`, `needs creds` and `image only` that way).
- **B** — Only benches whose status is `installed`.

**Recommended: A** — the counts then agree with the `→ Update` or `→ Install` the user sees on Space.

### NB-12. Spare rows on Benches: bench list or About first

**Items**: layout CHK029 · **Affects**: FR-047; delta › Height-aware Benches layout

FR-047 sets minimums (at least three bench rows, two to eight About lines). At 80×24 about eleven rows remain to share once the head, collapsed category line, panel borders and footer are drawn.

- **A** — Bench rows first, up to every bench of the current category, then About up to eight lines (design D8: About gets "spare rows"). At 80×24: all eight Software Engineering benches and a three-line About.
- **B** — About first, up to eight lines, then bench rows. At 80×24: three bench rows and an eight-line About.
- **C** — Split the spare rows evenly.

**Recommended: A** — the list is what the user acts on, and About scrolls.

### NB-13. Benches when no bench list ever arrives

**Items**: reliability CHK006 · **Affects**: FR-049; delta › Metadata delivery without discovery

If checks finish, or cannot start, without publishing a bench list, FR-049 would show `Loading benches…` forever.

- **A** — Replace it with a line saying the bench list could not be loaded and R retries; nothing can be queued there.
- **B** — Keep `Loading benches…` until R.

**Recommended: A** — 1.7 already says "Could not start readiness checks. R retries." for the start failure.

### NB-14. Review's scroll position when it opens

**Items**: ux CHK008 · **Affects**: FR-004, FR-012

- **A** — Review opens at its first item when reached by Enter or ←/→; a P or G return restores the remembered position like any other focus.
- **B** — Review always opens at its first item, including after P or G returns.

**Recommended: A** — consistent with FR-023 and FR-024's exact-focus restore.

### NB-15. Recording approval of the OpenSpec change

**Items**: release CHK005 · **Affects**: OpenSpec `tasks.md` 1.1

`tasks.md` 1.1 ("Brett reviews this change … record approval") is still unticked, although the change is described as approved.

- **A** — Brett confirms; tick 1.1 with who and date before `/speckit-plan`.
- **B** — Hold 1.1 until the plan review.

**Recommended: A** — the plan should start from a recorded approval.
