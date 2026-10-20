# GitHub QA team authorization

Provide a fail-closed, broker-side authorization component and an attended live
probe for the designated Opensoft-Testing accounts. User 1 is a member of
workbenches-qa-allowed; User 2 is an ordinary organization member excluded from
that team. Verify delegated GitHub identity and fresh team membership, not
caller-provided claims. Unknown profiles, wrong organizations, unavailable APIs,
and incomplete membership pagination never authorize credential release.

This increment supplies a nonproduction policy, component, tests, and isolated
attended probe. No vendor secret is created or fetched. Actual broker deployment,
its identity-provider integration, TUI end-to-end adapter, and company OIDC
provisioning remain prerequisites; no release gate is relaxed or marked passed.

Validation: deterministic allow/deny, organization isolation, fresh revocation,
pagination, unknown profile and failure behavior run with release framework tests.
Live browser consent requires the two QA account owners on disposable Eagle.
