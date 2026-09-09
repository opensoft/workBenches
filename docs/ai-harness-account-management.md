# Multiple AI harness account management

For the repository ownership model used by product, tenant, engineer, and
agent-stack credentials, read
[AI credential ownership and profile composition](ai-credential-ownership.md).

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
| `gemini` | Google Gemini CLI | `gemini` | One `GEMINI_CLI_HOME` per account | Login and local credential presence |
| `grok` | Grok Build | `grok` | One `GROK_HOME` per account | Login and verification |
| `glm` | Z.AI GLM Coding Plan through OpenCode | `opencode` | Profile-specific XDG directories | Login and verification |
| `kimi-code` | Kimi Code CLI (Moonshot AI, Kimi K3) | `kimi` | One `KIMI_CODE_HOME` per account | Inventory and manual verification |
| `qwen` | Qwen Code CLI (Alibaba) | `qwen` | Profile-specific `~/.qwen` config | Inventory and manual verification |
| `minimax` | MiniMax Code CLI | `mcode` | Region-aware login (`global`/`cn`) | Inventory and manual verification |
| `deepseek-harness` | DeepSeek Harness (developer preview) | `dsh` | One `DSH_HOME` per account | Inventory and manual verification |
| `antigravity` | Google Antigravity, the Gemini CLI migration target | `agy` | Operating-system secure keyring | Inventory and manual verification |
| `abacus` | Abacus AI CLI | `abacusai` | Provider login or per-process API key | Inventory and manual verification |

`openai` and `codex` are accepted as legacy aliases for `chatgpt`. `zai` and
`z.ai` are accepted as aliases for `glm`. The executable names remain the
vendor-provided names shown above.

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

- `provider`: one of the supported provider IDs above.
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

For profiles collected during `setup.sh`, run
`./scripts/check-ai-credentials.sh`. It defaults to the workstation inventory
in `~/.config/workbenches`.

Open `http://127.0.0.1:8765`. The server binds only to loopback. It displays
the source repository URL, verifies supported local profiles, and can start
vendor login flows. It does not read, return, copy, or commit credential
contents.

Kimi, Qwen, and MiniMax are recognized in the shared CLI inventory and shell
adapter, but the dashboard does not yet implement their profile-home or
authentication adapters. Use the vendor commands in their workflows below for
login and verification.

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
./scripts/setup-codex-profiles.sh --manifest /path/to/openai-profiles.json
codex-profile login company-chatgpt-1
codex-profile status company-chatgpt-1
pcodex company-chatgpt-1
```

The dashboard writes a profile-local `config.toml` that selects ChatGPT login
and file credential storage. Treat each profile's `auth.json` like a password.
The `codex-profile` and `pcodex` launchers provide the same isolation from the
terminal; see [Codex multi-account profiles](codex-multi-account-profiles.md).
OpenAI documents the browser flow, local cache, and automatic refresh in
[Authentication](https://learn.chatgpt.com/docs/auth) and the command details
in [Developer commands](https://learn.chatgpt.com/docs/developer-commands#codex-login).

### ChatGPT account with OpenCode

The host-side OpenCode profile extension is not yet a provider type supported
by the credential-manager dashboard or unified manifest. It uses a separate
`opencode-profiles.json` manifest and the `popencode` launcher. Unlike
`pcodex`, it preserves one
shared OpenCode project/session database and isolates only the selected OpenAI
OAuth record:

```bash
popencode login work1
popencode status work1
popencode work1
```

Shared OMO configuration and supporting API-key providers therefore remain
available after switching from `work1` to `work2`. A profile without its own
OpenAI credential is treated as logged out and cannot fall back to the other
profile. See
[OpenCode multi-account OpenAI profiles](opencode-openai-multi-account-profiles.md)
for the state layout, runtime contract, and verification procedure.

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

### Google Gemini CLI

Gemini CLI supports an isolated user-state root with `GEMINI_CLI_HOME`.
workBenches materializes one root per canonical identity:

```bash
pgemini login team001
pgemini status team001
pgemini team001
```

The login command opens Gemini's interactive Google sign-in. The status command
only reports whether the profile-local credential cache exists; use `/about`
inside Gemini to verify the selected Google account.

### Z.AI GLM Coding Plan

GLM profiles use OpenCode with isolated XDG config, data, cache, and state
directories. Authentication is a separate Z.AI API key for every profile:

```bash
pglm login team001  # select Z.AI Coding Plan
pglm status team001
pglm team001
```

`pzai` is an alias for `pglm`. The profile manifest records the expected email
but never contains the API key.

### Kimi Code CLI

Kimi Code CLI is Moonshot AI's terminal coding agent (Kimi K3 and later). It
reads local data from `~/.kimi-code/` by default, and honors a `KIMI_CODE_HOME`
override for a per-account root:

```bash
KIMI_CODE_HOME="$HOME/.kimi-code-profiles/personal" kimi
```

Inside the CLI, `/login` opens a chooser for Kimi Code OAuth (device-code flow)
or a Moonshot AI Open Platform API key; `/logout` clears the active profile's
credentials. Do not confuse this current TypeScript CLI with the legacy Python
`kimi-cli` package (distributed on PyPI as `kimi-cli`); check `kimi --version`
and expect a `0.x` release for the current tool.

### Qwen Code CLI

Qwen Code CLI is Alibaba's terminal coding agent. Configuration lives in
`~/.qwen/settings.json`, which can declare multiple named model providers
(Alibaba Cloud Model Studio, DeepSeek, MiniMax, Z.AI, Kimi, OpenRouter, or any
OpenAI/Anthropic/Gemini-compatible endpoint) side by side:

```bash
qwen
# inside the CLI
/auth
```

Since Qwen Code's `settings.json` can hold several third-party provider keys at
once, a single Qwen Code account/profile can double as the practical way to
use DeepSeek's or MiniMax's models without a dedicated CLI for those vendors.

### MiniMax Code CLI

MiniMax Code CLI (`mcode`) is MiniMax's terminal coding agent, distinct from
MiniMax's multimodal `mmx-cli` (`mmx`, for text/image/video/speech/music
generation). Sign-in is region-aware:

```bash
mcode login --region global   # overseas MiniMax account
mcode login --region cn       # mainland China MiniMax account
mcode /status                 # inside the TUI: verify account, model, region
```

### DeepSeek Harness

DeepSeek Harness (`dsh`, package `@deepseek-ai/dsh`) is DeepSeek AI's official,
plugin-based agent harness, released as an MIT-licensed developer preview. It
is genuinely different from the Claude Code/Codex/Kimi/Qwen model: nearly
everything (models, tools, sessions, sandboxes, the agent loop, and the UI) is
a swappable Cordis plugin rather than a fixed CLI surface.

```bash
npx @deepseek-ai/dsh web              # local Web UI at http://127.0.0.1:3080
dsh --profile headless "do the task"  # one-shot headless run for scripts/CI
```

Credentials resolve from the inherited environment, `$DSH_HOME/.credentials.yaml`,
the invoking directory's `.env`, then `$DSH_HOME/.env`; a DeepSeek API key
added under Settings → Models (or the credential provider) takes effect
immediately. Treat it as evaluation/development infrastructure, not a stable
daily driver: the upstream README warns in capitals that breaking changes are
expected between developer-preview releases, and installing a third-party
plugin runs that plugin's code unsandboxed.

### GLM/Z.AI Coding Tool Helper

Z.AI does not ship a standalone GLM coding agent. Its official `chelper`
(`@z_ai/coding-helper`) is a setup wizard that wires the GLM Coding Plan into
an existing tool (Claude Code, OpenCode, Crush, or Factory Droid) rather than
acting as an agent itself:

```bash
coding-helper init                       # interactive wizard
chelper auth glm_coding_plan_global <token>
chelper auth reload claude                # push the plan into Claude Code
chelper doctor                            # health check
```

This complements, rather than replaces, the existing OpenCode-based `glm`
profile workflow described above.

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
