---
description: "Resume parked features: recreate the worktrees, restore the state, and un-commit the parked work"
---

# Resume Parked Features

Recreate the worktrees `/speckit.git.park` recorded, restore
`.specify/feature.json` and the last-worktree state file, and un-commit the
parked work so it comes back exactly as it was left.

## Prerequisites

- The Speckit worktree overlay must be installed:
  `.specify/extensions/git/scripts/bash/resume.sh` must exist and be
  executable. If it does not, tell the operator to run `setup-openspeckit`
  and stop.
- `checkout_mode: worktree`, Python 3, and a Git checkout with `.specify/`.
- In a three-leg project the legs must be initialised first
  (`git submodule update --init`, or `make bootstrap`).
- The same workspace repository as `park`, named in
  `${AGENT_PROTOCOL_ROOT:-$HOME/.agents}/workspace.yaml`. **Never write that
  file for the operator.** The resolved order is `--workspace`, then
  `$SPECKIT_WORKSPACE_PATH`, then `orgs.<org>` for the project's own org, then
  the top-level default; a malformed `orgs:` block refuses by name
  (`workspace-config-invalid`, exit 2) rather than falling back to the default.

## Execution

Run from the project root (the assembly root in a three-leg project):

```bash
.specify/extensions/git/scripts/bash/resume.sh --json
```

Useful flags:

| Flag | Effect |
|------|--------|
| `--dry-run` | Print the plan; create, write and reset nothing |
| `--feature <branch>` | Resume only this feature; repeatable |
| `--workspace <path>` | Workspace checkout, overriding the user config |
| `--keep-staged` | Stop after the soft reset, leaving the work staged |

The staged/unstaged split does not survive a park: one commit cannot carry two
states. The default restores everything unstaged; `--keep-staged` gives the
staged form back.

## How to read the exit code

| Code | Meaning | What to do |
|------|---------|------------|
| 0 | Everything asked for was resumed, or there was nothing to resume | Report the branches, `FEATURE_JSON` and `STATE_FILE` |
| 1 | Usage or environment error | Fix what the message names; nothing was changed |
| 2 | A refusal before anything was done, or every feature was refused | Report the refusal verbatim |
| 3 | Partial: some resumed, some refused | Report both lists |

## What to tell the operator on each refusal

Print the script's own message verbatim, then add the reading below.

| Refusal | Reading |
|---------|---------|
| the branch has moved since it was parked | **The ruling on `openRepoShape#77`: nothing is ever reset over commits this workspace did not park.** The message names the parked commit, the current tip and the reconciliation commands. Offer to run the `log` command; never reset, never force |
| the branch is no longer on origin | Either the feature landed — remove its block from the manifest — or it was deleted by mistake and must be pushed again from the workstation that parked it |
| a path is already there | Something that is not this feature's worktree occupies the path. Nothing here overwrites a directory it did not create |
| the local branch is BEHIND the parked commit | This workstation had the feature before the other one parked newer work. The remediation is the fast-forward the message prints, then `make resume` again — not a deletion |
| the local branch diverged | Local commits exist that the parked commit does not contain. Rename or delete that branch; look first with the printed `log` command |
| parked with `--no-push` | The parked commit exists only on the workstation that parked it. Push it there, re-run `park`, then resume here |
| the record's `pushed:` is neither true nor false | A value `park` never writes — a hand-edit or a bad merge of the record. Do NOT read it as `--no-push`: the record rules nothing out, so whether the parked commit ever left that workstation cannot be read from it. The exit is a park from the workstation that has the worktree, which writes the record afresh |
| the workspace has no entry for this project | Either nothing was parked for it, or it was parked into a differently named file; the message prints the `grep` over that org's directory |
| `workspace-config-invalid` | The config's `orgs:` block is malformed. It refuses rather than falling back to the default workspace, because a confidential org's work must never be indexed in the wrong repository |

`[specify]` lines are not refusals. `worktree already registered … left as it
is` means `resume` is idempotent and touched nothing; a warning that HEAD is
not the parked commit means the un-commit was skipped on purpose, so a second
`resume` never double-resets.
