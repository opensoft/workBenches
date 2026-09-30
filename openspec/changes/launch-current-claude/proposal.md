Status: ratified
Ratified by: Brett Heap, 2026-09-29, verbatim "ratify the OpenSpec change when it's green" (lane openXfactory-5 RULED line, 2026-09-29T16:16:17Z), at baseline `34979348`. Record: [review/ratification-2026-09-29.md](review/ratification-2026-09-29.md).

**AMENDMENT PENDING RULING (R1 to R5, 2026-09-30):** Copilot's review points that would change requirement or
scenario text after the ratify word were put to Brett Heap as RULING NEEDED on opensoft/workBenches#119:
[comment 5894243795](https://github.com/opensoft/workBenches/issues/119#issuecomment-5894243795) (R1, R2, R3) and
[comment 5894338733](https://github.com/opensoft/workBenches/issues/119#issuecomment-5894338733) (R4, R5). This pull
request carries R1 to R4 as proposed in `specs/` and holds R5 as ratified. It lands only on his words: "amend as
proposed" for R1 to R4, each of which may be ruled apart, and for R5 one of "amend as (a)", "amend as (b)" or
"keep as ratified". Until then the packet stands as ratified at `376ee6c`. Record:
[review/amendment-pending-2026-09-30.md](review/amendment-pending-2026-09-30.md).

## Why

A profile or lane launch can start an old Claude Code, and nothing notices
(opensoft/workBenches#119). `claude-profile` hands `lane-start` `CLAUDE_BIN`
when it is set, else the newest installed native version (#109), else
whatever `claude` comes first on `PATH`. Nothing in that chain compares
against the newest published version, and nothing updates.

A bench with no native versions directory has two npm installs competing on
`PATH`: the Layer 0 image's root-owned copy, frozen at the image build, and
the runtime user's own `$HOME/.npm-global` copy. Which one a lane gets depends
on the shell that launched it. The served model catalog loads when the process
starts, so a stale binary hides newer models: on 2026-09-29 a lane that had run
2.1.283 for 20+ hours lacked Sonnet 5.5 in `/model`, while a fresh `claude` on
the same account listed it. That session also kept running the binary npm had
replaced under it (its `/proc/<pid>/exe` link ended in ` (deleted)`), and
nothing told it to restart.

## What Changes

- **Per-user install at the Layer 3 build.** Layer 3 installs Claude Code at
  the version npm publishes as `latest` into the runtime user's own npm prefix,
  beside the Codex overlay. The Layer 0 install stays unchanged as the floor
  that satisfies the required-CLI contract. This is the
  `enable-user-codex-updates` shape, taking npm latest rather than the base
  version.
- **Every launch runs the update check before it starts a session.** The
  profile launcher resolves the executable through `claude-current`, the
  resolver that `opensoft/openRepoTools` installs with `openRepoTools
  --install`. The resolver reads npm's published version with a bounded
  timeout and reads every installed candidate's `--version` by absolute path.
  When every candidate is behind, it updates the user-writable install under a
  lock. It then returns the absolute path whose version equals the published
  one. Offline, the launch goes ahead on the highest installed version and
  says `UNVERIFIED`. A launch that is still behind after the update attempt is
  refused, and `CLAUDE_ALLOW_STALE=1` is the one escape.
- **No launch resolves `claude` through `PATH`** while `claude-current` is
  installed. The #109 native ordering stays only as the fallback for a launcher
  that finds no `claude-current`, and that launch says it is not verified.
- **Every launch says what launched**, as `claude <version> (verified against
  npm <published>)`. It hands `lane-start` the path and
  `CLAUDE_VERIFIED_VERSION`, which the register's launch and `RESUMED` line
  records (the `opensoft/openRepoTools` side).
- **A running session is told to restart.** The shared status line prints one
  green `RESTART NEEDED` line when the binary its session runs was replaced on
  disk, or is older than the installed one. The line comes from
  `claude-restart-check`, also from `opensoft/openRepoTools`. It only warns.
- **Unchanged:** the Layer 0 install in `base-image/install-ai-clis.sh`, the
  CLI's own auto-updater (it stays on), an explicit `CLAUDE_BIN` pin, and every
  running bench.

## Capabilities

### New Capabilities

- `user-managed-claude-updates`: Layer 3 user images provide a user-owned
  Claude Code installation at npm latest on top of the shared baseline.
- `claude-session-restart-notice`: the shared status line tells a running
  session that its binary moved on disk.

### Modified Capabilities

- `claude-profile-binary-selection` (introduced by the active change
  `prefer-updated-claude`): a launch runs the update check before it starts,
  resolves by absolute path through `claude-current` instead of `PATH`, and
  keeps the native ordering only as the fallback when `claude-current` is
  absent.
- `shared-ai-cli-tooling` (introduced by the active changes
  `refresh-shared-ai-cli-tooling` and `repair-ai-cli-runtime-layout`): the
  scenario "Bench inherits the baseline" requires every required CLI command
  to be present and runnable from the image-managed installation, and lets a
  Layer 3 user-owned `claude` or `codex` resolve first on `PATH` (R3, pending
  ruling).

## Rulings

Brett Heap, 2026-09-29, on #119:

- **Home** (comment 5891571111): the resolver, `lane-start`'s use of it and the
  restart check live in `opensoft/openRepoTools`. This repository keeps
  `claude-profile` calling that command at its binary resolution, with the
  native-version ordering as the fallback when it is absent.
- **Point 1, the image install** (comment 5893687866): keep the base image
  install of Claude Code, which satisfies the required-CLI contract and the
  bench tests and becomes the floor. Then install or update Claude Code to npm
  latest in the user's own npm prefix at the per-user container build.
  `claude-current` then launches the copy whose version equals npm, normally
  the user copy.
- **Point 2, verbatim** (comment 5893706470): "for 2, we can run update on
  every start, this ensures we have the latest models". This supersedes
  `prefer-updated-claude`'s rule that a launch does not run a synchronous
  network update, and its PATH fallback. Offline still launches, marked
  `UNVERIFIED`.
- **Added scope** (comment 5891361098): every running session gets a green
  restart notice in the status line. It warns and never acts.
- **The CLI auto-updater stays on** (comment 5891339280).

## Impact

- `user-layer/Dockerfile` and `user-layer/build.sh`: the user copy and its
  version resolution. Rebuilt Layer 3 images carry it. No running container is
  recreated by this change; recreation stays a separately authorized act.
- `base-image/files/claude-profile`: the binary resolution and the
  `lane-start` hand-off.
- `base-image/files/claude-statusline-command.sh`: the restart line. It is
  installed by `scripts/setup-claude-profiles.sh` as the profiles' shared
  `statusline-command.sh`.
- Their regression suites under `devcontainer.test/`. Per #105, the
  claude-profile suites have no CI of their own yet.
- Depends on `opensoft/openRepoTools` shipping `claude-current` and
  `claude-restart-check`. The launcher and the status line degrade without
  them.
- Sequencing: `claude-profile-binary-selection` exists only in the active
  change `prefer-updated-claude`, so this change archives after that one does.
  Archive refuses a MODIFIED or RENAMED delta whose target spec does not exist
  yet. Likewise `shared-ai-cli-tooling` exists only in the active changes
  `refresh-shared-ai-cli-tooling` and `repair-ai-cli-runtime-layout`, so this
  change also archives after both of them (R3, pending ruling).
- Implementation hands off to Speckit feature `016-launch-current-claude`, in
  a separate pull request that lands after this change is ratified.
