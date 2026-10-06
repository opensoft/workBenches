# Feature Specification: setup-openspeckit advises a non-Triad repository at bootstrap

**Feature Branch**: `021-triad-shape-advisory`

**Created**: 2026-10-06

**Status**: Implemented, held for Brett Heap's merge word

**Input**: Task 5.4 ("the bootstrap") of openxFactory's ratified change
`prefer-triad-project-shape`, on opensoft/openxFactory `main`
`e63809650d39586134c4ec4fdb6e9effc87a7860`. The governing record here is
opensoft/workBenches#138, which extends the older shape-aware record #22.
Lane `codeXfactory-5`.

## Authority

Brett Heap said each of these to the lane, in session:

- 2026-10-06T10:20:12Z: "the triad should be the prefered structure and should
  prompt or warn the user if working on a non Triad repo."
- 2026-10-06T16:02:16Z: "ratify 1249 as recommended" (the change is ratified).
- 2026-10-06T17:31:10Z: "merge 1249" (the change is merged).
- 2026-10-06T17:41:18Z: "usage is fine, launch all four" (realization launched).

These authorize authoring and opening this feature's pull request. None of them
is a merge word for it.

## What the ratified text requires of this surface

The change's spec delta (`specs/project-repo-schema/spec.md`) is the source.
This feature realizes, for the workstation bootstrap only:

- **The preference with its posture.** The Triad is the preferred project shape,
  and preferred is not required. Wherever the preference is stated, the posture
  is stated with it: the shape stays elective and confers nothing. Human-facing
  text says "Triad"; no machine key, `kind`, field, file name or naming family
  is renamed.
- **The advisory's form at this surface.** The workstation bootstrap "SHALL
  print it as a warning in a non-interactive run, with its exit status
  unchanged, and in an interactive terminal SHALL ask before continuing, with
  continuing as the default answer". It names the way to convert
  (openRepoShape's `adopt-project.py`, run by a person deciding for that
  project) and the way to stop meeting it (the optional staying-single record).
  It converts nothing, creates nothing, writes nothing, and records nothing
  about having been given.
- **Silence where the question is answered or does not arise**, each read from a
  declared fact and never inferred: an elected Triad assembly root; a leg clone,
  where the instruction to move to the assembly root is given instead; a family
  holder; a `<user>-wip` workspace repository; a project that has recorded
  staying single. Every other repository, including aggregations,
  configuration or dotfile repositories and vendored forks, receives the
  advisory. "The list above is the whole list."
- **Never a review input.** No review lane, required check, validator, floor,
  merge gate, clearance or council reads the shape to pass, fail, warn in
  review output or change eligibility.

OQ-1 was ruled as recommended: the record is `single-repository.yaml` at the
repository root, carrying `schema_version: 1`, `kind:
single-repository-record`, `decided_by`, `decided_on`, `reason` and an optional
`revisit_on`, with its schema owned by openRepoShape. It is optional and never
owed, and its only reader is the advisory.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A scripted bootstrap in a single repository is warned and otherwise unchanged (Priority: P1)

A person, script or CI job runs `setup-openspeckit` in a single repository that
has not elected the Triad and is not exempt. The run prints the advisory as a
warning, writes exactly what it wrote before this feature, and exits with the
status it exited with before.

**Why this priority**: It is the commonest case, since nearly every estate
repository is single today, and it is the one the ratified text binds hardest:
the exit status and the written bytes must not move.

**Independent Test**: Bootstrap two identical single repositories
non-interactively, one carrying a valid staying-single record. Both exit 0, only
the first prints the advisory, and the two trees are byte-identical apart from
the record itself.

**Acceptance Scenarios**:

1. **Given** a single repository with no exemption, **When** the bootstrap runs
   with stdin or stdout not a terminal, **Then** the two advisory lines are
   printed as warnings, naming `adopt-project.py` and `single-repository.yaml`
   and stating that the shape stays elective and confers nothing.
2. **Given** the same run, **Then** it exits 0, and every file it writes is the
   file it writes for the same repository when the advisory is silent.
3. **Given** `CI` is set, **When** the bootstrap runs on a terminal, **Then** it
   warns and asks nothing.

---

### User Story 2 - The advisory is silent where the shape question is answered or does not arise (Priority: P1)

**Why this priority**: An advisory that speaks in a Triad, a family holder or a
workspace repository is false. One that ignores a recorded decision tells a
person something their project has already answered.

**Independent Test**: Bootstrap one fixture of each exempt kind and assert that
no advisory line appears.

**Acceptance Scenarios**:

1. **Given** an elected Triad assembly root, **When** the bootstrap runs,
   **Then** no advisory is given. This also holds under `--shape off`, because
   the exemption reads `project.yaml`'s declaration, not the layout chosen.
2. **Given** a family holder, **Then** no advisory is given.
3. **Given** a repository whose `origin` remote names a `<user>-wip`
   repository, or that the person's `workspace.yaml` names, **Then** no advisory
   is given.
4. **Given** a repository whose root `single-repository.yaml` carries `kind:
   single-repository-record`, **Then** no advisory is given.
5. **Given** a leg clone, **Then** no advisory is given, and the instruction to
   move to the Triad's assembly root is printed instead.

---

### User Story 3 - A person at a terminal is asked once, and continuing is the default (Priority: P2)

**Why this priority**: This is the "prompt" half of the direction. It touches
only interactive runs, and a person who presses Enter gets the run they would
have had anyway.

**Independent Test**: Drive the bootstrap through a pseudo-terminal. Answer
Enter, an unrecognised word, `s` followed by Enter, and end-of-file. Each run
continues to `done`, exits 0, and writes the same tree as a non-interactive
run. Sending an interrupt at the question ends the run before anything is
written.

**Acceptance Scenarios**:

1. **Given** stdin and stdout are terminals and `CI` is unset, **When** a
   non-exempt single repository is bootstrapped, **Then** the advisory is shown
   once, followed by one question whose default is to continue.
2. **When** the person presses Enter, types anything unrecognised (`no`
   included), or sends end-of-file, **Then** the run continues exactly as
   without the advisory.
3. **When** the person types `s`, **Then** the steps are shown: how to convert
   in place with `adopt-project.py`, and how to record staying single. The run
   then waits for one more Enter, and any answer continues.
4. **When** the person interrupts at the question, **Then** the run ends as an
   interrupt anywhere else in it ends, and nothing has been written.

---

### User Story 4 - A malformed staying-single record is reported, never fatal (Priority: P3)

**Acceptance Scenarios**:

1. **Given** a `single-repository.yaml` with the wrong `kind` or none, **Then**
   one note says so, the advisory is given, and the exit status is unchanged.
2. **Given** a `single-repository.yaml` that is a directory, a symlink or
   undecodable, **Then** one note says it cannot be read, the advisory is given,
   and the exit status is unchanged.

### Edge Cases

- A repository with no `origin` remote, no git at all, or one git refuses to read
  for ownership: the workspace test answers "not a workspace repository", and
  nothing fails.
- A missing, unreadable or malformed `workspace.yaml`: it names nothing, and
  nothing fails.
- A `project.yaml` that is not a Triad manifest (wrong `kind`, wrong `schema`,
  or a missing leg): the repository is single and gets the advisory. Nothing is
  guessed.
- A Triad root whose manifest has an unusable leg path, run under `--shape off`:
  silent. It declares the election, and the advisory reads the declaration
  without the layout's path validation, which `--shape off` never ran before
  either.
- `--shape on` in a single repository still refuses first, exactly as before.
  No advisory is given, because the run ends before the point where it is given.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: After resolving the shape and before its first write,
  `setup-openspeckit` MUST decide whether to give the advisory, and it MUST
  decide only from the declared facts listed in FR-004.
- **FR-002**: In a non-interactive run, the advisory MUST be printed as a
  two-line warning, and the run's writes and exit status MUST be those of the
  same run without it.
- **FR-003**: In an interactive run, the advisory MUST be followed by one
  question whose default and fallback are to continue. The question MUST NOT
  define an answer that converts, creates or writes anything.
- **FR-004**: The advisory MUST be silent for exactly these, and for nothing
  else:
  - a root `project.yaml` with `kind: project-manifest`, `schema:
    project-repo-schema`, and legs for `role: spec` and `role: code`;
  - a leg clone, which prints the move-to-root instruction instead;
  - a family holder (`family.yaml`, `kind: family-manifest`, and no
    `project.yaml`);
  - a `<user>-wip` repository;
  - a root `single-repository.yaml` with `kind: single-repository-record`.
- **FR-005**: A present `single-repository.yaml` that is unreadable or carries
  any other `kind` MUST NOT silence the advisory. It MUST be reported in one
  line, and the exit status MUST NOT change.
- **FR-006**: The advisory MUST state the posture (elective, confers nothing)
  beside the preference, and MUST call the shape the Triad.
- **FR-007**: Nothing MUST be recorded about the advisory having been given.
- **FR-008**: The tests MUST exercise every exemption, the warning, the wrong
  kind, the unreadable record, `--shape off`, and the interactive question
  through a real pseudo-terminal.

### Key Entities

- **Staying-single record**: `single-repository.yaml` at the repository root.
  The bootstrap reads its top-level `kind` and nothing else.
- **Workspace configuration**: `${AGENT_PROTOCOL_ROOT:-$HOME/.agents}/workspace.yaml`,
  read for `repository:` and `path:` only, and never written.

## Decisions the ratified text left open

Each decision is recorded here with its reason. The issue is #138.

The shared protocol's bootstrap contract leaves four choices to this
realization. That contract is task 5.5: issue brettheap/new-workstation#51 and
its pull request #52, which adds a "Non-Triad Advisory" section to
`project-agent-bootstrap.md`. The four choices are answered here:

- the output stream (decision 8);
- how a terminal is detected (decision 1);
- the exit status when the person declines to continue (decision 2);
- `--shape off` (decision 4).

The two things that contract fixes are honored as written:

- **The advisory comes before the bootstrap writes anything** (decision 11).
- **openRepoShape's own `make bootstrap` stays silent.** It is a different tool
  in another repository, and this feature does not touch it.

1. **What counts as interactive.** A run is interactive only when stdin and
   stdout are both terminals and `CI` is unset, empty, `0`, `false` or `no`.
   `setup-openspeckit` has no explicit non-interactive flag, and this feature
   adds none: a scripted run is already non-interactive by this test, and
   `< /dev/null` makes any run so.
2. **The question's answers, and how a person stops.**
   - Enter, end-of-file and any unrecognised input continue. `s`, `show` or
     `steps` shows the steps, then asks once more, and any answer continues.
   - No "no" answer is defined, and typing `no` continues like any other
     unrecognised input. The person's own stop is an interrupt (Ctrl-C), and the
     question names it ("Ctrl-C stops before anything is written"). It ends the
     run exactly as an interrupt anywhere else in it does, by re-raising SIGINT
     (shell status 130). Because the question comes before the first write,
     nothing has been written.
   - Why: `design.md` D2 leaves the stop's exit status to the realization owner,
     "with the rule that nothing reads that status as a verdict about the
     repository". The platform's own interrupt status is the one status the
     advisory does not add.
3. **Writing `single-repository.yaml` from the prompt is OUT of scope.**
   - The ratified requirement says that no surface writes "a manifest or a
     record on the advisory's account". A write offered from inside the
     advisory's own question is the closest reading of that phrase, and keeping
     the question write-free keeps the advisory "a sentence said to a person and
     not a state".
   - The record's schema and template are openRepoShape's (task 5.2), which is
     being realized in parallel. A writer here would fix the record's bytes
     before their owner publishes them.
   - `decided_by` names the person who decided for the project, as for an
     election. The person at a bootstrap terminal has not been shown to be that
     person, and `design.md` A3 rejected suppression held by one viewer.
   - Instead, the `s` answer shows the record's fields, so the advisory still
     names the way to stop meeting it.
4. **`--shape off` does NOT silence the advisory.** It is a layout choice, not a
   recorded decision. A Triad root bootstrapped with `--shape off` is still
   silent, because its exemption is read from `project.yaml`'s declaration
   rather than from the layout. `--shape on` is unchanged.
5. **How a leg clone is recognized.** A leg clone has no `project.yaml`, and its
   `AGENTS.md` carries a line that begins `This is the **spec leg** of` or `This
   is the **code leg** of`.
   - That line opens openRepoShape's `templates/spec-root/AGENTS.md` and
     `templates/code-root/AGENTS.md`, unchanged since they shipped in 99b3774.
     It opens all six legs of the estate's three Triads: openDox, openXdox and
     MedxEHR.
   - This is the shared protocol's rule ("its `AGENTS.md` says it is a leg of a
     project"). `setup-openspeckit` had no leg check before.
   - The bootstrap prints the move-to-root instruction in place of the advisory
     and otherwise runs as it did before. Making it refuse in a leg clone would
     change an exit status, and is not this feature.
6. **How a `<user>-wip` repository is recognized, offline and without
   openRepoShape.** Either test is enough:
   - The repository name of the `origin` remote matches
     `^[a-z0-9]+(?:-[a-z0-9]+)*-wip$`. That is the pattern of the `workspace`
     family in openRepoShape's `contracts/repository-naming.yaml`, which
     `scripts/validate-repository-naming.py` applies (openRepoShape `main`
     39d5c986). It is case-sensitive, as the policy is.
   - The person's `workspace.yaml` names the repository: `path:` (absolute or
     `~`-relative) resolves to the repository root, or `repository:` equals the
     `origin` remote's `owner/name`, compared case-insensitively as GitHub
     compares them.

   No directory name, other remote, or other heuristic is read.
7. **What makes a staying-single record valid.** Its top-level `kind:` reads
   `single-repository-record`, and the file is regular, readable UTF-8. No other
   field is validated: openRepoShape owns the schema, and a second validator
   here would be a second schema.
8. **Where the advisory is printed.**
   - Non-interactive: to stderr, each line prefixed `warning:`, with stdout
     flushed first so a combined log keeps its order.
   - Interactive: to stdout, the stream the interactive test proved to be the
     terminal, so the question can never land in a redirected file.
   - The text is ASCII only, so no locale can turn the advisory into an
     encoding failure that would change the exit status.
9. **The advisory's words.** They follow the reference meaning, adapted to two
   lines, and add "it stays elective and confers nothing". The modified
   requirement's restatement rule requires the posture wherever the preference
   is stated.
10. **Dry runs ask too.** The ratified text has no dry-run exception. A
    `--dry-run` run on a terminal asks the same question, and a scripted dry run
    warns.
11. **Exit-status order is unchanged.** Every refusal that already ends a run
    happens before the advisory, as before: an unsafe destination, a missing
    template root, `--shape on` in a single repository, or a three-leg root
    whose spec leg is not fetched.

## Out of Scope and Deferred

- **Deferred:** re-syncing the embedded fallbacks with the shared protocol.
  This is the second half of packet task 5.4. It follows the shared protocol's
  own pull request, brettheap/new-workstation#52 (issue #51), once that lands,
  as a separate follow-up under #138. Three embedded copies are owed, and this
  pull request re-syncs none of them:
  - `openspec_speckit_protocol()`, re-synced byte-identical to
    `openspec-speckit-workflow.md` after #52. That is about 40 new lines, with
    braces doubled because the function is an f-string.
  - `project_agent_bootstrap_protocol()`. It is already two sections behind the
    shared `project-agent-bootstrap.md` on `main`, a gap that predates this
    feature. #52 also adds a "Non-Triad Advisory" section and a Script Status
    entry citing #138.
  - `global_agent_entrypoint()`, which carries the shape bullet that #52
    changes in `AGENTS.md`.
- Writing `single-repository.yaml` (decision 3), refusing in a leg clone
  (decision 5), new-project creation (packet task 5.6), and openRepoShape's
  record schema and template (task 5.2).
- Any review, check or CI reading of a repository's shape. The new tests run
  inside the existing `regression` job over temporary fixtures only. No
  workflow reads the shape of workBenches or of any pull request under review.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Every pre-existing assertion of
  `devBenches/devcontainer.test/test-openspeckit-bootstrap.sh` still passes:
  793 before this feature.
- **SC-002**: The new assertions pass for each scenario above, including the
  pseudo-terminal runs.
- **SC-003**: `python3 devBenches/base-image/update-upstream.py check` still
  reports every vendored copy matching (23 before this feature).
- **SC-004**: No run changes its exit status or its written bytes because of
  the advisory.

## Assumptions

- `git` is on `PATH` wherever the bootstrap runs. Where it is not, the
  workspace test reads only `workspace.yaml`.
- A person's `workspace.yaml` follows the two-key form the bootstrap protocol
  documents: `repository:` and `path:`.
