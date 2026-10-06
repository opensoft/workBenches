# Tasks: setup-openspeckit advises a non-Triad repository at bootstrap

**Input**: [spec.md](spec.md) and [plan.md](plan.md) in
`specs/021-triad-shape-advisory/`

**Governing record**: opensoft/workBenches#138. The source is openxFactory's
ratified `prefer-triad-project-shape`, task 5.4, at `main` e6380965.

Format: `[ID] [P?] [Story] Description`. [P] means the task can run in parallel
with another [P] task.

## Phase 1: Setup

- [x] T001 Compute the next free feature number over `specs/` on `origin/main`,
  every remote head, local branches, worktrees, pull-request heads and history
  (workBenches#129). Then create the worktree from `origin/main` and the
  feature directory with `create-new-feature.sh --number 21`.
- [x] T002 Record the baseline: `test-openspeckit-bootstrap.sh` totals and
  `update-upstream.py check` on the untouched tree.

## Phase 2: Foundational

- [x] T003 In `devBenches/base-image/files/openspeckit/setup-openspeckit`, add
  the advisory constants and `read_root_text()`, a reader that never follows a
  symlink and never raises.

## Phase 3: User Story 1, the warning in a non-interactive run (P1)

- [x] T004 [US1] Add `triad_advisory_plan()` and `give_triad_advisory()`, and
  call them in `main()` straight after `resolve_project_shape()`, before the
  first write. Non-interactive output goes to stderr, prefixed `warning:`.
- [x] T005 [US1] Tests in
  `devBenches/devcontainer.test/test-openspeckit-bootstrap.sh`:
  - a single repository warns and exits 0;
  - twin repositories with and without a valid record are byte-identical apart
    from the record;
  - `--shape off` on a single repository warns.

## Phase 4: User Story 2, silence where the question is answered (P1)

- [x] T006 [US2] Add `declares_triad()`, `leg_clone_role()`,
  `origin_repository()`, `is_workspace_repository()` and
  `single_repository_record()`. A leg clone prints the move-to-root instruction
  in place of the advisory.
- [x] T007 [US2] Tests that the advisory stays silent for:
  - a Triad, including under `--shape off`;
  - a family holder;
  - a wip repository named by its `origin`;
  - a wip repository named by `workspace.yaml`;
  - a valid record;
  - a leg clone, which prints the instruction.

  Also a `runpy` unit block over the helpers.

## Phase 5: User Story 3, the question at a terminal (P2)

- [x] T008 [US3] Add `is_interactive_run()` and the question.
  - Enter, end-of-file and any unrecognised input continue.
  - `s` shows the steps, then asks once more.
  - An interrupt re-raises SIGINT before anything is written.
- [x] T009 [US3] Pseudo-terminal tests:
  - Enter, an unrecognised word, `s` then Enter, and end-of-file each continue
    and write the same tree;
  - an interrupt writes nothing;
  - `CI=true` on a terminal warns and asks nothing.

## Phase 6: User Story 4, malformed records are reported (P3)

- [x] T010 [US4] Tests: a wrong-kind record and a directory record each give
  one note and the advisory, and exit 0.

## Phase 7: Polish and delivery

- [x] T011 Run the whole `test-openspeckit-bootstrap.sh` and
  `update-upstream.py check`, and record both totals, before and after, in
  `verification.md`.
- [x] T012 Scan the diff for secrets, tokens and workstation absolute paths
  before pushing, because opensoft/workBenches is public.
- [x] T013 Commit with pathspecs and the lane trailers, push the branch, and
  open one pull request into `main` that says `Refs #138`. Then comment
  `@codex review`. It is held for Brett Heap's merge word.
  Done as opensoft/workBenches#139, opened from head `5988ad61`, with
  `@codex review` posted.

## Deferred, not part of this pull request

These are the second half of packet task 5.4. They come after
brettheap/new-workstation#52 (task 5.5, the shared protocol, issue #51) merges,
as their own pull request under #138.

- [x] D001 Re-sync `openspec_speckit_protocol()` byte-identical to the shared
  `openspec-speckit-workflow.md`. #52 adds about 40 lines to § Repository Shape
  and § Detecting the shape. The function is an f-string, so its braces are
  doubled.
  Done in opensoft/workBenches#140, after #52 merged as e081c5a. The rendering
  is byte-identical to the live file.
- [x] D002 Re-sync `project_agent_bootstrap_protocol()` with the shared
  `project-agent-bootstrap.md`. It is already two sections behind on `main`,
  which predates this feature. #52 adds a `## Non-Triad Advisory` section and a
  Script Status entry citing #138.
  Done in opensoft/workBenches#140. The rendering is byte-identical to the live
  file.
  D002 now tracks the corrected Script Status sentence from
  brettheap/new-workstation#53 (head 35623857). That sentence reads "is realized
  in the script under opensoft/workBenches#138.", and the stale "Until that
  lands, the installed script only logs `shape: single repository`." is gone.
  The rendering is byte-identical to `project-agent-bootstrap.md` at that head:
  14821 bytes, md5 692f68037aa27d17eeb6f460b194597d. #140 merges after #53, so
  the two match once both have landed.
- [x] D003 Re-sync `global_agent_entrypoint()` with the shared `AGENTS.md`, whose
  shape bullet #52 changes.
  Done in opensoft/workBenches#140. The shape bullet is byte-identical to the
  live one. The entrypoint as a whole stays a curated subset of `AGENTS.md`.

## Amendment, realized in this feature's own scope

- [x] D004 Realize stop-on-no, as ratified `design.md` D2 (openxFactory
  `a2dc658d`, lines 76-80) states it, verbatim:

  > **The interactive answer "no" is the person's own stop.** Taking the default
  > gives the run the person would have had without the advisory. Answering no
  > ends the run before it writes anything; that is the person choosing to stop,
  > not the advisory refusing, and the realization owner picks the exit status
  > for it with the rule that nothing reads that status as a verdict about the
  > repository.

  #139 shipped `no` as an unrecognised answer that continues. That departed
  from D2. The lane coordinator, acting as realization owner, ruled the
  correction.

  In `setup-openspeckit`, `TRIAD_STOP_ANSWERS = ("n", "no")`. Case is ignored,
  and so are surrounding spaces. At either question, such an answer takes
  Ctrl-C's path, `stop_at_the_triad_question()`: nothing has been written, the
  stop is said, and the run ends by SIGINT. That status is the platform's own
  for an interrupted process, and the advisory adds none. Both questions now
  read "n or Ctrl-C stops before anything is written".

  Pseudo-terminal tests cover these answers:
  - stopping: `n`, `no`, `NO` and ` No ` at the first question, and `s` then
    `n` and `steps` then `No`;
  - continuing: Enter, `y`, `yes`, an unrecognised word, `SHOW` then an
    unrecognised word, and end-of-file.

  `spec.md` decision 2 and User Story 3 are amended to match. Done in
  opensoft/workBenches#140.

## Dependencies

T001 → T002 → T003 → T004 → T006 → T008. Each test task follows its
implementation task. T011 to T013 come last.
