# Implementation Plan: setup-openspeckit advises a non-Triad repository at bootstrap

**Branch**: `021-triad-shape-advisory` | **Date**: 2026-10-06 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `specs/021-triad-shape-advisory/spec.md`

## Summary

Add the Triad advisory to `setup-openspeckit` directly after `main()` resolves
the shape and before its first write. A small classifier reads declared facts
only: the root `project.yaml`, `family.yaml`, `AGENTS.md` and
`single-repository.yaml`, the `origin` remote's name, and the person's
`workspace.yaml`. From these it decides whether to speak.

Outside a terminal, or under CI, the advisory is a two-line warning on stderr.
On a terminal it is followed by one question whose default and fallback are to
continue. The question offers only "show the steps", and the steps it shows are
text. Nothing is written, recorded or converted on its account, and no exit
status moves.

## Technical Context

**Language/Version**: Python 3, standard library only, in the existing script.
The test harness is bash with embedded Python, as before.

**Primary Dependencies**: None new. It uses `git` (already required) for
`remote get-url origin`, and `signal` from the standard library.

**Storage**: None. The advisory writes nothing.

**Testing**: `devBenches/devcontainer.test/test-openspeckit-bootstrap.sh`,
extended with end-to-end runs, a `runpy` unit block, and pseudo-terminal runs
driven from Python's `os.openpty`. Also
`python3 devBenches/base-image/update-upstream.py check`.

**Target Platform**: The devBench base image (`/usr/local/bin/setup-openspeckit`)
and any workstation that runs the script from source.

**Project Type**: CLI bootstrap script.

**Constraints**:

- It never changes an exit status or a written byte.
- Its reads never refuse the run. It uses its own no-follow reader rather than
  `read_destination_text`, whose symlink refusal raises `SystemExit`.
- Its output is ASCII only.

**Scale/Scope**: One script and one test script, plus this feature directory.

## Constitution Check

`.specify/memory/constitution.md` is the unfilled template, so there are no
gates to check. The governing constraints are the ratified requirements quoted
in spec.md, and the plan honors them:

- advise once, never block, never change an exit status;
- convert, create, write and record nothing;
- stay silent in exactly the five declared cases;
- never become a review input.

## Design

### Where it runs

In `main()`, immediately after `shape = resolve_project_shape(repo, args.shape)`
and before `ensure_agent_protocol_files`, the first write. A refusal that
already ends a run still happens first. That covers unsafe destinations, the
template-root preflight, `--shape on` in a single repository, and an unfetched
spec leg.

### Classifier, `triad_advisory_plan(repo, shape, agent_root) -> (give, notes)`

The checks run in this order:

1. Silent when `shape is not None`, which is the elected Triad under `auto` or
   `on`.
2. Silent when `declares_triad(repo)`. This reads `project.yaml`'s `kind`,
   `schema` and leg roles with the existing comment-stripping parser, without
   leg-path validation. It covers a Triad root under `--shape off`.
3. Silent for a family holder, using the existing `is_family_holder`.
4. Leg clone, from `leg_clone_role(repo)`. When there is no `project.yaml` and
   `AGENTS.md` has a line matching
   `^This is the \*\*(spec|code) leg\*\* of \S`, the advisory is not given and
   the move-to-root instruction is added to the notes.
5. Silent when `is_workspace_repository(repo, agent_root)`. That means either
   the `origin` repository name matches the openRepoShape `workspace` family
   pattern, or `workspace.yaml` names the repository by `path:` or
   `repository:`.
6. `single_repository_record(repo)`. A valid record is silent. An unreadable
   record, or one with the wrong `kind`, adds a note and the advisory is given.
7. Otherwise, the advisory is given.

All file reads go through `read_root_text(path)`. It returns `(text, problem)`,
uses `lstat` plus an `O_NOFOLLOW` open, and catches every `OSError` and
`UnicodeError`. `workspace.yaml` is the person's own configuration outside the
repository, so it is read with an ordinary `read_text` inside the same guard.

### Output and the question

`is_interactive_run()` is true when `CI` is unset or set to a false value, and
both `sys.stdin.isatty()` and `sys.stdout.isatty()` hold.

- **Non-interactive**: stdout is flushed. Then each note and advisory line goes
  to stderr, prefixed `warning: `.
- **Interactive**: the notes and advisory lines are printed to stdout, then the
  question is asked through `input()`.
  - Answer `s`, `show` or `steps` (any case): the steps are printed, then
    "Press Enter to continue" is asked.
  - `EOFError` continues.
  - `KeyboardInterrupt` prints one line, restores the default SIGINT handler and
    re-raises SIGINT against the process, so it ends exactly as an interrupt
    anywhere else in the script ends. If that returns, `SystemExit(130)`.

The steps restate openRepoShape's `adopt-project.py` plan/check/execute
sequence, with the repository path quoted, and the staying-single record's
fields. They say that converting is the project's decision and that the record
is optional and confers nothing.

### Tests (added near the existing shape tests)

1. **End-to-end, non-interactive** (stdin `/dev/null`, output to a log):
   - A single repository warns and exits 0.
   - Twin repositories, one with a valid record, both exit 0 and are
     byte-identical apart from the record. This proves the advisory changes
     nothing written.
   - A wrong-kind record and a directory record each warn with a note and
     exit 0.
   - A wip repository named by its remote, and another named by
     `workspace.yaml`, are both silent.
   - A leg clone is silent and prints the instruction.
   - `--shape off` on a single repository warns.
   - The existing Triad, family-holder and `--shape off` Triad logs carry no
     advisory.
   - `CI=true` on a pseudo-terminal warns and asks nothing.
2. **Unit (`runpy`)**:
   - `declares_triad`, `leg_clone_role`, `single_repository_record`, the wip
     pattern and `origin` parsing over several URL spellings;
   - `is_interactive_run` under `CI`;
   - a symlinked `AGENTS.md` and a symlinked record never raise.
3. **Pseudo-terminal**:
   - Enter, an unrecognised word, `s` then Enter, and end-of-file each reach
     `done`, exit 0, and produce the same tree as the non-interactive twin.
   - An interrupt at the question exits by SIGINT, and the repository is
     unchanged.

## Project Structure

### Documentation (this feature)

```text
specs/021-triad-shape-advisory/
├── spec.md          # what and why, with every open decision recorded
├── plan.md          # this file
├── tasks.md         # the executable task list, including the deferred re-sync
└── verification.md  # commands run and their results
```

This mirrors `specs/019-guard-claude-npm/`. There is no research, data model or
contracts file, because the feature has no data model and its contract is the
ratified text.

### Source Code (repository root)

```text
devBenches/base-image/files/openspeckit/setup-openspeckit      # the advisory
devBenches/devcontainer.test/test-openspeckit-bootstrap.sh     # its tests
```

**Structure Decision**: The change lives in the two files task 5.4 names. The
embedded fallbacks `openspec_speckit_protocol()`,
`project_agent_bootstrap_protocol()` and `global_agent_entrypoint()` are not
touched. They are deferred until brettheap/new-workstation#52 merges; see
tasks.md D001-D003.

## Process notes

- **Feature number 021.** The repository is exposed to the workBenches#129
  hazard, so the number was computed over all of these: `specs/` on
  `origin/main` (highest 019), every remote head (highest 019), local branches
  and worktrees (020 is held by another session's `020-default-claude-effort`),
  pull-request head branches, and `specs/` paths in all history. 021 appears in
  none of them. `create-new-feature.sh` was run with `--number 21`, because its
  auto-detection reads only `specs/` and would have issued 020.
- **The worktree.** It is `../speckit-worktrees/021-triad-shape-advisory`, the
  layout `.specify/extensions/git/git-config.yml` declares. It was cut from
  `origin/main` by `git worktree add`, not by the `before_specify` feature hook,
  because the hook runs from the shared root checkout and this feature must
  not touch it.
- **Files left out of the commits.** `.specify/feature.json` and the `AGENTS.md`
  SPECKIT block are not committed. This follows 019's precedent and avoids
  contention with the concurrent 020.

## Complexity Tracking

No constitution violations.
