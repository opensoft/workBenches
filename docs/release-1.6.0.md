# v1.6.0 — planned identity and company credential workflows

Status: development target, not a published release or completed release scope.
v1.5 remains focused on reliable workstation setup and its existing release gates.

| Feature | Status |
| --- | --- |
| Multiple personal/company email identities, reusable verified GitHub accounts, keyboard Profiles manager | Implemented on `feature/profile-onboarding`; multi-account migration, PTY, and native Tools callback tests passed; real browser/platform QA pending |
| Company sign-in → authorized AI profile discovery and recovery | Broker/client implemented; live managed-identity/provider QA pending |
| Approved local login changes → versioned Key Vault updates | Publication, conflict handling, and recovery implemented; examples disabled |
| Startup/launch/hourly workstation synchronization | Opt-in agent and managed launcher hooks implemented; platform QA pending |
| CPC weekly profile health sweep and expiry-driven supported refreshes | Container worker, broker scheduling, and attention alerts implemented; live provider QA pending |

See [Profiles](profiles.md), the
[profile onboarding specification](../specs/026-profile-onboarding/spec.md), and
the [company credential synchronization specification](../specs/027-company-credential-sync/spec.md).
Deployment/configuration instructions are in [Company credential synchronization](company-credential-sync.md).

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
access when broker authorization fails. Existing credentials are not migrated or
published merely by opening Profiles; company sync and managed paths require
explicit opt-in.
