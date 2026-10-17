# v1.6.0 — planned identity and company credential workflows

Status: development target, not a published release or completed release scope.
v1.5 remains focused on reliable workstation setup and its existing release gates.

| Feature | Status |
| --- | --- |
| Personal email, verified GitHub linking, multiple company profiles, third TUI page | Implemented on `feature/profile-onboarding`; live provider/platform QA pending |
| Company sign-in → authorized AI profile discovery and recovery | Designed; broker integration not implemented |
| Approved local login changes → versioned Key Vault updates | Designed; not implemented |
| Startup/launch/hourly workstation synchronization | Designed; not implemented |
| CPC weekly profile health sweep and expiry-driven supported refreshes | Designed; runtime and implementation pending |

See [Profiles](profiles.md), the
[profile onboarding specification](../specs/026-profile-onboarding/spec.md), and
the [company credential synchronization specification](../specs/027-company-credential-sync/spec.md).

The company flow uses administrator-controlled profile grants. Entra/Keycloak
establish identity; the broker enforces profile use/publication/maintenance rights.
Only the server-side broker has ordinary application access to Key Vault. The
CPC and workstations call the broker, not the vault directly.

Hourly metadata checks are the default background synchronization interval, with
additional startup/resume, launch, and authentication-error checks. CPC performs
a weekly health sweep, but actual token refresh schedules follow each provider's
expiry and rotation requirements. Neither cadence guarantees that a copied OAuth
session is safe to share; eligibility must be established per provider mode.

Before shipping the credential features, validate at least one provider mode end
to end with real test profiles, including tenant isolation, publication grants,
concurrent update/refresh conflicts, offline recovery, and login-required states.
Unsupported modes remain disabled. New provider modes can follow in later
compatible feature releases; unresolved broker security must not be bypassed to
meet a version target.

Existing Key Vault direct-user recovery remains a separate compatibility path;
company-managed broker mode must not silently fall back to direct user vault
access when broker authorization fails. Existing credentials are not migrated
or published automatically by this documentation or by Profiles onboarding.
