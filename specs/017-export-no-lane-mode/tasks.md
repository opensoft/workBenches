# Tasks

- [x] T001 Normalize explicit versus inherited launch mode and publish the marker for bare Claude execution.
- [x] T002 Extend launcher regressions and document the environment contract.
- [x] T003 Run focused launcher tests, syntax checks and governance validation; record results.
- [x] T004 Vendor the merged marker-aware openRepoTools guard with the canonical updater and verify the actual guard from a launcher subprocess.

## Verification

- Binary selection and launch-mode regression: passed, including direct profile launches, explicit lanes with inherited markers, both orders of `--no-lane`, actual tmux children and bare fallback after lane refusal.
- Name guard hook installation: 27 scenarios, 59 assertions passed.
- Lane defaults: 49 scenarios, 206 assertions passed for each of `claude-profile` and `lclaude`.
- Amendment 11: 111 scenarios, 467 assertions passed; existing vendored-skill notices remain reported by the suite.
- Changed shell files pass `bash -n`; diff whitespace checks and strict OpenSpec validation pass.
- Repeated the checks after updating the worktree to current `main`; binary selection also preserves all 72 current-Claude resolver checks.
- Canonical vendor update pins openRepoTools main commit `a7d125716829dcc24b009e464d919a3e404afba4` from PR #135; all 21 vendored copies match their pins.
- The real-guard integration case fails with status 2 against the old vendored guard and passes with the updated pin. The estate installer regression also passes with the updated vendor set.
