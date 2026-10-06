# Verification - 2026-10-06

Run in the feature worktree, cut from `origin/main` `c93f1a04`, inside the
devBench container, with stdin from `/dev/null`. The tests build their own
temporary fixtures, and no check reads the shape of any real repository.

## Totals before and after

| Check | Before (`c93f1a04`) | After (this branch) |
|---|---|---|
| `bash devBenches/devcontainer.test/test-openspeckit-bootstrap.sh` | exit 0, 793 PASS, 0 FAIL | exit 0, 966 PASS, 0 FAIL |
| `python3 devBenches/base-image/update-upstream.py check` | exit 0, "23 vendored copy(ies) match" | exit 0, "23 vendored copy(ies) match" |

- **Pre-existing assertions.** All 793 still pass, under identical labels once
  the random `mktemp` directory name is normalized: a sorted `diff` of the
  `PASS:` lines prints nothing.
- **New assertions: 173** (`PASS: Triad advisory ...`).
  - 62 are end-to-end runs with no terminal.
  - 48 are units loaded through `runpy`.
  - 63 drive a real pseudo-terminal from `os.openpty`.
- **Stability.** The whole script was run four times with the terminal cases
  included, and every run was green: three runs at 958 PASS, before the `no`
  case was added, and the final run at 966 PASS.

## What the new assertions prove

- **A single repository, no terminal.**
  - It exits 0 and prints the two-line advisory once, as `warning:` lines on
    stderr, naming `adopt-project.py` and `single-repository.yaml` and stating
    that the shape stays elective and confers nothing.
  - It asks nothing and writes no record.
  - Its tree is byte-, path-, type- and mode-identical to a twin repository
    silenced by a valid record (the record itself excepted). So the advisory
    changes nothing that the run writes.
- **Silence.** The advisory is not given in:
  - the existing Triad dry run, real run and rerun;
  - the family holder;
  - a Triad under `--shape off`;
  - a repository whose `origin` is `fixture-org/alice-wip`, checked out in a
    directory named `checkout`;
  - repositories that `workspace.yaml` names by `path:` (written with `~`) and
    by `repository:` (matched case-insensitively). The same two repositories
    get the advisory without that file, so nothing is guessed from a name or a
    place, and `workspace.yaml` is never written;
  - a valid record;
  - a leg clone, which instead receives "This checkout is the spec leg of a
    Triad (its AGENTS.md says so). ... move there and run setup-openspeckit in
    it."
- **`--shape off` on a single repository** still warns.
- **Unusable records.** A wrong kind, no kind, a directory and a symlink (never
  followed; its target is unchanged) each:
  - draw one `warning:` note naming the problem;
  - get the advisory;
  - exit 0.
- **A symlinked `AGENTS.md`** whose target carries a leg line. With
  `--no-repo-agent-pointers` it exits 0, gives the advisory, is not taken for a
  leg, and its target is unchanged.
- **At a terminal.** Enter, `maybe later`, `no`, `s` then Enter, `SHOW` then
  `no`, and end-of-file each:
  - show the advisory once, as plain text, followed by the question;
  - continue to `done` and exit 0;
  - write the same tree as the non-interactive run, and no record.

  The `s` answers show the `adopt-project.py` plan/check/execute steps, the
  record's fields, and the posture. An interrupt at the question ends the
  process by SIGINT (status -2 as Python reports it), prints "Stopped at your
  request; nothing was written.", and leaves the repository unchanged.
  `CI=true` on a terminal asks nothing and warns.
- **Units.**
  - the `<user>-wip` pattern, 4 matches and 7 rejections;
  - `origin` parsing for scp, https, ssh-with-slash and local-path remotes; no
    origin; a directory nested inside another repository; a missing directory;
  - `declares_triad`, including an unusable leg path read without validation;
  - `declares_family_holder` and `leg_clone_role`, including a quoted mention
    and a `project.yaml` beside a leg line;
  - every record state, including undecodable bytes and a non-ASCII kind
    reported in ASCII;
  - `is_interactive_run` under nine `CI` values, a redirected stdout and a
    closed stdin;
  - an advisory line written to an ASCII-only stream and to no stream at all
    never raises.

## Not run here

- `devBenches/devcontainer.test/test.sh`. It runs inside a built bench image
  and needs the `specify` CLI there. Its one `setup-openspeckit` line discards
  stdout and asserts nothing about stderr, so the new warning cannot change its
  result.
- The deferred fallback re-syncs (tasks.md D001-D003). They wait for
  brettheap/new-workstation#52.
