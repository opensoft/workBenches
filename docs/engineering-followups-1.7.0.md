# v1.7.0 engineering follow-ups

**Created**: 2026-10-24
**Provenance**: derived from the read-only review of feature 031 (Kimi and GLM
profile credentials) at baseline `0cf2ce7`. See
[the review record](../specs/031-kimi-glm-profile-credentials/review-2026-10-24-qwen.md)
and its
[proposed spec edits](../specs/031-kimi-glm-profile-credentials/review-2026-10-24-qwen-proposed-edits.md).
**Status**: proposed; no work started, nothing here is implemented.

## Why this file is separate from release-1.7.0.md

[release-1.7.0.md](release-1.7.0.md) is user-facing release notes — device
registration, directional SSH trust, the guided setup wizard and the planned
Kimi/GLM credentials. It is also co-owned by features 031 and 032, which is
recorded as finding F8 and is not yet resolved. The items below are
engineering-process and cross-cutting structural work, so they are tracked here
to avoid both a category error and a predictable merge conflict.

## Scope rule

Items the review ranked **High value** are targeted at 1.7.0 and listed here.
Everything else — Medium value, housekeeping, and the one High-value item that
depends on 031 landing first — is deferred to
[engineering-followups-1.7.1.md](engineering-followups-1.7.1.md). That deferral
is deliberate and is called out in EF-08 so it can be overridden.

All effort and value ratings are the reviewer's judgement, not estimates from the
implementation owners. Every evidence citation below was verified against source
in the 031 worktree on 2026-10-24.

## EF-01 — Fill in the project constitution

**Value: High · Effort: Low · Owner: unassigned**

`.specify/memory/constitution.md` is still the unfilled scaffold template,
containing 35 placeholder markers. Three separate feature-031 documents
nevertheless defer to it as authority:

- `plan.md` — "The constitution remains a template; global workflow and these
  concrete gates apply."
- `analysis.md` — "The constitution remains a template; global rules and the
  plan's concrete invariants apply."
- The pre-approval plan's "Governed invariants" section.

Meanwhile each spec re-derives the same rules by hand: no secrets in diagnostics,
owner-only paths, backward-compatible manifests, fixture evidence separated from
attended live acceptance, no provider requests from rendering, and a per-feature
governed-area list.

**Proposed change**: write the constitution once, capturing the invariants that
already recur across specs 026, 027, 029, 031 and 032, plus the global workflow
rules the documents keep referring to. Then let each `plan.md` cite it instead of
restating it.

**Done when**: the template markers are gone; at least one existing spec's
"governed invariants" section is replaced by a citation; and a new spec can be
written without inventing its own invariant list.

**Why 1.7.0**: it is the cheapest item here and it reduces divergence in every
spec written afterwards, including the 031 implementation work still ahead.

## EF-02 — Define a branch-stacking and integration-order policy for 1.7

**Value: High · Effort: Low · Owner: unassigned**

Current topology, verified on 2026-10-24 — none of it merged:

```text
origin/release/1.7.0  ccc9eac   Merge pull request #203 (fix/1.7-qa-engine-budget)
  └── 029-setup-guided-wizard            b8b1607   not contained in release/1.7.0
        └── 031-kimi-glm-profile-credentials  0cf2ce7
              └── 032-managed-cli-harnesses    00f3e62
```

Consequences already observed:

- Feature 031's task **T003 lists `scripts/setup_harnesses.py` and
  `scripts/setup_harness_targets.py`, which exist only in the 032 worktree.** An
  M1 task in 031 therefore depends on code from a branch stacked on top of it.
  This is finding F4, the review's only blocker.
- Neither 031 nor its own 029 baseline is contained in `origin/release/1.7.0`, so
  "Target: workBenches 1.7" depends on a three-deep unmerged stack landing in
  order.
- 031's `plan.md`, `quickstart.md` and FR-020 all say to reconcile 032's
  installer interface first, but no document states which feature lands first.

**Proposed change**: record an explicit integration order for the 1.7 line, and a
rule that a downstream branch must not be a build dependency of its own upstream.
Resolve F4 by either (A) landing 032 first and rebasing 031 onto it, or (B)
splitting T003 so mount/persistence stays in M1 and installer-identity work moves
to a new T003A gated on 032. Option B keeps M1 deliverable and is the lower-risk
choice; wording for both is in the
[proposed-edits document](../specs/031-kimi-glm-profile-credentials/review-2026-10-24-qwen-proposed-edits.md).

**Done when**: the order is written down, F4 is resolved by one of the two
options, and no task in any 1.7 feature lists a file that does not exist in its
own worktree.

## EF-03 — Codify spec-directory ownership across stacked worktrees

**Value: High · Effort: Low · Owner: unassigned**

Because specifications live inside the repository, every worktree carries a full
copy of every spec directory. During this review the following state was
observed:

- The 031 worktree held the approved 2026-10-24 revisions as **uncommitted**
  working-tree edits to `spec.md`, `plan.md`, `tasks.md` and
  `contracts/provider-credentials.md` — 288 insertions, 94 deletions.
- The 032 worktree, stacked on 031, held the **older committed** copies of the
  same four files in a clean tree.

The only copy of the approved revision was therefore uncommitted, in one
worktree, one `git checkout` from being lost while a downstream branch silently
carried the pre-review text. It has since been committed as `0cf2ce7`, so the
immediate exposure is closed, but the class of hazard is not.

Credit where due: 032 behaved correctly. `git log c5f39c4..HEAD --
specs/031-kimi-glm-profile-credentials/` in the 032 worktree is empty, meaning
032 never committed changes to another feature's spec directory. The discipline
exists; it is simply unwritten.

**Proposed change**: make it explicit — a feature branch may *read* another
feature's spec directory but must never *edit* it; spec revisions happen only in
the owning branch. Pair with a habit of committing spec revisions before starting
a downstream branch.

**Done when**: the rule is recorded (the constitution from EF-01 is the natural
home) and stacked branches are checked for foreign spec edits before merge.

## EF-04 — Build interactive terminal handoff as a provider-agnostic Tools capability

**Value: High · Effort: Medium · Owner: unassigned**

Feature 031's FR-016 and task T002A exist because the dashboard cannot host an
interactive TUI. Verified in source:

- `apps/credential-manager/credential_manager.py:298` launches with
  `stdin=subprocess.DEVNULL`.
- `tools-container/workbenches_host.py` and `scripts/lib/tools-host-broker.sh`
  implement a file-based, noninteractive callback.

That is a property of the Tools/dashboard transport, not of Kimi. Every future
provider using device-code, OAuth or any TUI login will hit the same wall, and
the hard part — keeping secret input and terminal transcripts out of logs and RPC
arguments — would be reimplemented each time.

**Proposed change**: implement "interactive session handoff" once in
`tools-container/` plus `tools-host-broker.sh`, with cancellation, bounded
process cleanup, completion detection, saved UI/queue-state return and
secret-transcript exclusion as generic guarantees. Kimi becomes its first caller
rather than its only one. FR-016's requirement that direct-terminal and
wizard/dashboard login have separate acceptance should be preserved as a property
of the generic capability.

**Done when**: T002A is implemented against the shared capability, and a second
provider could adopt it without new transport work.

**Why 1.7.0**: this must be decided *before* T002A is built. Retro-fitting a
generic transport underneath a Kimi-specific implementation is materially more
expensive than shaping it correctly the first time.

## Relationship to feature 031's own findings

The nine findings from the review (F1–F9) are **not** duplicated here; they are
tracked in the
[review record](../specs/031-kimi-glm-profile-credentials/review-2026-10-24-qwen.md)
with drafted wording in the
[proposed-edits document](../specs/031-kimi-glm-profile-credentials/review-2026-10-24-qwen-proposed-edits.md).
They belong to feature 031 and land with it. Two touchpoints matter for 1.7.0
sequencing:

- **F4** is the blocker that EF-02 exists to resolve.
- **F8** (`docs/release-1.7.0.md` edited by both 031 and 032) is the reason this
  file exists separately. If F8 is resolved by agreeing section ownership, these
  items may be merged into `release-1.7.0.md` and this file retired.

## Deferred to 1.7.1

EF-05 through EF-11, including the High-value provider capability registry
(EF-08), are recorded in
[engineering-followups-1.7.1.md](engineering-followups-1.7.1.md).
