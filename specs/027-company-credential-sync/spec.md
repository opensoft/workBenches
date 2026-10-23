# Company credential publication and synchronization

Target: **v1.6.0**, after v1.5 ships. Status: implementation on
`feature/profile-onboarding`; fixture validation and live deployment gates are
tracked in [tasks](tasks.md). See the [operational guide](../../docs/company-credential-sync.md).
This extends [Profiles onboarding](../026-profile-onboarding/spec.md).
OpenSoft is the initial deployment, not a hardcoded tenant.

## User outcome

A user signs into their company through its identity provider (OpenSoft uses
Microsoft Entra through Keycloak). The broker returns the company AI profiles
the user may use. The workstation can install those approved credentials into
managed Claude, Codex, or OpenCode profile storage where that provider supports
the credential format and sharing model.

When an approved contributor logs into a designated shared provider profile,
workBenches detects the changed credential, verifies the expected provider account,
and submits it to the broker. An accepted update creates a new Key Vault secret
version. Other authorized workstations discover and safely apply that version.
Not every user may update every profile; administrators can grant use and
publication to the same users when desired.

## Identity, permissions, and storage

| Component | Responsibility |
| --- | --- |
| Entra or another company IdP | User identity, MFA, organization membership |
| Keycloak | Federated sign-in and broker-audience tokens |
| Administrator-controlled tenant grant registry | Exact profile use, publication, and maintenance grants |
| Server-side credential broker | Enforce grants, validate updates, serialize publication, audit releases |
| Azure Key Vault | Versioned credential values |
| CPC maintenance worker | Scheduled checks and supported refreshes through the broker |

The detailed grant registry is the authorization source of truth. Company groups
can map to grants, but company membership alone grants no provider credentials.
Bind user grants to verified immutable identities (issuer/subject and, where
applicable, Entra tenant/object IDs). Do not authorize by entered email, mutable
GitHub username, or unverified identity linking. Existing GitHub-based grant files
need an explicit migration/mapping for federated company identities.

Separate capabilities: `profile:use`, `profile:publish`, and `profile:maintain`.
The server resolves profile IDs to secret names; clients cannot supply arbitrary
vault names, secret paths, or tenants outside their grants. Personal profiles,
other companies' profiles, company identity tokens, and GitHub login tokens are
excluded from shared AI credential publication.

Ordinary users and workstation clients receive no direct Key Vault data-plane
permissions or vault application secrets. The broker's managed identity gets only
the required secret-read/write permissions. No workstation receives that identity.
Privileged administrative access remains a separately controlled operational path.
The CPC uses a service identity with explicit maintenance grants and calls the
broker; it does not require independent direct Key Vault access.

This is a proposed Key Vault-backed company flow. The older
[SOPS broker design](../../docs/keycloak-credential-broker.md) remains a separate
storage adapter proposal, not evidence that this flow is already deployed.

## Local change detection and publication

1. Watch only configured managed profile stores, with periodic reconciliation
   and a check after managed login completes. Provider adapters cover files,
   keychains, or other supported stores; do not scan arbitrary user credentials.
2. Debounce changes and wait for a stable, complete credential record. Distinguish
   local login/rotation from a broker download to avoid upload/download loops.
   Missing files, logout, and partial writes are not shared credential updates.
3. Validate credential shape, expected provider account, profile binding, expiry,
   and sharing eligibility using a provider-supported method. Do not publish a
   login to a different account merely because the destination filename matches.
4. Submit an authenticated publication with the expected current broker version
   and an idempotency key. The broker checks publication grants and validates the
   candidate before it becomes authoritative. No credential values enter logs.
5. Serialize updates across broker replicas using transactional metadata or a
   distributed lock plus an atomic expected-version comparison. Do not assume
   Key Vault alone provides this application-level compare-and-set transaction.
6. Create a new Key Vault version and commit the authoritative profile-version
   pointer. Recover interrupted publication idempotently; an uncommitted vault
   version must not become authoritative merely because it is the newest.
7. Reject stale publications as conflicts. Keep the workstation's unsent local
   credential private and require reconciliation; never silently overwrite it
   with a remote version or replace the remote credential by last-writer-wins.

Record tenant/profile, actor identity, operation, version, and outcome in an audit
trail without token values. Backend retention and deletion follow company policy;
an older credential version must not be advertised as usable after rotation.

## Workstation synchronization

Check broker metadata on startup/resume, before launching a managed profile,
and every **60 minutes with jitter** while the synchronization agent is running.
If no persistent agent is running, launcher checks still apply; setup alone does
not establish a background service. Check immediately on an authentication error
and retry once only when a newer valid credential was installed. Rate limits and
other non-authentication errors must not trigger a credential-refresh loop.

Metadata requests return only profiles still authorized for that caller and their
opaque versions. Fetch credential values only when needed. Recheck grants on each
fetch; a notification is not authorization. Install credentials with private atomic
writes or the provider's supported credential-store API. Coordinate active local
writers; do not replace an in-progress login or dirty unpublished credential.

Optional later acceleration: Key Vault Event Grid events notify the broker, which
reconciles the authoritative version before notifying clients. Clients still poll
to recover from missed events. Notifications contain no credentials and do not
give clients direct vault access. Network failures use bounded retries/backoff;
offline clients cannot claim their credentials are current.

## CPC scheduled maintenance

Add a dedicated scheduled **CPC maintenance worker**. Its precise hosting/runtime
is to be chosen; this specification does not assume a particular CPC platform.

- Run a weekly inventory and health sweep across every profile it is permitted
  to maintain. Report expiry, last successful refresh, publication version, and
  profiles needing interactive login. Do not equate file age with validity.
- Schedule actual refreshes from provider-supported expiry/refresh rules with a
  safety margin and jitter. A weekly job alone cannot keep short-lived tokens
  fresh; profiles needing more frequent refresh must have a more frequent job.
- Acquire the same exclusive per-profile refresh/publication control as other
  writers; fetch the authoritative version and verify it again before refresh.
  Use only supported refresh mechanisms. Handle both access-token renewal and
  refresh-token replacement when the provider rotates the latter.
- Validate and publish supported refreshed credential bundles through the broker,
  creating a new authoritative version for workstation synchronization.
- On expiry/revocation requiring interactive reauthentication, stop automatic
  retries, mark `login required`, and notify an approved maintainer. The worker
  cannot bypass MFA, consent, account policy, or provider revocation.
- Expose maintenance results to profile administrators. Never log credential
  bodies or blindly retry a possibly consumed rotating refresh token after an
  ambiguous network failure; reconcile or require login as the provider permits.

## Provider eligibility and security boundaries

Shared API credentials and portable sessions require explicit provider eligibility
and company approval. Claude, Codex, and OpenCode are integration targets, not a
claim that all their authentication modes support copying or unattended refresh.
OpenCode eligibility depends on the underlying provider/authentication mode.

Rotating refresh tokens can invalidate earlier copies; concurrent workstation
refresh can revoke an entire token family. Polling, Key Vault versioning, and a
weekly CPC job do not solve this race. Enable sharing only after verifying a
supported model: independent per-device sessions, broker-exclusive refresh with
clients prevented from competing refreshes, or a compatible server-side gateway.
If the native client cannot cooperate, disable shared-session synchronization for
that mode and offer per-user login. Serialize CPC refreshes with workstation
publication; do not assume a broker lock controls an unmodified third-party CLI.

Once a credential is delivered to a user-controlled workstation, the user can
potentially extract it. Broker-only vault access does not guarantee app-only use
of delivered secrets. If users must never receive reusable provider secrets,
choose supported server-side execution/gateway integration instead of local
credential materialization. Offboarding blocks future broker access; already
delivered tokens may require provider-side revocation/rotation.

## Release acceptance

v1.6 inclusion requires broker identity/grant enforcement, Key Vault integration,
one explicitly validated provider mode end to end, conflict-safe publication,
workstation polling/installation, and CPC maintenance behavior. Unsupported modes
stay disabled. Do not delay v1.5 or quietly ship a partially secured sync path.

Test unauthorized read/write, cross-tenant access, account mismatch, local dirty
state, concurrent publishers and CPC refresh, replay/idempotency, rotation and
ambiguous failures, logout/partial writes, expired/revoked sessions, missed polls,
offline recovery, event duplication, audit redaction, and offboarding. Run live
provider tests with designated test profiles and document results per mode.

References: [OAuth refresh-token security](https://www.rfc-editor.org/rfc/rfc9700.html#section-4.14),
[Key Vault events](https://learn.microsoft.com/en-us/azure/key-vault/general/event-grid-overview),
[Key Vault RBAC](https://learn.microsoft.com/en-us/azure/key-vault/general/rbac-guide).
