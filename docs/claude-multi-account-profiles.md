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

Since lane-collision-protocol Amendment 11(1), the verb is optional:
`pclaude <profile>` and `pclaude run <profile>` build the identical argv. A
first word that is not one of the four actions — `list`, `login`, `status`, `run` — is
read as a profile, and only when it names one; the four action words win over
a profile of the same name, so a profile literally called `run` is reached as
`pclaude run run`. A first word that names neither an action nor a known
profile still exits 2 with `Unknown Claude profile: <name>` — the same words
`run` has always used, said one step earlier — so a typo is refused by name
rather than launched as something else. `--lane`, `--dir`, and `--no-lane`
stay LEADING options, read only before the action or the profile, so
everything meant for Claude itself passes through untouched.

Interactive `pclaude PROFILE` launches are tmux-backed by default when started
from a terminal outside tmux. The panel reserves its first segment for the
exact `tmux:<session>/<pane>` target, so AgentTower can use the session portion
with `tmux attach -t`. When Claude is not running in tmux, the panel explicitly
shows `[TMUX] none` instead of silently dropping the field. Set
`WORKBENCHES_CLAUDE_TMUX=off` for a direct interactive launch. Noninteractive
commands such as `mcp`, `doctor`, `--help`, `--version`, and `--print` remain
direct.

**The window is reused, never replaced (Amendment 11(2), act 1).** Run inside
tmux, the launcher creates no session of its own: it launches in the window
the operator is already sitting in and never renames it — renaming a window
is `lane-start`'s act, and only its act (Amendment 5(f)). So the window's name
and its tmux id both survive a restart, and the window-name step below fires
with zero questions. Run outside tmux there is no window to keep, and act 1 is
three steps. **One**, the lane is resolved *before* the session is created —
an explicit `--lane`/`CLAUDE_LANE` first, then the swap records' own window
refs, taking the first record whose window tmux resolves *now*, then the
newest swap as the guess it is. **Two**, where that lane's record names a
window that still exists, the launcher **respawns that window's pane** with
the launch command and attaches to its session instead of making one, so the
name and the id both survive; `-k` is used only where the window carries the
lane's own name, which is `lane-start`'s own word that the pane's process is
the session this restart replaces, and a plain `respawn-pane` that exits 1 is
not an error but the window being in use. A window the register knows as
*another* lane's is not taken at all. **Three**, failing both, a session is
created exactly as before, and where the lane is certain — `--lane` or
`CLAUDE_LANE`, the operator's own word — that new window is named for the lane
at birth with tmux's `automatic-rename` turned off, so the *next* restart
typed in it binds by name. What the parent resolved is never handed down as
the answer: a lane that was an inference still reaches `lane-start` as
`--confirm` in the child. Before Amendment 11, every outside-tmux
launch made a fresh session whose window tmux named for whatever command was
running in it instead — on Eagle, eight of sixteen live windows were simply
called `claude` when this was measured — so a restart could never bind by
window name and always fell to the swap record's one confirmation below.

Pass `--lane <repo>-<n>` (or set `CLAUDE_LANE=<repo>-<n>` in the environment)
to hand the launch to `lane-start` instead of exec'ing Claude directly.
`lane-start` (from `opensoft/brett-wip`'s `lanes/`, put on `PATH` by that
repository's `scripts/link-estates`) renames the current tmux window to the
lane, records the lane in the lane register, and starts this same Claude
binary under this same profile with `--resume`/`--name <lane>` as appropriate.
Naming a lane while `lane-start` is not on `PATH` refuses with the fix instead
of launching an unnamed session.

Since lane-collision-protocol Amendment 8(c) the lane is also the default: a
`run` that starts a conversation and names no lane resolves one itself. First
the current tmux window's name, when `lanes-edit.sh register-row` says the
register has a row for it — handed to `lane-start` bare, exactly as an explicit
`--lane` always was, because the operator is standing in the lane's own window
and there is nothing to confirm. Failing that, Amendment 11(2) adds one step:
the swap record whose `window` field names *this* window — its tmux id first,
else its `<session>:<index>` — which is not a guess either, but the same
certainty as the window's name, read from the record's side instead of the
window's, so it too goes to `lane-start` bare. **That step is read through
`lanes-edit.sh window-lane <@id>` / `<session>:<index>`, not through a parse of
the records this launcher makes for itself:** the same read answers for the
launcher, for `/restart` and for the `/lane-swap` skill's step 1, and two
implementations of one rule is how the three come to disagree about which lane
a window is. A `lanes-edit.sh` predating Amendment 11 has no such subcommand —
it says so and exits 2, which is an old helper, expected and silent — and a
read that *failed* names itself and falls to the **next** step rather than to
the bare-Claude end of the order. Failing both, and only inside
tmux, the lane this workstation last paused for a swap and has not resumed
since (`lanes-edit.sh swapped <workstation>`, first row) — handed over as
`--confirm`, so `lane-start` asks before it takes the window. That lane is a
guess about a *window*, and taking it means renaming one, so outside tmux it
is not read at all. The window's name and its id are both read before the
tmux re-exec and carried across it — on the reuse path they are the *reused*
window's, so the child comes up in a window the estate already knows; on the
fresh-session path a newly created window is named for the command that made
it unless the lane was certain. All three
register reads are made with `LANES_NO_FETCH=1`, so a launch never waits on
the network.

With neither, the launch is exactly as described above plus one line saying how
to take a lane in this window — and not even that where the `SessionStart` hook
below is installed, since that hook says the same thing with the repository and
the number filled in. `--no-lane` (or `CLAUDE_NO_LANE=1`) opts out of the
resolution entirely and wins over `--lane`; a machine with no `lane-start` on
`PATH` has no lane estate and is neither asked nor told anything.

**The lane's directory is resolved, not assumed (Amendment 11(3)).**
`lane-start`'s own default is `$PROJECTS_ROOT/<repo>`, and a checkout that
lives somewhere else used to end the launch outright:
`pclaude --lane openXfactory-5 run team01l` printed `[exited]` over a window
with no Claude in it, because that lane's checkout is `~/projects/xFactory/openxFactory`, not
`$PROJECTS_ROOT/openXfactory`. The launcher now learns the directory and
passes `--dir` when it can. **Four rungs, first answer wins, and there is no
fifth:** (1) `--dir <path>` — or the `CLAUDE_LANE_DIR` that carries the same
word across the re-exec into a new tmux session, which is one rung and two
spellings; (2) the `dir <path>` of *this lane's own* swap record, which the
swap writes from the live session's own record; (3) `lanes-edit.sh lane-dir
<lane>`, the directory the lane's log recorded at its last start; (4) nothing,
so `lane-start`'s own default `$PROJECTS_ROOT/<repo>` stands exactly as it did
before this existed. **The cwd's own checkout is not a rung and is ruled out by
name:** `lane-start` writes the lane's *home* into its Amendment 7 `STARTED`
line from that directory's `origin`, and every `#n` the lane afterwards writes
inherits it, so an inference that can silently re-home a lane is not worth the
refusal it saves — and the refusal names `--dir`, which is one word. Rungs 2
and 3 degrade silently against today's helpers, which do not record a directory
yet — `lanes-edit.sh swapped` prints no fourth field and `lane-dir` does not
exist — so both simply find nothing and rung 4 stands. A path containing a
space is written quoted and read back unquoted; one containing `, `, ` — ` or a
`"` is refused by the writer and never reaches a reader.

**Nothing here can close the window (Amendment 11(3)).** `lane-start` is now
*run*, never `exec`'d, on every path above that resolves a lane — before this,
only the swap-record confirmation ran it, and the window-name and `--lane`
paths still `exec`'ed it, byte for byte. `lane-start` refuses in exactly two
ways: exit 1 for its environment (no tmux, no register, no such directory) and
exit 2 for its own refusal (a bad argument, a name a window cannot take, a lane
already live elsewhere); every other status, including 0, is Claude's own,
because `lane-start` execs Claude itself once it succeeds. On a 1 or a 2,
`lane-start`'s own words are already on the terminal, the launcher adds one
line, and Claude starts bare in the same window — except where the window was
already named for the lane, in which case the rename `lane-start` would have
performed is a no-op, so a 1 or a 2 there could equally mean the lane's own
Claude just exited on its own terms, and the launcher cannot tell the two
apart. There, uniquely, the status is handed back unchanged rather than
covered over with a bare Claude, because a bare Claude started behind a
session that may still be the lane's would mint a new transcript in the
lane's own window — exactly the lineage fault the whole protocol exists to
prevent. See `claude-profile --help` for the exact options.

**`/swap`, manual and automatic (Amendment 11(4)).** `/swap` is an alias of
`/lane-swap` — the canonical name and its skill stay exactly where they are;
`/swap` is a one-line command file that invokes it, not a second copy.
`/lane-swap` remains the manual trigger for a usage reset or a profile switch.
Since Amendment 11(4), the usage guard (`claude-usage-guard.sh`, wired as the
`UserPromptSubmit` hook for every profile) turns its own top warning into a
directive at the same 95%-of-the-5-hour-window line that used to read only
"STOP at a breakpoint, write or refresh the handoff doc": at that point the
guard tells the session to run `/lane-swap` now, every step in order, with no
question put to the operator. The steps are Amendment 8(a)'s five, unchanged
— the identity triple derived; the handoff refreshed, committed, and pushed;
every running writer told to commit and push; the `PAUSED` swap record (now
carrying `dir` and `window`) together with the register's event line and the
row's state cell; and the one restart command printed — so the operator's
entire part in the restart is re-running `pclaude <profile>`. **The guard
performs no step of the swap itself** — it is a hook, it can put one line into
the session's context and nothing else — and **the directive fires only in a
session that HOLDS a lane.** That second fence matters because the guard is
wired for every profile and armed per *directory*: a bare `claude`, or a second
window in a lane's checkout, is armed too, and telling it to swap would have it
pause a lane it does not hold. `WORKBENCHES_CLAUDE_LANE` — exported by the
launcher only after `lane-start` took the lane, and unset again where
`lane-start` declined — is the fence, and the directive names the lane it is
about. Where the session carries no lane, the guard prints today's advice at
the same threshold and names nothing; the 90 and 80 lines, and the context
block, are unchanged for every session either way. The guard stays gated
exactly as before: silent unless `.claude/usage-guard.on` exists in the
session's working directory or an ancestor, up to `$HOME` (or
`~/.claude/usage-guard.on`, for every session on the machine). The Fable
weekly bucket's own 95% line is not part of this and keeps today's warning.

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
- **Skills belong in the shared skills directory.** Every profile's `skills` is
  a symlink to `~/.claude-profiles/shared/skills`, so one write there is
  visible to every profile at once. `scripts/setup-claude-profiles.sh` installs
  this repository's vendored skills — currently `/lane-swap`, from
  `base-image/files/claude/skills/` — into that directory and into
  `~/.claude/skills` for a bare `claude` outside the launcher. The copy is
  idempotent by content: a destination already holding the vendored bytes is
  left untouched.
- **The bare-`claude` path gets the hook too, from a second writer of the same
  entry.** `claude-profile` only ever ensures the `SessionStart` entry in the
  profile it is about to exec into, so a bare `claude` run — the one case
  `~/.claude/settings.json` exists for — used to get the skill above and
  nothing else. `scripts/setup-claude-profiles.sh` now ensures the identical
  entry (same command string, same `"matcher": "startup|resume|clear|fork"`,
  same `"timeout": 5`, same exact-string idempotence, additive beside every
  other hook kind) into `~/.claude/settings.json` on every setup run, gated on
  the same estate probe. The command string is the idempotence key for *both*
  writers of *both* files; change it in one and the other goes stale.

**Live state, so this section is not mistaken for a live measurement.** Both
writers above are gated on `~/projects/xFactory/lanes-edit.sh` having a
`session-start` subcommand, and on `opensoft/brett-wip` `main` that subcommand
does not exist yet — so today, correctly, neither writer ensures anything: no
profile `settings.json` under `~/.claude-profiles/profiles/` carries a
`SessionStart` hook, and `~/.claude/settings.json` only carries one where an
operator hand-wrote it before this script could. This section describes what
the code now does once the brett-wip half of Amendment 8 lands, not a
measurement of any workstation today.

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
