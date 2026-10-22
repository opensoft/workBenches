# Codex build prompt: guided setup wizard (feature 029)

Instructions for Codex, running inside WSL (or Linux) in the feature worktree. Treat everything below as if Brett had pasted it into the session.

---

Build Speckit feature `029-setup-guided-wizard`: the workBenches guided setup wizard for release 1.7.

The feature is approved and fully planned. The OpenSpec change, spec, clarifications, checklists, plan and tasks are all done and committed. Your job is `/speckit-implement`, run through your `speckit-implement` skill.

## Where

- You work in the Speckit feature worktree for branch `029-setup-guided-wizard`, which is `../speckit-worktrees/029-setup-guided-wizard` beside the workBenches checkout. From a workBenches checkout you can reach it with:
  `cd "$(git worktree list | awk '/\[029-setup-guided-wizard\]/ {print $1}')"`
- The branch tracks `origin/029-setup-guided-wizard`. It was pushed only so this prompt can be fetched on any machine. That push does not authorize any further push.
- Before starting, `git status -sb` must show a clean tree, level with `origin/029-setup-guided-wizard`. Stop and tell me if it doesn't.
- Work only in this worktree. The main checkout, the other worktrees and the prototype branch `prototype/tui-guided-wizard` are read-only.
- Release target: `release/1.7.0` (`VERSION` is `1.7.0-dev.1`, not a release candidate). If 1.7 freezes before the PR (T041), stop and ask me whether to retarget to 1.8.

## Read first

1. Your user-global `~/.agents/AGENTS.md` and the protocol it points to, `~/.agents/protocols/openspec-speckit-workflow.md`. Read especially "Worktree Rules", "Build Tiers" (including "Without subagents") and "Landing a feature".
2. `specs/029-setup-guided-wizard/handoff.md`: state, gates and environment hazards. Its "Dispatch rules" section is for Claude lanes; you follow the protocol's "Without subagents" path instead.
3. In `specs/029-setup-guided-wizard/`:
   - `tasks.md`, your work list (T001–T045);
   - `plan.md`, `research.md` (R1–R11), `data-model.md`, `contracts/` and `quickstart.md`;
   - `spec.md`, including both Clarifications sessions;
   - `analysis.md`: findings, and Brett's accepted decisions D1–D5.
4. `openspec/changes/setup-guided-wizard/` is approved. Edit it only where a task's `files:` list names it.

## Start

- `export SPECIFY_FEATURE=029-setup-guided-wizard SPECIFY_FEATURE_DIRECTORY=specs/029-setup-guided-wizard`
- `.specify/feature.json` is stale and points at 018. If a `.specify` script rewrites it, restore it with `git checkout -- .specify/feature.json` before every commit.
- Then run your `speckit-implement` skill for this feature.

## How to build (protocol › Build Tiers › Without subagents)

- Run the tasks one at a time, in `tasks.md` order, honouring each task's "Needs …" dependencies. Do `[P]` tasks one after another.
- The `[S]`/`[O]` tags are for Claude dispatch. Ignore them for routing, but never remove or change them, or any `files:` or `verify:` field. If a field is provably wrong, fix only that field and say so in the commit.
- For each task:
  1. Change only the paths in its `files:` list.
  2. Run its `verify:` command exactly as written, from the worktree root.
  3. Check scope: changed and untracked paths stay within `files:`, `git diff --summary` shows no mode changes, and line endings are LF.
  4. Only when steps 2 and 3 pass, tick the task `[X]` in `tasks.md` and commit it on its own: repo-style imperative subject, task ID in the body, body says why. If you run in a lane, follow `AGENTS.md`'s lane trailer rule.
- If a verify fails, fix it within scope and re-run. Never weaken a test, a verify command or an approved requirement to get a pass. If a task can't pass without leaving its `files:` list or changing a requirement, stop and report the failing output.
- At each phase boundary, run `git fetch`. If `origin/release/1.7.0` has moved, rebase onto it and re-run the last verify; ask me first if that would need a force push of anything already on origin. Then send me a short progress note.
- Before T039, re-run your `speckit-analyze` skill and fix any mechanical findings.

## Must-knows

- Phase 1 order matters.
  - Do T002 first: `test-setup-services.py` fails on WSL until the WSL item is stubbed.
  - T003 and T004 (bracket-safe jq lookups, fail-closed apply) must land before T005 adds 365Bench to `config/bench-config.json`. A bench name starting with a digit breaks interpolated jq paths like `.benches.${name}`, and can make the workBenches root the bench directory.
- The renderer is a rewrite that starts no subprocesses: no `$(…)`, pipes or external commands per frame (plan R1: 100 ms budget per key, 25 ms target). Don't port the prototype's renderer, which takes about 130 ms per key. The timing harness runs locally only; record its numbers where the tasks say.
- Don't run `./setup.sh` against this machine, Docker builds, installers or anything else that changes the host. The suites use fakes.
- To look at the TUI, use `scripts/interactive-setup.sh --select-only /tmp/wizard-preview.json`. Nothing gets applied, but Enter or Space on the Docker, Tools or Vault rows, and the V key, still run service actions, so avoid them.
- Never run `wsl --shutdown` or restart WSL.

## Stop points (Brett only)

Stop after T039 and report. Then, only with my explicit OK in chat:

- T040, bench copy approval: I review every bench's tagline and About text in the running preview. Apply my edits exactly and record the approval row. This comes before any push.
- T041: push your build commits to `origin/029-setup-guided-wizard` and open one PR into `release/1.7.0`.
- T042: CI check, after the push.
- T043: real-machine QA, which I do.
- T044: merge, only on my word.
- T045: archive the OpenSpec change, only after the merge.

Never push, force-push, merge, open or close PRs, or archive without that OK.

## Reporting

- At each phase boundary: tasks done, verify results, commit hashes, anything surprising.
- After T039: a summary per phase, full suite results, timing numbers (engine-only and full Benches), any remaining analyze findings, and what T040 needs from me.
- If your context resets, re-read `handoff.md`, `tasks.md` and this file, and resume at the first unchecked task. Never redo a ticked task without saying why.
