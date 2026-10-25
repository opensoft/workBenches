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
| Company-owned AI account (future target) | Company-controlled dedicated private AI profile repository |
| Engineer-owned personal account | `<engineer>/AI-Credentials` |
| Personal agent definition or stack | `<engineer>/Agents` |
| Local OAuth session | Workstation or approved runtime only |

Product repositories declare credential requirements and bindings, not tenant
secret values. Tenant repositories bind their own accounts to product roles.
User repositories import authorized tenant profiles and add personal profiles.
Agent-stack repositories reference credential IDs but do not copy credentials.

## Profiles product ownership and workBenches integration

Follow-up decision from Brett, 2026-10-24: complete the capability in the existing
[openProfiler](https://github.com/opensoft/openProfiler) product, called
"openProfiles" in discussion. workBenches will consume a tested pinned release
in v1.7 or v1.8 after qualification. openProfiler owns reusable catalogs,
manifest composition, provider stores, broker retrieval and lifecycle management.
workBenches owns setup and orchestration through a versioned headless contract,
with immutable release pins and verified artifacts. Preserve isolated launcher
behavior; activation into a default home alone is not a substitute.

Track upstream completion in [openProfiler #30](https://github.com/opensoft/openProfiler/issues/30)
and integration in [workBenches #229](https://github.com/opensoft/workBenches/issues/229).
This is a direction and migration plan, not an implemented extraction.

The target company deployment includes a separately deployable broker service
container connected to the company's existing vault. The current openProfiler
installer does not provide this company deployment. The workBenches Vault
container is a client toolbox for contacting credential stores, not a vault
server. Keep the authoritative company catalog in its private repository and
generate only the engineer's authorized launcher manifests on the workstation.
Initially preserve the compatible local paths
`~/.config/workbenches/claude-profiles.json` and `openai-profiles.json`;
provider credentials remain in their separate private profile stores.

## Company repository and broker onboarding target

Scope decision from Brett, 2026-10-24: company AI profile sets belong in a
dedicated private repository controlled by that company, rather than in
`opensoft/Opensoft-Tenant`. The latter is the currently observed Opensoft catalog
location, not the target storage contract. Every company chooses its own
repository and controls access for its engineers; workBenches must not assume
an Opensoft organization, repository name or shared central account catalog.
Migration of existing catalogs is future work and must be reviewed before any
source is moved or deleted.

The company repository owns profile metadata (names, provider login emails,
account IDs), credential references and administrator-controlled grants or
policy. Credential values remain in that company's vault. Company configuration
associates its repository and broker endpoint with its workBenches profile.
Repository administration and vault/broker administration remain company-owned.

An engineer links a verified GitHub account to a company in workBenches. Linking
is a local association, not proof of company membership or a credential grant.
After company/broker authentication and verified identity mapping, the broker
uses company policy to return only profiles that engineer may use. Setup reviews
the authorized set, generates local launcher manifests and retrieves approved
credentials through the broker into isolated private provider stores. Engineers
do not need direct vault access for this future path. Personal profiles and other
companies remain independent.

The current composer can read an entire cloned catalog before applying local
grant filtering. That filtering does not hide catalog metadata from someone
with repository read access. If company policy restricts which account metadata
an engineer can see, have the broker read the private source and expose only
authorized entries; do not distribute the full catalog to that engineer.
Repository visibility is a separate boundary from per-profile broker grants.
The existing optional broker GitHub-team checks are a building block, not proof
that this integrated onboarding and storage migration are implemented.

Acceptance must cover two independent companies, multiple linked GitHub
accounts, unauthorized users, revoked access, partial recovery, reruns and
migration without changing canonical profile IDs or breaking existing stores.
The v1.6.2 direct device-login recovery path remains separately scoped.

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
- company count, company login email (company name defaults to the email
  domain's first label and is editable), and company GitHub org;
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

For teams that want to stop distributing the age recovery identity to
workstations, the optional
[Keycloak-gated credential broker](keycloak-credential-broker.md) puts a shared
identity server and a Python broker in front of these same SOPS registries. It
gates the existing grants without replacing them: Keycloak proves identity, the
grant files remain authoritative for authorization, SOPS remains the at-rest
store, and the broker holds one age identity per tenant so no decryption key
reaches a workstation or agent.
