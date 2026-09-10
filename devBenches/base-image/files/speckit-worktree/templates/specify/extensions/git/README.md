# Git Branching Workflow Extension

Git repository initialization, feature checkout creation, numbering (sequential/timestamp), validation, remote detection, and auto-commit for Spec Kit.

## Overview

This extension provides Git operations as an optional, self-contained module. It manages:

- **Repository initialization** with configurable commit messages
- **Feature checkout creation** as either a branch in the current checkout or a linked worktree rooted from a configured base branch
- **Branch validation** to ensure branches follow naming conventions
- **Git remote detection** for GitHub integration (e.g., issue creation)
- **Auto-commit** after core commands (configurable per-command with custom messages)

## Commands

| Command | Description |
|---------|-------------|
| `speckit.git.initialize` | Initialize a Git repository with a configurable commit message |
| `speckit.git.feature` | Create a feature branch or worktree with sequential or timestamp numbering |
| `speckit.git.validate` | Validate current branch follows feature branch naming conventions |
| `speckit.git.remote` | Detect Git remote URL for GitHub integration |
| `speckit.git.commit` | Auto-commit changes (configurable per-command enable/disable and messages) |
| `speckit.git.park` | Park every open feature so another workstation can pick it up |
| `speckit.git.resume` | Recreate parked worktrees and un-commit the parked work |

## Hooks

| Event | Command | Optional | Description |
|-------|---------|----------|-------------|
| `before_constitution` | `speckit.git.initialize` | No | Init git repo before constitution |
| `before_specify` | `speckit.git.feature` | No | Create feature checkout before specification |
| `before_clarify` | `speckit.git.commit` | Yes | Commit outstanding changes before clarification |
| `before_plan` | `speckit.git.commit` | Yes | Commit outstanding changes before planning |
| `before_tasks` | `speckit.git.commit` | Yes | Commit outstanding changes before task generation |
| `before_implement` | `speckit.git.commit` | Yes | Commit outstanding changes before implementation |
| `before_checklist` | `speckit.git.commit` | Yes | Commit outstanding changes before checklist |
| `before_analyze` | `speckit.git.commit` | Yes | Commit outstanding changes before analysis |
| `before_taskstoissues` | `speckit.git.commit` | Yes | Commit outstanding changes before issue sync |
| `after_constitution` | `speckit.git.commit` | Yes | Auto-commit after constitution update |
| `after_specify` | `speckit.git.commit` | Yes | Auto-commit after specification |
| `after_clarify` | `speckit.git.commit` | Yes | Auto-commit after clarification |
| `after_plan` | `speckit.git.commit` | Yes | Auto-commit after planning |
| `after_tasks` | `speckit.git.commit` | Yes | Auto-commit after task generation |
| `after_implement` | `speckit.git.commit` | Yes | Auto-commit after implementation |
| `after_checklist` | `speckit.git.commit` | Yes | Auto-commit after checklist |
| `after_analyze` | `speckit.git.commit` | Yes | Auto-commit after analysis |
| `after_taskstoissues` | `speckit.git.commit` | Yes | Auto-commit after issue sync |

## Configuration

Configuration is stored in `.specify/extensions/git/git-config.yml`:

```yaml
# Branch numbering strategy: "sequential" or "timestamp"
branch_numbering: sequential

# Optional branch name template. Leave empty for the default "{number}-{slug}".
# Supported tokens: {author}, {app}, {number}, {slug}; include exactly one
# {number}. {slug} must not appear before {number}, and the final path segment
# must start with {number}-.
branch_template: ""

# Optional namespace prepended to branch_template unless already present.
branch_prefix: ""

# Feature checkout strategy: "branch" or "worktree"
checkout_mode: worktree

# Base branch used when checkout_mode is "worktree"
base_branch: main

# Parent directory for worktrees (relative to repo root or absolute)
worktree_root: ../my-repo-worktrees

# Custom commit message for git init
init_commit_message: "[Spec Kit] Initial commit"

# Auto-commit per command (all disabled by default)
# Example: enable auto-commit after specify
auto_commit:
  default: false
  after_specify:
    enabled: true
    message: "[Spec Kit] Add specification"
```

`{author}` is derived from Git config and sanitized for branch names. `{app}` is derived from the repository root name. `{number}` is either a zero-padded sequential number or a timestamp, and `{slug}` is the generated short feature name. The effective template defaults to `{number}-{slug}`. Custom templates must contain exactly one `{number}` and keep `{number}-` at the start of the final path segment, so a branch such as `feature/007-existing` participates in sequential numbering and the next branch in that namespace becomes `feature/008-...`.

`branch_prefix` prepends a namespace to the effective template. A trailing slash is optional, and the prefix is not duplicated when `branch_template` already starts with that namespace. Worktree paths use the complete rendered branch name, including namespace segments.

## Installation

```bash
# Install the bundled git extension (no network required)
specify extension add git
```

## Disabling

```bash
# Disable the git extension (spec creation continues without branching)
specify extension disable git

# Re-enable it
specify extension enable git
```

## Graceful Degradation

When Git is not installed or the directory is not a Git repository:
- Spec directories are still created under `specs/`
- Branch creation is skipped with a warning
- Branch validation is skipped with a warning
- Remote detection returns empty results

## Scripts

When `checkout_mode: worktree`, `speckit.git.feature` creates the new feature branch from `base_branch` and adds a linked worktree under `worktree_root`. The JSON result includes `WORKTREE_PATH`, which callers should use as the repo root for subsequent `/speckit.*` commands. The Bash implementation requires Python 3 for authenticated, atomic state publication during non-dry-run worktree creation.

Temporary overrides are also available through environment variables:

- `SPECKIT_GIT_BRANCH_NUMBERING`
- `SPECKIT_GIT_BRANCH_TEMPLATE`
- `SPECKIT_GIT_BRANCH_PREFIX`
- `SPECKIT_GIT_CHECKOUT_MODE`
- `SPECKIT_GIT_BASE_BRANCH`
- `SPECKIT_GIT_WORKTREE_ROOT`
- `GIT_BRANCH_NAME`

The extension bundles cross-platform scripts:

- `scripts/bash/create-new-feature.sh` — Bash implementation
- `scripts/bash/git-common.sh` — Shared Git utilities (Bash)
- `scripts/bash/workspace-common.sh` — Workspace manifest helpers for park and resume (Bash, sourced)
- `scripts/bash/park.sh` — Park open features (Bash)
- `scripts/bash/resume.sh` — Resume parked features (Bash)
- `scripts/powershell/create-new-feature.ps1` — PowerShell implementation
- `scripts/powershell/git-common.ps1` — Shared Git utilities (PowerShell)

## park and resume

`park` and `resume` carry in-flight worktrees between workstations. Worktrees
are git-ignored and never synced, so moving to another machine used to mean
losing them; `park` commits the work in progress on each feature branch,
pushes it, and records the feature list in a **private repository the person
owns**, and `resume` recreates the worktrees from those pushed branches and
un-commits the work again. Nothing is ever copied, moved or synced, and
nothing under `worktree_root` is ever committed at the root: `park` commits
only *inside* the leg worktrees, on the feature branch.

Both are shape-aware. In a three-leg project a feature is
`<worktree_root>/<branch>/{spec,code}` and both legs are parked together; in a
single repository a feature is one worktree under `worktree_root`, recorded as
one leg with `role: repo`. `checkout_mode: branch` is refused in both shapes —
there is no worktree to park.

```
park.sh   [--json] [--dry-run] [--feature <branch>]... [--lane <name>]
          [--message <text>] [--no-push] [--workspace <path>]
          [--retire-parked-wip] [-h|--help]

resume.sh [--json] [--dry-run] [--feature <branch>]... [--workspace <path>]
          [--keep-staged] [-h|--help]
```

The workspace repository is named once, by the person, in
`${AGENT_PROTOCOL_ROOT:-$HOME/.agents}/workspace.yaml`:

```yaml
repository: opensoft/brett-wip
path: ~/projects/brett-wip
orgs:                       # optional: an org whose work must stay inside that org
  MedxSoft:
    repository: MedxSoft/brett-wip
    path: ~/projects/MedxSoft-wip
```

The two top-level keys are the default. The optional `orgs:` map gives one org
a workspace repository of its own, so a confidential org's feature list is
never indexed in the home repository. The override applies to everything that
lives in a workspace repository — the manifests under `workspaces/` and the
handoffs under `handoffs/<estate>/` alike (`park` and `resume` never write a
handoff; a handoff is a document a person wrote). The resolved order is:

1. `--workspace <path>` — wins over everything;
2. `$SPECKIT_WORKSPACE_PATH` — a whole-run override;
3. `orgs.<org>` in the config — an org whose work must stay inside that org;
4. the config's top-level — the default workspace;
5. nothing — refuse, naming the two lines to write.

A malformed `orgs:` block is a named refusal (`workspace-config-invalid`, exit
2) and never a silent fall-through to the default. `SPECKIT_WORKSPACE_REPOSITORY`
overrides the repository slug used in the clone remediation, which otherwise
names whichever repository was chosen — so on a fresh machine the refusal says
exactly which `<org>/<user>-wip` to clone. `park` prints the choice on its
`WORKSPACE:` line and in `--json` as `WORKSPACE_SOURCE`.

Inside whichever repository is chosen, the manifest is
`workspaces/<org>/<Family>.yaml` when the project is a member of a family,
else `workspaces/<org>/<project id>.yaml`. `<org>` is the owner segment of the
family holder's or the project's declared `repository:` (`opensoft/openRepoShape`
→ `opensoft`), falling back to the root's `origin` remote and then to `local`
for a checkout that declares no owner at all. `local` therefore appears only
when neither `family.yaml` nor `project.yaml` carries a `repository:` and the
`origin` remote is a filesystem path rather than a hosted URL — a single
repository cloned from a path on the same machine, say. One workspace
repository can
track work across several orgs, and two projects that share an id in different
orgs must never share a file. Any segment outside `[A-Za-z0-9._-]+` is refused
rather than sanitised. The file records branches, commits and a relative
`root` — never an absolute path, because a linked worktree's absolute path is
machine plumbing and `resume` recreates at the *local* `worktree_root`.

`park` never force-pushes. When a previous `resume` has left the branch behind
the remote by this workspace's own parked WIP commits, `park` refuses and
prints the exact `--force-with-lease=<branch>:<recorded parked commit>`
command; `--retire-parked-wip` lets it run that one leased push itself. It is
off by default, and it is the only force-push in this extension.

`resume` **refuses on divergence**: if `origin/<branch>` is not the commit the
manifest recorded, that feature is not recreated and the message names the
parked commit, the current tip and the reconciliation commands. Nothing is
ever reset over commits this workspace did not park. A parked WIP commit is
recognised by three facts together — the `wip: park ` subject prefix, the sha
matching the recorded `parked_commit`, and a single parent on each of the
`wip_depth` tip commits — never by the prefix alone.

Both scripts extend the extension's exit-code convention, which is otherwise
only 0 and 1, because they need a third state:

| Code | Meaning |
|------|---------|
| 0 | Everything asked for was parked / resumed, or there was nothing to do |
| 1 | Usage or environment error: bad flag, not inside a Speckit checkout, `checkout_mode: branch`, an uninitialised leg, no Python 3 |
| 2 | A refusal before anything was done, or every feature was refused |
| 3 | Partial: at least one feature succeeded and at least one was refused |

Both require Python 3: the manifest and the last-worktree state file are
published through it.

**The PowerShell mirror has neither.** `scripts/powershell/*.ps1` are not
shape-aware and gain nothing here: **native Windows parks nothing.** Use the
dev container, or WSL, on Windows.
