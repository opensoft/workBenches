# Codex multi-account profiles

workBenches can launch Codex CLI with separate ChatGPT logins. Each account
receives its own `CODEX_HOME`, including its own file-backed `auth.json`,
sessions, logs, and caches. Profile names, aliases, families, and login emails
are inventory metadata only; OAuth credentials are never stored in a manifest.

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
`-- profiles/
    |-- work-chatgpt-1/
    |   |-- auth.json       # Created by Codex login; treat like a password
    |   |-- config.toml
    |   `-- .profile.json
    `-- personal-chatgpt-1/
```

The installer initializes each profile from the user's existing Codex
configuration, then forces ChatGPT login with file credential storage. Shared
skills, prompts, policy, and global instructions link back to `~/.codex` while
credentials and runtime state stay isolated per profile.

Codex's built-in `--profile` option is a configuration overlay within one
`CODEX_HOME`; it does not isolate account credentials. Use `pcodex` when the
login identity must change.

Each ChatGPT identity still needs its own applicable product entitlement. A
local profile does not create a ChatGPT Business seat or independent quota.
