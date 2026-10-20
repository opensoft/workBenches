# Unattended GitHub QA session coordinator

The main-only `GitHub QA session renewal and team authorization` workflow runs
every four hours and on dispatch. It is separate from the complete github-live
UI release adapter: it certifies actual identity, token renewal and current team
membership, not browser approval or clipboard behavior.

The protected `release-qa` environment admits main only. Azure OIDC federation
binds exactly `repo:opensoft/workBenches:environment:release-qa` to
`id-openbenches-qa-coordinator` in `rg-openbenches-qa`, QA subscription
297b2389-33bf-48c8-8deb-0b92838431e4. The identity has Secrets Officer at only the
two session-secret scopes in `kv-openbenches-qa`, not the vault or subscription.
The role permits rotation of those test credentials; no production access is
assigned. Environment variables OPENBENCHES_QA_AZURE_CLIENT_ID, _TENANT_ID and
_SUBSCRIPTION_ID are identifiers, not secrets. No PAT or Azure client secret is
stored in GitHub.

Initial consent uses `qa/release/provision-github-qa-sessions.py`; it stores
minimal read:org GitHub CLI device-flow OAuth bundles for Opensoft-Test-User-1
(ID 345520656) and Opensoft-Test-User-2 (ID 345521882), including refresh tokens
when supplied. Passwords/recovery codes are never collected. Device codes are
not saved to the vault. Initial GitHub consent can require a person; recurring
runs do not invoke it.

`qa/release/github-vault-sessions.py` reads the private bundles through Azure CLI
already authenticated by azure/login's workload identity. It rotates near expiry,
revalidates immutable identity and scopes, writes back the new token pair, then
checks fresh paginated GitHub membership. User 1 must belong to
Opensoft-Testing/workbenches-qa-allowed and User 2 must not. A wrong identity,
missing scope, API failure, incomplete pagination or unexpected decision fails.
Only fixed metadata is printed; token values never enter argv, environment,
artifacts or transcripts. Private upload files are RAM-backed and removed.

One concurrency group serializes all workflow writers. The local coordinator
also uses a private flock; that is not distributed locking. Do not run manual
provisioning/renewal while the workflow is executing. A stored renewal-intent
version prevents replay after an ambiguous one-use refresh. If rotation is
interrupted before the new pair is saved, automatic runs fail closed and require
recovery or fresh account authorization; they never silently use an older token.

GitHub's device-flow refresh supports the public client ID without a client
secret. Source: https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps#refreshing-an-access-token-with-a-refresh-token

No overall WB_QA_CONFIGURED flag is enabled by this workflow. Real company OIDC,
provider, native-platform and TUI release suites retain their independent gates.
