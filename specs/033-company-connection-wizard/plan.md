# Implementation plan

Use the existing Python/Bash tooling, profile_tui and native callback. Add a
company_connection module with pure descriptor/discovery/admin-guidance helpers
and injected prompt/selection/request/write/native operations for meaningful
fixture tests. Bound enrollment to issuer/clientId and optional broker/company
metadata; reject secret or unknown fields instead of projecting them silently.

Integrate at setup-workbenches-account.main only when configuration is absent.
Reuse existing login and session persistence unchanged. Delegate direct Profiles
Import enrollment to the shared parser/review path and supply selected company
name through its isolated child environment. Review settings before mutation;
save and sign-in are separate steps so decline/back preserves prior files.

Reuse Keycloak same-origin device-flow validation and reject unsupported metadata
without widening trust. Offer explicit native browser/clipboard actions and
printed fallback. Export uses atomic exclusive private-file publication and
refuses symlink/occupied paths. No new packages or container images are needed.

Develop and test in linked 033 worktree. Reconcile final v1.6.1 metadata before
landing; development VERSION/lock are 1.6.2-dev.1 with existing source pins.
Use declared Tools/test containers and fake HTTP/native services, not production
credentials. New suite joins ordinary Workstation Setup regression and release
setup manifest; existing release-line cases are unchanged except this additive
setup test. No v1.7 changes or release automation bypass belongs to this feature.

Constitution remains the inherited template; global workflow and explicit scope,
safe URL/storage, no token export, cancellation and non-secret diagnostics gates
apply. The sole executable checklist is tasks.md.
