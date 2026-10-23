# Kimi and GLM profile credentials for workBenches 1.7

## Why

Kimi Code is installed by the shared image recipe but has no composed profile
manifest, launcher, standard persistent bench mount or credential recovery
adapter. GLM has isolated OpenCode profile launchers, but its credentials are
outside the recovery and company-sync adapters, and dashboard status is incomplete.
Neither identity sign-in nor installing a CLI supplies provider credentials.

## Authority and status

Brett requested: "spec this and document this to add to 1.7" on 2026-10-23,
following the review of Kimi and GLM credential gaps. This authorizes this
specification and documentation. Runtime implementation, live credentials and
provider-mode qualification are not completed by this change.

The reviewed source baseline is wizard branch commit
`b8b16075a5b4f58eb6f6d307aa66af2c01e883f6`. The target is 1.7, with no 1.6
runtime or release changes. This is a separate feature because it expands
credential and container contracts beyond feature 029's UI scope.

## What changes

- First-class Kimi Code accounts in Profiles, metadata composition and the
  credential dashboard, with a `pkimi` launcher and isolated `KIMI_CODE_HOME`.
- Retain `pglm`/`pzai` and existing GLM paths; add accurate presence, verification,
  recovery and company-sync support for explicitly selected GLM credential modes.
- Persist account homes across bench restart/recreation and host reboot using
  the existing shared-home mount mechanism; separate profiles may run concurrently.
- Add provider-scoped credential export/import adapters to existing recovery
  stores and the authorized company broker, with safe retries and version conflicts.
- Separate local credential presence, verified provider access, model entitlement
  and broker freshness in status. Describe K3.1 Pro selection without assuming
  that CLI installation or an account email grants access.
- Keep OAuth refresh and company sharing disabled per mode until supported
  provider behavior and deployment authorization are established. API keys rotate
  through their provider or administrator; CPC does not invent a refresh endpoint.

## Scope and impact

New capability: `provider-profile-credentials`. Existing identity metadata,
company grants, use/publish/maintain separation and secret-store authority remain.
Schemas gain additive provider/mode support and explicit version handling; old
Claude/Codex/Pi/OmniRoute behavior and GLM profile paths remain compatible.
The Harness installation allowlist and manual catalog entries do not change
merely because a credential adapter becomes available.

Affected areas are Profiles composition, launchers, dashboard, native callbacks,
bench-home/mount generation, recovery, broker/CPC provider modes and 1.7 acceptance.
No runtime code, credential values, cloud deployment, source pins or release
tags change in this specification commit.

## Handoff

Exactly one implementation feature owns this work:
[`specs/031-kimi-glm-profile-credentials`](../../../specs/031-kimi-glm-profile-credentials/).
Its `tasks.md` is the sole implementation checklist. Integration follows feature
029 on the 1.7 line; this change remains open until implementation and its
required acceptance evidence land. See `design.md` and the capability delta.
