# Implementation Tasks

- [x] T001 Preserve all eighteen repository snapshots and verify recovery archives and parent bundle exist.
- [x] T002 Prepare and validate ten history fixes; all eleven primary/example configurations passed devcontainer and Compose environment/lifecycle checks in py-bench. Reviews prompted service-level HISTFILE and mounted-directory/file ownership initialization. Disposable containers proved root-owned volume migration and history persistence across recreation.
- [x] T003 Validate the separate Flutter SDK adjustment and required version increment; shell syntax, seven-package retry success, and retry exhaustion checks passed. Dockerfile header and layer.version label are 1.0.10. Final failed attempts no longer sleep or claim another retry. No image build or live activation was performed.
- [ ] T004 Preserve CloudBench evidence outside the checkout; verify its archive and absence of active users.
- [x] T005 Reconcile obsolete local profile branch and preserve active worktrees; the patch-equivalent local ref now matches its upstream after a recovery bundle. Four open-PR worktrees are preserved; container-only worktrees are locked against host pruning.
- [x] T006 Push child changes and request exact-head Codex review; parent PR 127 and eleven child PRs are recorded in protected recovery metadata. Resolve review findings and request review again after meaningful updates.
- [ ] T007 Merge reviewed, green children and synchronize original checkouts; verify no work was discarded.
- [ ] T008 Land parent governance and gitlink changes; verify all pins and upstream equality.
- [ ] T009 Assess Frappe maintenance requirements and either safely synchronize or record the specific approval gate.
- [ ] T010 Refresh the eighteen-repository audit and report remaining exceptions.
