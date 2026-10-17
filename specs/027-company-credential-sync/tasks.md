# Company credential synchronization — target v1.6.0

- [x] Record the proposed architecture, version target, and security boundaries.
- [x] Include CPC weekly health checks and expiry-driven refresh scheduling.
- [ ] Validate provider sharing/refresh modes and select the initial supported mode.
- [x] Select containerized CPC and single-host broker with persistent SQLite and
  publication file locks. Multi-host replicas are explicitly unsupported.
- [x] Implement immutable identity mappings and use/publish/maintain grants.
- [x] Implement broker-only managed-identity Key Vault access and versioned publication.
- [x] Implement conflict control, idempotency, interrupted-operation recovery,
  server-side validation, and redacted auditing.
- [x] Implement local change detection, approved post-login publication, metadata
  polling, and safe credential installation.
- [x] Implement CPC scheduling, exclusive supported refresh, and login-required alerts.
- [x] Add Profiles synchronization controls/status and administrator visibility.
- [x] Add declared container tests for concurrency/isolation/failure handling,
  HTTPS/JWT, Azure SDK boundaries, CPC rotation, local dirty/logout protection,
  launcher leases, and agent lifecycle. Existing setup and launcher suites passed.
- [ ] Complete live managed-identity Key Vault deployment/provider-mode QA.
- [ ] Record v1.6 release evidence and explicitly disable unsupported modes.

## Implementation boundaries

Broker/client/CPC code is implemented on `feature/profile-onboarding`. The generic
OAuth introspection adapter requires explicitly compatible provider endpoints;
real Claude/Codex/OpenCode subscription-mode validation is not established by
fictional fixtures. Example profiles remain disabled. No real credentials were
accessed, synchronized, or deployed during implementation.

The workstation agent is an opt-in persistent session process, not an OS boot
service. Authentication-error checks are explicit; arbitrary CLI work is not
automatically replayed. See the [runbook](../../docs/company-credential-sync.md).

## Verification on Raven/Linux, 2026-10-17

- Declared `credential-sync` container: **30 tests passed, zero skipped**. This
  includes real local HTTPS and signed identity checks, Azure SDK boundary mocks,
  publication concurrency/recovery, two clients, CPC refresh/alerts, native launch
  leases, background agent start/stop, and the baked production factory smoke test.
- All **21** existing Workstation Setup regression suites passed. The expanded
  Profiles (**13**) and account (**14**) cases also passed, including a real PTY
  visit to the company sync menu without enabling access or touching credentials.
- All **12** Claude/Codex launcher and shared-MCP suites passed.
- Declared `tools-runtime` acceptance passed: sync status works without native
  Python/jq/Git/curl, native callbacks and deadlines passed, immediate TUI startup
  and Vault fixture flows passed, Profiles cancel/back preserved a queued bench,
  and test-created containers/networks were cleaned up.
- Python compilation, Bash syntax, YAML/JSON parsing, documentation links and
  `git diff --check` passed. No real provider tokens or cloud resources were used.
