# v1.6 implementation and verification

- [x] Document three pages, personal-first onboarding, GitHub verification,
  repeated company creation, enrollment, compatibility, and integration boundaries.
- [x] Implement validated private metadata, stable company identities, and a
  lock against concurrent interactive profile changes.
- [x] Implement verified GitHub metadata links with explicit account confirmation.
- [x] Implement independent company sign-in configuration/sessions, imported or
  entered manually, without inheriting another company's server overrides.
- [x] Add Profiles page navigation/actions and cached background summary while
  preserving queued component selections and immediate startup.
- [x] Prefill identity-specific AI onboarding and preserve existing provider profiles.
- [x] Add the new suite to Workstation Setup CI path filters and regression job.
- [x] All 21 Workstation Setup regression suites passed on Raven/Linux.
- [x] All 12 focused profile checks passed, including personal plus two companies,
  cancellation/resume, scoped sign-in roots, verified GitHub metadata, enrollment,
  repeated AI additions, and navigation retaining queued selections.
- [x] Profile rendering checked at 36/60/80/100 columns without discovery; rendered
  80-column preview visually reviewed. Bash syntax, Python compilation, YAML
  parsing, and diff whitespace checks passed.
- [x] Declared Tools runtime acceptance passed on Raven/Linux, 2026-10-17,
  including Profiles open/cancel/back and queued bench preservation. The live
  run found and verified a fix for gating Profiles on optional background
  inventory instead of required-service readiness. Vault Install/Connect/
  Ctrl+C/sign-in/sign-out, health/restart/isolation, native callbacks, minimal
  host PATH, and immediate startup also passed. Account responses were fixtures;
  only test-created containers/networks were removed.

## Live QA still required before v1.6 release

- [ ] Exercise a real GitHub browser authorization through the new profile action
  and verify linking/reuse of personal and company GitHub identities.
- [ ] Exercise two real company identity-server connections through the new
  per-company storage, including independent sign-out/reconnect.
- [ ] Windows/WSL live acceptance of Profiles; macOS coverage must be stated from
  actual evidence before claiming support.

Fixtures do not establish real provider approval. Earlier v1.5 Keycloak QA used
the legacy workstation account and is not evidence for the new company flow.
Project association/default selection and automatic credential routing remain
separate follow-up integration work, as recorded in the specification.


## Multiple identities follow-up

- [x] Private version-2 migration/backup and stable company session roots.
- [x] Multiple personal and company email identities and explicit defaults.
- [x] Shared GitHub account library, per-identity links/defaults, scoped unlink.
- [x] Native gh multi-account discovery/verification without active-account switch.
- [x] Isolated native gh device sign-in with browser/code/clipboard/cancel controls.
- [x] Keyboard tree/detail manager, narrow-terminal layout, and PTY regressions.
- [x] Complete declared Tools-runtime and broker/client regression validation.
- [ ] Real GitHub browser and Linux/Windows workstation acceptance.
