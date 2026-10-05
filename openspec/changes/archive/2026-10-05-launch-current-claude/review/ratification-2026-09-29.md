# Ratification record: launch-current-claude

Status: ratified
Ratified by: Brett Heap, 2026-09-29, in session, verbatim: "ratify the OpenSpec change when it's green"
Recorded: lane openXfactory-5's RULED line of 2026-09-29T16:16:17Z in `lanes/log/openXfactory-5.md`, `opensoft/brett-wip` commit `0af6fcb1`
Baseline: opensoft/workBenches#120 at `34979348`, the change's only head when the word was given (pushed 2026-09-29T16:03Z), with its checks green (CodeQL: Analyze actions, javascript-typescript and python)
Governs: opensoft/workBenches#119, Brett Heap's rulings on point 1 (comment 5893687866) and point 2 (comment 5893706470)

## What is ratified

The requirement and scenario text under `specs/`, exactly as it stood at the baseline:

- `user-managed-claude-updates`: ADDED, 3 requirements
- `claude-profile-binary-selection`: RENAMED 1, MODIFIED 3, ADDED 1, against the active `prefer-updated-claude`
- `claude-session-restart-notice`: ADDED, 3 requirements

No requirement or scenario line has changed since the baseline.

## Addendum: non-normative corrections folded under the same word

1. `design.md`, Non-Goals: one bullet naming direct `lane-start` invocation as `opensoft/openRepoTools`' act under the home ruling. It answers Copilot's point on `specs/claude-profile-binary-selection/spec.md:40`.
2. `proposal.md`: the `Status:` and `Ratified by:` header. `tasks.md`: the ratification tick, with the handoff task renumbered after it. This record.

## Ruling needed: normative review findings held for the ratifier

Copilot's review at the baseline raised three points that would change requirement or scenario text. After a ratify word, such changes are the ratifier's act. The packet therefore stands as ratified, and each point is put to Brett Heap on opensoft/workBenches#119 (comment 5894243795) with exact before and after text and two words: "amend as proposed", which means a follow-up amendment, or "keep as ratified".

- **R1.** `claude-profile-binary-selection`, scenario "New session launch": narrow its WHEN to a session started while an installed candidate equals npm's published version, so that it no longer collides with the ahead, offline and stale-allowed scenarios.
- **R2.** `user-managed-claude-updates`, requirement "Layer 3 provides a user-owned Claude Code installation at npm latest": qualify its SHALL with the exact version a build may be given, which is what the scenario "A direct caller names the version" already allows.
- **R3.** `shared-ai-cli-tooling`, scenario "Bench inherits the baseline": narrow its THEN to presence and runnability, allowing a Layer 3 user-owned `claude` or `codex` first on `PATH`. That is a MODIFIED on a capability this change does not declare, and the point 1 ruling keeps its requirement.
