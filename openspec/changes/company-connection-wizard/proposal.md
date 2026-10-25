# Company connection onboarding for v1.6.2

Authority: Brett Heap requested release of tested v1.6.1 unchanged, logging this
onboarding defect for v1.6.2, then full specification and implementation on
2026-10-24. Governing issue: https://github.com/opensoft/workBenches/issues/213.
The user instruction authorizes this bounded onboarding fix and its tests.

Company login currently prompts immediately for issuer URL and Client ID. It
does not adequately explain administrator application registration or offer a
guided first-run connection route. Client ID identifies the application registered
with the organization's provider, not a user or company identifier.

Add a Profiles-style connection wizard: administrator enrollment import first,
administrator registration guidance, and an existing-registration path. Review
and validate discovery, optionally export non-secret enrollment settings, and
reuse existing public-client device login. Preserve preconfigured sign-in and
all company/personal/session isolation and cancellation behavior.

Scope is existing Keycloak-compatible, same-origin HTTPS device-flow support.
Do not claim arbitrary provider support, automatically register applications,
collect administrator credentials/client secrets, weaken endpoint validation,
change broker grants or add a new identity/credential authority. Registration
remains a provider-admin action performed once per organization. No production
login or cloud provisioning is authorized by fixture verification.

One implementation feature owns work: `specs/033-company-connection-wizard/`.
Its tasks.md is the sole executable checklist. v1.6.1 publication and unrelated
v1.7 worktrees remain separate. Do not publish a v1.6.2 release in this change.
