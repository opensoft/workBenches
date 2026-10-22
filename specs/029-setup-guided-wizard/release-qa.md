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
