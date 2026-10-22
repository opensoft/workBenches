# Specification Analysis Report: Guided setup wizard

**Feature**: `029-setup-guided-wizard` · **Date**: 2026-10-21 · **Command**: `/speckit-analyze` (user-global skill, with category G "Build Tiers")
**Artifacts**: [spec.md](spec.md) (FR-001–FR-060, SC-001–SC-013, US1–US7), [plan.md](plan.md) (`0680f10`), [tasks.md](tasks.md) (45 tasks), [research.md](research.md), [data-model.md](data-model.md), [contracts/](contracts/), [quickstart.md](quickstart.md), [checklists/](checklists/) (361/361), and the OpenSpec change [`setup-guided-wizard`](../../openspec/changes/setup-guided-wizard/) (proposal, design D1–D19, `tasks.md`, four deltas with 45 requirements).
**Setup**: `check-prerequisites.sh --json --require-tasks --include-tasks` with `SPECIFY_FEATURE=029-setup-guided-wizard` resolved `FEATURE_DIR` to this directory. It also rewrote the stale `.specify/feature.json` (018 → 029), which was restored before committing.
**Constitution**: `.specify/memory/constitution.md` is the unfilled Spec Kit template. As in the plan, the principle checks ran against Brett's protocol (`openspec-speckit-workflow.md`) and plan.md's gate table G1–G7.
**Evidence gathered in WSL at `0680f10`**:
- The full existing local suite list passes except `test-setup-services.py`, which fails 3 of 3 runs (see E3).
- `openspec validate setup-guided-wizard --strict` passes.
- PyYAML 6.0.3 and `gh` 2.86.0 are installed; verify commands use both.

**Decisions**: Brett Heap accepted decisions D1–D5 as recommended on 2026-10-21. The statuses below record that.

## Findings

| ID | Category | Severity | Location(s) | Summary | Recommendation | Status |
|----|----------|----------|-------------|---------|----------------|--------|
| E1 | Coverage | HIGH | `README.md` L116–117, L192–193; `docs/credential-recovery.md` L15; plan › Phase 8; OpenSpec 6.1 | Both files still describe the 1.7 screen ("select benches, AI assistants, and tools", "Benches \| AI Assistants \| Tools", "Enter applies the selected changes"). FR-001 requires the step to be named Agents in documentation, and FR-008 changes what Enter does. No task covered either file. | Add a docs task, and list both files in the plan. | **Fixed**: T038; plan.md source list and Phase 8 updated. |
| E2 | Coverage | HIGH | plan › impact table ("none expected" row); `devcontainer.test/test-setup-services.py` L17–60 | `test-setup-services.py` runs in CI's `regression` job and drives the production TUI in a PTY through `test-workstation-acceptance.py`'s `account_setup_replies`, `TUI` and `PROFILES`. The plan lists it as unaffected and moves those helpers only in Phase 7. Phase 5's flow change would therefore break the regression job with no task owning the fix (rule S1). | The tasks that change the flow update the shared helpers and this suite, and run it in their verify. | **Fixed**: T017 (markers `READY`/`STRIP_READY`/`REVIEW`, `→ → ↓ ↓ Space G`, widened `PROFILES`, `CURRENT_SECTION=3`), T018 (Review tail) and marker-conformance tests; plan impact table corrected. |
| E3 | Coverage | HIGH | `devcontainer.test/test-setup-services.py` (embedded script) | On a WSL host the test times out at `0680f10`, in 3 of 3 runs; it passes on the CI Ubuntu runner. The script sets Docker and Tools Up but not the WSL requirement item, so the strip reads `REQUIREMENTS · 2/3 ready` and the wait never matches. The build lane runs in WSL, so every verify that includes this suite would fail however good the work. | Stub the WSL item before anything else. | **Fixed**: T002 (Phase 1, before any verify that runs the suite); quickstart §2 notes it. |
| G1 | Build Tiers (check 2) | HIGH | tasks.md T032 (first draft) | T032's verify grepped for `IDENTITIES` and `Personal & companies`. `test-tools-runtime.py` already contains both, so the verify could not fail. | Verify the new behaviour instead. | **Fixed**: the verify now requires the stage-0 literal `\x1b[C\t \x1b[D`, which the task description names. |
| E4 | Coverage | MEDIUM | `devcontainer.test/test-setup-workspace-repo.sh` L626–630; `.github/workflows/speckit-git-bash.yml` paths | The suite asserts literal `process_selections` lines of `interactive-setup.sh`. It is in neither the plan's suite list nor any CI job that triggers on `interactive-setup.sh`. | Run it in the verify of every task that touches `process_selections`. | **Fixed** in tasks (T003, T004, T018, T029, T039), the plan list and quickstart §2. The CI trigger gap is decision D4: accepted, CI is left as is. |
| E5 | Coverage | MEDIUM | spec FR-033 (narrower than 36 columns); plan render matrix | No test covered "on narrower terminals setup still runs, drawing its 36-column frame". | Add a terminal narrower than 36 columns to the matrix. | **Fixed**: T029 adds a 30-column case. |
| F1 | Inconsistency | MEDIUM | quickstart.md §0 | `bash -n a b c …` checks only `a`, because Bash treats the other names as arguments. A syntax error in the other six scripts would pass. | Run one `bash -n` per file. | **Fixed** in quickstart §0; every task verify runs one `bash -n` per file. |
| B1 | Ambiguity | MEDIUM | OpenSpec `tasks.md` 6.2; plan › Phase 8 | "the 1.7 release notes" names no file. `docs/release-1.7.0.md` is the device-trust scope page, and `docs/releases.md` has no 1.7 entry. T037 uses `docs/release-1.7.0.md` as both the scope and the notes, plus `CHANGELOG.md`. | Confirm the target. | **Accepted**: decision D1 (Brett Heap, 2026-10-21). |
| C3 | Underspecification | MEDIUM | plan › Phase 9; quickstart §4 item 6; OpenSpec 7.2 | Copy approval was listed after real-host QA. If Brett edits the copy after QA, the merged commit differs from the commit QA tested. Tasks put it first (T040 before T041). | Confirm the order. | **Accepted**: decision D3 (Brett Heap, 2026-10-21); the tasks already follow it. |
| F2 | Inconsistency | LOW | plan › Phase 3 vs Phase 5; data-model §1.3 | Phase 3 asks for the vanished-bench fallback of the P and G return targets before Phase 5 creates the extended targets. | Split the data side from the UI side. | Resolved: T012 drops the queued change; T028 handles the focus and target fallback. |
| F3 | Inconsistency | LOW | plan › Phase 4; quickstart §3 | The timing harness is a Phase 4 deliverable, but its 100 ms Benches gate means something only after Phase 6. | Give the harness an engine-only mode. | Resolved: T016 adds `--engine-only` (synthetic body, 25 ms gate, which is the plan's target); the full mode gates in T029. Document the mode in quickstart §3 when the harness lands. |
| F4 | Inconsistency | LOW | plan › Phase 7 exit | "All three workflow jobs green on the PR head" needs a push, and every push is Brett's gate. | Move the check after the push. | Resolved: T042 runs after T041. |
| F5 | Inconsistency | LOW | OpenSpec `design.md` D19 L349 | D19 still reads "Each key press redraws within 100 ms, measured as the median…". The checklists replaced that phrasing in FR-060, SC-006 and the layout delta (performance CHK002), and the delta is authoritative. | Align the wording at the next OpenSpec edit. | Remaining, not fixed: LOW, governed text, and no behaviour differs. |
| F6 | Inconsistency | LOW | plan › Scale/Scope | "9 existing suites change and 5 more are re-verified" left out `test-setup-services.py` and `test-setup-workspace-repo.sh`. | Correct the count. | **Fixed**: 10 change and 6 are re-verified. |
| C1 | Underspecification | LOW | `.specify/feature.json` | Points at `specs/018-clean-sync-benches`; `.specify` scripts rewrite it. | Export `SPECIFY_FEATURE*`, then restore or commit the file. | Handled in handoff.md. |
| C2 | Underspecification | LOW | T001; `AGENTS.md` SPECKIT block | After merge, the block on `release/1.7.0` names 029 instead of 028 (device trust). | Confirm. | **Accepted**: decision D2 (Brett Heap, 2026-10-21). |
| CA1 | Constitution | LOW | `.specify/memory/constitution.md` | The file is an unfilled template, so there are no project principles to gate on. | Ratify a constitution later with `/speckit-constitution`. | **Accepted**: decision D5 (Brett Heap, 2026-10-21); not blocking. |
| G2 | Build Tiers | LOW | T005 ∥ T006 | The `[P]` siblings share no path, but T005's verify runs `test-setup-credential-plan.py`, which T006 edits. | Run `[P]` siblings in separate worktrees, or re-run a verify after its sibling commits. | Remaining: noted for the build lane in handoff.md. |
| G3 | Build Tiers (check 5) | LOW | T031, T032 | These test-only edits have their keys fully given in the plan, so they could rate `[S]`. They stay `[O]`, per the plan's Phase 7 hint, because no verify can run them: a failure surfaces only in CI or in Brett's QA. The tier is above the rubric. | Keep `[O]`. | Accepted. |

There are no CRITICAL findings, no duplicated requirements (FR-019 and FR-046 cross-reference rather than repeat each other) and no unresolved placeholders.

## Coverage Summary

| Requirement Key | Has Task? | Task IDs | Notes |
|---|---|---|---|
| FR-001–FR-007 (steps, navigation, nav bar) | Yes | T017; docs T034–T038 | Agents naming in the docs closed by E1 |
| FR-008–FR-014 (Enter, Review, Apply) | Yes | T018 | |
| FR-015 (contracts unchanged) | Yes | T018, T011 | apply-plan and dependencies-plan draw and load nothing |
| FR-016, FR-017 (Workstation) | Yes | T021 | |
| FR-018 (Agents, Tools) | Yes | T022 | |
| FR-019, FR-020 (Profiles) | Yes | T023 | |
| FR-021, FR-022 (footer) | Yes | T024 | |
| FR-023, FR-024, FR-028 (P, G, readiness jump) | Yes | T019, T028 | |
| FR-025–FR-027, FR-032 (V, R, Q, notices) | Yes | T020 | |
| FR-029–FR-031 (head, selector, strip) | Yes | T017, T021, T022, T023, T025 | |
| FR-033 (width) | Yes | T013, T014, T029 | case narrower than 36 columns added (E5) |
| FR-034–FR-037 (height, scrolling, banner) | Yes | T015, T027, T029 | |
| FR-038, FR-039 (first paint, partial redraw) | Yes | T011, T013, T014, T016, T029 | |
| FR-040 (Loading) | Yes | T021, T022, T028 | |
| FR-041–FR-043 (category block, zones) | Yes | T025 | |
| FR-044–FR-046 (bench panel, About) | Yes | T015, T026 | |
| FR-047 (Benches height budget) | Yes | T027 | |
| FR-048 (metadata delivery, sanitising) | Yes | T009, T010, T011 | security-sensitive, so `[O]` |
| FR-049–FR-051 (loading, degraded, focus survival) | Yes | T011, T012, T028 | |
| FR-052–FR-055 (catalog) | Yes | T005, T006 | approval gate T040 |
| FR-056–FR-058 (safe lookups, fail closed) | Yes | T003, T004 | lands before 365Bench enters the catalog (T005) |
| FR-059 (maintenance scripts) | Yes | T007, T008 | |
| FR-060 (key response) | Yes | T016, T029, T039 | local gate; the no-fork check runs in CI |
| SC-001 | Yes | T018, T025 | keystroke sweep, both zones |
| SC-002 | Yes | T029 (+ per-step rows T021–T027) | |
| SC-003 | Yes | T005, T029 | |
| SC-004 | Yes | T003, T004 | 8 of 8 consumers |
| SC-005 | Yes | T011, T029 | |
| SC-006 | Yes | T016, T029, T039 | |
| SC-007 | Yes | T020 | |
| SC-008 | Yes | T019, T028 | |
| SC-009 | Yes | T018 | |
| SC-010 | Yes | T002, T017, T018, T030–T033, T042, T043 | the real-host part is Brett's (T043) |
| SC-011 | Yes | T010, T011, T028 | |
| SC-012 | Yes | T043 | Brett-only |
| SC-013 | Yes | T005, T040 | the approval is Brett-only |

**OpenSpec traceability**: all 45 delta requirements map to FRs (spec › OpenSpec Traceability), and every FR has a task, so every delta requirement is covered. The OpenSpec `tasks.md` items map as follows:

| OpenSpec item | Speckit tasks |
|---|---|
| 1.3 | this run, ticked in T039 |
| 2.1–2.5 | T003–T008 |
| 3.1 | T009–T012 |
| 4.1–4.6 | T013–T029 |
| 5.1 | T017, T018, T030–T032 |
| 5.2 | T033, T042 |
| 5.3 | T043 |
| 6.1–6.2 | T034–T038 |
| 7.1 | T039, T045 |
| 7.2 | T040 |
| 7.3 | T041, T044 |
| 7.4 | T045 |

## Tier Table

The verify commands are abbreviated here; tasks.md has them in full. Every one runs from the worktree root in WSL and can fail.

| Task | Tier | Files | Verify | Finding |
|---|---|---|---|---|
| T001 | S | `AGENTS.md` | SPECKIT block names 029 | C2 |
| T002 | S | `test-setup-services.py` | services, pty-drain | E3 |
| T003 | O | lookups test; 4 shell consumers | lookups; `bash -n`/`-x` ×4; 6 suites | — |
| T004 | O | `interactive-setup.sh`; lookups test | lookups; 5 suites incl. workspace-repo | — |
| T005 | O | catalog test; `bench-config.json` | catalog; lookups; 6 suites | G2 |
| T006 | S | `credential-requirements.json`; doc; credential-plan test | credential-plan; `source == tui` check; doc grep | G2 |
| T007 | O | `update-bench-config.sh`; maintenance test | maintenance; lookups | — |
| T008 | S | `new-bench.sh`; maintenance test; `newBench.md` | maintenance; lookups; doc greps | — |
| T009 | O | loader; worker; wizard test | wizard; lookups; 4 suites | — |
| T010 | O | loader; `interactive-setup.sh`; wizard test | wizard; 5 suites | — |
| T011 | O | loader; `interactive-setup.sh`; wizard test | wizard; 6 suites | — |
| T012 | O | loader; `interactive-setup.sh`; wizard test | wizard; 4 suites | F2 |
| T013 | O | `interactive-setup.sh`; `tools-container.sh`; layout, async, requirements, profiles tests | layout; 9 suites | — |
| T014 | O | `interactive-setup.sh`; layout, wizard tests | layout; wizard; 5 suites | — |
| T015 | O | `interactive-setup.sh`; layout test | layout; 4 suites | — |
| T016 | O | `interactive-setup.sh`; timing harness; layout test | timing `--engine-only`; layout; 5 suites | F3 |
| T017 | O | `interactive-setup.sh`; 8 test files | wizard; layout; 10 suites; `py_compile` | E2 |
| T018 | O | `interactive-setup.sh`; 5 test files | wizard; layout; 8 suites | E2 |
| T019 | O | `interactive-setup.sh`; 3 test files | wizard; 6 suites | — |
| T020 | O | `interactive-setup.sh`; 4 test files | wizard; layout; 5 suites | — |
| T021 | S | `interactive-setup.sh`; 4 test files | wizard; layout; 5 suites | — |
| T022 | S | `interactive-setup.sh`; 3 test files | wizard; layout; 5 suites | — |
| T023 | S | `interactive-setup.sh`; 3 test files | wizard; layout; 4 suites | — |
| T024 | S | `interactive-setup.sh`; 4 test files | wizard; layout; 6 suites | — |
| T025 | O | `interactive-setup.sh`; 4 test files | wizard; layout; 5 suites | — |
| T026 | O | `interactive-setup.sh`; wizard, layout tests | wizard; layout; 2 suites | — |
| T027 | O | `interactive-setup.sh`; layout test | layout; wizard | — |
| T028 | O | `interactive-setup.sh`; wizard, layout tests | wizard; layout; 4 suites | F2 |
| T029 | O | `interactive-setup.sh`; layout test; timing harness | layout; timing (full); catalog suites; CI `regression` block; 3 suites | E5 |
| T030 | O | both workstation acceptance suites | `py_compile`; pty-drain; services; wizard; no `TUI` alias | — |
| T031 | O | `test-component-lifecycle.py` | `py_compile`; `terminal_screen`; new labels; old keys gone | G3 |
| T032 | O | `test-tools-runtime.py` | `py_compile`; stage-0 literal; label | G1, G3 |
| T033 | O | `.github/workflows/credential-recovery.yml` (governed) | paths in both lists; suites in `regression`; timed local run of the job | — |
| T034 | S | `docs/setup-script-ui.md` | six step names; no stale menu text | — |
| T035 | S | `docs/setup-requirements.md` | Workstation, Review; no "Requirements page" | — |
| T036 | S | `docs/profiles.md` | "step", `G Back`, rows | — |
| T037 | S | `docs/release-1.7.0.md`; `CHANGELOG.md` | Review and the three benches in both | B1 |
| T038 | S | `README.md`; `docs/credential-recovery.md` | stale phrases gone from README and docs | E1 |
| T039 | O | `release-qa.md` (measured values); OpenSpec `tasks.md` | validate; timing; CI block; records; ticks | — |
| T040 | O | `bench-config.json`; `release-qa.md`; OpenSpec `tasks.md` | catalog; approval row; 7.2 ticked | C3 (Brett-only) |
| T041 | O | `tasks.md` | remote head = HEAD; PR base `release/1.7.0` | Brett-only |
| T042 | O | `release-qa.md` | `gh pr checks`; CI row | F4 |
| T043 | O | `release-qa.md`; OpenSpec `tasks.md` | five QA rows PASS; 5.3 ticked | Brett-only |
| T044 | O | `tasks.md` | PR state `MERGED` | Brett-only |
| T045 | O | `openspec/changes/…`, `archive/`, `openspec/specs/` | change archived; `openspec validate --specs --strict` | Brett-only |

Results of the build-tier checks:
- **Check 1** (tier, `files:` and `verify:` present): 45 of 45 pass.
- **Check 2** (a verify that cannot fail): one found and fixed (G1).
- **Checks 3 and 4** (`[H]` tasks): none, because the repository declares no governed invariants.
- **Check 5** (tier against the rubric): none below it; two above it (G3).
- **Check 6** (`[P]` siblings): no shared path.

## Protocol alignment (constitution substitute)

- **G1, approved OpenSpec change and one feature**: holds. Task 1.1 is approved, and 1.3 is ticked in T039.
- **G3, worktree discipline**: this run wrote only `specs/029-setup-guided-wizard/`; `openspec/` is unchanged.
- **G5, governed paths**: every task touching `.github/workflows/`, `openspec/` or `release-qa.md` is `[O]` (T033, T039, T040, T042, T043, T045). The release lock, `.gitmodules` and gitlinks are untouched.
- **G6, verify per task**: 45 of 45 tasks have one.
- **G7, security-sensitive work is `[O]`**: T003 and T004 (fail-closed lookups), and T009–T011 (the outside-text boundary).
- **Brett's gates are explicit tasks**: copy approval (T040), every push (T041, T044, T045), the merge (T044) and the archive (T045).

## Unmapped tasks

T001 (the agent pointer, from plan › Agent context update) and T002 (which lets the build lane verify SC-010) map to no FR by design.

## Metrics

- Total requirements: 73 (60 FR, 13 SC)
- Total tasks: 45 (`[H]` 0, `[S]` 13, `[O]` 32), of which 5 are Brett-only gates
- Coverage: every FR and SC has at least one task (100%)
- Ambiguity count: 1 (B1, resolved by D1); duplication count: 0
- Findings by severity, after Brett accepted D1–D5:

| Severity | Count | Fixed or resolved | Remaining |
|---|---:|---:|---:|
| CRITICAL | 0 | 0 | 0 |
| HIGH | 4 | 4 | 0 |
| MEDIUM | 5 | 5 | 0 |
| LOW | 10 | 8 | 2 (F5 at the next OpenSpec edit; G2 noted for the build lane) |

## Decisions (accepted by Brett Heap, 2026-10-21)

- **D1 Release-notes target (B1).** Add the wizard as a section of `docs/release-1.7.0.md`, serving as both scope and release notes, plus a `CHANGELOG.md` entry, as T037 does. **Accepted.**
- **D2 `AGENTS.md` pointer (C2).** After merge, `release/1.7.0` names 029 as the active plan instead of 028; if 028 is still in flight, keep both lines. **Accepted.**
- **D3 Gate order (C3).** Approve the bench copy before the candidate push and real-host QA, so QA runs on the approved copy (T040 → T041). **Accepted.**
- **D4 CI trigger gap (E4).** `speckit-git-bash.yml` does not trigger on `scripts/interactive-setup.sh`, though `test-setup-workspace-repo.sh` asserts its text. Leave CI as it is in this feature; the local verifies cover it. **Accepted.**
- **D5 Constitution (CA1).** Ratify one later with `/speckit-constitution`; it does not block this feature. **Accepted.**

## Next actions

- No CRITICAL or open HIGH findings remain, so `/speckit-implement` may start (see handoff.md).
- Re-run `/speckit-analyze` before T039, where OpenSpec 1.3 is ticked.
- When T016 lands, add `--engine-only` to quickstart §3 (F3).
- At the next OpenSpec edit, align design D19's wording (F5).

## Remediation applied in this run

All fixes are in commit `1d1d203`. `openspec/changes/setup-guided-wizard/` is unchanged, and `openspec validate setup-guided-wizard --strict` passes.

- **`tasks.md`**: added T002 and T038; extended the rule-S1 scope of T017 and T018; added the sub-36 case to T029; fixed T032's verify.
- **`plan.md`**: impact table, source list, suite count, suite list and documentation tree.
- **`quickstart.md`**: the `bash -n` loop in §0; the workspace-repo suite and the WSL note in §2.
