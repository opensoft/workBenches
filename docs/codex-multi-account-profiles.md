# Codex multi-account profiles

workBenches can launch Codex CLI with separate ChatGPT logins. Each account
receives its own `CODEX_HOME` and file-backed `auth.json`. Profiles in the same
trust family share portable conversation state, while logs, caches, databases,
and credentials remain profile-local. Profile names, aliases, families, and
login emails are inventory metadata only; OAuth credentials are never stored
in a manifest.

## Setup

```bash
cp config/openai-profiles.example.json ~/.config/workbenches/openai-profiles.json
$EDITOR ~/.config/workbenches/openai-profiles.json
./scripts/setup-codex-profiles.sh
codex-profile list
codex-profile login work-chatgpt-1
pcodex work1
```

`codex-profile` and `pcodex` are the same launcher. Supported forms are:

```bash
pcodex list
pcodex login PROFILE
pcodex status PROFILE
pcodex logout PROFILE
pcodex PROFILE [codex arguments]
```

Profile homes are created under:

```text
~/.chatgpt-profiles/
|-- profiles/
|   |-- work-chatgpt-1/
|   |   |-- auth.json       # Created by Codex login; treat like a password
|   |   |-- config.toml
|   |   |-- sessions -> ../../state/work/sessions
|   |   `-- history.jsonl -> ../../state/work/history.jsonl
|   `-- personal-chatgpt-1/
`-- state/
    `-- work/                # Portable history shared by the work family
```

The installer initializes each profile from the user's existing Codex
configuration, then forces ChatGPT login with file credential storage. Shared
skills, prompts, policy, and global instructions link back to `~/.codex`.
`sessions`, `archived_sessions`, `history.jsonl`, and `session_index.jsonl`
link to family state so another login in that family can resume the same work.
Credential files and SQLite runtime state remain isolated per profile.

When existing profiles are adopted, setup merges their portable state into the
family directory without overwriting existing rollouts. The former local paths
are retained as `.pre-shared-state` recovery copies. Re-running setup repairs
the links without importing those recovery copies again.

Codex's built-in `--profile` option is a configuration overlay within one
`CODEX_HOME`; it does not isolate account credentials. Use `pcodex` when the
login identity must change.

Each ChatGPT identity still needs its own applicable product entitlement. A
local profile does not create a ChatGPT Business seat or independent quota.

## Codex Desktop through Multi-CLI

On Windows, the current Desktop store at `%USERPROFILE%\.codex` is the shared
conversation source. Synchronize registry-owned Multi-CLI profiles with:

```powershell
.\scripts\setup-multi-cli-codex-profiles.ps1 `
  -Manifest C:\path\to\openai-profiles.json
```

The script creates `MultiCliProfiles\codex\<profile>` homes for every
non-personal (company) family in the manifest by default, or only the
families passed via `-Family` (e.g. `-Family acme`). Their portable history
paths link to the live Desktop store, while `auth.json`, configuration,
caches, and databases remain inside each Multi-CLI profile. Multiple login
identities in the same company family can therefore open the same Desktop
conversations using different login tokens. Profiles with a `personal` family
are never linked.

The operation is idempotent. It refuses to replace a real profile-local history
path or a link targeting another store; migrate that state explicitly first.
