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
  "profiles": {
    "claude": [],
    "openai": []
  }
}
```

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
    "openai": ["team-*", "max-*"]
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
```

Run `scripts/setup-claude-profiles.sh` and
`scripts/setup-codex-profiles.sh` after composition to materialize the local
profile homes.

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

An agent stack may bind one credential to several surfaces, but the encrypted
credential has one owner and one source of truth. For example, a personal model
credential can be materialized for `pclaude` on a workstation and injected into
a personal VPS agent runtime without being copied into the Agents repository.
