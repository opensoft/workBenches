# Company credential synchronization — target v1.6.0

- [x] Record the proposed architecture, version target, and security boundaries.
- [x] Include CPC weekly health checks and expiry-driven refresh scheduling.
- [ ] Validate provider sharing/refresh modes and select the initial supported mode.
- [ ] Select CPC runtime, broker hosting, and transactional metadata storage.
- [ ] Implement immutable identity mappings and use/publish/maintain grants.
- [ ] Implement broker-only Key Vault access and versioned credential publication.
- [ ] Implement conflict control, idempotency, interrupted-operation recovery,
  server-side validation, and redacted auditing.
- [ ] Implement local change detection, approved post-login publication, metadata
  polling, and safe credential installation.
- [ ] Implement CPC scheduling, exclusive supported refresh, and login-required alerts.
- [ ] Add Profiles synchronization controls/status and administrator visibility.
- [ ] Complete automated concurrency/isolation/failure tests and live provider QA.
- [ ] Record v1.6 release evidence and explicitly disable unsupported modes.

No broker, synchronization agent, or CPC worker is implemented by this design.
