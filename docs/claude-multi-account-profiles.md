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
typed in it binds by name — and, since Evidence 3, created with `-c` the lane's
own directory where that is known, because the harness keys a session to the
directory its Claude runs in. `WORKBENCHES_CLAUDE_WINDOW_REUSE=off` turns step
two off for one launch, for the emergency where a record names a window that
must not be touched; the ownership fence above already refuses another lane's
window without it. What the parent resolved is never handed down as
the answer: a lane that was an inference still reaches only the picker in the
child (lane-collision-protocol Amendment 18 Addendum 1). Before Amendment 11,
every outside-tmux launch made a fresh session whose window tmux named for
whatever command was running in it instead — on Eagle, eight of sixteen live
windows were simply called `claude` when this was measured — so a restart
could never bind by window name and always fell to the picker below.

**The lane's session is NAMED by `lane-start`, which is why every path runs it
(new-workstation#20, Evidence 4).** Amendment 2 makes the Claude session's name
the lane's messaging address — the third leg of the identity triple, beside the
window's name and the transcript. Measured on `openRepoProject-1` on
2026-09-13: the transcript carries `customTitle: openRepoProject-1`, set once by
`/rename`, while every process that resumed it that day through a bare
`claude --resume <uuid>` carried a *derived* record name — `openrepoproject-b9`,
`-1e`, `-27`, `-45` — and the derived name is what the status line's
`session_name` and `ListAgents` display. So no surface here ever prints or execs
a bare `claude --resume` as the way back into a lane: the way back is
`pclaude <profile>`, which reaches `lane-start`. The bare Claude behind a refusal
is left **unnamed** on purpose, because it holds no lane, and naming it for one
would put the lane's own address on a session the register does not know.

**And `lane-start` names EVERY session it launches.** `--name "$LANE"` is on all
three of its launch branches — the two that RESUME, `claude --resume "$row_sid"`
(`lane-start:846`) and `claude --resume "$LANE"` (`:855`), as well as the one
that CREATES (`:866`) — since **adoption act 0** merged as `opensoft/brett-wip#5`
at `3719d97` on 2026-09-13, *"--name on every launch"*. That is the act **SPEC
rev 5 §13 act 0 item 2** assigns, and the line numbers above read back at that
commit. **An earlier revision of this paragraph gave the gap to the tooling PR
and said act 0 had left it open; both were false, and the correction is recorded
rather than quietly made** (`CF2-W1`). So a restart that goes through
`lane-start` — which is every restart this launcher makes where the tool is
there — comes up named for the lane, resume or not.

**What is left is the session that comes up WITHOUT `lane-start`**: the two
degradations this launcher documents — no `lane-start` on `PATH` (Evidence 5)
and a `lane-start` that refused, both of which start bare Claude in the same
window — a `claude` typed by hand, and a workstation whose `lane-start`
**predates `3719d97`**, since the fix lives in a checkout rather than in the
air. From inside a session already running
under a derived name, `/rename <lane>` is what fixes it — and **that act now has
two performers.** There is still no API to rename a running session, which is why
every surface HERE prints the act rather than performing it, and prints it
**conditionally** — *if its name is not the lane* — rather than always. But since
**Amendment 12** (the name guard, in force 2026-09-13T18:20:44Z) its
`UserPromptSubmit` guard and its `SessionStart` hook TYPE that same line into the
session's own tmux pane with `tmux send-keys` — a keystroke rather than an API —
and Amendment 11's own reconciliation section rules that **A12 governs the act
while this printed line is the fallback wherever that guard is not installed**,
which is every workstation until A12's adoption act 3 lands. Nothing here is the
only way, and nothing here performs it.

**What precedence step 3 can answer depends on the tmux server, and one case is
still owed to the helper (`RV-W7`).** Window ids are reissued from `@0` when the
server is replaced, so after a reboot every record the old server's sessions
wrote names a window that is gone: on Eagle at 15:5x on 2026-09-13, `@0`…`@4`
across five sessions, four of the five windows called `claude`, and all five swap
records naming sessions from the server that had just been replaced. That is the
**safe** half — nothing matches, the step answers nothing, and the launch falls
to the next one — and it is also why a restart taken right after a reboot still
meets the picker below. The unsafe half is this PR's ninth
divergence: a record carrying an `<@id>` whose `<session>:<index>` now belongs to
a *different* window would bind this lane to a stranger's window if it were
matched on the ref alone. The rule that closes it — *a record carrying an
`<@id>` is matched on its `<session>:<index>` only where the window now holding
that ref reports that same id* — belongs in `lanes-edit.sh window-lane`, where
the launcher, `/restart` and the `/lane-swap` skill share one implementation.
This PR **withdrew its own private copy** of that rule rather than keep a second
implementation of the one thing that stops the three callers disagreeing about
which lane a window is; `SPEC` rev 3 §5 now owns it and gives it to `window-lane`
(§11), and the tooling half implements it (§13.3). It is `RV-T6`/`RV-W7` on the two
reviews — `RV-T7` is the neighbouring rule, which scopes `window-lane` to the
asking workstation. **The helper now carries both**, read at
`opensoft/openRepoTools` `63a74af`: its `window_lane` continues past a record
whose recorded `<@id>` is not the id the window now holding that
`<session>:<index>` reports, and it answers a workstation that is not this one
from that workstation's records alone, because the window name and the liveness
fence are facts about the tmux server running here. This launcher matches
exactly what the helper answers and adds nothing of its own, which is why
nothing here changed when the helper arrived.

Pass `--lane <repo>-<n>` (or set `CLAUDE_LANE=<repo>-<n>` in the environment)
to hand the launch to `lane-start` instead of exec'ing Claude directly.
`lane-start` (from `opensoft/openRepoTools`, whose `--install` places it in
`~/.local/bin` — Amendment 9 act 3, merged as `63a74af`; before that act it came
from the workspace repository's own `lanes/`, and on a host that has not re-run
`--install` that repository's `scripts/link-estates` is still what puts the
helpers on `PATH`) renames the current tmux window to the
lane, records the lane in the lane register, and starts this same Claude
binary under this same profile — with `--name "$LANE"` on **every** branch it
launches, the two that `--resume` an existing transcript as well as the one that
starts a new session, since **adoption act 0** merged as `opensoft/brett-wip#5`
at `3719d97` (`lane-start:846`, `:855`, `:866` at that head; the same three
branches are `:1559`, `:1568` and `:1579` of the copy `openRepoTools` `63a74af`
installs, which is the one a host runs today), exactly as the `lane-start`
paragraph above says. **An earlier revision of this sentence split the two** and
sent the reader up to Evidence 4 to decide which was which; act 0 abolished that
distinction and the correction is recorded rather than quietly made (`CF3-W2`,
the residue of `CF2-W1`). The superseded wording is kept in the assertion that
now refuses it, `test-claude-profile-amendment-11.sh`'s doc audit, so that no
copy of it survives in a document a person reads.
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
the bare-Claude end of the order. **Failing both, and only inside tmux, THE
PICKER** (lane-collision-protocol Amendment 18 Addendum 1, clause (i-5)):
`lane` (`opensoft/openRepoTools#43`), on `PATH`, given a terminal to ask on,
lists this checkout's lanes — or, standing outside every checkout, every
repository — as a numbered pick, asks one question, and acts on the pick
itself: an available lane through `lane-start`, a lane live here through the
attach, a lane bound elsewhere through the handoff request. So this launcher
hands it the pane and **stops** — no `--dir`, no `--confirm`, nothing else —
and exits with whatever `lane` decided. `lane`'s own exit 0 covers both the
pick being acted on *and* a decline (`q`, or a blank line) at a question that
had at least one lane to offer; exit 8 is narrower than "the operator
quit" — it means there was *nothing* to pick at all, whether that came back as
a listing, as a `q`/`f`-only question, or as a decline of one of those. Either
way this launcher starts nothing here; only exit 2, a refusal — or the two
statuses `lane --help` documents and this launcher does not special-case, a
read that failed and a usage error the bare form here cannot trigger — falls
through to the plain session below, exactly as no `lane` on `PATH` or no
terminal already does. This step reads no swap record at all any more:
confirming the workstation's newest one is what put `openRepoShape-2` — a
person's own lane, but not the one they wanted — in front of an operator who
typed `pclaude team-01b` on 2026-09-14T12:04Z, whose `N` three minutes later
fell back to a bare resume (`opensoft/workBenches#77`); `lane` asks instead of
guessing, so a lane taken here was always the one the operator picked. The
window's name and its id are both read before the tmux re-exec and carried
across it — on the reuse path they are the *reused* window's, so the child
comes up in a window the estate already knows; on the fresh-session path a
newly created window is named for the command that made it unless the lane was
certain. Both register reads (the window's name and the window's record) are
made with `LANES_NO_FETCH=1`, so a launch never waits on the network.

With neither, the launch is exactly as described above plus one line saying how
to take a lane in this window — and not even that where the `SessionStart` hook
below is installed, since that hook says the same thing with the repository and
the number filled in. `--no-lane` (or `CLAUDE_NO_LANE=1`) opts out of the
resolution entirely and wins over `--lane`, and a launch that starts no
conversation at all takes no lane in the first place; neither is told anything,
because neither is a degradation.

**A missing `lane-start` is said, not passed over (new-workstation#20, Evidence
5).** Where the tool is not on `PATH` there is no lane to take, and the launch
still happens — but the **first** line it prints says so and names the one
install act. **Which act that is, is decided by capability and not by which
amendment is in force** (`R-A11-13`, A11 Addendum 3, ratified by Brett Heap
2026-09-13 *"a11 addendum 3 yes"*): the installed `openRepoTools --help` is
asked, and a copy that lists the lane tools is their placer, so the line names
`openRepoTools --install` — the act workBenches' own `setup.sh` already runs, so
the fix is a step this estate has and never a second installer. A copy that does
not list them cannot fix the machine, whatever the amendment says, so the line
names the `scripts/link-estates` of the repository `~/.agents/workspace.yaml`
names, with the `git clone` in front of it only where that checkout is not there
yet. Neither spelling is `link-estates` on its own — a script inside a
repository, with no repository named in front of it, is not an act anyone can
run — and neither is a repository this launcher chose for the operator.

**And the interval has two ends** (`CF2-W11`). It opens with the installed
`openRepoTools` not listing the lane tools and it closes twice over: with
Amendment 9 **act 3**, when `--install`'s list grows to carry them, and with
Amendment 9 **act 5** (`opensoft/brett-wip#6`, *"the workspace repository keeps
data only"*), which **deletes `scripts/link-estates`** from the workspace
repository. **Act 3 has since merged** as `opensoft/openRepoTools` `63a74af`,
and on a host that has re-run `--install` the first end has arrived: measured
here 2026-09-14, `openRepoTools --help` lists `lane-start` and the resolver
answers `openRepoTools --install` from the capability branch, which is the
branch the amendment wants asked. Those are not the same event as the probe, which reads the
*installed* copy's `--help`, so a host that has not re-run `--install` since act
3 merged is still on the fallback when act 5 lands. In that state — the checkout
present, its script gone — the line names `openRepoTools --install` with the
reason beside it and **never a path that is not there**, and never a `git clone`
of a checkout the operator is standing in. The clone form is fenced on the
checkout not existing, which is the only state it was ever right for.

This branch used to return in silence, on
the reasoning that a machine with no lane estate should not hear about one; that
was measured wrong. When this workstation was rebuilt on 2026-09-13 the
`~/.local/bin` symlinks were gone while `/usr/local/bin/claude-profile` was
still in place, so every restart took this branch and came up with no register
stamp, a record name the harness derived for itself and a window still called
`claude` — three times in one afternoon, with nothing said, because
`--resume <uuid>` went on continuing the right transcript. The launcher cannot
tell a machine that never had the estate from one whose links vanished this
morning, which is exactly why it states the fact instead of choosing between
them. The note does **not** stand down for the `SessionStart` hook the way the
no-lane notice does: that hook reports the lane it could not bind, and nothing
but this line can say the tool itself is missing.

**The workstation those records are keyed to is configured, never taken from
`hostname` inside a container (new-workstation#20, Evidence 6).** The
directory order's rung two and act 1's own window-reuse guess read
`lanes-edit.sh swapped <workstation>` — step four of the lane order no longer
does, since lane-collision-protocol Amendment 18 Addendum 1 replaced its
swap-record guess with the picker — and the swap records this machine wrote
say `Eagle`. Inside a bench container `hostname -s` is the
container's id — `0e7d1a79a07e`, as measured on 2026-09-13 — so a launcher that
passes it asks for the records of a machine that has existed for an hour, gets
nothing, and falls through with no reason given; and a *writer* that passes it
puts that id into an append-only log, which is what the forked orchestrator of
Evidence 6 did. `LANES_WORKSTATION` is honoured everywhere, container or not.
Failing that, `hostname` stands exactly as it did — but only where this is not a
container; inside one with nothing configured the records are **not read**, and
the launcher's one line names the gap and `LANES_WORKSTATION`.

**What a person does on each host, once — and usually nothing.** The name is
not read from a file and there is no file to write: the amendment rejects a
`workstation:` key in `workspace.yaml` by name, calling such a key
*"a SECOND PLACE FOR THE TRUTH TO BE WRONG beside the variable the launcher already sets"*. So wherever
the host's own `hostname -s` already IS the name the register is keyed to,
there is nothing to do and this launcher exports that. Where the two differ —
Eagle and Raven are keyed by those names, and a host whose `hostname -s` says
something else would key its rows to a machine no reader knows — the act is one
exported variable in the **host's** login shell, never inside a bench container
and never in this repository:

```sh
echo 'export LANES_WORKSTATION=Eagle' >> ~/.zshrc   # and Raven, on Raven
```

An already-set value always wins, so that one line reaches every session and
every bench container this launcher starts. To read back what a shell is
carrying, `lanes-edit.sh workstation` prints `<name><TAB><source>` — `seam`
where the variable is set, `hostname` on a host where it is not, and
`container-unset` inside a container where it is not, which is the one answer
every writer refuses on.

**And this launcher is what SETS it** (`R-A11-14`, A11 Addendum 3, ratified by
Brett Heap 2026-09-13 *"a11 addendum 3 yes"*). Before this the reader honoured
`LANES_WORKSTATION`, every writer refused without it, and nothing on the estate
wrote it — a contract with no owner, which inside a bench container means every
lane write stops. The owner is the launcher, because it is the one process that
runs on the **host**: `claude-profile` resolves the name once (configured value
first, `hostname -s` only where this is not a container) and **exports** it into
the session it starts, threading it across the tmux re-exec beside the window's
name and id; `scripts/wave-container-shell.sh` passes the same value through
`docker exec` into the bench container it opens, resolved before that script
assigns `container` for its own purposes — the systemd container marker is an
environment variable of exactly that name. An already-set value always wins.
Where there is no answer at all, **nothing is exported and nothing is
invented**: the `/lane-swap` skill and every other writer then **refuse**, in
one line that names `LANES_WORKSTATION` and the launcher that sets it, because
the register and the object log are both append-only and a workstation that is
not a workstation is wrong for ever. **The row's own state cell is refused with
them** (`R-A11-27`, A11 Addendum 4 ruling 11, ratified 2026-09-13T21:08:26Z
*"a11 addendum 4 yes"*): the flip is a register write too, and the helper keys
the commit it files for it on the workstation, so leaving it running would put
the container id in the register's own history through the one write that had
been spared. An earlier revision of this paragraph said it was still flipped.
What survives instead is the **handoff** — a commit in the lane's own
repository, keyed on no workstation — refreshed with the gap named in it, which
is where Amendment 8(a) step 4's *"never left unwritten"* keeps its substance
from a container; the swap also still polls the writers and still prints the one
restart command, with `--lane` in it because the row was never flipped.
`@unknown-workstation` and
`none recorded` are **gone from the skill**: the first is a word that is plainly
not a hostname in the position `swapped <ws>` keys on and `append-line`
validates neither half, so it would have landed and no reader would ever have
caught it; the second put a space inside a field Amendment 7(b) gives one
transcript uuid, which that clause has *reported* as `unreadable`. Where there
is no uuid the session field is **left out** and the line's own free text says
so.

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
and 3 degrade silently against a helper that records no directory — one
predating `opensoft/openRepoTools` `63a74af`, where `lanes-edit.sh swapped`
prints no fourth field and `lane-dir` does not exist, so both simply find
nothing and rung 4 stands. **That helper has landed**, and the two rungs are
measured rather than predicted from here on: at `63a74af` `swapped <ws>` prints
five tab-separated fields — `<lane>`, `<UTC>`, `<window>`, `<dir>`, `<profile>`
— with the fourth empty on every row written before the cutover, and `lane-dir
<lane>` exits 0 with an absolute path for a lane whose log carries one and 8 for
a lane that does not. So rung 2 still falls through on this workstation's own
rows and **rung 3 now answers**, which is what the order was written for and
changed nothing in the launcher when it happened. A path containing a
space is written quoted and read back unquoted; one containing `, `, ` — `, `; `
or a `"` is refused by the writer and never reaches a reader. **The
semicolon-space is on that list for `dir` and `profile` and deliberately not for
`window`** (SPEC rev 6 §5): `; ` separates a payload's sub-fields, so a `dir` of
`/a; b` reads back as a `dir` of `/a` followed by a sub-field `b` no reader
knows — the same lost fact one level down that `, ` causes one level up — while
a `profile` name is checked against `^[A-Za-z0-9._-]+$`, which admits neither a
semicolon nor a space, so one carrying either is omitted rather than written.
`window` keeps Amendment 8(b)'s own list because its value is a launcher-built
session name, an index and an `<@id>`, and widening it would be a seventh edit
to in-force text where the ratified count is six. The residue is named rather
than hidden: a tmux session name containing `; ` would split the payload the
same way, and that is A8(b)'s list to widen on the day something can produce
such a name. A reader following this contract can build no value the writer
silently drops.

**And the launch runs in that directory.** The harness keys a session to the
directory its Claude runs in, so a lane started somewhere else comes up without
that repository's `CLAUDE.md` and without the lane's own memory — while
`--resume <uuid>` still continues the right transcript, which is why it is easy
to miss. This lane's second restart on 2026-09-13 was typed from `/workspace`:
the launcher made its tmux session there, and the session came up with none of
its instructions (new-workstation#20, Evidence 3). The directory the order
above resolved is therefore **entered** before `lane-start` is run — and so
before the Claude `lane-start` execs, and before the bare Claude behind a
refusal — and a new tmux session is created with `-c` that directory.
**A recorded directory that is gone is a refusal that names the path**, never a
quiet fall to rung 4: `lane-start` writes the lane's home from the tree it
starts in, so falling through to `$PROJECTS_ROOT/<repo>` where that is a
different tree re-homes the lane silently. Rungs 2 and 3 are read for what they
say and are not tested for existence, exactly as rung 1 already was. Where
nothing was learnt there is nothing to enter, and the launcher says so in the
one line it prints, naming `--dir`.

**No path the launcher opened exits the pane (Amendment 11(3)).** `lane-start` is now
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
prevent. That last arm stops at the one place it would empty a pane: where this
process is the only command of a window the launcher itself **made** — the tmux
session it created or the recorded pane it respawned, both marked
`WORKBENCHES_CLAUDE_TMUX_CHILD` — there is no prompt behind the refusal, so the
lane is dropped and Claude starts bare in the window instead.

**The scope of that promise, exactly, and the case that used to fall outside it**
(`RV-W3`, closed by `R-A11-16` — A11 Addendum 3, ratified by Brett Heap
2026-09-13 *"a11 addendum 3 yes"*). The promise is held wherever this process is
**the only command of its pane**. `WORKBENCHES_CLAUDE_TMUX_CHILD` — set by both
of act 1's paths, the session it created and the pane it respawned — is the fast
path and answers most of them. The case it could not answer was real: a window
whose only command is `pclaude` and which the launcher did **not** create (`tmux
new-window -n <lane> 'pclaude <profile>'`, a tmux configuration line, a pane
respawned by hand) carries no such mark, so a `lane-start` refusal in a window
already named for the lane was handed back and tmux printed `[exited]` over a
window with no Claude in it. The fence is now a **pane-level** one: failing the
marker, the launcher reads the pane's own root process (`#{pane_pid}`) and walks
this process's ancestry towards it, through this launcher and the shell wrapper
tmux may have made to run it and through nothing else. Reaching the pane's root
that way means there is no prompt behind this process, so the lane is dropped
and Claude starts bare. Meeting a command of its own on the way — the shell you
typed `pclaude` into — stops the walk, and the refusal is handed back to that
prompt, which is the behaviour that must not change: a bare Claude started
behind a session that may still be the lane's would mint a second transcript in
the lane's own window. Every failure of the pane read (no `ps`, a tmux that will
not answer, a walk that runs out of depth) answers *not the root*, so it can
only close that door and never open another. See `claude-profile --help` for the
exact options.

**`/swap`, manual and automatic (Amendment 11(4)).** `/swap` is an alias of
`/lane-swap` — the canonical name and its skill stay exactly where they are;
`/swap` is a one-line command file that invokes it, not a second copy.
`/lane-swap` remains the manual trigger for a usage reset or a profile switch.
Since Amendment 11(4), the usage guard (`claude-usage-guard.sh`, wired as the
`UserPromptSubmit` hook for every profile) turns its own top warning into a
directive at the same 95%-of-the-5-hour-window line that used to read only
"STOP at a breakpoint, write or refresh the handoff doc": at that point the
guard tells the session to run `/handoff` (alias `/lane-swap`) now, every step
in order, with no question put to the operator. The steps are Amendment 8(a)'s
five, unchanged
— the identity triple derived; the handoff refreshed, committed, and pushed;
every running writer told to commit and push; the `PAUSED` swap record (now
carrying `dir`, `window` and `profile`) together with the register's event line and the
row's state cell; and the one restart command printed — so the operator's
entire part in the restart is re-running `pclaude <profile>`. **The guard
performs no step of the swap itself** — it is a hook, it can put one line into
the session's context and nothing else — and **the directive fires only in a
session that HOLDS a lane.** That second fence matters because the guard is
wired for every profile and armed per *directory*: a second window in a lane's
checkout, or the bare Claude this launcher starts behind a `lane-start` refusal,
is armed too, and telling it to swap would have it pause a lane it does not hold.
(A `claude` typed by hand is a different case and is **not** covered: it reads
`~/.claude`, which `scripts/setup-claude-profiles.sh` gives the shared status
line and the `SessionStart` entry and **no** `UserPromptSubmit` entry, so the
guard never runs there at all. That is the wiring's scope stated rather than
assumed — the automatic swap is a **launcher-managed profile** behaviour.) `WORKBENCHES_CLAUDE_LANE` — exported by the
launcher only after `lane-start` took the lane, and unset again where
`lane-start` declined — is the fence, and the directive names the lane it is
about. Where the session carries no lane, the guard prints today's advice at
the same threshold and names nothing; the 90 and 80 lines, and the context
block, are unchanged for every session either way. The guard stays gated
exactly as before: silent unless `.claude/usage-guard.on` exists in the
session's working directory or an ancestor, up to `$HOME` (or
`~/.claude/usage-guard.on`, for every session on the machine).
`configure_profile_runtime` now places that global flag itself — on every
launch that wires the guard, `$HOME/.claude/usage-guard.on` is created if it is
not already there — so a workstation this launcher has configured is never
left running every lane unguarded for want of someone arming it by hand; an
existing flag, armed or later disarmed by an operator, is never touched. The
Fable weekly bucket's own 95% line is not part of this and keeps today's
warning.

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
  profile at once. `--install` places EVERY skill in its own `SKILLS` array —
  `/lane-swap` and, from Amendment 11's tooling commit, `/restart` — at
  `${CLAUDE_PROFILES_HOME:-~/.claude-profiles}/shared/skills/<name>/SKILL.md`
  and a copy of each at `~/.claude/skills/<name>/SKILL.md` for a bare `claude`
  outside the launcher, all at 0644, idempotently and byte-compared. The set is
  the shim's, not this document's: it is read from that array, never counted
  here. `scripts/setup-claude-profiles.sh` used to install the `/lane-swap`
  skill from its own vendored copy; lane-collision-protocol Amendment 9's adoption act 4b deleted
  that loop and the copy with it, because two installers of one file is a
  defect no exact-match idempotence can resolve. This script still creates the
  shared directory and still links each profile at it.
- **`/swap`'s command file belongs beside the skills, on the same contract.**
  `--install` places every command in its `COMMANDS` array — `/swap` alone,
  once `opensoft/openRepoTools#26` round 2 landed it (A11 Addendum 4 ruling 9)
  — into the shared `commands` directory every profile's `commands` symlinks
  to, and a copy at `~/.claude/commands/swap.md` for a bare `claude`, at 0644,
  idempotently and byte-compared. `scripts/setup-claude-profiles.sh` used to
  install it from its own vendored copy on the same `for command in swap` loop
  as the skill; Amendment 9's adoption act 4b deleted that loop and the copy
  with it too, once the pin (`devBenches/base-image/upstream-pin.yaml`, commit
  `8a36eb3`, `opensoft/workBenches#78`) carried `commands/swap.md` and made
  `--install` capable of placing it with no writer left behind.
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
  session` already under `SessionStart`: `11 of 11 placed`, exit 0, the file
  left carrying both commands at mode 600. It computes the merge before it places
  anything, so a merge it cannot compute costs a whole install rather than half
  of one.
  Adoption act 4b deleted the ensure `scripts/setup-claude-profiles.sh` carried
  for the same file. **One path, one writer, in both halves:** a profile's
  `settings.json` is the launcher's, `~/.claude/settings.json` is
  `--install`'s, and the two never write one file.

**Live state, and the gate has since opened.** Both writers above are gated on
`~/projects/xFactory/lanes-edit.sh` having a `session-start` subcommand. That
path is not a second spelling of the estate: `link-estates` keeps it pointed at
the installed helper precisely because the hook's command string names it, and
the helper it points at now carries the subcommand — `opensoft/openRepoTools`
`63a74af`, Amendment 9's adoption act 3, merged. **Measured on this workstation
2026-09-14**, after `openRepoTools --install` ran: the link resolves to
`~/.local/bin/lanes-edit.sh`; `~/.claude/settings.json` carries the canonical
entry — same command string, `"matcher": "startup|resume|clear|fork"`,
`"timeout": 5` — beside an unrelated `SessionStart` hook it left exactly as it
was; and **15 of 383** profile `settings.json` under
`~/.claude-profiles/profiles/` carry it, which is the number of profiles
launched since, because the launcher writes the entry on a profile's NEXT launch
rather than into all of them at once. A workstation whose copy predates that
merge still fails the probe and still, correctly, ensures nothing.

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
