# Tasks

## 1. Governance and handoff

- [x] 1.1 Brett reviews this change (proposal, design, the four spec deltas); record approval or requested edits in the Speckit feature. Bench copy is approved separately, in the running TUI (7.2). (Done: approved by Brett Heap, 2026-10-21 — checklist decision NB-15, recorded in `specs/029-setup-guided-wizard/spec.md` › Clarifications.)
- [x] 1.2 Create Speckit feature `specs/029-setup-guided-wizard` from this change, run `/speckit-clarify` on the open questions in `design.md`, and fold any answer that alters a requirement back into these spec deltas before planning. (Done 2026-10-21: 20 questions answered by Brett and encoded.)
- [x] 1.3 Produce the Speckit plan and tiered tasks (`[H]`/`[S]`/`[O]`) for the groups below; verify `/speckit-analyze` reports no gaps against these specs.

## 2. Catalog and safe lookups (land before the new benches are offered)

- [x] 2.1 Replace every interpolated catalog lookup with `jq --arg` and `.benches[$n]` (and `.infrastructure[$n]`) in `scripts/interactive-setup.sh`, `scripts/setup-workbenches.sh`, `scripts/update-project.sh`, `scripts/launchBench` and any other shell consumer found; verify with a digit-leading fixture bench run against the four shell consumers and the four Python consumers (`setup_selection.py`, `setup-components.py`, `release-workbenches.py`, `remove-bench-checkout.py`), and a static check that fails on a reintroduced interpolation.
- [x] 2.2 Make `process_selections` fail closed on an unresolved or out-of-tree bench path; verify no git, clone or setup script runs against the workBenches root.
- [x] 2.3 Add `categories` and per-bench `category`, `tagline`, `usedFor` and `contains` to `config/bench-config.json` from `specs/029-setup-guided-wizard/bench-copy-draft.json`; add goBench, rustBench and 365Bench; correct simBench's text; verify with a catalog test covering schema, tagline length, control characters, characters that are not single-column printable (wide, fullwidth, combining, zero-width, bidi formatting) in bench copy and category text, version-like tokens in taglines, `usedFor` and `contains` (with the product-name allow-list), the catalog matching the release lock in both directions, and the simBench wording.
- [x] 2.4 Mark goBench, rustBench and 365Bench as TUI options in `config/credential-requirements.json` and update `docs/setup-credential-requirements.md`; verify the credential plan tests pass.
- [x] 2.5 Make `scripts/update-bench-config.sh` and `scripts/new-bench.sh` preserve `categories` and existing per-bench fields, and derive `category` for added benches; make `update-bench-config.sh` skip, with a warning, benches the release lock does not record; document that a new bench needs a release-lock entry and its copy before the catalog test passes; verify with fixture tests, including a local clone the lock does not record.

## 3. Metadata delivery

- [x] 3.1 Publish `bench-categories` and `bench-meta` from the status worker beside `catalog`; read them in the foreground with Bash builtins; load them synchronously when no TTY is attached; verify the foreground runs no jq or Python, control characters are removed from catalog text and from every other outside text (status details, identities summary, helper results), invalid names and ids are ignored, and each degraded fallback behaves as specified (unknown ids, benches outside the bench roots, categories without bench details, partly missing fields, no bench list at all, a bench that leaves the catalog on refresh).

## 4. Wizard flow and layout

- [x] 4.1 Add Review as section 5 and the step map; name the former AI assistants step Agents wherever a step is named; build the nav bar with readiness mark, queued counts, short ` ─ ` connectors and the compact form, without queued counts, for frames too narrow for the full nav; open on Workstation; wire ←/→ without wrap; verify with step-navigation tests, including the full nav at 80 columns with three single-digit counts.
- [x] 4.2 Implement Enter→Review→Apply: Review groups, step names, warnings, empty state, blocker line and scrolling (opening at the first item; P/G returns restore the position); unchanged gating, `--select-only` and empty-run behaviour; verify with tests for each scenario.
- [x] 4.3 Implement P and G jumps with exact focus restore, the readiness jump, V from any step with notices on the current step, R keeping focus and queued changes, and Q exiting 130; verify each with focused tests.
- [x] 4.4 Implement the Workstation (with 1.7's `G Profiles` label on OPTIONAL VAULT and no account rows), Agents, Tools and Profiles steps and per-step footers (context lines for the category zone and for steps without a focused item or state; two-line hint cap and `Changes: N` below 60 columns; the full hint list wrapped at 60–79 columns); verify Profiles actions, their readiness gate and result notices are unchanged.
- [x] 4.5 Implement the head, selector areas, notices, width and height bounds, banner collapse and character-based padding; repaint on width or height change; verify with a 36/60/87-column × 24/40-row/unknown-height render matrix, the existing first-paint and partial-redraw tests, and a key-response test (median redraw ≤ 100 ms at 87×40).
- [x] 4.6 Implement the Benches step: category block and installed counts (a bench counts as installed when Space would update it), two focus zones, bench panel, About panel and scrolling (offset kept on a same-bench refresh), and the height budget (spare rows to bench rows first, then About); verify with zone, scrolling and layout tests.

## 5. Test suites

- [x] 5.1 Update keystroke-driven and text-asserting suites (`test-workstation-acceptance.py`, `test-wsl-workstation-acceptance.py`, `test-component-lifecycle.py`, `test-tools-runtime.py`, `test-setup-async.py`, `test-setup-requirements.py`, `test-setup-profiles.py`, `test-setup-guided-flow.py`, `test-setup-cancel.sh`) to the wizard's keys and markers; keep every asserted outcome.
- [ ] 5.2 Run the full local regression set and the Workstation Setup workflow jobs; all pass.
- [ ] 5.3 Run the real-host acceptance suites (native workstation and WSL) on the candidate commit, including a TUI install of 365Bench on a disposable workstation, the hand check of glyphs in Windows Terminal and the VS Code terminal, and Brett's fresh-workstation walkthrough (SC-012); record results in the feature.

## 6. Documentation and release notes

- [x] 6.1 Update `docs/setup-requirements.md` (strip location, keys, Enter→Review→Apply), `docs/profiles.md` (Profiles as a wizard step) and rewrite `docs/setup-script-ui.md` for the wizard, naming the steps Workstation, Benches, Agents, Tools, Profiles and Review.
- [x] 6.2 Add the wizard to the 1.7 scope in `docs/release-1.7.0.md` (or the 1.8 plan if 1.7 has frozen), and add entries to `CHANGELOG.md` and the 1.7 release notes that call out the breaking interaction change (Enter opens Review; only Enter on Review applies) and the three newly offered benches (goBench, rustBench, 365Bench).

## 7. Verification and landing

- [ ] 7.1 Run `openspec validate setup-guided-wizard --strict` and confirm every Speckit task for `029-setup-guided-wizard` is complete and verified.
- [ ] 7.2 Merge gate: Brett reviews the bench copy for all 12 benches in the running TUI and approves it or requests edits; apply any edits, and record the approval (who, date, commit) in `specs/029-setup-guided-wizard/` before merge.
- [ ] 7.3 Open one pull request into `release/1.7.0` carrying this change and the Speckit feature; merge only on Brett's word and after 7.2.
- [ ] 7.4 Archive this change after the pull request has merged.
