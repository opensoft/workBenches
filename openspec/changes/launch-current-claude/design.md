## Context

See [proposal.md](proposal.md) for the motivation and the rulings.

- `claude-profile` resolves the executable once, in the block after
  `latest_installed_claude()`. Its order is `CLAUDE_BIN`, then the newest
  native version under `$HOME/.local/share/claude/versions` (#109), then
  `command -v claude`. It exports the result to its tmux child and to
  `lane-start` as `CLAUDE_BIN`.
- Layer 0 installs Claude Code as root. npm 12's selective install-script
  policy skips the package's native-binary hook, so
  `base-image/install-ai-clis.sh` runs the package's `install.cjs` itself.
  `claude` is in `WORKBENCHES_REQUIRED_AI_CLIS`, and the Layer 0 build exits
  unsuccessfully without a runnable `claude`. The sysBenches inherited-CLI
  check and the cascade image tests check it too. That is why the ruling keeps
  this install.
- Layer 3 already has a user-owned npm prefix. `NPM_CONFIG_PREFIX` is the
  runtime user's `$HOME/.npm-global`, and its `bin` comes first on `PATH`
  (`enable-user-codex-updates`). The Codex copy's version is probed from the
  base image. Claude's comes from npm latest.
- Measured on py-bench, 2026-09-29: Claude runs the status line command
  through `/bin/sh -c`, and dash does not exec the command it is given. The
  script's parent is that shell, and the claude process is its grandparent.
  When npm replaces the package under a running session, the process's exe
  link points into npm's renamed temporary directory and ends in ` (deleted)`.
  The installed version therefore has to be read from the package's
  `package.json`, not from the exe path.
- `npm view @anthropic-ai/claude-code version` answered in 0.6 s on py-bench
  on 2026-09-29.

## Goals / Non-Goals

**Goals:**

- Every new profile or lane session starts on the Claude Code version that npm
  publishes as `latest`, or a newer one. The version is verified by
  `--version` and the executable is started by an absolute path.
- A fresh Layer 3 image already carries a user-owned copy at npm latest, so
  the launch-time update is usually a no-op.
- A running session learns at its next status line render that the disk moved
  under it.

**Non-Goals:**

- Remove or change the Layer 0 install, or the required-CLI contract.
- Disable the CLI's auto-updater.
- Stop, restart or clear a running session.
- Cover a bare `claude` typed in a shell.
- Change what an explicit `CLAUDE_BIN` pin does.
- Specify the resolver's internals. `claude-current` and
  `claude-restart-check` are `opensoft/openRepoTools` commands, and this
  change governs how this repository calls them.

## Decisions

1. **The resolver lives in `opensoft/openRepoTools`** (home ruling). This
   repository calls `claude-current` and `claude-restart-check` from `PATH`
   and never vendors them. A test seam may name either command's path.
2. **The Layer 3 version is npm latest at build time.** `user-layer/build.sh`
   resolves it with `npm view` under a bounded timeout and passes it as a build
   argument. A new npm release therefore also invalidates Docker's cache for
   that step. The lookup runs with the base image's own npm, so the build host
   needs no npm. `--claude-version VERSION` gives a direct caller an exact
   version. When the lookup fails, the build fails and names it, rather than
   baking a version nobody chose. Layer 3 already needs the registry for the
   Codex overlay, so this adds no new dependency. The version is not part of
   the Layer 3 recipe fingerprint: a new npm release does not by itself
   rebuild an image. The launch-time update keeps a running bench current,
   and the image copy is a fresher floor.
3. **The Layer 3 install mirrors Layer 0.** It installs the resolved version
   into the user prefix, runs the package's `install.cjs` when npm skipped it,
   and then requires `claude --version` to report the resolved version and
   `command -v claude` to resolve under the user prefix.
4. **Launch precedence in `claude-profile`:**
   1. An operator `CLAUDE_BIN` is a pin. It is passed through verbatim with no
      update check.
   2. A `CLAUDE_BIN` that this launcher exported from its own resolution is
      not a pin. It reaches later launches through the environment of the
      session it started, for example a `/ctx` respawn, and it is resolved
      again. The launcher marks its own export so that it can tell the two
      apart.
   3. When `claude-current` is on `PATH`, it resolves, and its exit status
      decides. Resolved: the launcher starts that path. Refused as stale: the
      launch refuses with the resolver's message. No candidate at all: the
      launcher reports `Claude CLI not found`, as it does today.
   4. When no `claude-current` is found, the launcher uses the #109 native
      ordering, then the pre-change `PATH` lookup. It prints one notice that
      the launch was not verified against npm, naming `openRepoTools
      --install`. The rulings retire the `PATH` fallback for a launch the
      resolver verifies. A host without openRepoTools still has to start
      something, and refusing there would stop every launch on it. The
      alternative is to refuse and name `openRepoTools --install`. This is the
      one reading the ratifier is asked to confirm.
5. **The update runs on every start, and it is bounded.** The check costs one
   `npm view` per launch, 0.6 s as measured, with a 10 s default timeout. An
   install runs only when every candidate is behind. It runs under a lock, so
   two lanes starting together do not race one npm install, and the second
   re-reads the candidates after it takes the lock. Point 2's ruling accepts
   this cost for current models.
6. **An equal candidate beats a newer one.** A candidate newer than the
   published version, such as a native update that ran ahead of the npm tag,
   still launches, marked as ahead. An equal candidate is preferred when both
   exist. Ahead is never a refusal.
7. **The restart notice comes from the status line, not the prompt guard.**
   The status line passes its JSON's `version` field to `claude-restart-check
   --running <version>` and prints the check's line first. The check finds the
   claude process by walking at most three parents. It warns when that
   process's exe link ends in ` (deleted)`, or when the installed version is
   newer than the running one. It prints nothing otherwise and always exits 0.
   The `UserPromptSubmit` guard is not used, because it runs at prompt submit
   and can block. The status line re-renders at the prompt and can only
   display.

## Risks / Trade-offs

- [npm is slow or down at launch] → The check is bounded, and the launch goes
  ahead `UNVERIFIED` rather than blocking.
- [A bad release reaches every new session at once] → `CLAUDE_BIN` pins a
  known-good executable, and `CLAUDE_ALLOW_STALE=1` accepts a stale one.
- [An update at one launch makes every other running session stale] → Each of
  them shows the restart line at its next render, and nothing is killed.
- [Two lanes launch at once] → The resolver's lock serializes the install.
- [Layer 3 needs the registry] → This is already true for the Codex overlay,
  and the build names the failed lookup.
- [No `/proc` on the host, for example macOS] → The restart check prints
  nothing.
- [`shared-ai-cli-tooling`'s scenario "Bench inherits the baseline" says every
  required command resolves from the image-managed installation, in Layer 2
  and Layer 3] → In Layer 3 that already stopped holding for `codex` when
  `enable-user-codex-updates` put the user prefix first on `PATH`, and it
  stops holding for `claude` here. The baseline stays installed, root-owned
  and runnable, as point 1's ruling keeps it. This change does not reword that
  scenario; it is named here so the ratifier sees it.

## Migration Plan

1. Land the `opensoft/openRepoTools` commands. `openRepoTools --install`
   places them.
2. Ratify this change, then land Speckit feature `016-launch-current-claude`:
   the launcher, the status line and Layer 3.
3. A new launch picks the resolver up at once wherever it is installed.
   Rebuilt Layer 3 images carry the user copy. A running bench is recreated
   only on a separate authorization.
4. Archive after `prefer-updated-claude` is archived and feature 016 has
   landed.

Rollback is a revert of the launcher hunk, which brings the native ordering
back, or a `CLAUDE_BIN` pin.
