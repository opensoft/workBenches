# OpenCode multi-account OpenAI profiles

workBenches can run one OpenCode project workspace with more than one OpenAI
ChatGPT login. The `popencode` launcher isolates the OpenAI OAuth credential for
each account while preserving the OpenCode state that should remain common:

- project sessions and their SQLite database;
- OpenCode and Oh My OpenCode (OMO) configuration;
- agents, commands, and shared instructions; and
- API-key credentials for providers used by supporting agents.

This differs intentionally from the `pglm`/`pzai` launcher. GLM profiles isolate
all XDG directories. OpenAI profiles share OpenCode's normal XDG directories and
overlay only the `openai` authentication record.

## Use

For example, a private tenant registry may define `work-chatgpt-1` and
`work-chatgpt-2`, with short aliases `work1` and `work2`:

```bash
popencode list
popencode login work1
popencode status work1
popencode work1

popencode login work2
popencode status work2
popencode work2
```

Run the launcher from the repository whose OpenCode sessions you want to use.
Because both profiles use the same OpenCode data directory, switching accounts
does not move or copy a session:

```bash
cd ~/projects/example
popencode work1

# Later, after work1 reaches its usage limit:
popencode work2
```

An explicit session ID works from either login:

```bash
popencode work2 -s SESSION_ID
```

OpenCode still determines project membership from the repository/worktree. The
profile selects the OpenAI account used for the next model request; it does not
select a separate project or session database.

## State layout

The profile manifest contains identity metadata only:

```text
~/.config/workbenches/opencode-profiles.json
```

Each OpenAI OAuth record is stored separately and must be treated like a
password:

```text
~/.opencode-profiles/
`-- profiles/
    `-- example-company/
        `-- max/
            |-- work-chatgpt-1/openai-auth.json
            `-- work-chatgpt-2/openai-auth.json
```

The profiles intentionally share OpenCode's standard state locations:

```text
~/.local/share/opencode/   # project sessions and shared provider auth
~/.local/state/opencode/
~/.cache/opencode/
~/.config/opencode/       # OpenCode configuration
~/.omo/                   # OMO configuration
```

The shared `auth.json` may contain API-key or OAuth records for other providers.
When `popencode` runs, the selected profile's `openai-auth.json` replaces only
the `openai` entry in memory. If that profile has no OpenAI credential, OpenCode
sees OpenAI as logged out; it cannot silently fall back to another account's
shared OpenAI record. Token refreshes are written to the selected profile file.

## Manifest

The host manifest uses canonical names, aliases, expected emails, profile paths,
and—when known—the expected OpenAI account ID:

```json
{
  "profiles": [
    {
      "name": "work-chatgpt-1",
      "aliases": ["work1"],
      "email": "developer@example.com",
      "profilePath": "example-company/max/work-chatgpt-1",
      "expectedAccountId": "provider-account-id"
    }
  ]
}
```

Never put access tokens, refresh tokens, API keys, or browser cookies in this
manifest. `popencode status PROFILE` reports `verified` only when the profile
credential has an account ID and it matches `expectedAccountId`, when that
field is configured. It does not make a billable model request.

## Runtime contract

The launcher is `scripts/opencode-profile`; `popencode` and
`opencode-profile` are symlinks to it. It starts the profile-managed OpenCode
runtime with:

```text
OPENCODE_AUTH_PROFILE_PROVIDER=openai
OPENCODE_AUTH_PROFILE_FILE=<selected profile>/openai-auth.json
```

The profile-managed OpenCode build implements this provider overlay in
`packages/opencode/src/auth/index.ts`. Its Codex OAuth adapter must also allow
every OpenAI model ID referenced by the active OMO configuration. The managed
binary currently lives at:

```text
~/.local/lib/workbenches/opencode-profile
```

The ordinary `opencode` executable is deliberately not replaced. This keeps the
profile extension scoped to `popencode` until the overlay is upstreamed or
packaged as part of workBenches installation.

## Verification and troubleshooting

Check identity metadata before starting work:

```bash
popencode status work1
```

`OpenAI login: missing` means that profile must complete `popencode login`.
`OpenAI login: account mismatch` means the browser login selected a different
account; log out that profile and repeat the login with the expected identity.

To prove that two profiles see the same repository sessions without invoking a
model:

```bash
popencode work1 session list --pure --format json
popencode work2 session list --pure --format json
```

Use `--pure` for this diagnostic so external plugins cannot delay the listing.
Matching lists prove shared local session state, not that both OpenAI logins are
valid or have available quota. Verify each login independently with `status`
and, when necessary, a small live model request.

## Security and concurrency

- Keep every `openai-auth.json` owner-readable only (`0600`) and its profile
  directory `0700`.
- Never copy one profile's OAuth file into another profile.
- Do not commit the host manifest when real email addresses or account IDs are
  sensitive.
- Concurrent OpenCode processes may safely use the shared SQLite state through
  OpenCode's normal database handling. Each process receives only its selected
  OpenAI credential overlay.
- Changing shared API-key credentials affects both OpenAI profiles by design.
  Changing one profile's OpenAI login does not affect the other.
