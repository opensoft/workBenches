# Tasks

## 1. Governance and handoff

- [ ] 1.1 Brett reviews this change (proposal, design, the four spec deltas) and the drafted copy for the 12 benches; record approval or requested edits in the Speckit feature.
- [ ] 1.2 Create Speckit feature `specs/029-setup-guided-wizard` from this change, run `/speckit-clarify` on the open questions in `design.md`, and fold any answer that alters a requirement back into these spec deltas before planning.
- [ ] 1.3 Produce the Speckit plan and tiered tasks (`[H]`/`[S]`/`[O]`) for the groups below; verify `/speckit-analyze` reports no gaps against these specs.

## 2. Catalog and safe lookups (land before the new benches are offered)

- [ ] 2.1 Replace every interpolated catalog lookup with `jq --arg` and `.benches[$n]` (and `.infrastructure[$n]`) in `scripts/interactive-setup.sh`, `scripts/setup-workbenches.sh`, `scripts/update-project.sh`, `scripts/launchBench` and any other shell consumer found; verify with a digit-leading fixture bench and a static check that fails on a reintroduced interpolation.
- [ ] 2.2 Make `process_selections` fail closed on an unresolved or out-of-tree bench path; verify no git, clone or setup script runs against the workBenches root.
- [ ] 2.3 Add `categories` and per-bench `category`, `tagline`, `usedFor` and `contains` to `config/bench-config.json`; add goBench, rustBench and 365Bench; correct simBench's text; verify with a catalog test covering schema, tagline length, control characters, release-lock coverage and the simBench wording.
- [ ] 2.4 Mark goBench, rustBench and 365Bench as TUI options in `config/credential-requirements.json` and update `docs/setup-credential-requirements.md`; verify the credential plan tests pass.
- [ ] 2.5 Make `scripts/update-bench-config.sh` and `scripts/new-bench.sh` preserve `categories` and existing per-bench fields, and derive `category` for added benches; verify with fixture tests.

## 3. Metadata delivery

- [ ] 3.1 Publish `bench-categories` and `bench-meta` from the status worker beside `catalog`; read them in the foreground with Bash builtins; load them synchronously when no TTY is attached; verify the foreground runs no jq or Python, control characters are removed, invalid names and ids are ignored, and each degraded fallback behaves as specified.

## 4. Wizard flow and layout

- [ ] 4.1 Add Review as section 5 and the step map; build the nav bar with readiness mark, queued counts and the compact form; open on Workstation; wire ←/→ without wrap; verify with step-navigation tests.
- [ ] 4.2 Implement Enter→Review→Apply: Review groups, step names, warnings, empty state, blocker line and scrolling; unchanged gating, `--select-only` and empty-run behaviour; verify with tests for each scenario.
- [ ] 4.3 Implement P and G jumps with exact focus restore, the readiness jump, V from any step with notices on the current step, R keeping focus and queued changes, and Q exiting 130; verify each with focused tests.
- [ ] 4.4 Implement the Workstation, AI assistants, Tools and Profiles steps and per-step footers; verify Profiles actions, their readiness gate and result notices are unchanged.
- [ ] 4.5 Implement the head, selector areas, notices, width and height bounds, banner collapse and character-based padding; repaint on width or height change; verify with a 36/60/87-column × 24/40-row/unknown-height render matrix and the existing first-paint and partial-redraw tests.
- [ ] 4.6 Implement the Benches step: category block, two focus zones, bench panel, About panel and scrolling, and the height budget; verify with zone, scrolling and layout tests.

## 5. Test suites

- [ ] 5.1 Update keystroke-driven and text-asserting suites (`test-workstation-acceptance.py`, `test-wsl-workstation-acceptance.py`, `test-component-lifecycle.py`, `test-tools-runtime.py`, `test-setup-async.py`, `test-setup-requirements.py`, `test-setup-profiles.py`, `test-setup-guided-flow.py`, `test-setup-cancel.sh`) to the wizard's keys and markers; keep every asserted outcome.
- [ ] 5.2 Run the full local regression set and the Workstation Setup workflow jobs; all pass.
- [ ] 5.3 Run the real-host acceptance suites (native workstation and WSL) on the candidate commit, including a TUI install of 365Bench on a disposable workstation; record results in the feature.

## 6. Documentation and release notes

- [ ] 6.1 Update `docs/setup-requirements.md` (strip location, keys, Enter→Review→Apply), `docs/profiles.md` (Profiles as a wizard step) and rewrite `docs/setup-script-ui.md` for the wizard.
- [ ] 6.2 Add the wizard to the 1.7 scope in `docs/release-1.7.0.md` (or the 1.8 plan if 1.7 has frozen), and add entries to `CHANGELOG.md` and the 1.7 release notes.

## 7. Verification and landing

- [ ] 7.1 Run `openspec validate setup-guided-wizard --strict` and confirm every Speckit task for `029-setup-guided-wizard` is complete and verified.
- [ ] 7.2 Open one pull request into `release/1.7.0` carrying this change and the Speckit feature; merge only on Brett's word.
- [ ] 7.3 Archive this change after the pull request has merged.
