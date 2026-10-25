# Company connection wizard

Feature 033 · target v1.6.2 · issue [#213](https://github.com/opensoft/workBenches/issues/213).
Authority: Brett Heap, 2026-10-24: log the company connection problem for 1.6.2,
fully specify and implement it after preserving tested 1.6.1 behavior.
Governance: [proposal](../../openspec/changes/company-connection-wizard/proposal.md).

## Users and outcomes

Employees import administrator setup once, review it and sign in without needing
to understand application registration. Administrators receive guided registration
settings, enter the actual issuer/client ID and can share a non-secret enrollment
descriptor. Returning users retain the existing configured sign-in flow.

## Requirements

- **FR-001**: Missing company configuration opens a Profiles-style wizard offering administrator enrollment import first, registration guidance, existing registration and Back. Existing configured sign-in does not re-enroll or overwrite settings. An explicit R Connection setup action can reopen the wizard without starting sign-in, including after an invalid client registration.
- **FR-002**: Explain that Client ID is the application's registration at this provider, not the user/email/company ID. Registration is normally once per organization; the ID can be provider-generated or administrator-chosen. Suggested names are examples, not universally registered IDs.
- **FR-003**: Guide current Keycloak-compatible public-client device authorization: client authentication off/no embedded secret, device grant on, required openid/profile/email, optional offline_access only for opted-in sync. Do not claim support for arbitrary OIDC providers or implement automatic registration/admin login.
- **FR-004**: Validate issuer equality and same-origin HTTPS device/token/userinfo endpoints via discovery before confirmation. Discovery reports registration unverified; actual device authorization can subsequently validate it. Never perform a paid/cloud operation or login as a discovery check.
- **FR-005**: Import a bounded local JSON file or administrator HTTPS URL without redirects; validate structure, URLs, strings and allowlisted non-secret fields. Review selected company/issuer/client/optional broker and organization before saving. Save/import alone does not sign in or grant broker/vault/provider access.
- **FR-006**: Export a reusable allowlisted descriptor with private atomic storage and no overwritten/symlinked target. Never export sessions, tokens, client secrets, unknown input fields or other companies' configuration. Preserve old settings until confirmed.
- **FR-007**: Explicit browser/clipboard actions use the native Tools boundary and safe argument arrays; show usable manual instructions if unavailable. Derive an admin URL only from a validated Keycloak realm issuer; never send credentials or create applications.
- **FR-008**: Back returns within the wizard or to Profiles. Q/EOF/interrupt preserve existing cancellation statuses, saved identities, other companies' sessions and queued software selections. Failed discovery/import does not replace previous settings.
- **FR-009**: Share parser/review logic with the existing direct Import enrollment action; keep all existing configured login, verified-email and company environment-isolation contracts. No source pins or 1.6.1 runtime worktree is changed.
- **FR-010**: Meaningful fixtures cover employee/admin/existing routes, import/export round trips, device discovery versus registration, failures/unsupported states, explicit native browser/clipboard fallback, cancellation, company isolation and actual Profiles integration. Add the suite to ordinary setup CI and existing 1.6 release setup cases.

## Acceptance

1. Empty configuration shows explained choices rather than unexplained realm/client prompts.
2. An administrator can review public-client/device settings, open/copy guidance,
   enter the actual application identity, validate discovery, confirm and export.
3. An employee imports that exported descriptor, confirms the correct company
   binding and reaches existing device sign-in; no registration occurs in code.
4. Malformed/redirected/secret-bearing/oversize input and cross-origin discovery
   fail without writes or token requests. Discovery alone never says signed in.
5. Back and cancel leave identity/session/queue state intact, including when a
   second company already has settings. Configured login remains unchanged.
6. Unit/integration and affected account/Profiles/setup suites pass in declared
   containers; native Tools behavior is fixture-tested without production sign-in.

## Boundaries

This is onboarding guidance for existing supported authentication, not a new
identity-provider adapter or registration service. Company credential grants and
AI authentication remain independent. Live provider configuration/approval is an
administrator action outside fixture execution. v1.6.2 publication is separate.
