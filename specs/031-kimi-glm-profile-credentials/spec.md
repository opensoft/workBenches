# Feature Specification: Kimi and GLM profile credentials

**Feature Branch**: `031-kimi-glm-profile-credentials`  
**Created**: 2026-10-23  
**Target**: workBenches 1.7  
**Status**: Specified; implementation not started  
**Input**: Brett: "spec this and document this to add to 1.7" following the
review of Kimi isolation, persistent mounts and Kimi/GLM credential recovery gaps.

**Governance**: [OpenSpec proposal](../../openspec/changes/add-kimi-glm-profile-credentials/proposal.md).
Depends on [029 wizard](../029-setup-guided-wizard/spec.md), reuses
[026 Profiles](../026-profile-onboarding/spec.md) and
[027 company sync](../027-company-credential-sync/spec.md). It does not modify
1.6 release scope or assert that this functionality is already implemented.

## User Scenarios & Testing

### US1 — Separate provider accounts (P1)

From an identity's AI accounts action, create and name multiple Kimi or GLM
profiles, sign in to the intended account, and launch one without replacing
another identity's credentials. Independent test: personal plus two company
accounts, including two identities in the same company, retain distinct homes.

1. Given a configured identity, adding Kimi offers native OAuth or API-key sign-in;
   GLM offers the explicit Z.AI Coding Plan or standard API-key mode.
2. Repeating setup reuses the same profile; a different identity gets a distinct
   profile. Cancel preserves completed steps, other accounts and queued installs.
3. Status distinguishes local presence from verified access; unsupported verification
   is shown as unverified, not authenticated.

### US2 — Keep accounts through bench lifecycle (P1)

Sign in once per selected profile, then restart/recreate its bench or reboot the
host without losing its local home. Independent test: same persisted home and
credential bytes before/after lifecycle operations; actual provider access checked
separately. A revoked or expired login still requires recovery or sign-in.

### US3 — Recover only the chosen credential (P1)

Explicitly enroll a supported credential mode with an existing recovery store,
then recover it on an authorized replacement workstation. Independent test:
restore one profile, retain unrelated OpenCode providers and Kimi settings, refuse
an existing conflicting credential, and reject another profile/tenant's payload.

### US4 — Synchronize approved company credentials (P2)

Company sign-in discovers only granted Kimi/GLM profiles. Approved publication and
rotation produce a new authoritative version that another authorized workstation
can install. Independent test: use-only versus publisher/maintainer permissions,
two tenants, concurrent updates, outages and interrupted writes. Local Kimi OAuth
works without enabling unqualified company OAuth sharing.

## Functional Requirements

- **FR-001**: Add normalized provider `kimi-code` and `kimi-code-profiles.json` to metadata composition, identity-scoped setup and dashboard. Preserve `glm` and existing manifests, profile paths, aliases and credentials. Metadata contains identifiers and references, never keys/tokens.
- **FR-002**: Provide `pkimi` account selection and list/login/status/logout/run/path actions with a distinct `KIMI_CODE_HOME` per profile. Keep `pglm`/`pzai` with isolated OpenCode XDG roots. Launches must not silently inherit a conflicting account credential from ambient provider variables.
- **FR-003**: Use vendor sign-in under the selected profile's environment. Browser/device approval is native and cancellable through Tools; secrets are not CLI arguments, diagnostics, metadata, or shell history. Identity/company/GitHub sign-in is separate from provider authentication.
- **FR-004**: Show configured, credential-present, access-verified (timestamp), login-required/denied, check-unavailable and unsupported-mode facts separately. Profile email alone is not verification. Do not display key/token contents or run paid generation as a status probe.
- **FR-005**: Persist Kimi and GLM homes using validated shared bench mounts with correct ownership, including native/WSL and Wave-created benches. Restart, recreation, reboot and uninstall preserve them by default; no credentials enter image layers.
- **FR-006**: Treat existing default Kimi homes and legacy Python kimi-cli as separate inputs. Detect the actual client/package; offer an explicit reviewed import only. Do not overwrite an occupied destination or silently migrate active sessions, other identities, global defaults or unsupported formats.
- **FR-007**: Add versioned adapters for selected Kimi API-key/native-OAuth and GLM API-key modes. Maintain explicit per-mode local-login, verification, recovery, sharing and refresh eligibility. Local-login support does not imply eligibility for remote custody or company sharing.
- **FR-008**: Export the minimum approved credential projection and restore it atomically with strict size/type/path/ownership checks. Preserve unrelated Kimi config and OpenCode provider records. Default restore refuses to replace an existing usable/conflicting local credential; explicit replacement is per profile with review/backup.
- **FR-009**: Integrate qualified modes with the existing supported recovery stores, manifests, enrollment and status. Missing/locked/offline stores retain the last usable local credential; retry is safe and does not turn failure into success. No new secret-store service is introduced.
- **FR-010**: Extend company broker mode allowlists and profile bindings additively. Enforce existing issuer/subject/tenant authority and separate use/publish/maintain grants on every operation. Provider-account binding must be qualified using supported evidence; a user-entered email or path is insufficient.
- **FR-011**: Reuse durable expected-version/idempotency publication, launch/startup/resume/hourly sync and local writer coordination for managed profiles. Reconcile interrupted exports/installs without loops or loss of an unpublished local login. Logout/deletion/partial files do not publish revocation or an empty secret.
- **FR-012**: CPC checks only approved modes and uses existing scheduling/coordination. API keys are not OAuth-refreshable. Kimi OAuth automated refresh/shared use remains disabled until its refresh/rotation and concurrent-writer model is qualified. Ambiguous refresh is not blindly replayed; interactive reauthentication remains available.
- **FR-013**: Keep Kimi client version, model ID, reasoning effort and account entitlement separate. Initial compatibility testing targets CLI 2.3.1 and `k3.1-pro`, with thinking enabled and effort `max`; preserve existing choices and offer only entitled models. An unavailable request is explicit, with no silent model substitution. Model changes start a new session.
- **FR-014**: Profiles actions retain wizard focus, pending component selections and narrow-terminal behavior. The Harness installation/manual classification and selection JSON do not change merely from adding credentials support. CLI missing/unsupported gets an actionable prerequisite state.
- **FR-015**: Reuse existing 1.7 release gates and add provider-specific fixture and attended live acceptance. No test copies production accounts or authorizes cloud provisioning. Unsupported modes remain visible as unsupported; no tested mode's evidence qualifies another.

## Edge Cases

- Two identities use the same display name/email but different provider accounts;
  repeated setup must remain idempotent without merging their credentials.
- Default Kimi home, legacy CLI, symlinked or traversal paths, unknown client version,
  missing mounts, mixed-provider auth.json, ambient API keys and partial writes.
- Key expiry/revocation, MFA cancellation, vault outage, entitlement changes,
  tenant denial, concurrent login/publication and crash between install and baseline.
- Reboot preserves storage but cannot restore a killed process or a provider-revoked
  login; resuming conversation/session data is subject to the native client's support.

## Key Entities

Provider profile (provider, immutable local ID, identity/scope, safe profilePath,
auth mode, optional model/effort); provider capability record (client range and
operation eligibility); credential projection (versioned secret payload);
credential binding (authorized profile/account/tenant and secret reference);
local observation (presence, verification timestamp, sync state and version).
See the [contract](contracts/provider-credentials.md).

## Success Criteria

- **SC-001**: Personal plus two company profiles for each provider pass isolation,
  rerun and cancellation tests, with no credential changes to unrelated profiles.
- **SC-002**: Restart/recreate/reboot preserve selected homes in every claimed
  platform; missing/expired credentials never produce a false verified state.
- **SC-003**: Every enabled remote mode passes scoped round-trip recovery,
  denied-tenant, mixed-provider preservation, conflict, outage and crash tests.
- **SC-004**: Secret canaries never appear in captured logs, metadata, arguments,
  images or release artifacts; unsupported OAuth operations remain disabled.
- **SC-005**: Existing setup, identity, recovery and company-sync regression suites
  remain green; live evidence records exact client version/mode/platform.

## Decisions and Assumptions

Scope is specified for 1.7, not an instruction to implement or publish now.
Existing broker and recovery infrastructure are reused where deployed. Native Kimi
OAuth is first-class local login; its remote eligibility is a qualification gate,
not an assumption that a subscription token can be shared. No new identity or
secret authority is inferred. The implementation task list owns remaining work.
