# Multiple AI harness account management

workBenches provides a local account dashboard and profile conventions for
people who use more than one account across multiple AI coding and agent
harnesses. An account can be personal, belong to a company workspace, or use a
client-specific identity. The public repository contains only generic tooling
and examples; a user's real account inventory belongs in a separate private
source-of-truth repository.

The supported harness families are:

| Provider ID | Product label | Executable | Isolation model | Dashboard support |
|---|---|---|---|---|
| `claude` | Claude Code | `claude` | One `CLAUDE_CONFIG_DIR` per account | Login and verification |
| `chatgpt` | ChatGPT account used by Codex CLI | `codex` | One `CODEX_HOME` per account | Login and verification |
| `grok` | Grok Build | `grok` | One `GROK_HOME` per account | Login and verification |
| `antigravity` | Google Antigravity, the Gemini CLI migration target | `agy` | Operating-system secure keyring | Inventory and manual verification |
| `abacus` | Abacus AI CLI | `abacusai` | Provider login or per-process API key | Inventory and manual verification |

`openai` and `codex` are accepted as legacy aliases for `chatgpt`. `gemini` is
accepted as a legacy inventory alias for `antigravity`. The executable names
remain the vendor-provided names shown above.

## Source-of-truth manifest

Copy the public example into a private repository:

```bash
mkdir -p ~/account-registry/config
cp config/ai-harness-accounts.example.json \
  ~/account-registry/config/ai-harness-accounts.json
$EDITOR ~/account-registry/config/ai-harness-accounts.json
```

The manifest contains account labels and login identifiers, never passwords,
OAuth tokens, API-key values, browser cookies, or encryption private keys.

Important fields:

- `provider`: one of the five provider IDs above.
- `name`: stable machine-safe profile name.
- `family`: accounts that may intentionally share non-secret history or rules.
- `email`: expected login identity.
- `plan` and `workspace`: display metadata only.
- `authMode`: `browser`, `device`, `keyring`, or `api-key`.
- `secretEnv`: optional name of an environment variable; never put its value in
  the manifest.
- `status`: normally `active` or `planned`.

Launch the local-only dashboard:

```bash
python3 apps/credential-manager/credential_manager.py \
  --source-repo ~/account-registry
```

Open `http://127.0.0.1:8765`. The server binds only to loopback. It displays
the source repository URL, verifies supported local profiles, and can start
vendor login flows. It does not read, return, copy, or commit credential
contents.

## Provider workflows

### Claude Code

Claude Code supports Claude subscription and Anthropic Console login. The
workBenches launcher assigns each account its own `CLAUDE_CONFIG_DIR`:

```bash
./scripts/setup-claude-profiles.sh --manifest /path/to/claude-profiles.json
claude-profile login company-claude-1
claude-profile status company-claude-1
claude-profile company-claude-1
```

Profiles may share non-secret session history by `family`, while credentials,
account metadata, caches, and daemon state remain per profile. See
[Claude multi-account profiles](claude-multi-account-profiles.md) and
[Anthropic's setup documentation](https://docs.anthropic.com/en/docs/claude-code/getting-started).

### ChatGPT account with Codex CLI

The product/account label is ChatGPT; the official terminal executable remains
`codex`. Codex can sign in with ChatGPT through a browser and caches credentials
under `CODEX_HOME` (or the operating-system credential store):

```bash
profile="$HOME/.chatgpt-profiles/profiles/company-chatgpt-1"
mkdir -p "$profile"
CODEX_HOME="$profile" codex login
CODEX_HOME="$profile" codex login status
CODEX_HOME="$profile" codex
```

The dashboard writes a profile-local `config.toml` that selects ChatGPT login
and file credential storage. Treat each profile's `auth.json` like a password.
OpenAI documents the browser flow, local cache, and automatic refresh in
[Authentication](https://learn.chatgpt.com/docs/auth) and the command details
in [Developer commands](https://learn.chatgpt.com/docs/developer-commands#codex-login).

### Grok Build

Grok officially supports changing its home directory with `GROK_HOME`, so each
account can use an isolated browser or device-code session:

```bash
profile="$HOME/.grok-profiles/profiles/personal-grok-1"
mkdir -p "$profile"
GROK_HOME="$profile" grok login
GROK_HOME="$profile" grok models
GROK_HOME="$profile" grok
```

For a remote or headless machine, use:

```bash
GROK_HOME="$profile" grok login --device-auth
```

See xAI's [CLI reference](https://docs.x.ai/build/cli/reference) and
[settings documentation](https://docs.x.ai/build/settings).

### Google Antigravity

Antigravity is Google's migration target for Gemini CLI profiles, and its CLI
executable is `agy`. It stores session tokens in the operating system's secure
keyring and does not currently document a home-directory override suitable for
parallel account profiles. The dashboard therefore inventories Antigravity
accounts but does not copy, export, or claim to validate keyring tokens.

```bash
agy
# Use Account Settings to inspect the active account.
# Use /logout to remove that keyring session before changing accounts.
```

For concurrent identities, use separate operating-system user/keyring contexts
or separately isolated workstations. Do not reuse an Antigravity login in a
third-party harness; Google's FAQ directs third-party Gemini integrations to
Vertex AI or AI Studio API keys. See [Antigravity installation and auth](https://antigravity.google/docs/cli-install)
and [Gemini CLI migration](https://antigravity.google/docs/gcli-migration).

### Abacus AI

Abacus AI CLI supports an interactive account login and the
`ABACUS_API_KEY` environment variable:

```text
abacusai
/login user@example.com
/logout
```

For API-key use, keep each value in an external secret manager. A manifest may
record a unique `secretEnv` name, such as `ABACUS_API_KEY_COMPANY_1`, but never
the key itself. Resolve that secret only for the process being launched and map
it to `ABACUS_API_KEY`:

```bash
ABACUS_API_KEY="$ABACUS_API_KEY_COMPANY_1" abacusai
```

Abacus does not currently document a per-account CLI home override, so the
dashboard does not move its cached login between folders. See the official
[Abacus AI CLI installation guide](https://abacus.ai/help/abacusai-desktop/cli-installation).

## Security requirements

- Never extract browser cookies or invent session-token files.
- Never commit plaintext credential caches, API keys, private encryption keys,
  or keyring exports.
- Keep profile credential files readable only by their owner (`0600`).
- If encrypted credential backups are required, encrypt client-side to reviewed
  recipients and keep every decryption private key outside GitHub.
- Removing an encryption recipient does not revoke access to older ciphertext;
  revoke the vendor session or API key after a recipient-key compromise.
- Keep account manifests private when email addresses or workspace membership
  are sensitive, even though the manifests contain no authentication secrets.

## Legacy manifests

The dashboard also reads older split manifests for compatibility:

- `config/claude-profiles.json`
- `config/openai-profiles.json` (displayed as `chatgpt`)
- `config/grok-profiles.json`
- `config/antigravity-accounts.json`
- `config/abacus-accounts.json`

New installations should prefer the unified `ai-harness-accounts.json` schema.
