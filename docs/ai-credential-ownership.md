# AI credential ownership and profile composition

workBenches separates AI profile tooling from the repositories that own account
inventory and encrypted credentials. The public workBenches repository contains
schemas, launchers, validation, and composition logic. It must never contain a
real password, OAuth token, API key, private key, or tenant account inventory.

## Ownership rule

The owner of an identity determines its source repository:

| Identity | Source of truth |
|---|---|
| Product-required logical role | Product credential-contract repository |
| Opensoft-owned account | `opensoft/Opensoft-Tenant` |
| FarHeap-owned account | `FarHeap/FarHeap-Tenant` |
| Engineer-owned personal account | `<engineer>/AI-Credentials` |
| Personal agent definition or stack | `<engineer>/Agents` |
| Local OAuth session | Workstation or approved runtime only |

Product repositories declare credential requirements and bindings, not tenant
secret values. Tenant repositories bind their own accounts to product roles.
User repositories import authorized tenant profiles and add personal profiles.
Agent-stack repositories reference credential IDs but do not copy credentials.

## Source layout

Each tenant or user credential repository exposes one source directory:

```text
ai/
|-- source.json
|-- grants/
|   `-- users/                 # Tenant sources only
|       `-- <github-user>.json
|-- secrets/                   # SOPS ciphertext only
|-- bindings/
`-- docs/
```

`source.json` uses this contract:

```json
{
  "version": 1,
  "kind": "workbenches-ai-profile-source",
  "owner": {"type": "tenant", "id": "example"},
  "credentialContractVersion": 1,
  "profiles": {
    "claude": [],
    "openai": [],
    "gemini": [],
    "grok": [],
    "glm": []
  }
}
```

Every versioned provider profile represents one provider account and declares
its credential separately:

```json
{
  "name": "team-001",
  "email": "team-001@example.com",
  "family": "company-team",
  "accountId": "example.openai.team-001.account",
  "credentialId": "example.openai.team-001.credential",
  "authentication": {
    "type": "workspace_access_token",
    "credentialRef": "ai/secrets/openai/team-001.credentials.sops.yaml",
    "escrowStatus": "not-escrowed"
  }
}
```

The same canonical profile name may exist for several providers, but each
provider has a distinct account, authentication method, and ciphertext. Use
`scripts/normalize-ai-provider-accounts.py` to add or refresh this contract in
an existing registry.

Supported owner types are `tenant`, `user`, and `product`. Product sources are
requirements-only and do not materialize workstation profiles. A tenant source
must grant profiles explicitly in `grants/users/<github-user>.json`. A user
source is accepted only when its owner ID matches the requested user.

Grants contain provider-specific profile-name patterns:

```json
{
  "version": 1,
  "user": "engineer",
  "profiles": {
    "claude": ["team-*", "max-*"],
    "openai": ["team-*", "max-*"],
    "gemini": ["team-*", "max-*"],
    "grok": ["team-*", "max-*"],
    "glm": ["team-*", "max-*"]
  }
}
```

Git authorization and a grant file do not provide secret access by themselves.
The tenant's SOPS recipients or external vault policy remains authoritative.

## Composition

Compose authorized tenant sources with one personal source:

```bash
python3 scripts/compose-ai-profiles.py \
  --user engineer \
  --source ~/projects/Opensoft-Tenant/ai \
  --source ~/projects/AI-Credentials/ai \
  --output-dir ~/.config/workbenches
```

The composer rejects duplicate canonical names, duplicate aliases, ungranted
tenant profiles, mismatched user sources, and malformed manifests. It writes
the existing launcher manifests atomically with mode `0600`:

```text
~/.config/workbenches/claude-profiles.json
~/.config/workbenches/openai-profiles.json
~/.config/workbenches/gemini-profiles.json
~/.config/workbenches/grok-profiles.json
~/.config/workbenches/glm-profiles.json
```

Run `scripts/setup-ai-profiles.sh --apply-existing` after composition to
materialize every provider's local profile homes.

## First-run onboarding

`setup.sh` invokes `scripts/setup-ai-profiles.sh` when no profile manifests
exist. Before querying GitHub or writing profile metadata, it asks whether the
user consents to work/personal profile setup. It then collects:

- the personal GitHub username;
- company count, company name, company login email, and company GitHub org;
- personal AI subscription emails and the providers used by each account; and
- the personal GitHub user or org that owns the personal credential registry.

For each GitHub owner, onboarding searches accessible repositories whose names
look like AI credential registries and verifies `ai/source.json` exists. The
user selects a result, enters a repository URL/local path, or chooses a local
manual profile. Discovery also recognizes a published credential-registry
feature branch when the source has not reached the default branch. Manual
profiles are workstation metadata only and are marked
`sourceMode: manual-workstation`; they do not become a tenant source of truth.

The consent and selections are recorded with mode `0600` at
`~/.config/workbenches/ai-profile-onboarding.json`. Existing standard provider
credential homes are detected and preserved, never copied automatically into
isolated profiles.

## Secret handling

- Git may contain profile metadata, vault references, and SOPS ciphertext.
- Plaintext credentials must never be committed, logged, or passed on a command
  line.
- Each tenant controls its own SOPS/age recovery identity and recipients.
- Each engineer controls a separate personal SOPS/age recovery identity.
- A VPS receives a distinct age recipient and only the files required by its
  approved agent stack.
- Interactive subscription OAuth credentials should not be used for unattended
  automation unless the provider and tenant policy explicitly allow it.

Use `scripts/provider-credential-escrow` for operator-invoked Claude or Codex
backup, verification, and restoration. The command resolves the encrypted path
from `source.json`, validates the provider-specific plaintext shape, performs
an encrypted round-trip canonical-payload hash check during backup, and never prints credential
values. Backup requires the matching recovery identity so ciphertext cannot be
committed without proving it can be recovered.

An agent stack may bind one credential to several surfaces, but the encrypted
credential has one owner and one source of truth. For example, a personal model
credential can be materialized for `pclaude` on a workstation and injected into
a personal VPS agent runtime without being copied into the Agents repository.
