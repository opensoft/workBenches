# Independent review — 2026-10-24 (Qwen Code)

## Authority, basis and scope

Brett requested a review and critique of the 1.7 Kimi/GLM specification on
2026-10-24. This is a **read-only documentation review**: no runtime code,
credential, cloud resource, firewall or git state was changed by this reviewer,
and no existing file in this directory was modified.

- Documentation baseline reviewed: `0cf2ce7` on `031-kimi-glm-profile-credentials`
  (working tree clean at time of review).
- This review is performed against the **post-approval** text, i.e. after the
  revisions recorded in [review-2026-10-24.md](review-2026-10-24.md). It is not a
  review of the earlier baseline `c5f39c4`.
- Companion document: [proposed edits](review-2026-10-24-qwen-proposed-edits.md)
  contains drafted wording for the text-level findings.

**Housekeeping:** adding this file and its companion makes this directory hold 16
Markdown documents. The figure "all 14 Markdown documents passed local-link,
code-fence and LF checks" in [analysis.md](analysis.md), and the OpenSpec strict
validation result recorded there, should be re-run before the next approval.

## Method

Every assertion in the eight documents that could be checked against this
worktree's source was checked. **19 claims tested, 19 true.** No false statement
was found in the document set.

Vendor-documentation claims (Kimi CLI 2.3.1 release date, `k3.1-pro` entitlement,
`high` default effort, thinking-cannot-be-disabled, Z.AI Coding Plan versus
standard modes, OpenCode precedence) were **not** independently re-fetched; no
network verification was performed. They are accepted as recorded in
[research.md](research.md) and [review-2026-10-24.md](review-2026-10-24.md). No
test, container or verification command in
[tasks.md](tasks.md) was executed.

## Claim verification

| # | Claim (document) | Evidence | Result |
| --- | --- | --- | --- |
| 1 | Composer covers Claude/OpenAI/Gemini/Grok/GLM, not Kimi (research) | `scripts/compose-ai-profiles.py`: 0 `kimi` matches | true |
| 2 | Recovery adapters cover Claude/Codex/Pi/OmniRoute only (research) | `credential-container/credential_recovery.py`, `scripts/profile_credentials.py`: 0 `kimi`/`glm` | true |
| 3 | GLM dashboard status is guidance, not verification (research) | `apps/credential-manager/credential_manager.py:236` | true |
| 4 | Dashboard auth uses closed stdin (FR-016 premise) | `credential_manager.py:298` `stdin=subprocess.DEVNULL` | true |
| 5 | Tools callback is file-based and noninteractive (research seam) | `tools-container/workbenches_host.py`, `scripts/lib/tools-host-broker.sh` present | true |
| 6 | Sync client reads/hashes/replaces whole credential files (FR-017 premise) | `scripts/credential_sync_client.py`: `read_json`, `digest(downloaded['credential'])`, `atomic` | true |
| 7 | GLM mutates `XDG_CONFIG_HOME`, which company sync uses for discovery (research seam) | `credential_sync_client.py:10`; `scripts/lib/company-profile-sync.sh:6` | true |
| 8 | Broker `mode` already means portable/broker-refresh (FR-019 premise) | `credential-broker/core.py:97,225-227,338` | true |
| 9 | `install-ai-clis.sh` installs `@moonshot-ai/kimi-code@latest` (research) | `base-image/install-ai-clis.sh:283` | true |
| 10 | `provider-profile` supports `pglm`/`pzai` with isolated XDG (research) | `base-image/files/provider-profile:8`, XDG at `:95-98` | true |
| 11 | Kimi profile-home persistence missing from mounts (research) | 0 `kimi` matches in all three mount consumers | true |
| 12 | Constitution remains an unfilled template (plan, analysis) | `.specify/memory/constitution.md`, 35 placeholder markers | true |
| 13 | `.specify/feature.json` points at 018 (quickstart) | `feature_directory: specs/018-clean-sync-benches` | true |
| 14 | "all 14 Markdown documents" (analysis) | exactly 14 `.md` files in scope | true |
| 15 | "all 14 runtime tasks have unique IDs" (analysis) | T000, T001, T002, T002A, T003, T007A, T004, T005, T006, T007, T007B, T008, T009, T010 | true |
| 16 | "FR-001–FR-023 are uniquely defined" (analysis) | 23 requirements, no duplicates | true |
| 17 | "Git whitespace checks passed" (analysis) | `git diff --check HEAD~1 HEAD` clean; no CRLF | true |
| 18 | FR→task matrix covers every requirement (analysis) | 3+3+2+2+3+4+3+3 = 23, no duplicates | true |
| 19 | Quickstart anchor into plan resolves | `plan.md:54` `## Minimum 1.7 retrieval acceptance` | true |

## Premises that are precisely right

Three findings deserve specific credit because they name defects that exist in
current source, not merely plausible risks.

**FR-019 identifies a live hole.** `managed_path()` in
`scripts/credential_sync_client.py:13-21` forbids company publication only for
hardcoded *default* roots — `.claude-profiles`, `.chatgpt-profiles`,
`.opencode-profiles`, `.pi-profiles` and three bare credential paths. Kimi and GLM
appear nowhere in it, and a user-configured custom root is not covered at all.
FR-019's "Personal/default roots, including their configured custom locations,
MUST be excluded" names exactly this gap.

**The `XDG_CONFIG_HOME` seam is a real bug class.** The sync client derives its
control-plane root from `XDG_CONFIG_HOME` (`credential_sync_client.py:10`), and
the GLM launcher rewrites `XDG_CONFIG_HOME` for the vendor child
(`provider-profile:95`). The contract's control-plane rule — resolve workBenches
roots in the parent, apply XDG only to the child, use the same roots and lease
before launch and after login — is the correct fix for a failure that would
otherwise be very hard to diagnose.

**The anti-vacuous-pass design is the strongest part of the revision.** `SC-006`
("Zero enabled recovery modes cannot pass it"), `FR-021`, and T010's
per-milestone recording close off the most common way a credential feature ships
hollow: every remote mode disabled, fixtures green, release notes implying
support. Separating projection `fingerprint` from backing-file revision so that
"unrelated provider edits do not become GLM publications" is a subtle and correct
insight, and `T006 is not an M2 prerequisite` correctly decouples the milestones.

## Findings

Severity: **blocker** prevents a milestone completing as written; **major** risks
a wrong or unenforceable outcome; **minor** is a text or coordination defect.

### F1 — M1's required-task list omits T000 (major)

`tasks.md` "Dependencies and milestone completion" states M1 requires
`T001/T002/T002A/T003/T007A`. But the same section states "T000 precedes
dependent implementation/enablement", and `analysis.md` maps FR-005/FR-020 to
`T000, T001, T002, T003` and FR-013/FR-014/FR-018 to `T000, T002, T007A, T007`.
Three M1 requirements are therefore partly T000-owned while M1 can be declared
complete without T000. Either add T000's M1-scoped rows to the M1 list, or state
explicitly which subset of T000 M1 requires.

### F2 — T007 is tagged `[US1]` but delivers US3 (minor)

T007's text is "Extend M1 UI with qualified **personal recovery** actions", which
is US3 ("Recover only the chosen credential"). T004 and T005 correctly carry
`[US3]`. As tagged, the recovery UI traces only to US1, so a US3 coverage check
would not surface it.

### F3 — FR-013 never received the effort correction (major)

`spec.md:69` still reads "with thinking enabled and effort `max`".
`review-2026-10-24.md:34` assigns that correction to "FR-013, FR-022", and it was
applied to FR-022 (`spec.md:78`), `plan.md` (UI/model bullet), the contract's
"Bound verification and model observations" section, `research.md:21`, and
quickstart step 5 — but not to FR-013. FR-013 is now the only place implying
`max` is the starting state rather than something explicitly configured against a
`high` vendor default.

Secondarily, `research.md` records that thinking **cannot** be disabled, so
FR-013's "with thinking enabled" is a vendor constant, not one of the "existing
choices" the same sentence promises to preserve.

### F4 — 031↔032 circular dependency; T003 is unexecutable here (blocker)

T003 lists `scripts/setup_harnesses.py` and `scripts/setup_harness_targets.py`.
Both are **absent from this worktree** and present only in
`032-managed-cli-harnesses`. Feature 032 is stacked *on top of* 031 (032 contains
`c5f39c4`), so an M1 task in 031 requires code from a branch built on 031.

The dependency is acknowledged — quickstart ("Integrate current 1.7/032
interfaces before dependent work"), `plan.md:11`, `plan.md:100`, `plan.md:114`
("T003 owns mount/032 compatibility") and FR-020 — but never *sequenced*. Neither
document states which feature lands first, and no option exists under which T003
can be completed in this worktree today.

Two resolutions, either acceptable: land 032 first and rebase 031 onto it; or
split T003 so its mount/persistence half stays in M1 and its
installer-identity half moves to a task gated on 032.

Note also that neither 031 nor its own baseline 029 (`b8b1607`) is contained in
`origin/release/1.7.0` (`ccc9eac`), so "Target: workBenches 1.7" depends on a
three-deep stack of unmerged branches landing in order.

### F5 — T010's exact-head guard uses three unguarded variables (major)

T010's verify command passes `"$WORKBENCHES_17_RELEASE_RUN"`,
`"$WORKBENCHES_17_RELEASE_SHA"` and `"$WORKBENCHES_031_MILESTONE"`. If any is
unset it expands to an empty string. T008 requires "nonempty minimum M2 live
cases rather than accepting any green run ID" — the right intent — but rejecting
empty or placeholder *arguments* is nowhere stated, and
`devcontainer.test/test-kimi-glm-release-contract.py` is a T008 output that does
not yet exist. The guard's correctness is delegated to an unwritten script's
default behaviour. The earlier revision of this task list explicitly warned
against "a placeholder environment variable"; that warning was dropped.

### F6 — `research.md:12` understates GLM persistence scope (minor)

That row reads "Standard Kimi profile-home persistence is missing" and groups all
three mount consumers. Measured matches: `docker-compose.mounts.yml` has **0 kimi
and 0 glm**; `scripts/wave-container-shell.sh` has 9 glm and 0 kimi;
`scripts/setup-bench-home.py` has 1 glm and 0 kimi. The Compose reference template
persists **neither** provider. FR-005 and T003 do cover both, so this is not a
requirement gap — but the research table will cause T003's GLM portion to be
underestimated at planning time.

### F7 — Two capability registries, authority unstated (major)

T000 creates `config/provider-credential-capabilities.json`. Meanwhile
`config/setup-tool-catalog.json:1518` already defines a `kimi_code` row with
`access='api unknown'`, `type='frontier unknown'`, `native='llm video unknown'`,
`via='unknown'`. `research.md` asks for "one capability registry rather than
differently interpreted mode strings" — the right instinct — but no document says
how the new registry relates to the catalog's `access` field.

FR-014 freezes harness classification, so `access='api unknown'` will remain
while the capability registry declares concrete API-key modes. Two files will then
answer "is Kimi API-key access available?" differently. Name the authority.

### F8 — `docs/release-1.7.0.md` is edited by both 031 and 032 (minor)

031's T009 and T010 both list it; 032's task list lists it once. Both branches are
unmerged and stacked, so a conflict in release notes is effectively guaranteed.
Agreeing section ownership now is cheaper than resolving it at merge time.

### F9 — M2's live rows need provider accounts nobody owns (minor)

`SC-006` and `plan.md` do define the fallback — "Record M1 as local-only and defer
M2 explicitly rather than passing with an empty enabled set" — so this will not
ambush the release. But no task owns procuring authorized disposable Kimi
Platform and Z.AI Coding Plan accounts across native Linux and WSL, which the
required M2 rows demand. It is an unowned external dependency on M2's critical
path.

## Summary

| ID | Finding | Severity | Kind |
| --- | --- | --- | --- |
| F1 | M1 task list omits T000 | major | text |
| F2 | T007 tagged US1, delivers US3 | minor | text |
| F3 | FR-013 missing the effort correction | major | text |
| F4 | 031↔032 cycle; T003 unexecutable | blocker | decision |
| F5 | T010 guard depends on unset variables | major | text |
| F6 | research understates GLM mount work | minor | text |
| F7 | capability registry authority unstated | major | text |
| F8 | release notes edited by two branches | minor | coordination |
| F9 | provider test accounts unowned | minor | coordination |

No design flaws were found. F4 is the only blocker and it is a branch-topology
decision rather than a specification defect. F1, F2, F3, F5, F6 and F7 are text
edits; drafted wording for each is in the
[companion document](review-2026-10-24-qwen-proposed-edits.md). F8 and F9 are
coordination notes for `plan.md`.

## Not covered by this review

- Vendor documentation, model defaults, CLI release dates and entitlement
  behaviour were not independently verified (no network checks performed).
- No verification command, fixture or container was executed; all runtime tasks
  remain unimplemented and this review asserts nothing about their future results.
- `openspec/changes/add-kimi-glm-profile-credentials/specs/provider-profile-credentials/spec.md`
  and `design.md` were not compared line-by-line against `spec.md` for delta
  consistency.
- Feature 032's own specification was not reviewed; it is referenced only where
  031 depends on it.
