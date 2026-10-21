# Implementation Plan: Guided setup wizard

**Branch**: `029-setup-guided-wizard` | **Date**: 2026-10-21 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/029-setup-guided-wizard/spec.md`, the approved OpenSpec change [`openspec/changes/setup-guided-wizard/`](../../openspec/changes/setup-guided-wizard/) (design D1–D19), Brett's 35 clarification answers, the release-gate checklists (361/361) and `bench-copy-draft.json`.

**Artifacts**: [research.md](research.md) · [data-model.md](data-model.md) · [contracts/](contracts/) ([bench-config.schema.json](contracts/bench-config.schema.json), [worker-metadata-files.md](contracts/worker-metadata-files.md), [key-map.md](contracts/key-map.md), [setup-contracts-unchanged.md](contracts/setup-contracts-unchanged.md)) · [quickstart.md](quickstart.md)

## Summary

Replace the 1.7 setup TUI's three-column main screen and its separate Requirements and Profiles pages with a six-step wizard — Workstation → Benches → Agents → Tools → Profiles → Review — in `scripts/interactive-setup.sh`, where Enter opens Review and only Enter on Review applies; browse benches by category with a scrolling About panel; fit 36–87+ columns and any known height; and make the bench catalog complete (goBench, rustBench, 365Bench) and safely read by every consumer.

The approach, from [research.md](research.md):

- **Safety first.** Every shell catalog lookup becomes `jq --arg n "$name" '.benches[$n]…'`, `process_selections` fails closed on an unresolved path, and a static check plus a digit-leading fixture test across 8 consumers land **before** 365Bench enters the catalog (R4).
- **A fork-free renderer.** Measured on Brett's workstation, one `$(…)` costs 3.5–6 ms inside the setup process; 1.7's main screen already takes ~250 ms per redraw and the prototype ~130 ms per key, while a fork-free Benches frame takes 3.8 ms. The frame is built into an array by helpers that return through variables, with cached static parts and a cached terminal size (R1, R5). Target ≤ 25 ms per key; requirement 100 ms.
- **Data, not discovery.** Category and bench details travel from the status worker as two validated, sanitised TSV files beside `catalog`, which gains a path field for the degraded path fallback (R3).
- **Same contracts.** Section numbers stay (Review is section 5), setup modes and the selection file are unchanged, and suites switch their "ready" wait from the Workstation-only strip to the nav's readiness mark (R2, R8).

## Technical Context

**Language/Version**: GNU Bash 5.x (TUI, status loader, catalog consumers; measured on 5.2.21); Python 3 (catalog consumers and suites, unchanged interpreters); `jq` 1.6+ (status worker and catalog consumers only, never the render path).

**Primary Dependencies**: `tput`/terminfo (terminal size, first paint and resize only); the status worker inside the managed Tools container (`scripts/setup-status-worker.sh`, `scripts/lib/setup-status-loader.sh`); `config/release-lock.json` as the source of truth for which benches exist; `config/credential-requirements.json`.

**Storage**: Files only — `config/bench-config.json` (catalog, additive fields), private status-directory files during a run (`catalog`, `bench-categories`, `bench-meta`, `*.row`), and the private selection file (unchanged).

**Testing**: Python `unittest` and Bash suites in `devcontainer.test/` driven by PTY keystrokes or by sourcing the script; the "Workstation Setup" GitHub workflow (`.github/workflows/credential-recovery.yml`: `regression`, `tools-runtime`, `component-lifecycle` jobs); real-host acceptance (native Docker-in-Docker profile and WSL) in release QA; `openspec validate --strict`.

**Target Platform**: Linux and WSL 2 workstations running `./setup.sh` in Windows Terminal, the VS Code terminal or Linux terminals with UTF-8; frames 36–87 columns, minimum supported terminal 36×24.

**Project Type**: CLI/TUI inside a single repository (no three-leg manifest; `<spec>` and `<code>` are the worktree root).

**Performance Goals**: median key → completed redraw ≤ 100 ms at 87×40 (FR-060, SC-006); engineering target ≤ 25 ms; zero forks on the render path; first frame before any Docker, catalog, Python, Git or network check (FR-038); unchanged frame writes nothing (FR-039).

**Constraints**: "look only, same behaviour" plus three deliberate changes (Enter → Review → Apply, category/About browsing, catalog additions); setup modes and selection file unchanged (FR-015); 1.7 section numbers kept (D1); no `jq`/`python3`/`docker`/`git` while rendering; outside text sanitised (FR-048); only single-column glyphs; one PR into `release/1.7.0` (fallback 1.8); bench copy approved by Brett in the running TUI before merge (merge gate).

**Scale/Scope**: 12 benches in 4 categories (3 with benches), 8 agent items, 7 tool items, 4 workstation rows, 3 Profiles rows; `interactive-setup.sh` is 3,384 lines on 1.7, and about 40 of its render and input functions change; 4 shell + 4 Python catalog consumers; 9 existing suites change and 5 more are re-verified; 5 new suites and 1 local timing harness.

No item is NEEDS CLARIFICATION: the spec has none, and every open technical choice is decided in [research.md](research.md) R1–R11.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

`.specify/memory/constitution.md` in this repository is the unfilled Spec Kit template: every principle, section and the version line are placeholders, and nothing has been ratified. There are no project principles to evaluate. The gate is therefore run against the rules that do govern this work — Brett's user-global OpenSpec/Speckit protocol (`openspec-speckit-workflow.md`) and the approved change — and is recorded here so `/speckit-analyze` can check it.

| # | Gate | Source | Pre-research | Post-design |
|---|---|---|---|---|
| G1 | Product behaviour changes go through an approved OpenSpec change handed to exactly one Speckit feature | protocol › When To Use OpenSpec, Lifecycle | PASS — `setup-guided-wizard` approved by Brett 2026-10-21 (tasks 1.1, NB-15); one feature, 029 | PASS |
| G2 | No unresolved clarification before planning | skill › Key rules ("ERROR on … unresolved clarifications") | PASS — 0 NEEDS CLARIFICATION; 35 answers encoded; 45/45 traceability; 361/361 checklist items | PASS — R1–R11 decide every open technical choice |
| G3 | Work happens in the feature worktree; planning writes only the feature directory | protocol › Worktree Rules; this run's brief | PASS — single repository, worktree on `029-setup-guided-wizard`, writes only `specs/029-setup-guided-wizard/` | PASS — no product file changed |
| G4 | Shipped contracts are not reinterpreted silently | protocol › Lifecycle (shipped-feature amendments) | PASS — FR-015 keeps setup modes and the selection file; [contracts/setup-contracts-unchanged.md](contracts/setup-contracts-unchanged.md) restates them | PASS — the only contract extension is the private worker `catalog` path field (internal, run-scoped; [contracts/worker-metadata-files.md](contracts/worker-metadata-files.md)) |
| G5 | Governed paths are identified before tasks are tiered | protocol › Build Tiers › Governed invariants | PASS — see [Governance notes](#governance-notes) | PASS — always-governed paths touched: the Workstation Setup workflow and `openspec/` task ticks; untouched: release lock, `.gitmodules`, gitlinks |
| G6 | Every requirement has a verifying test; existing suite outcomes are kept | spec SC-010; protocol › Build Tiers (`verify:` per task) | PASS — FR → test map below | PASS |
| G7 | Security-sensitive work is identified (tiered `[O]`) | protocol › The rubric | PASS — fail-closed lookups (FR-056–058) and outside-text sanitising (FR-048) are security-sensitive | PASS |

No gate fails, so Complexity Tracking is empty. Recommendation (not blocking): ratify a project constitution with `/speckit-constitution` so later features gate on project principles rather than on this substitute table.

## Project Structure

### Documentation (this feature)

```text
specs/029-setup-guided-wizard/
├── spec.md                    # feature spec (FR-001–FR-060, SC-001–SC-013)
├── clarify-questions.md       # clarification record
├── bench-copy-draft.json      # evidence-based bench copy (merge gate: Brett approves in the TUI)
├── checklists/                # release-gate checklists (361/361) and README (NB-1–NB-15)
├── plan.md                    # this file
├── research.md                # R1–R11 decisions, with measurements
├── data-model.md              # UI state, catalog schema, worker files, queued changes, validation
├── quickstart.md              # preview, suites, timing harness, real-host QA hand-off
├── contracts/
│   ├── bench-config.schema.json
│   ├── worker-metadata-files.md
│   ├── key-map.md
│   └── setup-contracts-unchanged.md
├── tasks.md                   # next: /speckit-tasks
└── release-qa.md              # later: timing, real-host results, glyph check, walkthrough, copy approval
```

### Source code touched (repository root)

```text
scripts/
├── interactive-setup.sh            # wizard: step map, frame builder, steps, keys, Review, jumps, Benches; safe lookups; fail-closed apply
├── lib/setup-status-loader.sh      # metadata publish/read, sanitiser, catalog path field, degraded rules, readiness jump targets
├── setup-workbenches.sh            # safe lookups (benches and infrastructure)
├── update-project.sh               # safe lookups
├── launchBench                     # safe lookup
├── update-bench-config.sh          # merge-preserving regeneration; skip benches the release lock does not record
└── new-bench.sh                    # preserve existing fields; derive category from path
config/
├── bench-config.json               # categories; category, tagline, usedFor, contains; goBench, rustBench, 365Bench; simBench text
└── credential-requirements.json    # goBench, rustBench, 365Bench as TUI options
devcontainer.test/
├── test-bench-catalog.py                 # new
├── test-bench-catalog-lookups.py         # new
├── test-bench-catalog-maintenance.sh     # new
├── test-setup-wizard.py                  # new
├── test-setup-wizard-layout.py           # new (render matrix; no-fork check)
├── test-setup-render-timing.py           # new, local only
├── test-workstation-acceptance.py        # keys, READY marker
├── test-wsl-workstation-acceptance.py    # keys
├── test-component-lifecycle.py           # keys, labels
├── test-tools-runtime.py                 # keys, labels
├── test-setup-async.py                   # Workstation section for strip renders; builder seam
├── test-setup-requirements.py            # strip format, notice wording if asserted
├── test-setup-profiles.py                # Profiles step shims
├── test-setup-guided-flow.py             # keys
└── test-setup-cancel.sh                  # piped keys
docs/
├── setup-script-ui.md              # rewritten for the wizard
├── setup-requirements.md           # strip location, keys, Enter → Review → Apply
├── profiles.md                     # Profiles as a wizard step
├── setup-credential-requirements.md
├── newBench.md                     # a new bench needs a lock entry and copy first
└── release-1.7.0.md                # scope note
CHANGELOG.md                        # breaking interaction change; three new benches
.github/workflows/credential-recovery.yml   # "Workstation Setup": run and trigger on the new suites (always governed)
openspec/changes/setup-guided-wizard/tasks.md  # tick tasks as they complete (always governed)
```

**Structure Decision**: Single repository, existing layout. All TUI logic stays in `scripts/interactive-setup.sh` and `scripts/lib/setup-status-loader.sh` (no new runtime module: a sourced library would add a file every suite fixture copies, for no gain); new tests follow the existing `devcontainer.test/test-*.{py,sh}` convention. Not touched: `config/release-lock.json`, `.gitmodules` and gitlinks, `scripts/setup_selection.py`, `scripts/setup-profiles.py` and the Profiles manager screens, `setup.sh`, the OpenTUI app (`scripts/setup-ui`), Docker/Tools/Vault service code.

## Phased approach

Phase 0 (research) and Phase 1 (design and contracts) are complete in this plan. Implementation runs in nine phases. Each phase's tasks are test-first: the task's `verify:` command runs the new or updated tests for its behaviour plus the existing suites it could break, so the branch stays green commit by commit. A task that changes an interaction updates the local suites that assert it **in the same task** (rule S1, below).

```text
P1 safe lookups ─► P2 catalog ─┬─► P3 metadata delivery ─────────────┐
                               └─► P4 frame engine ─► P5 flow & steps ─┴─► P6 Benches ─► P7 suites & CI ─► P9 verify & land
                                                                     P8 docs (after P5/P6; parallel with P7) ─┘
```

### Phase 1 — Safe catalog lookups (FR-056, FR-057, FR-058; SC-004)

Lands, as its own commits, **before** any catalog entry for 365Bench exists in `config/bench-config.json`.

- Write `devcontainer.test/test-bench-catalog-lookups.py` first: the static check (no shell lookup built from a variable, no `${` in a jq program), the digit-leading behaviour test against a **fixture** catalog with `365Bench` at `sysBenches/365Bench` across the four shell consumers (`check_component_status` + `process_selections`, `setup-workbenches.sh`, `update-project.sh`, `launchBench`) and the four Python consumers, and the fail-closed test (empty and out-of-tree paths; recording `git`, `docker`, `bash` stubs; no call in the root).
- Replace every site in research R4's table with `--arg` lookups; drop the `// "$bench"` defaults.
- Add `bench_checkout_path` and use it in `process_selections` (failure reported like any failed component) and in `check_component_status` (`needs check`).
- Exit: static check clean; 8/8 consumers resolve the fixture; zero git/clone/setup runs in the root; all existing local suites pass.
- Tier hint: `[O]` (security-sensitive, crosses five files).

### Phase 2 — Catalog content and maintenance (FR-052–FR-055, FR-059; SC-003; SC-013 rule)

- Write `devcontainer.test/test-bench-catalog.py` first: schema of [contracts/bench-config.schema.json](contracts/bench-config.schema.json), tagline ≤ 35, single-line non-empty fields, control characters, wide/fullwidth/combining/zero-width/bidi characters, version-like tokens with the allow-list and the accepted examples (`ARM64`, `MMseqs2`, `py3Dmol`, `m365`), whole-field `-`, lock coverage in both directions (path and URL), category rules, simBench wording, and failure messages naming the bench, category or token.
- Merge `bench-copy-draft.json` into `config/bench-config.json` as [data-model.md](data-model.md) §2 describes (versions removed; no `draft`/`evidence`), add the three benches from `newBenches`, correct simBench.
- In the same task or the next one: mark goBench, rustBench and 365Bench `"source": "tui"` with their notes cleared in `config/credential-requirements.json`, and update `docs/setup-credential-requirements.md`; `test-setup-credential-plan.py` must pass.
- Write `devcontainer.test/test-bench-catalog-maintenance.sh`, then make `scripts/update-bench-config.sh` build entries with `jq --arg` and merge them over the existing catalog (keeping `categories` and every existing per-bench field, deriving `category` from the path for new entries) and skip, with a warning, any discovered clone whose path the release lock does not record; make `scripts/new-bench.sh` keep existing fields and add a path-derived `category`; document in `docs/newBench.md` that a new bench needs a release-lock entry and its copy before the catalog test passes.
- Exit: catalog test, maintenance test, credential-plan test and the Phase 1 tests pass against the real catalog (12 benches).
- Tier hints: catalog merge `[O]` (contract and schema); credential requirements `[S]`; `update-bench-config.sh` `[O]` (lock-aware merge); `new-bench.sh` and docs `[S]`.

### Phase 3 — Metadata delivery (FR-048–FR-051 data side; SC-011)

- Tests first (in `test-setup-wizard.py`, metadata section): the worker writes `catalog` (`name ⇥ path`), `bench-categories`, `bench-meta` atomically in that order; the foreground reads them with builtins only (recording stubs for `jq`, `python3`); hostile text (`ESC [2J`, C1 CSI, tabs, `\036`) is neutralised in metadata, row details, the identities summary and helper results; invalid names and ids are ignored; every degraded case in [contracts/worker-metadata-files.md](contracts/worker-metadata-files.md) produces the specified arrays; a bench that leaves the catalog drops its queued change and falls back focus and return targets (NB-5); the synchronous path loads the same arrays; `--apply-plan`/`--dependencies-plan` never load them.
- Implement the row builder (worker), the readers and the locale-independent sanitiser (R3), the catalog path field, and the derived per-arrival structures (category of each bench, ordered categories, members, counts).
- Exit: metadata tests and `test-setup-async.py` pass.
- Tier hint: `[O]` (boundary and security-sensitive).

### Phase 4 — Frame engine (FR-033, FR-034, FR-036, FR-037, FR-038, FR-039, FR-060 enablers; SC-005, SC-006)

- Tests first: `devcontainer.test/test-setup-wizard-layout.py` skeleton (width and height bound helpers, the no-fork static check of render-path functions) and `devcontainer.test/test-setup-render-timing.py` (the harness of [quickstart.md](quickstart.md) §3).
- Build the engine of research R1, R5, R9 and R10: `setup_frame_lines` and region builders; `_v` helpers (`setup_ui_pair`, rule, status label, `workbenches_requirement_action_v`); static-part and wrap caches; the size cache with the `WINCH` trap and the `read`-interrupt rule; height-aware layout primitives (roomy/tight, edge-triggered scrolling with `▲/▼ N more`, drop-from-top); banner collapse; repaint on width or height change; locale check; the fork-free main-loop signature.
- The 1.7 bodies that Phase 5 replaces may be bridged through one capture per frame until then; the no-fork check covers engine functions now and every render-path function from Phase 5 on.
- Exit: existing render tests (`test-setup-async.py`, `test-setup-requirements.py`, `test-setup-profiles.py`) pass with the builder seam updated; no-fork check passes for the engine.
- Tier hint: `[O]` (new interface used by every later phase).

### Phase 5 — Wizard flow and steps (FR-001–FR-032 except Benches content, FR-040; SC-001, SC-007, SC-008, SC-009)

- Tests first in `test-setup-wizard.py` (flow) and `test-setup-wizard-layout.py` (frames), one group per behaviour.
- Step map and Review as section 5 (R2); opening on Workstation in `main()`; ←/→ without wrap and arrival rules; nav bar with readiness mark, counts, full/compact form by measured width (R6).
- Enter → Review → Apply: Review groups in step order with step names, REMOVE note, Shell setup/Org workspace warnings, empty state, blocker line, read-only scrolling with hidden counts, opening at the first item; unchanged gating, `--select-only` and empty-run behaviour (FR-014).
- P and G targets with exact focus (row, zone, category, bench by name, Review offset); readiness jump after every completed check run; V from every step with notices on the current step; R keeping focus and queued changes; Q exiting 130 from every step.
- Workstation (strip on Workstation only; REQUIRED SOFTWARE and OPTIONAL VAULT with `G Profiles`; detail under the focused row only), Agents and Tools (single-column panels, 1.7 items and rules), Profiles (identities line cut with `…`, three rows, About from `profile_about`, R7; refusal and result notices), per-step footers (context line, `Changes selected: N`/`Changes: N`, hint rules of [contracts/key-map.md](contracts/key-map.md)).
- Update in the same tasks the local suites these changes break (rule S1): `test-setup-cancel.sh`, `test-setup-guided-flow.py`, `test-setup-async.py`, `test-setup-requirements.py`, `test-setup-profiles.py` (see the impact table).
- Exit: flow and layout tests pass for every non-Benches step at the render matrix sizes; the local regression list passes; the timing harness's per-step medians are within target.
- Tier hints: step map, Review and Apply gate, jumps `[O]`; per-step bodies and footers `[S]` once the engine exists.

### Phase 6 — Benches step (FR-041–FR-047, FR-049–FR-051 UI; SC-002, SC-008, SC-011)

- Tests first: zones (FR-042, FR-043), category block and counts (FR-041, NB-11), bench panel columns by width (FR-044), About content and scrolling with range, markers, hint and reset/keep rules (FR-045, FR-046), height budget at 80×24, 37×24, 88×40, unknown height (FR-047, NB-12), loading/unavailable/degraded states (FR-049, FR-050), focus survival on refresh and on a vanished bench (FR-051), context line for the category zone.
- Implement the category block (one-line collapse), the two zones and their key handler, the bench panel with per-category edge-triggered offsets, the About panel with the wrap cache, and the Benches height budget (bench rows first, then About up to eight lines).
- Exit: Benches tests pass; the timing harness median at 87×40 meets the ≤ 25 ms target (and must pass the 100 ms gate).
- Tier hint: `[O]` (zones, budget and focus survival interact).

### Phase 7 — Acceptance suites and CI coverage (SC-010)

- Migrate the Docker-backed and real-host suites to the wizard's keys and the `READY`/`STRIP_READY`/`REVIEW` markers of research R8: `test-workstation-acceptance.py`, `test-wsl-workstation-acceptance.py`, `test-component-lifecycle.py`, `test-tools-runtime.py` (impact table). Every asserted outcome stays.
- Add the five new CI-safe suites to the Workstation Setup workflow's `regression` job and the new and newly relevant paths (`config/release-lock.json`, `scripts/update-bench-config.sh`, `scripts/new-bench.sh`, `scripts/update-project.sh`, `scripts/launchBench`, `scripts/release-workbenches.py`, `docs/newBench.md`, the new test files, `specs/029-setup-guided-wizard/**`) to both `paths:` lists. The timing harness stays out of CI. Check the job still fits its 5-minute timeout.
- Run the full local list ([quickstart.md](quickstart.md) §2) and the workflow on the PR.
- Exit: local list green; all three workflow jobs green on the PR head.
- Tier hint: `[O]` (CI workflow is always governed; real-host suites cannot be run locally).

### Phase 8 — Documentation and release notes (OpenSpec 6.1, 6.2)

- Rewrite `docs/setup-script-ui.md` for the wizard (steps named Workstation, Benches, Agents, Tools, Profiles, Review; keys; Enter → Review → Apply; sizes); update `docs/setup-requirements.md` (strip on Workstation, keys) and `docs/profiles.md` (Profiles as a step).
- Add the wizard to the 1.7 scope in `docs/release-1.7.0.md` and entries to `CHANGELOG.md` and the 1.7 release notes calling out the breaking interaction change (Enter opens Review; only Enter on Review applies) and the three newly offered benches. If 1.7 has frozen, move the note to the 1.8 plan.
- Exit: docs name every step consistently ("Agents", never "AI assistants" as a step name); a doc check greps for the old three-column wording.
- Tier hint: `[S]`.

### Phase 9 — Verification and landing (OpenSpec 7.1–7.4)

- Record timing medians, commit and machine in `release-qa.md`; `openspec validate setup-guided-wizard --strict`; `/speckit-analyze` clean; every task verified.
- Brett's real-host QA ([quickstart.md](quickstart.md) §4): native and WSL acceptance on the candidate commit, a TUI install of 365Bench on a disposable workstation, the glyph check in Windows Terminal and the VS Code terminal, and the fresh-workstation walkthrough (SC-012), recorded in `release-qa.md`.
- Merge gate: Brett approves or edits the bench copy in the running TUI; edits applied; approval recorded (who, date, commit).
- One PR into `release/1.7.0` carrying the OpenSpec change and this feature; merge only on Brett's word; archive the OpenSpec change after merge.
- Tier hint: `[O]` (landing is procedure-heavy and irreversible).

## Acceptance-suite impact

**Rule S1.** A task that changes an asserted interaction updates every local suite that asserts it in the same task, keeping every asserted outcome (SC-010: zero outcomes removed). Docker-backed and real-host suites, which cannot run in a task's `verify:`, move in Phase 7 and run in CI and release QA.

**PTY size.** The suites' PTYs have no window size, so `tput` reports 80×24: every PTY-driven suite runs the **79-column, 24-row tight layout** (research R5). The full nav fits there with single-digit counts (R6); Software Engineering's eight benches all fit with a three-line About (NB-12).

**The `REQUIREMENTS · N/N ready` wait-marker problem after Profiles.** Four suites wait for the strip title as "checks done, workstation ready". The wizard opens on Workstation, so startup waits still match, but the strip no longer appears on other steps. In `test-workstation-acceptance.py` › `account_setup_replies`, G from the component step, the AI accounts action and G back return the user to **Agents**, and the next wait `(TUI, '\n')` never matches — `terminal_screen()` sees only the current screen — so the suite would hang to its timeout. Decision (research R8): wait on the nav's readiness mark `✓ Workstation` (same meaning, on every step) after the first key; keep the strip wait for the first frame; wait for Review's "Nothing has changed yet" line before the applying Enter.

| Suite | Where it runs | What breaks | Change (outcome kept) | Phase |
|---|---|---|---|---|
| `test-workstation-acceptance.py` | real host (compose `workstation-acceptance`) | `TUI` strip wait after Profiles; `→` now reaches Benches, not AI; Enter no longer applies; bench index is global; Profiles label `PERSONAL & COMPANY IDENTITIES` | define `STRIP_READY`, `READY`, `REVIEW` (R8). `CODEX`: `→ → ↓ ↓ Space Enter`, wait `REVIEW`, `Enter`. Profiles: `→ → ↓ ↓ Space G`, `PROFILES` regex on `IDENTITIES … AI accounts … G Back … Q Quit`, `↓ ↓ Enter`, then after `G` wait `READY`, `Enter`, `REVIEW`, `Enter`. Empty and repeat runs: `→ Enter`, `REVIEW`, `Enter`. Benches: `→ Tab` + `↓ × (index of pyBench among benches of its category, catalog-name order)` + `Space`/`D` + `Enter`, `REVIEW`, `Enter`. Keep `'Apply these changes?' not in output` (Review says "Enter applies these changes.") | 7 |
| `test-wsl-workstation-acceptance.py` | real host (WSL) | imports `tui.TUI`; same key changes; bench index | use `tui.STRIP_READY`/`tui.READY`; `codex`/`remove_codex`: `→ → ↓ ↓` then the context-line wait, then `Space`/`D` `Enter`, `REVIEW`, `Enter`; bench phases and frozen guard: `→ Tab` + category index; `empty`: `→ Enter`, `REVIEW`, `Enter` | 7 |
| `test-component-lifecycle.py` | CI compose `component-lifecycle` | `PQ`/`GQ` page-text assertions; `D→↓↓D\n`; raw-transcript strip wait (latent false positive) | `PQ` → `→ P Q` (still exercises P to Workstation); `GQ` asserts `IDENTITIES`, `Personal & companies`, `Workstation account`, `AI accounts`; removal `→ Tab D → ↓ ↓ D Enter Enter`; no-op run `→ Enter Enter`; match the screen with `terminal_screen` | 7 |
| `test-tools-runtime.py` | CI compose `tools-runtime` | stage 0 Space queued a bench on the main screen; Profiles label | stage 0 keys `→ Tab Space ←` (queue the first bench, back to Workstation where `[V …]` is shown); stage 7 waits `IDENTITIES` and `Personal & companies`; G from Workstation returns to Workstation, so stages 9–10 are unchanged; first-paint `PQ` markers unchanged (first frame is Workstation) | 7 |
| `test-setup-guided-flow.py` | CI `regression` | strip wait then `→ ↓ ↓ Space Enter` | `→ → ↓ ↓ Space Enter Enter` after the startup strip wait (checks done, so the Review gate passes); unit tests starting at `CURRENT_SECTION=1` unchanged | 5 |
| `test-setup-cancel.sh` | CI `regression` | piped `\n` applied from the first screen | `$'\e[C\n\n'` (→ Benches, Enter opens Review, Enter applies), same for the empty, cancel and failure cases; must not break when the stubbed `init_components` leaves no bench list | 5 |
| `test-setup-async.py` | CI `regression` | status-update render expects `Docker Up` (strip now Workstation-only); `render_setup_frame` override seam | set `CURRENT_SECTION=3` in that render; override `setup_frame_build` instead of `render_setup_frame`; first-paint, no-discovery and redraw assertions unchanged | 4–5 |
| `test-setup-requirements.py` | CI `regression` | strip renders unboxed; Profiles refusal wording if asserted | `draw_requirements_summary` shim prints the strip; `Vault <State> [V <Action>]` and width assertions unchanged; navigation tests start from the sourced section 0 (R2) and pass unchanged | 5 |
| `test-setup-profiles.py` | CI `regression` | `draw_profiles; draw_setup_footer` render | shims print the Profiles step; widths 36/60/80/100 and no-discovery assertions unchanged; G G round trip unchanged | 5 |
| `test-setup-components.py`, `test-setup-bench-status.sh`, `test-setup-credential-plan.py`, `test-release-version.py`, `test-project-command.py` | CI / local | indirect: lookup rewrite, catalog fields, array literal format | expected to pass unchanged; `ai_items=(…)`/`tool_items=(…)` literal layout is kept (R10); verify in Phases 1–2 | 1–2 |
| `test-setup-consent.py`, `test-docker-prerequisite.py`, `test-install-friction.py`, `test-setup-services.py` | CI `regression` | none expected: they replace `interactive-setup.sh` with a stub or do not drive the TUI | none; run in the regression list | — |

## Governance notes

This feature does **not** need a `## Governed invariants` section of its own: its contract-bearing files (`config/bench-config.json`, the catalog consumers, the selection-file path) are already routed to `[O]` by the rubric's "contract, schema or boundary" and "security-sensitive" clauses, and the repository root's `AGENTS.md` declares no `## Governed invariants` section, so the tasks have **no `[H]` tier** — every task is `[S]` or `[O]`.

Always-governed paths (protocol) that the work touches or must avoid:

- `.github/workflows/credential-recovery.yml` (Workstation Setup) — **touched** in Phase 7 to run and trigger on the new suites; Brett reviews it as a governed change.
- `openspec/changes/setup-guided-wizard/` — **touched** only to tick tasks and, if review finds a wording gap, through an OpenSpec edit with `openspec validate --strict`.
- `config/release-lock.json` (records pins) — **read only**; the catalog test reads it, nothing writes it.
- `.gitmodules` and submodule gitlinks — **not touched**.
- Files that record measured values — `specs/029-setup-guided-wizard/release-qa.md` will record timing medians and real-host results; it is written by the QA tasks, not by builders' code.

## Risks and mitigations

| # | Risk | Mitigation |
|---|---|---|
| 1 | **Key-response budget missed** (top technical risk): 1.7 already redraws in ~250 ms and the prototype in ~130 ms per key on Brett's workstation. | Fork-free renderer by construction (R1); engine first (Phase 4) with the timing harness from day one; CI-safe no-fork static check; per-step medians reported; 25 ms target leaves 4× headroom. If a phase cannot reach 100 ms, stop and return to planning rather than relaxing FR-060. |
| 2 | **jq hazard goes live with 365Bench** (an empty path makes the workBenches root the bench directory). | Phase 1 lands before the catalog entry; static check; digit-leading fixture across 8 consumers; fail-closed helper; release QA installs 365Bench through the TUI. |
| 3 | **Suites hang or assert the wrong screen** (strip-only wait marker; Enter semantics; category-relative bench index). | Rule S1; `READY`/`STRIP_READY`/`REVIEW` markers (R8); category-relative index computed from the catalog; Docker-backed suites run in CI on the PR; real-host suites in QA. |
| 4 | **Enter no longer applies on the first press** surprises returning users. | Review states "Nothing has changed yet. Enter applies these changes."; hints say "Enter Review" and "Enter Apply"; CHANGELOG and release notes call it out as breaking. |
| 5 | **Resize quits setup**: a `WINCH` trap interrupts `read`, which 1.7 treats as Quit. | `handle_input` returns 3 when the resize flag is set (R5); a test sends `SIGWINCH` during `read` and asserts the TUI stays open and repaints. |
| 6 | **Misalignment on hosts without a UTF-8 locale** (`${#}` counts bytes). | Locale check at startup (R9); render-matrix tests run under `LANG=C` as well as `C.UTF-8`. |
| 7 | **Hostile or malformed outside text** drives the terminal. | Worker and foreground sanitising, locale-independent C1 handling, validation of names and ids (R3); `ESC [2J` and C1 CSI fixtures in metadata, row details, identities summary and helper results. |
| 8 | **Catalog rewrites drop metadata or pull in local clones.** | Merge-preserving `update-bench-config.sh` that skips unlocked clones; `new-bench.sh` keeps fields; maintenance fixture tests; docs updated. |
| 9 | **Copy drift or approval missed.** | Catalog test enforces presence, length, characters and no versions; merge gate records Brett's approval in the running TUI. |
| 10 | **Glyph width differs across terminals.** | Single-column glyphs only; character padding; manual check in Windows Terminal and VS Code terminal in QA. |
| 11 | **Edits over UNC drop the executable bit or add CR.** | Pre-commit checks in [quickstart.md](quickstart.md) §0; verify commands include `git ls-files -s` mode checks for `scripts/interactive-setup.sh`, `scripts/launchBench`, `setup.sh`. |
| 12 | **Large diff in a busy 3,400-line file conflicts with other 1.7 work.** | Small phase commits; rebase on `release/1.7.0` at each phase boundary; one PR. |
| 13 | **1.7 freezes before merge.** | Retarget the same PR to the 1.8 line; move the scope note to the 1.8 plan; no requirement changes (spec Assumptions). |
| 14 | **WSL unresponsive during builds** (`Wsl/Service/0x8007274c`). | Retry with backoff; never `wsl --shutdown`; keep editing over UNC while it is down. |
| 15 | **CI regression job exceeds its 5-minute timeout** with five more suites. | Measure locally; keep the new suites fixture-only (no Docker); raise the timeout in the same governed edit only if needed. |

## Speckit test strategy

- **Test-first per task.** Each task names its tests in `files:` and runs them in `verify:` together with the existing suites its files can break; the task is not marked done until its verify command passes and its diff touches only its files (protocol › Build Tiers).
- **Suites keep their outcomes.** Rule S1; no asserted outcome is deleted; keystroke and marker changes are listed in the impact table.
- **Determinism in CI, timing locally.** CI runs only deterministic suites; the timing harness is local and recorded; the no-fork static check guards the renderer in CI.
- **Fixtures, never the machine.** New suites build temporary repositories (`scripts/`, `config/`, `bootstrap.sh` copies, fixture catalogs including a digit-leading bench), stub `tput`, `docker`, `git`, `jq`, `python3` where they assert non-use, and never touch the real Docker engine.

### Requirement → test map

| Requirements | Test |
|---|---|
| FR-052–FR-055, SC-003, SC-013 (rules) | `test-bench-catalog.py` |
| FR-056–FR-058, SC-004 | `test-bench-catalog-lookups.py` |
| FR-059 | `test-bench-catalog-maintenance.sh` |
| FR-048–FR-051, SC-011 | `test-setup-wizard.py` (metadata) + `test-setup-async.py` |
| FR-001–FR-028, FR-040, SC-001, SC-007–SC-009 | `test-setup-wizard.py` (flow), `test-setup-cancel.sh`, `test-setup-guided-flow.py`, `test-setup-requirements.py`, `test-setup-profiles.py` |
| FR-029–FR-039, FR-041–FR-047, SC-002, SC-005 | `test-setup-wizard-layout.py` (render matrix: all six steps at 36, 60, 87 columns × 24, 40 rows and unknown height, plus 37×24, 80×24, 88×39, 88×40, 120 columns; no-fork check) + `test-setup-async.py` |
| FR-060, SC-006 | `test-setup-render-timing.py` (local) + no-fork check (CI) |
| FR-015, SC-009 | `test-setup-wizard.py` (selection-file equality with 1.7 for the same queued changes; apply-plan and dependencies-plan draw nothing) + `test-setup-guided-flow.py` |
| SC-010, SC-012 | Docker-backed suites in CI; real-host acceptance, 365Bench install and walkthrough in release QA |

### Exact local suite list and commands

The full list, a one-shot loop, the Docker-backed jobs and the real-host hand-off are in [quickstart.md](quickstart.md) §2–§4. In short, from the worktree root inside WSL:

```bash
# Existing setup suites (Workstation Setup › regression job, in its order)
python3 -m py_compile devcontainer.test/test-wsl-workstation-acceptance.py devcontainer.test/test-workstation-acceptance.py
for t in acceptance-pty-drain image-layer-budget setup-requirements setup-async setup-services workbenches-account \
         setup-profiles profile-multi-identity docker-prerequisite setup-components vibe-annotations-readiness \
         setup-credential-plan git-transport; do python3 devcontainer.test/test-$t.py || echo "FAIL $t"; done
bash devcontainer.test/test-setup-bench-status.sh
python3 devcontainer.test/test-compose-ai-profiles.py
bash devcontainer.test/test-ai-credential-keyvault.sh
bash devcontainer.test/test-opencode-omniroute-credential.sh
for t in vault-credential-recovery setup-guided-flow setup-consent install-friction azure-cli-runtime; do python3 devcontainer.test/test-$t.py || echo "FAIL $t"; done
bash devcontainer.test/test-setup-ai-credential-recovery.sh
bash devcontainer.test/test-setup-cancel.sh
# Also affected
python3 devcontainer.test/test-release-version.py
python3 devcontainer.test/test-project-command.py
# New (this feature)
python3 devcontainer.test/test-bench-catalog.py
python3 devcontainer.test/test-bench-catalog-lookups.py
bash    devcontainer.test/test-bench-catalog-maintenance.sh
python3 devcontainer.test/test-setup-wizard.py
python3 devcontainer.test/test-setup-wizard-layout.py
# Local only
python3 devcontainer.test/test-setup-render-timing.py
# Change
openspec validate setup-guided-wizard --strict
```

## Agent context update

Skipped. The user-global `speckit-plan` skill updates the plan reference between `<!-- SPECKIT START -->` and `<!-- SPECKIT END -->` in `CLAUDE.md`; this repository's `CLAUDE.md` has no such markers (they are in `AGENTS.md`, still pointing at `specs/028-device-trust/plan.md`), and this planning run may write only under `specs/029-setup-guided-wizard/`. Repoint `AGENTS.md` to this plan when the feature's implementation starts, as an ordinary task.

## Complexity Tracking

No constitution violations to justify (see Constitution Check).
