# Amendment record: launch-current-claude (AMENDMENT RULED, R1 to R5)

Status: ruled. This record is non-normative. It changes no requirement or scenario line by itself.
Governs: opensoft/workBenches#119; the ratification in [ratification-2026-09-29.md](ratification-2026-09-29.md) (Brett Heap, 2026-09-29, verbatim "ratify the OpenSpec change when it's green", baseline `34979348`, ratified head `376ee6c`, landed as `c2403eb9`)
Raised by: Copilot's reviews of #120 at `34979348` and at `376ee6c`; put to Brett Heap as RULING NEEDED on opensoft/workBenches#119
Rulings asked in: [comment 5894243795](https://github.com/opensoft/workBenches/issues/119#issuecomment-5894243795) (R1, R2, R3) and [comment 5894338733](https://github.com/opensoft/workBenches/issues/119#issuecomment-5894338733) (R4, R5)
R1 to R4 ruled by: Brett Heap, 2026-09-30, in session, verbatim: "amend as proposed". Read as R1, R2, R3 and R4 taking their After text as proposed. Recorded: lane openXfactory-5's RULED line of 2026-09-30T15:24:34Z in `lanes/log/openXfactory-5.md`, `opensoft/brett-wip` commit `531c01a09`
R5 ruled by: Brett Heap, 2026-09-30, in session by multichoice, verbatim option label: "amend as (a) (Recommended)". Read as R5 taking alternative (a). Recorded: lane openXfactory-5's RULED line of 2026-09-30T15:29:54Z in `lanes/log/openXfactory-5.md`, `opensoft/brett-wip` commit `e2b879387`
Landing: Brett Heap, 2026-09-30, verbatim option label: "land #122 when green (Recommended)", recorded in the same RULED line (`e2b879387`). The texts below are not in force until that pull request lands.

## Why this record exists

After a ratify word, requirement or scenario text is not changed except by the ratifier's word, following the estate's 2026-09-01 precedent. So the five points were put to Brett Heap with exact before and after text, and #120 landed as ratified. The amendment carries the ruled After text of all five, each as the ruling comment gave it.

## The five points and their rulings

| Point | Where | Ruled | Text |
|---|---|---|---|
| R1 | `claude-profile-binary-selection`, scenario "New session launch" | "amend as proposed" | the After text, in `specs/claude-profile-binary-selection/spec.md` |
| R2 | `user-managed-claude-updates`, requirement "Layer 3 provides a user-owned Claude Code installation at npm latest" | "amend as proposed" | the After text, in `specs/user-managed-claude-updates/spec.md` |
| R3 | `shared-ai-cli-tooling`, scenario "Bench inherits the baseline" | "amend as proposed" | the After text, as a MODIFIED delta in `specs/shared-ai-cli-tooling/spec.md` |
| R4 | `claude-profile-binary-selection`, scenario "The launch says what launched" | "amend as proposed" | the After text, in `specs/claude-profile-binary-selection/spec.md` |
| R5 | `claude-session-restart-notice`, the SHALL of "A running session is told when its binary moved" against the scenario "No process table" of "The restart notice degrades silently" | "amend as (a) (Recommended)" | alternative (a), in `specs/claude-session-restart-notice/spec.md`; the scenario "No process table" stands as ratified |

## R5: the alternatives offered, verbatim from comment 5894338733

As ratified, the SHALL promised the line whenever the process was started from a replaced executable or runs an older version, while the scenario "No process table" says the panel shows no restart line on a host without `/proc`. Without `/proc` the status line still has the running version from its JSON, yet the degrade rule suppresses the notice. Alternative (a) was ruled; alternative (b) was offered and not taken.

```text
Before (spec.md:9):
The shared Claude status line SHALL print one green line, ..., at the top of its panel whenever the Claude Code process it renders for was started from an executable since replaced on disk, or runs an older version than the one installed.

(a) After, scoping the guarantee (RULED):
The shared Claude status line SHALL print one green line, ..., at the top of its panel whenever the restart check can read the process it renders for, and that process was started from an executable since replaced on disk or runs an older version than the one installed.

(b) After, keeping version detection without /proc (scenario "No process table") (not taken):
- **WHEN** the host has no `/proc`, for example macOS
- **THEN** the panel shows the restart line only when the status line's running version is older than the version installed at `CLAUDE_BIN`, and never errors
```

## What lands with R3

R3 adds a MODIFIED delta on `shared-ai-cli-tooling`, a capability that exists only in the active changes `refresh-shared-ai-cli-tooling` and `repair-ai-cli-runtime-layout`. The delta carries the whole requirement "Shared image owns the CLI baseline" as `repair-ai-cli-runtime-layout` states it, with all three of its scenarios by name and only the THEN of "Bench inherits the baseline" changed. Four non-normative mirrors go with it: the Modified Capabilities entry and the Sequencing sentence in `proposal.md`, the Risks bullet in `design.md`, and task 2.2 in `tasks.md`. Archive order becomes `refresh-shared-ai-cli-tooling`, `repair-ai-cli-runtime-layout`, `prefer-updated-claude`, then this change.
