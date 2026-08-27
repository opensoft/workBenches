---
description: "Validate current branch follows feature branch naming conventions"
---

# Validate Feature Branch

Validate that the current Git branch follows the expected feature branch naming conventions.

## Prerequisites

- Check if Git is available by running `git rev-parse --is-inside-work-tree 2>/dev/null`
- If Git is not available, output a warning and skip validation:
  ```
  [specify] Warning: Git repository not detected; skipped branch validation
  ```

## Validation Rules

Get the current branch name:

```bash
git rev-parse --abbrev-ref HEAD
```

Validate only the branch name's final path segment. Namespace segments before the final `/` do not participate in feature-marker validation.

The final segment must start with one of these patterns:

1. **Sequential**: `^[0-9]{3,}-` (e.g., `001-feature-name`, `042-fix-bug`, `feature/1000-big-feature`)
2. **Timestamp**: `^[0-9]{8}-[0-9]{6}-` (e.g., `20260319-143022-feature-name`, `release/20260319-143022-feature-name`)

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

## Graceful Degradation

If Git is not installed or the directory is not a Git repository:
- Check the `SPECIFY_FEATURE` environment variable as a fallback
- If set, validate its final path segment against the naming patterns
- If not set, skip validation with a warning
