# Enforce GitHub team membership at the v1.6 broker boundary

Add an optional profile-level team restriction in addition to existing verified
OIDC issuer/subject grants. An administrator binds those immutable subjects to
GitHub numeric account IDs. Check the current team membership on every user
metadata/fetch/publish request; fail closed on API/config errors. Keep dedicated
CPC service maintenance governed by its own OIDC grants. Preserve existing
profiles without a GitHub restriction.

Expose no GitHub token to clients: the broker uses a private server-only Members
read credential. Extend the existing TUI selection's empty-profile message.
Provide a strictly unattended live broker probe using pre-provisioned, renewable
QA company sessions. No browser/password/MFA interaction during recurring tests;
reauthorization is a provisioning failure, not an automated pass.

Validate through the declared credential-sync Compose service: allowed/denied
metadata, HTTP fetch/publish, revocation, immutable ID mismatch, duplicate/missing
bindings, API failures, private token storage and unattended probe strictness.
Actual deployment requires QA OIDC subjects/sessions, a QA-only seeded credential,
and a server-side GitHub membership credential. No live release gate is bypassed.
