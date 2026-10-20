# Automated release QA completion checklist

Goal: get the entire automated test system running, not merely its unit tests.
Use config/release-tests.json on the automation branch as the release contract.

## Current evidence (2026-10-20)

- v1.6 broker PR #181: 40 declared Compose tests pass; all hosted PR checks pass
  at 39aa0d2. Managed and AKS workload identities are explicit SDK modes, with
  no Azure CLI/default-credential fallback in the broker.
- Raven isolated Arch provisioning VM: built the broker image and passed 34
  tests at 3a60291; stopped with private disk preserved. Not a reset release runner.
- Dedicated Azure QA vault kv-openbenches-qa contains verified read:org OAuth
  sessions for Opensoft-Test-User-1 and Opensoft-Test-User-2, including refresh
  tokens. No passwords or production credentials were collected.
- Live unattended GitHub renewal proved both tokens rotate and are written back
  to the vault. Fresh membership checks allow User 1 and deny User 2.
- PR #182 is merged on main. Its four-hour scheduled coordinator uses GitHub
  OIDC and an identity scoped to the two QA session secrets only. Actual main
  workflow run 39502004154 passed real renewal and team authorization for both
  users. This does not satisfy the browser/device-flow acceptance cases.
- Actual AKS job openbenches-kv-20261020-v1 passed the AzureVault workload-identity
  roundtrip/idempotency probe and received HTTP 403 for both GitHub session
  secrets. The broker identity can access only its fictional provider fixture;
  this proves the bounded KV path, not real vendor refresh or provider-live.
- PR #185 (encrypted fixture diagnosis), #186 (native controller/shell fixture
  isolation and Eagle prompt), and #187 (isolated Team001 bootstrap) are merged
  on main. Combined release framework tests: 36 pass. Bootstrap tests: 6 pass.
- Hosted full v1.6 fixtures at 6a3ca16: 11/12 pass. Fresh install fails at
  bench-install on GitHub runners. The same candidate passes the full local
  workstation acceptance; do not treat local success as hosted success.
- Hosted investigation run 39503962450 is in progress on candidate 7951f5b and
  automation 956dd64. Eleven hosted suites passed; fresh-install is still running.
- Fresh Arch run arch-native-run-20261020-v2 is still running against candidate
  a05f815 and automation 37a9fc1. Tool/cancellation/CLI/shell/vault cases passed;
  bench discovery is stalled before installation. Do not claim native completion.

## Still required (completion is unproven)

1. Make hosted fresh-install pass and rerun all hosted suites plus evidence gate
   on the final candidate. Preserve private diagnostic policy.
2. Connect the real live adapters to the provisioned QA sessions and identities;
   scheduled token renewal/team checks are already running independently.
3. Fresh per-job native Arch VM lifecycle and actual native acceptance.
4. Isolated Eagle WSL worker and WSL acceptance. Raven cannot certify WSL.
5. Restricted public-repository runner group permitting only the protected main
   QA workflow; ephemeral runner registration, cleanup/watchdog and inventory.
6. github-live: actual browser-open, clipboard-code, account-a-login,
   account-b-login, reuse-no-switch, reauth, cancel, cleanup. Saved OAuth tokens
   alone do not prove browser device approval or replace those UI cases.
7. company-live: two real QA company identity contexts, delegated sign-in,
   signout/reconnect, expiry, denied user, tenant isolation and cleanup. GitHub
   users are not company OIDC subjects. Do not substitute client credentials for
   delegated Microsoft browser sign-in.
8. provider-live: explicitly approved provider mode, broker managed-identity KV,
   publication/recovery/conflicts/offline/login-required/CPC refresh/tenant denial
   and cleanup, using authorized nonproduction provider profiles.
9. v1.7 device tests: hosted device-SSH plus real registration, directional
   approval, owner/reverse denial, connect, revoke, offline expiry and cleanup.
10. Install and pin real adapters; produce exact-source/automation evidence from
    scheduled/release workflows. Enable readiness only when prerequisites pass.
    No fabricated attestation, missing-case bypass or fixture-to-live relabeling.

Live deployment prerequisites remain external: QA issuer/client/subjects,
restricted GitHub organization administration scope, workload identity, approved
provider profiles/mode, and an accessible isolated Eagle execution environment.
Keep this checklist tied to observed runs; passing tests are not proof of cases
that they do not exercise.

## Provider slots selected by the user

- Claude: Team001, Team-001@opensoft.one (local canonical profile team-001).
- Codex: Team001, Team-001@opensoft.one (local canonical profile team-001).
- DeepSeek: Team001; reserved for the user's planned free API model setup.
- GLM: Team001; reserved for the user's planned free API model setup.

Use a separate credential/session for each provider under the shared Team001
profile. DeepSeek and GLM remain pending, rather than passing or silently omitted,
until the user supplies the configured model identifiers and credentials through
the approved vault path. Their free-tier availability and limits must be checked
when those models are selected.

Claude/Codex production backup sessions were found but are expired. Independent
QA sign-ins are pending in isolated Raven credential directories; no successful
provider-live result is claimed yet. Store verified new sessions only in
kv-openbenches-qa. Do not force-rotate a shared production session to make a test
pass. The generic RFC 7662 adapter explicitly does not support Claude/Codex
subscription refresh; provider-specific native support is required.

Codex account-auth automation must run in private infrastructure, with one
serialized owner of each refreshable credential copy and durable persistence of
native CLI updates. Do not run that account-auth workflow from this public
repository's Actions workflows; see the official
[Codex CI/CD authentication guidance](https://learn.chatgpt.com/docs/auth/ci-cd-auth).
