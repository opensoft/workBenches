# Tasks

- [x] Implement strict version-aware manifest and commit-bound evidence validator.
- [x] Reuse regression/container commands for ordinary CI and release validation.
- [x] Add release orchestration, prerequisite checks and publication guard.
- [x] Add native/live worker contracts and isolated runner setup instructions.
- [x] Test tampering, missing/skipped/stale evidence, failed cleanup and publication.
- [ ] Enable workflows on GitHub and configure dedicated runner environments.
- [ ] Provision QA accounts, native VMs and approved live provider mode.

Implemented checks: 26 framework tests, workflow syntax validation, and 11 hosted
suites against v1.6.0-rc.3 passed locally. The fresh-install rehearsal is incomplete
(stalled at Vault readiness); it is not accepted as passing evidence.

Dedicated GitHub environments were created with QA disabled. Workflow activation,
protected runner provisioning, live adapters and QA identities remain pending.
