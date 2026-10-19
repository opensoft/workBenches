# v1.6.0 — identity and company credential workflows

Status: scope frozen for release candidate **v1.6.0-rc.1** on 2026-10-19,
at Brett's request. This is not a stable release or a completed release gate.
The candidate includes profile-onboarding head
`edefc67c340603a783876cdf1b424b3d9f1093db` and stable fixes through main
`5880c09bf019f3166316d957e8fa26cd98c2ed54`.

The `release/1.6.0` branch accepts only candidate fixes and validation evidence;
new feature scope continues separately. All 12 existing repository source pins
remain unchanged in `config/release-lock.json`. See the
[candidate notes](release-1.6.0-rc.1.md) for limitations and the remaining gates.
Published candidate tags are immutable; further candidates receive new tags.
v1.5.0 remains the stable release until a separately validated v1.6.0 is published.

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


## Candidate follow-up: openRepoTools #237 / workBenches #107

The candidate now consumes the complete openRepoTools payload at upstream merge
`586dea25e073caadc33002e0157376788678dee0` (PR #247), taken with the vendored-copy
updater. This includes the two additional installables `lanes-index` and
`lane-worktrees`; host preflight and the dev-image COPY/chmod set match all 17
upstream bin files. Grouped COPY instructions preserve the existing image-layer
budget rather than adding two layers. The earlier upstream fixes in that commit's ancestry are
included as a consistent pinned snapshot, not hand-edited vendor files.

Fresh installation defers the hook pair until its linked target answers guard.
An old broken prompt guard is removed while unrelated settings/hooks are kept.
Workspace initialization reconciles the pair, including a rerun after an
interruption. Container startup invokes the same upstream installer again after
successful workspace linking so that the first startup completes deferred hooks.
It never retries an initial installer refusal or edits hook JSON itself.

This is a post-rc.1 candidate fix. The existing tag remains unchanged; a further
candidate needs a new version/tag and exact-commit release validation.
