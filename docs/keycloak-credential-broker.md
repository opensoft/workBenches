# Keycloak-gated credential broker

workBenches stores no secrets. Today the actual credential values live as SOPS
ciphertext inside private tenant and user registries, and
`scripts/provider-credential-escrow` restores them by reading a local clone with
the age recovery identity present **on the engineer's workstation**. This
document specifies an optional server-side alternative: a shared
[Keycloak](https://www.keycloak.org/) identity server plus a Python credential
broker that releases those same credentials to an authenticated caller, so the
age recovery identity never has to leave a controlled host.

This design **gates** the existing SOPS registries. It does not replace them.
SOPS remains the at-rest storage format and the offline break-glass path. Read
[AI credential ownership and profile composition](ai-credential-ownership.md)
first; this document assumes that ownership model and extends it.

## Why

The single largest weakness in the current model is that restoring an escrowed
credential requires the tenant's age recovery identity to be readable on the
workstation performing the restore. Every workstation that restores a profile is
therefore a place a decryption key can leak from, and offboarding an engineer
means trusting that they scrub local key material.

With a broker in front of SOPS:

- The age recovery identity stays on the broker host and never reaches a
  workstation or agent.
- Workstations and unattended agents only ever *authenticate*; they never hold a
  decryption key.
- Onboarding and offboarding become Keycloak group membership changes plus the
  existing grant files. No key distribution or scrubbing.
- Every credential release is authenticated, authorized against the existing
  grants, and audited centrally.

The caveats the current model already documents still hold. Releasing a
long-lived vendor token to a workstation or agent means that token now lives
there; the broker can revoke future *access* instantly by disabling a Keycloak
identity, but it cannot recall an already-materialized vendor token. A leaked
vendor secret still requires vendor-side rotation.

## Locked decisions

| Decision | Choice | Rationale |
|---|---|---|
| Broker role | Gate in front of SOPS | Reuses the existing registries, grants, and escrow validators; keeps SOPS as offline fallback. |
| Deployment | Shared org server | One Keycloak and one broker for the team; benches and agents authenticate over the network. |
| Authorization source | Existing grant files | `grants/users/<github-user>.json` stays the single source of truth for *what*; Keycloak only proves *who*. |
| Decryption capability | One age identity per tenant | Preserves cryptographic separation between tenants instead of one org-wide key. |
| Broker language | Python | Reuses the `provider-credential-escrow` validators and `credential-manager` verification patterns directly. |
| Registry access | Live read-only git pull | One read-only deploy key per tenant; no new pipeline to maintain. |
| Keycloak install | Optional installer repo | Self-hosting is opt-in, so it follows the `Install-Wave-Terminal` pattern, not a forced submodule. |

## Separation of concerns

Each component does exactly one job:

- **Keycloak — authentication.** *Who are you?* GitHub is configured as an
  identity provider, and a mapper writes the GitHub login into a `github_login`
  token claim. That claim is the key the broker uses to locate
  `grants/users/<github_login>.json`, so the github-centric grant model is
  preserved.
- **Grant files — authorization.** *What may this identity use?* The existing
  `grants/users/<github-user>.json` patterns are unchanged and stay in the
  tenant registry.
- **SOPS — at-rest storage.** Ciphertext, unchanged.
- **Broker — the runtime that binds the three** and enforces release. It holds
  the per-tenant age identities, checks Keycloak identity against the grant
  files, decrypts in memory, validates the plaintext shape, and returns the
  credential over TLS.

## Flow

```
┌── bench / VPS ──────────────┐        ┌── shared org server ─────────────────┐
│ pclaude team001             │        │                                      │
│  └─ resolver:               │        │  Keycloak (realm: workbenches)       │
│     1. device-code login ───┼──OIDC──▶  ├─ GitHub identity broker           │
│        (cache refresh tok   │        │  ├─ groups: /tenants/*               │
│         0600 in profile)    │        │  └─ service-account clients (agents) │
│     2. POST credentials     │        │                                      │
│        Bearer <access tok> ─┼──mTLS──▶  Broker service (Python)             │
│        {tenant,provider,    │        │   ├─ validate token (aud-locked)     │
│         profile}            │        │   ├─ read grants/users/<gh>.json      │
│     3. writes plaintext ◀───┼────────┤   ├─ pull SOPS ciphertext (registry) │
│        into profile home    │        │   ├─ decrypt w/ tenant age identity   │
│        (same path as        │        │   ├─ validate plaintext shape         │
│         escrow restore)     │        │   ├─ audit-log the release            │
│                             │        │   └─ return plaintext over TLS        │
└─────────────────────────────┘        └──────────────────────────────────────┘
```

Step 3 writes to the exact path `provider-credential-escrow restore` writes
today, so the broker is a drop-in alternate restore source and the SOPS-direct
path remains available as break-glass.

## Keycloak realm layout

**Realm:** `workbenches` — a single realm, multi-tenant via groups.

**Identity brokering:** GitHub is configured as an IdP with a mapper that writes
the GitHub login into a `github_login` claim.

**Groups** express coarse "which tenant registries may I touch":

```
/tenants/opensoft
/tenants/farheap
```

A user belongs to one or more tenant groups. Fine-grained profile selection
stays in the grant files; Keycloak only asserts tenant membership.

**Clients:**

| Client | Type | Grant | Used by |
|---|---|---|---|
| `workbench-launcher` | public | device authorization + PKCE | the `p*` resolvers on workstations and benches |
| `workbench-broker` | bearer-only (resource server) | — | the broker API; tokens must carry its audience |
| `agent-<name>` | confidential | `client_credentials` | one per unattended agent or VPS |

**Audience:** a `broker-audience` client scope on `workbench-launcher` and every
`agent-*` client injects `aud: workbench-broker`. The broker rejects any token
missing its audience, so a token minted for another service cannot be replayed
against it.

**Token claims the broker consumes:** `sub`; `github_login` for humans or
`agent_id` for service accounts; `groups` (mapped to tenants); a short `exp`
(around five minutes, refreshed by the launcher).

## Broker API

Base `https://broker.<org>.internal/v1`. Every request uses mTLS and an
`Authorization: Bearer <keycloak access token>` header. On each request the
broker validates the signature (JWKS), issuer, `aud == workbench-broker`, and
`exp`, then resolves the caller identity (`github_login` or `agent_id`) and the
tenant set from `groups`.

### `GET /v1/entitlements`

Read-only; returns no secret values. Intersects the caller's tenant membership
with grant-file patterns across accessible tenant registries. This is the
broker-era equivalent of the loopback dashboard's profile-verification view.

```json
{
  "entitlements": [
    {
      "tenant": "opensoft",
      "kind": "ai-provider",
      "provider": "claude",
      "profile": "team-001",
      "credentialRef": "ai/secrets/claude/team-001.credentials.sops.yaml",
      "escrowStatus": "escrowed"
    },
    {
      "tenant": "opensoft",
      "kind": "cloud",
      "provider": "aws",
      "profile": "team-001",
      "mode": "federated"
    }
  ]
}
```

### `POST /v1/credentials:fetch`

The single credential-release path.

```json
{
  "tenant": "opensoft",
  "kind": "ai-provider",
  "provider": "claude",
  "profile": "team-001"
}
```

Broker sequence: resolve tenant → select the tenant age identity → read
`grants/users/<github_login>.json` → confirm `profile` matches a granted pattern
for `provider` → resolve `credentialRef` from `source.json` (reusing the
existing path-traversal guard) → decrypt in memory → run the existing
`validate_plaintext` shape check → return.

```json
{
  "leaseId": "ls_01J...",
  "ttl": 900,
  "materialization": {
    "path": "profiles/team-001/.credentials.json",
    "filename": ".credentials.json",
    "mode": "0600"
  },
  "credential": { "…": "opaque provider plaintext" }
}
```

The `materialization` block is exactly the current `profile_root` plus
`credential_name` mapping (`.credentials.json` for claude, `auth.json` for
codex, provider-specific homes for the rest), so the resolver writes it
atomically the same way escrow restore does.

Errors: `403` identity, grant, or tenant denied; `404` no escrow present; `409`
malformed escrow.

### `POST /v1/leases/<id>:renew` and `DELETE /v1/leases/<id>`

TTL re-fetch and explicit drop. The `leaseId` is wired in from the first
version even if renew ships later.

### `GET /v1/healthz`

Unauthenticated liveness.

### Cross-cutting

Every fetch emits a structured audit record —
`{ts, sub, github_login|agent_id, tenant, kind, provider, profile, leaseId,
outcome}` — and never the value. Decryption happens in memory only; the
plaintext is returned in the TLS response body only. Requests are rate-limited
per identity.

### The `kind` enum

`ai-provider | cloud | git | mcp`. For `kind: cloud` with `mode: federated`, the
broker performs an STS or OIDC federation exchange (Keycloak to
AWS/GCP/Azure) and returns short-lived cloud credentials instead of releasing a
stored long-lived key — so those cloud secrets need not sit in SOPS at all.

## Bench-side resolver

A shared function the `p*` launchers call before materializing a profile:

1. Canonicalize the requested name (`team001` → `team-001`) and take the
   provider from the launcher.
2. Ensure a Keycloak session: read the cached refresh token (mode `0600`) from
   the profile home; if missing or expired, run the device-code flow (print the
   verification URL and code, poll), and cache the refresh token.
3. Exchange for an access token with `aud: workbench-broker`.
4. `POST /v1/credentials:fetch` and write `credential` to `materialization.path`
   atomically (temp file plus `mv`, mode `0600`).
5. Record the lease and expiry; within the TTL on the next launch, skip the
   fetch.
6. Break-glass fallback: if the broker is unreachable **and** a local recovery
   identity is present, fall through to
   `scripts/provider-credential-escrow restore`.

## Machine identities

Unattended agents set `WORKBENCH_AGENT_CLIENT_ID` and its secret — the only
material escrowed per agent, and small and rotatable. The resolver detects these
and uses the `client_credentials` grant instead of the device-code flow. The
broker authorizes service accounts against a parallel
`grants/agents/<agent>.json`, keeping the same grant-file model:

```json
{
  "version": 1,
  "agent": "nightly-refactor",
  "tenant": "opensoft",
  "profiles": {
    "claude": ["team-001"],
    "aws": ["team-001"]
  }
}
```

This is the correct answer to the existing warning against using interactive
subscription OAuth for unattended automation: an agent gets only the credentials
its own grant allows, and disabling its Keycloak client revokes access
instantly.

## Registry access

The broker reads the ciphertext from the private tenant registries with a
**read-only deploy key per tenant**. It clones each registry once and `git
pull`s on a timer or on cache-miss, so it always sees the latest escrow. It is
safe for the ciphertext to reside on the broker host because it is encrypted and
only the per-tenant age identity — held only by the broker — can decrypt it.

A pushed object-store mirror (a CI job in each tenant repo publishing
`ai/source.json`, `ai/grants/`, and `ai/secrets/` to S3/MinIO) is a supported
alternative that decouples the broker from git, at the cost of a pipeline to
maintain. Live git pull is the recommended starting point.

## Deployment: the `Install-Keycloak` installer repo

Self-hosting Keycloak is opt-in — a team using a shared org server should never
be forced to pull it — so it follows the `Install-Wave-Terminal` pattern rather
than becoming a submodule. `setup.sh` can clone `opensoft/Install-Keycloak` on
demand (sibling checkout preferred, else `~/.cache/workbenches/`, with env
overrides), best-effort. The installer repo is secret-free and contains:

- `docker-compose.yml` — Keycloak plus Postgres, with TLS and healthchecks.
- `realm-workbenches.json` — an importable realm export: the `/tenants/*`
  groups, the `workbench-launcher` and `workbench-broker` clients, the
  `broker-audience` client scope and mapper, and a GitHub IdP stub with the
  `github_login` mapper. Placeholders only; the GitHub OAuth application id and
  secret and any client secrets are entered at bootstrap and never committed.
- `scripts/bootstrap.sh` — bring up the stack, import the realm, prompt for the
  GitHub OAuth credentials, and print the device-flow client id and broker URL
  to drop into workBenches config.

The **broker service itself lives in workBenches** at `apps/credential-broker/`,
next to `apps/credential-manager/`, because it reuses the Python escrow code
directly. Only Keycloak, its compose file, and the realm export live in
`Install-Keycloak`, keeping the auth-server install separable from the
credential logic.

## Reuse versus build

Reused as-is from the current codebase:

- the `validate_plaintext` provider shape validators;
- `credentialRef` resolution and the path-traversal guard;
- the `profile_root` and `credential_name` materialization mapping;
- `grants/users/*.json`;
- `source.json` discovery;
- the atomic-write pattern (temp file plus `mv`, mode `0600`).

Built new:

- the Python broker service (`apps/credential-broker/`);
- the Keycloak realm, client, and scope configuration (secret-free, shipped in
  `Install-Keycloak`);
- the shared launcher resolver function;
- `grants/agents/*.json`.

## Security model

- The broker is a crown-jewel target. It requires mTLS, audience-locked tokens,
  per-request audit, in-memory-only decryption, no value logging, and per-identity
  rate limiting.
- A released vendor token lives wherever it is materialized. Mitigate with a
  short materialization TTL plus re-fetch, and keep per-profile isolation so a
  leak is scoped to one identity.
- Keycloak revokes *access* instantly by disabling an identity or client, but a
  leaked vendor secret still requires vendor-side rotation, exactly as today.
- The shared-server model introduces a network dependency and requires benches
  to trust the Keycloak realm URL and CA. The SOPS-direct restore path remains
  the offline break-glass fallback.
- Every artifact shipped in the public repositories — the realm export, group,
  client, and scope definitions, the broker code, and the resolver — is
  secret-free. Only credential values remain in SOPS and are held in memory by
  the broker.

## Open questions

- Lease renewal semantics and whether the broker tracks outstanding leases for
  active revalidation or only issues opaque TTLs.
- Whether federated cloud credentials (`mode: federated`) ship in the first
  version or after the SOPS-backed `kind`s.
- Whether the broker should also serve the read-only `credential-manager`
  dashboard's verification view directly, replacing its local-only inspection
  for shared-server deployments.
