# Multiple AI Harness Account Manager

This local-only dashboard manages account inventory and supported login flows
for Claude Code, ChatGPT/Codex CLI, Grok Build, Google Antigravity, and Abacus
AI. It is generic public tooling: real account names and email addresses belong
in a separate private source-of-truth repository.

Create a private manifest from the example:

```bash
mkdir -p ~/account-registry/config
cp config/ai-harness-accounts.example.json \
  ~/account-registry/config/ai-harness-accounts.json
$EDITOR ~/account-registry/config/ai-harness-accounts.json
```

Run the dashboard:

```bash
python3 apps/credential-manager/credential_manager.py \
  --source-repo ~/account-registry
```

Open `http://127.0.0.1:8765`. The server binds only to loopback. It reads
non-secret account metadata, derives the source clone's Git remote, verifies
supported profiles, and starts supported vendor login commands.

Automated adapters:

- Claude Code: `CLAUDE_CONFIG_DIR`, `claude auth login`, and
  `claude auth status`.
- ChatGPT/Codex CLI: `CODEX_HOME`, `codex login`, and
  `codex login status`.
- Grok Build: `GROK_HOME`, `grok login`, and `grok models`.

Inventory/manual adapters:

- Google Antigravity: the vendor stores sessions in the operating-system
  keyring and does not document a profile-home override.
- Abacus AI: the vendor documents `/login [email]` and `ABACUS_API_KEY`, but
  not a profile-home override.

The dashboard never reads, returns, copies, or stores credential contents.
Authentication logs are local, mode `0600`, and may contain short-lived login
URLs, so they must not be committed.

See [Multiple AI harness account management](../../docs/ai-harness-account-management.md)
for the manifest schema, provider commands, security model, and official
documentation links.
