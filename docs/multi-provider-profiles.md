# Shared AI provider profiles

workBenches uses one canonical profile name and login email across Claude,
ChatGPT/Codex, Google Gemini CLI, Grok Build, and the Z.AI GLM Coding Plan.
Provider credentials remain isolated and are never interchangeable.

## Interactive setup

Run the onboarding directly with:

```bash
./scripts/setup-ai-profiles.sh --interactive
```

The flow asks for consent, work companies, company emails and GitHub orgs,
personal subscription emails, and the personal GitHub owner. It searches each
owner's accessible repositories for a credential registry containing
`ai/source.json`. When none is found, the user may enter a registry URL or
create local manual profile metadata.

Standard non-profile logins under `~/.claude`, `~/.codex`, `~/.gemini`, and
`~/.grok` are left untouched. Each generated isolated profile still requires
the corresponding provider login unless its owning private registry restores
an approved credential escrow.

The standard launchers are:

| Provider | Launcher | Isolated state |
|---|---|---|
| Claude | `pclaude` | `CLAUDE_CONFIG_DIR` |
| ChatGPT/Codex | `pcodex` | `CODEX_HOME` |
| Gemini | `pgemini` | `GEMINI_CLI_HOME` |
| Grok | `pgrok` | `GROK_HOME` |
| Z.AI GLM through OpenCode | `pglm` or `pzai` | profile-specific XDG directories |

For example, `team001` resolves to the canonical `team-001` profile for every
provider:

```bash
pclaude team001
pcodex team001
pgemini team001
pgrok team001
pglm team001
```

Login and status operations use the same pattern:

```bash
pgemini login team001
pgrok login team001
pglm login team001

pgemini status team001
pgrok status team001
pglm status team001
```

Gemini starts its normal interactive Google sign-in flow. For GLM, select
`Z.AI Coding Plan` in OpenCode and enter the profile's Z.AI API key. Secrets
must come from the owning tenant vault or SOPS escrow and never from a profile
manifest.
