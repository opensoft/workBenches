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
