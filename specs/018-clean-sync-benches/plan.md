# Implementation Plan

1. Save protected recovery patches, untracked archives, refs, and a parent bundle; audit current remotes and ownership.
2. Prepare existing history changes in child feature worktrees, validate all affected configurations, commit, push, and request exact-head Codex reviews.
3. Independently validate and review the Flutter SDK timeout/retry change; increment its version header.
4. Verify and preserve CloudBench temporary evidence outside Git; move only unchanged, inactive material.
5. Reconcile the old patch-equivalent profile branch with its remote without force-pushing; preserve four open feature PR worktrees and repair proven namespace-only metadata issues.
6. Merge ready child PRs only after required checks and unresolved findings are cleared. Synchronize original child checkouts only when their edits still match the captured patches, then land reviewed parent pin updates.
7. Perform the user-approved Frappe upgrade only after verified database/site backups; stop before changing application code if backups cannot be taken.
8. Refresh every remote and report cleanliness, upstream differences, pins, review gates, and recovery location. Recovery consists of the protected starting bundle, patches, and untracked archives.

Use the declared bench for validation and WSL-native Git for host checkout operations. Do not initialize unrelated submodules or modify the active no-lane feature.
