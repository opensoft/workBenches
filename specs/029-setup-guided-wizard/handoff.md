# Hand-off: guided setup wizard → WSL build lane

## State

Branch `029-setup-guided-wizard`, cut from `origin/release/1.7.0` at `ccc9eac`. Nothing is pushed.

- `ec5e2f2` OpenSpec change `setup-guided-wizard`. Approved by Brett Heap on 2026-10-21 (OpenSpec 1.1, NB-15).
- `97172b4`, `e5b7c20` spec and the 20 clarification answers; `086b46f`, `8488a6e` release-gate checklists (361/361) and decisions NB-1 to NB-15.
- `0680f10` plan, research R1–R11, data model, contracts, quickstart.
- The latest commit: `tasks.md` (45 tasks: 13 `[S]`, 32 `[O]`, no `[H]`), this note, and analysis fixes to `plan.md` and `quickstart.md`.

Approved: the change, the spec, every clarification, and decisions D1–D5 in `analysis.md` (Brett Heap accepted all five as recommended on 2026-10-21; the tasks follow them). Still to come: the bench copy (T040, merge gate) and Brett's review of the governed CI edit (T033) in the PR.

## How to start

```bash
cd "$(git worktree list | awk '/\[029-setup-guided-wizard\]/ {print $1}')"   # from your workBenches checkout, inside a claude-profile lane
export SPECIFY_FEATURE=029-setup-guided-wizard SPECIFY_FEATURE_DIRECTORY=specs/029-setup-guided-wizard
```

- `.specify/feature.json` is stale and points at 018. A `.specify` script rewrites it to 029. Either restore it with `git checkout -- .specify/feature.json`, or commit it pointing at 029 (your choice). Never leave it dirty.
- Run `claude-usage` first. At 95% or more, stop at a breakpoint and write a handoff.
- Then run `/speckit-implement`.

## Dispatch rules (protocol › Build Tiers)

- The main loop runs on Fable, or on Opus 5.5 with `echo $CLAUDE_EFFORT` printing `max`. It orchestrates and writes no code.
- Dispatch each task by its tier definition, with no `model` override: `[S]` → `sonnet-xhigh`, `[O]` → `opus-xhigh`. You may raise a tier, never lower one.
- Before dispatching:
  - `echo "${CLAUDE_CODE_DISABLE_REFUSAL_FALLBACK-unset}"` must print `1`;
  - `CLAUDE_CODE_EFFORT_LEVEL` must be unset;
  - `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` must be unset.
- Before accepting a task:
  - check the model in every transcript, from the `agent-model-record:` line or `grep -o '"model":"[^"]*"' <output> | sort | uniq -c`;
  - check its scope: the diff stays inside `files:`;
  - run its `verify:`, and only then mark it `[X]`.
- Escalate `[S]` → `[O]` once. When `[O]` fails, go back to `/speckit-plan`. Never reword a refused task to get past a classifier; triage it as the protocol says.

## Gates that need Brett

- **Copy approval.** T040: Brett approves the bench copy in the running TUI before any push. It is the merge gate.
- **Every `git push`.**
  - T041 pushes the real-host QA candidate and opens the PR into `release/1.7.0`.
  - T044 pushes the record commits.
  - T045 pushes the archive branch.
  - Brett's real-host QA (T043) needs the pushed candidate.
- **Merge.** T044, only on Brett's word. If 1.7 has frozen, retargeting is his call.
- **Archive.** T045, only after the merge and with his OK.

## Environment hazards

- **Executable bit.** Editing over `\\wsl.localhost\…` drops it. Run `chmod +x` and check that `git diff --summary` shows no mode change before every commit. Use LF line endings only.
- **Git.** Run git, the suites, `openspec` and `.specify` scripts inside WSL. Never use Windows-side git: it shows phantom changes.
- **WSL outages.** WSL is intermittently unresponsive (`Wsl/Service/0x8007274c`). Retry with backoff. Never run `wsl --shutdown` without Brett.
- **365Bench and jq.** Until Phase 1 (T003, T004) lands, keep 365Bench out of `config/bench-config.json` and never run setup against a catalog that contains it. An interpolated jq lookup fails on the digit-leading name and makes the workBenches root the bench directory.
- **`test-setup-services.py`.** It fails on WSL hosts until T002 lands, because the WSL requirement item is not stubbed. It is the only baseline failure at `0680f10`.
- **Parallel tasks.** `[P]` siblings can read each other's files in their verify commands: T005 runs the credential-plan test, which T006 edits. Re-run a verify after its sibling commits.
- **Prototype branch.** `prototype/tui-guided-wizard` at `896b481` is a behaviour reference only. Do not port its renderer, which takes about 130 ms per key.
- **Timing harness.** It runs locally only (T016, T029, T039). Record the results on Brett's workstation.
