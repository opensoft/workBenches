# Tasks

- [x] T001 Normalize explicit versus inherited launch mode and publish the marker for bare Claude execution.
- [x] T002 Extend launcher regressions and document the environment contract.
- [x] T003 Run focused launcher tests, syntax checks and governance validation; record results.

## Verification

- Binary selection and launch-mode regression: passed, including direct profile launches, explicit lanes with inherited markers, both orders of `--no-lane`, actual tmux children and bare fallback after lane refusal.
- Name guard hook installation: 27 scenarios, 59 assertions passed.
- Lane defaults: 49 scenarios, 206 assertions passed for each of `claude-profile` and `lclaude`.
- Amendment 11: 111 scenarios, 467 assertions passed; existing vendored-skill notices remain reported by the suite.
- Changed shell files pass `bash -n`; diff whitespace checks and strict OpenSpec validation pass.
- Repeated the checks after updating the worktree to current `main`; binary selection also preserves all 72 current-Claude resolver checks.
