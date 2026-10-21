# Proposal: Guided setup wizard for workBenches 1.7

## Why

The setup TUI puts benches, AI assistants and tools in three fixed 24-column lists side by side (84 columns), with Requirements and Profiles on separate pages. It overflows terminals narrower than that (side-by-side captures break at 60 and 36 columns), gives a new workstation no order to follow, cannot say what a bench is for, and applies queued changes on the first Enter without showing them. Three locked benches (goBench, rustBench, 365Bench) are missing from the catalog, so setup never offers them, and cataloguing 365Bench exposes a jq lookup hazard that can aim bench setup at the workBenches root.

## What Changes

- Replace the three-column main screen and the separate Requirements and Profiles
  pages with a guided wizard, one step per screen, in the order a new workstation
  needs: **Workstation → Benches → Agents → Tools → Profiles → Review** (the
  former AI assistants section is named Agents). A top nav bar shows every step,
  progress, queued-change counts and workstation readiness, and fits an
  80-column terminal. ←/→ move between steps; ↑/↓ move within a step.
- **BREAKING (interaction):** Enter on a component no longer applies. Enter opens
  Review, which lists every queued install, update and removal by step; Enter on
  Review applies with today's gating. Enter on a Workstation service row or a
  Profiles row still runs that action immediately.
- The Benches step groups benches by **category** (Software Engineering, Science,
  System Administration, and Electrical Engineering shown as "coming soon"), with
  a category zone and a bench zone, and a small scrolling **About** panel that
  explains what the focused bench is for and what it contains.
- The requirements strip (`REQUIREMENTS · N/N ready … Vault <State> [V <Action>]`)
  moves directly under the nav and appears only on the Workstation step; V still
  runs the Vault action from any step. Per-step title and description lines are
  removed.
- The layout fits every terminal from 36 to 87+ columns and never draws a frame
  taller than a known terminal height; the banner collapses below 40 rows.
- `config/bench-config.json` gains top-level `categories` and per-bench
  `category`, `tagline`, `usedFor[]` and `contains[]`; goBench, rustBench and
  365Bench are catalogued; simBench's description is corrected (OpenMM/ESM with
  CPU PyTorch; no baked AlphaFold/ESMFold weights).
- Every shell consumer of the catalog looks benches up by name safely
  (`jq --arg n "$bench" '.benches[$n]…'`) and fails closed instead of targeting the
  workBenches root; a regression test uses a digit-leading bench name. Catalog
  maintenance scripts preserve the new metadata.
- The background status worker publishes bench and category metadata beside its
  existing `catalog` file; the foreground reads it with plain Bash and degrades to
  path-derived categories when metadata is missing.
- Setup, Profiles and release documentation, the changelog, keystroke-driven tests
  and the real-host acceptance suites are updated; every asserted outcome is kept,
  and new tests cover the wizard, the catalog and the safe lookups.

Unchanged: `setup.sh` modes (`--select-only`, `--dependencies-plan`,
`--apply-plan`), the selection-file JSON, apply/plan semantics, rendering without
discovery, immediate first paint, partial redraw of changed lines, blinking
"Loading" indicators, Q exiting with status 130, and Profiles internals.

## Capabilities

### New Capabilities

- `setup-wizard-flow`: wizard steps and order, nav bar, step and jump keys,
  Enter→Review→Apply, the Workstation, Agents, Tools, Profiles and Review
  steps, readiness handling, and the preserved setup contracts.
- `setup-wizard-layout`: frame composition, the per-step selector area, width and
  height bounds, banner collapse, first paint without discovery, partial redraw
  and loading indicators.
- `setup-bench-browser`: the Benches step — category block, focus zones, bench
  panel, About panel and scrolling, height-aware layout, and catalog metadata
  delivery with degraded fallbacks.
- `bench-catalog`: the bench catalog's category and presentation schema, catalog
  completeness and accuracy, name-safe lookups in shell consumers, and metadata
  preservation by maintenance scripts.

### Modified Capabilities

None. `openspec/specs/` holds only the Claude CLI capabilities
(`claude-profile-binary-selection`, `claude-session-restart-notice`,
`shared-ai-cli-tooling`, `user-managed-claude-updates`); setup TUI and bench
catalog behaviour has no existing capability.

## Impact

- Code: `scripts/interactive-setup.sh` (rendering, input, step model, Review),
  `scripts/lib/setup-status-loader.sh` (metadata publishing and reading, readiness
  jump), and the catalog's shell consumers `scripts/setup-workbenches.sh`,
  `scripts/update-project.sh`, `scripts/launchBench`, plus
  `scripts/update-bench-config.sh` and `scripts/new-bench.sh`.
- Data: `config/bench-config.json` (additive fields and three entries);
  `config/credential-requirements.json` (the three benches become TUI options).
  Python consumers (`setup_selection.py`, `setup-components.py`,
  `release-workbenches.py`, `remove-bench-checkout.py`) already index by name;
  the new entries become valid selection keys.
- Tests: suites in `devcontainer.test/` that drive the TUI by keystroke or assert
  its text, including `test-workstation-acceptance.py`,
  `test-wsl-workstation-acceptance.py`, `test-component-lifecycle.py` and
  `test-tools-runtime.py`; new wizard, catalog and lookup tests.
- Docs: `docs/setup-requirements.md`, `docs/profiles.md`, `docs/setup-script-ui.md`,
  `docs/setup-credential-requirements.md`, `docs/release-1.7.0.md`, `CHANGELOG.md`
  and the 1.7 release notes.
- Users: Enter now opens Review first; three more benches become installable.
- Not affected: the disabled OpenTUI app (`scripts/setup-ui`), Profiles internals
  (`scripts/setup-profiles.py`), Docker/Tools/Vault service behaviour.

## Release Target

workBenches **1.7** (`release/1.7.0`, `VERSION` `1.7.0-dev.1`; 1.7 is not yet a
release candidate). If 1.7 freezes before this lands, the change retargets to
**1.8** without changing its requirements. 1.6 is frozen at rc.3 and, per
`docs/releases.md`, admits only release fixes.

## Handoff

This change hands off to exactly one Speckit feature,
`specs/029-setup-guided-wizard`, on branch `029-setup-guided-wizard` (cut from
`origin/release/1.7.0` at `ccc9eac`). The OpenSpec change and the Speckit feature
land together in one pull request into `release/1.7.0`. The open questions in
`design.md` go to `/speckit-clarify` for that feature.

## Decision Record

Brett Heap's decisions, quoted from the design sessions:

- Original ask: "use your design skills to create some version of the TUI and put
  them on branches that I can test"; scope chosen: "Look only, same behavior",
  Bash TUI.
- Nav: "we have what we call the top nav bar. this shows workstaitons, benches, ai
  assitants, tools, and review. the arrows move thru these sections. this part is
  good."
- Benches: "the user should select the category of the bench. so they can slect
  Science and then BioBench or chemBench or physicsBench. or category Software
  Engingeering Bench, with the devBenches listed. Or Electrical Engineerging
  Benches with some that we will add for EE tools. we also have System
  Administration and that covers cloudBench and 365Bench … when the user selects
  a bench, we can explain what the bench is used for and what it contains. can we
  make a small scrolling window in the TUI?"
- Refinement: "this design is good, but too busy. we can remove the [step title /
  group info] part. and move category up. The REQUIREMENTS · 3/3 ready … [V
  Connect] can also be only visible when the workstation is selected. this will
  be in the area where category is for benches."
- Approval and target: "lets go with this design" → "1.7 is fine. we can target
  that" / "we can even use 1.8 if we need to".
- Profiles: its own wizard step before Review (decision, paraphrased).
- Clarification (`/speckit-clarify`, 2026-10-21): Brett answered the 20 questions
  in `specs/029-setup-guided-wizard/clarify-questions.md`. On the nav fit:
  "use Agents instead of ai or ai assistants". The other answers confirm the
  design or set rules folded into the deltas: the `G Profiles` pointer on the
  Workstation step, a two-line hint cap and `Changes: N` below 60 columns, no
  version numbers in bench copy, a 100 ms key-response budget, a catalog that
  matches the release lock exactly, and the bench copy approved in the running
  TUI before merge.

The approved scope was "look only"; the deliberate behaviour changes are
Enter→Review→Apply, the category/About browsing on the Benches step, and the
catalog additions needed to show every locked bench.

## Non-Goals

- The disabled OpenTUI app (`scripts/setup-ui`).
- Profiles internals (`scripts/setup-profiles.py` and its manager screens).
- New Electrical Engineering benches, or chemistry/physics Science benches.
- Categories or About panels for the Agents and Tools steps.
