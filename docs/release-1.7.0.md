# v1.7 — user/device registration and directional SSH trust

Status: feature implementation and fixture validation; not a release candidate.
Development branch: `feature/1.7-device-trust`. v1.6 is unchanged. The inherited
VERSION/source lock is not a v1.7 freeze or publication.

Profiles gains a Devices inventory per personal/company context. Configured
sign-in registers the current user's device, dedicated public login key and local
server public key. Registration grants no SSH access. Destination-approved
connections are directional and isolated by verified OIDC owner/context.

Public inventory and hashed device capabilities use the authenticated broker's
durable registry. The workstation renews ten-minute managed SSH leases every two
minutes. Sign-out, retirement and revocation stop managed access; unrelated keys
and existing sessions are preserved. Strict server-key pinning and dedicated
login identities are used for Connect. No new cloud infrastructure or vault
permissions are deployed by this source change.

See [Devices](device-trust.md) for setup, operation, limitations and acceptance,
and [specification](../specs/028-device-trust/spec.md) for the trust model.

Before release: validate real HTTPS/OIDC deployment, separate owners and company
contexts, Raven↔Eagle directional approval/revocation, session refresh and reboot,
and every claimed client platform. Company membership grants no implicit SSH.

## Guided setup wizard

The 1.7 scope also includes the six-step setup wizard: Workstation → Benches →
Harness → Tools → Profiles → Review. This is a breaking interaction change:
**Enter opens Review; only Enter on Review applies** the component queue.
Workstation and Profiles rows still run their explicit actions immediately.

Benches are browsed by category with responsive lists and scrolling About text.
The catalog now offers all twelve locked benches, adding **goBench**, **rustBench**
and **365Bench**. Safe catalog lookups support the digit-leading name; unresolved
paths fail closed. The existing setup modes and private selection format remain.

Bench copy approval in the running preview, CI and real-host QA remain release
gates. See [the wizard verification handoff](../specs/029-setup-guided-wizard/quickstart.md).

## Kimi and GLM profile credentials — planned addition

Brett requested this 1.7 scope on 2026-10-23. It is specified in
[feature 031](../specs/031-kimi-glm-profile-credentials/spec.md), with runtime
implementation still pending. Kimi gains named isolated accounts, a pkimi
launcher and persistent profile mounts; GLM retains pglm/pzai. Both gain qualified
credential recovery and company-sync adapters, with accurate access/freshness
status and preservation of unrelated accounts and provider records.

Initial Kimi compatibility testing targets CLI 2.3.1 and entitled k3.1-pro use;
installing a CLI does not grant model access. Remote OAuth custody/sharing and
CPC refresh remain disabled until qualified per mode. Existing release gates,
including exact-head native/live acceptance, remain required. See the
[planned user guide](kimi-glm-profile-credentials.md) and
[implementation tasks](../specs/031-kimi-glm-profile-credentials/tasks.md).

All Codex/Astra review revisions were approved by Brett on 2026-10-24; runtime
implementation remains pending. Deliver local profiles/login/persistence (M1),
qualified personal retrieval (M2), then independently qualified company sync
(M3). Minimum M2 acceptance names Kimi Platform API-key and GLM Coding Plan
API-key Azure Key Vault round trips on every claimed native Linux/WSL runtime;
zero enabled retrieval modes is an explicitly deferred M2, not success.

The revised contract requires interactive native terminal handoff, selected-
record TOML/JSON merge/sync, stable company control-plane paths, immutable owned
profile binding, separate authentication/sync-policy fields, 032 installer/update
qualification and real boundary/image-packaging tests. K3.1 Pro max effort is
explicitly configured/verified; its observed vendor default is high. See the
[approved review record](../specs/031-kimi-glm-profile-credentials/review-2026-10-24.md).
