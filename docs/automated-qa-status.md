# Automated release QA completion checklist

Goal: get the entire automated test system running, not merely its unit tests.
Use config/release-tests.json on the automation branch as the release contract.

## Current evidence (2026-10-20)

- v1.6 broker PR #181: 36 declared Compose tests pass; hosted checks pass at its
  prior revision. Latest code includes private QA OAuth provisioning.
- Raven isolated Arch provisioning VM: built the broker image and passed 34
  tests at 3a60291; stopped with private disk preserved. Not a reset release runner.
- Dedicated Azure QA vault kv-openbenches-qa contains verified read:org OAuth
  sessions for Opensoft-Test-User-1 and Opensoft-Test-User-2, including refresh
  tokens. No passwords or production credentials were collected.
- Live unattended GitHub renewal proved both tokens rotate and are written back
  to the vault. Fresh membership checks allow User 1 and deny User 2.
- Hosted full v1.6 fixtures at 6a3ca16: 11/12 pass. Fresh install fails at
  bench-install on GitHub runners. The same candidate passes the full local
  workstation acceptance; do not treat local success as hosted success.

## Still required (completion is unproven)

1. Make hosted fresh-install pass and rerun all hosted suites plus evidence gate
   on the final candidate. Preserve private diagnostic policy.
2. Unattended vault session retrieval/rotation wired into the QA coordinator,
   with single-writer scheduling and least-privilege workload identity.
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
