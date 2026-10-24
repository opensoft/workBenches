# Proposed edits — findings F1–F9 (Qwen Code, 2026-10-24)

Companion to [the review](review-2026-10-24-qwen.md). Drafted wording only.
**No file in this directory was modified to produce this document**; apply,
adapt or discard at your discretion. Baseline `0cf2ce7`.

Quoted "current" text is verbatim from the baseline. Line numbers are from that
commit and will drift.

## F1 — add T000 to the M1 requirement list

`tasks.md`, section "Dependencies and milestone completion".

Current:

```text
T008–T010 operate per selected milestone: M1 requires
T001/T002/T002A/T003/T007A; M2 additionally requires T004/T005/T007;
M3 additionally requires T006/T007B and company acceptance.
```

Proposed:

```text
T008–T010 operate per selected milestone: M1 requires the M1-scoped rows of
T000 plus T001/T002/T002A/T003/T007A; M2 additionally requires the M2-scoped
rows of T000 and T004/T005/T007; M3 additionally requires the M3-scoped rows
of T000 and T006/T007B and company acceptance.
```

If T000 is intended to be indivisible, the simpler alternative is to list it
once and state that no milestone may be accepted while it is open:

```text
T000 is a prerequisite for every milestone; no milestone is accepted while it
remains open. M1 requires T000/T001/T002/T002A/T003/T007A; ...
```

Also worth adding a scoping column or per-milestone sub-rows to T000 itself,
since it currently owns qualification for FR-001, FR-005, FR-006, FR-007,
FR-010–FR-013, FR-018 and FR-020 across all three milestones.

## F2 — retag T007

`tasks.md`, task T007.

Current:

```text
- [ ] T007 [US1] [O] Extend M1 UI with qualified personal recovery actions and ...
```

Proposed:

```text
- [ ] T007 [US1] [US3] [O] Extend M1 UI with qualified personal recovery actions and ...
```

Check first whether your task grammar permits more than one US tag. If it does
not, retag T007 as `[US3]` alone and move the model-observation clause
("explicitly configure/verify K3.1 Pro max and thinking, resolve native
IDs/aliases, detect substitution") into T007A, which already carries `[US1]` and
owns the M1 model surface. Do not leave recovery UI traceable only to US1.

## F3 — correct FR-013

`spec.md:69`.

Current:

```text
- **FR-013**: Keep Kimi client version, model ID, reasoning effort and account entitlement separate. Initial compatibility testing targets CLI 2.3.1 and `k3.1-pro`, with thinking enabled and effort `max`; preserve existing choices and offer only entitled models. An unavailable request is explicit, with no silent model substitution. Model changes start a new session.
```

Proposed:

```text
- **FR-013**: Keep Kimi client version, model ID, reasoning effort and account entitlement separate. Initial compatibility testing targets CLI 2.3.1 and `k3.1-pro`. Thinking cannot be disabled on that model and the vendor default effort is `high` (observed 2026-10-24), so a requested `max` MUST be configured and verified explicitly rather than assumed; neither is a user choice to preserve. Preserve user-selected models where entitlement allows and offer only entitled models. An unavailable request is explicit, with no silent model substitution. Model changes start a new session.
```

This aligns FR-013 with FR-022, the contract's "Bound verification and model
observations" section, `research.md:21`, the `plan.md` UI/model bullet and
quickstart step 5, all of which already carry the correction.

## F5 — make the release-contract check fail closed

`tasks.md`, task T008. Append to the existing sentence ending "...rather than
accepting any green run ID."

Proposed addition:

```text
The release-contract check MUST fail closed when WORKBENCHES_17_RELEASE_RUN,
WORKBENCHES_17_RELEASE_SHA or WORKBENCHES_031_MILESTONE is unset, empty or a
placeholder, and MUST reject a run whose repository, head SHA, trusted workflow
or milestone does not match the expected value for the milestone under review.
An empty argument is a failure, not a wildcard.
```

Optionally restore the warning that the pre-approval task list carried and that
was dropped in the revision:

```text
Do not merge or publish based on a fixture report or a placeholder environment
variable.
```

## F6 — state GLM's mount gap accurately

`research.md:12`, table row.

Current:

```text
| `scripts/setup-bench-home.py`, `scripts/wave-container-shell.sh`, `docker-compose.mounts.yml` | Standard Kimi profile-home persistence is missing; update actual mount generation as well as the reference template. |
```

Proposed:

```text
| `scripts/setup-bench-home.py`, `scripts/wave-container-shell.sh`, `docker-compose.mounts.yml` | Kimi profile-home persistence is absent from all three. GLM is only partially present — 9 references in `wave-container-shell.sh` and 1 in `setup-bench-home.py`, none in the `docker-compose.mounts.yml` reference template — so FR-005's GLM work is not zero. Update actual mount generation and the reference template for both providers. |
```

## F7 — declare one authority for provider capability

Two coordinated additions.

`spec.md`, appended to FR-014:

```text
`config/provider-credential-capabilities.json` is authoritative for credential
authentication modes and per-operation eligibility. `config/setup-tool-catalog.json`
remains authoritative for Harness installation and classification only; an
`access` value of `api unknown` on the existing `kimi_code` row is not a
credential-capability statement and MUST NOT be read as one. Where the two
disagree on whether a mode is available, the capability registry governs and the
catalog row is left unchanged.
```

`contracts/provider-credentials.md`, appended to "Typed binding and policy":

```text
The capability registry is the single source of truth for the four
authentication modes and their per-operation eligibility. Harness catalog rows
describe installation and classification and are never consulted for credential
eligibility; adding a mode does not modify a catalog row.
```

This also discharges `research.md`'s "one capability registry rather than
differently interpreted mode strings", which currently has no normative home.

## F4 — decision required, not wording

`plan.md` "Dependencies and delivery milestones" and quickstart both say to
reconcile feature 032 first, but 032 is stacked on 031 and T003 lists
`scripts/setup_harnesses.py` and `scripts/setup_harness_targets.py`, which exist
only in the 032 worktree. Pick one and record it in `plan.md`:

Option A — sequence the branches:

```text
Feature 032 lands in 1.7 before 031. 031 is rebased onto merged 032 before any
T003 work begins; T003 consumes 032's installer identity/readiness contract as
shipped, not as specified.
```

Option B — split T003:

```text
T003 covers Kimi/GLM home persistence in Wave/devcontainer/Compose paths only and
stays in M1. Installer identity, package/version resolution, PATH shadowing,
update/rollback drift and vendor auto-install ownership move to a new T003A gated
on feature 032 and excluded from M1 acceptance.
```

Option B keeps M1 deliverable without 032 and is the lower-risk choice, at the
cost of one more task and a re-cut of FR-020's task ownership in `analysis.md`.

Either way, record that `origin/release/1.7.0` currently contains neither 031 nor
its 029 baseline, so the 1.7 target depends on a three-deep unmerged stack.

## F8 — pre-agree release-notes ownership

`plan.md`, "Implementation owners and validation".

```text
`docs/release-1.7.0.md` is edited by both 031 (T009, T010) and feature 032. 031
owns only the "Kimi and GLM profile credentials" section; 032 owns the managed
harness sections. Neither feature rewrites the other's section, and both rebase
before release rather than resolving conflicts at merge time.
```

## F9 — assign an owner for provider test accounts

`tasks.md`, T000 or T005.

```text
T005 additionally records who procures the authorized disposable Kimi Platform
and Z.AI Coding Plan accounts required by the plan's minimum M2 rows, on each
claimed platform, before attended acceptance is scheduled. If no owner or account
exists, M2 is deferred explicitly under SC-006 rather than left unstarted.
```

`SC-006` and `plan.md` already define the deferral path, so this only closes the
ownership gap; it does not change any acceptance threshold.

## Suggested application order

1. F4 — it is the blocker and may re-cut T003 and the `analysis.md` matrix.
2. F1, F3, F5, F7 — substantive requirement wording.
3. F2, F6, F8, F9 — traceability, accuracy and coordination.
4. Re-run documentation validation and update the document count and OpenSpec
   result in `analysis.md`, which now must account for 16 Markdown files.
