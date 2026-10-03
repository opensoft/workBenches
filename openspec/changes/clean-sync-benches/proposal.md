# Proposal

## Why

Ten bench repositories contain uncommitted shell-history fixes, one contains an Android SDK installer adjustment, and local Git metadata contains divergent or namespace-dependent references. Preserve this work and land reviewed fixes so the retained checkouts are clean and synchronized without disrupting live benches.

## What Changes

- Finish the existing history-directory mount fixes in ten child repositories.
- Review the Flutter SDK timeout/retry adjustment independently.
- Preserve CloudBench temporary evidence in a protected host-local recovery directory.
- Reconcile patch-equivalent branch history, protect open-PR worktrees, and land parent submodule pins only after child merges.
- Upgrade Frappe independently after protected database/site backups; the user approved the backed-up upgrade on 2026-10-02.

## Capabilities

### New Capabilities

- `persistent-shell-history`: benchmark shells use a regular history file within a persistent directory volume.

### Modified Capabilities

None. Cleanup does not change launcher, lane, profile, or review policy.

## Impact

Affected child repositories: cppBench, dotNetBench, goBench, javaBench, pyBench, rustBench, phpBench, flutterBench, opsBench, and cloudBench, plus Frappe's local application repositories and sites. The parent records merged submodule pins. Implementation and verification are owned by `specs/018-clean-sync-benches/`; local recovery evidence is never committed. No unrelated container restart, image activation, credential change, or unrelated open-PR merge is included. Approved Frappe maintenance remains gated on verified backups.
