---
description: "Create a feature branch or worktree with sequential or timestamp numbering"
---

# Create Feature Checkout

Create a new git feature checkout for the given specification. Depending on git extension config, this command either switches the current checkout to a new feature branch or creates a linked worktree from a configured base branch. This command handles **git checkout creation only** — the spec directory and files are created by the core `/speckit.specify` workflow.

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Environment Variable Override

If the user explicitly provided `GIT_BRANCH_NAME` (e.g., via environment variable, argument, or in their request), pass it through to the script by setting the `GIT_BRANCH_NAME` environment variable before invoking the script. When `GIT_BRANCH_NAME` is set:
- The script uses the exact value as the branch name, bypassing all prefix/suffix generation
- `--short-name`, `--number`, and `--timestamp` flags are ignored
- `FEATURE_NUM` is extracted from the name if it starts with a numeric prefix, otherwise set to the full branch name

## Prerequisites

- Verify Git is available by running `git rev-parse --is-inside-work-tree 2>/dev/null`
- If Git is not available, warn the user and skip branch creation

## Repository Shape

The script resolves the project shape itself and reports it as `REPO_SHAPE`.

- **Single repository** (`REPO_SHAPE: "single"`): one feature branch, and in worktree mode one linked worktree under `worktree_root`.
- **Three-leg project** (`REPO_SHAPE: "three-leg"` — an openRepoShape assembly root whose `project.yaml` declares `legs:` for `role: spec` and `role: code`): the same `NNN-feature-name` branch is created in **both** leg repositories and one linked worktree is added per leg at `worktrees/<NNN-feature-name>/<spec>/` and `worktrees/<NNN-feature-name>/<code>/`. The assembly root never receives a feature branch or a worktree. The script writes `.specify/feature.json` **at the project root**, pointing at `worktrees/<NNN-feature-name>/<spec>/specs/<NNN-feature-name>`.

In a three-leg project:

- Run the script from the project root (the directory holding `.specify/`).
- `checkout_mode` must be `worktree`; `branch` is refused with an error naming `checkout_mode` in `.specify/extensions/git/git-config.yml`.
- Both legs must be initialised checkouts; otherwise the script refuses and names `git submodule update --init` / `make bootstrap`.
- Feature numbering scans `specs/` on the spec leg's base branch and working tree, plus the branch lists of both leg repositories.
- Each leg's branch is cut from `origin/<base_branch>` after a best-effort fetch, falling back to the local base branch when offline.

## Branch Numbering Mode

Determine the branch numbering strategy by checking configuration in this order:

1. Check `.specify/extensions/git/git-config.yml` for `branch_numbering` value
2. Check `.specify/init-options.json` for `branch_numbering` value (backward compatibility)
3. Default to `sequential` if neither exists

## Checkout Mode

Read `.specify/extensions/git/git-config.yml` for:

- `checkout_mode`: `branch` or `worktree`
- `base_branch`: branch to fork from when using worktree mode
- `worktree_root`: parent directory for linked worktrees

The script also honors these temporary environment overrides when present:

- `SPECKIT_GIT_CHECKOUT_MODE`
- `SPECKIT_GIT_BASE_BRANCH`
- `SPECKIT_GIT_WORKTREE_ROOT`

## Execution

Generate a concise short name (2-4 words) for the branch:
- Analyze the feature description and extract the most meaningful keywords
- Use action-noun format when possible (e.g., "add-user-auth", "fix-payment-bug")
- Preserve technical terms and acronyms (OAuth2, API, JWT, etc.)

Run the appropriate script based on your platform:

- **Bash**: `.specify/extensions/git/scripts/bash/create-new-feature.sh --json --short-name "<short-name>" "<feature description>"`
- **Bash (timestamp)**: `.specify/extensions/git/scripts/bash/create-new-feature.sh --json --timestamp --short-name "<short-name>" "<feature description>"`
- **PowerShell**: `.specify/extensions/git/scripts/powershell/create-new-feature.ps1 -Json -ShortName "<short-name>" "<feature description>"`
- **PowerShell (timestamp)**: `.specify/extensions/git/scripts/powershell/create-new-feature.ps1 -Json -Timestamp -ShortName "<short-name>" "<feature description>"`

**IMPORTANT**:
- Do NOT pass `--number` — the script determines the correct next number automatically
- Always include the JSON flag (`--json` for Bash, `-Json` for PowerShell) so the output can be parsed reliably
- You must only ever run this script once per feature
- The JSON output will always contain `BRANCH_NAME`, `FEATURE_NUM`, and `CHECKOUT_MODE`
- In worktree mode the JSON output also contains `BASE_BRANCH` and `WORKTREE_PATH`
- In a three-leg project the JSON also contains `REPO_SHAPE`, `PROJECT_ROOT`, `SPEC_WORKTREE_PATH`, `CODE_WORKTREE_PATH`, and `FEATURE_DIR`; there `WORKTREE_PATH` is the feature directory that holds both leg worktrees

## Graceful Degradation

If Git is not installed or the current directory is not a Git repository:
- Checkout creation is skipped with a warning: `[specify] Warning: Git repository not detected; skipped {branch|worktree} creation`
- The script still outputs `BRANCH_NAME`, `FEATURE_NUM`, and `CHECKOUT_MODE` so the caller can reference them

## Output

The script outputs JSON with:
- `BRANCH_NAME`: The branch name (e.g., `003-user-auth` or `20260319-143022-user-auth`)
- `FEATURE_NUM`: The numeric or timestamp prefix used
- `CHECKOUT_MODE`: `branch` or `worktree`
- `BASE_BRANCH`: the configured worktree base branch when `CHECKOUT_MODE=worktree`
- `WORKTREE_PATH`: the linked worktree root when `CHECKOUT_MODE=worktree`
- `REPO_SHAPE`: `single` or `three-leg`
- `PROJECT_ROOT`: the project root that holds `.specify/` (three-leg only)
- `SPEC_WORKTREE_PATH`: the spec leg worktree `worktrees/<NNN-feature-name>/<spec>/` (three-leg only)
- `CODE_WORKTREE_PATH`: the code leg worktree `worktrees/<NNN-feature-name>/<code>/` (three-leg only)
- `FEATURE_DIR`: the Speckit feature directory `<spec worktree>/specs/<NNN-feature-name>` (three-leg only)
