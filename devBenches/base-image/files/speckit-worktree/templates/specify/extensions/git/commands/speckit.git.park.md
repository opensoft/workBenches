---
description: "Park every open feature: commit the work in progress, push it, and record the feature list"
---

# Park Open Features

Commit, push and record every open feature of this project, so the work can be
picked up on another workstation with `/speckit.git.resume`.

## Prerequisites

- The Speckit worktree overlay must be installed:
  `.specify/extensions/git/scripts/bash/park.sh` must exist and be executable.
  If it does not, tell the operator to run `setup-openspeckit` and stop.
- `checkout_mode: worktree` in `.specify/extensions/git/git-config.yml`. In
  `branch` mode there is no worktree to park and the script refuses.
- Python 3, and a Git checkout with a `.specify/` directory.
- A workspace repository, named once by the operator in
  `${AGENT_PROTOCOL_ROOT:-$HOME/.agents}/workspace.yaml`:

  ```yaml
  repository: <owner>/<repo>
  path: ~/projects/<repo>
  orgs:                     # optional: an org with a workspace of its own
    <Org>:
      repository: <Org>/<repo>
      path: ~/projects/<repo>
  ```

  The resolved order is `--workspace`, then `$SPECKIT_WORKSPACE_PATH`, then
  `orgs.<org>` for the project's own org, then the top-level default. A
  malformed `orgs:` block refuses by name (`workspace-config-invalid`, exit 2)
  rather than falling back to the default.

  This file is the operator's. **Never write it for them** — a person names
  their own private repository.

## Execution

Run from the project root (the assembly root in a three-leg project):

```bash
.specify/extensions/git/scripts/bash/park.sh --json
```

Useful flags:

| Flag | Effect |
|------|--------|
| `--dry-run` | Print the plan; commit, push and write nothing |
| `--feature <branch>` | Park only this feature; repeatable |
| `--lane <name>` | Lane recorded in the WIP subject (else `$SPECKIT_LANE`, `$LANE`, `unknown`) |
| `--message <text>` | Provenance appended after the fixed WIP subject prefix |
| `--no-push` | Commit locally and record `pushed: false`; `resume` refuses those entries |
| `--workspace <path>` | Workspace checkout, overriding the user config |
| `--retire-parked-wip` | Allow the single leased push described under R8 below |

## How to read the exit code

| Code | Meaning | What to do |
|------|---------|------------|
| 0 | Everything asked for was parked, or there was nothing to park | Report the branches and the manifest commit |
| 1 | Usage or environment error | Fix what the message names; nothing was changed |
| 2 | A refusal before anything was done, or every feature was refused | Report the refusal verbatim; nothing was recorded |
| 3 | Partial: some parked, some refused | Report both lists; the refusals are printed with their remediation |

## What to tell the operator on each refusal

Print the script's own message verbatim — it already carries the exact
commands. Then add the one-line reading below.

| Refusal | Reading |
|---------|---------|
| no workspace repository is configured | They must create `~/.agents/workspace.yaml` themselves; offer the two lines, do not write the file |
| the workspace checkout is not a Git checkout | The `path:` chosen for this project's org names something that is not a clone; the message prints the exact `git clone` |
| `workspace-config-invalid` | The config's `orgs:` block is malformed. It refuses rather than falling back to the default workspace, because a confidential org's work must never be indexed in the wrong repository |
| a merge, rebase or cherry-pick is in progress | Nothing was committed in that leg. A WIP commit over an unresolved index would park a conflicted tree as if it were work |
| unmerged paths | The same: resolve or reset first |
| no `origin` remote | `resume` rebuilds from pushed branches, so a leg with no remote cannot travel |
| the push was refused | **The work is not lost** — it is committed locally at the sha the message names. `park` never force-pushes |
| behind by parked WIP commits | The remote still carries this workspace's own parked WIP. The message prints the exact `--force-with-lease` command; `--retire-parked-wip` lets `park` run that one push itself. Never run a force-push on the operator's behalf without it |
| a leg worktree is missing | The feature directory exists with only one leg; recreate it or remove the directory |

A `[specify] Warning:` line is never a refusal. The one about
`.specify/feature.json` means the recorded feature is not open any more;
`park` enumerates from `git worktree list`, so the parked list is still right.

A refused feature keeps whatever an earlier `park` recorded for it: a refusal
never erases the entry another workstation would resume from.
