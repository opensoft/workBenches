# Clarification Questions: Guided setup wizard

**Feature**: [spec.md](spec.md) · **OpenSpec change**: [`openspec/changes/setup-guided-wizard/`](../../openspec/changes/setup-guided-wizard/)
**Round**: 1 of `/speckit-clarify` — 20 questions (cap 25), ordered by impact — **complete**
**Prepared**: 2026-10-21 · **Status**: all 20 answered by Brett Heap on 2026-10-21 and encoded in `spec.md` (`## Clarifications` › Session 2026-10-21), the OpenSpec deltas, `design.md` (open questions closed) and `tasks.md`

## How to answer

- Reply on one line: `Q1: B, Q2: A, Q3: A, …`. **Any question you skip takes its Recommended option.**
- To answer differently, write `Q9: other — <a few words>`. For Q5 option B, put the edits after the letter (`Q5: B — 365Bench: drop mailbox migration`).
- `all recommended` accepts every recommendation. The recommendations as one line, ready to edit:
  `Q1: B, Q2: A, Q3: A, Q4: A, Q5: C, Q6: A, Q7: B, Q8: A, Q9: B, Q10: A, Q11: A, Q12: A, Q13: A, Q14: B, Q15: A, Q16: A, Q17: A, Q18: A, Q19: A, Q20: A`

## How answers will be encoded

1. Each answer is recorded inline in this file, under its question, as `**Answer:** <letter> — <text> (Brett Heap, <date>)`.
2. `spec.md` gains a `## Clarifications` section (after the header block, before User Scenarios) with `### Session <answer date>` and one bullet per answer, `- Q: <question> → A: <answer>`. The FRs, stories, edge cases and success criteria each answer touches are edited in place, and the three `[NEEDS CLARIFICATION]` markers (FR-007 → Q1, FR-053 → Q5, FR-033 → Q6) are replaced.
3. When an answer changes or adds a requirement, the OpenSpec delta named on its **OpenSpec** line is updated in the same pull request (with `design.md`'s decision and open-question list), `openspec validate setup-guided-wizard --strict` is re-run, and the traceability table in `spec.md` is updated. An answer that confirms the design only closes the matching open question in `design.md`.
4. `checklists/requirements.md` is re-validated.

Each question gives its **Source** (design open question, a decision the OpenSpec author made without you, an item you asked about, or the spec ambiguity scan), what it **Affects** in `spec.md`, and the **OpenSpec** requirement an answer could change.

---

### Q1. How should the six-step nav fit standard terminal widths?

**Source**: design open question 7; author decision D5 · **Affects**: FR-007 (marker) · **OpenSpec**: setup-wizard-flow › Top nav bar

**Why it matters**: With full labels the nav needs 80 columns with nothing queued and 86 with three counts, so on a standard 80-column terminal (79-column frame) users always see the compact `Step 2 of 6 · Benches` form, never the step names.

- **A** — As designed: full labels with short ` ─ ` connectors; the full nav appears only on terminals of 87+ columns with single-digit counts, the compact form everywhere else, including 80 columns.
- **B** — Show `AI` instead of `AI assistants` in the nav only, with ` ─ `: the full nav fits an 80-column terminal (75 columns with three counts); the step keeps its full name on Review, in hints and in docs.
- **C** — `AI` in the nav with the approved ` ── ` connectors: always fits at 87 (80 columns with three counts), but at 80 columns only while nothing is queued.

**Recommended: B** — the most common terminal width gets the full nav for the cost of one shortened label.

**Answer:** other — "use Agents instead of ai or ai assistants". The step is named Agents wherever a step is named (nav, Review step names, footer, hints, specs and docs). The nav uses short ` ─ ` connectors and is 79 columns with three single-digit counts (77 without the current step's highlight padding), so it fits an 80-column terminal; the compact `Step N of 6 · <Name>` form remains only for frames too narrow for the full nav. This replaces option B's "AI". (Brett Heap, 2026-10-21)

### Q2. Which step should setup open on?

**Source**: author decision D2 · **Affects**: FR-002; every acceptance suite's opening keystrokes · **OpenSpec**: setup-wizard-flow › Guided wizard steps

**Why it matters**: The first screen decides what a returning user presses to reach their usual work and how every keystroke-driven suite starts.

- **A** — Workstation (as designed): readiness and the requirements strip are visible while checks load; Benches is one → away, AI assistants two.
- **B** — Benches (as 1.7 opens): one key fewer for the common case; readiness shows only as the nav mark until checks end unresolved.
- **C** — Workstation, then move to Benches automatically once checks finish ready if the user has not pressed a key (adds an auto-advance rule).

**Recommended: A** — it follows the wizard order and keeps readiness visible at startup.

**Answer:** A — open on Workstation (as designed). (Brett Heap, 2026-10-21)

### Q3. What should Enter do on the Workstation step?

**Source**: author decision D3 (and its risk note) · **Affects**: FR-008, FR-017 · **OpenSpec**: setup-wizard-flow › Enter opens Review

**Why it matters**: In 1.7 Enter on the first screen applied; the wizard's first screen is Workstation, so a habitual Enter now runs the focused service action (Check when everything is Up).

- **A** — Run the focused service action, like Space (as designed; same as 1.7's Requirements page; the worst case is a harmless re-check).
- **B** — Open Review, like every component step; only Space runs a service action.
- **C** — Move to the next step (wizard "Next"); Space runs the action.

**Recommended: A** — keeps 1.7's Requirements behaviour, and a habitual Enter only re-checks.

**Answer:** A — Enter runs the focused service action, like Space (as designed). (Brett Heap, 2026-10-21)

### Q4. How should Review behave when it does not fit, and can it edit the queue?

**Source**: author decision D15; spec scan · **Affects**: FR-012 · **OpenSpec**: setup-wizard-flow › Review lists every queued change

**Why it matters**: Review is the only place the user sees every change before applying, and the prototype could hide items on short terminals.

- **A** — Read-only; ↑/↓ scroll with `▲/▼ N more` when the list does not fit (as designed).
- **B** — As A, plus a focus row: Space or D on a focused item unqueues it.
- **C** — No scrolling; show `N more` and leave the rest unseen until the terminal is enlarged (prototype behaviour).

**Recommended: A** — every item can be read, and editing stays on the steps that own the items.

**Answer:** A — Review is read-only; ↑/↓ scroll with `▲/▼ N more` when it does not fit (as designed). (Brett Heap, 2026-10-21)

### Q5. Do you approve the drafted copy for all 12 benches?

**Source**: design open question 5; OpenSpec task 1.1 · **Affects**: FR-053 (marker), FR-055, User Story 2 · **OpenSpec**: bench-catalog › Bench presentation fields; Accurate bench descriptions

**Why it matters**: Every user reads this text in the bench rows and the About panel, and the catalog test enforces it once it is encoded.

**File**: [`bench-copy-draft.json`](bench-copy-draft.json) — a snapshot of the evidence-based draft; each bench lists the files its claims come from. Working copy: `C:\Users\Brett\AppData\Local\Temp\claude\--wsl-localhost-Ubuntu-24-04-home-brett-projects-workBenches\d57c6441-6979-4788-a698-b3f7086bccba\scratchpad\bench-content.json`.

**Notable points**:
- **simBench corrected**: "Molecular simulation workbench with ESMFold and AlphaFold" becomes "Molecular simulation and protein structure workbench with OpenMM and ESM". No AlphaFold or ESMFold models or weights are claimed; the image has OpenMM, MDTraj, PDBFixer, MMseqs2, Foldseek, HMMER and fair-esm on CPU-only PyTorch.
- **New entries**: goBench ("Go development environment with cloud-native tools"), rustBench ("Rust, Tauri and WebAssembly development environment and tools") and 365Bench ("Microsoft 365, Dynamics 365 and Power Platform administration tools"), each with URL, path and AI keywords.
- **Unchanged**: the other eight descriptions. All 12 benches gain a tagline (≤ 35 characters), four `Use it for` items and seven or eight `Contains` items. The four category summaries are new; Electrical Engineering's says "no benches are available yet".
- **Worth a second look**: 365Bench's "Cross-tenant mailbox migration" comes from a bundled Codex skill, not an installed tool; pyBench's AMD ROCm item is optional and WSL-only; several items name versions (Q14).

- **A** — Approve all 12 as drafted.
- **B** — Approve with the edits you list after the letter.
- **C** — Build with the draft now, then approve or edit it in the running TUI before merge (approval becomes a merge gate recorded in this feature).

**Recommended: C** — you judge the copy where users will see it, planning is not blocked, and nothing merges unapproved.

**Answer:** C — build with the draft; Brett approves or edits the copy in the running TUI before merge, and that approval is a recorded merge gate (OpenSpec tasks.md 7.2). (Brett Heap, 2026-10-21)

### Q6. What is the minimum supported terminal size?

**Source**: your request; spec scan · **Affects**: FR-033 (marker), FR-036, SC-002 · **OpenSpec**: setup-wizard-layout › Width bounds; Height bounds

**Why it matters**: It sets the floor of the render-matrix tests and what users see below it; the spec guarantees 36×24 but says nothing about narrower terminals.

- **A** — 36×24 (as designed); below it best effort: lines drop from the top, and below 36 columns lines may wrap.
- **B** — 36×24; below it the frame becomes one line, "Enlarge the terminal to at least 36×24", and keys still work (Q quits).
- **C** — 60×24; drop the 36-column layouts (simpler panels and hints; narrow side panes unsupported).
- **D** — 80×24; only standard terminal sizes are supported.

**Recommended: A** — keeps today's 36-column clamp and side-pane use, and setup stays operable when cramped.

**Answer:** A — 36×24; below it best effort (lines drop from the top; below 36 columns lines may wrap). (Brett Heap, 2026-10-21)

### Q7. How should footer hints fit at narrow widths?

**Source**: your request · **Affects**: FR-022, FR-047 · **OpenSpec**: setup-wizard-flow › Footer context and hints (design D16)

**Why it matters**: At 36×24 the prototype's Benches hints take 6 of 24 rows, leaving About 2 lines — javaBench's About reads `1–2 of 43` and each PgDn moves one line.

- **A** — Keep every hint, wrapped (prototype): About stays at 2 lines at 36×24.
- **B** — Below 60 columns cap hints at two lines: the step's own keys plus ←→, Enter and Q. P, G, R, V and PgUp/PgDn still work but are listed only at 60+ columns (About's border already shows `PgUp/PgDn scroll`); About gains about four lines.
- **C** — Below 60 columns show one hint line ending in `? Keys`, a new key that shows the full list.
- **D** — Below 60 columns hide the About panel and keep every hint.

**Recommended: B** — roughly triples About's room at 36 columns without adding a key; the keys it stops listing work on every step.

**Answer:** B — below 60 columns at most two hint lines: the step's own keys plus ←→, Enter and Q; P, G, R, V and PgUp/PgDn keep working but are listed only at 60+ columns. (Brett Heap, 2026-10-21)

### Q8. Where should focus land when arriving on Benches with ← or →?

**Source**: author decision D6 · **Affects**: FR-004 · **OpenSpec**: setup-wizard-flow › Step navigation

**Why it matters**: It decides whether coming back to Benches restores the user's place, and which keys the suites send (`→ Tab` to reach a bench).

- **A** — The category zone on the first category that has benches, every time (as designed; matches 1.7, where ←/→ reset every section to its first row).
- **B** — The bench zone on the first bench of the first category (Space queues at once; categories need ↑ or Tab).
- **C** — The category zone on the category last viewed (the first visit behaves as A).

**Recommended: A** — consistent with every other step; P and G already restore exact focus.

**Answer:** A — the category zone on the first category that has benches, every time (as designed). (Brett Heap, 2026-10-21)

### Q9. Should the Workstation step show the workBenches account and AI accounts?

**Source**: your request · **Affects**: FR-016 · **OpenSpec**: setup-wizard-flow › Workstation step

**Why it matters**: The prototype, built before Profiles existed, shows both rows on Workstation; 1.7's Requirements page shows Vault alone, with a `G Profiles` label, because the accounts moved to Profiles.

- **A** — No: services only (WSL 2, Docker, Tools, Vault) and no pointer (as designed).
- **B** — No account rows, but keep 1.7's `G Profiles` label on the OPTIONAL VAULT panel as a pointer (a one-line delta addition).
- **C** — Yes: show both rows read-only on Workstation as well, with Enter opening Profiles (duplicates the Profiles step).

**Recommended: B** — no duplication and no extra rows, and the only place G is advertised outside Profiles survives.

**Answer:** B — no account rows; keep 1.7's `G Profiles` label on the OPTIONAL VAULT panel as the pointer. (Brett Heap, 2026-10-21)

### Q10. Should phpBench and opsBench be catalogued?

**Source**: design open question 1 · **Affects**: FR-054, SC-003 · **OpenSpec**: bench-catalog › Complete catalog

**Why it matters**: They are local, gitignored clones outside the release lock, so setup cannot fetch them from a pinned source.

- **A** — No: the catalog matches the release lock exactly (as designed).
- **B** — Yes, after they get their own repositories and lock entries (separate work outside this feature).
- **C** — List them only when a local clone exists, marked local and not installable from setup.

**Recommended: A** — keeps "offered means locked" true; revisit when they join the lock.

**Answer:** A — not catalogued; the catalog matches the release lock exactly. (Brett Heap, 2026-10-21)

### Q11. Should AI assistants and Tools get categories or an About panel now?

**Source**: design open question 3 · **Affects**: FR-018; Assumptions › Out of scope · **OpenSpec**: setup-wizard-flow › AI assistants and Tools steps (proposal Non-Goals)

**Why it matters**: It trades consistency with Benches against scope; those steps hold 8 and 7 items and fit one panel.

- **A** — Not now (as designed): single-column panels, as in 1.7.
- **B** — An About panel only (fixed text per item), no categories.
- **C** — Both categories and an About panel.

**Recommended: A** — the lists are short; an About panel can follow if users ask what an item is.

**Answer:** A — not now. (Brett Heap, 2026-10-21)

### Q12. In what order should benches appear within a category?

**Source**: design open question 8; author decision D6 · **Affects**: FR-044 · **OpenSpec**: setup-bench-browser › Bench panel

**Why it matters**: The approved mockup showed a curated order (pyBench, javaBench, goBench, rustBench, …), but the design chose name order.

- **A** — Catalog-name order (as designed): cppBench, dotNetBench, flutterBench, frappeBench, goBench, javaBench, pyBench, rustBench; 365Bench before cloudBench; no new field.
- **B** — A curated order from a new optional per-bench `order` field (schema, test and maintenance-script work).
- **C** — Installed benches first, then the rest, each group by name (order shifts as benches are installed).

**Recommended: A** — predictable, no schema change, and how 1.7 lists benches.

**Answer:** A — catalog-name order (as designed). (Brett Heap, 2026-10-21)

### Q13. Should categories without benches be shown as "coming soon"?

**Source**: your request · **Affects**: FR-041, FR-052 · **OpenSpec**: setup-bench-browser › Category block

**Why it matters**: Electrical Engineering has no benches; listing it signals the roadmap you described, but it spends a row and cannot be selected.

- **A** — Show it dim with `coming soon`, never focusable (as designed).
- **B** — Hide categories with no benches (the catalog still defines Electrical Engineering for later).
- **C** — Hide them in the block and mention them in the category About text ("Coming: Electrical Engineering").

**Recommended: A** — matches how you described the categories, and costs nothing in the tight layout, where the block is one line.

**Answer:** A — show dim with `coming soon`, never focusable (as designed). (Brett Heap, 2026-10-21)

### Q14. Should the bench copy name tool versions?

**Source**: spec scan (copy accuracy) · **Affects**: FR-053, FR-055 · **OpenSpec**: bench-catalog › Accurate bench descriptions

**Why it matters**: The draft names versions (Go 1.26, OpenJDK 25, GCC 14 and Clang 19, .NET 10, Python 3.12 and 3.11, Flutter 3.27 LTS, MariaDB 10.6, Frappe version-15) that go stale when images are bumped, and no test can catch that.

- **A** — Keep the versions: most precise today, but the copy needs review on every image bump.
- **B** — Remove version numbers from taglines, uses and contents.
- **C** — Keep only versions that identify the product line a bench targets (Frappe version-15, .NET 10, OpenJDK 25); drop the rest.

**Recommended: B** — the copy stays true across image bumps; bench READMEs and images remain the source for versions.

**Answer:** B — no version numbers in taglines, `usedFor` or `contains`; the catalog test rejects version-like tokens (allow-list: Microsoft 365, Dynamics 365). `bench-copy-draft.json` has been de-versioned; the scratch copy is unchanged. (Brett Heap, 2026-10-21)

### Q15. What key-response budget should the tests enforce?

**Source**: spec scan (performance) · **Affects**: SC-006 · **OpenSpec**: none (design Risks: "measure frame time at 87×40")

**Why it matters**: Height budgeting and About wrapping now run on every frame, and the design asks for a frame-time test without giving a number.

- **A** — 100 ms per key press (median of repeated renders at 87×40 on a developer workstation).
- **B** — 200 ms per key press.
- **C** — No absolute number: no more than 20% slower than 1.7's main screen measured the same way.

**Recommended: A** — 100 ms is the usual threshold for a response that feels immediate.

**Answer:** A — 100 ms per key press (median of repeated renders at 87×40 on a developer workstation). (Brett Heap, 2026-10-21)

### Q16. When should the readiness jump fire?

**Source**: spec scan · **Affects**: FR-028; Edge Cases · **OpenSpec**: setup-wizard-flow › Readiness jump

**Why it matters**: 1.7 jumps to Workstation whenever any check run ends unresolved, including runs started by R, which can pull a user off Review.

- **A** — After every completed check run, as 1.7 does (as designed).
- **B** — Only after the startup check run; later runs update the nav mark and Review's blocker line without moving the user.

**Recommended: A** — keeps 1.7 behaviour and its tests, and after a refresh the jump lands on the item that still needs attention.

**Answer:** A — after every completed check run, including runs started by R, as in 1.7. (Brett Heap, 2026-10-21)

### Q17. Science sub-groups (biology, chemistry, physics): now or later?

**Source**: design open question 2 · **Affects**: FR-041, FR-052; Assumptions › Out of scope · **OpenSpec**: bench-catalog › Bench categories (proposal Non-Goals)

**Why it matters**: Sub-groups add a nesting level to the category zone for two benches that are both biology.

- **A** — Later, when chemistry or physics benches exist (as designed); Science stays flat.
- **B** — Now: Biology, Chemistry and Physics under Science, the last two "coming soon".

**Recommended: A** — there are no benches to fill them yet.

**Answer:** A — later, when chemistry or physics benches exist. (Brett Heap, 2026-10-21)

### Q18. Should the Workstation explanation move into an About panel?

**Source**: design open question 4 · **Affects**: FR-016 · **OpenSpec**: setup-wizard-flow › Workstation step

**Why it matters**: Benches and Profiles explain the focused row in an About panel, while Workstation shows a one-line explanation under the focused row, as 1.7 does.

- **A** — Keep the explanation under the focused row (as designed).
- **B** — Move it into an About panel: consistent across steps, but at least three more rows, which matters at 24 rows.

**Recommended: A** — the explanations are one line, and the strip already fills the selector area.

**Answer:** A — keep the explanation under the focused row (as designed). (Brett Heap, 2026-10-21)

### Q19. Should the Profiles step ever show a count in the nav?

**Source**: design open question 6 · **Affects**: FR-005 · **OpenSpec**: setup-wizard-flow › Top nav bar

**Why it matters**: Profiles rows run their actions immediately, so nothing on Profiles is ever queued and its nav item never shows a number.

- **A** — No count, ever (as designed).
- **B** — A yellow `!` while no personal identity exists (needs a cached status; the summary is not parsed today).
- **C** — The number of Profiles actions completed this session.

**Recommended: A** — nav counts mean "queued", and nothing on Profiles is queued.

**Answer:** A — no count, ever (as designed). (Brett Heap, 2026-10-21)

### Q20. Below 60 columns, how should the footer show the queued total?

**Source**: spec scan · **Affects**: FR-021 · **OpenSpec**: setup-wizard-flow › Footer context and hints

**Why it matters**: The spec defines `Changes selected: N` only at 60+ columns; the prototype shows `Changes: N` and cuts the context line without a mark ("Ready → updat").

- **A** — `Changes: N` at the right, with the context line cut with `…`.
- **B** — Omit the total; the nav counts remain.

**Recommended: A** — the total stays visible and the cut is marked.

**Answer:** A — `Changes: N` at the right, with the context line cut with `…`. (Brett Heap, 2026-10-21)

---

## Scan coverage

| Taxonomy area | Status before answers | Questions |
|---|---|---|
| Functional scope and out-of-scope | Partial | Q10, Q11, Q17 |
| Domain and data model (catalog) | Partial | Q5, Q12, Q14 |
| Interaction and UX flow | Partial | Q2, Q3, Q4, Q8, Q9, Q13, Q16, Q18, Q19 |
| Layout, narrow and short terminals | Partial | Q1, Q6, Q7, Q20 |
| Non-functional (performance) | Missing a number | Q15 |
| Edge cases and failure handling | Clear | — (fallback when a focused bench leaves the catalog is an assumption in spec.md › Edge Cases) |
| Security and safety (lookups, hostile catalog text) | Clear | — |
| Integration and contracts (setup modes, selection file) | Clear | — |
| Terminology | Clear | — |
| Completion signals | Clear | — |

After the answers every Partial or Missing area above is Resolved.

Round complete: all 20 questions answered by Brett Heap and encoded on 2026-10-21.
