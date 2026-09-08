---
name: speckit-git-validate
description: Validate current branch follows feature branch naming conventions
compatibility: Requires spec-kit project structure with .specify/ directory
metadata:
  author: github-spec-kit
  source: git:commands/speckit.git.validate.md
---
<!-- speckit-overlay-shape: 1 -->

# Validate Feature Branch

Validate that the current Git branch follows the expected feature branch naming conventions.

## Prerequisites

- Check if Git is available by running `git rev-parse --is-inside-work-tree 2>/dev/null`
- If Git is not available, output a warning and skip validation:
  ```
  [specify] Warning: Git repository not detected; skipped branch validation
  ```

## Repository Shape

Resolve the shape before validating anything.

- **Single repository**: the branch to validate is the current checkout's branch (`git rev-parse --abbrev-ref HEAD`), and `.specify/feature.json` is read from that checkout.
- **Three-leg project** (the project root has `project.yaml` with `kind: project-manifest` and `legs:` for `role: spec` and `role: code`): the assembly root has **no** feature branch, so validating its branch is meaningless. Validate the two **leg worktree** branches instead.

In a three-leg project:

1. Resolve the feature from `SPECIFY_FEATURE` / `SPECIFY_FEATURE_DIRECTORY`, or from `.specify/feature.json` at the project root — its `feature_directory` is `worktrees/<NNN-feature-name>/<spec>/specs/<NNN-feature-name>`, relative to the project root. The `speckit.git.feature` hook's JSON carries the same values as `SPEC_WORKTREE_PATH`, `CODE_WORKTREE_PATH`, and `FEATURE_DIR`.
2. Read the branch of each leg worktree with `git -C <SPEC_WORKTREE_PATH> rev-parse --abbrev-ref HEAD` and `git -C <CODE_WORKTREE_PATH> rev-parse --abbrev-ref HEAD`.
3. Both must match the feature-branch patterns below **and** be the same branch name in both legs. Report a mismatch between the legs as an error naming both branches.
4. Do not validate the assembly root's branch and do not report it as a failure; it stays on its tracking branch until the pin bump.

## Validation Rules

Get the current branch name:

```bash
git rev-parse --abbrev-ref HEAD
```

Validate only the branch name's final path segment. Namespace segments before the final `/` do not participate in feature-marker validation.

The final segment must start with one of these patterns:

1. **Sequential**: `^[0-9]{3,}-.+` (e.g., `001-feature-name`, `042-fix-bug`, `feature/1000-big-feature`)
2. **Timestamp**: `^[0-9]{8}-[0-9]{6}-.+` (e.g., `20260319-143022-feature-name`, `release/20260319-143022-feature-name`)

## Execution

If on a feature branch (matches either pattern):
- Output: `✓ On feature branch: <branch-name>`
- Resolve the spec directory using this order:
  1. If `.specify/feature.json` exists, parse its `feature_directory` value and treat that mapping as authoritative. Resolve a relative value from the repository root. Do not infer a different directory from the branch name when this file is present.
  2. If `.specify/feature.json` is absent, fall back to the feature marker from the branch's final path segment and look for `specs/<prefix>-*`.
- If `.specify/feature.json` exists but cannot be parsed, lacks `feature_directory`, or points to a missing directory, report that state error instead of falling back to a branch-derived path.
- If spec directory exists: `✓ Spec directory found: <path>`
- If spec directory missing: `⚠ No spec directory found for prefix <prefix>`

If NOT on a feature branch:
- Output: `✗ Not on a feature branch. Current branch: <branch-name>`
- Output: `Feature branches should be named like: 001-feature-name, 20260319-143022-feature-name, or <namespace>/001-feature-name`

In a three-leg project apply the same reporting per leg, using the leg worktree branch instead of the root branch:

- `✓ On feature branch: <branch-name> (spec worktree)` and the same line for the code worktree
- `✗ Leg branches differ: spec=<spec-branch>, code=<code-branch>` when the two legs are not on the same branch
- The spec directory is `FEATURE_DIR` inside the spec worktree (`worktrees/<NNN-feature-name>/<spec>/specs/<NNN-feature-name>`), resolved from `.specify/feature.json` at the project root; do not look for `specs/<prefix>-*` at the root

## Graceful Degradation

If Git is not installed or the directory is not a Git repository:
- Check the `SPECIFY_FEATURE` environment variable as a fallback
- If set, validate its final path segment against the naming patterns
- If not set, skip validation with a warning
