# Company credential synchronization — v1.6 development

Implemented on `feature/profile-onboarding`; not deployed or certified for real
Claude/Codex/OpenCode subscription sessions. All example profiles are disabled.
The [specification](../specs/027-company-credential-sync/spec.md) records the
provider eligibility and security boundaries. v1.5 is unchanged.

## Components

- `credential-broker/`: authenticated WSGI service with RS256/JWKS verification,
  fixed issuer/audience, immutable issuer/subject grants, redacted audit records,
  and Azure Key Vault access through `ManagedIdentityCredential` only.
- `scripts/credential-sync.sh`: optional workstation command/agent using declared
  Tools on minimal hosts. Its Python client polls managed files every 30 seconds,
  debounces completed changes, and checks broker metadata hourly with jitter.
- Launcher hooks: configured Claude, Codex, and OpenCode profile launchers check
  before starting sessions and publish after successful managed login. A local
  lease prevents the background agent from replacing a credential during a
  managed session/login. Unmanaged profiles are unaffected.
- `credential-broker/cpc.py`: separate maintenance service using an IdP service
  account with profile maintenance grants. It checks every five minutes by
  default. The broker performs weekly health validation and expiry-driven refresh
  within each profile's safety margin, not a blind weekly token refresh.

## Broker configuration and deployment preparation

Start from [credential-broker.example.json](../config/credential-broker.example.json).
Set the actual organization issuer, broker audience and JWKS URL. Map approved
immutable user subjects to `use` and/or `publish`; give the CPC service subject
`maintain`. Grants and profile disabling are reloaded for every request. Changing
deployment issuer/audience/JWKS/database requires restart. Do not use an entered
email, GitHub username, or organization membership alone as a profile grant.

Configure a dedicated Key Vault secret per enabled profile, the expected provider
account ID, a validated adapter command, and explicit `sharingApproved: true`.
Never enable a mode merely because its JSON looks like an auth file. Multiple
profiles must not alias the same vault secret; grant multiple users access to a
single profile instead.

Deploy the broker on an Azure host with managed identity and narrowly scoped
secret get/list-version/set rights. Users, workstation clients, and the CPC have
no direct vault data-plane permissions. The broker never falls back to Azure CLI
user credentials. Administrative access is a separate privileged operational path.

This implementation supports **one broker instance on one host**, with SQLite and
publication locks on the same persistent local filesystem. Do not deploy multiple
hosts, use a network filesystem, or run independent state volumes against the
same profile secrets. A multi-host deployment needs distributed transactional
metadata/locking first. Protect and back up the metadata together with vault
version history; losing metadata is not repaired by blindly selecting KV latest.

The [Compose definition](../credential-broker/compose.yml) expects:

```bash
export WORKBENCHES_BROKER_CONFIG_FILE=/absolute/path/broker.json
export WORKBENCHES_BROKER_STATE_DIR=/absolute/path/private-broker-state
export WORKBENCHES_BROKER_ADAPTER_DIR=/absolute/path/admin-managed-adapters
docker compose -f credential-broker/compose.yml up -d --build broker
```

Prepare these directories/configs for service UID/GID **10001**. State must be
private and writable by that UID; adapter code/configs must be readable/executable
but not writable by it. Protect any provider adapter client-secret files and
mount them read-only. No real secrets belong in the repository or shell arguments.

The broker binds host loopback port 8080. Put it behind a trusted HTTPS ingress
with request-size/rate limits and appropriate network controls before clients
connect. Do not expose the HTTP port directly. Gunicorn access logging is disabled
to avoid credential-bearing request metadata; operational/audit access is server-side.
Starting these services provisions no Azure resources or role assignments.

## Provider adapter contract

Adapter commands are administrator-managed absolute argv lists; no shell is used.
They receive JSON on stdin and return JSON on stdout within 30 seconds. Credentials
must not be printed elsewhere. Raw adapter exceptions/stderr are not reflected to
clients. Validation must be nonmutating and prove account identity with the actual
provider; trusting a client-supplied `accountId` is insufficient.

Validation input includes `action: validate`, `credential`, expected `accountId`,
`provider`, and `profile`. Output:

```json
{
  "valid": true,
  "accountId": "provider-confirmed-account",
  "expiresAt": 1900000000,
  "publicCredential": {"provider-specific-access-credential": "..."}
}
```

`expiresAt` is Unix seconds, or null for a supported nonexpiring key.
`portable` mode rejects refresh-token-bearing bundles. `broker-refresh` requires
an expiry and refresher command; only its access credential projection reaches
workstations, never the shared provider refresh token. The third-party CLI must
work with that projection without competing refreshes before enabling the mode.

Refresh input has `action: refresh` and the current server-only credential bundle.
Output is `{"credential": {...}}`; the broker independently validates it before
publication. Adapter timeouts/failures require maintainer attention; an ambiguous
rotating refresh is never automatically replayed.

`credential-broker/oauth_adapter.py` implements RFC 7662 introspection plus OAuth
refresh for providers explicitly supporting `client_secret_post`, the configured
audience/scopes, and this sharing model. See
[oauth-adapter.example.json](../config/oauth-adapter.example.json). Use commands
such as `["/usr/local/bin/python3", "/app/oauth_adapter.py", "/adapters/provider.json"]`
for validator/refresher. Configure native JSON token paths, expiry units and
rotation behavior. This is **not** a ready-made Claude/Codex subscription adapter;
those endpoints/modes require separate provider validation. The test adapter under
`devcontainer.test/fixtures` is fictional and must never handle production credentials.

## Workstation setup

1. Open setup → **G Profiles** → **Personal & companies** → select a company →
   **Y Company credential synchronization**.
2. Configure the administrator-provided HTTPS broker URL and company tenant ID.
   Enrollment can supply `credentialBrokerUrl` and `organizationId` as reviewed
   defaults. Enabling sync installs
   the optional `workbenches-credential-sync` helper without overwriting an unrelated
   command. Changing an existing company's broker URL or tenant requires a separate company
   identity so unsent credentials cannot silently move to another destination.
3. Use **C Company sign-in** again. Sync-enabled company login requests
   `offline_access`; the IdP must permit that scope and include the broker audience.
   The private company session holds its own refresh token, never shares it, and
   serializes renewal against local sign-out. Without background renewal approval,
   an expired company session shows login required.
4. Add approved profiles from the broker's authorized list. Supply the exact native
   company credential JSON path and explicitly consent to management/publication.
   Bare personal stores and known personal-profile paths are refused. Do not point
   a company entry at an unrecognized personal or another company's store.
5. Check now or start background sync. Unrecognized preexisting local credentials
   require explicit adoption; they are never uploaded automatically. In portable
   mode, **Publish an existing local credential** adopts one with confirmation.
   For broker-refresh mode use the managed provider login action; it records the
   pre-login version and removes the local shared refresh token after publication.

Commands from an installed helper:

```bash
workbenches-credential-sync --status
workbenches-credential-sync --before-launch /absolute/company/profile/auth.json
workbenches-credential-sync --auth-failed /absolute/company/profile/auth.json
workbenches-credential-sync --stop
```

An authentication-failure check is explicit; the implementation does not blindly
replay an arbitrary CLI command that might have already performed work. A provider
integration may retry once after confirming an auth error and a newer credential.
The start action runs a persistent process for the current workstation session;
it does not install an OS boot service. Before-launch checks still work while the
agent is stopped. Bench containers need the helper/checkout available on their
mounted PATH to use opt-in hooks. Managed coordination currently requires `flock`.
Direct third-party CLI launches that bypass these wrappers are not coordinated.
Managed launches fail closed when the fresh authorization/version check cannot
complete. Disabling synchronization preserves local credentials; it is not a
provider-side revocation mechanism.

Local company config/state live under
`~/.config/workbenches/identities/<company-id>/credential-sync*.json` (XDG supported).
State records fingerprints, versions, pending operation IDs, and statuses, not
credential bodies. Native provider credential files remain private. Conflicts,
partial writes and logout preserve local state; logout does not immediately
download the same credential and sign the user back in. **F Fetch remote and
replace local** explicitly restores or resolves a local conflict after confirmation;
it refuses a remote version that is still pending broker reconciliation.

For offboarding, remove broker grants and revoke company IdP/offline sessions as
appropriate. Grant removal takes effect on the next broker request even if an
existing bearer token has not expired. Entra lifecycle changes do not automatically
edit this grant registry. Already delivered provider credentials may also require
provider-side revocation or rotation.

## CPC scheduling and alerts

Create an IdP confidential service client restricted to broker maintenance grants.
Use [cpc.example.json](../config/cpc.example.json) and a protected service client
secret mounted only into the CPC. Configure these additional paths:

```bash
export WORKBENCHES_CPC_CONFIG_FILE=/absolute/path/cpc.json
export WORKBENCHES_CPC_CLIENT_SECRET_FILE=/absolute/path/private/cpc-client-secret
docker compose -f credential-broker/compose.yml --profile maintenance up -d --build
```

Each five-minute scheduler tick asks the broker to inspect authorized profiles.
The broker skips recent healthy entries, refreshes supported near-expiry entries,
and performs an otherwise weekly health sweep. `refreshMarginSeconds` must exceed
the CPC interval plus expected request time. No provider supports perpetual login
merely because this process exists; revoked sessions or MFA still need a person.

CPC emits redacted JSON maintenance/attention events on stdout. Optional
`alertsWebhookUrl` and `alertsBearerTokenFile` send metadata-only HTTPS alerts to
an administrator-configured endpoint; mount any alert token separately read-only.
Repeated identical attention states are deduplicated within a CPC run. Route logs
or the configured webhook into the organization's alerting system.

## Publication/recovery API

All endpoints require an unexpired broker-audience bearer token:

| Endpoint | Capability / purpose |
| --- | --- |
| GET `/v1/profiles` | Authorized metadata and current version/status only |
| POST `/v1/fetch` | `use`; body `profileId`, returns current public credential/version |
| POST `/v1/publish` | `publish`; `profileId`, `credential`, `expectedVersion`, `idempotencyKey` |
| POST `/v1/maintain` | `maintain`; `profileId`, weekly health or expiry-driven refresh |
| POST `/v1/reconcile` | `maintain`; recover a completed vault write tagged with the pending operation |
| POST `/v1/require-login` | `maintain`; `profileId`, `expectedVersion`; explicitly abandon a stalled refresh/publication after at least two minutes and require fresh login |

Publication reserves an expected version durably before KV I/O, tags the new KV
version with its operation ID, and commits an authoritative pointer afterward.
Retries reuse the operation, including after a lost response. Stale writers are
rejected; KV's latest version is never implicitly authoritative. A crashed refresh
remains blocked. First reconcile any completed KV write; if none exists, an approved
maintainer can require a new login. Stop/reconcile a stalled worker before
abandoning its operation. This does not replay a potentially consumed
provider refresh token or make an old token valid again.

## Verification and remaining release gates

The declared `credential-sync` service in `devcontainer.test/docker-compose.yml`
runs fictional provider/vault tests, including real local HTTPS transport, RS256
token verification, grants/revocation, concurrency/idempotency, interrupted writes,
two-workstation sync, dirty/local logout protection, CPC rotation, and alerts.
No real Azure vault, company identity, or provider credentials are used by these tests.

Live managed-identity KV deployment, approved provider-mode validation, alert routing,
and platform acceptance remain required before the feature is enabled for a company
or included as validated functionality in the v1.6 release.
