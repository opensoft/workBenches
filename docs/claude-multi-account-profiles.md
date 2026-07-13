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
|   |-- work-acme/  # One company's login, settings, plugins, and cache
|   `-- personal/   # Personal login, settings, plugins, and cache
|-- state/
|   |-- work-acme/  # Company-only history, projects, plans, and tasks
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
Credentials, settings, plugins, caches, and daemon state remain per profile.

Every profile receives the shared four-line Claude status panel. It reports the
worktree and Git branch, model and effort level, context use, 5-hour and 7-day
credit use, the exact tmux attach target, and graphical countdowns to the
5-hour and 7-day reset times. The 5-hour countdown shows minutes remaining; the
weekly countdown shows days remaining, switching to hours under one day. Reset
times use `America/Los_Angeles` by default and can be changed with
`STATUSLINE_TZ`. When Claude exposes a separate weekly Fable limit, the panel
shows both `7d All` and `7d Fable`. Because the standard status-line payload
contains only the aggregate weekly value, the Fable value comes from Claude's
read-only OAuth usage endpoint and is cached per profile for 60 seconds.

The canonical renderer is
`base-image/files/claude-statusline-command.sh`. Profile setup installs it once
at `~/.claude-profiles/shared/statusline-command.sh`, and every profile links to
that shared copy. Update the canonical renderer in workBenches, then rerun
`./scripts/setup-claude-profiles.sh` to propagate changes without rebuilding a
bench image. Mounted running benches see the updated shared file immediately;
Claude refreshes the panel on its configured 10-second interval.

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
