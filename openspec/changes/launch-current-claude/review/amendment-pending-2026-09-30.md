# Amendment record: launch-current-claude (AMENDMENT PENDING RULING)

Status: pending ruling. This record is non-normative. It changes no requirement or scenario line by itself.
Governs: opensoft/workBenches#119; the ratification in [ratification-2026-09-29.md](ratification-2026-09-29.md) (Brett Heap, 2026-09-29, verbatim "ratify the OpenSpec change when it's green", baseline `34979348`, ratified head `376ee6c`, landed as `c2403eb9`)
Raised by: Copilot's reviews of #120 at `34979348` and at `376ee6c`; put to Brett Heap as RULING NEEDED on opensoft/workBenches#119
Rulings asked in: [comment 5894243795](https://github.com/opensoft/workBenches/issues/119#issuecomment-5894243795) (R1, R2, R3) and [comment 5894338733](https://github.com/opensoft/workBenches/issues/119#issuecomment-5894338733) (R4, R5)
Answered: not yet

## Why this record exists

After a ratify word, requirement or scenario text is not changed except by the ratifier's word, following the estate's 2026-09-01 precedent. So the five points were put to Brett Heap with exact before and after text, and #120 landed as ratified. This pull request carries the proposed texts for R1 to R4, and R5 as ratified, so that one word lands each ruling. Nothing here is in force until that word is given and this pull request lands.

## The five points, and the words each needs

| Point | Where | This pull request | Words |
|---|---|---|---|
| R1 | `claude-profile-binary-selection`, scenario "New session launch" | the proposed After text, applied | "amend as proposed" or "keep as ratified" |
| R2 | `user-managed-claude-updates`, requirement "Layer 3 provides a user-owned Claude Code installation at npm latest" | the proposed After text, applied | "amend as proposed" or "keep as ratified" |
| R3 | `shared-ai-cli-tooling`, scenario "Bench inherits the baseline" | the proposed After text, applied as a MODIFIED delta in `specs/shared-ai-cli-tooling/spec.md` | "amend as proposed" or "keep as ratified" |
| R4 | `claude-profile-binary-selection`, scenario "The launch says what launched" | the proposed After text, applied | "amend as proposed" or "keep as ratified" |
| R5 | `claude-session-restart-notice`, the SHALL of "A running session is told when its binary moved" against the scenario "No process table" of "The restart notice degrades silently" | NOT applied; the ratified text stands | "amend as (a)", "amend as (b)" or "keep as ratified" |

R1 to R4 can each be ruled apart. A "keep as ratified" on one of them removes only that point's hunk from this pull request, and the record is updated to RULED.

## R5: the two alternatives, verbatim from comment 5894338733

The seat does not choose between them. As ratified, the SHALL of the requirement below promises the line whenever the process was started from a replaced executable or runs an older version, while the scenario "No process table" says the panel shows no restart line on a host without `/proc`. Without `/proc` the status line still has the running version from its JSON, yet the degrade rule suppresses the notice.

```text
Before (spec.md:9):
The shared Claude status line SHALL print one green line, ..., at the top of its panel whenever the Claude Code process it renders for was started from an executable since replaced on disk, or runs an older version than the one installed.

(a) After, scoping the guarantee:
The shared Claude status line SHALL print one green line, ..., at the top of its panel whenever the restart check can read the process it renders for, and that process was started from an executable since replaced on disk or runs an older version than the one installed.

(b) After, keeping version detection without /proc (scenario "No process table"):
- **WHEN** the host has no `/proc`, for example macOS
- **THEN** the panel shows the restart line only when the status line's running version is older than the version installed at `CLAUDE_BIN`, and never errors
```

- "amend as (a)": the SHALL of `claude-session-restart-notice` takes text (a). The scenario "No process table" and the requirement "The restart notice degrades silently" stand as ratified.
- "amend as (b)": the scenario "No process table" takes text (b). Seat note, not part of the comment's text: the SHALL of "The restart notice degrades silently" also says the panel renders without a restart line when the check "cannot read the process table", which text (b) contradicts for a host without `/proc`. The ratifier may want that clause narrowed in the same amendment; the seat has not changed it.
- "keep as ratified": no change to `claude-session-restart-notice`.

## What lands with R3, if it lands

R3 adds a MODIFIED delta on `shared-ai-cli-tooling`, a capability that exists only in the active changes `refresh-shared-ai-cli-tooling` and `repair-ai-cli-runtime-layout`. The delta carries the whole requirement "Shared image owns the CLI baseline" as `repair-ai-cli-runtime-layout` states it, with all three of its scenarios by name and only the THEN of "Bench inherits the baseline" changed. Four non-normative mirrors go with it and come out with it on a "keep as ratified": the Modified Capabilities entry and the Sequencing sentence in `proposal.md`, the Risks bullet in `design.md`, and task 2.2 in `tasks.md`. Archive order becomes `refresh-shared-ai-cli-tooling`, `repair-ai-cli-runtime-layout`, `prefer-updated-claude`, then this change.
