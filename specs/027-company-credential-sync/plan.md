# Implementation plan — target v1.6.0

1. Validate provider modes and choose the CPC runtime and broker hosting model.
   Establish whether clients support independent sessions or broker-exclusive
   refresh before enabling shared OAuth credentials.
2. Define immutable company identity mappings and separate use/publish/maintain
   grants. Implement broker authorization and narrowly scoped Key Vault access.
3. Implement transactional version metadata, idempotent publication, and conflict
   handling before adding workstation uploads or scheduled refresh.
4. Add opt-in company profile synchronization, provider change-detection adapters,
   post-login publication, startup/launch/hourly metadata polling, and safe installs.
5. Add the CPC weekly health sweep and expiry-driven supported refresh schedules,
   using the same broker serialization and publication path.
6. Show sync state, conflicts, last check, and login-required state in Profiles.
   Validate one supported mode end to end, then enable others individually.
7. Complete isolation, concurrency, failure recovery, live provider, and platform
   acceptance. Update release evidence before inclusion in v1.6.

Event-driven client notifications are optional after the polling path is reliable.
This plan is not an instruction to deploy cloud resources or access real tokens.
