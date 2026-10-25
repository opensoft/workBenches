# Design boundary and current readiness

Keep identity scopes, provider AI profiles, source connections and AI credential
stores distinct. Associate sources with stable local personal/company IDs, not
an email-domain guess. A connection can be explicitly linked to multiple scopes;
detaching one source must not delete another scope's usable connection.

The source record stores its type, stable file/repository locator, repository
path/ref where relevant, verified account/tenant identity and connection ID.
It also records the last successful revision/check and import result. Store
neither bearer tokens nor transient preauthenticated download URLs in that record.
Retain a validated local copy and reconstruct launcher paths on this workstation;
do not import another host's paths, symlinks or OAuth sessions as profile metadata.

Local JSON needs no web login. GitHub and private Microsoft/Google files use a
system-browser OAuth flow (device approval where supported, otherwise native-app
authorization code with PKCE). Provider applications/scopes must be configured
and qualified. No password, PAT, service-account credential or pasted token is
an interactive source-login method for this scope. Public HTTPS files require
no invented login. Unsupported protected URLs report that they need a supported
provider connector rather than scraping browser cookies or forwarding tokens.

Retain account authorization across restarts with a provider-supported protected
token cache/native keyring, separate from the manifest. Request read and renewal
permissions only as justified by the confirmed operation. Reuse valid access,
renew when authorized and supported, and require browser reauthentication after
expiry/revocation/denied consent. Never promise perpetual login. Connection
status must distinguish authorization failure from temporary transport failure.

Current GitHub browser login persists isolated gh configurations, but catalog
discovery/cloning still uses ambient gh/Git in the old onboarding path. Wire the
selected connection through every discovery/content fetch. Current Keycloak
company login stores a private session; offline refresh is conditional on opted-in
company sync. Neither path implements Microsoft Graph/Google Drive authorization.
Keycloak external-token brokering requires separate provider/server/client
configuration and is not supplied by today's public-client device login.

Import validates the supported versioned schema, ownership/grants, collisions
and local destination before a full review/merge. Preserve other scopes,
existing credentials, the last good local copy and queued installer selections
on failure or cancellation. Importing metadata does not authenticate AI accounts.
Use existing explicit vault recovery or provider sign-in independently.

For v1.8, a service shipped with workBenches may provide authenticated peer
discovery/catalog/export and authorized import over an approved transport such
as HTTPS/Tailscale. Its network trust, account policy, service lifecycle and any
credential-transfer operation require their own implementation design. Existing
openProfiler ownership/pinned integration (#229) remains the product boundary;
the peer-service target is specifically v1.8, not v1.7 or v1.6.2.

Qualification needs disposable two-company/personal fixtures, multiple provider
accounts, reboot/cache reuse, renewed/revoked/denied consent, cancellation,
malformed links, expired downloads, conflicts, reruns and offline preservation.
Approved live browser/API tests remain necessary; no credentials are read while
documenting this proposal. Remote publishing scope is pending clarification.

References:
- [Keycloak external identity-provider tokens](https://www.keycloak.org/docs/26.8.0/server_development/#_identity_brokering_apis)
- [Google native application OAuth](https://developers.google.com/identity/protocols/oauth2/native-app)
- [Microsoft permissions and scopes](https://learn.microsoft.com/en-us/entra/identity-platform/scopes-oidc)
