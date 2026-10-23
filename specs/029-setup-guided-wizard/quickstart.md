# Quickstart: building and checking the guided setup wizard

**Feature**: [`029-setup-guided-wizard`](spec.md) · **Plan**: [plan.md](plan.md)

For the builders of the tasks in this feature and for Brett's real-host QA. Commands run **inside WSL** (or on Linux) from the feature worktree root; never run Git or the suites from Windows.

```bash
cd "$(git worktree list | awk '/\[029-setup-guided-wizard\]/ {print $1}')"   # from your workBenches checkout
```

## 0. Before every commit

Editing over the `\\wsl.localhost\…` UNC path from Windows drops the executable bit (prototype finding). Check modes and line endings before committing:

```bash
git diff --cached --summary | grep -E 'mode change' && echo "MODE CHANGED: restore with chmod +x" || echo "modes ok"
git diff --cached --name-only | xargs -r grep -l $'\r' && echo "CR FOUND" || echo "no CR"
for f in scripts/interactive-setup.sh scripts/lib/setup-status-loader.sh scripts/setup-workbenches.sh scripts/update-project.sh scripts/launchBench scripts/update-bench-config.sh scripts/new-bench.sh; do bash -n "$f" || echo "SYNTAX $f"; done   # bash -n checks only its first file argument
git ls-files -s scripts/interactive-setup.sh scripts/launchBench setup.sh | awk '{print $1, $4}'   # expect 100755
```

## 1. Preview the wizard

### Live preview (real checks, nothing applied)

```bash
scripts/interactive-setup.sh --select-only /tmp/wizard-preview.json
```

This is the TUI stage of `./setup.sh` alone: it paints at once, runs the background readiness and component checks (as setup does, which connect to already-running Tools; missing/stopped Tools requires explicit selection), and on Enter on Review writes `/tmp/wizard-preview.json` and exits 0. It never applies, installs, builds or removes anything; Q exits 130. Inspect what Review would have applied with `cat /tmp/wizard-preview.json`.

Check sizes by resizing the terminal, or in a fixed-size tmux pane:

```bash
for size in 37x24 60x24 81x24 88x40 120x40; do
  tmux new-session -d -s wizard -x "${size%x*}" -y "${size#*x}" \
    "scripts/interactive-setup.sh --select-only /tmp/wizard-preview.json"
  tmux attach -t wizard
done
```

### Offline render of one step (no Docker, no checks)

Once the frame builder and the metadata loader exist (Phases 3–4), any step can be printed at any size from fixtures, for review or bug reports:

```bash
bash -c '
  export WORKBENCHES_SETUP_LOG_FILE=/dev/null
  source scripts/interactive-setup.sh
  init_components; setup_load_bench_metadata_sync     # synchronous path, as with no TTY
  for k in "${!component_description[@]}"; do component_status[$k]=installed; done
  for k in "${requirement_items[@]}"; do component_status[$k]=up; done
  status_checks_running=false; setup_os_label=Linux
  tput() { case $1 in cols) echo 81;; lines) echo 24;; esac; }   # 80-column frame, 24 rows
  CURRENT_SECTION=0; setup_bench_zone=bench; current_selection=0
  render_setup_frame'
```

Function names are those planned in [data-model.md](data-model.md); adjust if the builder chose others.

## 2. Local suites

Every task's `verify:` command is a subset of this list. Run the whole list before asking for review.

### Existing setup suites (the "Workstation Setup" `regression` job)

```bash
python3 -m py_compile devcontainer.test/test-wsl-workstation-acceptance.py devcontainer.test/test-workstation-acceptance.py
python3 devcontainer.test/test-acceptance-pty-drain.py
python3 devcontainer.test/test-image-layer-budget.py
python3 devcontainer.test/test-setup-requirements.py
python3 devcontainer.test/test-setup-async.py
python3 devcontainer.test/test-setup-services.py
python3 devcontainer.test/test-workbenches-account.py
python3 devcontainer.test/test-setup-profiles.py
python3 devcontainer.test/test-profile-multi-identity.py
python3 devcontainer.test/test-docker-prerequisite.py
python3 devcontainer.test/test-setup-components.py
python3 devcontainer.test/test-vibe-annotations-readiness.py
python3 devcontainer.test/test-setup-credential-plan.py
python3 devcontainer.test/test-git-transport.py
bash devcontainer.test/test-setup-bench-status.sh
python3 devcontainer.test/test-compose-ai-profiles.py
bash devcontainer.test/test-ai-credential-keyvault.sh
bash devcontainer.test/test-opencode-omniroute-credential.sh
python3 devcontainer.test/test-vault-credential-recovery.py
python3 devcontainer.test/test-setup-guided-flow.py
python3 devcontainer.test/test-setup-consent.py
python3 devcontainer.test/test-install-friction.py
python3 devcontainer.test/test-azure-cli-runtime.py
bash devcontainer.test/test-setup-ai-credential-recovery.sh
bash devcontainer.test/test-setup-cancel.sh
```

### Also affected, outside that job

```bash
python3 devcontainer.test/test-release-version.py        # sources interactive-setup.sh
python3 devcontainer.test/test-project-command.py        # reads bench-config.json
bash devcontainer.test/test-setup-workspace-repo.sh       # asserts process_selections lines (CI runs it only in speckit-git-bash)
```

On a WSL host `test-setup-services.py` times out until task T002 stubs the WSL requirement item (it passes on the CI Ubuntu runner).

### New suites (this feature)

```bash
python3 devcontainer.test/test-bench-catalog.py             # FR-052–055: schema, copy rules, lock coverage, simBench
python3 devcontainer.test/test-bench-catalog-lookups.py     # FR-056–058: static check, 365Bench in 8 consumers, fail closed
bash    devcontainer.test/test-bench-catalog-maintenance.sh # FR-059: regeneration and new-bench keep metadata, skip unlocked clones
python3 devcontainer.test/test-setup-wizard.py              # steps, nav, Enter→Review→Apply, jumps, footers, Benches zones, metadata, sanitising
python3 devcontainer.test/test-setup-wizard-layout.py       # render matrix, width/height bounds, banner, nav fit, no-fork render path
```

### Spec and change

```bash
openspec validate setup-guided-wizard --strict
```

### One loop for all of the above

```bash
fail=0
for t in devcontainer.test/test-{acceptance-pty-drain,image-layer-budget,setup-requirements,setup-async,setup-services,workbenches-account,setup-profiles,profile-multi-identity,docker-prerequisite,setup-components,vibe-annotations-readiness,setup-credential-plan,git-transport,compose-ai-profiles,vault-credential-recovery,setup-guided-flow,setup-consent,install-friction,azure-cli-runtime,release-version,project-command,bench-catalog,bench-catalog-lookups,setup-wizard,setup-wizard-layout}.py; do
  python3 "$t" >/tmp/suite.log 2>&1 && echo "PASS $t" || { echo "FAIL $t"; tail -20 /tmp/suite.log; fail=1; }
done
for t in devcontainer.test/test-{setup-bench-status,ai-credential-keyvault,opencode-omniroute-credential,setup-ai-credential-recovery,setup-cancel,setup-workspace-repo,bench-catalog-maintenance}.sh; do
  bash "$t" >/tmp/suite.log 2>&1 && echo "PASS $t" || { echo "FAIL $t"; tail -20 /tmp/suite.log; fail=1; }
done
python3 -m py_compile devcontainer.test/test-workstation-acceptance.py devcontainer.test/test-wsl-workstation-acceptance.py || fail=1
openspec validate setup-guided-wizard --strict || fail=1
exit $fail
```

### Docker-backed jobs (CI; run locally only on a disposable engine)

The `tools-runtime` and `component-lifecycle` jobs of the Workstation Setup workflow run `test-tools-runtime.py` and `test-component-lifecycle.py` inside Compose services with their own engine. They change Docker state (images, containers, volumes) and belong to CI or a disposable machine:

```bash
export WORKBENCHES_SOURCE_ROOT="$PWD" WORKBENCHES_DOCKER_GID="$(stat -c %g /var/run/docker.sock)"
docker compose -p workbenches-runtime-test -f devcontainer.test/docker-compose.yml --profile tools-runtime run --rm --no-deps tools-runtime
docker compose -p workbenches-runtime-test -f devcontainer.test/docker-compose.yml --profile tools-runtime down --remove-orphans
docker compose -p workbenches-lifecycle -f devcontainer.test/docker-compose.yml --profile component-lifecycle run --rm component-lifecycle
docker compose -p workbenches-lifecycle -f devcontainer.test/docker-compose.yml --profile component-lifecycle down --volumes --remove-orphans
```

## 3. Timing harness (FR-060, SC-006)

```bash
python3 devcontainer.test/test-setup-render-timing.py
```

- Sources the script with a fixture catalog of all 12 benches carrying the draft copy, stubs the terminal to 88×40 (an 87×40 frame) and every status to a known state, opens the Benches bench zone and replays ↑, ↓, Tab and PgDn through `handle_input` + `draw_ui` (output to `/dev/null`), 100 samples timed in-shell with `$EPOCHREALTIME`.
- Prints the median, p90 and max key → redraw time, and the median render time of each of the six steps at 87×40.
- Fails when the median exceeds **100 ms** (the requirement). The plan's engineering target is **≤ 25 ms** median on Brett's workstation; a result between 25 and 100 ms passes but is worth a look.
- Local only: not in the CI job (spec Assumptions). Run it on the developer workstation (Brett's: AMD Ryzen AI MAX+ 395, WSL 2 Ubuntu 24.04, Bash 5.2) with no heavy load, and record the printed medians, the commit and the machine in `specs/029-setup-guided-wizard/release-qa.md`.
- Baselines measured during planning on that machine: 1.7 main screen ~250 ms per redraw; prototype Benches ~105 ms per redraw, ~130 ms per key; a fork-free Benches frame 3.8 ms ([research.md](research.md) R1).

The CI-safe companion is the no-fork check in `test-setup-wizard-layout.py`: render-path functions contain no command substitution, backtick, process substitution or pipeline.

## 4. Real-host QA hand-off (Brett; OpenSpec tasks 5.3 and 7.2)

The builder hands over a pushed candidate commit (the PR head) and this checklist. Brett runs it and the results go into `specs/029-setup-guided-wizard/release-qa.md` (who, date, commit, host, result).

1. **Native workstation acceptance** (disposable Docker-in-Docker engine, bootstraps the pushed ref from GitHub):

   ```bash
   WORKBENCHES_ACCEPTANCE_REF=029-setup-guided-wizard WORKBENCHES_ACCEPTANCE_SHA=<candidate sha> \
     docker compose -f devcontainer.test/docker-compose.yml --profile workstation-acceptance run --rm workstation-acceptance
   docker compose -f devcontainer.test/docker-compose.yml --profile workstation-acceptance down --volumes --remove-orphans
   ```

2. **WSL workstation acceptance** (explicit opt-in, frozen release mode, isolated engine socket):

   ```bash
   WORKBENCHES_WSL_ACCEPTANCE=1 WORKBENCHES_FROZEN=1 \
     python3 devcontainer.test/test-wsl-workstation-acceptance.py --repo <checkout> --report <dir> \
       --sha <candidate sha> --engine <disposable engine socket> --phase all
   ```

3. **365Bench through the TUI** on a disposable workstation: `./setup.sh`, → to Benches, ↓ to System Administration, Tab, Space on 365Bench, Enter, Enter; confirm it installs into `sysBenches/365Bench` and nothing ran in the workBenches root (SC-010).
4. **Glyphs by hand** in Windows Terminal and the VS Code terminal at 36, 80 and 120 columns: `✓ ⚠ … ● ○ ─ ▲ ▼ › · ⇄` each one column wide, borders aligned (spec Assumptions).
5. **Fresh-workstation walkthrough** (SC-012): from the first screen to a completed apply using only the on-screen nav and hints; every queued change visible on Review first.
6. **Bench copy approval** (FR-053, SC-013, merge gate): read every bench's tagline and About in the running TUI; approve or give edits. The builder applies edits, and the approval is recorded with who, date and commit before the PR merges.
7. **Timing** (section 3) on the developer workstation, recorded with the commit.

## Workstation lifecycle extension

Run `python3 devcontainer.test/test-workstation-lifecycle.py` for the additional native-plan, queue, ordering, ownership and data-preservation fixtures. The existing requirements suite loads these tests too, so CI covers them. Workstation uses Space/D → Review → Apply; --select-only saves without applying. Docker Desktop/WSL removals require manual host steps; fixture tests never change the real host.


### Harness category review (029-A06)

Harness now starts on categories. Tab enters TUI AI Tools before selecting an existing CLI; real-host Codex sequences add Tab between the second Right and the two Down keys. Browse GUI AI Tools, IDE extensions and Workflow with the same category/list controls as Benches. Tools groups Editors & IDEs together. New reference entries are manual-only: About supplies setup sources, presence is not login, and Space/D cannot queue them. Extension status targets only the local VS Code CLI default profile; Windows/WSL references require manual checking.


### Expanded catalog and CLI groups

The product inventory is governed by setup-agent-tool-catalog. Check or regenerate its static snapshots with `python3 scripts/setup-tool-catalog.py --check` / `--write`. Run `python3 devcontainer.test/test-tool-catalog.py` directly; the wizard suite also loads these tests so the existing CI job checks catalog coverage and snapshot drift without a workflow change.

Preview Harness → CLI/TUI Agent Harnesses, press F, choose an ownership group with up/down and Tab into its list. Check a long About and return via P/G, then refresh: group/item/list/About position and all selected managed changes stay intact. Browse GUI agents separately from IDEs/editors and extensions. Confirm product source qualifications and manual-only controls, including separate Kimi/Qoder identities. Do not infer model access, agent cooperation or active-session transfer from installation evidence.
