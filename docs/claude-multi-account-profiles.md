# Claude multi-account profiles

workBenches can provision multiple Claude Code logins with separate credentials,
shared reusable capabilities, and session history shared only within a trust
family such as `personal`, `work`, or `client`. Every new workBenches user starts
with separate `work` and `personal` profiles. Additional account slots can be
added to the manifest when needed.

## New-machine setup

```bash
cp config/claude-profiles.example.json ~/.config/workbenches/claude-profiles.json
$EDITOR ~/.config/workbenches/claude-profiles.json
./scripts/setup-claude-profiles.sh
claude-profile list
claude-profile login work
claude-profile login personal
pclaude work
pclaude personal
```

Alternatively, collect or confirm each email interactively:

```bash
./scripts/setup-claude-profiles.sh --interactive
```

On first-run `setup.sh`, this questionnaire runs automatically. It asks for a
personal Claude login email, whether the workstation is used for company work,
the number of companies, and each company's name and work login email. It
creates `personal` plus one stable `work-<company>` profile per company. The
answers are account inventory only; passwords, OAuth tokens, and API keys are
never requested or written to the manifest.

After setup, launch the local credential manager with:

```bash
./scripts/check-ai-credentials.sh
```

The manager reads `~/.config/workbenches/claude-profiles.json` by default and
can start or verify each profile's isolated Claude login.

The manifest contains email addresses but no credentials. Claude stores OAuth
credentials inside each directory under `~/.claude-profiles/profiles/`.
An optional `profilePath`, such as `company-one/team/team-001` or
`company-one/max/max-001`, groups profile directories by company and account
class without changing the name accepted by `pclaude`.
The installer marks the profile's CLI onboarding as complete because login is
performed explicitly with `claude-profile login`; this prevents Claude's
first-run wizard from starting a second, redundant browser login.

`claude-profile` and `pclaude` are the same launcher. Every profile also has a
mode-`600` `.profile.json` containing its profile name, optional aliases,
family, and login email. Aliases are declared in the private manifest and may
be used anywhere the canonical profile name is accepted. This lets a bench
resolve a mounted profile without depending on a
host-only manifest symlink. Credentials and shared state remain under the
mounted `~/.claude-profiles` tree.

The setup creates this per-user structure:

```text
~/.claude-profiles/
|-- profiles/
|   |-- company-one/
|   |   |-- team/
|   |   |   `-- team-001/  # One login, settings, plugins, and cache
|   |   |-- max/
|   |   |   `-- max-001/   # A separately authenticated Max login
|   |   `-- xfactor/
|   |       `-- xfactor-001/
|   |-- company-two/
|   |   |-- team/
|   |   |-- max/
|   |   `-- xfactor/
|   `-- personal/   # Personal login, settings, plugins, and cache
|-- state/
|   |-- company-one/ # Company-only history, projects, plans, and tasks
|   |-- company-two/
|   `-- personal/   # Personal-only history, projects, plans, and tasks
`-- shared/         # Status panel, skills, agents, commands, and rules
```

The directories belong to the host workbench user and are bind-mounted at the
same home-relative path in each bench. Run setup as that user, not as `root`.
Existing named profiles are preserved; adopting the `work` and `personal`
names on an established machine should be handled as an explicit credential
and state migration rather than by renaming directories.

All profiles share `skills`, `agents`, `commands`, and `rules`. Profiles in the
same family share transcripts, prompt history, file history, plans, and tasks.
Use a unique family for each personal login when personal histories must remain
separate.
Credentials, settings, plugins, caches, and daemon state remain per profile.

Every profile receives the shared four-line Claude status panel. It reports the
selected profile as a compact label such as `Team002`, `Max001`, or
`xFactory001`, along with the worktree and Git branch, model and effort level,
context use, 5-hour and 7-day credit use, the exact tmux attach target, and
graphical countdowns to the 5-hour and 7-day reset times. The tmux field is
always the first panel segment so it remains visible when the terminal narrows.
The profile label
identifies the selected configuration directory; it does not independently
verify the account in the current credential. The 5-hour countdown shows
minutes remaining; the weekly countdown shows days remaining, switching to
hours under one day. Reset times use `America/Los_Angeles` by default and can
be changed with `STATUSLINE_TZ`. When Claude exposes a separate weekly Fable
limit, the panel shows both `7d All` and `7d Fable`. Because the standard
status-line payload contains only the aggregate weekly value, the Fable value
comes from Claude's read-only OAuth usage endpoint and is cached per profile
for 60 seconds.

The canonical renderer is
`base-image/files/claude-statusline-command.sh`. Profile setup installs it once
at `~/.claude-profiles/shared/statusline-command.sh`, and every profile links to
that shared copy. The compatibility path used by bare `claude` and `yolo`,
`~/.claude/statusline-command.sh`, links to the same renderer. The first setup
that adopts an existing regular compatibility script preserves it as
`statusline-command.sh.pre-workbenches-shared`. Update the canonical renderer
in workBenches, then rerun
`./scripts/setup-claude-profiles.sh` to propagate changes without rebuilding a
bench image. Mounted running benches see the updated shared file immediately;
Claude refreshes the panel on its configured 10-second interval.

The same renderer also publishes usage snapshots for two readers that have no
access to the statusline payload themselves: `claude-usage-guard.sh` (the
`UserPromptSubmit` hook that injects a context/rate-limit warning into the
model's own context) and the `claude-usage` command (the balance check behind
the Claude Model Roles and Usage Budget protocol). Every tick writes the
account-scoped `five_hour`/`fable_weekly` percentages and reset times to
`$HOME/.claude/usage-snapshots/profile.<key>.json`, where `<key>` is
`$CLAUDE_CONFIG_DIR` with every character outside `[A-Za-z0-9._-]` replaced by
`_`; the session's own context percentage goes to a session-keyed file
alongside it, since context is not shared across sessions the way account
rate limits are. Both writes are fail-quiet: a missing directory or a failed
write is swallowed and never changes the visible line. Because
`setup-claude-profiles.sh` reinstalls the shared status line from this file on
every run, the publisher has to live in `base-image/files/claude-statusline-command.sh`
itself — a patch applied only to the installed copy at
`~/.claude-profiles/shared/statusline-command.sh` does not survive the next
setup run. That is exactly what happened on 2026-09-11: the publisher existed
only in the deployed shared copy, a routine `setup-claude-profiles.sh` run
overwrote it with this file's then-unpatched contents, and every profile's
snapshot went stale until the shared copy was restored by hand.

Interactive `pclaude PROFILE` launches are tmux-backed by default when started
from a terminal outside tmux. The panel reserves its first segment for the
exact `tmux:<session>/<pane>` target, so AgentTower can use the session portion
with `tmux attach -t`. When Claude is not running in tmux, the panel explicitly
shows `[TMUX] none` instead of silently dropping the field. Set
`WORKBENCHES_CLAUDE_TMUX=off` for a direct interactive launch. Noninteractive
commands such as `mcp`, `doctor`, `--help`, `--version`, and `--print` remain
direct, and a `pclaude` command run inside an existing tmux session reuses it.

Pass `--lane <repo>-<n>` (or set `CLAUDE_LANE=<repo>-<n>` in the environment)
to hand the launch to `lane-start` instead of exec'ing Claude directly.
`lane-start` (from `opensoft/openRepoTools`, placed on `PATH` by
`openRepoTools --install`, which workBenches' own `./setup.sh` runs — lane-collision-protocol
Amendment 9(b)) renames the current tmux window to the
lane, records the lane in the lane register, and starts this same Claude
binary under this same profile with `--resume`/`--name <lane>` as appropriate.
Naming a lane while `lane-start` is not on `PATH` refuses with the fix instead
of launching an unnamed session.

Since lane-collision-protocol Amendment 8(c) the lane is also the default: a
`run` that starts a conversation and names no lane resolves one itself. First
the current tmux window's name, when `lanes-edit.sh register-row` says the
register has a row for it — handed to `lane-start` bare, exactly as an explicit
`--lane` always was, because the operator is standing in the lane's own window
and there is nothing to confirm. Failing that, and only inside tmux, the lane
this workstation last paused for a swap and has not resumed since
(`lanes-edit.sh swapped <workstation>`, first row) — handed over as
`--confirm`, so `lane-start` asks before it takes the window. That second lane
is a guess about a *window*, and taking it means renaming one, so outside tmux
it is not read at all. The window name is read before the tmux re-exec and
carried across it, since the new session's window is named for the command that
made it rather than for a lane. Both register reads are made with
`LANES_NO_FETCH=1`, so a launch never waits on the network.

With neither, the launch is exactly as described above plus one line saying how
to take a lane in this window — and not even that where the `SessionStart` hook
below is installed, since that hook says the same thing with the repository and
the number filled in. `--no-lane` (or `CLAUDE_NO_LANE=1`) opts out of the
resolution entirely and wins over `--lane`; a machine with no `lane-start` on
`PATH` has no lane estate and is neither asked nor told anything.

**Nothing in the resolution can refuse a launch, and the one question it can
ask has two answers that both start Claude.** A `lanes-edit.sh` with no
`swapped` subcommand, a `lane-start` with no `--confirm`, a missing
`lanes-edit.sh` and a launch outside tmux all fall back to the unchanged
behaviour. When `lane-start` *is* asked to confirm, the launcher runs it rather
than `exec`ing it: a `lane-start` that declines the window (exit 2) falls
through to a bare Claude with one line saying so, and a `lane-start` that took
the lane has its status handed back unchanged, so the launcher can never start
a second Claude behind the first. See `claude-profile --help` for the exact
options.

### The Amendment 8 `SessionStart` hook, and where skills have to live

Claude reads the configuration directory it is launched with, and every
`pclaude run` execs with `CLAUDE_CONFIG_DIR=<profile dir>`. So the harness
reads *that* directory's `settings.json` and *that* directory's `skills/`, and
neither `~/.claude/settings.json` nor `~/.claude/skills/` is consulted under
this launcher at all. Two consequences, both of which this launcher and
`scripts/setup-claude-profiles.sh` now handle:

- **The per-launch settings rewrite is additive for every hook kind but its
  own.** `configure_profile_runtime` sets `hooks.UserPromptSubmit` and leaves
  every other key under `hooks` untouched, so an entry written into a profile's
  `hooks.SessionStart` survives every subsequent launch. The launcher relies on
  that to *ensure* Amendment 8(e)'s `SessionStart` entry on every run, matched
  by its exact command string: an entry already carrying that command is left
  exactly as it is, whatever matcher or timeout it was given, and otherwise the
  entry is appended with `"matcher": "startup|resume|clear|fork"` and
  `"timeout": 5`. The entry is written only where
  `~/projects/xFactory/lanes-edit.sh` exists *and* has the `session-start`
  subcommand, so a machine without the lane estate — and one whose estate
  predates Amendment 8 — is left alone; a later install is picked up by the
  next launch, because the ensure runs on every one. Any installer that wants a
  hook to fire for profile launches should write it into the profile
  `settings.json` files the same way, not into `~/.claude/settings.json`.
- **Skills belong in the shared skills directory, and `openRepoTools --install`
  is the one thing that writes them.** Every profile's `skills` is a symlink to
  `~/.claude-profiles/shared/skills`, so one write there is visible to every
  profile at once. `--install` places `/lane-swap` at
  `${CLAUDE_PROFILES_HOME:-~/.claude-profiles}/shared/skills/lane-swap/SKILL.md`
  and a copy at `~/.claude/skills/lane-swap/SKILL.md` for a bare `claude`
  outside the launcher, both at 0644, idempotently and byte-compared.
  `scripts/setup-claude-profiles.sh` used to install that skill from its own
  vendored copy; lane-collision-protocol Amendment 9's adoption act 4b deleted
  that loop and the copy with it, because two installers of one file is a
  defect no exact-match idempotence can resolve. This script still creates the
  shared directory and still links each profile at it.
- **The bare-`claude` hook entry is `--install`'s too, and there is no second
  writer of it.** `claude-profile` ensures the `SessionStart` entry only in the
  profile it is about to exec into; `~/.claude/settings.json` — the one file a
  bare `claude` run reads — is merged by `openRepoTools --install`, which adds
  exactly one entry, by exact-string match on the command, additive beside
  every other hook kind, and writes the file back at mode 600. It refuses
  rather than repairing a file it cannot parse, and it refuses on an entry
  under `SessionStart` that itself runs `session-start` under a different
  command string. **Not on any differing command.** The clause is about a
  second program running the same hook verb, which merging beside would fire
  twice (R-A9-8, narrowed from `lanes-edit.sh` to the verb by R-A9-14 in the
  openRepoTools#24 review): an entry running `lanes-edit.sh who` competes with
  nothing and is not refused, and `~/bin/lane-hook.sh session-start` does
  compete and is. Measured, with an unrelated `~/bin/herdr-agent-state.sh
  session` already under `SessionStart`: `9 of 9 placed`, exit 0, the file left
  carrying both commands at mode 600. It computes the merge before it places
  anything, so a merge it cannot compute costs a whole install rather than half
  of one.
  Adoption act 4b deleted the ensure `scripts/setup-claude-profiles.sh` carried
  for the same file. **One path, one writer, in both halves:** a profile's
  `settings.json` is the launcher's, `~/.claude/settings.json` is
  `--install`'s, and the two never write one file.

**The command string is the idempotence key across all three places** —
`~/projects/xFactory/lanes-edit.sh session-start || true`, with
`"matcher": "startup|resume|clear|fork"` and `"timeout": 5` — byte for byte in
the launcher's per-profile ensure, in `--install`'s merge, and in Amendment
8(e) itself. A re-formatted quotation of a string whose only idempotence is
exact match is a second string; change it in one place and the others go
stale. Both writers are gated on `~/projects/xFactory/lanes-edit.sh` actually
having the `session-start` subcommand, so on a host whose estate has not been
repointed yet neither of them writes anything at all.

Profile launches default to
`xhigh` effort and always start Claude with `bypassPermissions` plus
`--dangerously-skip-permissions` (the most permissive Claude Code mode). The
launcher also passes `--allow-dangerously-skip-permissions`, keeping bypass in
the in-session Shift+Tab mode cycle if the user temporarily selects another
permission mode.

Do not resume the same Claude session concurrently from two profiles. Use email
magic-link authentication for mailbox aliases; Microsoft or Google SSO may
resolve an alias back to the mailbox's primary identity.

## Reproducing this setup in a new AI session

Tell the agent:

> Read `docs/claude-multi-account-profiles.md` and
> `config/claude-profiles.example.json`, then run the workBenches Claude profile
> setup for this machine. Do not copy OAuth credential files between accounts.
