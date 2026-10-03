# Design

## Context

See proposal.md. The audit found eighteen repositories, ten dirty children, eight registered submodules, three clean but outdated Frappe application checkouts, and four open parent feature PRs. User approval covers the cleanup plan, not interruption of running workloads.

## Goals / Non-Goals

**Goals:** preserve every existing change, validate before landing, keep active work recoverable, and synchronize retained branches and parent pins with explicitly verified remotes.

**Non-Goals:** restart unrelated benches, activate rebuilt images, rewrite remote branch history, discard temporary evidence, or merge unrelated active features. The user approved a backed-up Frappe upgrade on 2026-10-02; database/site backups must precede any application update or migration.

## Decisions

- Store binary patches, untracked-file archives, branch tips, and a parent Git bundle in a mode-0700 host-local recovery directory. This is more durable than relying on a stash.
- Prepare existing child fixes in linked worktrees cut from their fetched default branches, keeping original checkout edits until landing is proven.
- Validate devcontainer parsing plus service-level Compose history environment inside the declared bench using existing tooling. Compose owns the single history volume mount and startup ownership initializer, so plain Compose and Dev Container starts both make fresh or root-owned history directories/files writable by the runtime user. Duplicate Dev Container mounts are removed. Disposable isolated containers verify the actual resolved startup command and persistence; declared live services are never launched as a configuration-validation side effect.
- Keep Flutter SDK changes separate from history changes; increment any required version header.
- Pin history engine names to the existing Docker volumes observed during the audit, including PyBench's active history-directory volume. `WORKBENCH_HISTORY_VOLUME` permits selecting a legacy engine name without deleting or overwriting either volume. Verify both default and override resolution; do not assume a raw Dev Container mount name equals the running engine name.
- Preserve CloudBench temporary evidence outside the repository only after verifying an unchanged archive and checking for active users. Do not publish evidence or secrets.
- Reconcile obsolete patch-equivalent local refs only after a recovery bundle and open-PR checks. Retain active worktrees, including container-path worktrees that merely appear prunable from the host.
- Land children first, then move parent gitlinks through a reviewed parent PR. No force-pushes.
- Restore Frappe's stopped supporting services through declared tooling, verify complete database/site backups, and only then update dependencies/code and migrate the approved local sites. Stop before code changes if backups cannot be taken.

## Risks / Trade-offs

- Concurrent edits can invalidate a captured patch → recheck status and patch equality immediately before moving files or synchronizing a checkout.
- OAuth/SQL evidence can contain secrets → owner-only archives outside Git; inspect metadata rather than printing contents.
- CI/review delays can leave clean main checkouts plus open feature worktrees → report pending review accurately rather than bypass required checks.
- Git metadata uses different host/container paths → verify in both namespaces; repair registration instead of deleting a live worktree.

## Migration Plan

The Speckit plan owns execution order and rollback. Recovery patches and archives preserve the starting state. Container activation remains separate from Git landing.
