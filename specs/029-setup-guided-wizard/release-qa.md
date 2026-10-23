# Guided setup wizard verification record

Verified source: `97f0a1e4e52ca75147f94e59cf22490e5caa53ee` on branch `029-setup-guided-wizard`, 2026-10-22.
Host: Raven, native Linux / Omarchy, x86_64, Linux 7.1.9-arch1-2,
GNU Bash 5.3.15. The source remains `1.7.0-dev.1`; this is not a release candidate.
The T039 commit adds this record and task ticks; no build commit has been pushed.

## Gates

| Gate | Who | Date | Commit | Host | Result | Notes |
|---|---|---|---|---|---|---|
| Timing (FR-060) | Codex | 2026-10-22 | 97f0a1e4e52ca75147f94e59cf22490e5caa53ee | Raven / Linux | PASS | Engine-only median 0.811 ms; full Benches median 3.269 ms. Distribution and per-step values below. |
| Local suites | Codex | 2026-10-22 | 97f0a1e4e52ca75147f94e59cf22490e5caa53ee | Raven / Linux | PASS | All 32 quickstart suites, native/WSL acceptance compilation and the CI regression command. Quickstart list: 60.57 s. |
| OpenSpec validate | Codex | 2026-10-22 | 97f0a1e4e52ca75147f94e59cf22490e5caa53ee | Raven / Linux | PASS | `openspec validate setup-guided-wizard --strict`. |
| Bench copy approval | Brett Heap | pending | pending | pending | pending | T040: read all twelve taglines and About panels in the running preview; approve or provide edits. |
| Workstation Setup CI | GitHub Actions | pending | pending | pending | pending | T042: after explicit push/PR approval. Local regression took 54.39 s within the unchanged 5-minute timeout. |
| Native workstation acceptance | Brett Heap | pending | pending | pending | pending | T043: disposable real-host acceptance on the pushed candidate. |
| WSL workstation acceptance | Brett Heap | pending | pending | pending | pending | T043: opt-in disposable-engine WSL acceptance. |
| 365Bench TUI install | Brett Heap | pending | pending | pending | pending | T043: install through the wizard on a disposable workstation. |
| Glyph check | Brett Heap | pending | pending | pending | pending | T043: Windows Terminal and VS Code terminal, 36/80/120 columns. |
| Fresh-workstation walkthrough | Brett Heap | pending | pending | pending | pending | T043: follow the visible navigation and hints through Apply. |

## Phase summary

Every completed task was verified with its prescribed command and committed
separately. T002 ran first as the build prompt requires. All phase-boundary fetches
left `origin/release/1.7.0` at `ccc9eaca2c492db27ea262b90eaf30d506c55ef3`;
no rebase was needed.

| Phase | Tasks | Commits | Result |
|---|---|---|---|
| 1 — Safe lookups | T001–T004 | `a5e1bcd`, `5cffe01`, `cf81227`, `89ce6f0` | PASS: digit-leading readers and invalid-path apply fixtures; no root setup actions. |
| 2 — Catalog | T005–T008 | `2bf3703` through `9aee527` | PASS: all twelve locked benches, copy rules, credential options and metadata-preserving maintenance. T005 rechecked after T006. |
| 3 — Metadata | T009–T012 | `c52ac32` through `d2828fc` | PASS: atomic snapshots, built-in readers, sanitising, fallback grouping and queue pruning. |
| 4 — Frame engine | T013–T016 | `32096c9` through `2114f82` | PASS: array renderer, resize/input handling, scrolling primitives and engine timing. |
| 5 — Wizard flow | T017–T024 | `ab625c1` through `e6d4324` | PASS: six steps, Review gate, exact jump targets, actions, service/component/profile bodies and responsive footers. |
| 6 — Benches | T025–T029 | `1949c3b` through `ddd2915` | PASS: category zones, responsive copy/About, height budgets, refresh focus, full matrix and retirement of the legacy renderer. |
| 7 — Acceptance / CI | T030–T033 | `f5a2485` through `f516f2b` | PASS locally: acceptance scripts compile, assertions retained, expanded regression command completes within timeout. Remote CI and real-host runs pending. |
| 8 — Documentation | T034–T038 | `b8fc3d6` through `97f0a1e` | PASS: step names, keys, readiness and Enter → Review → Apply are consistent; 1.7 notes name the three new benches. |
| 9 — Verification | T039 | this record commit | PASS for local gates only. Stop before T040. |

### Task-field corrections

The build prompt permits correcting a provably wrong field. T016 and T019 added
`scripts/lib/setup-status-loader.sh` to their `files:` fields because their
required metadata cleanup/readiness transitions are implemented there. T028 added
that loader and `devcontainer.test/test-setup-async.py`: its existing refresh
fixture needed to identify its manually seeded bench as an already-loaded bench
view. Its focus-preservation assertion remains unchanged. These corrections are
explained in the corresponding commit bodies. No `verify:` was weakened.

## Timing

Commands: `python3 devcontainer.test/test-setup-render-timing.py --engine-only`
and `python3 devcontainer.test/test-setup-render-timing.py`.
Both use the real twelve-bench catalog, known fixture statuses and an 87×40 frame;
full mode starts in Software Engineering's bench zone. The harness runs locally,
not in CI. Engine-only uses a synthetic body and has a 25 ms median gate; full
mode has the 100 ms median gate (engineering target 25 ms).

```text
Engine-only: median=0.811ms p90=1.083ms max=1.138ms
Workstation: median=0.402ms
Benches: median=0.394ms
Agents: median=0.397ms
Tools: median=0.421ms
Profiles: median=0.394ms
Review: median=0.399ms

Full Benches: median=3.269ms p90=4.637ms max=5.159ms
Workstation: median=2.064ms
Benches: median=2.424ms
Agents: median=2.379ms
Tools: median=2.135ms
Profiles: median=1.855ms
Review: median=2.045ms
```

The deterministic no-fork guard has no bridge exemptions. The full frame matrix
covers every step under C.UTF-8 and C startup locales: 36/60/87 columns ×
24/40/unknown height, plus 37×24, 80×24, 88×39, 88×40, 120×40 and a best-effort
30-column case. It checks bounds, navigation/focus/footer visibility, three queued
counts at 80 columns, banner behavior and no discovery calls. Every locked bench
is checked in its category for tagline and About content. At 80×24 Software
Engineering shows all eight benches plus a three-line About window.

## Complete local suite results

The exact quickstart §2 loop passed all of the following. Native and WSL
acceptance scripts also passed `py_compile`. Docker-backed / real-host acceptance
was not executed; all executed setup operations used the fixture suites.

- PASS `devcontainer.test/test-acceptance-pty-drain.py`
- PASS `devcontainer.test/test-image-layer-budget.py`
- PASS `devcontainer.test/test-setup-requirements.py`
- PASS `devcontainer.test/test-setup-async.py`
- PASS `devcontainer.test/test-setup-services.py`
- PASS `devcontainer.test/test-workbenches-account.py`
- PASS `devcontainer.test/test-setup-profiles.py`
- PASS `devcontainer.test/test-profile-multi-identity.py`
- PASS `devcontainer.test/test-docker-prerequisite.py`
- PASS `devcontainer.test/test-setup-components.py`
- PASS `devcontainer.test/test-vibe-annotations-readiness.py`
- PASS `devcontainer.test/test-setup-credential-plan.py`
- PASS `devcontainer.test/test-git-transport.py`
- PASS `devcontainer.test/test-compose-ai-profiles.py`
- PASS `devcontainer.test/test-vault-credential-recovery.py`
- PASS `devcontainer.test/test-setup-guided-flow.py`
- PASS `devcontainer.test/test-setup-consent.py`
- PASS `devcontainer.test/test-install-friction.py`
- PASS `devcontainer.test/test-azure-cli-runtime.py`
- PASS `devcontainer.test/test-release-version.py`
- PASS `devcontainer.test/test-project-command.py`
- PASS `devcontainer.test/test-bench-catalog.py`
- PASS `devcontainer.test/test-bench-catalog-lookups.py`
- PASS `devcontainer.test/test-setup-wizard.py`
- PASS `devcontainer.test/test-setup-wizard-layout.py`
- PASS `devcontainer.test/test-setup-bench-status.sh`
- PASS `devcontainer.test/test-ai-credential-keyvault.sh`
- PASS `devcontainer.test/test-opencode-omniroute-credential.sh`
- PASS `devcontainer.test/test-setup-ai-credential-recovery.sh`
- PASS `devcontainer.test/test-setup-cancel.sh`
- PASS `devcontainer.test/test-setup-workspace-repo.sh`
- PASS `devcontainer.test/test-bench-catalog-maintenance.sh`

Strict OpenSpec validation passed. Each task's own verification also passed,
including workspace-repository checks (152 checks), local selection contracts,
first-paint/partial-redraw checks and cancellation behavior.

## Pre-landing analysis

Re-ran the repository `speckit-analyze` workflow read-only against the spec, plan,
tasks, contracts, constitution and approved OpenSpec handoff. All 60 functional
requirements and 13 success criteria map to the 45 tasks. No uncovered requirement,
unmapped task or CRITICAL/HIGH cross-artifact finding remains. Human/remote gates
are intentionally assigned to T040–T045 and are not claimed complete.

The constitution is still an unratified template, as accepted in decision D5;
the plan's G1–G7 gates and shared protocol govern this build. All task tier tags,
scopes and verify contracts remain present. Optional pre/post analysis commit
hooks required no additional commit; analysis changed no governing artifact.

Remaining known finding: **F5 (LOW)** in `analysis.md` — OpenSpec design D19 says
“Each key press redraws within 100 ms, measured as the median…”. The authoritative
layout delta, FR-060 and the implemented gate consistently require the median.
No behavior or requirement is relaxed; governed design wording was left unchanged.
No other analysis remediation remains for this build stop.

## T040 handoff

Only with Brett's explicit OK, open the running selection-only preview from this
worktree using `scripts/interactive-setup.sh --select-only /tmp/wizard-preview.json`.
Review every bench's tagline and About text (description, uses and contents), then
approve the copy or provide exact edits. Service rows and V still run real actions;
use category/bench navigation and About paging for copy review. Q cancels.
Record approval with the reviewed commit before requesting separate push/PR
permission at T041. Do not push, open a PR, merge or archive at the T039 stop.

## Live-review adjustment 029-A01 — 2026-10-22

Brett requested removing the duplicate status row beneath About, separating the
category section from the header, and adding space below the Opensoft logo.
Task T039A implements this feedback after baseline `3a3cbb3`; its implementation
and evidence are in the commit containing this section. The working spec, plan,
acceptance criteria, footer contract and OpenSpec deltas reflect the accepted
refinement. See `features/029-setup-guided-wizard/openspec/029-A01.md`.

- Benches omits its focused-bench/category footer context row. Its divider keeps
  the queued changes total, followed directly by navigation hints.
- Every logo has one blank row below it. Roomy Benches also has one blank row
  between the header rule and CATEGORY. Tight Benches uses the removed footer
  row for logo spacing, preserving all eight benches and three About lines at
  80×24.
- PASS: task T039A's exact verify command, including the 24 wizard tests,
  18 layout tests/full locale-size matrix, no-fork guard, syntax and strict
  OpenSpec validation. The existing assertions remain; spacing/footer checks
  extend them.
- PASS: all 32 quickstart suites and native/WSL acceptance compilation after
  the adjustment. No Docker-backed real-host tests were run.
- Full Benches timing: median 3.373 ms, p90 4.645 ms, max 5.105 ms. Per-step
  medians: Workstation 2.098, Benches 2.436, Agents 2.428, Tools 2.146,
  Profiles 1.878, Review 2.047 ms.
- Visual check: updated live preview on Raven, Benches/Software Engineering
  with cppBench focused. Logo/category gaps, complete bench and About content,
  and the footer divider total are visible without a duplicate status row.

T040 remains pending: this layout feedback does not approve the twelve benches'
wording. No push, PR, merge or archive is authorized by this adjustment.

## Live-review adjustment 029-A02 — 2026-10-22

Brett requested renaming Agents to Harness and adding a blank line between the
category list and bench panel, and another between the bench panel and About.
Task T039B implements that feedback after baseline `bd32ec1`; its implementation
and evidence are in the commit containing this section. The accepted amendment
is `features/029-setup-guided-wizard/openspec/029-A02.md`.

- Harness is the consistent label in navigation, its panel, Review, working
  feature contracts and current user documentation. Historical decisions and
  earlier verification records keep their original wording.
- Roomy Benches has both new section gaps. The height calculation reserves
  their rows before assigning space to lists and About. Tight views omit the
  extra gaps, preserving all eight Software Engineering benches and three About
  lines at 80×24.
- The current nav item's trailing highlight padding is removed to accommodate
  the extra character in Harness; the full nav with three single-digit queued
  counts still fits the 79-column frame at an 80-column terminal.
- PASS: exact T039B verify command; 24 wizard and 18 layout tests, including
  the full size/locale matrix, updated name/spacing checks and no-fork guard;
  Bash syntax and strict OpenSpec validation. Existing behavioral assertions
  remain intact.
- PASS: all 32 quickstart suites and native/WSL acceptance compilation after
  the change. No Docker-backed real-host acceptance was run.
- Full Benches timing: median 3.319 ms, p90 4.707 ms, max 5.927 ms. Per-step
  medians: Workstation 2.091, Benches 2.463, Harness 2.371, Tools 2.200,
  Profiles 1.874, Review 2.064 ms.
- Visual check: refreshed live preview on Raven, workspace 14, maximized to
  show the full layout with cppBench focused. Harness and both new section
  gaps are visible. Compact rendering was also inspected.

All twelve benches' wording is unchanged and T040 approval remains pending.
No push, PR, merge or archive was performed.

## Live-review adjustment 029-A03 — 2026-10-22

Brett requested `openBenches v1.7` beside the Opensoft logo and the detected OS
inside the separator bar. T039C implements this after baseline `2e627e1`; the
implementation/evidence are in the commit containing this section. See
`features/029-setup-guided-wizard/openspec/029-A03.md`.

- The display brand sits beside the full logo on its third row, or beside
  compact Opensoft when height/width requires it. Full logos require a
  59-column frame to fit both.
- The separator below navigation carries the detected OS at its right; Raven
  shows `Linux — Omarchy`. There is no standalone version/OS row.
- One blank row remains below the banner. The freed version row gives About
  four lines instead of three at 80×24, retaining all eight benches.
- Repository VERSION and non-wizard product identities are unchanged.
- PASS: exact T039C verification, including 24 wizard tests, 18 responsive
  layout tests/full size-locale matrix, six async tests, no-fork and partial
  redraw guards, Bash syntax, strict OpenSpec validation, and compilation of
  component-lifecycle/WSL acceptance. Header-specific markers were updated;
  cancellation and lifecycle assertions remain in place.
- PASS: all 32 quickstart suites and native/WSL acceptance compilation.
  Docker-backed real-host acceptance remains unexecuted.
- Full Benches timing: median 3.354 ms, p90 4.784 ms, max 5.055 ms. Per-step
  medians: Workstation 2.107, Benches 2.434, Harness 2.420, Tools 2.135,
  Profiles 1.852, Review 2.081 ms.
- Visual check: refreshed and maximized live Benches preview on Raven,
  workspace 14, cppBench focused. The requested adjacent brand and OS divider
  are visible with the prior section spacing retained.

Bench copy is unchanged; T040 approval remains pending. Nothing was pushed,
opened as a PR, merged or archived.

## Live-review alignment polish T039D — 2026-10-22

Brett requested centering the existing brand within the space to the logo's
right. After baseline `8003efc`, T039D computes the available horizontal space
from visible character widths for both full and compact banners, with balanced
left/right spacing to within one character. The approved header composition,
wordmark row and collapse thresholds are unchanged. This is implementation-only
alignment polish under FR-029/037.

PASS: the exact T039D command (Bash syntax, 18 layout tests including the full
responsive/locale matrix and no-fork guard, and six async/partial-redraw tests).
Visual verification: refreshed maximized Benches preview on Raven, workspace 14,
with the brand centered between the logo and the frame's right edge.
T040 copy approval remains pending; no remote changes were made.

## Live-review adjustment 029-A04 — 2026-10-22

Brett requested Workstation follow the Benches layout, with a blank row below
the divider, one Containers panel combining required services and optional
Vault, and a focused About panel. T039E implements this after baseline
`8227a1b`; implementation/evidence are in the commit containing this section.
See `features/029-setup-guided-wizard/openspec/029-A04.md`.

- One Containers panel lists WSL 2 where applicable, Docker, Tools and Vault
  in their existing order. States and immediate action buttons are retained.
  The required count excludes optional Vault. The readiness strip/markers,
  Apply/Profile gates, service actions and serialized queue are unchanged.
- Inline focused-row explanations move into About, alongside a short purpose
  description. About follows focus, resets on service change, clamps on
  same-service refresh and pages with PgUp/PgDn or [/]. It uses the existing
  fork-free wrapping/paging renderer. Full footer hints include G Profiles.
- Workstation has a blank row after its navigation divider. Roomy layouts
  also separate Containers and About; tight layouts preserve content space.
- PASS: exact T039E verification: Bash syntax, 25 wizard tests, 18 layout
  tests including the complete size/locale matrix and native/WSL Workstation
  cases at 36/60/61/88 columns × 24/40/unknown rows, six async tests,
  18 requirements tests, eight service tests, timing, component-lifecycle
  compilation and strict OpenSpec validation. The new About test verifies
  both paging key forms, reset, unchanged queue and no service action.
- PASS: all 32 quickstart suites and native/WSL acceptance compilation after
  the adjustment. No Docker-backed or real-host acceptance was executed.
- Full Benches timing: median 3.256 ms, p90 4.666 ms, max 5.892 ms. Per-step
  medians: Workstation 2.288, Benches 2.453, Harness 2.377, Tools 2.134,
  Profiles 1.865, Review 2.077 ms.
- Visual check: refreshed maximized live Workstation preview on Raven,
  workspace 14, with Tools focused. Containers, the selected-service About
  purpose/current details, divider gap and full footer are visible.

Bench copy is unchanged and T040 remains pending. No push, PR, merge or archive
was performed.

## Approved Workstation lifecycle extension T039F — 2026-10-22

Brett requested replacing the duplicate Requirements service row with a blank
row, moving service information into Containers, and adopting the Benches
selection pattern with Installed/Up status. He explicitly chose all entries,
including Docker/WSL, and subsequently instructed “then commit and push” and
“get this repo in sync with remote.” That newer instruction authorizes branch
publication before the pending bench-copy gate; it does not approve a merge,
archive, or the bench wording.

The accepted full OpenSpec extension is setup-workstation-lifecycle, handed to
feature 029/task T039F. It explicitly extends the former immediate-service and
allowed-plan-key contracts. The implementation/evidence are in the commit
containing this record, after baseline `aa6b4d1`.

- Containers rows show selection boxes on the left and installation/runtime
  state on the right, including Installed · Up. Space selects install/start,
  D selects uninstall, Enter opens Review, and only Review Apply authorizes
  execution. The Requirements heading/count remains, with a blank next row.
- Selected services appear in Review with Workstation counts/warnings. Normal
  component readiness is retained; missing prerequisites are installed using
  a service-only plan before returning for component setup. Service-only
  teardown does not require the services being removed to be Up.
- Selection-only mode writes private schemaVersion-1 JSON natively/atomically,
  without Python or Docker. The strict native prerequisite reader rejects
  malformed, duplicate, unknown-service, non-private and symlink plans. Mixed
  component plans receive Python/catalog validation before selected service
  changes. Service-only plans skip unrelated onboarding/build steps.
- Managed removal checks role/uid/HOME and pins the verified container ID,
  preserving volumes, images, credentials and projects. Native Linux Engine
  package removal avoids purge/autoremove and preserves Docker data/config.
  All removal preflights occur before service mutation; removals execute last
  after successful work. Component failure prevents later removal.
- Docker Desktop uninstall is data-destructive by default and WSL teardown
  must occur outside the running distro. These cases refuse with manual
  host steps before mutation and are never reported completed. No WSL
  unregister/shutdown/restart or real host removal was executed in this build.
- Background checks adopt healthy installed Tools and do not start/install
  missing/stopped Tools. Refresh preserves selected service actions.
- PASS: exact T039F verification; all 32 quickstart suites; 11 lifecycle
  fixtures (also loaded by the CI requirements suite, now 29 tests); the
  full responsive/locale matrix, async/partial redraw, cancellation, ownership,
  native selection security, service-only root path and failure-order checks.
  Native/WSL acceptance and component-lifecycle compile. Docker-backed and
  real-host acceptance remain pending. Both OpenSpec changes validate strict.
- Timing and visual evidence: timing remains below the engineering target;
  the latest live Workstation preview on Raven/workspace 14 shows the requested
  boxes, Installed · Up labels, blank row and About panel. Latest timing: engine-only median 0.799 ms; full median 3.197 ms, p90
  4.525 ms, max 4.831 ms; Workstation step median 2.088 ms.

Fixture-scope corrections: the new sourced lifecycle helper was added to the
selective Docker prerequisite/bench-status/cancellation fixtures, and stat/wc
to the isolated component fixture PATH. All their prior assertions remain.
The existing immediate-row/strip expectations were updated to the explicitly
approved queue/status behavior; V's account shortcut/cancellation coverage stays.

Before publication, fetch confirmed origin/029-setup-guided-wizard was an
ancestor (44 local commits ahead, zero behind), release/1.7.0 remained
`ccc9eaca2c492db27ea262b90eaf30d506c55ef3`, and VERSION remained 1.7.0-dev.1.
T040 copy approval, remote/real-host QA, merge and archive remain pending.

## Review refinement 029-A05 / T039G — 2026-10-23

Brett requested the Harnesses panel title, About for each selected harness/tool,
and Tools categories matching the Benches browsing pattern. Amendment 029-A05
records the accepted refinement after baseline `de43627`. Implementation and
evidence are in the commit containing this record.

- The nav/Review step remains Harness; its list is titled Harnesses. All eight
  harness/specification entries and all seven tools have cached About text.
- Tools groups are Editors (VS Code), Terminals (Warp/Wave), Networking
  (AmneziaVPN/0dcloud VPN), and Workstation setup (Shell setup/Org workspace).
  Category/list zones use the Benches keys; only the current category's tools
  appear. Space enters a category list without queuing, and Space/D selects
  changes only in the tool zone. Existing flat IDs, installer order and
  configuration-only restrictions remain unchanged.
- Shared About paging/reset/clamping applies to both steps. P/G saves and
  restores tool zone/category/global item plus list/About offsets and anchor.
  Refresh preserves these and queued actions. Categories collapse at short
  heights, and lists/About reserve footer space without renderer subprocesses.
- PASS: exact T039G command (29 wizard tests, 19 layout tests, six async tests,
  43 guided-flow tests, syntax, timing and strict OpenSpec validation). The
  complete size/locale matrix retains its focus/bounds/no-discovery assertions;
  Tools item cases explicitly enter the tool zone. New coverage renders all
  15 item descriptions, proves category isolation, tests keyboard selection,
  both paging forms, jump/refresh restoration and configuration-only actions.
- PASS: all 32 quickstart suites and native/WSL acceptance compilation. The
  component reconfiguration fixture now identifies the selected Workstation
  setup category/tool zone; its true:install assertion is unchanged. That
  fixture was added to T039G's files field to reflect the new focus model.
- Full Benches timing: median 3.306 ms, p90 4.700 ms, max 5.310 ms. Step
  medians: Workstation 2.195, Benches 2.524, Harness 2.960, Tools 2.580,
  Profiles 1.933, Review 2.224 ms.
- Visual review: Raven/workspace 14, Harnesses with Claude Code CLI About;
  Tools with Terminals selected and its Warp/Wave list/category About.
  Individual tool About rendering is covered for all seven entries by the
  fixture checks. The live preview remains available for Brett's review.

No installer, real Docker build, service removal, or WSL restart was executed.
Bench copy approval and real-host/remote release gates remain pending. This
review iteration continues the existing authorization to commit/push updates
to the same feature branch; no merge or archive is authorized.


## Review refinement 029-A06 / T039H — 2026-10-23

Source: this T039H commit, based on `6d471b2d4f5eff4a5421cb7529c21182d9d0924a`.
Brett requested implementation of the categorized Harness catalog and combined
Editors & IDEs group. Both steps now share category/list navigation and About,
with four Harness categories, seventeen harness entries and eleven Tools entries.
Existing managed flat indexes, installer order, credential options and allowed
plan keys stay stable. Thirteen new references explicitly require manual setup,
show setup sources, lack action boxes, and cannot be queued or accepted as plan
keys. Presence checks distinguish desktop launchers from CLIs, use exact local
VS Code default-profile extension IDs, cache failed as well as successful
extension inventory, and leave Windows/WSL references for manual checking.
Installation evidence does not establish sign-in.

Long setup links revealed body-column/paging-marker truncation. Body-only rows
now retain the full interior width, and About reserves room for paging markers.
A round-trip fixture preserves the complete link through wrapping and paging.

Verification on Raven / native Linux, using fixtures only:

- Exact T039H verify: PASS, 34.29 seconds; Bash syntax, wizard 31, layout 21,
  components 28, guided flow 43 and async 6 tests; native/WSL acceptance compile;
  render timing and strict guided-wizard OpenSpec validation.
- All 32 quickstart suites: PASS, 66.46 seconds. The final extension-inventory
  caching adjustment also passed the component suite and the complete exact
  T039H verify afterward.
- Both guided-wizard and workstation-lifecycle OpenSpec changes validate strictly.
- Existing locale/size matrix retained, plus all Harness categories in both zones
  at 36/60/87 columns and 24/40/unknown height under C and C.UTF-8 (144 frames).
  Every catalog member has About; category membership and manual action/plan
  rejection are covered. P/G/refresh preserve focus and About pages.
- Full Benches timing median 3.447 ms, p90 4.820 ms, max 5.218 ms. Step medians:
  Workstation 2.227, Benches 2.508, Harness 3.411, Tools 3.298,
  Profiles 1.978, Review 2.460 ms. No renderer subprocess exemptions.
- Live selection-only preview refreshed on workspace 14; visually inspected the
  Harness categories/TUI list/About and Editors & IDEs category/list/About.
  Actual native package naming prompted adding the distinct antigravity-ide
  launcher as desktop evidence, without treating agy as a desktop install.
- Scope, LF, modes and diff whitespace checks pass; release base remains `ccc9eac`.

No installers, removals, Docker builds, account actions or host configuration
changes were executed. Human bench-copy approval, remote CI, real-host install
QA, PR/merge and archive gates remain pending.
