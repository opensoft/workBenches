# Claude multi-account profiles

workBenches can provision multiple Claude Code logins with separate credentials,
shared reusable capabilities, and session history shared only within a trust
family such as `personal`, `company`, or `client`.

## New-machine setup

```bash
cp config/claude-profiles.example.json ~/.config/workbenches/claude-profiles.json
$EDITOR ~/.config/workbenches/claude-profiles.json
./scripts/setup-claude-profiles.sh
claude-profile list
claude-profile login company-premium-1
claude-profile company-premium-1
```

Alternatively, collect or confirm each email interactively:

```bash
./scripts/setup-claude-profiles.sh --interactive
```

The manifest contains email addresses but no credentials. Claude stores OAuth
credentials inside each directory under `~/.claude-profiles/profiles/`.
The installer marks the profile's CLI onboarding as complete because login is
performed explicitly with `claude-profile login`; this prevents Claude's
first-run wizard from starting a second, redundant browser login.

All profiles share `skills`, `agents`, `commands`, and `rules`. Profiles in the
same family share transcripts, prompt history, file history, plans, and tasks.
Credentials, settings, plugins, caches, and daemon state remain per profile.

Do not resume the same Claude session concurrently from two profiles. Use email
magic-link authentication for mailbox aliases; Microsoft or Google SSO may
resolve an alias back to the mailbox's primary identity.

## Reproducing this setup in a new AI session

Tell the agent:

> Read `docs/claude-multi-account-profiles.md` and
> `config/claude-profiles.example.json`, then run the workBenches Claude profile
> setup for this machine. Do not copy OAuth credential files between accounts.
